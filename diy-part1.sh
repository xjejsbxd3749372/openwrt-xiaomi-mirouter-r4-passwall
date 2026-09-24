#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(pwd)"
HELLOWORLD_DIR="${ROOT_DIR}/package/helloworld"

command -v git >/dev/null 2>&1
command -v clang >/dev/null 2>&1 || {
    echo "ERROR: clang is required by fw876/helloworld"
    exit 1
}

rm -rf "${HELLOWORLD_DIR}"
git clone --depth=1 https://github.com/fw876/helloworld.git "${HELLOWORLD_DIR}"

# OpenWrt 19.07 cannot parse current packages feeds. Keep only the local
# helloworld feed; the selected SSR Plus+ packages are discovered directly
# from package/helloworld by the build system.
sed -i '/^src-link \(compat23\|modern\|golang27\|kcptun\|luci19\) /d' feeds.conf.default

# These packages belong to newer dependency stacks and are not required by
# the selected SSR Plus+ configuration on OpenWrt 19.07.
sed -i '/^CONFIG_PACKAGE_rust=/d; /^CONFIG_PACKAGE_lyaml=/d' "${GITHUB_WORKSPACE:-${ROOT_DIR}}/.config" 2>/dev/null || true

test -f "${HELLOWORLD_DIR}/luci-app-ssr-plus/Makefile"
test -f "${HELLOWORLD_DIR}/xray-core/Makefile"
