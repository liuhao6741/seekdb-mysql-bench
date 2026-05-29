#!/usr/bin/env bash
# Post-load housekeeping: trigger major compaction (seekdb only) and gather statistics.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

parse_common_args "$@"

TABLES=(lineitem orders customer part partsupp supplier nation region)

if [[ "${DB_TYPE}" == "seekdb" ]]; then
    log "Triggering OceanBase major freeze (requires sys tenant access; set SYS_PASSWORD if needed)"
    if run_sql_sys "ALTER SYSTEM MAJOR FREEZE;" ; then
        log "Major freeze submitted. Polling cdb_ob_major_compaction until IDLE ..."
        while :; do
            status=$(run_sql_sys "SELECT status FROM oceanbase.cdb_ob_major_compaction\G" \
                       | awk -F': ' '/status/ {print $2}' | head -n1 || true)
            log "  current status: ${status:-unknown}"
            if [[ "${status}" == "IDLE" ]]; then
                break
            fi
            sleep 15
        done
    else
        log "[WARN] sys tenant not reachable, skipping major freeze. Stats only."
    fi

    log "Gathering optimizer stats via dbms_stats"
    for t in "${TABLES[@]}"; do
        log "  stats: ${t}"
        run_sql "CALL dbms_stats.gather_table_stats('${DBNAME}', '${t}', degree=>32);"
    done
else
    log "Running ANALYZE TABLE on MySQL"
    for t in "${TABLES[@]}"; do
        log "  analyze: ${t}"
        run_sql "ANALYZE TABLE ${t};"
    done
fi

log "post_load done."
