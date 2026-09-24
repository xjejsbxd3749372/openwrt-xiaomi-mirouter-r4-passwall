#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(pwd)"

DTS_FILE="${ROOT_DIR}/target/linux/ramips/dts/MIR4.dts"
IMAGE_MK="${ROOT_DIR}/target/linux/ramips/image/mt7621.mk"
NETWORK_FILE="${ROOT_DIR}/target/linux/ramips/base-files/etc/board.d/02_network"
PLATFORM_FILE="${ROOT_DIR}/target/linux/ramips/base-files/lib/upgrade/platform.sh"
UBOOTENV_FILE="${ROOT_DIR}/package/boot/uboot-envtools/files/ramips"

PASSWALL_MK="${ROOT_DIR}/package/feeds/passwall_luci/luci-app-passwall/Makefile"
PASSWALL_PACKAGES="${ROOT_DIR}/package/feeds/passwall_packages"
PASSWALL_PACKAGES_ALT="${ROOT_DIR}/feeds/passwall_packages"
GOLANG_DIR="${ROOT_DIR}/feeds/packages/lang/golang"
KERNEL_NETSUPPORT_MK="${ROOT_DIR}/package/kernel/linux/modules/netsupport.mk"

PREBUILT_SINGBOX="${PREBUILT_SINGBOX:-${GITHUB_WORKSPACE:-}/prebuilt/sing-box}"
SINGBOX_VERSION="${SINGBOX_VERSION:-1.14.1}"

mkdir -p \
  "$(dirname "${DTS_FILE}")" \
  "$(dirname "${IMAGE_MK}")" \
  "$(dirname "${NETWORK_FILE}")" \
  "$(dirname "${PLATFORM_FILE}")" \
  "$(dirname "${UBOOTENV_FILE}")"

# ============================================================================
# 1. MIR4 DTS
# ============================================================================
cat > "${DTS_FILE}" <<'EOF'
/dts-v1/;

#include "mt7621.dtsi"
#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/input/input.h>

/ {
	compatible = "xiaomi,mir4", "mediatek,mt7621-soc";
	model = "Xiaomi Mi Router 4";

	aliases {
		led-boot = &led_status_yellow;
		led-failsafe = &led_status_red;
		led-running = &led_status_blue;
		led-upgrade = &led_status_yellow;
	};

	memory@0 {
		device_type = "memory";
		reg = <0x0 0x8000000>;
	};

	chosen {
		bootargs = "console=ttyS0,115200n8";
	};

	leds {
		compatible = "gpio-leds";

		led_status_red: status_red {
			label = "mir4:red:status";
			gpios = <&gpio0 6 GPIO_ACTIVE_LOW>;
		};

		led_status_blue: status_blue {
			label = "mir4:blue:status";
			gpios = <&gpio0 8 GPIO_ACTIVE_LOW>;
		};

		led_status_yellow: status_yellow {
			label = "mir4:yellow:status";
			gpios = <&gpio0 10 GPIO_ACTIVE_LOW>;
		};
	};

	button {
		compatible = "gpio-keys-polled";
		poll-interval = <20>;

		reset {
			label = "reset";
			gpios = <&gpio0 18 GPIO_ACTIVE_LOW>;
			linux,code = <KEY_RESTART>;
		};

		minet {
			label = "minet";
			gpios = <&gpio0 12 GPIO_ACTIVE_LOW>;
			linux,code = <KEY_WPS_BUTTON>;
		};
	};
};

&nand {
	status = "okay";

	partitions {
		compatible = "fixed-partitions";
		#address-cells = <1>;
		#size-cells = <1>;

		partition@0 {
			label = "Bootloader";
			reg = <0x0 0x80000>;
			read-only;
		};

		partition@80000 {
			label = "Config";
			reg = <0x80000 0x40000>;
		};

		partition@c0000 {
			label = "Bdata";
			reg = <0xc0000 0x40000>;
			read-only;
		};

		factory: partition@100000 {
			label = "Factory";
			reg = <0x100000 0x40000>;
			read-only;
		};

		partition@140000 {
			label = "crash";
			reg = <0x140000 0x40000>;
		};

		partition@180000 {
			label = "crash_syslog";
			reg = <0x180000 0x40000>;
		};

		partition@1c0000 {
			label = "reserved0";
			reg = <0x1c0000 0x40000>;
			read-only;
		};

		partition@200000 {
			label = "kernel_stock";
			reg = <0x200000 0x400000>;
		};

		partition@600000 {
			label = "kernel";
			reg = <0x600000 0x400000>;
		};

		partition@a00000 {
			label = "ubi";
			reg = <0xa00000 0x7580000>;
		};
	};
};

&pcie {
	status = "okay";
};

&pcie0 {
	wifi@0,0 {
		compatible = "pci14c3,7603";
		reg = <0x0000 0 0 0 0>;
		mediatek,mtd-eeprom = <&factory 0x0000>;
		ieee80211-freq-limit = <2400000 2500000>;
	};
};

&pcie1 {
	wifi@0,0 {
		compatible = "pci14c3,7662";
		reg = <0x0000 0 0 0 0>;
		mediatek,mtd-eeprom = <&factory 0x8000>;
		ieee80211-freq-limit = <5000000 6000000>;
	};
};

&ethernet {
	mtd-mac-address = <&factory 0xe000>;
	mediatek,portmap = "llllw";
};

&pinctrl {
	state_default: pinctrl0 {
		gpio {
			ralink,group = "jtag", "uart2", "uart3", "wdt";
			ralink,function = "gpio";
		};
	};
};
EOF

# ============================================================================
# 2. MIR4 image profile
# ============================================================================
python3 - "${IMAGE_MK}" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text()

s = re.sub(r'define Device/(?:mir4|xiaomi_mir4)\n.*?endef\nTARGET_DEVICES \+= (?:mir4|xiaomi_mir4)\n', '', s, flags=re.S)
anchor = 'TARGET_DEVICES += xiaomi_mir3g\n'
if anchor not in s:
    raise SystemExit('ERROR: xiaomi_mir3g image profile anchor not found')

block = r'''define Device/xiaomi_mir4
  DTS := MIR4
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_SIZE := 4096k
  IMAGE_SIZE := 32768k
  UBINIZE_OPTS := -E 5
  BOARD_NAME := mir4
  IMAGES += kernel1.bin rootfs0.bin
  IMAGE/kernel1.bin := append-kernel
  IMAGE/rootfs0.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  DEVICE_TITLE := Xiaomi Mi Router 4
  DEVICE_PACKAGES := \
	kmod-mt7603 kmod-mt76x2 wpad-basic uboot-envtools
endef
TARGET_DEVICES += xiaomi_mir4

'''
s = s.replace(anchor, anchor + '\n' + block, 1)
p.write_text(s)
PY

# ============================================================================
# 3. 02_network
# ============================================================================
python3 - "${NETWORK_FILE}" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text()

s = re.sub(r'\txiaomi,mir4\)\n\t\tucidef_add_switch "switch0" \\\n(?:\t\t\t".*?"\s*)+\n\t\t;;\n', '', s)

anchor = '\txiaomi,mir3p)\n\t\tucidef_add_switch "switch0" \\\n\t\t\t"1:lan:3" "2:lan:2" "3:lan:1" "4:wan" "6@eth0"\n\t\t;;\n'
if anchor not in s:
    alt_anchor = '\txiaomi,mir3g)\n\t\tucidef_add_switch "switch0" \\\n\t\t\t"1:lan:3" "2:lan:2" "3:lan:1" "4:wan" "6@eth0"\n\t\t;;\n'
    if alt_anchor not in s:
        raise SystemExit('ERROR: xiaomi,mir3p network anchor not found')
    s = s.replace(alt_anchor, anchor, 1)

block = '''\txiaomi,mir4)
\t\tucidef_add_switch "switch0" \\
\t\t\t"1:lan:2" "2:lan:1" "4:wan" "6t@eth0"
\t\t;;
'''
s = s.replace(anchor, anchor + block, 1)

s = re.sub(r'\txiaomi,mir3g\|\\\n\txiaomi,mir3p\|\\\n\txiaomi,mir4\)\n\t\tlan_mac=.*?\n\t\t;;\n',
           '\txiaomi,mir3g|\\\n\txiaomi,mir3p|\\\n\txiaomi,mir4)\n\t\tlan_mac=$(mtd_get_mac_binary Factory 0xe006)\n\t\t;;\n',
           s, count=1)

p.write_text(s)
PY

# ============================================================================
# 4. NAND upgrade path
# ============================================================================
python3 - "${PLATFORM_FILE}" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text()

if 'xiaomi,mir4)' not in s:
    patterns = [
        r'(xiaomi,mir3p\|\\\n\txiaomi,mir3g\))',
        r'(xiaomi,mir3g\|\\\n\txiaomi,mir3p\))',
    ]
    for pattern in patterns:
        if re.search(pattern, s):
            s = re.sub(pattern, lambda m: m.group(1)[:-1] + '|\\\n\txiaomi,mir4)', s, count=1)
            break
    else:
        raise SystemExit('ERROR: OpenWrt 19.07 Xiaomi NAND case not found')

p.write_text(s)
PY

# ============================================================================
# 5. U-Boot envtools
# ============================================================================
python3 - "${UBOOTENV_FILE}" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text()

if 'xiaomi,mir4)' not in s:
    patterns = [
        r'(xiaomi,mir3p\|\\\nxiaomi,mir3g\))',
        r'(xiaomi,mir3g\|\\\nxiaomi,mir3p\))',
    ]
    for pattern in patterns:
        if re.search(pattern, s):
            s = re.sub(pattern, lambda m: m.group(1)[:-1] + '|\\\nxiaomi,mir4)', s, count=1)
            break
    else:
        raise SystemExit('ERROR: uboot-envtools Xiaomi case not found')

p.write_text(s)
PY

grep -q 'xiaomi,mir4)' "${PLATFORM_FILE}"
grep -q 'xiaomi,mir4)' "${UBOOTENV_FILE}"

# ============================================================================
# 6. lyaml
# ============================================================================
LYAML_DIR="${ROOT_DIR}/package/lyaml"
mkdir -p "${LYAML_DIR}"
cat > "${LYAML_DIR}/Makefile" <<'EOF'
include $(TOPDIR)/rules.mk

PKG_NAME:=lyaml
PKG_VERSION:=6.2.7
PKG_RELEASE:=2
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/gvvaughan/lyaml/tar.gz/v$(PKG_VERSION)?
PKG_HASH:=9bb489cefae48b150d66f6bab4141d8d5831fcb7465bfc52a9845fa01efc63b0
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_BUILD_DEPENDS:=lua/host luarocks/host
include $(INCLUDE_DIR)/package.mk

define Package/lyaml
  SUBMENU:=Lua
  SECTION:=lang
  CATEGORY:=Languages
  TITLE:=Lua lib-yaml bindings
  URL:=https://github.com/gvvaughan/lyaml
  DEPENDS:=+lua +libyaml
endef

TARGET_CFLAGS += -I$(STAGING_DIR)/usr/include

define Build/Compile
	cd $(PKG_BUILD_DIR) && \
	LUA_LIBDIR=$(STAGING_DIR)/usr/lib/lua \
	LUA_PKGNAME=lua5.1 \
	CFLAGS="$(TARGET_CFLAGS) $(FPIC)" \
	LDFLAGS="$(TARGET_LDFLAGS)" \
	CC="$(TARGET_CC)" LD="$(TARGET_CC)" \
	luarocks make --pack-binary-rock lyaml-$(PKG_VERSION)-1.rockspec \
	LUA_LIBDIR=$(STAGING_DIR)/usr/lib/lua \
	YAML_DIR=$(STAGING_DIR)/usr \
	LUA_INCDIR=$(STAGING_DIR)/usr/include \
	LUA_PKGNAME=lua5.1 \
	CFLAGS="$(TARGET_CFLAGS) $(FPIC)" \
	LDFLAGS="$(TARGET_LDFLAGS)" \
	CC="$(TARGET_CC)" LD="$(TARGET_CC)"
endef

define Package/lyaml/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/lyaml
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/linux/yaml.so $(1)/usr/lib/lua/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/lib/lyaml/*.lua $(1)/usr/lib/lua/lyaml/
endef

$(eval $(call BuildPackage,lyaml))
EOF

# ============================================================================
# 7. kmod-inet-diag / kmod-netlink-diag (package defs only)
# ============================================================================
if [ -f "${KERNEL_NETSUPPORT_MK}" ]; then
  if ! grep -q 'KernelPackage/netlink-diag' "${KERNEL_NETSUPPORT_MK}"; then
    cat >> "${KERNEL_NETSUPPORT_MK}" <<'EOF'

define KernelPackage/netlink-diag
  SUBMENU:=$(NETWORK_SUPPORT_MENU)
  TITLE:=Netlink diag support for ss utility
  KCONFIG:=CONFIG_NETLINK_DIAG
  FILES:=$(LINUX_DIR)/net/netlink/netlink_diag.ko
  AUTOLOAD:=$(call AutoLoad,31,netlink-diag)
endef

define KernelPackage/netlink-diag/description
  Netlink diag is a module made for use by iproute2 ss.
endef

$(eval $(call KernelPackage,netlink-diag))
EOF
  fi

  if ! grep -q 'KernelPackage/inet-diag' "${KERNEL_NETSUPPORT_MK}"; then
    cat >> "${KERNEL_NETSUPPORT_MK}" <<'EOF'

define KernelPackage/inet-diag
  SUBMENU:=$(NETWORK_SUPPORT_MENU)
  TITLE:=INET diag support for ss utility
  KCONFIG:= \
	CONFIG_INET_DIAG \
	CONFIG_INET_TCP_DIAG \
	CONFIG_INET_UDP_DIAG \
	CONFIG_INET_RAW_DIAG \
	CONFIG_INET_DIAG_DESTROY=n
  FILES:= \
	$(LINUX_DIR)/net/ipv4/inet_diag.ko \
	$(LINUX_DIR)/net/ipv4/tcp_diag.ko \
	$(LINUX_DIR)/net/ipv4/udp_diag.ko \
	$(LINUX_DIR)/net/ipv4/raw_diag.ko
  AUTOLOAD:=$(call AutoLoad,31,inet_diag tcp_diag udp_diag raw_diag)
endef

define KernelPackage/inet-diag/description
  Support for INET socket monitoring used by native Linux tools such as ss.
endef

$(eval $(call KernelPackage,inet-diag))
EOF
  fi
fi

# ============================================================================
# 8. Resolve PassWall packages path; drop rust packages
# ============================================================================
PW_PKGS=""
for d in "${PASSWALL_PACKAGES}" "${PASSWALL_PACKAGES_ALT}"; do
  if [ -d "${d}" ]; then
    PW_PKGS="${d}"
    break
  fi
done

if [ -z "${PW_PKGS}" ]; then
  echo "ERROR: passwall_packages directory not found"
  find feeds package -type d -name 'passwall*' 2>/dev/null | head -20 || true
  exit 1
fi

echo "Using PassWall packages at: ${PW_PKGS}"

[ -f "${PW_PKGS}/shadowsocksr-libev/Makefile" ]
[ -f "${PW_PKGS}/hysteria/Makefile" ]

for rust_pkg in shadowsocks-rust shadow-tls; do
  for base in "${PW_PKGS}" "${PASSWALL_PACKAGES}" "${PASSWALL_PACKAGES_ALT}" \
              "${ROOT_DIR}/package/feeds/passwall_packages" \
              "${ROOT_DIR}/feeds/passwall_packages"; do
    if [ -d "${base}/${rust_pkg}" ]; then
      echo "Removing rust-dependent package: ${base}/${rust_pkg}"
      rm -rf "${base}/${rust_pkg}"
    fi
  done
done

if [ -f "${PASSWALL_MK}" ]; then
  sed -i \
    -e '/select PACKAGE_iptables-zz-legacy/d' \
    -e '/select PACKAGE_iptables-mod-socket/d' \
    -e '/select PACKAGE_kmod-nft-socket/d' \
    -e '/select PACKAGE_kmod-nft-tproxy/d' \
    -e '/select PACKAGE_kmod-inet-diag/d' \
    -e '/select PACKAGE_kmod-netlink-diag/d' \
    -e '/select PACKAGE_shadowsocks-rust/d' \
    -e '/select PACKAGE_shadow-tls/d' \
    "${PASSWALL_MK}" || true
fi

# ============================================================================
# 9. Go 26.x for packages that still compile from source (e.g. hysteria)
# ============================================================================
rm -rf "${GOLANG_DIR}"
if ! git clone --depth 1 --single-branch --branch 26.x \
  https://github.com/sbwml/packages_lang_golang.git "${GOLANG_DIR}"; then
  echo "ERROR: failed to clone sbwml/packages_lang_golang branch 26.x"
  exit 1
fi

# ============================================================================
# 10. Xray 26.9.9 official MIPS32LE binary
# ============================================================================
XRAY_DIR="${PW_PKGS}/xray-core"
rm -rf "${XRAY_DIR}"
mkdir -p "${XRAY_DIR}"

cat > "${XRAY_DIR}/Makefile" <<'EOF'
include $(TOPDIR)/rules.mk

PKG_NAME:=xray-core
PKG_VERSION:=26.9.9
PKG_RELEASE:=1

PKG_SOURCE:=Xray-linux-mips32le.zip
PKG_SOURCE_URL:=https://github.com/XTLS/Xray-core/releases/download/v$(PKG_VERSION)/
PKG_HASH:=e572d2cdd819318383460443140898e6117e8e0da5f0c359b25f6c890b8d81a2

PKG_LICENSE:=MPL-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_SOURCE_SUBDIR)
PKGARCH:=mipsel_24kc

include $(INCLUDE_DIR)/unpack.mk
UNPACK_CMD:=unzip -q -d $(PKG_BUILD_DIR) $(DL_DIR)/$(PKG_SOURCE)

include $(INCLUDE_DIR)/package.mk

define Package/xray-core
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Xray-core
  URL:=https://xtls.github.io
  DEPENDS:=+ca-bundle
endef

define Package/xray-core/description
  Xray-core 26.9.9 official upstream MIPS32LE release binary.
endef

define Build/Compile
endef

define Package/xray-core/install
  $(INSTALL_DIR) $(1)/usr/bin
  $(INSTALL_BIN) $(PKG_BUILD_DIR)/xray $(1)/usr/bin/xray
endef

$(eval $(call BuildPackage,xray-core))
EOF

# ============================================================================
# 11. sing-box 1.14.1 prebuilt binary (mipsle softfloat from Actions host)
# ============================================================================
if [ ! -f "${PREBUILT_SINGBOX}" ]; then
  echo "ERROR: prebuilt sing-box not found at ${PREBUILT_SINGBOX}"
  echo "Workflow must run 'Prebuild sing-box' before diy-part2."
  exit 1
fi

SINGBOX_DIR="${PW_PKGS}/sing-box"
rm -rf "${SINGBOX_DIR}"
mkdir -p "${SINGBOX_DIR}/files"
cp -a "${PREBUILT_SINGBOX}" "${SINGBOX_DIR}/files/sing-box"
chmod +x "${SINGBOX_DIR}/files/sing-box"

cat > "${SINGBOX_DIR}/Makefile" <<EOF
include \$(TOPDIR)/rules.mk

PKG_NAME:=sing-box
PKG_VERSION:=${SINGBOX_VERSION}
PKG_RELEASE:=1

PKG_LICENSE:=GPL-3.0-or-later
PKGARCH:=mipsel_24kc

include \$(INCLUDE_DIR)/package.mk

define Package/sing-box
  SECTION:=net
  CATEGORY:=Network
  TITLE:=sing-box (prebuilt mipsle softfloat)
  URL:=https://sing-box.sagernet.org
  DEPENDS:=+ca-bundle
endef

define Package/sing-box/description
  sing-box ${SINGBOX_VERSION} prebuilt for MT7621A / OpenWrt 19.07
  (GOARCH=mipsle GOMIPS=softfloat, host Go 1.23+).
endef

define Build/Prepare
	mkdir -p \$(PKG_BUILD_DIR)
	cp -a ./files/sing-box \$(PKG_BUILD_DIR)/sing-box
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/sing-box/install
	\$(INSTALL_DIR) \$(1)/usr/bin
	\$(INSTALL_BIN) \$(PKG_BUILD_DIR)/sing-box \$(1)/usr/bin/sing-box
endef

\$(eval \$(call BuildPackage,sing-box))
EOF

# ============================================================================
# 12. Sanity checks
# ============================================================================
[ -f "${PASSWALL_MK}" ]
[ -f "${SINGBOX_DIR}/Makefile" ]
[ -f "${SINGBOX_DIR}/files/sing-box" ]
[ -f "${PW_PKGS}/hysteria/Makefile" ]
[ -f "${PW_PKGS}/shadowsocksr-libev/Makefile" ]
[ ! -d "${PW_PKGS}/shadowsocks-rust" ]
[ ! -d "${PW_PKGS}/shadow-tls" ]

grep -q 'compatible = "xiaomi,mir4"' "${DTS_FILE}"
grep -q 'define Device/xiaomi_mir4' "${IMAGE_MK}"
grep -q 'xiaomi,mir4)' "${NETWORK_FILE}"
grep -q 'luarocks make --pack-binary-rock' "${LYAML_DIR}/Makefile"
grep -q 'PKG_VERSION:=26.9.9' "${XRAY_DIR}/Makefile"
grep -q "PKG_VERSION:=${SINGBOX_VERSION}" "${SINGBOX_DIR}/Makefile"
grep -q 'KernelPackage/inet-diag' "${KERNEL_NETSUPPORT_MK}"
grep -q 'KernelPackage/netlink-diag' "${KERNEL_NETSUPPORT_MK}"

echo "============================================================"
echo "MIR4 / OpenWrt 19.07 / PassWall compatibility patch completed"
echo "Target: Xiaomi Mi Router 4 (MT7621A)"
echo "PassWall: main 26.x"
echo "Xray: 26.9.9 official MIPS32LE binary"
echo "sing-box: ${SINGBOX_VERSION} prebuilt mipsle softfloat"
echo "SSR: upstream"
echo "shadowsocks-rust / shadow-tls: REMOVED (need rust/host)"
echo "kmod-inet-diag / kmod-netlink-diag: package defs present"
echo "============================================================"
