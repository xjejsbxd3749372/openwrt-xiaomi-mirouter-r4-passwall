#!/usr/bin/env bash

set -euo pipefail

FEEDS_FILE="feeds.conf.default"

# Latest PassWall UI is tracked from main. Xray is packaged separately as the
# current MIPS32 little-endian release binary from diy-part2.sh, which avoids
# forcing a modern Go toolchain into the OpenWrt 19.07 build system.
XRAY_VERSION="26.9.9"
XRAY_ASSET="Xray-linux-mips32le.zip"
XRAY_SHA256="e572d2cdd819318383460443140898e6117e8e0da5f0c359b25f6c890b8d81a2"

[ -f "${FEEDS_FILE}" ] || {
    echo "ERROR: ${FEEDS_FILE} not found"
    exit 1
}

add_feed() {
    local line="$1"

    if ! grep -Fqx "${line}" "${FEEDS_FILE}"; then
        printf '%s\n' "${line}" >> "${FEEDS_FILE}"
    fi
}

# ---------------------------------------------------------------------------
# PassWall
# ---------------------------------------------------------------------------

add_feed "src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main"
add_feed "src-git passwall_luci https://github.com/Openwrt-Passwall/openwrt-passwall.git;main"

echo "===== PassWall ====="
git ls-remote https://github.com/Openwrt-Passwall/openwrt-passwall.git     refs/heads/main | head -n 1 || true

echo "===== PassWall Packages ====="
git ls-remote https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git     refs/heads/main | head -n 1 || true

echo "===== Xray release ====="
echo "version=${XRAY_VERSION}"
echo "asset=${XRAY_ASSET}"
echo "sha256=${XRAY_SHA256}"

echo "===== Sing-box upstream (informational only) ====="
git ls-remote https://github.com/SagerNet/sing-box.git     refs/heads/main | head -n 1 || true

echo "===== Domain rules (informational only) ====="
git ls-remote https://github.com/v2fly/domain-list-community.git     refs/heads/master | head -n 1 || true

echo "===== GeoIP rules (informational only) ====="
git ls-remote https://github.com/v2fly/geoip.git     refs/heads/master | head -n 1 || true

# Xray is not built from current Go source on OpenWrt 19.07. The MIPS32LE
# release binary is installed by diy-part2.sh.
# Sing-box is deliberately excluded from the 128 MiB target.

echo "===== feeds.conf.default ====="
grep -E 'passwall_packages|passwall_luci' "${FEEDS_FILE}"

echo "diy-part1.sh completed."
