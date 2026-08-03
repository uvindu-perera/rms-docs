#!/usr/bin/env bash
# Sync docs/documentation.md from each sibling RMS repo into this site's
# docs/ folder. Run this whenever a source repo's documentation changes,
# then commit and push rms-docs to redeploy the site.
#
# Usage: ./scripts/sync-docs.sh

set -euo pipefail

SITE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_ROOT="$(cd "$SITE_ROOT/.." && pwd)"
DOCS_DIR="$SITE_ROOT/docs"

# slug:relative-path-to-repo-root (relative to WORKSPACE_ROOT)
SOURCES=(
  "rmdb-etl:rmdb-etl/rmdb-etl"
  "rmdb-analytics:rmdb-analytics"
  "rms-ai-insights:rms-ai-insights"
  "rms-central-command:rms-central-command"
  "rms-individuals:rms-individuals"
  "rms-ratings:rms-ratings"
  "rms-simulator:rms-simulator"
  "rms-suppliers:rms-suppliers"
  "rms-revenue-extract:rms-revenue-extract"
  "rms-vehicle-annotate:rms-vehicle-annotate"
  "rms-vehicle-review:rms-vehicle-review"
)

echo "Syncing documentation from sibling repos into $DOCS_DIR ..."

for entry in "${SOURCES[@]}"; do
  slug="${entry%%:*}"
  rel="${entry##*:}"
  src="$WORKSPACE_ROOT/$rel/docs/documentation.md"
  dest="$DOCS_DIR/$slug.md"

  if [[ ! -f "$src" ]]; then
    echo "  SKIP $slug: not found at $src"
    continue
  fi

  {
    echo "<!-- Synced from $rel/docs/documentation.md. Edit there, then re-run scripts/sync-docs.sh -->"
    echo
    cat "$src"
  } > "$dest"

  echo "  OK   $slug <- $rel/docs/documentation.md"
done

echo "Done. Review changes with 'git status', then commit and push."
