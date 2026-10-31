#!/usr/bin/env bash
#
# FFShell FFmpeg - distributable package builder (manifest + installer zip).
#
# Single source of truth for packaging, used by:
#   - .github/workflows/package.yml  (CI: pass version input as $1)
#   - local usage: ./package.sh [version]
#
# Produces: build/package/ffmpeg-runtime-<version>-<build_type>.zip
#           build/package/manifest.json
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VERSION_INPUT="${1:-}"
BUILD_TYPE_INPUT="${2:-${BUILD_TYPE:-}}"
STAGE_DIR="${STAGE_DIR:-/tmp/pkg-stage}"
OUT_DIR="$SCRIPT_DIR/build/package"
ABIS="arm64-v8a armeabi-v7a x86 x86_64"
PRIMARY_ABI="arm64-v8a"
API_LEVEL="25"
NDK_LABEL="r28c"

log() { echo "[package] $*"; }
die() { echo "[package] ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Tool discovery: llvm-readelf from NDK (ANDROID_NDK_PATH -> sdkmanager ->
# known SDK roots), falling back to PATH tools like CI runners have.
# ---------------------------------------------------------------------------
resolve_readelf() {
	local cands="" vers="" roots="" r v c
	[ -n "${ANDROID_NDK_PATH:-}" ] && cands="$cands $ANDROID_NDK_PATH"
	[ -n "${ANDROID_NDK_ROOT:-}" ] && cands="$cands $ANDROID_NDK_ROOT"
	[ -n "${ANDROID_NDK_HOME:-}" ] && cands="$cands $ANDROID_NDK_HOME"

	if command -v sdkmanager >/dev/null 2>&1; then
		vers=$(yes 2>/dev/null | sdkmanager --list_installed 2>/dev/null \
			| grep -oE 'ndk;[0-9.]+' | sed 's/^ndk;//' | sort -uV || true)
	fi

	roots="/opt/android-sdk $HOME/Android/Sdk /usr/local/share/android-sdk /usr/local/lib/android/sdk $HOME/Library/Android/sdk ${ANDROID_HOME:-} ${ANDROID_SDK_ROOT:-}"

	for c in $cands; do
		c="$c/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf"
		[ -x "$c" ] && { printf '%s\n' "$c"; return 0; }
	done

	for r in $roots; do
		[ -d "$r/ndk" ] || continue
		for pass in 1 2; do
			for v in $vers $(ls "$r/ndk" 2>/dev/null | sort -uV); do
				if [ "$pass" = "1" ]; then
					case "$v" in 28.*) ;; *) continue ;; esac   # prefer r28c family first
				fi
				c="$r/ndk/$v/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf"
				[ -x "$c" ] && { printf '%s\n' "$c"; return 0; }
			done
		done
	done

	command -v llvm-readelf 2>/dev/null && return 0
	command -v readelf 2>/dev/null && return 0
	return 1
}

READELF="$(resolve_readelf || true)"
if [ -n "$READELF" ]; then
	log "ELF tool: $READELF"
else
	log "WARNING: no readelf found - manifest soname/align will use defaults"
fi

# ---------------------------------------------------------------------------
# Stage per-ABI libs (mirrors download-artifact layout + local build layouts)
# ---------------------------------------------------------------------------
find_lib_for_abi() {
	local abi="$1" base hit
	local bases=(
		"$SCRIPT_DIR/combined/ffshell-libffmpeg-$abi"
		"$SCRIPT_DIR/out/$abi"
		"$SCRIPT_DIR/ffmpeg-build/$abi"
		"$SCRIPT_DIR/ffmpeg-build/$API_LEVEL/$abi"
	)
	local cands=()
	for base in "${bases[@]}"; do
		cands+=("$base/lib/libffmpeg.so" "$base/libffmpeg.so")
	done
	for c in "${cands[@]}"; do
		[ -f "$c" ] && { printf '%s\n' "$c"; return 0; }
	done
	for base in "${bases[@]}"; do
		if [ -d "$base" ]; then
			hit=$(find "$base" -name libffmpeg.so 2>/dev/null | head -1)
			[ -n "$hit" ] && { printf '%s\n' "$hit"; return 0; }
		fi
	done
	return 1
}

log "=== Staging per-ABI libs ==="
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
MISSING=""
AVAILABLE_ABIS=""
for abi in $ABIS; do
	src=$(find_lib_for_abi "$abi" || true)
	if [ -z "$src" ]; then
		MISSING="$MISSING $abi"
		log "WARNING: $abi not built - skipping"
		continue
	fi
	AVAILABLE_ABIS="$AVAILABLE_ABIS $abi"
	mkdir -p "$STAGE_DIR/$abi"
	cp "$src" "$STAGE_DIR/$abi/libffmpeg.so"
	log "OK $abi: $(du -h "$STAGE_DIR/$abi/libffmpeg.so" | cut -f1) ($src)"
done
# Trim leading space
AVAILABLE_ABIS=$(echo "$AVAILABLE_ABIS" | sed 's/^ //')
if [ -z "$AVAILABLE_ABIS" ]; then
	echo "Missing libffmpeg.so for all ABIs (tried:$MISSING)" >&2
	echo "Searched: combined/ffshell-libffmpeg-<abi>/{lib,}, out/<abi>/{lib,}, ffmpeg-build/<abi>/{lib,}, ffmpeg-build/$API_LEVEL/<abi>/{lib,}" >&2
	die "no libffmpeg.so found for any ABI - build at least one via: ./android.sh"
fi
if [ -n "$MISSING" ]; then
	log "Partial package: packing [$AVAILABLE_ABIS] (missing:$MISSING)"
fi

# ---------------------------------------------------------------------------
# Version detection (input > git tag > strings > ffversion.h > git sha)
# ---------------------------------------------------------------------------
FFVERSION_H_CANDIDATES=()
# Generated headers may live under several build layouts (with/without API level).
for _abi in "$PRIMARY_ABI" $AVAILABLE_ABIS; do
	for _root in "$SCRIPT_DIR/ffmpeg-build" "$SCRIPT_DIR/ffmpeg-build/$API_LEVEL"; do
		FFVERSION_H_CANDIDATES+=("$_root/$_abi/include/libavutil/ffversion.h")
	done
done
FFVERSION_H_CANDIDATES+=(
	"$SCRIPT_DIR/build-src/ffmpeg/libavutil/ffversion.h"
	"$SCRIPT_DIR/ffmpeg/libavutil/ffversion.h"
)

if [ -n "$VERSION_INPUT" ]; then
	PKG_VERSION="$VERSION_INPUT"
elif PKG_TAG=$(git describe --tags --exact-match 2>/dev/null); then
	log "git tag detected: $PKG_TAG"
	PKG_VERSION=$(printf '%s' "$PKG_TAG" | sed 's/^v//')
else
	PKG_VERSION=$(find "$STAGE_DIR" -name libffmpeg.so | head -1 \
		| xargs -I{} sh -c 'strings {} | grep -m1 "N-.*-g" | head -1' 2>/dev/null || true)
	if [ -z "$PKG_VERSION" ]; then
		for f in "${FFVERSION_H_CANDIDATES[@]}"; do
			PKG_VERSION=$(grep -m1 '#define FFMPEG_VERSION' "$f" 2>/dev/null | cut -d'"' -f2 || true)
			[ -n "$PKG_VERSION" ] && break
		done
		[ -n "$PKG_VERSION" ] || PKG_VERSION="git-$(git rev-parse --short HEAD)"
	fi
	PKG_VERSION="1.0.0+${PKG_VERSION}"
fi

AV_VERSION=""
# Search every generated ffversion.h under the builder tree (any layout).
while IFS= read -r _ffv; do
	[ -n "$_ffv" ] || continue
	AV_VERSION=$(grep -m1 '#define FFMPEG_VERSION' "$_ffv" 2>/dev/null | cut -d'"' -f2 || true)
	[ -n "$AV_VERSION" ] && break
done < <(find "$SCRIPT_DIR" -type f -name "ffversion.h" 2>/dev/null)
if [ -z "$AV_VERSION" ]; then
	# Try strings from staged libs, prefer PRIMARY_ABI then any available
	for try_abi in "$PRIMARY_ABI" $AVAILABLE_ABIS; do
		[ -f "$STAGE_DIR/$try_abi/libffmpeg.so" ] || continue
		AV_VERSION=$(strings "$STAGE_DIR/$try_abi/libffmpeg.so" 2>/dev/null | grep -E "N-[0-9]+-g[0-9a-f]+" | head -1 || true)
		[ -n "$AV_VERSION" ] && break
	done
fi
[ -n "$AV_VERSION" ] || AV_VERSION="unknown"
# Prefer a provided release tag over a bare commit hash produced by shallow checkouts.
if [ "$AV_VERSION" = "unknown" ] || echo "$AV_VERSION" | grep -qE '^[0-9a-f]{7,}$'; then
	if [ -n "${FFMPEG_TAG:-}" ]; then
		AV_VERSION="$FFMPEG_TAG"
	fi
fi

FFMPEG_CONF=""
FFMPEG_CONFIG_MAK=""
# Prefer generated build trees (they contain the real configure flags).
while IFS= read -r _cfg; do
	[ -n "$_cfg" ] || continue
	FFMPEG_CONFIG_MAK="$_cfg"
	break
done < <(find "$SCRIPT_DIR" -type f -path "*/ffbuild/config.mak" 2>/dev/null | head -1)
if [ -n "$FFMPEG_CONFIG_MAK" ]; then
	FFMPEG_CONF=$(grep '^FFMPEG_CONFIGURATION=' "$FFMPEG_CONFIG_MAK" 2>/dev/null | head -1 | cut -d= -f2- | head -c 2000 || true)
fi
BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Build type: explicit input/env wins; otherwise infer from FFmpeg configuration.
if [ -n "$BUILD_TYPE_INPUT" ]; then
	BUILD_TYPE=$(printf '%s' "$BUILD_TYPE_INPUT" | tr '[:upper:]' '[:lower:]')
else
	case "$FFMPEG_CONF" in
		*--enable-nonfree*|*--enable-gpl*) BUILD_TYPE="full" ;;
		*) BUILD_TYPE="minimal" ;;
	esac
fi
case "$BUILD_TYPE" in
	full|minimal) ;;
	*) echo "[package] ERROR: unsupported build type '$BUILD_TYPE' (use full or minimal)" >&2; exit 1 ;;
esac
log "BUILD_TYPE=$BUILD_TYPE"

# Derive license name from the FFmpeg configuration.
LICENSE_NAME="LGPL-2.1-or-later"
case "$FFMPEG_CONF" in
	*--enable-nonfree*) LICENSE_NAME="Non-free" ;;
	*--enable-gpl*)
		case "$FFMPEG_CONF" in
			*--enable-version3*) LICENSE_NAME="GPL-3.0-or-later" ;;
			*) LICENSE_NAME="GPL-2.0-or-later" ;;
		esac
		;;
	*--enable-version3*) LICENSE_NAME="LGPL-3.0-or-later" ;;
esac
log "LICENSE_NAME=$LICENSE_NAME"

log "PKG_VERSION=$PKG_VERSION"
log "AV_VERSION=$AV_VERSION"

# ---------------------------------------------------------------------------
# manifest.json (installer compatible)
# ---------------------------------------------------------------------------
# Build abIs JSON array exactly matching packed ABIs (permissive: 1-4)
ABIS_JSON=$(printf '"%s",' $AVAILABLE_ABIS | sed 's/,$//')
cat > "$STAGE_DIR/manifest.json" <<EOF
{
  "name": "ffshell-ffmpeg",
  "version": "$PKG_VERSION",
  "build_type": "$BUILD_TYPE",
  "ffmpeg_version": "$AV_VERSION",
  "ffmpeg_configuration": "$FFMPEG_CONF",
  "api_level": 25,
  "ndk": "$NDK_LABEL",
  "abIs": [$ABIS_JSON],
  "ffshell_api": ["ffshell_ffmpeg_run", "ffshell_cancel", "ffshell_get_version", "ffshell_set_log_callback", "ffshell_set_path_callback", "ffshell_ffprobe_run"],
  "minSdk": 25,
  "license": "$LICENSE_NAME",
  "build_date": "$BUILD_DATE",
  "instructions": "Use installer: Installer.install(packageFd, getNoBackupFilesDir()+\"/ffshell\") - installer auto-detects ABI and extracts only required lib.",
  "libs": {
EOF

first=1
for abi in $AVAILABLE_ABIS; do
	LIB="$STAGE_DIR/$abi/libffmpeg.so"
	[ -f "$LIB" ] || continue
	SIZE=$(stat -c%s "$LIB")
	SHA256=$(sha256sum "$LIB" | cut -d' ' -f1)
	SONAME=$($READELF -d "$LIB" 2>/dev/null | grep SONAME | sed -n 's/.*\[\(.*\)\]/\1/p' || true)
	[ -n "$SONAME" ] || SONAME="libffmpeg.so"
	ALIGN=$($READELF -lW "$LIB" 2>/dev/null | awk '/^  LOAD/ {print $NF}' | head -1 | tr -d '[]' || true)
	[ -n "$ALIGN" ] || ALIGN="0x4000"
	[ "$first" -eq 0 ] && echo "," >> "$STAGE_DIR/manifest.json"
	first=0
	cat >> "$STAGE_DIR/manifest.json" <<EOF
            "$abi": {"path": "$abi/libffmpeg.so", "size": $SIZE, "sha256": "$SHA256", "soname": "$SONAME", "align": "$ALIGN"}
EOF
done

cat >> "$STAGE_DIR/manifest.json" <<EOF
          },
          "headers": null,
          "changelog": "ffprobe 16KB + mediacodec + per-ABI binaries only (no headers, less nesting)"
        }
EOF

# Pretty-print the manifest for stable, readable output.
python3 -m json.tool "$STAGE_DIR/manifest.json" > "$STAGE_DIR/manifest.pretty.json" && mv "$STAGE_DIR/manifest.pretty.json" "$STAGE_DIR/manifest.json"
python3 -m json.tool "$STAGE_DIR/manifest.json" >/dev/null && log "manifest.json valid"

# ---------------------------------------------------------------------------
# Package extras (README/LICENSE/INSTALL.txt with CI fallbacks)
# ---------------------------------------------------------------------------
cp README.md "$STAGE_DIR/README.md" 2>/dev/null || printf '# FFShell FFmpeg\n' > "$STAGE_DIR/README.md"
LICENSE_SRC=""
case "$LICENSE_NAME" in
	"GPL-3.0-or-later") [ -f COPYING.GPLv3 ] && LICENSE_SRC="COPYING.GPLv3" ;;
	"GPL-2.0-or-later") [ -f COPYING.GPLv2 ] && LICENSE_SRC="COPYING.GPLv2" ;;
	"LGPL-3.0-or-later") [ -f COPYING.LGPLv3 ] && LICENSE_SRC="COPYING.LGPLv3" ;;
	"LGPL-2.1-or-later") [ -f COPYING.LGPLv2.1 ] && LICENSE_SRC="COPYING.LGPLv2.1" ;;
esac
if [ -n "$LICENSE_SRC" ]; then
	cp "$LICENSE_SRC" "$STAGE_DIR/LICENSE"
elif [ -f "LICENSE" ]; then
	cp LICENSE "$STAGE_DIR/LICENSE"
else
	printf '%s\n' "$LICENSE_NAME" > "$STAGE_DIR/LICENSE"
fi
cat > "$STAGE_DIR/INSTALL.txt" <<EOF
FFShell FFmpeg Package (per-ABI binaries only, no outer folder)
=============================================================
Structure: <abi>/libffmpeg.so + manifest.json, no libs/, no include, no outer pkg dir)

Installer usage (auto ABI, storage saving):
  int fd = open("ffmpeg-runtime-*.zip", O_RDONLY);
  Installer.install(fd, "/data/data/com.app/files/ffshell");
  // Only host ABI (e.g. arm64-v8a) is extracted - installer searches by suffix

Manifest: manifest.json contains version, sha256, align.
EOF

# ---------------------------------------------------------------------------
# Zip creation (flat layout: <abi>/libffmpeg.so at zip root, no outer folder)
# ---------------------------------------------------------------------------
PKG_VERSION=$(grep '"version"' "$STAGE_DIR/manifest.json" | head -1 | cut -d'"' -f4 | tr -d ' ' | head -c 50)
[ -n "$PKG_VERSION" ] || PKG_VERSION="1.0.0+unknown"
PKG_NAME="ffmpeg-runtime-${PKG_VERSION}-${BUILD_TYPE}"
ZIP_OUT="/tmp/${PKG_NAME}.zip"

log "Creating $ZIP_OUT"
if command -v zip >/dev/null 2>&1; then
	( cd "$STAGE_DIR" && zip -r "$ZIP_OUT" . ) > /dev/null
else
	log "zip CLI not found - using python3 zipfile fallback"
	(
		cd "$STAGE_DIR"
		ZIP_OUT="$ZIP_OUT" python3 - <<'PY'
import os, zipfile
out = os.environ["ZIP_OUT"]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
    for dirpath, dirs, files in sorted(os.walk(".")):
        for name in sorted(files):
            path = os.path.join(dirpath, name)
            arc = os.path.relpath(path, ".")
            info = zipfile.ZipInfo.from_file(path, arc)
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(path, "rb") as src:
                zf.writestr(info, src.read())
PY
	)
fi
ls -lh "$ZIP_OUT"

# ---------------------------------------------------------------------------
# Validation (installer dry-run parity)
# ---------------------------------------------------------------------------
MANIFEST_PATH=$(unzip -l "$ZIP_OUT" | awk '{print $4}' | grep "manifest.json" | head -1 || true)
[ -n "$MANIFEST_PATH" ] || die "manifest.json not found inside $ZIP_OUT"
log "Manifest path in zip: $MANIFEST_PATH"
unzip -p "$ZIP_OUT" "$MANIFEST_PATH" | python3 -m json.tool | head -80
for abi in $AVAILABLE_ABIS; do
	unzip -l "$ZIP_OUT" | grep -q "$abi/libffmpeg.so" \
		|| die "missing $abi/libffmpeg.so in package (expected for packed ABI)"
	log "found $abi/libffmpeg.so"
done
if [ "$(echo "$AVAILABLE_ABIS" | wc -w)" -lt 4 ]; then
	log "WARNING: partial package ($AVAILABLE_ABIS) - $(echo "$MISSING" | wc -w) ABI(s) missing"
fi
log "Package validation OK - installer compatible (zip with $AVAILABLE_ABIS/libffmpeg.so + manifest.json)"

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
mkdir -p "$OUT_DIR"
cp "$ZIP_OUT" "$OUT_DIR/"
cp "$STAGE_DIR/manifest.json" "$OUT_DIR/" 2>/dev/null || true
ls -lh "$OUT_DIR/"

if [ -n "${GITHUB_ENV:-}" ]; then
	{ echo "PKG_NAME=${PKG_NAME}"; echo "PKG_VERSION=${PKG_VERSION}"; echo "PKG_BUILD_TYPE=${BUILD_TYPE}"; } >> "$GITHUB_ENV"
fi
log "DONE PKG_NAME=${PKG_NAME}"
