#!/usr/bin/env bash
set -euo pipefail

# Restore last known-good diy-part2 (pre-PLACEHOLDER), then inject naiveproxy package.
ROOT_DIR="$(pwd)"
BASE_COMMIT="f4506d60f3ccd13f0977e4956315ccb3527b6907"
BASE_URL="https://raw.githubusercontent.com/xjejsbxd3749372/openwrt-xiaomi-mirouter-r4-passwall/${BASE_COMMIT}/diy-part2.sh"

curl -fsSL "${BASE_URL}" -o /tmp/diy-part2-base.sh
bash /tmp/diy-part2-base.sh

# ---------------------------------------------------------------------------
# Official klzgrad naiveproxy mipsel_24kc-static (~3MB)
# ---------------------------------------------------------------------------
PREBUILT_NAIVEPROXY="${PREBUILT_NAIVEPROXY:-${GITHUB_WORKSPACE:-}/prebuilt/naiveproxy}"
NAIVEPROXY_VERSION="${NAIVEPROXY_VERSION:-v150.0.7871.63-1}"

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
  echo "Workflow must run scripts/fetch-naiveproxy.sh first."
  exit 1
fi

NAIVE_DIR="${PW_PKGS}/naiveproxy"
rm -rf "${NAIVE_DIR}"
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
  Official klzgrad naiveproxy ${NAIVEPROXY_VERSION} openwrt-mipsel_24kc-static (~3MB).
  Fully static; suitable for OpenWrt 19.07 musl.
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

echo "naiveproxy package injected: ${NAIVE_DIR}"
