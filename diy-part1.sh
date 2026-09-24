#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(pwd)"
HELLOWORLD_DIR="${ROOT_DIR}/package/helloworld"
COMPAT23="/tmp/openwrt-packages-2305"
MODERN="/tmp/openwrt-packages-modern"
GOLANG27="/tmp/packages-lang-golang-27"
KCPTUN="/tmp/openwrt-kcptun"
LUCI19="/tmp/openwrt-luci-1907"

command -v git >/dev/null 2>&1
command -v clang >/dev/null 2>&1 || {
    echo "ERROR: clang is required by fw876/helloworld"
    exit 1
}

rm -rf "${HELLOWORLD_DIR}"
git clone https://github.com/fw876/helloworld.git "${HELLOWORLD_DIR}"

rm -rf "${COMPAT23}" "${MODERN}" "${GOLANG27}" "${KCPTUN}" "${LUCI19}"

git clone --branch openwrt-23.05 https://github.com/openwrt/packages.git "${COMPAT23}"
git clone --branch openwrt-19.07 https://github.com/openwrt/packages.git "${MODERN}"
git clone --branch 27.x https://github.com/sbwml/packages_lang_golang.git "${GOLANG27}"
git clone https://github.com/kuoruan/openwrt-kcptun.git "${KCPTUN}"
git clone --branch openwrt-19.07 https://github.com/openwrt/luci.git "${LUCI19}"

feed_line() {
    local name="$1"
    local path="$2"
    grep -q "^src-link ${name} " feeds.conf.default 2>/dev/null || echo "src-link ${name} ${path}" >> feeds.conf.default
}

feed_line compat23 "${COMPAT23}"
feed_line modern "${MODERN}"
feed_line golang27 "${GOLANG27}"
feed_line kcptun "${KCPTUN}"
feed_line luci19 "${LUCI19}"

./scripts/feeds update compat23 modern golang27 kcptun luci19

./scripts/feeds install golang -p golang27 -f
./scripts/feeds install rust -p compat23
./scripts/feeds install luarocks lyaml -p modern
./scripts/feeds install csstidy -p compat23
./scripts/feeds install kcptun-client kcptun-server -p kcptun
./scripts/feeds install luci-compat -p luci19 || ./scripts/feeds install luci-compat -p luci

for p in coreutils coreutils-base64 jq bind-dig nping unzip xz-utils xz; do
    ./scripts/feeds install "${p}" -p compat23 || ./scripts/feeds install "${p}" -p modern || true
done

./scripts/feeds install luci-app-ssr-plus xray-core hysteria shadowsocksr-libev shadowsocks-libev -p helloworld -f

test -f "${ROOT_DIR}/feeds/golang27/golang/Makefile"
test -f "${ROOT_DIR}/feeds/golang27/golang/golang-package.mk"
test -f "${ROOT_DIR}/feeds/compat23/rust/Makefile"
test -f "${ROOT_DIR}/feeds/compat23/rust/rust-package.mk"
test -f "${ROOT_DIR}/feeds/modern/lyaml/Makefile"
test -f "${ROOT_DIR}/feeds/kcptun/kcptun-client/Makefile"
test -f "${HELLOWORLD_DIR}/luci-app-ssr-plus/Makefile"
test -f "${HELLOWORLD_DIR}/xray-core/Makefile"

