#!/usr/bin/env bash
# Drop all TPC-H tables in the target database.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

parse_common_args "$@"

log "Dropping TPC-H tables in '${DBNAME}' on ${HOST}:${PORT}"
run_sql_file "${REPO_ROOT}/ddl/drop_tables.sql"
log "Cleanup done."
