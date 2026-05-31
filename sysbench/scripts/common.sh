# shellcheck shell=bash
# Common helpers for sysbench-bench scripts.
# Source this; do not execute directly.

set -euo pipefail

# ----- defaults -----
DB_TYPE="${DB_TYPE:-mysql}"          # seekdb | mysql
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-3306}"
USER="${USER:-root}"
PASSWORD="${PASSWORD:-}"
DBNAME="${DBNAME:-sbtest}"

TABLES="${TABLES:-10}"
TABLE_SIZE="${TABLE_SIZE:-1000000}"
THREADS="${THREADS:-200}"
PREPARE_THREADS="${PREPARE_THREADS:-16}"
CPU_COUNT="${CPU_COUNT:-0}"          # SeekDB cpu_count parameter (0 = skip / auto)
TIME_SEC="${TIME_SEC:-600}"
REPORT_INTERVAL="${REPORT_INTERVAL:-10}"
PERCENTILE="${PERCENTILE:-99}"

# Path to sysbench binary; falls back to plain `sysbench` on PATH.
SYSBENCH_BIN="${SYSBENCH_BIN:-/usr/sysbench/bin/sysbench}"
if [[ ! -x "${SYSBENCH_BIN}" ]]; then
    if command -v sysbench >/dev/null 2>&1; then
        SYSBENCH_BIN="$(command -v sysbench)"
    fi
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOG_DIR:-${REPO_ROOT}/logs}"
mkdir -p "${LOG_DIR}"

log() { echo "[$(date '+%F %T')] $*"; }

usage_common() {
    cat <<EOF
Common options:
  --db        seekdb | mysql            (default: ${DB_TYPE})
  -h HOST     database host             (default: ${HOST})
  -P PORT     database port             (default: ${PORT})
  -u USER     database user             (default: ${USER})
  -p PASS     database password         (default: empty)
  -D DBNAME   database name             (default: ${DBNAME})
  --tables N        table count         (default: ${TABLES})
  --table-size N    rows per table      (default: ${TABLE_SIZE})
  --cpu-count N     CPU count for SeekDB (0=auto) (default: ${CPU_COUNT})
  --threads N       concurrent threads  (default: ${THREADS})
  --prepare-threads N  threads for prepare (default: ${PREPARE_THREADS})
  --time N          run duration sec    (default: ${TIME_SEC})
  --report-interval N                   (default: ${REPORT_INTERVAL})
  --percentile N                        (default: ${PERCENTILE})
  --help      show this message
EOF
}

parse_common_args() {
    EXTRA_ARGS=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --db)               DB_TYPE="$2"; shift 2 ;;
            -h)                 HOST="$2"; shift 2 ;;
            -P)                 PORT="$2"; shift 2 ;;
            -u)                 USER="$2"; shift 2 ;;
            -p)                 PASSWORD="$2"; shift 2 ;;
            -D)                 DBNAME="$2"; shift 2 ;;
            --tables)           TABLES="$2"; shift 2 ;;
            --table-size)       TABLE_SIZE="$2"; shift 2 ;;
            --cpu-count)        CPU_COUNT="$2"; shift 2 ;;
            --threads)          THREADS="$2"; shift 2 ;;
            --prepare-threads)  PREPARE_THREADS="$2"; shift 2 ;;
            --time)             TIME_SEC="$2"; shift 2 ;;
            --report-interval)  REPORT_INTERVAL="$2"; shift 2 ;;
            --percentile)       PERCENTILE="$2"; shift 2 ;;
            --help)             usage_common; exit 0 ;;
            *)                  EXTRA_ARGS+=("$1"); shift ;;
        esac
    done

    case "${DB_TYPE}" in
        seekdb|mysql) ;;
        *) echo "[ERROR] --db must be 'seekdb' or 'mysql'" >&2; exit 1 ;;
    esac

    if [[ ! -x "${SYSBENCH_BIN}" ]]; then
        echo "[ERROR] sysbench binary not found at ${SYSBENCH_BIN} and not on PATH" >&2
        echo "        Run ./scripts/install.sh first, or set SYSBENCH_BIN=/path/to/sysbench" >&2
        exit 1
    fi
}

# Build the shared sysbench connection / sizing args.
# Caller picks the workload (e.g. oltp_read_write) and the action (prepare/run/cleanup).
build_sysbench_args() {
    SB_ARGS=(
        --mysql-host="${HOST}"
        --mysql-port="${PORT}"
        --mysql-user="${USER}"
        --mysql-db="${DBNAME}"
        --mysql-ignore-errors=1062
        --tables="${TABLES}"
        --table_size="${TABLE_SIZE}"
    )
    if [[ -n "${PASSWORD}" ]]; then
        SB_ARGS+=( --mysql-password="${PASSWORD}" )
    fi
}

# Append the args you typically only want for `run` (not prepare/cleanup).
build_run_args() {
    RUN_ARGS=(
        --db-ps-mode=disable
        --report-interval="${REPORT_INTERVAL}"
        --percentile="${PERCENTILE}"
        --time="${TIME_SEC}"
        --threads="${THREADS}"
    )
}

# Run a SQL string against the SeekDB/OceanBase sys tenant.
# Uses SYS_PASSWORD env var if set, otherwise falls back to PASSWORD.
run_sql_sys() {
    local sys_cmd=( mysql -h"${HOST}" -P"${PORT}" -uroot@sys -A )
    local sp="${SYS_PASSWORD:-${PASSWORD}}"
    if [[ -n "${sp}" ]]; then
        sys_cmd+=( -p"${sp}" )
    fi
    "${sys_cmd[@]}" oceanbase -e "$1"
}

# Silent/no-header variant of run_sql_sys for machine parsing (tab-separated).
run_sql_sys_n() {
    local sys_cmd=( mysql -h"${HOST}" -P"${PORT}" -uroot@sys -A -N -s )
    local sp="${SYS_PASSWORD:-${PASSWORD}}"
    if [[ -n "${sp}" ]]; then
        sys_cmd+=( -p"${sp}" )
    fi
    "${sys_cmd[@]}" oceanbase -e "$1" 2>/dev/null
}

# Trigger a SeekDB/OceanBase MAJOR FREEZE and block until the major compaction
# completes, so the run starts from a clean baseline (empty incremental memtable
# layer, no carried-over LSM read amplification). Detection: a new FROZEN_SCN is
# registered (distinct from the pre-freeze value), then STATUS returns to IDLE
# with LAST_SCN == FROZEN_SCN. FREEZE_TIMEOUT caps the wait (default 900s).
seekdb_major_freeze() {
    local timeout="${FREEZE_TIMEOUT:-900}" interval=3 waited=0
    local prev_frozen
    prev_frozen="$(run_sql_sys_n "SELECT FROZEN_SCN FROM DBA_OB_MAJOR_COMPACTION;" | head -1)"
    log "SeekDB: MAJOR FREEZE (prev_frozen=${prev_frozen}); waiting for compaction ..."
    run_sql_sys "ALTER SYSTEM MAJOR FREEZE;" >/dev/null 2>&1 || true
    while true; do
        local row frozen last status
        row="$(run_sql_sys_n "SELECT FROZEN_SCN, LAST_SCN, STATUS FROM DBA_OB_MAJOR_COMPACTION;" | head -1)"
        frozen="$(echo "${row}" | cut -f1)"
        last="$(echo "${row}" | cut -f2)"
        status="$(echo "${row}" | cut -f3)"
        if [[ "${status}" == "IDLE" && -n "${frozen}" && "${frozen}" == "${last}" && "${frozen}" != "${prev_frozen}" ]]; then
            log "SeekDB: major compaction complete (scn=${frozen}, waited ${waited}s)"
            return 0
        fi
        if (( waited >= timeout )); then
            log "SeekDB: WARN compaction not IDLE after ${timeout}s (status=${status} frozen=${frozen} last=${last}); proceeding anyway"
            return 0
        fi
        sleep "${interval}"; waited=$((waited+interval))
    done
}
