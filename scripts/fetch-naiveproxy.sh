#!/usr/bin/env bash
# Fetch official klzgrad naiveproxy static binary for mipsel_24kc
set -euo pipefail

NAIVE_VER="${NAIVEPROXY_VERSION:-v150.0.7871.63-1}"
OUT_DIR="${1:-${GITHUB_WORKSPACE:-.}/prebuilt}"
URL="https://github.com/klzgrad/naiveproxy/releases/download/${NAIVE_VER}/naiveproxy-${NAIVE_VER}-openwrt-mipsel_24kc-static.tar.xz"

mkdir -p "${OUT_DIR}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "Downloading ${URL}"
wget -qO "${TMP}/naive.tar.xz" "${URL}"
tar -xJf "${TMP}/naive.tar.xz" -C "${TMP}"

# Archive may contain naive or naiveproxy at root or in a subdir
BIN=""
for c in naive naiveproxy; do
  if [ -f "${TMP}/${c}" ]; then
    BIN="${TMP}/${c}"
    break
  fi
done
if [ -z "${BIN}" ]; then
  BIN="$(find "${TMP}" -type f \( -name naive -o -name naiveproxy \) | head -n1 || true)"
fi
if [ -z "${BIN}" ] || [ ! -f "${BIN}" ]; then
  echo "ERROR: naive binary not found in archive"
  find "${TMP}" -type f | head -50
  exit 1
fi

cp -a "${BIN}" "${OUT_DIR}/naiveproxy"
chmod +x "${OUT_DIR}/naiveproxy"
ls -lh "${OUT_DIR}/naiveproxy"
file "${OUT_DIR}/naiveproxy" || true
echo "naiveproxy ready: ${OUT_DIR}/naiveproxy"
