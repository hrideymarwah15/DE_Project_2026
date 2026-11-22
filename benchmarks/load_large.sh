#!/usr/bin/env bash
# Run from the repository root against a NEW database with sql/01_schema.sql applied.
set -euo pipefail
db="${1:?database required}"
test -f large_data/messages.csv
sed 's@seed_data/@large_data/@g' sql/02_load_data.sql | psql -X -v ON_ERROR_STOP=1 -d "$db"
psql -X -v ON_ERROR_STOP=1 -d "$db" -f sql/05_indexes.sql
