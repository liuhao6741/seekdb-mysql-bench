#!/usr/bin/env bash
# Pre-populate the sysbench schema (--tables of --table-size rows each).
#
# Usage:
#   ./scripts/prepare.sh --db seekdb -h 11.124.9.34 -P 2881 -u root -D sbtest

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

parse_common_args "$@"
build_sysbench_args

log "Preparing sbtest: db=${DB_TYPE} host=${HOST}:${PORT} dbname=${DBNAME}"
log "  tables=${TABLES} table_size=${TABLE_SIZE} prepare_threads=${PREPARE_THREADS}"

"${SYSBENCH_BIN}" \
    "${SB_ARGS[@]}" \
    --auto_inc=on \
    --threads="${PREPARE_THREADS}" \
    oltp_read_write prepare
