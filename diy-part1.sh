#!/usr/bin/env bash

set -euo pipefail

FEEDS_FILE="feeds.conf.default"

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

# ---------------------------------------------------------------------------
# PassWall 相关核心与规则源检查
#
# 实际 package recipe 由 passwall_packages feed 提供，避免把上游 Xray /
# Sing-box 直接复制到 package/ 目录造成重复 PACKAGE 定义。
#
# 这里使用 git ls-remote 获取最新提交信息，同时不把庞大的上游源码
# 额外塞进固件源码树。
# ---------------------------------------------------------------------------

echo "===== PassWall ====="
git ls-remote https://github.com/Openwrt-Passwall/openwrt-passwall.git \
    refs/heads/main | head -n 1 || true

echo "===== PassWall Packages ====="
git ls-remote https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git \
    refs/heads/main | head -n 1 || true

echo "===== Xray upstream ====="
git ls-remote https://github.com/XTLS/Xray-core.git \
    refs/heads/main | head -n 1 || true

echo "===== Sing-box upstream ====="
git ls-remote https://github.com/SagerNet/sing-box.git \
    refs/heads/main | head -n 1 || true

echo "===== Domain rules ====="
git ls-remote https://github.com/v2fly/domain-list-community.git \
    refs/heads/master | head -n 1 || true

echo "===== GeoIP rules ====="
git ls-remote https://github.com/v2fly/geoip.git \
    refs/heads/master | head -n 1 || true

# ---------------------------------------------------------------------------
# 说明：
# 1. 最新 PassWall UI 使用 main。
# 2. Xray / Sing-box 不在这里单独 clone 到 OpenWrt package 目录。
# 3. PassWall 的规则集不直接嵌入固件，避免固件膨胀；运行时由 PassWall
#    按需更新。
# ---------------------------------------------------------------------------

echo "===== feeds.conf.default ====="
grep -E 'passwall_packages|passwall_luci' "${FEEDS_FILE}"

echo "diy-part1.sh completed."
