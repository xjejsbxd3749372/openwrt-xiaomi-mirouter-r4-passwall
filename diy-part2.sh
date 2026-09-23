#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(pwd)"

DTS_FILE="${ROOT_DIR}/target/linux/ramips/dts/MIR4.dts"
IMAGE_MK="${ROOT_DIR}/target/linux/ramips/image/mt7621.mk"
NETWORK_FILE="${ROOT_DIR}/target/linux/ramips/base-files/etc/board.d/02_network"
PLATFORM_FILE="${ROOT_DIR}/target/linux/ramips/base-files/lib/upgrade/platform.sh"
UBOOTENV_FILE="${ROOT_DIR}/package/boot/uboot-envtools/files/ramips"

PASSWALL_MK="${ROOT_DIR}/package/feeds/passwall_luci/luci-app-passwall/Makefile"
XRAY_MK="${ROOT_DIR}/package/feeds/passwall_packages/xray-core/Makefile"

mkdir -p \
    "$(dirname "${DTS_FILE}")" \
    "$(dirname "${IMAGE_MK}")" \
    "$(dirname "${NETWORK_FILE}")" \
    "$(dirname "${PLATFORM_FILE}")" \
    "$(dirname "${UBOOTENV_FILE}")" \
    "${ROOT_DIR}/files/etc/uci-defaults"

# ============================================================================
# 1. Xiaomi Mi Router 4 DTS
#    基于 OpenWrt 19.07 的 MT7621 / MIR3G DTS 结构，
#    按 Mi Router 4 官方硬件信息改为 128 MiB RAM + 128 MiB NAND。
# ============================================================================

cat > "${DTS_FILE}" <<'EOF'
/dts-v1/;

#include "mt7621.dtsi"

#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/input/input.h>

/ {
	compatible = "xiaomi,mi-router-4", "mediatek,mt7621-soc";
	model = "Xiaomi Mi Router 4";

	aliases {
		led-boot = &led_status_yellow;
		led-failsafe = &led_status_red;
		led-running = &led_status_blue;
		led-upgrade = &led_status_yellow;
	};

	memory@0 {
		device_type = "memory";
		reg = <0x0 0x08000000>;
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
	mediatek,portmap = "lwlll";
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
# 2. 添加 MIR4 image profile
# ============================================================================

python3 - "${IMAGE_MK}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

if "define Device/mir4" not in text:
    marker = "TARGET_DEVICES += xiaomi_mir3g\n"

    block = r'''
define Device/mir4
  DTS := MIR4
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_SIZE := 4096k
  IMAGE_SIZE := 124416k
  UBINIZE_OPTS := -E 5
  BOARD_NAME := mir4
  IMAGES += kernel1.bin rootfs0.bin
  IMAGE/kernel1.bin := append-kernel
  IMAGE/rootfs0.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  DEVICE_TITLE := Xiaomi Mi Router 4
  SUPPORTED_DEVICES += mir4
  SUPPORTED_DEVICES += xiaomi,mi-router-4
  DEVICE_PACKAGES := \
	kmod-mt7603 kmod-mt76x2 \
	wpad-basic uboot-envtools
endef
TARGET_DEVICES += mir4

'''

    if marker not in text:
        raise SystemExit("ERROR: MIR3G target anchor not found")

    text = text.replace(marker, marker + "\n" + block, 1)
    path.write_text(text)
PY

# ============================================================================
# 3. 网络接口
# ============================================================================

python3 - "${NETWORK_FILE}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

# xiaomi,mi-router-4 -> legacy MT7621 switch mapping used by Mi Router 3G.
# Physical LAN numbering follows Xiaomi's OEM wiring.
if "\txiaomi,mi-router-4|" not in text:
    needle = "\txiaomi,mir3g)\n"
    replacement = (
        "\txiaomi,mi-router-4|\\\n"
        "\txiaomi,mir3g)\n"
    )

    if needle not in text:
        raise SystemExit("ERROR: xiaomi,mir3g interface case not found")

    text = text.replace(needle, replacement, 1)

# MIR4 factory MAC layout:
# LAN / base MAC = factory 0xe000
# WAN MAC        = factory 0xe006
if "\txiaomi,mi-router-4)\n" not in text.split("ramips_setup_macs()", 1)[-1]:
    needle = "\txiaomi,mir3g|\\\n\txiaomi,mir3p)\n"
    replacement = (
        "\txiaomi,mi-router-4)\n"
        "\t\tlan_mac=$(mtd_get_mac_binary Factory 0xe000)\n"
        "\t\twan_mac=$(mtd_get_mac_binary Factory 0xe006)\n"
        "\t\t;;\n"
        + needle
    )

    if needle not in text:
        raise SystemExit("ERROR: MIR3G MAC case not found")

    text = text.replace(needle, replacement, 1)

path.write_text(text)
PY

# ============================================================================
# 4. NAND 升级路径
# ============================================================================

python3 - "${PLATFORM_FILE}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

if "\txiaomi,mi-router-4|" not in text:
    needle = "\txiaomi,mir3g|\\\n\txiaomi,mir3p)\n"
    replacement = (
        "\txiaomi,mi-router-4|\\\n"
        "\txiaomi,mir3g|\\\n"
        "\txiaomi,mir3p)\n"
    )

    if needle not in text:
        raise SystemExit("ERROR: MIR3G NAND upgrade case not found")

    text = text.replace(needle, replacement, 1)

path.write_text(text)
PY

# ============================================================================
# 5. U-Boot envtools
# ============================================================================

python3 - "${UBOOTENV_FILE}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

if "\txiaomi,mi-router-4|" not in text:
    needle = "\txiaomi,mir3p|\\\n\txiaomi,mir3g)\n"
    replacement = (
        "\txiaomi,mi-router-4|\\\n"
        "\txiaomi,mir3p|\\\n"
        "\txiaomi,mir3g)\n"
    )

    if needle not in text:
        raise SystemExit("ERROR: MIR3G uboot-envtools case not found")

    text = text.replace(needle, replacement, 1)

path.write_text(text)
PY

# ============================================================================
# 6. 当前 PassWall 主程序：保留最新版 UI，关闭大核心默认项
# ============================================================================

python3 - "${PASSWALL_MK}" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()

keys = [
    "Iptables_Transparent_Proxy",
    "Nftables_Transparent_Proxy",
    "INCLUDE_Geoview",
    "INCLUDE_Haproxy",
    "INCLUDE_Hysteria",
    "INCLUDE_NaiveProxy",
    "INCLUDE_Shadowsocks_Rust_Client",
    "INCLUDE_Shadowsocks_Rust_Server",
    "INCLUDE_ShadowsocksR_Libev_Client",
    "INCLUDE_ShadowsocksR_Libev_Server",
    "INCLUDE_Shadow_TLS",
    "INCLUDE_Simple_Obfs",
    "INCLUDE_SingBox",
    "INCLUDE_V2ray_Geodata",
    "INCLUDE_V2ray_Plugin",
    "INCLUDE_Xray",
    "INCLUDE_Xray_Plugin",
]

for key in keys:
    pattern = re.compile(
        rf"(config PACKAGE_\$\(PKG_NAME\)_{re.escape(key)}.*?)(?=\nconfig PACKAGE_|\nendmenu)",
        re.S,
    )

    m = pattern.search(text)
    if not m:
        continue

    block = m.group(1)

    if key == "Iptables_Transparent_Proxy":
        continue

    block2 = re.sub(
        r"\n\tdefault\s+.*",
        "\n\tdefault n",
        block,
        count=1,
    )

    text = text[:m.start(1)] + block2 + text[m.end(1):]

path.write_text(text)
PY

# ============================================================================
# 7. 删除导致 19.07 构建失败或没有必要的 PassWall 重型核心
#
# ShadowsocksR Libev 是此前 19.07 构建失败的直接来源。
# 其它现代核心在 128M RAM 版本中不参与固件编译。
# ============================================================================

PASSWALL_PACKAGES_DIR="${ROOT_DIR}/package/feeds/passwall_packages"

for pkg in \
    shadowsocksr-libev \
    shadowsocks-rust \
    shadow-tls \
    sing-box \
    hysteria \
    naiveproxy \
    geoview \
    haproxy \
    v2ray-plugin \
    xray-plugin \
    simple-obfs
do
    rm -rf "${PASSWALL_PACKAGES_DIR}/${pkg}"
done

# ============================================================================
# 8. 使用与 Go 1.26.x 匹配的 Xray 26.6.1
#
# 当前 PassWall main 保持最新 UI。
# Xray 26.9.x 要求 Go 1.27，而 26.x Golang feed 为 Go 1.26.x，
# 因此 pin 到 Xray 26.6.1。
# ============================================================================

cat > "${XRAY_MK}" <<'EOF'
include $(TOPDIR)/rules.mk

PKG_NAME:=xray-core
PKG_VERSION:=26.6.1
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/XTLS/Xray-core/tar.gz/v$(PKG_VERSION)?
PKG_HASH:=efe463f8e35c4e6e93a6e8d51b27bae0cd4904b9820740c3af01733efb566fee

PKG_MAINTAINER:=Tianling Shen <cnsztl@immortalwrt.org>
PKG_LICENSE:=MPL-2.0
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_DIR:=$(BUILD_DIR)/Xray-core-$(PKG_VERSION)

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_USE_MIPS16:=0
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/xtls/xray-core
GO_PKG_LDFLAGS:=-s -w
GO_PKG_BUILD_PKG:=$(GO_PKG)/main
GO_PKG_LDFLAGS_X:= \
	$(GO_PKG)/core.build=OpenWrt \
	$(GO_PKG)/core.version=$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/xray-core
  TITLE:=A platform for building proxies to bypass network restrictions
  SECTION:=net
  CATEGORY:=Network
  URL:=https://xtls.github.io
  DEPENDS:=$(GO_ARCH_DEPENDS) +ca-bundle
endef

define Package/xray-core/description
  Xray, Penetrates Everything. It helps you to build your own computer network.
  It secures your network connections and thus protects your privacy.
endef

define Package/xray-core/conffiles
/etc/xray/
/etc/config/xray
endef

define Package/xray-core/install
	$(call GoPackage/Package/Install/Bin,$(PKG_INSTALL_DIR))
	$(INSTALL_DIR) $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/main $(1)/usr/bin/xray
endef

$(eval $(call BuildPackage,xray-core))
EOF

# ============================================================================
# 9. 使用 Go 1.26.x feed
# ============================================================================

rm -rf "${ROOT_DIR}/feeds/packages/lang/golang"

git clone \
    --depth 1 \
    --single-branch \
    --branch 26.x \
    https://github.com/sbwml/packages_lang_golang \
    "${ROOT_DIR}/feeds/packages/lang/golang"

# ============================================================================
# 10. 关闭无用日志 / 大型服务 / 第二套代理核心
# ============================================================================

mkdir -p "${ROOT_DIR}/files/etc/uci-defaults"

cat > "${ROOT_DIR}/files/etc/uci-defaults/99-mir4-tuning" <<'EOF'
#!/bin/sh

# ============================================================================
# Xiaomi Mi Router 4 runtime tuning
# ============================================================================

# ---------------------------------------------------------------------------
# LAN
# ---------------------------------------------------------------------------

uci -q set network.lan.ipaddr='192.168.1.1'
uci -q set network.lan.netmask='255.255.255.0'

# Disable IPv6 on LAN/WAN.
uci -q delete network.wan6
uci -q set network.lan.ip6assign='0'

uci -q set dhcp.lan.ra='disabled'
uci -q set dhcp.lan.dhcpv6='disabled'
uci -q set dhcp.lan.ndp='disabled'

# ---------------------------------------------------------------------------
# DNS cache
# ---------------------------------------------------------------------------

uci -q set dhcp.@dnsmasq[0].cachesize='512'
uci -q set dhcp.@dnsmasq[0].domainneeded='1'
uci -q set dhcp.@dnsmasq[0].boguspriv='1'

# ---------------------------------------------------------------------------
# Software flow offloading only.
#
# Hardware NAT offload is deliberately disabled because policy routing /
# TPROXY traffic handled by PassWall must continue through netfilter.
# ---------------------------------------------------------------------------

uci -q set firewall.@defaults[0].flow_offloading='1'
uci -q set firewall.@defaults[0].flow_offloading_hw='0'

# ---------------------------------------------------------------------------
# 64 MiB ZRAM
# ---------------------------------------------------------------------------

uci -q set system.@system[0].zram_size_mb='64'
uci -q set system.@system[0].zram_comp_algo='lz4'
uci -q set system.@system[0].zram_comp_streams='4'

# Keep normal log buffer small.
uci -q set system.@system[0].log_size='16'

# ---------------------------------------------------------------------------
# Conntrack / TCP tuning for 128 MiB RAM.
#
# 32768 is deliberately used instead of extremely large conntrack tables.
# ---------------------------------------------------------------------------

SYSCTL_MARK="# MIR4-PASSWALL-128M"

if ! grep -q "${SYSCTL_MARK}" /etc/sysctl.conf 2>/dev/null; then
	cat >> /etc/sysctl.conf <<'SYSCTL'
# MIR4-PASSWALL-128M

vm.swappiness=10
vm.vfs_cache_pressure=200
vm.dirty_background_ratio=2
vm.dirty_ratio=5

net.core.somaxconn=512
net.core.netdev_max_backlog=2048

net.ipv4.tcp_max_syn_backlog=2048
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_tw_reuse=1
net.ipv4.ip_local_port_range=10240 65535
net.ipv4.tcp_syncookies=1

net.netfilter.nf_conntrack_max=32768
net.netfilter.nf_conntrack_acct=0
net.netfilter.nf_conntrack_timestamp=0
net.netfilter.nf_conntrack_tcp_timeout_established=1800
net.netfilter.nf_conntrack_tcp_timeout_time_wait=30
net.netfilter.nf_conntrack_udp_timeout=30
net.netfilter.nf_conntrack_udp_timeout_stream=120
SYSCTL
fi

sysctl -p /etc/sysctl.conf >/dev/null 2>&1 || true

uci -q commit network
uci -q commit dhcp
uci -q commit firewall
uci -q commit system

# Enable ZRAM for subsequent boots.
if [ -x /etc/init.d/zram ]; then
	/etc/init.d/zram enable >/dev/null 2>&1 || true
fi

exit 0
EOF

chmod 0755 "${ROOT_DIR}/files/etc/uci-defaults/99-mir4-tuning"

# ============================================================================
# 11. 清理不必要的 source-side 文件，确保没有旧的 MIR4 注入冲突
# ============================================================================

rm -f "${ROOT_DIR}/files/MIR4.dts" 2>/dev/null || true

# ============================================================================
# 12. 基本完整性检查
# ============================================================================

test -s "${DTS_FILE}"
grep -q 'compatible = "xiaomi,mi-router-4"' "${DTS_FILE}"
grep -q 'reg = <0x0 0x08000000>' "${DTS_FILE}"
grep -q 'partition@a00000' "${DTS_FILE}"

grep -q 'define Device/mir4' "${IMAGE_MK}"
grep -q 'TARGET_DEVICES += mir4' "${IMAGE_MK}"
grep -q 'xiaomi,mi-router-4' "${NETWORK_FILE}"
grep -q 'xiaomi,mi-router-4' "${PLATFORM_FILE}"
grep -q 'xiaomi,mi-router-4' "${UBOOTENV_FILE}"

grep -q 'PKG_VERSION:=26.6.1' "${XRAY_MK}"
grep -q 'PKG_HASH:=efe463f8e35c4e6e93a6e8d51b27bae0cd4904b9820740c3af01733efb566fee' "${XRAY_MK}"

echo "============================================================"
echo "diy-part2.sh completed"
echo "Target      : Xiaomi Mi Router 4 / MT7621"
echo "RAM         : 128 MiB"
echo "Kernel      : OpenWrt 19.07 / Linux 4.14"
echo "PassWall    : current main"
echo "Proxy core  : Xray 26.6.1"
echo "Go feed     : sbwml/packages_lang_golang 26.x"
echo "ZRAM        : 64 MiB / lz4 / 4 streams"
echo "Conntrack   : 32768"
echo "Flow offload: software only"
echo "============================================================"
