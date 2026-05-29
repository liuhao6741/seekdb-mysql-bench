#!/usr/bin/env bash
# Create the target database, tables and indexes.
# Picks the correct DDL flavor based on --db.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

parse_common_args "$@"

DDL_DIR="${REPO_ROOT}/ddl/${DB_TYPE}"
if [[ ! -d "${DDL_DIR}" ]]; then
    echo "[ERROR] DDL dir not found: ${DDL_DIR}" >&2
    exit 1
fi

log "Creating database '${DBNAME}' on ${HOST}:${PORT} (db=${DB_TYPE})"
run_sql_nodb "CREATE DATABASE IF NOT EXISTS \`${DBNAME}\`;"

for f in "${DDL_DIR}"/[0-9]*.sql; do
    log "Applying ${f##*/}"
    run_sql_file "${f}"
done

log "Schema ready."
