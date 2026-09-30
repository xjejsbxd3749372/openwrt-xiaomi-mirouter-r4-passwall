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
    end=text.find("\n		;;", pos)
    if end < 0:
        raise SystemExit("case terminator missing: " + case_line.strip())
    return text[:end+len("\n		;;")] + block + text[end+len("\n		;;"):]

if "mir4)" not in s:
    s=insert_after_case(s, "	mir3g)", """\n	mir4)
		ucidef_add_switch "switch0" \\\n			"1:lan:2" "2:lan:1" "4:wan" "6t@eth0"
		;;\n""")

mac_start=s.find("ramips_setup_macs")
if "	mir4)" not in s[mac_start:]:
    pos=s.find("	mir3g)",mac_start)
    if pos<0: raise SystemExit("MAC mir3g anchor missing")
    end=s.find("\n		;;",pos)
    if end<0: raise SystemExit("MAC mir3g terminator missing")
    block='''\n	mir4)
		lan_mac=$(mtd_get_mac_binary Factory 0xe000)
		wan_mac=$(mtd_get_mac_binary Factory 0xe006)
		;;
'''
    s=s[:end+len("\n		;;")]+block+s[end+len("\n		;;"):]

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
    s=s[:line_end+1] + "	mir4|" + bs + "\n" + s[line_end+1:]
    second=s.find(needle, line_end+1)
    if second<0: raise SystemExit("platform second mir3g anchor missing")
    line_end=s.find("\n", second)
    s=s[:line_end+1] + "	mir4|" + bs + "\n" + s[line_end+1:]
upg.write_text(s)

s=env.read_text()
if "	mir4)" not in s:
    pos=s.find("mir3g)")
    if pos<0: raise SystemExit("envtools mir3g anchor missing")
    end=s.find("\n	;;",pos)
    if end<0: raise SystemExit("envtools mir3g terminator missing")
    block='''\n	mir4)
	ubootenv_add_uci_config "/dev/mtd1" "0x0" "0x1000" "0x20000"
	;;
'''
    s=s[:end+len("\n	;;")]+block+s[end+len("\n	;;"):]
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
# OpenWrt 18.06 has old host-tool source URLs. Keep its pinned versions/hashes,
# but use currently reachable mirrors/releases.
python3 - "${ROOT}" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])

def set_source(path, url):
    p=root/path
    lines=p.read_text().splitlines()
    out=[]
    skipping=False
    for line in lines:
        if line.startswith("PKG_SOURCE_URL:="):
            out.append("PKG_SOURCE_URL:="+url)
            skipping=True
            continue
        if skipping and (line.startswith("	") or line.startswith("    ")):
            continue
        skipping=False
        out.append(line)
    p.write_text("\n".join(out)+"\n")

set_source("tools/expat/Makefile", "https://github.com/libexpat/libexpat/releases/download/R_2_2_9")
set_source("tools/scons/Makefile", "https://netix.dl.sourceforge.net/project/scons/scons/3.0.1")
set_source("tools/lzma/Makefile", "https://mirror2.openwrt.org/sources/")
set_source("tools/xz/Makefile", "https://github.com/tukaani-project/xz/releases/download/v5.2.4")

m4=root/"tools/m4/Makefile"
ms=m4.read_text()
ms=ms.replace("PKG_VERSION:=1.4.19","PKG_VERSION:=1.4.18")
ms=ms.replace("PKG_HASH:=63aede5c6d33b6d9b13511cd0be2cac046f2e70fd0a07aa9573a04a82783af96",
              "PKG_HASH:=f2c1e86ca0a404ff281631bdc8377638992744b175afb806e25871a24a934e07")
m4.write_text(ms)
PY

# m4 1.4.18 expects SIGSTKSZ to be a preprocessor constant. Ubuntu 22.04/glibc
# exposes a dynamic SIGSTKSZ, so apply the established gnulib portability fix.
mkdir -p "${ROOT}/tools/m4/patches"
cat > "${ROOT}/tools/m4/patches/999-glibc-2.34-sigstksz.patch" <<'PATCH'
--- a/lib/c-stack.c
+++ b/lib/c-stack.c
@@ -50,13 +50,8 @@
 #if ! HAVE_STACK_T && ! defined stack_t
 typedef struct sigaltstack stack_t;
 #endif
-#ifndef SIGSTKSZ
-# define SIGSTKSZ 16384
-#elif HAVE_LIBSIGSEGV && SIGSTKSZ < 16384
-/* libsigsegv 2.6 through 2.8 have a bug where some architectures use
-   more than the Linux default of an 8k alternate stack when deciding
-   if a fault was caused by stack overflow.  */
-# undef SIGSTKSZ
-# define SIGSTKSZ 16384
-#endif
+#ifdef SIGSTKSZ
+# undef SIGSTKSZ
+#endif
+#define SIGSTKSZ 16384
PATCH
echo "MIR4 board files ready."

# ---------------------------------------------------------------------------
# Xray-core v26.9.9 as a prebuilt mipsel softfloat binary.
#   * building 26.x needs Go >= 1.26 (crypto/hpke), the 18.06 golang feed
#     stops at Go 1.21;
#   * PassWall 4.69-4 only ships xray 1.8.4;
#   * the official mips32le zip is not guaranteed to be softfloat, and
#     MT7621 has no FPU - so use the locally verified build instead.
XDIR="${ROOT}/package/passwall/xray-core"
mkdir -p "${XDIR}/files"
curl -fsSL --retry 3 -o "${XDIR}/files/xray" \
  https://github.com/xjejsbxd3749372/openwrt-xiaomi-mirouter-r4-passwall/releases/download/xray-v26.9.9/xray-mipsle-1.26.8
echo "41e2aabfbce4218c5ee0ea82c639c0da7424c159739f829538e11682955af4e6  ${XDIR}/files/xray" | sha256sum -c -

# exactly one definition of "xray-core" may stay in the tree, otherwise
# make picks the feed copy (1.8.4) and the prebuilt never gets installed.
rm -rf package/feeds/packages/xray-core feeds/packages/net/xray-core

cat > "${XDIR}/Makefile" <<'XRAYMK'
include $(TOPDIR)/rules.mk

PKG_NAME:=xray-core
PKG_VERSION:=26.9.9
PKG_RELEASE:=1
PKG_LICENSE:=MPL-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_FLAGS:=nostrip

include $(INCLUDE_DIR)/package.mk

define Package/xray/template
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=IP Addresses and Names
  TITLE:=Xray-core proxy platform
  DEPENDS:=+libpthread +libm
endef

define Package/xray-core
  $(call Package/xray/template)
  TITLE:=Xray-core v26.9.9 (prebuilt mipsel softfloat)
endef

define Package/xray-example
  $(call Package/xray/template)
  TITLE:=Xray-core example configuration
endef

define Package/xray-core/description
 Xray-core v26.9.9 prebuilt static mipsel softfloat binary, built with
 Go 1.26.8 so it runs on the OpenWrt 18.06 (Linux 4.14) kernel.
endef

define Package/xray-example/description
 Example Xray configuration files.
endef

define Package/xray-core/conffiles
/etc/config/xray
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/xray-core/install
	$(INSTALL_DIR) $(1)/usr/bin/
	$(INSTALL_BIN) $(CURDIR)/files/xray $(1)/usr/bin/xray
	$(INSTALL_DIR) $(1)/etc/xray/
	$(INSTALL_DATA) $(CURDIR)/files/config.json.example $(1)/etc/xray/
	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_CONF) $(CURDIR)/files/xray.conf $(1)/etc/config/xray
	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) $(CURDIR)/files/xray.init $(1)/etc/init.d/xray
endef

define Package/xray-example/install
	$(INSTALL_DIR) $(1)/etc/xray/
	$(INSTALL_DATA) $(CURDIR)/files/config.json.example $(1)/etc/xray/
endef

$(eval $(call BuildPackage,xray-core))
$(eval $(call BuildPackage,xray-example))
XRAYMK

test -s "${XDIR}/files/xray"
test -f "${XDIR}/Makefile"
echo "xray-core 26.9.9 (prebuilt) installed"
