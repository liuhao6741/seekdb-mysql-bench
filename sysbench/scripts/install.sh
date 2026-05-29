#!/usr/bin/env bash
# Build & install sysbench 1.0.20 from source.
# Mirrors the manual steps:
#   wget .../1.0.20.tar.gz && tar zxvf ... && cd && ./autogen.sh
#   ./configure --prefix=/usr/sysbench --with-mysql
#   make && make install
#   cp share/sysbench/* bin/
#
# Usage:
#   sudo ./scripts/install.sh
#   sudo PREFIX=/opt/sysbench ./scripts/install.sh

set -euo pipefail

VERSION="${VERSION:-1.0.20}"
PREFIX="${PREFIX:-/usr/sysbench}"
MYSQL_INCLUDES="${MYSQL_INCLUDES:-/usr/include/mysql/}"
MYSQL_LIBS="${MYSQL_LIBS:-/usr/lib64/mysql/}"
BUILD_DIR="${BUILD_DIR:-/tmp/sysbench-build}"
TARBALL_URL="https://github.com/akopytov/sysbench/archive/refs/tags/${VERSION}.tar.gz"

log() { echo "[$(date '+%F %T')] $*"; }

# Best-effort dependency hint (does not auto-install — distro-specific).
cat <<'EOF'
[INFO] Build dependencies (install manually if missing):
  RHEL/Anolis/CentOS:
    sudo yum install -y make automake libtool pkgconfig libaio-devel \
        openssl-devel mysql-devel
  Debian/Ubuntu:
    sudo apt install -y make automake libtool pkg-config libaio-dev \
        libssl-dev libmysqlclient-dev
EOF

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

TARBALL="sysbench-${VERSION}.tar.gz"
if [[ ! -f "${TARBALL}" ]]; then
    log "Downloading ${TARBALL_URL}"
    wget -O "${TARBALL}" "${TARBALL_URL}"
fi

SRC_DIR="sysbench-${VERSION}"
if [[ ! -d "${SRC_DIR}" ]]; then
    log "Extracting ${TARBALL}"
    tar -zxvf "${TARBALL}"
fi

cd "${SRC_DIR}"
log "Running autogen.sh"
./autogen.sh

log "Configuring (prefix=${PREFIX})"
./configure --prefix="${PREFIX}" \
    --with-mysql-includes="${MYSQL_INCLUDES}" \
    --with-mysql-libs="${MYSQL_LIBS}" \
    --with-mysql

log "make"
make -j "$(nproc)"

log "make install"
make install

# Copy the bundled lua tests next to the binary so workloads like oltp_read_write
# can be referenced by short name without -L paths.
if [[ -d "${PREFIX}/share/sysbench" ]]; then
    log "Copying lua tests into ${PREFIX}/bin"
    cp -r "${PREFIX}/share/sysbench/"* "${PREFIX}/bin/"
fi

log "Verifying:"
"${PREFIX}/bin/sysbench" --version

cat <<EOF

[OK] sysbench installed at ${PREFIX}/bin/sysbench
Consider adding it to PATH:
    export PATH=${PREFIX}/bin:\$PATH
EOF
