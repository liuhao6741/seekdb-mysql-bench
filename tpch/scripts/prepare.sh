#!/usr/bin/env bash
# Generate TPC-H data files using the bundled dbgen.
#
# Usage:
#   ./scripts/prepare.sh -s 1
#   ./scripts/prepare.sh -s 10 -d /tmp/tpch_10g
#
# Output: <data-dir>/{customer,lineitem,nation,orders,part,partsupp,region,supplier}.tbl

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

parse_common_args "$@"

DBGEN_DIR="${REPO_ROOT}/dbgen"
if [[ ! -x "${DBGEN_DIR}/dbgen" ]]; then
    cat >&2 <<EOF
[ERROR] dbgen binary not found at ${DBGEN_DIR}/dbgen

Build it first:
    cd dbgen && make
(or drop a prebuilt binary + dists.dss there)
EOF
    exit 1
fi

mkdir -p "${DATA_DIR}"

log "Generating TPC-H scale=${SCALE} data into ${DATA_DIR}"
pushd "${DBGEN_DIR}" >/dev/null
./dbgen -f -s "${SCALE}"
mv ./*.tbl "${DATA_DIR}/"
popd >/dev/null

log "Done. Files:"
ls -lh "${DATA_DIR}"/*.tbl
