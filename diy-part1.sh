#!/usr/bin/env bash
set -euo pipefail

FEEDS_FILE="feeds.conf.default"
PASSWALL_UI_URL="https://github.com/Openwrt-Passwall/openwrt-passwall.git"
PASSWALL_PACKAGES_URL="https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git"

[ -f "${FEEDS_FILE}" ] || {
    echo "ERROR: ${FEEDS_FILE} not found"
    exit 1
}

add_feed() {
    local line="$1"
    if ! grep -Fqx "${line}" "${FEEDS_FILE}"; then
        printf "%s\n" "${line}" >> "${FEEDS_FILE}"
    fi
}

# PassWall main tracks the current 26.x line.  Do not pin it to an old release.
add_feed "src-git passwall_packages ${PASSWALL_PACKAGES_URL};main"
add_feed "src-git passwall_luci ${PASSWALL_UI_URL};main"

echo "===== PassWall upstream ====="
git ls-remote "${PASSWALL_UI_URL}" refs/heads/main | head -n 1
echo "===== PassWall packages upstream ====="
git ls-remote "${PASSWALL_PACKAGES_URL}" refs/heads/main | head -n 1

echo "===== Required core versions ====="
echo "PassWall: main (26.x)"
echo "Xray: 26.9.9 official MIPS32LE binary"
echo "sing-box: current 1.14.x PassWall package"
echo "SSR: current 2.5.6 PassWall package"
echo "hysteria: current PassWall package"

grep -E "passwall_packages|passwall_luci" "${FEEDS_FILE}"
echo "diy-part1.sh completed."
