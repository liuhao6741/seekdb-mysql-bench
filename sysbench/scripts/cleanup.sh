#!/usr/bin/env bash
# Drop the sysbench schema tables (sbtest1 .. sbtestN).
#
# Usage:
#   ./scripts/cleanup.sh --db seekdb -h 11.124.9.34 -P 2881 -u root -D sbtest

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

parse_common_args "$@"
build_sysbench_args

log "Cleaning sbtest: db=${DB_TYPE} host=${HOST}:${PORT} dbname=${DBNAME} tables=${TABLES}"

"${SYSBENCH_BIN}" \
    "${SB_ARGS[@]}" \
    oltp_read_write cleanup
