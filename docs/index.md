# RMS Documentation

Documentation for the RMS (Risk Management System) service suite maintained by
the Risk Management Directorate. Each project below is developed and operated
as an independent service; this site collects their `documentation.md` files
in one searchable place.

## Data Warehouse

- [rmdb-etl](rmdb-etl.md) — extraction of operational source data into RMDB.
- [rmdb-analytics](rmdb-analytics.md) — transformation of warehouse data into
  dashboard-ready analytical datasets.

## Orchestration

- [rms-central-command](rms-central-command.md) — control plane that runs the
  services below as scheduled packages, with run history and a dashboard.

## Risk Profiling

- [rms-individuals](rms-individuals.md) — individual identity and
  risk-continuity layer.
- [rms-ratings](rms-ratings.md) — risk rating computation for profiling
  workflows.
- [rms-simulator](rms-simulator.md) — ASYCUDA World selectivity rule
  simulation engine for testing criteria changes.
- [rms-suppliers](rms-suppliers.md) — foreign supplier entity resolution.

## Extraction and Reporting

- [rms-revenue-extract](rms-revenue-extract.md) — Revenue Dashboard workbook
  loader.
- [rms-ai-insights](rms-ai-insights.md) — AI-assisted analytical summaries.

## Vehicle Import Review

- [rms-vehicle-annotate](rms-vehicle-annotate.md) — vehicle make/model/fuel/
  valuation annotation for SAD vehicle declarations.
- [rms-vehicle-review](rms-vehicle-review.md) — two-tier (rule + local LLM)
  review of annotated vehicle records.

---

*This site is generated from each project's `docs/documentation.md`. Source
repositories are private; see `scripts/sync-docs.sh` in
[rms-docs](https://github.com/uvindu-perera/rms-docs) for how this content is
kept up to date.*
