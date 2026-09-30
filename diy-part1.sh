#!/usr/bin/env bash
set -euo pipefail
ROOT="$(pwd)"
PASSWALL="${ROOT}/package/passwall"
GOLANG="${ROOT}/feeds/packages/lang/golang"
MTK="${ROOT}/package/mtk-closed"
PW_REPO="${PASSWALL_REPO:-https://github.com/Openwrt-Passwall/openwrt-passwall.git}"
PW_TAG="${PASSWALL_CORE_TAG:-4.69-4}"
PW_LUCI="${PASSWALL_LUCI_COMMIT:-d1e618220a9a0a4b73d536101f452a2f4cf14861}"
GO_REPO="${GOLANG_REPO:-https://github.com/sbwml/packages_lang_golang.git}"
GO_BRANCH="${GOLANG_BRANCH:-21.x}"
MTK_REPO="${MTK_REPO:-https://github.com/coolsnowwolf/lede.git}"
MTK_COMMIT="${MTK_COMMIT:-24cb7521b659dac3f37907364d96eb998c1d04af}"

echo "== PassWall core ${PW_TAG}"
rm -rf "${PASSWALL}"
git clone --depth=1 --single-branch --branch "${PW_TAG}" "${PW_REPO}" "${PASSWALL}"
test -f "${PASSWALL}/xray-core/Makefile"
test -f "${PASSWALL}/shadowsocksr-libev/Makefile"

echo "== PassWall LuCI commit ${PW_LUCI}"
TMP_PW_LUCI="$(mktemp -d)"
git clone --filter=blob:none --no-checkout "${PW_REPO}" "${TMP_PW_LUCI}"
git -C "${TMP_PW_LUCI}" fetch --depth=1 origin "${PW_LUCI}"
git -C "${TMP_PW_LUCI}" checkout --detach FETCH_HEAD
rm -rf "${PASSWALL}/luci-app-passwall"
cp -a "${TMP_PW_LUCI}/luci-app-passwall" "${PASSWALL}/luci-app-passwall"
test -f "${PASSWALL}/luci-app-passwall/Makefile"
grep -q 'PKG_VERSION:=4.69-4' "${PASSWALL}/luci-app-passwall/Makefile"

echo "== Go ${GO_BRANCH}"
rm -rf "${GOLANG}"
TMP_GO="$(mktemp -d)"
git clone --depth=1 --single-branch --branch "${GO_BRANCH}" "${GO_REPO}" "${TMP_GO}"
mkdir -p "${GOLANG}"
cp -a "${TMP_GO}/golang/." "${GOLANG}/"
for f in golang-build.sh golang-compiler.mk golang-host-build.mk golang-package.mk golang-values.mk; do
  cp -a "${TMP_GO}/${f}" "${GOLANG}/${f}"
done
sed -i -e 's@include ../golang-compiler.mk@include ./golang-compiler.mk@' -e 's@include ../golang-package.mk@include ./golang-package.mk@' "${GOLANG}/Makefile"
test -f "${GOLANG}/Makefile"
test -f "${GOLANG}/golang-package.mk"

echo "== MTK proprietary WiFi ${MTK_COMMIT}"
rm -rf "${MTK}"
TMP_MTK="$(mktemp -d)"
git init "${TMP_MTK}"
git -C "${TMP_MTK}" remote add origin "${MTK_REPO}"
git -C "${TMP_MTK}" fetch --depth=1 origin "${MTK_COMMIT}"
git -C "${TMP_MTK}" checkout --detach FETCH_HEAD
for p in package/lean/mt/drivers/mt7603e package/lean/mt/drivers/mt7612e package/lean/mt/drivers/mt_wifi package/lean/mt/luci-app-mtwifi; do
  test -d "${TMP_MTK}/${p}"
done
mkdir -p "${MTK}/drivers" "${MTK}/luci"
cp -a "${TMP_MTK}/package/lean/mt/drivers/mt7603e" "${MTK}/drivers/"
cp -a "${TMP_MTK}/package/lean/mt/drivers/mt7612e" "${MTK}/drivers/"
cp -a "${TMP_MTK}/package/lean/mt/drivers/mt_wifi" "${MTK}/drivers/"
cp -a "${TMP_MTK}/package/lean/mt/luci-app-mtwifi" "${MTK}/luci/"

rm -rf feeds/luci/applications/luci-app-passwall feeds/packages/net/xray-core feeds/packages/net/v2ray-core feeds/packages/net/shadowsocks-rust feeds/packages/net/sing-box feeds/packages/net/naiveproxy feeds/packages/net/hysteria feeds/packages/net/trojan feeds/packages/net/trojan-go feeds/packages/net/v2ray-plugin feeds/packages/net/xray-plugin || true
echo "Preparation complete."

# ---------------------------------------------------------------------------
# OpenWrt 18.06 ships Linux 4.14, but the MTK closed driver reads
# task_struct.thread_pid, a field the kernel only gained in 4.19. Without
# this the driver fails to compile ("has no member named 'thread_pid'") and
# the whole build dies. task_pid(current) exists on both.
while IFS= read -r f; do
  sed -i 's/current->thread_pid/task_pid(current)/g' "$f"
  echo "kernel-4.14 compat applied: $f"
done < <(find package/mtk-closed -name rt_linux.h -type f)

# NOTE: the ssrplus feed is added by the workflow BEFORE "Update base feeds",
# because feeds update/install run ahead of this script.

echo "diy-part1 complete"
# ---------------------------------------------------------------------------
# Second kernel-4.14 incompatibility in the same driver: this MTK source is
# written against Linux >= 5.0, where access_ok() takes two arguments
# (addr, size). 4.14 still has the pre-5.0 three-argument form
# (type, addr, size), so every two-argument call fails with
#   error: macro "access_ok" requires 3 arguments, but only 2 given
# and the compiler then reports the identifier as undeclared. Rewrite only
# the two-argument call sites - the three-argument ones are left alone, as
# are any macro definitions.
python3 - <<'PYACC'
import pathlib, re

pat = re.compile(r"(?<![A-Za-z0-9_])access_ok\s*\(")
total = 0

def upgrade(text):
    out, i, n, changed = [], 0, len(text), 0
    while True:
        m = pat.search(text, i)
        if not m:
            out.append(text[i:])
            break
        start = m.end()
        depth, j, commas = 1, start, 0
        while j < n and depth:
            c = text[j]
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            elif c == "," and depth == 1:
                commas += 1
            j += 1
        if commas == 1:            # exactly two arguments
            out.append(text[i:start])
            out.append("VERIFY_READ, ")
            i, changed = start, changed + 1
        else:
            out.append(text[i:j])
            i = j
    return "".join(out), changed

for root in ["package/mtk-closed"]:
    for p in sorted(pathlib.Path(root).rglob("*")):
        if p.suffix not in (".c", ".h") or not p.is_file():
            continue
        try:
            src = p.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        if "access_ok" not in src:
            continue
        fixed, n = upgrade(src)
        if n:
            p.write_text(fixed, encoding="utf-8")
            print(f"  access_ok: {n} call(s) -> 3-arg form in {p}")
            total += n

print(f"  access_ok: {total} call(s) fixed for kernel 4.14")
PYACC
echo "diy-part1 kernel-4.14 fixes complete"
# ---------------------------------------------------------------------------
# Third batch of kernel-4.14 differences in the same MTK sources.
#
# 1) for_each_process() moved to <linux/sched/signal.h> in Linux 4.11, and
#    <linux/sched.h> no longer pulls it in -> "implicit declaration of
#    function 'for_each_process'", which then also breaks the statement.
#
# 2) This driver typedefs TIMER_FUNCTION as void (*)(struct timer_list *)
#    (the post-4.15 callback signature), but the code path it takes on
#    kernels older than 4.19 still does the pre-4.15 setup:
#        init_timer(pTimer);
#        pTimer->data = (unsigned long)data;
#        pTimer->function = function;      <-- incompatible pointer type
#    On 4.14 timer_list.function is still void (*)(unsigned long) and the
#    kernel hands it timer_list.data as the argument. Feed it the timer_list
#    itself instead: a post-4.15 style callback expects exactly that, so the
#    callback keeps working instead of being called with the wrong argument
#    (silencing the warning alone would turn this into a runtime crash).
python3 - <<'PYK414'
import pathlib, re

roots = pathlib.Path("package/mtk-closed")
sched_inc = "#include <linux/sched/signal.h>"
n_sched = 0

# --- 1) for_each_process / for_each_thread ---------------------------------
for p in sorted(roots.rglob("*.c")):
    s = p.read_text(encoding="utf-8", errors="ignore")
    if not re.search(r"\bfor_each_(process|thread)\b", s):
        continue
    if sched_inc in s:
        continue
    m = re.search(r"^#include\s+[<\"]", s, re.M)
    if not m:
        continue
    p.write_text(s[:m.start()] + sched_inc + "\n" + s[m.start():], encoding="utf-8")
    print(f"  <linux/sched/signal.h> added: {p}")
    n_sched += 1

# --- 2) pre-4.15 timer setup on a post-4.15 typedef -----------------------
new_style = "typedef void (*TIMER_FUNCTION)(struct timer_list *)"
has_new_typedef = any(
    new_style in (p.read_text(encoding="utf-8", errors="ignore"))
    for p in roots.rglob("*.h")
)
n_timer = 0
if has_new_typedef:
    trig = re.compile(r"pTimer->function\s*=\s*function\s*;")
    for p in sorted(roots.rglob("*.c")):
        s = p.read_text(encoding="utf-8", errors="ignore")
        if not trig.search(s):
            continue
        s = re.sub(r"pTimer->data\s*=\s*\(unsigned long\)data\s*;",
                   "pTimer->data = (unsigned long)pTimer;", s)
        s = trig.sub("pTimer->function = (void (*)(unsigned long))function;", s)
        p.write_text(s, encoding="utf-8")
        print(f"  timer compat applied: {p}")
        n_timer += 1
else:
    print("  WARNING: new-style TIMER_FUNCTION typedef not found, timer patch skipped")

print(f"  kernel-4.14 round 3: sched.h={n_sched} timer={n_timer}")
PYK414
echo "diy-part1 kernel-4.14 fixes complete"
