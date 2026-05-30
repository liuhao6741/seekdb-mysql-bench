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

if [[ "${DB_TYPE}" == "seekdb" ]]; then
    log "SeekDB: setting cpu_quota_concurrency = 20"
    run_sql_sys "ALTER SYSTEM SET cpu_quota_concurrency = 20 TENANT = ALL;"

    if [[ "${CPU_COUNT}" -gt 0 ]]; then
        log "SeekDB: setting cpu_count = ${CPU_COUNT}"
        run_sql_sys "ALTER SYSTEM SET cpu_count = ${CPU_COUNT};"
    fi

    log "SeekDB: tuning for benchmark (disable audit/trace/defensive checks)"
    run_sql_sys "ALTER SYSTEM SET enable_sql_audit = false;"
    run_sql_sys "ALTER SYSTEM SET enable_perf_event = false;"
    run_sql_sys "ALTER SYSTEM SET syslog_level = 'PERF';"
    run_sql_sys "ALTER SYSTEM SET enable_record_trace_log = false;"
    run_sql_sys "ALTER SYSTEM SET _enable_defensive_check = false;"
    run_sql_sys "ALTER SYSTEM SET _lcl_op_interval = '0ms';"
    # Tolerate failure: errors with "tracing not enabled" when trace is already off,
    # which is the desired benchmark state anyway.
    run_sql_sys "CALL DBMS_MONITOR.OB_TENANT_TRACE_DISABLE;" || \
        log "SeekDB: OB_TENANT_TRACE_DISABLE skipped (tracing already disabled)"
fi
