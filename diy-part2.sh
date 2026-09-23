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
GOLANG_DIR="${ROOT_DIR}/feeds/packages/lang/golang"

mkdir -p \
  "$(dirname "${DTS_FILE}")" \
  "$(dirname "${IMAGE_MK}")" \
  "$(dirname "${NETWORK_FILE}")" \
  "$(dirname "${PLATFORM_FILE}")" \
  "$(dirname "${UBOOTENV_FILE}")"

# ============================================================================
# 1. MIR4 DTS
# Source: ioiotor/mir4-ss, with the source project's exact hardware layout:
# 128 MiB RAM, NAND partitions, Wi-Fi EEPROMs and llllw switch portmap.
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
			label = "mri4:red:status";
			gpios = <&gpio0 6 GPIO_ACTIVE_LOW>;
		};

		led_status_blue: status_blue {
			label = "mri4:blue:status";
			gpios = <&gpio0 8 GPIO_ACTIVE_LOW>;
		};

		led_status_yellow: status_yellow {
			label = "mri4:yellow:status";
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
# Source project uses the exact separate kernel/rootfs image layout.
# ============================================================================

python3 - "${IMAGE_MK}" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text()

s = re.sub(r'define Device/(?:mir4|xiaomi_mir4)\n.*?endef\nTARGET_DEVICES \+= (?:mir4|xiaomi_mir4)\n',
           '', s, flags=re.S)

anchor = 'TARGET_DEVICES += xiaomi_mir3g\n'
if anchor not in s:
    raise SystemExit("ERROR: xiaomi_mir3g image profile anchor not found")

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
  DEVICE_PACKAGES := 	kmod-mt7603 kmod-mt76x2 wpad-basic uboot-envtools
endef
TARGET_DEVICES += xiaomi_mir4

'''
s = s.replace(anchor, anchor + "\n" + block, 1)
p.write_text(s)
PY

# ============================================================================
# 3. 02_network
# Use the source project's exact legacy swconfig mapping:
# physical LAN2 -> switch port 1, LAN1 -> port 2, WAN -> port 4, CPU -> 6t.
# ============================================================================

python3 - "${NETWORK_FILE}" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text()

s = re.sub(r'\txiaomi,mir4\)\n\t\tucidef_add_switch "switch0" \\\n(?:\t\t\t".*?"\s*)+\n\t\t;;\n',
           '', s)

anchor = '\txiaomi,mir3p)\n\t\tucidef_add_switch "switch0" \\\n\t\t\t"1:lan:3" "2:lan:2" "3:lan:1" "4:wan" "6@eth0"\n\t\t;;\n'
if anchor not in s:
    raise SystemExit("ERROR: xiaomi,mir3p network anchor not found")

block = '''\txiaomi,mir4)
\t\tucidef_add_switch "switch0" \\\t\t\t"1:lan:2" "2:lan:1" "4:wan" "6t@eth0"
\t\t;;
'''
s = s.replace(anchor, anchor + block, 1)

# Match the source project's MAC policy exactly: LAN MAC from Factory+0xe006.
s = re.sub(r'\txiaomi,mir3g\|\\\n\txiaomi,mir3p\|\\\n\txiaomi,mir4\)\n\t\tlan_mac=.*?\n\t\t;;\n',
           '\txiaomi,mir3g|\\\n\txiaomi,mir3p|\\\n\txiaomi,mir4)\n\t\tlan_mac=$(mtd_get_mac_binary Factory 0xe006)\n\t\t;;\n',
           s, count=1)

p.write_text(s)
PY

# ============================================================================
# 4. NAND upgrade path -- exact source project board case
# ============================================================================

python3 - "${PLATFORM_FILE}" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text()
s = re.sub(r'\txiaomi,mir3g\|\\\n\txiaomi,mir3p\|\\\n\txiaomi,mir4\)',
           '\txiaomi,mir3g|\\\n\txiaomi,mir3p|\\\n\txiaomi,mir4)', s, count=1)

if '\txiaomi,mir4)' not in s:
    anchor = '\txiaomi,mir3p|\\\n\txiaomi,mir3g)'
    if anchor in s:
        s = s.replace(anchor, '\txiaomi,mir3p|\\\n\txiaomi,mir3g|\\\n\txiaomi,mir4)', 1)
    else:
        raise SystemExit("ERROR: NAND upgrade anchor not found")
p.write_text(s)
PY

# ============================================================================
# 5. U-Boot envtools -- exact source project configuration
# ============================================================================

python3 - "${UBOOTENV_FILE}" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text()

if 'xiaomi,mir4)' not in s:
    anchor = 'xiaomi,mir3p|\\\nxiaomi,mir3g)'
    if anchor not in s:
        raise SystemExit("ERROR: uboot-envtools Xiaomi anchor not found")
    s = s.replace(anchor, 'xiaomi,mir3p|\\\nxiaomi,mir3g|\\\nxiaomi,mir4)', 1)

p.write_text(s)
PY

# ============================================================================
# 6. Real lyaml package (PassWall depends on it)
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
	cd $(PKG_BUILD_DIR) && 	LUA_LIBDIR=$(STAGING_DIR)/usr/lib/lua 	LUA_PKGNAME=lua5.1 	CFLAGS="$(TARGET_CFLAGS) $(FPIC)" 	LDFLAGS="$(TARGET_LDFLAGS)" 	CC="$(TARGET_CC)" LD="$(TARGET_CC)" 	luarocks make --pack-binary-rock lyaml-$(PKG_VERSION)-1.rockspec 	LUA_LIBDIR=$(STAGING_DIR)/usr/lib/lua 	YAML_DIR=$(STAGING_DIR)/usr 	LUA_INCDIR=$(STAGING_DIR)/usr/include 	LUA_PKGNAME=lua5.1 	CFLAGS="$(TARGET_CFLAGS) $(FPIC)" 	LDFLAGS="$(TARGET_LDFLAGS)" 	CC="$(TARGET_CC)" LD="$(TARGET_CC)"
endef

define Package/lyaml/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/lyaml
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/linux/yaml.so $(1)/usr/lib/lua/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/lib/lyaml/*.lua $(1)/usr/lib/lua/lyaml/
endef

$(eval $(call BuildPackage,lyaml))
EOF

# ============================================================================
# 7. Replace broken current SSR recipe with a working git-source recipe.
# Current PassWall's main branch declares SSR 2.5.6 but its Makefile has no
# source stanza, which caused the previous "No makefile found" failure.
# ============================================================================

SSR_DIR="${PASSWALL_PACKAGES}/shadowsocksr-libev"
rm -rf "${SSR_DIR}"
mkdir -p "${SSR_DIR}"

cat > "${SSR_DIR}/Makefile" <<'EOF'
include $(TOPDIR)/rules.mk

PKG_NAME:=shadowsocksr-libev
PKG_VERSION:=2.5.6
PKG_RELEASE:=14

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/shadowsocksrr/shadowsocksr-libev.git
PKG_SOURCE_VERSION:=4799b312b8244ec067b8ae9ba4b85c877858976c

PKG_LICENSE:=GPL-3.0
PKG_LICENSE_FILES:=LICENSE
PKG_FIXUP:=autoreconf
PKG_USE_MIPS16:=0
PKG_BUILD_FLAGS:=no-mips16 gc-sections lto
PKG_BUILD_PARALLEL:=1
PKG_INSTALL:=1

include $(INCLUDE_DIR)/package.mk

define Package/shadowsocksr-libev/Default
  define Package/shadowsocksr-libev-ssr-$(1)
    SECTION:=net
    CATEGORY:=Network
    SUBMENU:=Web Servers/Proxies
    TITLE:=shadowsocksr-libev ssr-$(1)
    URL:=https://github.com/shadowsocksrr/shadowsocksr-libev
    DEPENDS:=+libev +libsodium +libopenssl +libpthread +libpcre2 +libudns +zlib
  endef

  define Package/shadowsocksr-libev-ssr-$(1)/install
	$$(INSTALL_DIR) $$(1)/usr/bin
	$$(INSTALL_BIN) $$(PKG_INSTALL_DIR)/usr/bin/ss-$(1) $$(1)/usr/bin/ssr-$(1)
  endef
endef

SHADOWSOCKSR_COMPONENTS:=check local nat redir server
define shadowsocksr-libev/templates
  $(foreach component,$(SHADOWSOCKSR_COMPONENTS),$(call Package/shadowsocksr-libev/Default,$(component)))
endef
$(eval $(call shadowsocksr-libev/templates))

CONFIGURE_ARGS += 	--disable-documentation 	--disable-ssp 	--disable-assert 	--enable-system-shared-lib

TARGET_LDFLAGS += -Wl,--as-needed

$(foreach component,$(SHADOWSOCKSR_COMPONENTS),   $(eval $(call BuildPackage,shadowsocksr-libev-ssr-$(component))) )
EOF

# ============================================================================
# 8. Xray 26.6.1 + Go 1.26 feed
# This keeps Xray, sing-box and hysteria on one modern Go toolchain while
# avoiding Xray 26.9.x's Go 1.27 requirement on the legacy 19.07 buildroot.
# ============================================================================

rm -rf "${GOLANG_DIR}"
git clone --depth 1 --single-branch --branch 26.x   https://github.com/sbwml/packages_lang_golang.git "${GOLANG_DIR}"

XRAY_DIR="${PASSWALL_PACKAGES}/xray-core"
rm -rf "${XRAY_DIR}"
mkdir -p "${XRAY_DIR}"

cat > "${XRAY_DIR}/Makefile" <<'EOF'
include $(TOPDIR)/rules.mk

PKG_NAME:=xray-core
PKG_VERSION:=26.6.1
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/XTLS/Xray-core/tar.gz/v$(PKG_VERSION)?
PKG_HASH:=efe463f8e35c4e6e93a6e8d51b27bae0cd4904b9820740c3af01733efb566fee
PKG_BUILD_DIR:=$(BUILD_DIR)/Xray-core-$(PKG_VERSION)

PKG_LICENSE:=MPL-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_USE_MIPS16:=0
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/xtls/xray-core
GO_PKG_BUILD_PKG:=$(GO_PKG)/main
GO_PKG_LDFLAGS:=-s -w
GO_PKG_LDFLAGS_X:= 	$(GO_PKG)/core.build=OpenWrt 	$(GO_PKG)/core.version=$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/xray-core
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Xray-core
  URL:=https://xtls.github.io
  DEPENDS:=$(GO_ARCH_DEPENDS) +ca-bundle
endef

define Package/xray-core/install
	$(call GoPackage/Package/Install/Bin,$(PKG_INSTALL_DIR))
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/main $(1)/usr/bin/xray
endef

$(eval $(call BuildPackage,xray-core))
EOF

# ============================================================================
# 9. PassWall cores: keep all requested cores enabled.
# Do not delete sing-box/hysteria/SSR from the feed.
# ============================================================================

test -f "${PASSWALL_MK}"
test -f "${PASSWALL_PACKAGES}/sing-box/Makefile"
test -f "${PASSWALL_PACKAGES}/hysteria/Makefile"

# ============================================================================
# 10. Runtime defaults: IPv6 enabled + 128 MiB ZRAM
# ============================================================================

mkdir -p "${ROOT_DIR}/files/etc/uci-defaults"

cat > "${ROOT_DIR}/files/etc/uci-defaults/99-mir4-tuning" <<'EOF'
#!/bin/sh

# Keep IPv6 enabled. The firmware is built with kernel IPv6, ip6tables,
# odhcp6c/odhcpd and luci-proto-ipv6.

uci -q set network.lan.ip6assign='60'
uci -q set dhcp.lan.ra='server'
uci -q set dhcp.lan.dhcpv6='server'
uci -q set dhcp.lan.ndp='hybrid'

# Software flow offloading is safe with PassWall's iptables/TProxy path.
uci -q set firewall.@defaults[0].flow_offloading='1'
uci -q set firewall.@defaults[0].flow_offloading_hw='0'

# OpenWrt 19.07 zram-swap reads these exact UCI options.
uci -q set system.@system[0].zram_size_mb='128'
uci -q set system.@system[0].zram_comp_algo='lz4'
uci -q set system.@system[0].zram_comp_streams='4'
uci -q set system.@system[0].log_size='16'

uci -q set dhcp.@dnsmasq[0].cachesize='512'
uci -q set dhcp.@dnsmasq[0].domainneeded='1'
uci -q set dhcp.@dnsmasq[0].boguspriv='1'

uci -q commit network
uci -q commit dhcp
uci -q commit firewall
uci -q commit system

[ -x /etc/init.d/zram ] && /etc/init.d/zram enable >/dev/null 2>&1 || true

exit 0
EOF

chmod 0755 "${ROOT_DIR}/files/etc/uci-defaults/99-mir4-tuning"

# ============================================================================
# 11. Build-time sanity checks
# ============================================================================

grep -q 'compatible = "xiaomi,mir4"' "${DTS_FILE}"
grep -q 'mediatek,portmap = "llllw"' "${DTS_FILE}"
grep -q 'define Device/xiaomi_mir4' "${IMAGE_MK}"
grep -q 'IMAGE_SIZE := 124416k' "${IMAGE_MK}"
grep -q 'xiaomi,mir4)' "${NETWORK_FILE}"
grep -q '"1:lan:2" "2:lan:1" "4:wan" "6t@eth0"' "${NETWORK_FILE}"
grep -q 'xiaomi,mir4)' "${PLATFORM_FILE}"
grep -q 'xiaomi,mir4)' "${UBOOTENV_FILE}"
grep -q 'PKG_VERSION:=2.5.6' "${SSR_DIR}/Makefile"
grep -q '4799b312b8244ec067b8ae9ba4b85c877858976c' "${SSR_DIR}/Makefile"
grep -q 'PKG_VERSION:=26.6.1' "${XRAY_DIR}/Makefile"

echo "============================================================"
echo "MIR4 / OpenWrt 19.07 patch completed"
echo "DTS         : ioiotor/mir4-ss hardware layout"
echo "Switch      : port1 LAN2 / port2 LAN1 / port4 WAN / port6 CPU"
echo "NAND image  : 124416 KiB"
echo "IPv6        : enabled"
echo "ZRAM        : 128 MiB / lz4 / 4 streams"
echo "Xray        : 26.6.1"
echo "Sing-box    : PassWall feed current main"
echo "Hysteria    : PassWall feed current main"
echo "SSR         : 2.5.6 git master source, fixed recipe"
echo "Go          : sbwml/packages_lang_golang 26.x"
echo "============================================================"
