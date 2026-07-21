<!-- Synced from rms-central-command/docs/documentation.md. Edit there, then re-run scripts/sync-docs.sh -->

# rms-central-command Documentation

## 1. Purpose

`rms-central-command` is the orchestration and monitoring control plane for RMS
data services.

It provides:

- ordered, reusable service pipelines called **packages**;
- cron-based scheduling in a configurable timezone;
- manual package execution from the CLI or dashboard;
- package and step run history in PostgreSQL;
- retained stdout and stderr tails for troubleshooting;
- email alerts for failed or partially successful packages;
- optional daily summary emails;
- a localhost FastAPI dashboard for package, service, database, and run status;
- database endpoint discovery and lightweight TCP reachability checks.

Central command does not import or rewrite the business logic of the services it
orchestrates. Each package step launches the target service as a subprocess,
using that service's own:

- installation directory;
- Python virtual environment;
- entry script;
- command-line interface;
- `.env` file;
- database credentials and application configuration.

This separation means every service remains independently runnable and can be
restored to its former scheduler if central orchestration is rolled back.

## 2. High-Level Architecture

The runtime flow is:

1. `src/main.py` loads the CLI command and the central `.env`.
2. `Registry` loads service definitions from `config/services.yaml`.
3. `Registry` loads package definitions from `config/packages/*.yaml`.
4. A package is selected manually or triggered by APScheduler.
5. The executor creates a package run in PostgreSQL.
6. Package steps run sequentially as child processes.
7. Each step runs from the target service root with its own Python and
   environment.
8. Exit status and retained output tails are written to the run-history tables.
9. Failure behavior determines whether later steps run or are skipped.
10. The package receives a final `success`, `failed`, or `partial` status.
11. A failure notification is sent when configured.
12. The dashboard reads the same history and configuration to display status.

The main components are:

| Component | Responsibility |
|---|---|
| `src/main.py` | CLI and dashboard startup |
| `src/core/config_loader.py` | YAML loading and environment substitution |
| `src/core/registry.py` | Service and package discovery |
| `src/core/executor.py` | Sequential subprocess execution |
| `src/core/scheduler.py` | Cron registration and package triggering |
| `src/core/runstore.py` | Package and step history persistence |
| `src/core/db.py` | PostgreSQL access for the history store |
| `src/core/placeholders.py` | Runtime date placeholder resolution |
| `src/core/notifier.py` | Failure alerts and daily summaries |
| `src/core/metrics_lookup.py` | Best-effort records-updated lookup |
| `src/web/` | FastAPI dashboard, templates, and database health checks |

## 3. Repository Layout

```text
rms-central-command/
├── config/
│   ├── connections.yaml
│   ├── services.yaml
│   ├── settings.yaml
│   └── packages/
│       ├── live_package.yaml
│       ├── core_package.yaml
│       ├── off_peak_package.yaml
│       ├── ai_off_peak_package.yaml
│       └── ai_insights_package.yaml
├── deployment/
│   ├── env.server.example
│   ├── MIGRATION.md
│   ├── orchestrator_schema.sql
│   └── rms-central-command.service
├── src/
│   ├── main.py
│   ├── core/
│   └── web/
├── .env.example
├── README.md
├── documentation.md
└── requirements.txt
```

## 4. Services

### Service Registry

Every orchestrated application must be registered under `services` in
`config/services.yaml`.

Example:

```yaml
services:
  rms-vehicle-review:
    root: ${RMS_CC_RMS_VEHICLE_REVIEW_ROOT:../rms-vehicle-review}
    entry: main.py
    job_style: subcommand
```

Supported service fields are:

| Field | Required | Meaning |
|---|---:|---|
| `root` | Yes | Service installation directory |
| `entry` | Yes | Python entry script relative to `root` |
| `job_style` | No | `positional` or `subcommand`; defaults to `subcommand` |
| `python` | No | Explicit Python interpreter path |
| `env_file` | No | Explicit service environment file |
| `list_cmd` | No | Job-listing arguments for positional services |
| `connections` | No | Config files inspected by the Databases panel |
| `legacy_tls_jobs` | No | Jobs that require the legacy OpenSSL environment |
| `legacy_tls` | No | OpenSSL config and module paths |

### Job Styles

Central command supports two CLI conventions.

#### Positional

The job name is the first positional argument:

```text
python <entry> <job>
```

Package syntax:

```yaml
- service: rmdb-etl
  job: sad_general_segment
```

This produces a command similar to:

```bash
/opt/rmdb-etl/venv/bin/python \
  /opt/rmdb-etl/src/main.py sad_general_segment
```

`--dry-run` is appended to positional steps when the package is run with the
central `--dry-run` option.

#### Subcommand

The package supplies the complete application arguments:

```yaml
- service: rms-ratings
  argv: ["daily", "--date", "{yesterday}"]
```

This produces a command similar to:

```bash
/opt/rms-ratings/venv/bin/python \
  /opt/rms-ratings/main.py daily --date 2026-07-16
```

Central command does not append `--dry-run` to subcommand services because
their CLI capabilities are not assumed to be uniform.

### Python Resolution

For each service, the interpreter is selected in this order:

1. explicit `python` from `services.yaml`;
2. `<root>/venv/bin/python`;
3. `<root>/.venv/bin/python`;
4. system `python3`.

Use `list-services` to verify the result. Falling back to `python3` usually
means that the service root or virtual environment is missing or incorrect.

### Service Environment

The child process starts with a copy of the central process environment. Values
from the target service's `.env` are then overlaid on it. The default file is:

```text
<service-root>/.env
```

An `env_file` setting can override this path.

The built-in service `.env` parser supports ordinary `KEY=value` lines,
optional `export`, comments, and simple quoted values. It is not a full shell
parser and does not perform shell expansion.

### Registered Services

The current registry includes:

- `rmdb-etl`
- `rmdb-analytics`
- `rms-ai-insights`
- `rms-attribute-refiner`
- `rms-individuals`
- `rms-ratings`
- `rms-revenue-extract`
- `rms-valuation-extract`
- `rms-valuation-flags`
- `rms-suppliers`
- `rms-vdf-mining`
- `rms-vehicle-annotate`
- `rms-vehicle-review`

Registration makes a service available to packages. It does not automatically
schedule or execute it.

## 5. Packages

A package is an ordered list of service commands stored in one YAML file under
`config/packages/`.

Example:

```yaml
package:
  name: example_package
  cron: "0 6 * * *"
  enabled: true
  on_failure: stop
  description: "Example daily pipeline."
  steps:
    - service: rmdb-etl
      job: sad_vehicles
    - service: rms-vehicle-annotate
      argv: ["run"]
```

### Package Fields

| Field | Required | Meaning |
|---|---:|---|
| `name` | No | Package name; defaults to the YAML filename |
| `cron` | No | Five-field cron expression; omitted means manual-only |
| `enabled` | No | Enables scheduled execution; defaults to `true` |
| `on_failure` | No | `stop` or `continue`; defaults to `stop` |
| `description` | No | Dashboard and operator description |
| `steps` | No | Ordered service steps |

A disabled package is excluded from the scheduler but can still be run
manually.

### Step Fields

| Field | Meaning |
|---|---|
| `service` | Name from `config/services.yaml` |
| `job` | Positional service job name |
| `argv` | Argument list for a subcommand service |
| `continue_on_error` | Continue after this step fails |
| `legacy_tls` | Per-step override for legacy TLS handling |

Use `job` for positional services and `argv` for subcommand services.

### Current Schedule

Cron expressions use `Asia/Colombo` by default.

| Package | Cron | Schedule | Purpose |
|---|---|---|---|
| `live_package` | `0 * * * *` | Hourly | AsyCuDa live declaration sync |
| `core_package` | `0 8,14,20 * * *` | 08:00, 14:00, 20:00 daily | Core ETL, analytics, suppliers, individuals, ratings, and valuation |
| `off_peak_package` | `0 22 * * *` | 22:00 daily | Nightly ETL, analytics, revenue extraction, and vehicle annotation |
| `ai_off_peak` | `0 23 * * *` | 23:00 daily | Deterministic and local-LLM vehicle review |
| `ai_insights_package` | `0 9 * * 2` | Tuesday 09:00 | Weekly revenue AI insights |

The YAML configuration is the authoritative source if this table and the live
deployment ever differ.

### Date Placeholders

Subcommand `argv` tokens can contain runtime placeholders:

| Placeholder | Value |
|---|---|
| `{today}` | Current date in scheduler timezone |
| `{yesterday}` | Previous date in scheduler timezone |
| `{date}` | Alias for `{yesterday}` |
| `{as_of}` | Alias for `{today}` |

Values are formatted as `YYYY-MM-DD` and resolved once at package startup.

Placeholders are applied only to subcommand `argv`; positional `job` names are
not transformed.

## 6. Execution Semantics

### Sequential Processing

Steps run one at a time in their listed order. A step is complete when its child
process exits or exceeds the configured timeout.

For each step, central command:

1. resolves its service, Python interpreter, entry script, and arguments;
2. resolves date placeholders;
3. creates a `running` step-history row;
4. loads the service environment;
5. sets any required legacy TLS variables;
6. runs the process with the service root as its working directory;
7. captures stdout and stderr;
8. maps exit code zero to `success` and nonzero to `failed`;
9. retains the configured tail of each output stream;
10. completes the step-history row.

### Output Capture

Child stdout and stderr are captured rather than streamed live through central
command. Operators see central start and completion logs while the child runs.
After completion, retained output tails are available in the run detail page.

The retention limit is controlled by:

```yaml
execution:
  output_tail_bytes: 4096
```

This setting limits characters in the current implementation despite the
`bytes` name.

The target service may still write its own log files according to its own
configuration.

### Step Timeout

The global timeout is:

```yaml
execution:
  step_timeout_seconds: ${RMS_CC_STEP_TIMEOUT:0}
```

- `0`: no timeout;
- positive value: maximum seconds for each subprocess.

On timeout, the step is recorded as failed with exit code `-1`, and stderr
includes a timeout message.

Choose this value carefully. One global limit applies to all services, including
long ETL and AI steps.

### Failure Behavior

With `on_failure: stop`, a failed step stops normal execution and all remaining
steps are recorded as `skipped`.

With `on_failure: continue`, later steps still run.

`continue_on_error: true` allows a specific failed step to continue even when
the package uses `on_failure: stop`.

Final package states are:

| Status | Meaning |
|---|---|
| `success` | No step failed |
| `failed` | A step failed and package execution stopped |
| `partial` | At least one step failed but execution continued |

Skipped steps do not by themselves make a package fail.

### Resume From a Step

Use `--from` with the exact stable step key:

```bash
python src/main.py run-package core_package \
  --from rmdb-analytics:dat_fcl_imports_daily_counts
```

For positional services, the key is:

```text
service:job
```

For subcommand services, it is:

```text
service:argument1 argument2 ...
```

Earlier steps are recorded as skipped. The selected step and all following
steps run normally.

If the key does not match, central command logs a warning and runs the entire
package. Always verify the key with `list-packages`.

Resume starts a new package run; it does not reopen or modify the failed run.

### Concurrency

APScheduler configures `max_instances=1` for each scheduled package. This
prevents two scheduler-created instances of the same package from running
simultaneously in one central-command process. Missed triggers are coalesced.

This is not a distributed or database-backed lock. A manual CLI run, dashboard
run, another central-command process, or the service's former scheduler can
still overlap the same package or service.

Operationally:

- run only one scheduler-enabled central-command instance;
- disable superseded service schedules after validation;
- check run history before manually launching a long package;
- avoid clicking **Run now** repeatedly;
- coordinate manual runs that touch the same source or target tables.

## 7. Scheduler

The production service starts the dashboard and an in-process background
scheduler:

```bash
python src/main.py serve --with-scheduler
```

At startup, the scheduler:

1. loads all packages;
2. ignores packages without `cron`;
3. ignores packages with `enabled: false`;
4. parses cron expressions in the configured timezone;
5. registers the optional daily summary.

The default timezone is:

```yaml
scheduler:
  timezone: ${RMS_CC_TZ:Asia/Colombo}
```

Package and service configuration is loaded when commands or scheduler objects
are created. Restart the systemd service after changing package schedules,
enabled states, service roots, or central settings:

```bash
sudo systemctl restart rms-central-command.service
```

## 8. Run-History Database

Central command requires PostgreSQL for its own history store. By default it
uses the `rmdb` connection and `orchestrator_schema`.

Initialize it once:

```bash
psql -h "$RMDB_HOST" \
  -U "$RMDB_USER" \
  -d "$RMDB_DATABASE" \
  -f deployment/orchestrator_schema.sql
```

### `package_runs`

Stores:

- run ID;
- package name;
- trigger (`manual` or `scheduled`);
- status;
- UTC-aware start and finish timestamps;
- package-level error message.

### `step_runs`

Stores:

- step ID and parent run ID;
- package step index;
- service and job label;
- status and exit code;
- UTC-aware start and finish timestamps;
- retained stdout and stderr tails.

Database writes are committed per history operation. Successful step history is
therefore retained even when a later step fails.

The schema name is configurable in `config/settings.yaml`, but
`deployment/orchestrator_schema.sql` creates the default
`orchestrator_schema`. If a different schema is selected, create equivalent
tables there before running central command.

## 9. Dashboard

Start without scheduling:

```bash
python src/main.py serve
```

Start with scheduling:

```bash
python src/main.py serve --with-scheduler
```

Defaults:

```text
http://127.0.0.1:8800
```

CLI overrides are available:

```bash
python src/main.py serve --host 127.0.0.1 --port 8800
```

The dashboard provides:

- **Overview**: package status, descriptions, schedules, next runs, recent
  runs, and database health summary;
- **Services**: registered roots, resolved Python interpreters, declared jobs,
  and latest job outcomes;
- **Databases**: discovered database endpoints, services using them, and TCP
  reachability;
- **Run History**: recent package runs with package filtering;
- **Run Detail**: step timings, statuses, exit codes, output tails, and
  best-effort records-updated metrics;
- **Run now**: starts a package in a background thread.

### Database Health

The Databases panel reads configured endpoints from service
`connections.yaml` or `settings.yaml` files. It tests only TCP connectivity to
the host and port.

A reachable result means the network endpoint accepted a connection. It does
not prove that credentials are correct, a query can execute, or the required
schema exists.

Credentials are not displayed or used by these reachability checks.

### Records-Updated Metrics

Run detail attempts to enrich supported steps using existing service runtime
tables, including:

- `rmdb_schema.rms_script_runtimes`;
- `analytics_schema.analytics_script_runtimes`;
- `rmdb_schema.rms_risk_rating_processing_log`.

The lookup uses the step execution time plus a five-minute grace period.
Unsupported services or missing log rows display no metric. Metric lookup
failure does not alter the package or step result.

### Dashboard Security

The current dashboard has no built-in authentication or authorization. Its
**Run now** action can execute configured packages.

Keep it bound to `127.0.0.1`. For remote administration, use an SSH tunnel:

```bash
ssh -L 8800:127.0.0.1:8800 user@server
```

Then open `http://127.0.0.1:8800` locally.

Do not bind it to a public interface unless it is protected by a properly
configured authenticated reverse proxy and network controls.

## 10. Email Notifications

Notifications support standard SMTP, including Mailgun.

Configure `.env`:

```dotenv
RMS_CC_NOTIFY_ENABLED=true
RMS_CC_NOTIFY_TO=ops@example.com,team@example.com
RMS_CC_NOTIFY_SUBJECT_PREFIX=[RMS]
RMS_CC_DAILY_SUMMARY=true
RMS_CC_DASHBOARD_URL=http://127.0.0.1:8800

SMTP_MG_HOST=smtp.mailgun.org
SMTP_MG_PORT=587
SMTP_MG_USER=your-smtp-user
SMTP_MG_PASSWORD=your-smtp-password
SMTP_MG_FROM_EMAIL=alerts@example.com
SMTP_MG_FROM_NAME=RMS Central Command
SMTP_MG_USE_SSL=false
```

With `SMTP_MG_USE_SSL=false`, central command uses STARTTLS. With `true`, it
uses implicit TLS through `SMTP_SSL`.

Failure notifications are sent when a package ends as `failed` or `partial`.
They include the first failed step and up to 2,000 characters from its stderr
tail.

The optional daily summary defaults to:

```yaml
daily_summary:
  enabled: ${RMS_CC_DAILY_SUMMARY:false}
  cron: "0 7 * * *"
  lookback_hours: 24
```

Test notification configuration:

```bash
python src/main.py send-test-email
python src/main.py send-daily-summary
```

Notification failure is logged but does not change a package's result.

## 11. Legacy TLS for eCCR

Some eCCR SQL Server jobs require a legacy OpenSSL configuration. Registered
jobs include:

- `dat_investigations`
- `dat_suspect_information`
- `eccr_case_registration`
- `eccr_recoveries`
- `eccr_suspect_information`

For these jobs, central command sets:

- `OPENSSL_CONF` from the configured path relative to the service root;
- `OPENSSL_MODULES` from `config/services.yaml`.

This reproduces the environment used by the standalone rmdb-etl legacy TLS
wrapper. A step can explicitly enable or disable this behavior using
`legacy_tls: true` or `legacy_tls: false`.

If the configured OpenSSL file is missing, central command logs a warning and
launches the step without that variable.

## 12. Installation

### Prerequisites

- Linux server;
- Python 3.10 or newer;
- PostgreSQL client and network access to RMDB;
- all orchestrated services installed separately;
- a virtual environment and `.env` for each service;
- systemd for the documented production setup.

### Application Setup

```bash
cd /opt
git clone https://github.com/uvindu-perera/rms-central-command.git
cd rms-central-command

python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
nano .env
chmod 600 .env
```

Initialize run history:

```bash
set -a
source .env
set +a

psql -h "$RMDB_HOST" \
  -U "$RMDB_USER" \
  -d "$RMDB_DATABASE" \
  -f deployment/orchestrator_schema.sql
```

### Required Central Environment

```dotenv
RMDB_HOST=localhost
RMDB_PORT=5432
RMDB_USER=rmdb
RMDB_PASSWORD=replace-with-secret
RMDB_DATABASE=rmdb

RMS_CC_HOST=127.0.0.1
RMS_CC_PORT=8800
RMS_CC_TZ=Asia/Colombo
RMS_CC_STEP_TIMEOUT=0
```

Never commit the populated `.env`.

### Production Service Roots

Development defaults point to sibling repositories. On the server, copy the
root mappings from `deployment/env.server.example` into `.env`.

Typical mappings are:

```dotenv
RMS_CC_RMDETL_ROOT=/opt/rmdb-etl
RMS_CC_RMDANALYTICS_ROOT=/opt/rmdb-analytics
RMS_CC_RMS_AI_INSIGHTS_ROOT=/opt/rms-ai-insights
RMS_CC_RMS_ATTRIBUTE_REFINER_ROOT=/opt/rms-attribute-refiner
RMS_CC_RMS_INDIVIDUALS_ROOT=/opt/rms-individuals
RMS_CC_RMS_RATINGS_ROOT=/opt/rms-ratings
RMS_CC_RMS_REVENUE_EXTRACT_ROOT=/opt/rms-revenue-extract
RMS_CC_RMS_VALUATION_EXTRACT_ROOT=/opt/rms-valuation-extract
RMS_CC_RMS_VALUATION_FLAGS_ROOT=/opt/rms-valuation-flags
RMS_CC_RMS_SUPPLIERS_ROOT=/opt/rms-suppliers
RMS_CC_RMS_VDF_MINING_ROOT=/opt/rms-vdf-mining
RMS_CC_RMS_VEHICLE_ANNOTATE_ROOT=/opt/rms-vehicle-annotate
RMS_CC_RMS_VEHICLE_REVIEW_ROOT=/opt/rms-vehicle-review
```

Validate discovery:

```bash
source venv/bin/activate
python src/main.py list-services
python src/main.py list-packages
```

Every expected interpreter should show `[ok]`.

## 13. CLI Reference

### List Services

```bash
python src/main.py list-services
```

Shows service style and resolved interpreter path.

### List Packages

```bash
python src/main.py list-packages
```

Shows schedule, enabled state, failure behavior, and ordered steps.

### List Jobs

```bash
python src/main.py list-jobs
python src/main.py list-jobs --service rmdb-etl
```

For positional services, central command invokes the service's configured list
command and heuristically parses the output. For subcommand services, it lists
commands referenced by package definitions.

### Run a Package

```bash
python src/main.py run-package live_package
python src/main.py run-package core_package
python src/main.py run-package off_peak_package
python src/main.py run-package ai_off_peak
python src/main.py run-package ai_insights_package
```

The CLI exits zero only when the package status is `success`.

### Dry Run

```bash
python src/main.py run-package core_package --dry-run
```

This passes `--dry-run` only to positional services. Subcommand steps still run
normally. Do not use package-level dry-run as a guarantee that an entire mixed
package is non-mutating.

### Start Dashboard

```bash
python src/main.py serve
python src/main.py serve --with-scheduler
```

Production should normally use systemd rather than an interactive shell.

## 14. systemd Deployment

Install and start the supplied unit:

```bash
sudo cp deployment/rms-central-command.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now rms-central-command.service
```

Common operations:

```bash
sudo systemctl status rms-central-command.service
sudo systemctl restart rms-central-command.service
sudo systemctl stop rms-central-command.service
sudo systemctl start rms-central-command.service
sudo journalctl -u rms-central-command.service -f
sudo journalctl -u rms-central-command.service --since today
```

The supplied unit:

- runs as user `rmd`;
- uses `/opt/rms-central-command` as its working directory;
- loads `/opt/rms-central-command/.env`;
- runs `serve --with-scheduler`;
- restarts after failures with a ten-second delay.

Ensure `rmd` can:

- read central and service files;
- execute each service virtual environment;
- read each service `.env`;
- connect to required databases and APIs;
- write wherever the child services require.

## 15. Safe Migration

Central command should become the only scheduled trigger only after package
validation.

Recommended sequence:

1. Install central command without enabling its scheduler.
2. Initialize the history schema.
3. verify service roots and interpreters.
4. inspect all package steps.
5. run low-risk packages manually.
6. validate run status, outputs, row metrics, and downstream data.
7. test long and off-peak packages in their intended operating window.
8. record every legacy scheduler or timer that will be disabled.
9. disable overlapping service schedules.
10. enable `rms-central-command.service`.
11. verify next-run times and monitor the first scheduled runs.

Do not leave both old and new schedules enabled for the same work. Central
command's in-process scheduler lock does not prevent another systemd service or
timer from launching the same application.

### Rollback

```bash
sudo systemctl stop rms-central-command.service
```

Then re-enable the documented former service schedules. Because central command
executes services externally, rollback does not require undoing changes inside
those services.

## 16. Operations and Troubleshooting

### Service Shows `python3` or `MISSING`

Run:

```bash
python src/main.py list-services
```

Check:

- the relevant `RMS_CC_*_ROOT`;
- the service directory;
- `venv/bin/python` or `.venv/bin/python`;
- file ownership and execute permissions.

### Unknown Package or Service

Confirm:

- the package file ends in `.yaml`;
- it is under `config/packages/`;
- the package name is correct;
- every step references a registered service;
- YAML indentation is valid.

Then run:

```bash
python src/main.py list-packages
```

### History Schema Missing

Typical errors mention missing `orchestrator_schema.package_runs` or
`step_runs`.

Apply:

```bash
psql -h "$RMDB_HOST" \
  -U "$RMDB_USER" \
  -d "$RMDB_DATABASE" \
  -f deployment/orchestrator_schema.sql
```

### Database Password Missing

Set `RMDB_PASSWORD` in `/opt/rms-central-command/.env`, restrict permissions,
and restart:

```bash
chmod 600 /opt/rms-central-command/.env
sudo systemctl restart rms-central-command.service
```

Remember that each child service also needs its own valid credentials in its
own `.env`.

### Step Failed

Inspect:

1. dashboard run detail;
2. step exit code;
3. retained stderr and stdout tails;
4. central journal;
5. target service logs;
6. the exact command shown in central logs.

Reproduce directly from the service root with its own virtual environment when
necessary.

### Package Remains `running`

An abrupt process termination or an exception outside normal step completion
can leave history rows in `running`. First confirm that no process is actually
active. Treat stale rows as interrupted history; starting a new run does not
resume them automatically.

### No Live Child Output

This is expected. Child output is captured and retained after the step exits.
Use the target service's own logs for live application progress, or inspect the
central log for step start and completion.

### Package Runs Twice

Check for:

- multiple central-command processes;
- a manual CLI run;
- dashboard **Run now**;
- the previous service scheduler or systemd timer;
- a second host running central command.

### Schedule Change Has No Effect

Restart the scheduler process:

```bash
sudo systemctl restart rms-central-command.service
```

Then inspect startup registration:

```bash
sudo journalctl -u rms-central-command.service -n 100
```

### eCCR TLS Failure

Confirm:

- the job appears in `legacy_tls_jobs`;
- `/opt/rmdb-etl/config/openssl_legacy.cnf` exists;
- `OPENSSL_MODULES` matches the server;
- central logs say the legacy TLS environment was applied.

Resume after correcting the environment:

```bash
python src/main.py run-package core_package \
  --from rmdb-etl:dat_investigations
```

### Email Not Sent

Run:

```bash
python src/main.py send-test-email
```

Check:

- `RMS_CC_NOTIFY_ENABLED=true`;
- recipients are present;
- SMTP host, port, user, password, and sender;
- SSL versus STARTTLS mode;
- outbound firewall rules;
- central logs.

## 17. Configuration Change Checklist

When adding a service:

1. register it in `config/services.yaml`;
2. add its production root to `.env` and the server environment example;
3. verify its virtual environment and entry script;
4. test its CLI directly;
5. run `list-services`;
6. add it to a package;
7. run the package manually;
8. inspect history and output tails.

When adding or changing a package:

1. choose a unique package name;
2. verify the cron expression and timezone;
3. choose `stop` or `continue` deliberately;
4. order dependencies correctly;
5. use the correct `job` or `argv` style;
6. verify placeholders;
7. consider overlap with existing packages and old schedules;
8. validate manually;
9. restart central command;
10. confirm the dashboard's next-run time.

## 18. Security and Governance

- Keep `.env` files out of source control.
- Restrict central and service `.env` permissions.
- Keep the dashboard on localhost unless protected by authentication.
- Treat dashboard access as execution access.
- Run systemd under a dedicated non-root account.
- Grant only the file and database permissions required by the child services.
- Retained output can contain business data or error context; restrict access to
  the dashboard and history schema.
- Review package changes as production scheduling changes.
- Maintain a record of disabled legacy schedules for rollback.
- Avoid configuring untrusted service roots or package arguments; central
  command executes configured Python commands with the service account's
  privileges.

## 19. Current Limitations

- There is no distributed package lock.
- Manual and dashboard runs can overlap scheduled runs.
- Child output is not streamed live.
- The dashboard has no built-in authentication.
- Dashboard package launch has no confirmation or per-user authorization.
- Configuration changes require scheduler restart to affect registered jobs.
- Dry-run applies only to positional services.
- Metrics are best-effort and available only for recognized service logs.
- Database health is TCP reachability, not an authenticated query.
- Run-history retention and cleanup are not automated.
- Interrupted runs can remain marked `running`.
- Scheduling state is in memory rather than persisted as APScheduler job data.

These limitations do not prevent normal single-host operation, but they should
guide access controls, operator procedures, and future enhancements.

---

## Attribution

*Administrative context — separate from the operational sections above.*

> **Developer** — **Uvindu Perera**, Superintendent of Customs, **Risk Management Directorate**.
>
> **Modernization context** — **rms-central-command** is part of a broader program to retire legacy **Java** components built for the **Automated Risk Management System (ARMS)** in favor of **service-oriented Python** applications. As the orchestration control plane, it replaces fragmented per-service schedulers and cron entries with a single **package-based** pipeline runner on **systemd**, coordinating **rmdb-etl**, **rmdb-analytics**, and all downstream **rms-\*** services through YAML-defined packages. It provides **run history**, **failure alerts**, and a **localhost dashboard** for operational visibility, consolidating scheduling governance into one maintainable entry point for the RMS data platform.
