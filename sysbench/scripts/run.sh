#!/usr/bin/env bash
# Run one or more sysbench OLTP workloads against the target database.
#
# Workloads (and their rand-seed, kept identical to the originally provided commands
# so the runs are reproducible across users):
#   point_select       - oltp_point_select       (no extra seed)
#   read_only          - oltp_read_only          (no extra seed)
#   read_write         - oltp_read_write         --rand-seed=24433 --rand-type=uniform
#   insert             - oltp_insert             --rand-seed=12104 --rand-type=uniform
#   update_non_index   - oltp_update_non_index   --rand-seed=10515 --rand-type=uniform
#   write_only         - oltp_write_only         --rand-seed=11972 --rand-type=uniform
#
# Usage:
#   ./scripts/run.sh --db seekdb -h <host> -P <port> -u root -D sbtest \
#                    --workload read_write --threads 200 --time 600
#   ./scripts/run.sh --db mysql ... --workload all       # runs all six in order

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

ALL_WORKLOADS=(point_select read_only read_write insert update_non_index write_only)
WORKLOAD="read_write"

COMMON_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --workload) WORKLOAD="$2"; shift 2 ;;
        *)          COMMON_ARGS+=("$1"); shift ;;
    esac
done
parse_common_args "${COMMON_ARGS[@]}"
build_sysbench_args
build_run_args

# Map workload short name -> (lua test, extra args).
workload_lua() {
    case "$1" in
        point_select)     echo "oltp_point_select" ;;
        read_only)        echo "oltp_read_only" ;;
        read_write)       echo "oltp_read_write" ;;
        insert)           echo "oltp_insert" ;;
        update_non_index) echo "oltp_update_non_index" ;;
        write_only)       echo "oltp_write_only" ;;
        *) echo "" ;;
    esac
}

workload_extra() {
    case "$1" in
        read_write)       echo "--rand-seed=24433 --rand-type=uniform" ;;
        insert)           echo "--rand-seed=12104 --rand-type=uniform" ;;
        update_non_index) echo "--rand-seed=10515 --rand-type=uniform" ;;
        write_only)       echo "--rand-seed=11972 --rand-type=uniform" ;;
        *) echo "" ;;
    esac
}

run_one() {
    local w="$1"
    local lua extras log_file
    lua="$(workload_lua "$w")"
    if [[ -z "${lua}" ]]; then
        echo "[ERROR] unknown workload: $w" >&2
        echo "Supported: ${ALL_WORKLOADS[*]} | all" >&2
        exit 1
    fi
    extras="$(workload_extra "$w")"

    stamp="$(date +%Y%m%d_%H%M%S)"
    log_file="${LOG_DIR}/sysbench_${DB_TYPE}_${w}_${stamp}.log"

    log "===== workload=${w} (lua=${lua}) ====="
    log "  log file: ${log_file}"
    # extras is empty or "--rand-seed=N --rand-type=uniform" -> safe to word-split
    # shellcheck disable=SC2086
    "${SYSBENCH_BIN}" \
        "${SB_ARGS[@]}" \
        "${RUN_ARGS[@]}" \
        ${extras} \
        "${lua}" run 2>&1 | tee "${log_file}"

    # Pull the key numbers from the tail of the log into a summary line.
    summary="$(awk '
        /transactions:/     {tps=$3}
        /queries:/          {qps=$3}
        /95th percentile:|99th percentile:/ {p99=$3" "$4}
        END { printf "tps=%s qps=%s p99=%s", tps, qps, p99 }
    ' "${log_file}")"
    log "  summary: ${summary}"
}

if [[ "${WORKLOAD}" == "all" ]]; then
    for w in "${ALL_WORKLOADS[@]}"; do
        run_one "${w}"
    done
else
    run_one "${WORKLOAD}"
fi

log "All requested workloads finished. Logs in ${LOG_DIR}"
