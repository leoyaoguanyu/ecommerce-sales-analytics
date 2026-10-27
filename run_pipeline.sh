#!/usr/bin/env bash
# End-to-end pipeline: load -> clean -> data-quality gate -> analyses -> exports.
# Connection comes from the standard libpq env vars (PGHOST, PGUSER,
# PGPASSWORD, PGDATABASE). Run from the repo root.
set -euo pipefail

PSQL="psql -X -q -v ON_ERROR_STOP=1"

echo "==> 1/5 schema + load"
$PSQL -f sql/01_schema.sql 2>/dev/null
$PSQL -f sql/02_load.sql

echo "==> 2/5 clean star schema"
$PSQL -f sql/03_clean.sql 2>/dev/null

echo "==> 3/5 data-quality gate"
$PSQL -f sql/04_data_quality.sql 2>/dev/null
blocking=$($PSQL -At -c "SELECT COALESCE(SUM(failing_rows),0) FROM analytics.dq_report WHERE severity='blocking'")
if [ "$blocking" != "0" ]; then
  echo "Blocking data-quality checks failed ($blocking rows). Stopping." >&2
  exit 1
fi
$PSQL --csv -c "SELECT * FROM analytics.dq_report ORDER BY severity, check_name" > outputs/00_data_quality.csv

echo "==> 4/5 business analyses -> outputs/*.csv"
for f in sql/analysis/*.sql; do
  name=$(basename "$f" .sql)
  $PSQL --csv -f "$f" 2>/dev/null > "outputs/${name}.csv"
  echo "    $name ($(($(wc -l < "outputs/${name}.csv") - 1)) rows)"
done

echo "==> 5/5 Power BI model tables -> powerbi/data/*.csv"
mkdir -p powerbi/data
$PSQL -f sql/05_powerbi_export.sql
echo "Done."
