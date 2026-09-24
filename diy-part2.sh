#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(pwd)"
HELLOWORLD_DIR="${ROOT_DIR}/package/helloworld"

test -d "${HELLOWORLD_DIR}" || {
    echo "ERROR: package/helloworld does not exist"
    exit 1
}

echo "===== MIR4 + helloworld compatibility checks ====="

# Do not modify helloworld's dependency graph. In particular, do not inject
# PassWall, lyaml, sing-box, shadow-tls, or shadowsocks-rust dependencies.
#
# helloworld upstream already provides:
#   luci-app-ssr-plus
#   xray-core
#   shadowsocksr-libev
#   shadowsocks-libev
#   hysteria
#
# Xray/Hysteria use feeds/packages/lang/golang/golang-package.mk, which
# diy-part1.sh replaced with the OpenWrt 23.05-era Golang toolchain.

for p in \
    luci-app-ssr-plus \
    xray-core \
    shadowsocksr-libev \
    shadowsocks-libev \
    hysteria
do
    test -f "${HELLOWORLD_DIR}/${p}/Makefile" || {
        echo "ERROR: missing helloworld package: ${p}"
        exit 1
    }
done

# OpenWrt 19.07 uses iptables; explicitly select the SSR Plus iptables backend.
grep -q 'CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Xray' \
    "${HELLOWORLD_DIR}/luci-app-ssr-plus/Makefile"

# Keep the MIR4 firmware small. No PassWall/Rust/sing-box packages are added.
echo "helloworld packages:"
find "${HELLOWORLD_DIR}" -maxdepth 2 -name Makefile | sort

echo "diy-part2.sh completed."
