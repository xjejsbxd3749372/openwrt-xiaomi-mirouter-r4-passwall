#!/usr/bin/env bash
set -euo pipefail

# Base: last good full diy without requiring host-cargo rust binaries.
# Then inject naiveproxy + purge rust/host deps (OpenWrt 19.07 has no rust feed).
ROOT_DIR="$(pwd)"
BASE_COMMIT="f4506d60f3ccd13f0977e4956315ccb3527b6907"
BASE_URL="https://raw.githubusercontent.com/xjejsbxd3749372/openwrt-xiaomi-mirouter-r4-passwall/${BASE_COMMIT}/diy-part2.sh"

export PREBUILT_SINGBOX="${PREBUILT_SINGBOX:-${GITHUB_WORKSPACE:-}/prebuilt/sing-box}"
export PREBUILT_NAIVEPROXY="${PREBUILT_NAIVEPROXY:-${GITHUB_WORKSPACE:-}/prebuilt/naiveproxy}"
export SINGBOX_VERSION="${SINGBOX_VERSION:-1.14.1}"
export NAIVEPROXY_VERSION="${NAIVEPROXY_VERSION:-v150.0.7871.63-1}"

curl -fsSL "${BASE_URL}" -o /tmp/diy-part2-base.sh

sed -i \
  -e '/prebuilt sslocal not found/d' \
  -e '/prebuilt shadow-tls not found/d' \
  -e 's|if \[ ! -f "${PREBUILT_SSLOCAL}" \]; then|if false; then|' \
  -e 's|if \[ ! -f "${PREBUILT_SHADOW_TLS}" \]; then|if false; then|' \
  /tmp/diy-part2-base.sh

python3 - <<'PY'
from pathlib import Path
import re
p = Path('/tmp/diy-part2-base.sh')
s = p.read_text()
s2 = re.sub(
    r'# ={10,}\n# 12\. shadowsocks-rust.*?\n# ={10,}\n# 13\. shadow-tls prebuilt.*?\n# ={10,}\n# 14\. Sanity',
    '# === rust packages skipped ===\n# ===========================================================================\n# 14. Sanity',
    s, count=1, flags=re.S,
)
if s2 == s:
    lines = s.splitlines(True)
    out, skip = [], False
    for line in lines:
        if '12. shadowsocks-rust' in line:
            skip = True
            out.append('# skipped section 12-13 rust packages\n')
            continue
        if skip and ('14. Sanity' in line or '15. Sanity' in line):
            skip = False
        if not skip:
            out.append(line)
    s2 = ''.join(out)
s2 = s2.replace('[ -f "${SSRUST_DIR}/Makefile" ]\n', '')
s2 = s2.replace('[ -f "${STLS_DIR}/Makefile" ]\n', '')
p.write_text(s2)
print('base script patched')
PY

bash /tmp/diy-part2-base.sh

# ---------------------------------------------------------------------------
# Kill rust/host dependency warnings on OpenWrt 19.07 (method 1)
# ---------------------------------------------------------------------------
# 1) Delete packages that require rustc in buildroot
# 2) Strip PKG_BUILD_DEPENDS:=rust/host from any remaining Makefiles
for base in \
  "${ROOT_DIR}/package/feeds/passwall_packages" \
  "${ROOT_DIR}/feeds/passwall_packages" \
  "${ROOT_DIR}/package/feeds/packages" \
  "${ROOT_DIR}/feeds/packages"
do
  [ -d "${base}" ] || continue
  for rust_pkg in shadowsocks-rust shadow-tls; do
    if [ -d "${base}/${rust_pkg}" ]; then
      echo "Removing ${base}/${rust_pkg} (needs rust/host, not on 19.07)"
      rm -rf "${base}/${rust_pkg}"
    fi
  done
  # strip dependency line everywhere under this tree
  find "${base}" -name Makefile -type f -print0 2>/dev/null | while IFS= read -r -d '' mk; do
    if grep -q 'rust/host' "${mk}" 2>/dev/null; then
      echo "Stripping rust/host from ${mk}"
      sed -i \
        -e 's/PKG_BUILD_DEPENDS:=rust\/host//g' \
        -e 's/+rust\/host//g' \
        -e 's/rust\/host//g' \
        "${mk}" || true
    fi
  done
done

# Also strip from luci-app-passwall selects if present
PASSWALL_MK="${ROOT_DIR}/package/feeds/passwall_luci/luci-app-passwall/Makefile"
if [ -f "${PASSWALL_MK}" ]; then
  sed -i \
    -e '/select PACKAGE_shadowsocks-rust/d' \
    -e '/select PACKAGE_shadow-tls/d' \
    -e '/select PACKAGE_Shadowsocks_Rust/d' \
    "${PASSWALL_MK}" || true
fi

# ---------------------------------------------------------------------------
# Official naiveproxy → binary package into rootfs (ipk-style)
# ---------------------------------------------------------------------------
PASSWALL_PACKAGES="${ROOT_DIR}/package/feeds/passwall_packages"
PASSWALL_PACKAGES_ALT="${ROOT_DIR}/feeds/passwall_packages"
PW_PKGS=""
for d in "${PASSWALL_PACKAGES}" "${PASSWALL_PACKAGES_ALT}"; do
  if [ -d "${d}" ]; then
    PW_PKGS="${d}"
    break
  fi
done

if [ -z "${PW_PKGS}" ]; then
  echo "ERROR: passwall_packages not found after base diy-part2"
  exit 1
fi

if [ ! -f "${PREBUILT_NAIVEPROXY}" ]; then
  echo "ERROR: prebuilt naiveproxy missing at ${PREBUILT_NAIVEPROXY}"
  exit 1
fi

rm -rf "${PW_PKGS}/naiveproxy"
NAIVE_DIR="${PW_PKGS}/naiveproxy"
mkdir -p "${NAIVE_DIR}/files"
cp -a "${PREBUILT_NAIVEPROXY}" "${NAIVE_DIR}/files/naiveproxy"
chmod +x "${NAIVE_DIR}/files/naiveproxy"

cat > "${NAIVE_DIR}/Makefile" <<EOF
include \$(TOPDIR)/rules.mk

PKG_NAME:=naiveproxy
PKG_VERSION:=${NAIVEPROXY_VERSION}
PKG_RELEASE:=1

PKG_LICENSE:=BSD-3-Clause
PKGARCH:=mipsel_24kc

include \$(INCLUDE_DIR)/package.mk

define Package/naiveproxy
  SECTION:=net
  CATEGORY:=Network
  TITLE:=naiveproxy (official mipsel_24kc static)
  URL:=https://github.com/klzgrad/naiveproxy
  DEPENDS:=+ca-bundle
endef

define Package/naiveproxy/description
  Official klzgrad naiveproxy static binary, installed like an ipk into rootfs.
endef

define Build/Prepare
	mkdir -p \$(PKG_BUILD_DIR)
	cp -a ./files/naiveproxy \$(PKG_BUILD_DIR)/naiveproxy
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/naiveproxy/install
	\$(INSTALL_DIR) \$(1)/usr/bin
	\$(INSTALL_BIN) \$(PKG_BUILD_DIR)/naiveproxy \$(1)/usr/bin/naiveproxy
endef

\$(eval \$(call BuildPackage,naiveproxy))
EOF

echo "============================================================"
echo "rust/host warnings: fixed by removing ss-rust/shadow-tls + sed"
echo "naiveproxy binary package ready"
echo "============================================================"
