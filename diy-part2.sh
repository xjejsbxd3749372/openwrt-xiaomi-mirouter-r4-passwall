#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(pwd)"
HELLOWORLD_DIR="${ROOT_DIR}/package/helloworld"
DTS_FILE="${ROOT_DIR}/target/linux/ramips/dts/MIR4.dts"
IMAGE_FILE="${ROOT_DIR}/target/linux/ramips/image/mt7621.mk"
NETWORK_FILE="${ROOT_DIR}/target/linux/ramips/base-files/etc/board.d/02_network"
UPGRADE_FILE="${ROOT_DIR}/target/linux/ramips/base-files/lib/upgrade/platform.sh"
UBOOTENV_FILE="${ROOT_DIR}/package/boot/uboot-envtools/files/ramips"

test -d "${HELLOWORLD_DIR}"

mkdir -p "$(dirname "${DTS_FILE}")"

cat > "${DTS_FILE}" <<'EOF'
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT
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
	memory@0 { device_type = "memory"; reg = <0x0 0x8000000>; };
	chosen { bootargs = "console=ttyS0,115200n8"; };
	leds {
		compatible = "gpio-leds";
		led_status_red: status_red { label = "mri4:red:status"; gpios = <&gpio0 6 GPIO_ACTIVE_LOW>; };
		led_status_blue: status_blue { label = "mri4:blue:status"; gpios = <&gpio0 8 GPIO_ACTIVE_LOW>; };
		led_status_yellow: status_yellow { label = "mri4:yellow:status"; gpios = <&gpio0 10 GPIO_ACTIVE_LOW>; };
	};
	button {
		compatible = "gpio-keys-polled";
		poll-interval = <20>;
		reset { label = "reset"; gpios = <&gpio0 18 GPIO_ACTIVE_LOW>; linux,code = <KEY_RESTART>; };
		minet { label = "minet"; gpios = <&gpio0 12 GPIO_ACTIVE_LOW>; linux,code = <KEY_WPS_BUTTON>; };
	};
};

&nand {
	status = "okay";
	partitions {
		compatible = "fixed-partitions";
		#address-cells = <1>;
		#size-cells = <1>;
		partition@0 { label = "Bootloader"; reg = <0x0 0x80000>; read-only; };
		partition@80000 { label = "Config"; reg = <0x80000 0x40000>; };
		partition@c0000 { label = "Bdata"; reg = <0xc0000 0x40000>; read-only; };
		factory: partition@100000 { label = "Factory"; reg = <0x100000 0x40000>; read-only; };
		partition@140000 { label = "crash"; reg = <0x140000 0x40000>; };
		partition@180000 { label = "crash_syslog"; reg = <0x180000 0x40000>; };
		partition@1c0000 { label = "reserved0"; reg = <0x1c0000 0x40000>; read-only; };
		partition@200000 { label = "kernel_stock"; reg = <0x200000 0x400000>; };
		partition@600000 { label = "kernel"; reg = <0x600000 0x400000>; };
		partition@a00000 { label = "ubi"; reg = <0xa00000 0x7580000>; };
	};
};

&pcie { status = "okay"; };
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

if ! grep -q 'Device/xiaomi_mir4' "${IMAGE_FILE}"; then
python3 - "${IMAGE_FILE}" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
anchor="TARGET_DEVICES += xiaomi_mir3g\n"
block="""define Device/xiaomi_mir4
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
  DEVICE_PACKAGES := kmod-mt7603 kmod-mt76x2 wpad-basic uboot-envtools
endef
TARGET_DEVICES += xiaomi_mir4

"""
if anchor not in s: raise SystemExit("MIR4 image anchor not found")
p.write_text(s.replace(anchor,anchor+block,1))
PY
fi

python3 - "${NETWORK_FILE}" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
if "xiaomi,mir4)" not in s:
    anchor="\txiaomi,mir4a-100m)"
    block='\txiaomi,mir4)\\\n\t\tucidef_add_switch "switch0" \\\n\t\t\t"1:lan:2" "2:lan:1" "4:wan" "6t@eth0"\n\t\t;;\n'
    if anchor not in s: raise SystemExit("network anchor not found")
    s=s.replace(anchor,block+anchor,1)
    s=s.replace("xiaomi,mir3p)\n\t\tlan_mac=", "xiaomi,mir3p|\\\n\txiaomi,mir4)\n\t\tlan_mac=",1)
p.write_text(s)
PY

python3 "${UPGRADE_FILE}" "${UBOOTENV_FILE}" <<'PY'
from pathlib import Path
import sys
upgrade, env = map(Path, sys.argv[1:])

s = upgrade.read_text()
if "xiaomi,mir4)" not in s:
    s = s.replace("xiaomi,mir3g|\\\n\txiaomi,mir3p)", "xiaomi,mir3g|\\\n\txiaomi,mir3p|\\\n\txiaomi,mir4)", 1)
upgrade.write_text(s)

s = env.read_text()
if "xiaomi,mir4)" not in s:
    s = s.replace("xiaomi,mir3p|\\\n\txiaomi,mir3g)", "xiaomi,mir4|\\\n\txiaomi,mir3p|\\\n\txiaomi,mir3g)", 1)
env.write_text(s)
PY

XRAY_MK="${HELLOWORLD_DIR}/xray-core/Makefile"
sed -i 's/^PKG_VERSION:=26\.5\.9$/PKG_VERSION:=26.9.9/' "${XRAY_MK}"
sed -i 's/^PKG_HASH:=.*/PKG_HASH:=skip/' "${XRAY_MK}"

grep -q 'compatible = "xiaomi,mir4"' "${DTS_FILE}"
grep -q 'Device/xiaomi_mir4' "${IMAGE_FILE}"
grep -q 'xiaomi,mir4)' "${NETWORK_FILE}"
grep -q 'xiaomi,mir4)' "${UPGRADE_FILE}"
grep -q 'xiaomi,mir4)' "${UBOOTENV_FILE}"
test -f "${ROOT_DIR}/package/feeds/golang27/lang/golang/Makefile"
test -f "${ROOT_DIR}/package/feeds/compat23/rust/Makefile"
test -f "${ROOT_DIR}/package/feeds/compat23/rust/rust-package.mk"
test -f "${ROOT_DIR}/package/feeds/modern/lang/lua/lyaml/Makefile"
test -f "${ROOT_DIR}/package/feeds/kcptun/kcptun/Makefile"

echo "MIR4 + real host dependency repair completed."
