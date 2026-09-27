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
