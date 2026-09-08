#!/usr/bin/env bash
# ffshell-ffmpeg temp build wrapper
# Copies src to temp, runs android.sh with forwarded args, builds package.zip there,
# then copies build/package/*.zip + manifest.json back to original and cleans temp.
#
# Usage:
#   ./build.sh [--arch ARCHS] [--full] [--help] [--keep-temp]
#   ./build.sh --arch x86_64
#   ./build.sh --arch x86_64,arm64-v8a --full
#   ./build.sh --arch arm64-v8a --keep-temp   # leave /tmp for inspection
#
# All args except --keep-temp/--no-package are forwarded verbatim to android.sh.
# package.sh is run automatically after android.sh; pass --no-package to skip.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIGINAL_BUILD_PACKAGE_DIR="$SCRIPT_DIR/build/package"

KEEP_TEMP=0
NO_PACKAGE=0
ANDROID_ARGS=()
PKG_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --keep-temp) KEEP_TEMP=1 ;;
    --no-package) NO_PACKAGE=1 ;;
    --help|-h)
      echo "Usage: $0 [--arch ARCHS] [--full] [--keep-temp] [--no-package] [--help]"
      echo ""
      echo "  Temp wrapper around android.sh + package.sh:"
      echo "    1) copies src to mktemp dir (excludes build artifacts)"
      echo "    2) runs android.sh <forwarded args>"
      echo "    3) runs package.sh"
      echo "    4) copies build/package/*.zip + manifest.json back to $ORIGINAL_BUILD_PACKAGE_DIR"
      echo "    5) cleans temp (unless --keep-temp)"
      echo ""
      echo "  Forwarded to android.sh:"
      ANDROID_ARGS+=("$arg")
      ;;
    *) ANDROID_ARGS+=("$arg") ;;
  esac
done

# If user asked --help, still forward to android.sh after showing wrapper help
if [[ " ${ANDROID_ARGS[*]:-} " == *" --help "* ]] || [[ " ${ANDROID_ARGS[*]:-} " == *" -h "* ]]; then
  echo "--- android.sh --help follows ---"
fi

TEMP_DIR=""
cleanup() {
  local rc=$?
  if [[ $KEEP_TEMP -eq 1 && -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    echo "[build.sh] --keep-temp: leaving temp at $TEMP_DIR (exit $rc)" >&2
    return $rc
  fi
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    echo "[build.sh] cleaning temp $TEMP_DIR" >&2
    rm -rf "$TEMP_DIR"
  fi
  return $rc
}
trap cleanup EXIT INT TERM

TEMP_DIR="$(mktemp -d -t ffshell-ffmpeg-build-XXXXXX)"
echo "[build.sh] SCRIPT_DIR=$SCRIPT_DIR"
echo "[build.sh] TEMP_DIR=$TEMP_DIR"
echo "[build.sh] ANDROID_ARGS=${ANDROID_ARGS[*]:-<none>}"

# Copy src to temp. Exclude heavy / generated dirs to keep temp lean.
# Use rsync if available (faster, respects excludes), fallback to cp -a.
copy_src() {
  if command -v rsync >/dev/null 2>&1; then
    rsync -a \
      --exclude='.cxx' \
      --exclude='build' \
      --exclude='build-tools' \
      --exclude='ffmpeg-build' \
      --exclude='out' \
      --exclude='combined' \
      --exclude='.gradle' \
      --exclude='*.zip' \
      --exclude='*.log' \
      "$SCRIPT_DIR"/ "$TEMP_DIR"/
  else
    # cp fallback: copy everything then prune excluded dirs if present
    cp -a "$SCRIPT_DIR/." "$TEMP_DIR"/
    rm -rf "$TEMP_DIR/.git" "$TEMP_DIR/build" "$TEMP_DIR/build-tools" "$TEMP_DIR/ffmpeg-build" "$TEMP_DIR/out" "$TEMP_DIR/combined" 2>/dev/null || true
  fi
}

echo "[build.sh] copying src to temp..."
copy_src
chmod +x "$TEMP_DIR/android.sh" "$TEMP_DIR/package.sh" 2>/dev/null || true

echo "[build.sh] running android.sh in temp..."
(
  cd "$TEMP_DIR"
  # Forward all original args (minus wrapper-only flags) to android.sh
  ./android.sh "${ANDROID_ARGS[@]}"
)
echo "[build.sh] android.sh completed."

# Skip packaging for --help (android.sh didn't build libs, package.sh would fail)
HAS_HELP=0
for a in "${ANDROID_ARGS[@]}"; do [[ "$a" == "--help" || "$a" == "-h" ]] && HAS_HELP=1 && break; done

if [[ $NO_PACKAGE -eq 1 || $HAS_HELP -eq 1 ]]; then
  if [[ $HAS_HELP -eq 1 ]]; then
    echo "[build.sh] --help detected: skipping package.sh"
  else
    echo "[build.sh] --no-package: skipping package.sh"
  fi
else
  echo "[build.sh] running package.sh in temp..."
  (
    cd "$TEMP_DIR"
    ./package.sh "${PKG_ARGS[@]}"
  )
  echo "[build.sh] package.sh completed."

  # Copy generated artifacts back to original
  if compgen -G "$TEMP_DIR/build/package/*.zip" > /dev/null; then
    mkdir -p "$ORIGINAL_BUILD_PACKAGE_DIR"
    echo "[build.sh] copying artifacts to $ORIGINAL_BUILD_PACKAGE_DIR"
    cp -v "$TEMP_DIR/build/package/"*.zip "$ORIGINAL_BUILD_PACKAGE_DIR"/
    if [[ -f "$TEMP_DIR/build/package/manifest.json" ]]; then
      cp -v "$TEMP_DIR/build/package/manifest.json" "$ORIGINAL_BUILD_PACKAGE_DIR"/
    fi
    # Also copy zip that package.sh places at /tmp/ffshell-ffmpeg-*.zip (if present) — optional
    for f in /tmp/ffshell-ffmpeg-*.zip; do
      [[ -f "$f" ]] && echo "[build.sh] temp package also at $f" || true
    done
    echo "[build.sh] artifacts:"
    ls -lh "$ORIGINAL_BUILD_PACKAGE_DIR" | cat
  else
    echo "[build.sh] ERROR: no zip found at $TEMP_DIR/build/package/*.zip" >&2
    echo "[build.sh] contents of $TEMP_DIR/build:" >&2
    ls -R "$TEMP_DIR/build" 2>&1 | head -n 100 >&2 || true
    exit 1
  fi
fi

echo "[build.sh] done. KEEP_TEMP=$KEEP_TEMP"
# trap will clean unless --keep-temp
