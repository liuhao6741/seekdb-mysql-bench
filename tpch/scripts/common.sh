# shellcheck shell=bash
# Common helpers shared by all tpch-bench scripts.
# Source this file from other scripts; do not execute directly.

set -euo pipefail

# ----- defaults -----
DB_TYPE="${DB_TYPE:-mysql}"      # seekdb | mysql
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-3306}"
USER="${USER:-root}"
PASSWORD="${PASSWORD:-}"
DBNAME="${DBNAME:-tpch}"
SCALE="${SCALE:-1}"

# Resolve repo root regardless of where the script is invoked from.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR_DEFAULT="${REPO_ROOT}/data/tpch_${SCALE}g"
DATA_DIR="${DATA_DIR:-$DATA_DIR_DEFAULT}"
LOG_DIR="${LOG_DIR:-${REPO_ROOT}/logs}"
mkdir -p "${LOG_DIR}"

usage_common() {
    cat <<EOF
Common options:
  --db        seekdb | mysql            (default: ${DB_TYPE})
  -h HOST     database host             (default: ${HOST})
  -P PORT     database port             (default: ${PORT})
  -u USER     database user             (default: ${USER})
  -p PASS     database password         (default: empty)
  -D DBNAME   database name             (default: ${DBNAME})
  -s SCALE    TPC-H scale factor        (default: ${SCALE})
  -d DIR      data directory            (default: \${REPO_ROOT}/data/tpch_<scale>g)
  --help      show this message
EOF
}

parse_common_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --db)   DB_TYPE="$2"; shift 2 ;;
            -h)     HOST="$2"; shift 2 ;;
            -P)     PORT="$2"; shift 2 ;;
            -u)     USER="$2"; shift 2 ;;
            -p)     PASSWORD="$2"; shift 2 ;;
            -D)     DBNAME="$2"; shift 2 ;;
            -s)     SCALE="$2"; shift 2 ;;
            -d)     DATA_DIR="$2"; shift 2 ;;
            --help) usage_common; exit 0 ;;
            *)      echo "[ERROR] unknown argument: $1" >&2; usage_common; exit 1 ;;
        esac
    done

    case "${DB_TYPE}" in
        seekdb|mysql) ;;
        *) echo "[ERROR] --db must be 'seekdb' or 'mysql', got '${DB_TYPE}'" >&2; exit 1 ;;
    esac

    if [[ "${DATA_DIR}" == "${DATA_DIR_DEFAULT}" ]]; then
        DATA_DIR="${REPO_ROOT}/data/tpch_${SCALE}g"
    fi

    # Build the mysql argv array once. Use an array so quoting / spaces are safe
    # and we never need to eval the command string.
    MYSQL_CMD=( mysql -h"${HOST}" -P"${PORT}" -u"${USER}" --local-infile=1 -A )
    if [[ -n "${PASSWORD}" ]]; then
        MYSQL_CMD+=( -p"${PASSWORD}" )
    fi
}

# Run a SQL string against the target DB.
run_sql() {
    "${MYSQL_CMD[@]}" "${DBNAME}" -e "$1"
}

# Run a SQL string without selecting a database (e.g. CREATE DATABASE).
run_sql_nodb() {
    "${MYSQL_CMD[@]}" -e "$1"
}

# Run a SQL file against the target DB.
run_sql_file() {
    "${MYSQL_CMD[@]}" "${DBNAME}" < "$1"
}

# Run a SQL string against the OceanBase sys tenant (seekdb only).
run_sql_sys() {
    local sys_cmd=( mysql -h"${HOST}" -P"${PORT}" -uroot@sys -A )
    if [[ -n "${SYS_PASSWORD:-}" ]]; then
        sys_cmd+=( -p"${SYS_PASSWORD}" )
    fi
    "${sys_cmd[@]}" oceanbase -e "$1"
}

log() {
    echo "[$(date '+%F %T')] $*"
}
