#!/usr/bin/env bash
set -euo pipefail

OWNER="nico-spaenkuch"
REPO="lvrsys-log-converter-releases"
API="https://api.github.com/repos/${OWNER}/${REPO}/releases?per_page=20"

fail() {
    echo "FEHLER: $*" >&2
    exit 1
}

if [ "$(id -u)" -ne 0 ]; then
    fail "Bitte als root ausführen, z. B. curl -fsSL https://raw.githubusercontent.com/${OWNER}/${REPO}/main/install-linux.sh | sudo bash"
fi

command -v curl >/dev/null 2>&1 || fail "curl wurde nicht gefunden."
command -v python3 >/dev/null 2>&1 || fail "python3 wurde nicht gefunden."
command -v apt-get >/dev/null 2>&1 || fail "apt-get wurde nicht gefunden. Dieses Skript ist für Debian/Ubuntu-basierte Systeme gedacht."
command -v dpkg-deb >/dev/null 2>&1 || fail "dpkg-deb wurde nicht gefunden."

ARCH="$(dpkg --print-architecture 2>/dev/null || true)"
[ "$ARCH" = "amd64" ] || fail "Aktuell wird nur amd64/x86-64 unterstützt (erkannt: ${ARCH:-unbekannt})."

TMP_JSON="$(mktemp)"
TMP_DEB="$(mktemp --suffix=.deb)"
trap 'rm -f "$TMP_JSON" "$TMP_DEB"' EXIT

curl -fsSL \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2026-03-10' \
    "$API" -o "$TMP_JSON"

readarray -t RELEASE_INFO < <(python3 - "$TMP_JSON" <<'PY'
import json
import re
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    releases = json.load(f)

version_re = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")
asset_re = re.compile(r"^lvrsys-log-converter_(\d+\.\d+\.\d+)_amd64\.deb$")

candidates = []
for release in releases:
    if release.get("draft"):
        continue
    m = version_re.match(str(release.get("tag_name", "")))
    if not m:
        continue
    version = tuple(map(int, m.groups()))
    for asset in release.get("assets", []):
        name = str(asset.get("name", ""))
        am = asset_re.match(name)
        if not am:
            continue
        if am.group(1) != ".".join(map(str, version)):
            continue
        candidates.append((version, name, asset.get("browser_download_url", "")))

if not candidates:
    raise SystemExit("Kein installierbares amd64-DEB in den öffentlichen Releases gefunden.")

version, name, url = max(candidates, key=lambda x: x[0])
print(".".join(map(str, version)))
print(name)
print(url)
PY
)

[ "${#RELEASE_INFO[@]}" -eq 3 ] || fail "Release-Daten konnten nicht ausgewertet werden."

VERSION="${RELEASE_INFO[0]}"
ASSET="${RELEASE_INFO[1]}"
URL="${RELEASE_INFO[2]}"

[ -n "$URL" ] || fail "Download-URL fehlt."

echo "LVRSys Log Converter ${VERSION}"
echo "Download: ${ASSET}"

curl -fL --progress-bar "$URL" -o "$TMP_DEB"

PKG="$(dpkg-deb -f "$TMP_DEB" Package)"
VER="$(dpkg-deb -f "$TMP_DEB" Version)"
PKG_ARCH="$(dpkg-deb -f "$TMP_DEB" Architecture)"

[ "$PKG" = "lvrsys-log-converter" ] || fail "Unerwarteter Paketname: $PKG"
[ "$VER" = "$VERSION" ] || fail "Paketversion $VER stimmt nicht mit Release $VERSION überein."
[ "$PKG_ARCH" = "amd64" ] || fail "Unerwartete Paketarchitektur: $PKG_ARCH"

echo
apt-get install -y "$TMP_DEB"

echo
echo "LVRSys Log Converter ${VERSION} wurde installiert/aktualisiert."
echo "Start: lvrsys-log-converter"
