#!/usr/bin/env bash
# Load TPC-H .tbl files into the target database via LOAD DATA LOCAL INFILE.
# For seekdb, OB direct-load hints are added to accelerate ingestion.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

PARALLEL="${PARALLEL:-16}"

parse_common_args "$@"

if [[ ! -d "${DATA_DIR}" ]]; then
    echo "[ERROR] data dir not found: ${DATA_DIR}" >&2
    echo "Run scripts/prepare.sh first or pass -d <dir>." >&2
    exit 1
fi

TABLES=(region nation customer supplier part partsupp orders lineitem)

hint_for() {
    if [[ "${DB_TYPE}" == "seekdb" ]]; then
        echo "/*+ parallel(${PARALLEL}) direct(true, 0) */"
    else
        echo ""
    fi
}

for t in "${TABLES[@]}"; do
    file="${DATA_DIR}/${t}.tbl"
    if [[ ! -f "${file}" ]]; then
        echo "[ERROR] missing data file: ${file}" >&2
        exit 1
    fi
    log "Loading ${t} <- ${file}"
    HINT="$(hint_for)"
    run_sql "LOAD DATA ${HINT} LOCAL INFILE '${file}' INTO TABLE ${t} FIELDS TERMINATED BY '|';"
done

log "Load done."
