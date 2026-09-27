#!/usr/bin/env bash
set -euo pipefail
ROOT="$(pwd)"
DTS="${ROOT}/target/linux/ramips/dts/MIR4.dts"
IMAGE="${ROOT}/target/linux/ramips/image/mt7621.mk"
NET="${ROOT}/target/linux/ramips/base-files/etc/board.d/02_network"
UPG="${ROOT}/target/linux/ramips/base-files/lib/upgrade/platform.sh"
ENVTOOLS="${ROOT}/package/boot/uboot-envtools/files/ramips"
ACC="${ROOT}/files/etc/uci-defaults/99-mir4-accel"
mkdir -p "$(dirname "${DTS}")" "$(dirname "${ACC}")"

cat > "${DTS}" <<'EOF'
// SPDX-License-Identifier: GPL-2.0-only OR MIT
/dts-v1/;
#include "mt7621.dtsi"
#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/input/input.h>
/ {
  compatible = "xiaomi,mir4", "mediatek,mt7621-soc";
  model = "Xiaomi Mi Router 4";
  memory@0 { device_type = "memory"; reg = <0x0 0x8000000>; };
  chosen { bootargs = "console=ttyS0,115200n8"; };
  gpio-leds {
    compatible = "gpio-leds";
    red { label = "mir4:red:status"; gpios = <&gpio0 6 GPIO_ACTIVE_LOW>; };
    blue { label = "mir4:blue:status"; gpios = <&gpio0 8 GPIO_ACTIVE_LOW>; };
    yellow { label = "mir4:yellow:status"; gpios = <&gpio0 10 GPIO_ACTIVE_LOW>; };
  };
  gpio-keys-polled {
    compatible = "gpio-keys-polled";
    #address-cells = <1>;
    #size-cells = <0>;
    poll-interval = <20>;
    reset { label = "reset"; gpios = <&gpio0 18 GPIO_ACTIVE_LOW>; linux,code = <KEY_RESTART>; };
    minet { label = "minet"; gpios = <&gpio0 12 GPIO_ACTIVE_LOW>; linux,code = <KEY_WPS_BUTTON>; };
  };
};
&nand {
  status = "okay";
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
&pcie {
  status = "okay";
  pcie0 {
    wifi@14c3,7603 {
      compatible = "pci14c3,7603";
      reg = <0x0000 0 0 0 0>;
      mediatek,mtd-eeprom = <&factory 0x0000>;
      ieee80211-freq-limit = <2400000 2500000>;
    };
  };
  pcie1 {
    wifi@14c3,7662 {
      compatible = "pci14c3,7662";
      reg = <0x0000 0 0 0 0>;
      mediatek,mtd-eeprom = <&factory 0x8000>;
      ieee80211-freq-limit = <5000000 6000000>;
    };
  };
};
&ethernet {
  mtd-mac-address = <&factory 0xe000>;
  mediatek,portmap = "llllw";
};
&pinctrl {
  state_default: pinctrl0 {
    gpio { ralink,group = "jtag", "uart2", "uart3", "wdt"; ralink,function = "gpio"; };
  };
};
EOF

python3 - "${IMAGE}" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
if "define Device/mir4" not in s:
    anchor="TARGET_DEVICES += mir3g\n"
    block="""define Device/mir4
  DTS := MIR4
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_SIZE := 4096k
  KERNEL := $(KERNEL_DTB) | uImage lzma
  IMAGE_SIZE := 32768k
  UBINIZE_OPTS := -E 5
  IMAGES := sysupgrade.tar kernel1.bin rootfs0.bin
  IMAGE/kernel1.bin := append-kernel
  IMAGE/rootfs0.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.tar := sysupgrade-tar | append-metadata
  DEVICE_TITLE := Xiaomi Mi Router 4
  SUPPORTED_DEVICES += MIR4
  DEVICE_PACKAGES := kmod-mt7603e kmod-mt76x2e mt_wifi luci-app-mtwifi wpad-mini uboot-envtools kmod-ipt-offload kmod-tcp-bbr zram-swap
endef
TARGET_DEVICES += mir4

"""
    if anchor not in s: raise SystemExit("MIR3G image anchor missing")
    p.write_text(s.replace(anchor,anchor+block,1))
PY

python3 - "${NET}" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()

def insert_after_case(text, case_line, block):
    pos=text.find(case_line)
    if pos < 0:
        raise SystemExit("case anchor missing: " + case_line.strip())
    end=text.find("\n\t\t;;", pos)
    if end < 0:
        raise SystemExit("case terminator missing: " + case_line.strip())
    return text[:end+len("\n\t\t;;")] + block + text[end+len("\n\t\t;;"):]

if "mir4)" not in s:
    s=insert_after_case(s, "\tmir3g)", """\n\tmir4)
\t\tucidef_add_switch "switch0" \\\n\t\t\t"1:lan:2" "2:lan:1" "4:wan" "6t@eth0"
\t\t;;\n""")

mac_start=s.find("ramips_setup_macs")
if "\tmir4)" not in s[mac_start:]:
    pos=s.find("\tmir3g)",mac_start)
    if pos<0: raise SystemExit("MAC mir3g anchor missing")
    end=s.find("\n\t\t;;",pos)
    if end<0: raise SystemExit("MAC mir3g terminator missing")
    block='''\n\tmir4)
\t\tlan_mac=$(mtd_get_mac_binary Factory 0xe000)
\t\twan_mac=$(mtd_get_mac_binary Factory 0xe006)
\t\t;;
'''
    s=s[:end+len("\n\t\t;;")]+block+s[end+len("\n\t\t;;"):]

p.write_text(s)
PY

python3 - "${UPG}" "${ENVTOOLS}" <<'PY'
from pathlib import Path
import sys
upg,env=map(Path,sys.argv[1:])

s=upg.read_text()
if "mir4|" not in s:
    bs=chr(92)
    needle="mir3g|"
    first=s.find(needle)
    if first<0: raise SystemExit("platform mir3g anchor missing")
    line_end=s.find("\n", first)
    s=s[:line_end+1] + "\tmir4|" + bs + "\n" + s[line_end+1:]
    second=s.find(needle, line_end+1)
    if second<0: raise SystemExit("platform second mir3g anchor missing")
    line_end=s.find("\n", second)
    s=s[:line_end+1] + "\tmir4|" + bs + "\n" + s[line_end+1:]
upg.write_text(s)

s=env.read_text()
if "\tmir4)" not in s:
    pos=s.find("mir3g)")
    if pos<0: raise SystemExit("envtools mir3g anchor missing")
    end=s.find("\n\t;;",pos)
    if end<0: raise SystemExit("envtools mir3g terminator missing")
    block='''\n\tmir4)
\tubootenv_add_uci_config "/dev/mtd1" "0x0" "0x1000" "0x20000"
\t;;
'''
    s=s[:end+len("\n\t;;")]+block+s[end+len("\n\t;;"):]
env.write_text(s)
PY

cat > "${ACC}" <<'EOF'
#!/bin/sh
uci -q set firewall.@defaults[0].flow_offloading='1'
uci -q set firewall.@defaults[0].flow_offloading_hw='1'
uci -q commit firewall
uci -q set system.@system[0].zram_size_mb='64'
uci -q set system.@system[0].zram_comp_algo='lz4'
uci -q set system.@system[0].zram_comp_streams='2'
uci -q commit system
grep -q '^net.ipv4.tcp_congestion_control=bbr$' /etc/sysctl.conf 2>/dev/null || echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.conf
rm -f /etc/uci-defaults/99-mir4-accel
exit 0
EOF
chmod 0755 "${ACC}"
grep -q 'compatible = "xiaomi,mir4"' "${DTS}"
grep -q 'define Device/mir4' "${IMAGE}"
grep -q 'SUPPORTED_DEVICES += MIR4' "${IMAGE}"
grep -q 'mir4)' "${NET}"
grep -q 'mir4|' "${UPG}"
grep -q 'mir4)' "${ENVTOOLS}"
test -f "${ACC}"
echo "MIR4 board files ready."
