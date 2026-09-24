#!/usr/bin/env bash
set -euo pipefail

# Base: last good full diy without requiring host-cargo rust binaries.
# Then inject naiveproxy + ensure rust dirs do not block the build.
ROOT_DIR="$(pwd)"
BASE_COMMIT="f4506d60f3ccd13f0977e4956315ccb3527b6907"
BASE_URL="https://raw.githubusercontent.com/xjejsbxd3749372/openwrt-xiaomi-mirouter-r4-passwall/${BASE_COMMIT}/diy-part2.sh"

# Provide dummy paths so base script's PREBUILT_SSLOCAL/SHADOW_TLS checks can be patched out
export PREBUILT_SINGBOX="${PREBUILT_SINGBOX:-${GITHUB_WORKSPACE:-}/prebuilt/sing-box}"
export PREBUILT_NAIVEPROXY="${PREBUILT_NAIVEPROXY:-${GITHUB_WORKSPACE:-}/prebuilt/naiveproxy}"
export SINGBOX_VERSION="${SINGBOX_VERSION:-1.14.1}"
export NAIVEPROXY_VERSION="${NAIVEPROXY_VERSION:-v150.0.7871.63-1}"

curl -fsSL "${BASE_URL}" -o /tmp/diy-part2-base.sh

# Neutralize rust binary hard-requirements in the base script
sed -i \
  -e '/prebuilt sslocal not found/d' \
  -e '/prebuilt shadow-tls not found/d' \
  -e 's|if \[ ! -f "${PREBUILT_SSLOCAL}" \]; then|if false; then|' \
  -e 's|if \[ ! -f "${PREBUILT_SHADOW_TLS}" \]; then|if false; then|' \
  /tmp/diy-part2-base.sh

# Skip entire sslocal / shadow-tls package generation blocks by making PREBUILT paths empty checks fail soft
# Replace package sections 12-13 with no-ops via env so missing files do not abort when we guard differently:
# Simpler: create empty skip and comment out by wrapping - run a filtered version

python3 - <<'PY'
from pathlib import Path
p = Path('/tmp/diy-part2-base.sh')
s = p.read_text()
# Remove sections 12 and 13 (shadowsocks-rust / shadow-tls package writes)
import re
s2 = re.sub(
    r'# ={10,}\n# 12\. shadowsocks-rust.*?\n# ={10,}\n# 13\. shadow-tls prebuilt.*?\n# ={10,}\n# 14\. Sanity',
    '# === rust packages skipped (no host mipsel cargo) ===\n# ===========================================================================\n# 14. Sanity',
    s,
    count=1,
    flags=re.S,
)
if s2 == s:
    # fallback line-based cut between markers
    lines = s.splitlines(True)
    out = []
    skip = False
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
# also drop checks for SSRUST_DIR / STLS_DIR makefiles
s2 = s2.replace('[ -f "${SSRUST_DIR}/Makefile" ]\n', '')
s2 = s2.replace('[ -f "${STLS_DIR}/Makefile" ]\n', '')
p.write_text(s2)
print('base script patched')
PY

bash /tmp/diy-part2-base.sh

# ---------------------------------------------------------------------------
# Official naiveproxy → package (binary "ipk" style install into rootfs)
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

# Remove any feed naiveproxy that needs source/chromium build
rm -rf "${PW_PKGS}/naiveproxy" "${PW_PKGS}/shadowsocks-rust" "${PW_PKGS}/shadow-tls"

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

echo "naiveproxy binary package ready; rust packages removed from feeds"
