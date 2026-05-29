#!/usr/bin/env bash
# Run the 22 TPC-H queries once and log per-query latency.
#
# Extra option:
#   --queries "1 3 7"    only run the listed query ids

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

QUERY_IDS=""

COMMON_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --queries) QUERY_IDS="$2"; shift 2 ;;
        *)         COMMON_ARGS+=("$1"); shift ;;
    esac
done
parse_common_args "${COMMON_ARGS[@]}"

QUERY_DIR="${REPO_ROOT}/queries"
if [[ -z "${QUERY_IDS}" ]]; then
    QUERY_IDS="$(seq 1 22 | tr '\n' ' ')"
fi

stamp="$(date +%Y%m%d_%H%M%S)"
SUMMARY="${LOG_DIR}/tpch_${DB_TYPE}_${SCALE}g_${stamp}.tsv"
DETAIL="${LOG_DIR}/tpch_${DB_TYPE}_${SCALE}g_${stamp}.log"
echo -e "query\tcost_ms" > "${SUMMARY}"

log "Target: db=${DB_TYPE} host=${HOST}:${PORT} dbname=${DBNAME} scale=${SCALE}"
log "Detail log : ${DETAIL}"
log "Summary tsv: ${SUMMARY}"

total_start=$(date +%s%3N)
for i in ${QUERY_IDS}; do
    f="${QUERY_DIR}/${i}.sql"
    if [[ ! -f "${f}" ]]; then
        log "[WARN] missing ${f}, skip"
        continue
    fi
    s=$(date +%s%3N)
    log "BEGIN Q${i}"
    run_sql_file "${f}" >>"${DETAIL}" 2>&1
    e=$(date +%s%3N)
    cost=$((e - s))
    log "END   Q${i} cost=${cost}ms"
    echo -e "${i}\t${cost}" >> "${SUMMARY}"
done
total_end=$(date +%s%3N)
log "TPC-H 22 queries finished, total=$((total_end - total_start))ms"

log "Per-query latency:"
column -t -s $'\t' "${SUMMARY}"
