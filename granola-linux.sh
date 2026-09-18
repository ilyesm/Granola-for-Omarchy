#!/usr/bin/env bash

set -euo pipefail

DMG="${1:-}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications/granola}"
CACHE_DIR="${CACHE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.cache}"
DESKTOP_FILE="${DESKTOP_FILE:-$HOME/.local/share/applications/granola.desktop}"
RES="Granola/Granola.app/Contents/Resources"

die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
step() { printf '\n\033[1;36m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$CACHE_DIR"

if [[ -z "$DMG" ]]; then
  step "Downloading the latest Granola .dmg"
  DMG="$CACHE_DIR/Granola-latest.dmg"
  curl -fL --progress-bar -o "$DMG.part" "https://api.granola.ai/v1/download-latest" \
    || die "could not download Granola .dmg from api.granola.ai"
  mv "$DMG.part" "$DMG"
  info "$DMG"
elif [[ ! -f "$DMG" ]]; then
  die "no such file: $DMG"
fi


step "Checking prerequisites"

for cmd in node npm python3 curl make; do
  command -v "$cmd" >/dev/null || die "'$cmd' not found. Please install it."
done

HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  x86_64)  EL_ARCH=x64;   SEVEN_ARCH=x64;   NODE_ARCH=x64 ;;
  aarch64) EL_ARCH=arm64; SEVEN_ARCH=arm64; NODE_ARCH=arm64 ;;
  *) die "unsupported architecture: $HOST_ARCH (need x86_64 or aarch64)" ;;
esac
info "host: $HOST_ARCH (Electron linux-$EL_ARCH)"


SEVENZZ="$(command -v 7zz || true)"
if [[ -z "$SEVENZZ" ]]; then
  SEVENZZ="$CACHE_DIR/7zz"
  if [[ ! -x "$SEVENZZ" ]]; then
    info "7zz not found, downloading the official static build (LZFSE support)"
    curl -fsSL -o "$WORK/7z.tar.xz" "https://www.7-zip.org/a/7z2501-linux-${SEVEN_ARCH}.tar.xz" \
      || die "could not download 7zz; install it manually and re-run"
    tar xf "$WORK/7z.tar.xz" -C "$CACHE_DIR" 7zz
    chmod +x "$SEVENZZ"
  fi
fi
info "7zz:  $SEVENZZ"


CXX=""
for v in 15 14 13 12 11; do
  if command -v "g++-$v" >/dev/null; then CXX="g++-$v"; CC="gcc-$v"; break; fi
done
if [[ -z "$CXX" ]] && command -v g++ >/dev/null; then
  if [[ "$(g++ -dumpversion | cut -d. -f1)" -ge 11 ]]; then CXX=g++; CC=gcc; fi
fi
[[ -n "$CXX" ]] || die "need g++ 11 or newer (Electron 42 headers require C++20). Try: sudo apt install g++-11"
info "compiler: $CXX ($($CXX -dumpversion))"


step "Reading Electron version from the .dmg"

"$SEVENZZ" e "$DMG" \
  "Granola/Granola.app/Contents/Frameworks/Electron Framework.framework/Versions/A/Resources/Info.plist" \
  -o"$WORK/fw" -y >/dev/null || die "could not read the .dmg (is it a Granola disk image?)"
EL_VER="$(grep -A1 CFBundleVersion "$WORK/fw/Info.plist" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
[[ -n "$EL_VER" ]] || die "could not determine the Electron version"
info "Electron $EL_VER"

step "Fetching the Linux Electron runtime"

ZIP="$CACHE_DIR/electron-v$EL_VER-linux-$EL_ARCH.zip"
if [[ ! -f "$ZIP" ]]; then
  URL="https://github.com/electron/electron/releases/download/v$EL_VER/electron-v$EL_VER-linux-$EL_ARCH.zip"
  info "downloading $URL"
  curl -fL --progress-bar -o "$ZIP.part" "$URL" || die "download failed"
  mv "$ZIP.part" "$ZIP"
else
  info "using cached $(basename "$ZIP")"
fi

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
"$SEVENZZ" x "$ZIP" -o"$INSTALL_DIR" -y >/dev/null
chmod +x "$INSTALL_DIR/electron"
rm -f "$INSTALL_DIR/resources/default_app.asar"   # the "welcome to Electron" demo


step "Extracting the app payload"


"$SEVENZZ" x "$DMG" "$RES/app.asar" "$RES/app.asar.unpacked" "$RES/icons" \
  -o"$WORK/dmg" -y >/dev/null
cp -r "$WORK/dmg/$RES/app.asar" "$WORK/dmg/$RES/app.asar.unpacked" \
      "$WORK/dmg/$RES/icons" "$INSTALL_DIR/resources/"
cp "$INSTALL_DIR/resources/icons/icon.png" "$INSTALL_DIR/granola-icon.png"
"$SEVENZZ" e "$DMG" "Granola/Granola.app/Contents/Info.plist" -o"$WORK/appinfo" -y >/dev/null 2>&1 || true
APP_VER="$(grep -A1 CFBundleShortVersionString "$WORK/appinfo/Info.plist" 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)"
info "Granola ${APP_VER:-?} payload installed"


step "Patching the platform string"

# api.granola.ai answers 500 Internal Server Error to any request carrying
# platform=linux, including the sign-in URL, so login is impossible without
# this. The app maps darwin->macOS and win32->Windows and passes anything else
# through verbatim; rewrite that fallback so Linux reports Windows.
#
# The replacement is byte-for-byte the same length (padded with spaces) because
# an .asar has a header that records file offsets. Stock Electron does not
# verify asar integrity on Linux, so an in-place edit is safe.
python3 - "$INSTALL_DIR/resources/app.asar" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); data = p.read_bytes(); total = 0
for pat in (b'?`Windows`:window.electron.platform', b'?`Windows`:process.platform'):
    rep = b'?`Windows`:`Windows`'.ljust(len(pat))
    total += data.count(pat)
    data = data.replace(pat, rep)
if total == 0:
    sys.exit("no platform fallback found. Granola's bundler output may have changed")
p.write_bytes(data)
print(f"    rewrote {total} platform fallback(s)")
PYEOF


step "Rebuilding better-sqlite3-multiple-ciphers for Linux"

# Granola ships a *patched* fork of better-sqlite3-multiple-ciphers: it adds an
# updateHook() method that the renderer's cache layer calls on startup. Upstream
# npm builds do not have it, so dropping in a stock prebuilt binary gets you a
# window that dies with "r.updateHook is not a function".
#
# Their full C++ source is inside app.asar.unpacked, so build *that*. Only
# binding.gyp is missing from the bundle; take it from the matching npm release.
BS3="$INSTALL_DIR/resources/app.asar.unpacked/node_modules/better-sqlite3-multiple-ciphers"
BS3_VER="$(node -p "require('$BS3/package.json').version")"
info "building Granola's fork of v$BS3_VER from source"

cp -r "$BS3" "$WORK/bs3"
( cd "$WORK" && npm pack "better-sqlite3-multiple-ciphers@$BS3_VER" --silent >/dev/null \
    && tar xzf better-sqlite3-multiple-ciphers-*.tgz ) || die "could not fetch binding.gyp from npm"
cp "$WORK/package/binding.gyp" "$WORK/bs3/"

( cd "$WORK/bs3" && CC="$CC" CXX="$CXX" npx --yes node-gyp rebuild --release \
    --runtime=electron --target="$EL_VER" --arch="$NODE_ARCH" \
    --dist-url=https://electronjs.org/headers ) >"$WORK/build.log" 2>&1 \
  || { tail -30 "$WORK/build.log"; die "native build failed (full log: $WORK/build.log)"; }

cp "$WORK/bs3/build/Release/better_sqlite3.node" \
   "$WORK/bs3/build/Release/test_extension.node" "$BS3/build/Release/"


step "Building electron-click-drag-plugin for Linux"

# Granola's macOS payload only ships darwin / win32 / linux-x64 drag.node.
# The main process requires the addon at startup. Electron only loads
# unpacked files that are listed in the asar header, so on linux-arm64 we
# compile the upstream X11 implementation and drop it on the linux-x64
# path (already marked unpacked), then same-length-patch index.js to
# report arch x64 so the loader finds it.
DRAG="$INSTALL_DIR/resources/app.asar.unpacked/node_modules/electron-click-drag-plugin"
if [[ "$EL_ARCH" == "arm64" ]]; then
  info "no linux-arm64 prebuild; compiling from source"
  DRAG_SRC="$WORK/electron-click-drag-plugin"
  git clone --depth 1 https://github.com/Wargraphs/electron-click-drag-plugin.git "$DRAG_SRC" >/dev/null 2>&1 \
    || die "could not clone electron-click-drag-plugin"
  python3 - "$DRAG_SRC/binding.gyp" <<'PYEOF'
from pathlib import Path
import sys
p = Path(sys.argv[1]); t = p.read_text()
old = '''        [ "OS=='mac'", {'''
new = '''        [ "OS=='linux'", {
          "libraries": [ "-lX11" ]
        }],
        [ "OS=='mac'", {'''
if "OS=='linux'" not in t:
    if old not in t:
        raise SystemExit("binding.gyp pattern not found")
    p.write_text(t.replace(old, new, 1))
PYEOF
  ( cd "$DRAG_SRC" && npm install --no-audit --no-fund --no-save node-addon-api >/dev/null \
      && CC="$CC" CXX="$CXX" npx --yes node-gyp rebuild --release \
           --runtime=electron --target="$EL_VER" --arch="$NODE_ARCH" \
           --dist-url=https://electronjs.org/headers ) >"$WORK/drag-build.log" 2>&1 \
    || { tail -30 "$WORK/drag-build.log"; die "click-drag native build failed"; }
  python3 - "$DRAG" "$DRAG_SRC/build/Release/drag.node" "$INSTALL_DIR/resources/app.asar" <<'PYEOF'
import hashlib, struct, sys
from pathlib import Path

plugin = Path(sys.argv[1])
blob = Path(sys.argv[2]).read_bytes()
asar_path = Path(sys.argv[3])

index_path = plugin / "index.js"
index = index_path.read_bytes()
old = b"const arch = os.arch();"
new = b"const arch = 'x64';    "
if old not in index:
    raise SystemExit("click-drag index.js arch pattern not found")
index = index.replace(old, new, 1)
index_path.write_bytes(index)

dest = plugin / "build/Release/linux-x64/drag.node"
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_bytes(blob)
(plugin / "build/Release/drag.node").write_bytes(blob)
arm = plugin / "build/Release/linux-arm64/drag.node"
arm.parent.mkdir(parents=True, exist_ok=True)
arm.write_bytes(blob)

data = bytearray(asar_path.read_bytes())
json_str_len = struct.unpack_from("<I", data, 12)[0]
json_start = 16
text = bytes(data[json_start:json_start + json_str_len]).decode()

def swap(hay, old, new, label):
    if old == new:
        return hay
    if old not in hay:
        raise SystemExit(f"asar header missing {label}")
    if len(old) != len(new):
        raise SystemExit(f"asar header length mismatch for {label}: {len(old)} vs {len(new)}")
    return hay.replace(old, new, 1)

# linux-x64 drag.node size/hash. Size is a JSON number; keep digit count.
old_size = '"linux-x64":{"files":{"drag.node":{"size":65536'
new_size = f'"linux-x64":{{"files":{{"drag.node":{{"size":{len(blob):05d}'
if old_size in text:
    text = swap(text, old_size, new_size, "drag.node size")
old_hash = "31a45ef9ba72e377811843511814075d0634ba7d6eabb3b5f66e6278a18a4e96"
new_hash = hashlib.sha256(blob).hexdigest()
if old_hash in text:
    text = swap(text, old_hash, new_hash, "drag.node hash")
old_ih = "f4d95e2bd398c0b5f75bc7ebc056a8b73164acf518f17503b110ad33a8726c2d"
new_ih = hashlib.sha256(index).hexdigest()
if old_ih in text:
    text = swap(text, old_ih, new_ih, "index.js hash")

enc = text.encode()
if len(enc) != json_str_len:
    raise SystemExit(f"asar json length changed {json_str_len} -> {len(enc)}")
data[json_start:json_start + json_str_len] = enc
asar_path.write_bytes(data)
print(f"    linux-arm64 drag.node installed ({len(blob)} bytes)")
PYEOF
fi


step "Installing launcher and desktop entry"

cat > "$INSTALL_DIR/granola.sh" <<EOF
#!/usr/bin/env bash
DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "\${NODE_EXTRA_CA_CERTS:-}" && -f /etc/ca-certificates/trust-source/anchors/cloudflare-gateway-managed-g1.pem ]]; then
  export NODE_EXTRA_CA_CERTS=/etc/ca-certificates/trust-source/anchors/cloudflare-gateway-managed-g1.pem
  export NODE_USE_SYSTEM_CA=1
fi
exec "\$DIR/electron" --ozone-platform-hint=auto --password-store=gnome-libsecret "\$@"
EOF
chmod +x "$INSTALL_DIR/granola.sh"

mkdir -p "$(dirname "$DESKTOP_FILE")"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Granola
Comment=AI Notepad for meetings
Exec=$INSTALL_DIR/granola.sh %U
Icon=$INSTALL_DIR/granola-icon.png
Terminal=false
Categories=Office;Utility;
StartupWMClass=granola
MimeType=x-scheme-handler/granola;
EOF

ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
mkdir -p "$ICON_DIR"
cp "$INSTALL_DIR/granola-icon.png" "$ICON_DIR/granola.png"
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -f "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

command -v update-desktop-database >/dev/null && update-desktop-database "$(dirname "$DESKTOP_FILE")" 2>/dev/null || true

command -v xdg-mime >/dev/null && xdg-mime default "$(basename "$DESKTOP_FILE")" x-scheme-handler/granola 2>/dev/null || true


step "Smoke-testing the native module"

ELECTRON_RUN_AS_NODE=1 NODE_PATH="$INSTALL_DIR/resources/app.asar/node_modules" \
  "$INSTALL_DIR/electron" -e "
    const Database = require('$BS3/lib/index.js');
    const db = new Database('$WORK/smoke.db');
    db.pragma(\"cipher='sqlcipher'\");
    db.pragma(\"key='smoketest'\");
    db.exec('CREATE TABLE t(a)');
    let fired = false;
    db.updateHook(() => { fired = true; });
    db.prepare('INSERT INTO t VALUES (1)').run();
    if (db.prepare('SELECT count(*) c FROM t').get().c !== 1) throw new Error('insert failed');
    if (!fired) throw new Error('updateHook did not fire');
    db.close();
  " || die "smoke test failed, the app would not start"
info "encrypted database + updateHook both work"

printf '\n\033[32m✓ Granola %s is installed.\033[0m\n' "$APP_VER"
printf '  Launch it from your application menu, or run:\n    %s\n\n' "$INSTALL_DIR/granola.sh"
