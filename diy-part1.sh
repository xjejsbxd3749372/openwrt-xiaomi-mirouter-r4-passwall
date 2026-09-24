#!/usr/bin/env bash
set -euo pipefail

# OpenWrt 19.07 + fw876/helloworld
# Method 1 from upstream README: clone directly into package/helloworld.
# OpenWrt <= 21.02 also needs a newer Golang toolchain for Xray.

ROOT_DIR="$(pwd)"
HELLOWORLD_DIR="${ROOT_DIR}/package/helloworld"
GO_OVERLAY_DIR="/tmp/openwrt-packages-2305"
GO_VERSION_BRANCH="openwrt-23.05"

command -v git >/dev/null 2>&1 || {
    echo "ERROR: git is required"
    exit 1
}
command -v clang >/dev/null 2>&1 || {
    echo "ERROR: clang is required. Install clang before building helloworld."
    exit 1
}

echo "===== Clone fw876/helloworld (Method 1) ====="
rm -rf "${HELLOWORLD_DIR}"
git clone --depth=1 https://github.com/fw876/helloworld.git "${HELLOWORLD_DIR}"

echo "===== helloworld revision ====="
git -C "${HELLOWORLD_DIR}" rev-parse HEAD
git -C "${HELLOWORLD_DIR}" log -1 --oneline

echo "===== Upgrade Golang toolchain for OpenWrt 19.07 ====="
rm -rf "${GO_OVERLAY_DIR}"
git clone --depth=1 --filter=blob:none --sparse \
    --branch "${GO_VERSION_BRANCH}" \
    https://github.com/openwrt/packages.git "${GO_OVERLAY_DIR}"

git -C "${GO_OVERLAY_DIR}" sparse-checkout set lang/golang

# helloworld's Xray/Hysteria Makefiles include:
#   feeds/packages/lang/golang/golang-package.mk
# Therefore replace only the Golang toolchain subtree, not the whole packages feed.
if [ ! -f "${GO_OVERLAY_DIR}/lang/golang/golang-package.mk" ]; then
    echo "ERROR: Golang package files were not found in ${GO_VERSION_BRANCH}"
    exit 1
fi

rm -rf "${ROOT_DIR}/feeds/packages/lang/golang"
mkdir -p "${ROOT_DIR}/feeds/packages/lang"
cp -a "${GO_OVERLAY_DIR}/lang/golang" "${ROOT_DIR}/feeds/packages/lang/golang"

echo "===== Golang package source ====="
grep -E '^(PKG_NAME|PKG_VERSION|GO_VERSION|GO_HASH)' \
    "${ROOT_DIR}/feeds/packages/lang/golang/golang/Makefile" \
    "${ROOT_DIR}/feeds/packages/lang/golang/golang-values.mk" 2>/dev/null || true

echo "===== Required helloworld packages ====="
for p in \
    luci-app-ssr-plus \
    xray-core \
    shadowsocksr-libev \
    shadowsocks-libev \
    hysteria
do
    test -f "${HELLOWORLD_DIR}/${p}/Makefile" || {
        echo "ERROR: helloworld package missing: ${p}"
        exit 1
    }
done

echo "diy-part1.sh completed."
