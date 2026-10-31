#!/bin/bash

### Describe Your Target Android Api or Architectures ###
ANDROID_API_LEVEL="25"
ARCH_LIST=("armv8a" "armv7a" "x86" "x86-64")


### Enable FFMPEG BUILD MODULES ####
# Minimal APK-bundlable build: --disable-everything + only what is listed
# here. Rule: native FFmpeg codecs/filters only (each a few KB), no external
# libs (x264/x265/vpx/lame/...), no network, no avdevice except lavfi.
ENABLED_CONFIG="\
		--enable-avcodec \
		--enable-avformat \
		--enable-avutil \
    --enable-swscale \
		--enable-swresample \
		--enable-libdav1d \
		--enable-avfilter \
		--enable-avdevice \
		--enable-mediacodec \
		--enable-jni \
    --enable-demuxer=* \
		--enable-filter=* \
		--enable-indev=lavfi \
		--enable-muxer=wav,mp4,matroska,webm,mp3,adts,flac,ogg,opus,mpegts,hls,dash,segment,gif,image2,srt \
	 	--enable-encoder=mjpeg,utvideo \
		--enable-encoder=aac,mpeg4 \
		--enable-encoder=opus,vorbis,flac \
		--enable-encoder=pcm_s16le,pcm_s24le \
		--enable-encoder=png,gif \
		--enable-encoder=h264_mediacodec,hevc_mediacodec \
		--enable-encoder=srt,mov_text,webvtt,ass \
		--enable-encoder=wrapped_avframe,rawvideo \
		--enable-decoder=wrapped_avframe,rawvideo \
		--enable-decoder=pcm_s32le,pcm_f32le,pcm_u8 \
		--enable-decoder=h264,hevc,vp8,vp9,libdav1d \
		--enable-decoder=flv,vp6f,gif,dvbsub,dvdsub,pgssub,utvideo \
		--enable-decoder=adpcm_swf,mpeg4,wmv3,mpeg1video,mpeg2video \
		--enable-decoder=mpeg2audio,msmpeg4v2,msmpeg4v3,theora,truehd \
		--enable-decoder=amrnb,amrwb,dvvideo,h263,mjpeg,png,jpeg,bmp \
		--enable-decoder=webp,mp3,aac,ac3,eac3,flac,opus,vorbis,pcm_s16le \
		--enable-decoder=pcm_s24le,alac,wma,ass,ssa,mov_text,subrip,webvtt \
		--enable-decoder=h264_mediacodec,hevc_mediacodec,mpeg2_mediacodec,mpeg4_mediacodec,vp8_mediacodec,vp9_mediacodec,av1_mediacodec \
		--enable-parser=* \
		--enable-bsf=* \
 		--enable-protocol=file,pipe,appfd \
    --enable-ffmpeg \
		--enable-ffprobe \
		--enable-shared \
		--enable-optimizations \
		--enable-lto \
		--enable-pic "


### Disable FFMPEG BUILD MODULES ####
DISABLED_CONFIG="\
		--disable-small \
		--disable-v4l2-m2m \
		--disable-cuda-llvm \
		--disable-libxml2 \
		--disable-network \
		--disable-static \
		--disable-debug \
		--disable-ffplay \
		--disable-doc \
		--disable-symver \
		--disable-gpl "




############ Dont Change ################
############ Dont Change ################
############ Dont Change ################
############ Dont Change ################
############ Dont Change ################

# Optional emulator perf: set ENABLE_X86_ASM=1 to enable asm for x86 32-bit (requires non-LTO, larger binary, emulator-only)
ENABLE_X86_ASM="${ENABLE_X86_ASM:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SRC_DIR="${SRC_DIR:-$SCRIPT_DIR/build-src}"
FFMPEG_SOURCE_DIR="${FFMPEG_SOURCE_DIR:-$SRC_DIR/ffmpeg}"
FFMPEG_BUILD_DIR="${FFMPEG_BUILD_DIR:-$SCRIPT_DIR/ffmpeg-build}"

FFMPEG_URL="https://git.ffmpeg.org/ffmpeg.git"
DAV1D_URL="https://code.videolan.org/videolan/dav1d.git"
X264_URL="https://code.videolan.org/videolan/x264.git"
X265_URL="https://bitbucket.org/multicoreware/x265_git.git"
VPX_URL="https://chromium.googlesource.com/webm/libvpx.git"
OPUS_URL="https://github.com/xiph/opus.git"
LAME_URL="https://github.com/rbrito/lame.git"
AOM_URL="https://aomedia.googlesource.com/aom.git"
ASS_URL="https://github.com/libass/libass.git"
FDKAAC_URL="https://github.com/mstorsjo/fdk-aac.git"
# Text stack for libass (minimal: freetype without harfbuzz + fribidi + harfbuzz without freetype loop)
FREETYPE_VERSION="2.13.3"
FREETYPE_URL="https://github.com/freetype/freetype.git"
FRIBIDI_URL="https://github.com/fribidi/fribidi.git"
HARFBUZZ_URL="https://github.com/harfbuzz/harfbuzz.git"
OGG_URL="https://github.com/xiph/ogg.git"
VORBIS_URL="https://github.com/xiph/vorbis.git"
WEBP_URL="https://chromium.googlesource.com/webm/libwebp.git"
SVTAV1_URL="https://gitlab.com/AOMediaCodec/SVT-AV1.git"
JXL_URL="https://github.com/libjxl/libjxl.git"
SOXR_URL="https://github.com/chirlu/soxr.git"
RUBBERBAND_URL="https://github.com/breakfastquay/rubberband.git"
VIDSTAB_URL="https://github.com/georgmartius/vid.stab.git"
XVID_URL="https://github.com/arthenica/xvidcore.git"



### Android NDK ###
# Auto-provisioned when absent: discovered via common SDK roots or sdkmanager,
# otherwise downloaded directly into ./build-tools/ (gitignored).
ANDROID_NDK_VERSION="r28c"
ANDROID_NDK_VERSION_NUM="28.2.13676358"
ANDROID_NDK_URL="https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_VERSION}-linux.zip"

# Parallel build tuning (override with JOBS=... ./android.sh)
NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
JOBS="${JOBS:-$(( NPROC > 8 ? 8 : NPROC ))}"

# Argument parsing: --full, --gpl, --arch, --help (supports FULL_BUILD=1 env)
FULL_BUILD="${FULL_BUILD:-0}"
GPL_BUILD="${GPL_BUILD:-0}"
ARCH_SET=0
# Preserve original args for later full-build header print
ARGS=("$@")
while [ $# -gt 0 ]; do
	case "$1" in
		--full|--full-build) FULL_BUILD=1; GPL_BUILD=0; shift ;;
		--gpl|--gpl-build) GPL_BUILD=1; FULL_BUILD=0; shift ;;
		--arch)
			if [ -z "${2:-}" ]; then echo -e "\e[1;31mError: --arch requires a value (e.g. --arch x86_64,armv8a)\e[0m" >&2; exit 1; fi
			ARCH_INPUT="$2"
			IFS=',' read -ra _archs <<< "$ARCH_INPUT"
			ARCH_LIST=()
			for _a in "${_archs[@]}"; do
				_a=$(echo "$_a" | xargs) # trim
				[ -z "$_a" ] && continue
				ARCH_LIST+=("$_a")
			done
			if [ ${#ARCH_LIST[@]} -eq 0 ]; then echo -e "\e[1;31mError: --arch parsed empty list\e[0m" >&2; exit 1; fi
			ARCH_SET=1
			shift 2
			;;
		--arch=*)
			ARCH_INPUT="${1#*=}"
			IFS=',' read -ra _archs <<< "$ARCH_INPUT"
			ARCH_LIST=()
			for _a in "${_archs[@]}"; do
				_a=$(echo "$_a" | xargs)
				[ -z "$_a" ] && continue
				ARCH_LIST+=("$_a")
			done
			if [ ${#ARCH_LIST[@]} -eq 0 ]; then echo -e "\e[1;31mError: --arch parsed empty list\e[0m" >&2; exit 1; fi
			ARCH_SET=1
			shift
			;;
		--help|-h)
			echo "Usage: $0 [--arch ARCHS] [--gpl|--full] [--help]"
			echo "  --arch ARCHS  Comma-separated list: x86_64,x86,armv8a,armv7a (aliases: arm64-v8a,armeabi-v7a,aarch64,arm,i686,x86-64 etc.)"
			echo "                Default (no --arch): builds all architectures: armv8a,armv7a,x86,x86-64"
			echo "                Examples:"
			echo "                  $0 --arch x86_64"
			echo "                  $0 --arch x86_64,armv8a --gpl"
			echo "                  $0 --arch=x86,armv7a --full"
			echo "  --gpl         GPL build: full feature set with GPL components, no non-free libraries (redistributable)"
			echo "  --full        Full build: enables all components including non-free libraries (not redistributable)"
			echo "  --help        Show this help"
			echo "Env: GPL_BUILD=1 $0  FULL_BUILD=1 $0  JOBS=8 $0  ARCH_LIST=\"x86-64 armv8a\" $0"
			exit 0
			;;
		--) shift; break ;;
		-*) echo -e "\e[1;31mUnknown option: $1\e[0m" >&2; echo "Try $0 --help" >&2; exit 1 ;;
		*) break ;;
	esac
done
if [ "$FULL_BUILD" = "1" ]; then
	echo -e "\e[1;32mFull build enabled (--full / FULL_BUILD=1): enabling almost every Android-compatible config\e[0m"
fi
# Early validation + deduplicate ARCH_LIST (fail fast before fetching)
_tmp_arch=()
for _a in "${ARCH_LIST[@]}"; do
	case " ${_tmp_arch[*]} " in *" $_a "*) continue;; *) _tmp_arch+=("$_a");; esac
done
ARCH_LIST=("${_tmp_arch[@]}")
for _chk in "${ARCH_LIST[@]}"; do
	case "$_chk" in
		armv8a|armv8-a|aarch64|arm64-v8a|armv7a|armv7-a|armeabi-v7a|x86|x86-64|x86_64|i686) ;;
		*)
			echo -e "\e[1;31mError: unknown architecture '$_chk'\e[0m" >&2
			echo "Valid: armv8a(aarch64/arm64-v8a), armv7a(armeabi-v7a), x86(i686), x86-64(x86_64)" >&2
			echo "Try $0 --help" >&2
			exit 1
			;;
	esac
done
if [ "$ARCH_SET" = "1" ]; then
	echo -e "\e[1;32mArch override: ${ARCH_LIST[*]}\e[0m"
else
	echo -e "\e[1;32mBuilding all architectures: ${ARCH_LIST[*]}\e[0m"
fi



# GPL build override: full feature set, GPL components only (no non-free).
if [ "${GPL_BUILD:-0}" = "1" ]; then
	ENABLED_CONFIG="\
		--enable-avcodec \
		--enable-avformat \
		--enable-avutil \
		--enable-swscale \
		--enable-swresample \
		--enable-avfilter \
		--enable-avdevice \
		--enable-network \
		--enable-zlib \
		--enable-mediacodec \
		--enable-jni \
		--enable-libdav1d \
		--enable-libx264 \
		--enable-libx265 \
		--enable-libvpx \
		--enable-libopus \
		--enable-libmp3lame \
		--enable-libaom \
		--enable-libass \
		--enable-libfreetype \
		--enable-libharfbuzz \
		--enable-libfribidi \
		--enable-libvorbis \
		--enable-libwebp \
		--enable-libsvtav1 \
		--enable-libjxl \
		--enable-libsoxr \
		--enable-librubberband \
		--enable-libvidstab \
		--enable-libxvid \
		--enable-gpl \
		--enable-version3 \
		--enable-hwaccel=* \
		--enable-decoder=* \
		--enable-encoder=* \
		--enable-muxer=* \
		--enable-demuxer=* \
		--enable-parser=* \
		--enable-bsf=* \
		--enable-protocol=* \
		--enable-filter=* \
		--enable-indev=* \
		--enable-outdev=* \
		--enable-ffmpeg \
		--enable-ffprobe \
		--enable-shared \
		--enable-optimizations \
		--enable-lto \
		--enable-pic "

	DISABLED_CONFIG="\
		--disable-small \
		--disable-v4l2-m2m \
		--disable-cuda-llvm \
		--disable-static \
		--disable-debug \
		--disable-ffplay \
		--disable-doc \
		--disable-symver "

	echo -e "\e[1;32mGPL build config active (no non-free components):\e[0m"
	echo "  ENABLED: avcodec/avformat/avutil/swscale/swresample/avfilter/avdevice/network/zlib + mediacodec/jni + dav1d/x264/x265/vpx/opus/mp3lame/aom/ass/freetype/harfbuzz/fribidi + GPLv3 + hwaccel/decoder/encoder/muxer/demuxer/parser/bsf/protocol/filter/indev/outdev = *"
	echo "  DISABLED: non-free (fdk-aac), small/v4l2-m2m/cuda-llvm/static/debug/ffplay/doc/symver"
fi

# Full build override (only configs, no other logic changed)
if [ "${FULL_BUILD:-0}" = "1" ]; then
	ENABLED_CONFIG="\
		--enable-avcodec \
		--enable-avformat \
		--enable-avutil \
		--enable-swscale \
		--enable-swresample \
		--enable-avfilter \
		--enable-avdevice \
		--enable-network \
		--enable-zlib \
		--enable-mediacodec \
		--enable-jni \
		--enable-libdav1d \
		--enable-libx264 \
		--enable-libx265 \
		--enable-libvpx \
		--enable-libopus \
		--enable-libmp3lame \
		--enable-libaom \
		--enable-libass \
		--enable-libfreetype \
		--enable-libharfbuzz \
		--enable-libfribidi \
		--enable-libfdk-aac \
		--enable-libvorbis \
		--enable-libwebp \
		--enable-libsvtav1 \
		--enable-libjxl \
		--enable-libsoxr \
		--enable-librubberband \
		--enable-libvidstab \
		--enable-libxvid \
		--enable-gpl \
		--enable-nonfree \
		--enable-version3 \
		--enable-hwaccel=* \
		--enable-decoder=* \
		--enable-encoder=* \
		--enable-muxer=* \
		--enable-demuxer=* \
		--enable-parser=* \
		--enable-bsf=* \
		--enable-protocol=* \
		--enable-filter=* \
		--enable-indev=* \
		--enable-outdev=* \
		--enable-ffmpeg \
		--enable-ffprobe \
		--enable-shared \
		--enable-optimizations \
		--enable-lto \
		--enable-pic "

	DISABLED_CONFIG="\
		--disable-small \
		--disable-v4l2-m2m \
		--disable-cuda-llvm \
		--disable-static \
		--disable-debug \
		--disable-ffplay \
		--disable-doc \
		--disable-symver "

	echo -e "\e[1;32mFull build config active:\e[0m"
	echo "  ENABLED: avcodec/avformat/avutil/swscale/swresample/avfilter/avdevice/network/zlib + mediacodec/jni + dav1d/x264/x265/vpx/opus/mp3lame/aom/ass/fdk-aac + GPL/nonfree + hwaccel/decoder/encoder/muxer/demuxer/parser/bsf/protocol/filter/indev/outdev = *"
	echo "  DISABLED: small/v4l2-m2m/cuda-llvm/static/debug/ffplay/doc/symver (zlib/network/avdevice/indevs/gpl re-enabled)"
fi



fetch_tarball(){
	local url="$1" dir="$2"
	local tarball="$SRC_DIR/$(basename "$url")"
	local tmpdir="$SRC_DIR/.tmp-$(basename "$dir")"
	echo "Fetching $dir from $url ..."
	if command -v curl >/dev/null 2>&1; then
		curl -L --fail --retry 3 -o "$tarball" "$url" || return 1
	else
		wget -O "$tarball" "$url" || return 1
	fi
	rm -rf "$tmpdir" "${SRC_DIR}/${dir}"
	mkdir -p "$tmpdir"
	tar -xf "$tarball" -C "$tmpdir" --strip-components=1 2>/dev/null || tar -xf "$tarball" -C "$tmpdir" || return 1
	mv "$tmpdir" "${SRC_DIR}/${dir}"
	rm -f "$tarball"
	# Ensure clean git state not needed for tarballs
	return 0
}



# ---------------------------------------------------------------------------
# Self-provisioning helpers: never abort for missing prerequisites when they
# can be installed/fetched automatically.
# ---------------------------------------------------------------------------
SUDO_PREFIX=""
if [ "$(id -u)" != "0" ] && command -v sudo > /dev/null 2>&1; then
	SUDO_PREFIX="sudo"
fi

# Package-manager detection + per-tool candidate packages.
# A tool may live in different packages per distro (e.g. Debian/Ubuntu split
# the libtool binary across 'libtool' and 'libtool-bin'), so every tool maps
# to an ordered candidate list tried one by one until the binary appears.
PKG_MANAGER=""
detect_pkg_manager(){
	PKG_MANAGER="$(command -v apt-get dnf yum pacman apk zypper brew 2>/dev/null | head -1)"
	case "$PKG_MANAGER" in
		*apt-get)	PKG_MANAGER="apt" ;;
		*dnf)		PKG_MANAGER="dnf" ;;
		*yum)		PKG_MANAGER="yum" ;;
		*pacman)	PKG_MANAGER="pacman" ;;
		*apk)		PKG_MANAGER="apk" ;;
		*zypper)	PKG_MANAGER="zypper" ;;
		*brew)		PKG_MANAGER="brew" ;;
		*)			PKG_MANAGER="" ;;
	esac
}

tool_packages(){
	local m="$1" t="$2"
	case "$m:$t" in
		apt:libtool)	echo "libtool libtool-bin" ;;
		apt:pkg-config)	echo "pkg-config pkgconf" ;;
		dnf:pkg-config|yum:pkg-config)	echo "pkgconf-pkg-config" ;;
		pacman:pkg-config)	echo "pkgconf" ;;
		apk:pkg-config)	echo "pkgconfig" ;;
		brew:make)		echo "make" ;;
		apt:make)		echo "build-essential" ;;
		dnf:make|yum:make)	echo "gcc make" ;;
		dnf:gcc|yum:gcc)	echo "gcc gcc-c++" ;;
		*)				echo "$t" ;;
	esac
}

pkg_install(){
	case "$1" in
		apt)
			export DEBIAN_FRONTEND=noninteractive
			$SUDO_PREFIX apt-get install -y "${@:2}" ;;
		dnf)	$SUDO_PREFIX dnf install -y "${@:2}" ;;
		yum)	$SUDO_PREFIX yum install -y "${@:2}" ;;
		pacman)	$SUDO_PREFIX pacman -Sy --noconfirm --needed "${@:2}" ;;
		apk)	$SUDO_PREFIX apk add --no-progress "${@:2}" ;;
		zypper)	$SUDO_PREFIX zypper --non-interactive install "${@:2}" ;;
		brew)	brew install "${@:2}" ;;
	esac
}

ensure_build_tools(){
	# Tools actually invoked by this script (clang/llvm tools come from the NDK).
	local REQUIRED_TOOLS="git make meson ninja pkg-config autoconf automake libtool nasm file patch python3 unzip cmake"
	local missing="" t p ok failed_detail=""
	for t in $REQUIRED_TOOLS; do
		command -v "$t" > /dev/null 2>&1 || missing="$missing $t"
	done
	# A downloader is required for the NDK fallback fetch.
	if ! command -v curl > /dev/null 2>&1 && ! command -v wget > /dev/null 2>&1; then
		missing="$missing curl"
	fi

	if [ -z "$missing" ]; then
		echo "All build tools already available."
		return 0
	fi
	echo -e "\e[1;33mInstalling missing build tools:$missing\e[0m"

	detect_pkg_manager
	if [ -z "$PKG_MANAGER" ]; then
		echo -e "\e[1;31mNo known package manager found; cannot install:$missing\e[0m"
		echo -e "\e[1;31mInstall them manually, e.g.: apt-get install build-essential git meson ninja-build nasm pkg-config autoconf automake libtool patch file python3 unzip curl\e[0m"
		return 1
	fi

	# Refresh package indexes (best effort - stale caches often still work).
	if [ "$PKG_MANAGER" = "apt" ]; then
		$SUDO_PREFIX apt-get update || echo -e "\e[1;33mapt-get update failed - continuing with cached indexes\e[0m"
	fi

	# Pass 1: bulk install of all candidates.
	local ALL_PKGS=$(for t in $missing; do tool_packages "$PKG_MANAGER" "$t"; done | tr ' ' '\n' | sort -u)
	if ! pkg_install "$PKG_MANAGER" $ALL_PKGS; then
		echo -e "\e[1;33mBulk install reported errors - verifying per tool and retrying\e[0m"
	fi

	# Pass 2: targeted retries for whatever is still absent.
	local still=""
	for t in $missing; do
		[ "$t" = "curl" ] && { command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || still="$still $t"; continue; }
		command -v "$t" > /dev/null 2>&1 || still="$still $t"
	done
	for t in $still; do
		ok=0
		for p in $(tool_packages "$PKG_MANAGER" "$t"); do
			pkg_install "$PKG_MANAGER" "$p" && command -v "$t" > /dev/null 2>&1 && { ok=1; break; }
		done
		if [ "$ok" != "1" ]; then
			failed_detail="$failed_detail
  - '$t': no candidate package provided it (tried:$(tool_packages "$PKG_MANAGER" "$t" | sed 's/^ / /'))"
		fi
	done
	if [ -n "$failed_detail" ]; then
		echo -e "\e[1;31mCould not provision some build tools on '$PKG_MANAGER':$failed_detail\e[0m"
		echo -e "\e[1;31mInstall them manually and re-run android.sh.\e[0m"
		return 1
	fi

	for t in $REQUIRED_TOOLS; do
		command -v "$t" > /dev/null 2>&1 || { echo -e "\e[1;31m'$t' still missing after install attempts. Aborting.\e[0m"; return 1; }
	done
	echo -e "\e[1;32mBuild tools ready.\e[0m"
}

ndk_clang_ok(){
	[ -x "$1/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" ]
}

ensure_android_ndk(){
	# 1) Explicit environment wins.
	if [ -n "${ANDROID_NDK_PATH:-}" ]; then
		if ndk_clang_ok "${ANDROID_NDK_PATH}"; then
			echo "Using ANDROID_NDK_PATH=${ANDROID_NDK_PATH}"
			return 0
		fi
		echo -e "\e[1;33mANDROID_NDK_PATH='${ANDROID_NDK_PATH}' is not a valid NDK (missing toolchains/llvm/prebuilt/linux-x86_64/bin/clang) - probing system...\e[0m"
	fi

	# 2) Probe common SDK roots (prefers the pinned r28c, else newest installed).
	local roots="/opt/android-sdk /usr/local/share/android-sdk /usr/local/lib/android-sdk /usr/local/lib/android/sdk $HOME/Android/Sdk $HOME/Library/Android/sdk ${ANDROID_HOME:-} ${ANDROID_SDK_ROOT:-}"
	local r v cand pass
	for r in $roots; do
		[ -d "$r/ndk" ] || continue
		for pass in 1 2; do
			for v in $(ls "$r/ndk" 2>/dev/null | sort -uV); do
				if [ "$pass" = "1" ]; then
					case "$v" in "${ANDROID_NDK_VERSION_NUM%.*}"*) ;; *) continue ;; esac
				fi
				cand="$r/ndk/$v"
				if ndk_clang_ok "$cand"; then
					echo "Found NDK $v at $cand"
					export ANDROID_NDK_PATH="$cand"
					return 0
				fi
			done
		done
	done

	# 3) sdkmanager (accepts licenses non-interactively via 'yes').
	if command -v sdkmanager > /dev/null 2>&1; then
		local sm_root=""
		for r in $roots; do [ -d "$r" ] && { sm_root="$r"; break; } done
		if [ -z "$sm_root" ]; then
			sm_root="$SCRIPT_DIR/build-tools/android-sdk"
			mkdir -p "$sm_root"
		fi
		echo "sdkmanager: installing NDK $ANDROID_NDK_VERSION_NUM into $sm_root ..."
		if yes 2>/dev/null | sdkmanager --sdk_root="$sm_root" "ndk;$ANDROID_NDK_VERSION_NUM"; then
			cand="$sm_root/ndk/$ANDROID_NDK_VERSION_NUM"
			if ndk_clang_ok "$cand"; then
				export ANDROID_NDK_PATH="$cand"
				return 0
			fi
		fi
		echo -e "\e[1;33msdkmanager install did not produce a usable NDK - falling back to direct download\e[0m"
	fi

	# 4) Direct download from Google into ./build-tools (gitignored).
	local DEST="$SCRIPT_DIR/build-tools/android-ndk-$ANDROID_NDK_VERSION"
	if ndk_clang_ok "$DEST"; then
		export ANDROID_NDK_PATH="$DEST"
		echo "Using previously downloaded NDK at $DEST"
		return 0
	fi
	mkdir -p "$SCRIPT_DIR/build-tools"
	local ZIP_FILE="$SCRIPT_DIR/build-tools/android-ndk-$ANDROID_NDK_VERSION-linux.zip"
	echo "Downloading NDK $ANDROID_NDK_VERSION ..."
	if command -v curl > /dev/null 2>&1; then
		curl -L --fail --retry 3 -o "$ZIP_FILE" "$ANDROID_NDK_URL" || return 1
	else
		wget -O "$ZIP_FILE" "$ANDROID_NDK_URL" || return 1
	fi
	unzip -q -o "$ZIP_FILE" -d "$SCRIPT_DIR/build-tools" || return 1
	rm -f "$ZIP_FILE"
	if ndk_clang_ok "$DEST"; then
		export ANDROID_NDK_PATH="$DEST"
		echo -e "\e[1;32mNDK $ANDROID_NDK_VERSION provisioned at $DEST\e[0m"
		return 0
	fi
	echo -e "\e[1;31mNDK extraction did not yield a usable toolchain at $DEST\e[0m"
	return 1
}




# ---------------------------------------------------------------------------
# Auto-enable required libs for fftools/umbrella (prevents build failures
# if user disables avfilter/avcodec/avformat/avutil/swscale/swresample
# or ffmpeg/ffprobe). Gracefully corrects config instead of aborting.
# ---------------------------------------------------------------------------
_REQUIRED_FF_LIBS="avcodec avformat avutil avfilter swscale swresample"
for _lib in $_REQUIRED_FF_LIBS; do
  if echo "$DISABLED_CONFIG" | grep -q -- "--disable-${_lib}"; then
    echo "WARNING: --disable-${_lib} is required for fftools/umbrella, auto-enabling --enable-${_lib}"
    DISABLED_CONFIG=$(echo "$DISABLED_CONFIG" | sed "s/--disable-${_lib}//g")
  fi
  if ! echo "$ENABLED_CONFIG" | grep -q -- "--enable-${_lib}"; then
    echo "WARNING: --enable-${_lib} is required for fftools, auto-enabling"
    ENABLED_CONFIG="$ENABLED_CONFIG --enable-${_lib}"
  fi
done
for _prog in ffmpeg ffprobe; do
  if echo "$DISABLED_CONFIG" | grep -q -- "--disable-${_prog}"; then
    echo "WARNING: --disable-${_prog} breaks fftools, auto-enabling"
    DISABLED_CONFIG=$(echo "$DISABLED_CONFIG" | sed "s/--disable-${_prog}//g")
  fi
  if ! echo "$ENABLED_CONFIG" | grep -q -- "--enable-${_prog}"; then
    echo "WARNING: --enable-${_prog} is required, auto-enabling"
    ENABLED_CONFIG="$ENABLED_CONFIG --enable-${_prog}"
  fi
done

_REQUIRED_FF_PROTOCOLS="pipe file appfd"
for _protocol in $_REQUIRED_FF_PROTOCOLS; do
  if echo "$DISABLED_CONFIG" | grep -q -- "--disable-protocol=${_protocol}"; then
    echo "WARNING: --disable-protocol=${_protocol} is required for fftools, auto-enabling"
    DISABLED_CONFIG=$(echo "$DISABLED_CONFIG" | sed "s/--disable-protocol=${_protocol}//g")
  fi
  if ! echo "$ENABLED_CONFIG" | grep -q -- "--enable-protocol=${_protocol}"; then
    echo "WARNING: --enable-protocol=${_protocol} is required for fftools, auto-enabling"
    ENABLED_CONFIG="$ENABLED_CONFIG --enable-protocol=${_protocol}"
  fi
done




# ---------------------------------------------------------------------------
# Provision prerequisites (installs missing tools / fetches NDK if needed)
# ---------------------------------------------------------------------------
if ! ensure_build_tools; then
	echo -e "\e[1;31mError: required build tools unavailable. Aborting.\e[0m"
	exit 1
fi
if ! ensure_android_ndk; then
	echo -e "\e[1;31mError: could not locate, install or download Android NDK $ANDROID_NDK_VERSION. Aborting.\e[0m"
	exit 1
fi

SYSROOT="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
LLVM_AR="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar"
LLVM_NM="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-nm"
LLVM_RANLIB="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ranlib"
LLVM_STRIP="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
LLVM_STRINGS="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strings"
LLVM_READELF="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf"
export ASFLAGS="-fPIC"


### Umbrella FFmpeg library configuration ####
# One single runtime shared library per ABI containing all FFmpeg code.
FFMPEG_UMBRELLA_NAME="libffmpeg.so"
# Libraries whose objects are merged into the umbrella library.
# Dynamically built from _REQUIRED_FF_LIBS / ENABLED_CONFIG so only
# enabled required libs are merged. Auto-enable above guarantees all
# required libs are present, so umbrella never fails when user disables
# avfilter/avcodec/etc. Keeps link order canonical.
FFMPEG_UMBRELLA_LIBS=""
for _lib in $_REQUIRED_FF_LIBS; do
  if echo "$ENABLED_CONFIG" | grep -q -- "--enable-${_lib}"; then
    FFMPEG_UMBRELLA_LIBS="$FFMPEG_UMBRELLA_LIBS $_lib"
  fi
done
FFMPEG_UMBRELLA_LIBS=$(echo "$FFMPEG_UMBRELLA_LIBS" | sed 's/^ //')
# Reorder to canonical link order: avutil avcodec avformat avfilter swresample swscale
_ordered="avutil avcodec avformat avfilter swresample swscale"
_ordered_result=""
for _o in $_ordered; do
  if echo " $FFMPEG_UMBRELLA_LIBS " | grep -q " $_o "; then
    _ordered_result="$_ordered_result $_o"
  fi
done
FFMPEG_UMBRELLA_LIBS=$(echo "$_ordered_result" | sed 's/^ //')
# Also handle future optional libs (avdevice) if ever enabled:
for _opt in avdevice; do
  if echo "$ENABLED_CONFIG" | grep -q -- "--enable-${_opt}"; then
    if ! echo " $FFMPEG_UMBRELLA_LIBS " | grep -q " $_opt "; then
      FFMPEG_UMBRELLA_LIBS=$(echo "$FFMPEG_UMBRELLA_LIBS" | sed "s/ swresample/ ${_opt} swresample/")
      if ! echo "$FFMPEG_UMBRELLA_LIBS" | grep -q "$_opt"; then
        FFMPEG_UMBRELLA_LIBS="$FFMPEG_UMBRELLA_LIBS $_opt"
      fi
    fi
  fi
done
# Runtime dependencies that must NEVER appear as DT_NEEDED of libffmpeg.so
# (their implementation is linked INTO the umbrella library instead).
FFMPEG_FORBIDDEN_DEPS="libavcodec.so libavformat.so libavutil.so libavfilter.so libswscale.so libswresample.so libdav1d.so libx264.so libx265.so libvpx.so libopus.so libmp3lame.so libaom.so libass.so libfreetype.so libharfbuzz.so libfribidi.so libfdk-aac.so libvorbis.so libogg.so libwebp.so libSvtAv1Enc.so libjxl.so libsoxr.so librubberband.so libvidstab.so libxvidcore.so"
# Public FFShell API symbols exported from the umbrella library.
FFSHELL_API_SYMBOLS="ffshell_ffmpeg_run ffshell_cancel ffshell_get_version ffshell_set_log_callback ffshell_set_path_callback ffshell_ffprobe_run ffshell_saf_pattern_output_supported"


clean_and_fetch_sources(){
	# Isolated, reproducible builds: always start from a pristine source tree.
	echo -e "\e[1;32mFetching a clean FFmpeg source tree...\e[0m"

	if [ -z "${FFMPEG_TAG:-}" ]; then
	FFMPEG_TAG=$(git ls-remote --tags "$FFMPEG_URL" 2>/dev/null | sed 's|.*/||' | grep -E '^n[0-9]+\.[0-9]+(\.[0-9]+)?$' | sort -V | tail -1)
fi
: "${FFMPEG_TAG:=n9.0.2}"
	if [ -d "$FFMPEG_SOURCE_DIR" ] && [ ! -d "$FFMPEG_SOURCE_DIR/.git" ]; then
		echo "Existing $FFMPEG_SOURCE_DIR is not a git checkout - removing for clean fetch"
		rm -rf "$FFMPEG_SOURCE_DIR"
	fi
	if [ -d "$FFMPEG_SOURCE_DIR/.git" ]; then
		git -C "$FFMPEG_SOURCE_DIR" reset --hard
		git -C "$FFMPEG_SOURCE_DIR" clean -fdx
		git -C "$FFMPEG_SOURCE_DIR" fetch --depth 1 origin tag "$FFMPEG_TAG"
		git -C "$FFMPEG_SOURCE_DIR" checkout "$FFMPEG_TAG"
		git -C "$FFMPEG_SOURCE_DIR" clean -fdx
	else
		git clone --depth 1 --branch "$FFMPEG_TAG" "$FFMPEG_URL" "$FFMPEG_SOURCE_DIR" || return 1
	fi

	# Conditional external deps: only fetch what ENABLED_CONFIG actually needs.
	# Generic mapping: enable-lib* -> directory + URL
	for lib in dav1d x264 x265 vpx opus mp3lame aom freetype fribidi harfbuzz ass fdk-aac ogg vorbis webp svtav1 jxl soxr rubberband vidstab xvid; do
		# Map enable flag: lib name with dash handling
		flag="enable-lib${lib}"
		# freetype/fribidi/harfbuzz are deps for libass, not directly in ENABLED_CONFIG – fetch when libass enabled
		need_fetch=0
		case "$lib" in
			freetype|fribidi|harfbuzz)
				if echo "$ENABLED_CONFIG" | grep -q "enable-libass"; then
					need_fetch=1
				fi
				flag="enable-libass"
				;;
			ogg)
				if echo "$ENABLED_CONFIG" | grep -q "enable-libvorbis"; then
					need_fetch=1
				fi
				flag="enable-libvorbis"
				;;
		esac
		case "$lib" in
			dav1d)		url="$DAV1D_URL"; dir="dav1d" ;;
			x264)		url="$X264_URL"; dir="x264" ;;
			x265)		url="$X265_URL"; dir="x265" ;;
			vpx)		url="$VPX_URL"; dir="libvpx" ;;
			opus)		url="$OPUS_URL"; dir="opus" ;;
			mp3lame)	url="$LAME_URL"; dir="lame" ;;
			aom)		url="$AOM_URL"; dir="aom" ;;
			freetype)	url="$FREETYPE_URL"; dir="freetype" ;;
			fribidi)	url="$FRIBIDI_URL"; dir="fribidi" ;;
			harfbuzz)	url="$HARFBUZZ_URL"; dir="harfbuzz" ;;
			ass)		url="$ASS_URL"; dir="libass" ;;
			fdk-aac)	url="$FDKAAC_URL"; dir="fdk-aac" ;;
			ogg)		url="$OGG_URL"; dir="ogg" ;;
			vorbis)		url="$VORBIS_URL"; dir="vorbis" ;;
			webp)		url="$WEBP_URL"; dir="libwebp" ;;
			svtav1)		url="$SVTAV1_URL"; dir="SVT-AV1" ;;
			jxl)		url="$JXL_URL"; dir="libjxl" ;;
			soxr)		url="$SOXR_URL"; dir="soxr" ;;
			rubberband)	url="$RUBBERBAND_URL"; dir="rubberband" ;;
			vidstab)	url="$VIDSTAB_URL"; dir="vid.stab" ;;
			xvid)		url="$XVID_URL"; dir="xvidcore" ;;
		esac
		# Normalize flag for mp3lame (ffmpeg uses --enable-libmp3lame)
		if [ "$lib" = "mp3lame" ]; then flag="enable-libmp3lame"; fi
		if [ "$lib" = "fdk-aac" ]; then flag="enable-libfdk-aac"; fi

		if [ "$need_fetch" = "1" ] || echo "$ENABLED_CONFIG" | grep -q "$flag"; then
			echo -e "\e[1;32mFetching a clean lib${lib} source tree...\e[0m"

			# Handle both git and tarball URLs
			if [[ "$url" == *.git ]]; then
				if [ -d "${SRC_DIR}/${dir}" ] && [ ! -d "${SRC_DIR}/${dir}/.git" ]; then
					echo "Existing ${SRC_DIR}/${dir} is not a git checkout - removing for clean fetch"
					rm -rf "${SRC_DIR}/${dir}"
				fi
				if [ -d "${SRC_DIR}/${dir}/.git" ]; then
					git -C "${SRC_DIR}/${dir}" fetch --depth 1 origin
					branch="$(git -C "${SRC_DIR}/${dir}" symbolic-ref --short refs/remotes/origin/HEAD)"
					git -C "${SRC_DIR}/${dir}" reset --hard "$branch"
					git -C "${SRC_DIR}/${dir}" clean -fdx
				else
					git clone --depth 1 "$url" "${SRC_DIR}/${dir}" || return 1
				fi
			else
				# Tarball
				if [ -d "${SRC_DIR}/${dir}/.git" ]; then
					rm -rf "${SRC_DIR}/${dir}"
				fi
				if [ ! -f "${SRC_DIR}/${dir}/configure" ] && [ ! -f "${SRC_DIR}/${dir}/meson.build" ] && [ ! -f "${SRC_DIR}/${dir}/CMakeLists.txt" ]; then
					fetch_tarball "$url" "$dir" || return 1
				else
					echo "Using existing ${SRC_DIR}/${dir} tarball source"
				fi
			fi
		
		else
			echo -e "\e[1;33mSkipping lib${lib} fetch (not enabled)\e[0m"
		fi
	done

	# FFShell CLI integration needs NO source patches:
	#   - entry point renamed via '-Dmain=ffmpeg_main' (see configure_ffmpeg)
	#   - two tiny hook functions are APPENDED to fftools/ffmpeg.c below;
	#     appending at end-of-file cannot conflict with upstream changes.
	if ! inject_ffshell_hooks; then return 1; fi

	# Fix duplicate show_help_default: ffmpeg and ffprobe both define it, linker picks ffmpeg with --allow-multiple-definition
	# so ffprobe -h would show ffmpeg help. Rename ffprobe's and dispatch via program_name.
	if grep -q "^void show_help_default" "$FFMPEG_SOURCE_DIR/fftools/ffprobe.c" 2>/dev/null; then
		echo "Patching ffprobe.c show_help_default -> ffprobe_show_help_default"
		sed -i 's/^void show_help_default/void ffprobe_show_help_default/' "$FFMPEG_SOURCE_DIR/fftools/ffprobe.c" || true
	fi
	if grep -q "ffprobe_show_help_default" "$FFMPEG_SOURCE_DIR/fftools/ffprobe.c" 2>/dev/null && ! grep -q "ffprobe_show_help_default" "$FFMPEG_SOURCE_DIR/fftools/opt_common.c" 2>/dev/null; then
		echo "Patching opt_common.c to dispatch show_help_default via program_name"
		# Add extern decl for renamed ffprobe help (after log.h include, idempotent)
		sed -i '/#include "libavutil\/log.h"/a extern void ffprobe_show_help_default(const char *opt, const char *arg);' "$FFMPEG_SOURCE_DIR/fftools/opt_common.c" || true
		sed -i 's/show_help_default(topic, par);/if (!strcmp(program_name, "ffprobe")) ffprobe_show_help_default(topic, par); else show_help_default(topic, par);/g' "$FFMPEG_SOURCE_DIR/fftools/opt_common.c" || true
	fi

	# Upstream FFmpeg bugfix: libavutil/pixelutils.c calls ff_pixelutils_sad_init_arm()
	# under "#elif ARCH_ARM" but includes "arm/pixelutils.h" only under
	# "#elif ARCH_ARM && HAVE_ARMV6". When android.sh disables ARMv6 for armv7a
	# (TARGET_CPU=armv7-a with --disable-armv6), HAVE_ARMV6=0 => header not included
	# but call remains => implicit-function-declaration error with NDK r28c clang.
	# Patch the call site to match the include guard (require HAVE_ARMV6).
	if [ -f "$FFMPEG_SOURCE_DIR/libavutil/pixelutils.c" ]; then
		if grep -q "ARCH_ARM && HAVE_ARMV6" "$FFMPEG_SOURCE_DIR/libavutil/pixelutils.c" && grep -q "#elif ARCH_ARM$" "$FFMPEG_SOURCE_DIR/libavutil/pixelutils.c"; then
			echo "Patching pixelutils.c: ARCH_ARM -> ARCH_ARM && HAVE_ARMV6 for arm init"
			sed -i 's/^#elif ARCH_ARM$/#elif ARCH_ARM \&\& HAVE_ARMV6/' "$FFMPEG_SOURCE_DIR/libavutil/pixelutils.c" || true
		fi
	fi
	# Custom appfd protocol (same conventions as built-in protocols):
	# re-injected here so a pristine upstream checkout always gets it
	# before configure runs.
	if ! inject_appfd_protocol; then return 1; fi
	# Route marked concat-list entries through the runtime path hook so
	# SAF/Picked inputs resolve like any other FFmpeg input.
	if ! patch_concat_path_hook; then return 1; fi
	# Patch libavformat/img2enc so each image-sequence frame is resolved
	# through the runtime path callback, allowing SAF output patterns.
	if ! patch_saf_pattern_output_hook; then return 1; fi
	# Guard upstream binder threadpool init: unpatched, every ffmpeg run
	# SIGABRTs on API 35+ app processes ("cannot be shrunk after starting").
	if ! patch_binder_threadpool_guard; then return 1; fi
	return 0
}

inject_appfd_protocol(){
	# Custom appfd protocol — build-time static registration following
	# the same conventions as built-in FFmpeg protocols:
	#   appfd.c:  const URLProtocol ff_appfd_protocol (.name
	#                 "appfd") guarded by #if CONFIG_APPFD_PROTOCOL
	#                 (cf. file.c pipe/fd blocks)
	#   Makefile:     OBJS-$(CONFIG_APPFD_PROTOCOL) += appfd.o
	#   protocols.c:  extern const URLProtocol ff_appfd_protocol;
	#   configure:    nothing to patch — modern configure derives
	#                 PROTOCOL_LIST via find_things_extern() from the
	#                 protocols.c externs above, which auto-generates
	#                 CONFIG_APPFD_PROTOCOL (config_components.h),
	#                 the url_protocols[] entry (protocol_list.c), and
	#                 --enable-protocol=appfd / --list-protocols.
	#                 (protocol_list.c itself is generated — never hand-edit.)
	# Source of truth lives outside the checkout (appfd/appfd.c)
	# and is re-injected after every `git reset --hard / clean -fdx` via
	# idempotent grep -q guards, before configure runs.
	if [ ! -f "$SCRIPT_DIR/appfd/appfd.c" ]; then
		echo "appfd source missing ($SCRIPT_DIR/appfd/appfd.c)" >&2
		return 1
	fi
	echo "Injecting appfd protocol (build-time static)..."
	cp "$SCRIPT_DIR/appfd/appfd.c" "$FFMPEG_SOURCE_DIR/libavformat/appfd.c"

	if grep -qF "appfd.o" "$FFMPEG_SOURCE_DIR/libavformat/Makefile" 2>/dev/null; then
		echo "appfd Makefile already present."
	else
		echo 'OBJS-$(CONFIG_APPFD_PROTOCOL) += appfd.o' >> "$FFMPEG_SOURCE_DIR/libavformat/Makefile"
	fi

	if grep -q "ff_appfd_protocol" "$FFMPEG_SOURCE_DIR/libavformat/protocols.c" 2>/dev/null; then
		echo "appfd protocols.c already present."
	else
		sed -i '/extern const URLProtocol ff_mmst_protocol;/a extern const URLProtocol ff_appfd_protocol;' "$FFMPEG_SOURCE_DIR/libavformat/protocols.c" 2>/dev/null || true
		if ! grep -q "ff_appfd_protocol" "$FFMPEG_SOURCE_DIR/libavformat/protocols.c" 2>/dev/null; then
			echo "appfd protocols.c injection failed (anchor ff_mmst_protocol not found)" >&2
			return 1
		fi
	fi
	return 0
}

patch_concat_path_hook(){
	# Marked lists ("# ffshell-list v1", written by the `listfiles` command)
	# store workspace paths that must be resolved at open time, exactly like
	# a normal FFmpeg input:
	#   Internal      absolute paths (also work unpatched)
	#   SAF           workspace-root-relative paths
	#   PickedFiles   full virtual paths
	# Upstream add_file() resolves entries with ff_make_absolute_url() against
	# the *script* URL (an appfd:N FD for SAF lists), which cannot represent
	# those paths. Keep the raw entry, and immediately before each
	# avformat_open_input() ask the runtime path hook to resolve it.
	# Unmarked lists are left byte-for-byte upstream (the agent merge list
	# depends on that).
	local TARGET="$FFMPEG_SOURCE_DIR/libavformat/concatdec.c"
	if [ ! -f "$TARGET" ]; then
		echo "concatdec.c not found; concat path hook not injected" >&2
		return 1
	fi
	if grep -q "FFSHELL_CONCAT_PATH_HOOK" "$TARGET" 2>/dev/null; then
		echo "concat path hook already present."
		return 0
	fi
	python3 - "$TARGET" <<'PYEOF'
import sys

path = sys.argv[1]
with open(path) as fh:
    src = fh.read()

if "FFSHELL_CONCAT_PATH_HOOK" in src:
    print("concat path hook already present")
    sys.exit(0)

def patch(anchor, replacement, what):
    global src
    count = src.count(anchor)
    if count != 1:
        sys.stderr.write(
            "concatdec hook: expected exactly one anchor for %s, found %d\n"
            % (what, count))
        sys.exit(1)
    src = src.replace(anchor, replacement, 1)

# 1. Hook declaration, marker, and close() for the detached appfd FD.
patch(
    '#include "url.h"\n',
    '#include "url.h"\n'
    '#include <unistd.h>\n'
    '\n'
    '/* ---- FFSHELL_CONCAT_PATH_HOOK (injected by android.sh) --------------- */\n'
    '/* Resolve marked concat entries through the runtime path callback.      */\n'
    '/* Returns a caller-owned URL (av_free) and, for appfd:N results, N in  */\n'
    '/* *fd_to_close. appfd_open() duplicates N, so concatdec must close it   */\n'
    '/* after avformat_open_input() returns.                                  */\n'
    'extern char *ffshell_concat_path_hook_request(const char *raw_path, int *fd_to_close);\n'
    '/* Must match ConcatListFormat.MARKER in the app (Kotlin). */\n'
    '#define FFSHELL_LIST_MARKER     "# ffshell-list v1"\n'
    '#define FFSHELL_LIST_MARKER_LEN (sizeof(FFSHELL_LIST_MARKER) - 1)\n'
    '/* ---- end FFSHELL_CONCAT_PATH_HOOK declaration ----------------------- */\n',
    "url.h include",
)

# 2. Per-file raw entry (pre-ff_make_absolute_url).
patch(
    '    char *url;\n'
    '    int64_t start_time;\n',
    '    char *url;\n'
    '    char *ffshell_raw_url;\n'
    '    int64_t start_time;\n',
    "ConcatFile.url field",
)

# 3. Per-script marker flag.
patch(
    '    int safe;\n'
    '    int seekable;\n',
    '    int ffshell_list;\n'
    '    int safe;\n'
    '    int seekable;\n',
    "ConcatContext.safe field",
)

# 4. Keep the escaped token before upstream rewrites it into an absolute URL.
patch(
    '    char *url = NULL;\n'
    '    const char *proto;\n',
    '    char *url = NULL;\n'
    '    char *raw_url = NULL;\n'
    '    const char *proto;\n',
    "add_file url declaration",
)
patch(
    '    if (cat->safe && !safe_filename(filename)) {\n'
    '        av_log(avf, AV_LOG_ERROR, "Unsafe file name \'%s\'\\n", filename);\n'
    '        FAIL(AVERROR(EPERM));\n'
    '    }\n'
    '\n'
    '    proto = avio_find_protocol_name(filename);\n',
    '    if (cat->safe && !safe_filename(filename)) {\n'
    '        av_log(avf, AV_LOG_ERROR, "Unsafe file name \'%s\'\\n", filename);\n'
    '        FAIL(AVERROR(EPERM));\n'
    '    }\n'
    '\n'
    '    if (cat->ffshell_list && !(raw_url = av_strdup(filename)))\n'
    '        FAIL(AVERROR(ENOMEM));\n'
    '\n'
    '    proto = avio_find_protocol_name(filename);\n',
    "add_file safe check",
)
patch(
    '    file->url        = url;\n',
    '    file->url        = url;\n'
    '    file->ffshell_raw_url = raw_url;\n',
    "add_file file assignment",
)
patch(
    'fail:\n'
    '    av_free(url);\n'
    '    av_free(filename);\n'
    '    return ret;\n',
    'fail:\n'
    '    av_free(raw_url);\n'
    '    av_free(url);\n'
    '    av_free(filename);\n'
    '    return ret;\n',
    "add_file fail cleanup",
)

# 5. Detect the marker on the first line (before keyword parsing).
patch(
    '    while ((ret = ff_read_line_to_bprint_overwrite(avf->pb, &bp)) >= 0) {\n'
    '        line++;\n'
    '        cursor = bp.str;\n'
    '        keyword = get_keyword(&cursor);\n',
    '    while ((ret = ff_read_line_to_bprint_overwrite(avf->pb, &bp)) >= 0) {\n'
    '        line++;\n'
    '        cursor = bp.str;\n'
    '        if (line == 1 &&\n'
    '            !strncmp((const char *)cursor, FFSHELL_LIST_MARKER,\n'
    '                     FFSHELL_LIST_MARKER_LEN))\n'
    '            cat->ffshell_list = 1;\n'
    '        keyword = get_keyword(&cursor);\n',
    "concat_parse_script first line",
)

# 6. Open marked entries through the hook. appfd_open() duplicates the FD,
#    so close the original one after the open.
patch(
    '    if ((ret = avformat_open_input(&cat->avf, file->url, NULL, &options)) < 0 ||\n'
    '        (ret = avformat_find_stream_info(cat->avf, NULL)) < 0) {\n',
    '    if (cat->ffshell_list && file->ffshell_raw_url) {\n'
    '        int hook_fd = -1;\n'
    '        char *hook_url = ffshell_concat_path_hook_request(file->ffshell_raw_url,\n'
    '                                                           &hook_fd);\n'
    '        ret = avformat_open_input(&cat->avf, hook_url ? hook_url : file->url,\n'
    '                                  NULL, &options);\n'
    '        if (hook_fd >= 0)\n'
    '            close(hook_fd);\n'
    '        av_freep(&hook_url);\n'
    '    } else {\n'
    '        ret = avformat_open_input(&cat->avf, file->url, NULL, &options);\n'
    '    }\n'
    '    if (ret < 0 || (ret = avformat_find_stream_info(cat->avf, NULL)) < 0) {\n',
    "probe_file open_input",
)

# 7. Free the raw entry with the rest of the file state.
patch(
    '        av_freep(&cat->files[i].url);\n',
    '        av_freep(&cat->files[i].url);\n'
    '        av_freep(&cat->files[i].ffshell_raw_url);\n',
    "concat_read_close url free",
)

with open(path, "w") as fh:
    fh.write(src)
print("concat path hook injected")
PYEOF
}

patch_saf_pattern_output_hook(){
    local TARGET="$FFMPEG_SOURCE_DIR/libavformat/img2enc.c"
    if [ ! -f "$TARGET" ]; then
        echo "img2enc.c not found; SAF pattern output hook not injected" >&2
        return 1
    fi
    if grep -q "FFSHELL_SAF_PATTERN_OUTPUT_HOOK" "$TARGET" 2>/dev/null; then
        echo "SAF pattern output hook already present."
        return 0
    fi
    python3 - "$TARGET" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as fh:
    src = fh.read()

if "FFSHELL_SAF_PATTERN_OUTPUT_HOOK" in src:
    print("SAF pattern output hook already present")
    sys.exit(0)

anchor = '#include "mux.h"\n'
add = '''#include "mux.h"

/* ---- FFSHELL_SAF_PATTERN_OUTPUT_HOOK (injected by android.sh) -------- */
#include <unistd.h>
extern char *ffshell_saf_pattern_path_hook_request(const char *raw_path, int *fd_to_close);
/* ---- end FFSHELL_SAF_PATTERN_OUTPUT_HOOK declaration ----------------- */
'''
assert src.count(anchor) == 1, "mux.h include not found"
src = src.replace(anchor, add, 1)

anchor2 = '        if ((ret = s->io_open(s, &pb[i], tmp[i] ? tmp[i] : filename.str, AVIO_FLAG_WRITE, &options)) < 0) {\n'
repl = '''        /* ---- FFSHELL_SAF_PATTERN_OUTPUT_HOOK (injected by android.sh) ---- */
        {
            const char *ffshell_open_path = tmp[i] ? tmp[i] : filename.str;
            char *ffshell_hook_url = NULL;
            int ffshell_hook_fd = -1;
            if (!img->use_rename &&
                ffshell_open_path[0] != '/' &&
                strncmp(ffshell_open_path, "appfd:", 6) &&
                !strstr(ffshell_open_path, "://") &&
                strncmp(ffshell_open_path, "pipe:", 5)) {
                ffshell_hook_url = ffshell_saf_pattern_path_hook_request(ffshell_open_path, &ffshell_hook_fd);
            }
            if ((ret = s->io_open(s, &pb[i], ffshell_hook_url ? ffshell_hook_url : ffshell_open_path, AVIO_FLAG_WRITE, &options)) < 0) {
                if (ffshell_hook_fd >= 0)
                    close(ffshell_hook_fd);
                av_free(ffshell_hook_url);
                av_log(s, AV_LOG_ERROR, "Could not open file : %s\\n", ffshell_open_path);
                goto fail;
            }
            if (ffshell_hook_fd >= 0)
                close(ffshell_hook_fd);
            av_free(ffshell_hook_url);
        }
        if (0) {
        /* ---- end FFSHELL_SAF_PATTERN_OUTPUT_HOOK ------------------------- */
'''
assert anchor2 in src, "io_open anchor not found"
src = src.replace(anchor2, repl, 1)

with open(path, "w") as fh:
    fh.write(src)
print("SAF pattern output hook injected")
PYEOF
    if [ $? -ne 0 ]; then
        echo "SAF pattern output hook injection failed" >&2
        return 1
    fi
    return 0
}

patch_binder_threadpool_guard(){
	# Upstream compat/android/binder.c unconditionally calls
	# ABinderProcess_setThreadPoolMaxThreadCount(1) on API 35+ right before
	# every transcode (fftools/ffmpeg.c). In an app process the framework has
	# already started the binder pool with a larger max, and shrinking it is
	# LOG_ALWAYS_FATAL ("Binder threadpool cannot be shrunk after starting")
	# -> SIGABRT on EVERY ffmpeg run (ffmpeg -version/ffprobe are unaffected:
	# they exit before transcode). Guard: when the host pool is already
	# running, skip set+start entirely (MediaCodec then uses the host pool).
	# Standalone/CLI processes (Termux) keep upstream behavior.
	# Re-applied here so a pristine upstream checkout always gets it.
	local TARGET="$FFMPEG_SOURCE_DIR/compat/android/binder.c"
	if grep -q "FFSHELL_BINDER_GUARD" "$TARGET" 2>/dev/null; then
		echo "Binder threadpool guard already present."
		return 0
	fi
	if ! grep -q "ABinderProcess_setThreadPoolMaxThreadCount" "$TARGET" 2>/dev/null; then
		echo "Note: compat/android/binder.c has no binder init (pre-Android15 FFmpeg?) - nothing to guard."
		return 0
	fi
	python3 - "$TARGET" <<'PYEOF'
import sys
path = sys.argv[1]
src = open(path).read()
anchor_start = "    if (start_thread_pool == NULL) {"
anchor_set = "    if (set_thread_pool_max != NULL) {"
if anchor_start not in src or anchor_set not in src:
    sys.stderr.write("binder.c guard: upstream anchors not found, refusing to patch\n")
    sys.exit(1)
guard = """    /* ---- FFSHELL_BINDER_GUARD (injected by android.sh) ------------------ */
    /* Upstream shrinks the binder pool to 1 thread unconditionally. In an  */
    /* app process the framework already started the pool with a larger    */
    /* max, and shrinking is LOG_ALWAYS_FATAL ("Binder threadpool cannot   */
    /* be shrunk after starting") -> SIGABRT on every ffmpeg run. When the */
    /* host pool is already running, skip set+start entirely (MediaCodec   */
    /* then uses the host pool). Standalone/CLI processes keep upstream    */
    /* behavior.                                                           */
    {
        typedef _Bool (*ffshell_is_started_fn)(void);
        ffshell_is_started_fn ffshell_is_started =
            (ffshell_is_started_fn) dlsym(h, "ABinderProcess_isThreadPoolStarted");
        if (ffshell_is_started != NULL) {
            if (ffshell_is_started()) {
                av_log(NULL, AV_LOG_DEBUG,
                       "android/binder: host threadpool already started; skipping init\\n");
                return;
            }
        } else {
            /* Symbol unavailable (older platform): never risk shrinking the
             * pool - start only, keep the library default max. */
            start_thread_pool();
            av_log(NULL, AV_LOG_DEBUG,
                   "android/binder: ABinderProcess_startThreadPool() called (default max)\\n");
            return;
        }
    }
    /* ---- end FFSHELL_BINDER_GUARD --------------------------------------- */
"""
head, tail = src.split(anchor_set, 1)
assert anchor_start in head, "binder.c guard: start-pool check must precede set-max"
src = head + guard + anchor_set + tail
open(path, "w").write(src)
print("binder.c guard injected")
PYEOF
}

inject_ffshell_hooks(){
	# Appends (idempotently) the FFShell integration hooks:
	#   - fftools/ffmpeg.c      : cancel + interrupt/state reset
	#   - fftools/ffmpeg_opt.c  : io-path rewrite using split_commandline()
	#   - fftools/ffprobe.c     : input-path rewrite using ffprobe's own grammar
	# All appends are end-of-file and reference only symbols visible in the
	# same translation unit, so they survive upstream refactors; a grep guard
	# makes drift fail loudly instead of silently mis-parsing.

	local TARGET="$FFMPEG_SOURCE_DIR/fftools/ffmpeg.c"
	if grep -q "ffshell_request_cancel" "$TARGET"; then
		echo "FFShell hooks already present."
	else
	cat >> "$TARGET" <<'FFSHELL_HOOKS'

/* ---- FFShell integration hooks (appended by android.sh) ---------------- */
void ffshell_request_cancel(void);
void ffshell_reset_interrupt_state(void);
void ffshell_reset_state(void);

/* Cooperative cancellation without POSIX signals: mirrors what the CLI's
 * own signal handler does, so all existing interrupt checks apply. */
void ffshell_request_cancel(void)
{
    received_sigterm    = SIGTERM;
    received_nb_signals++;
}

/* Clear interrupt state before starting a new in-process run so repeated
 * executions are not aborted by leftovers of a previous cancellation. */
void ffshell_reset_interrupt_state(void)
{
    received_sigterm    = 0;
    received_nb_signals = 0;
}

void ffshell_reset_state(void)
{
    received_sigterm    = 0;
    received_nb_signals = 0;
    ffmpeg_exited = 0;
    atomic_store(&transcode_init_done, 0);
    /* Unconditional reset — previous conditional if (!ptr) left stale nb_*
     * after an OPT_EXIT info run (-h/-version/-decoders) that never allocated
     * arrays but kept previous transcode counts. Next transcode then reuses
     * stale counts and emits extra TRACE Writing block / filter logs. */
    nb_input_files  = 0;
    nb_output_files = 0;
    nb_filtergraphs = 0;
    nb_decoders     = 0;
    /* Also reset muxer/timestamp statics that survive ffmpeg_cleanup */
    copy_ts_first_pts = AV_NOPTS_VALUE;
    if (vstats_file) { fclose(vstats_file); vstats_file = NULL; }
    if (progress_avio) { avio_closep(&progress_avio); }
    atomic_store(&nb_output_dumped, 0);
    memset(&current_time, 0, sizeof(current_time));
    /* filter_hw_device is freed in ffmpeg_cleanup but pointer left dangling */
    {
        extern HWDevice *filter_hw_device;
        filter_hw_device = NULL;
    }
    /* Close report file and restore av_log callback (set by show_help/report) */
    {
        extern void ffshell_reset_report(void);
        ffshell_reset_report();
    }
}
/* ---- end FFShell integration hooks ------------------------------------- */
FFSHELL_HOOKS
	fi

	# --- report/log callback reset for opt_common.c (close report file left open by -report / FFREPORT) ---
	local REPORT_TARGET="$FFMPEG_SOURCE_DIR/fftools/opt_common.c"
	if ! grep -q "ffshell_reset_report" "$REPORT_TARGET"; then
	cat >> "$REPORT_TARGET" <<'FFSHELL_REPORT_HOOKS'

/* ---- FFShell report reset (appended by android.sh) ---------------------- */
void ffshell_reset_report(void);
void ffshell_reset_report(void)
{
    if (report_file) { fclose(report_file); report_file = NULL; }
    report_file_level = AV_LOG_DEBUG;
    av_log_set_callback(av_log_default_callback);
}
/* ---- end FFShell report reset ------------------------------------------- */
FFSHELL_REPORT_HOOKS
	else
		echo "FFShell report hooks already present."
	fi

	# --- io-path rewrite for the ffmpeg CLI (real tokenizer, same TU) ---
	local OPT_TARGET="$FFMPEG_SOURCE_DIR/fftools/ffmpeg_opt.c"
	if ! grep -q "ffshell_rewrite_io_paths" "$OPT_TARGET"; then
		grep -q "int split_commandline(OptionParseContext" \
			"$FFMPEG_SOURCE_DIR/fftools/cmdutils.h" || {
			echo "Error: cmdutils.h no longer declares split_commandline as expected."
			return 1
		}
	cat >> "$OPT_TARGET" <<'FFSHELL_OPT_HOOKS'

/* ---- FFShell io-path rewrite (appended by android.sh) ------------------- */
/* appfd is build-time guaranteed; no availability check, no /proc fallback */
extern char *ffshell_path_hook_request(int is_output, const char *raw_path);
static int ffshell_has_token(int argc, char **argv, const char *tok){
  for(int i=1;i<argc;i++) if(argv[i] && !strcmp(argv[i],tok)) return 1;
  return 0;
}
int ffshell_rewrite_io_paths(int argc, char **argv)
{
    OptionParseContext octx;
    int ret;

    memset(&octx, 0, sizeof(octx));
    ret = split_commandline(&octx, argc, argv, options, groups,
                            FF_ARRAY_ELEMS(groups));
    if (ret < 0) {
        uninit_parse_context(&octx);
        return ret;
    }

    char *replaced = calloc((size_t)argc, 1);
    for (int gi = 0; gi < octx.nb_groups; gi++) {
        OptionGroupList *l = &octx.groups[gi];
        int is_output;

        if (l->group_def == &groups[GROUP_OUTFILE])     is_output = 1;
        else if (l->group_def == &groups[GROUP_INFILE]) is_output = 0;
        else continue;

        for (int g = 0; g < l->nb_groups; g++) {
            const char *raw = l->groups[g].arg;
            char *url;

            if (!raw || !*raw)
                continue;
            url = ffshell_path_hook_request(is_output, raw);
            if (!url)
                continue;
            for (int i = 1; i < argc; i++) {
                if (replaced && replaced[i]) continue;
                if (argv[i] == raw || (argv[i] && !strcmp(argv[i], raw))) {
                    argv[i] = url;
                    if (replaced) replaced[i] = 1;
                    break;
                }
            }
        }
    }
    free(replaced);
    uninit_parse_context(&octx);
    return 0;
}
/* ---- end FFShell io-path rewrite ---------------------------------------- */
FFSHELL_OPT_HOOKS
	else
		echo "FFShell opt hooks already present."
	fi

	# --- input-path rewrite for ffprobe (its own linear grammar) --------
	local PROBE_TARGET="$FFMPEG_SOURCE_DIR/fftools/ffprobe.c"
	if ! grep -q "ffshell_rewrite_probe_paths" "$PROBE_TARGET"; then
	cat >> "$PROBE_TARGET" <<'FFSHELL_PROBE_HOOKS'

/* ---- FFShell input-path rewrite (appended by android.sh) ---------------- */
/*
 * Hardened appfd probe rewrite (Android 14): keep appfd:N as-is, no /proc fallback.
 * - Reliable: handles -i/-o values, "--", positional inputs, duplicate paths and already-replaced slots.
 * - Hardened: appfd protocol guaranteed, so keep appfd:N (fixes Permission denied on API 34).
 *   Never injects -y: ffprobe has no -y/-n option.
 * - The callback decides whether a raw path needs fd substitution (return NULL to keep).
 * - Duplicate raw values handled via replaced[] tracking, mirroring ffmpeg.
 */
extern char *ffshell_path_hook_request(int is_output, const char *raw_path);

int ffshell_rewrite_probe_paths(int argc, char **argv)
{
    int handleoptions = 1;
    char *replaced = calloc((size_t)argc, 1);
    for (int optindex = 1; optindex < argc && argv[optindex]; optindex++) {
        const char *opt = argv[optindex];
        const char *raw = NULL;
        int is_output = 0;
        int target = -1;

        if (!opt) continue;
        if (replaced && replaced[optindex]) continue;

        if (handleoptions && opt[0] == '-' && opt[1] != '\0') {
            if (opt[1] == '-' && opt[2] == '\0') {
                handleoptions = 0;
                continue;
            }
            if (!strcmp(opt, "-i")) {
                if (optindex + 1 < argc && argv[optindex + 1] && !(replaced && replaced[optindex+1])) {
                    raw = argv[optindex + 1];
                    target = optindex + 1;
                    is_output = 0;
                }
            } else if (!strcmp(opt, "-o")) {
                if (optindex + 1 < argc && argv[optindex + 1] && !(replaced && replaced[optindex+1])) {
                    raw = argv[optindex + 1];
                    target = optindex + 1;
                    is_output = 1;
                }
            } else {
                continue;
            }
        } else {
            raw = opt;
            target = optindex;
            is_output = 0;
        }

        if (!raw || !*raw || target < 0 || target >= argc) continue;
        if (replaced && replaced[target]) continue;

        char *url = ffshell_path_hook_request(is_output, raw);
        if (url) {
            // Hardened: keep appfd:N as-is (no /proc fallback)
            argv[target] = url;
            if (replaced) replaced[target] = 1;
        }
    }
    /* Also handle any remaining positional bare tokens that are true
     * inputs (e.g. "ffprobe input.mp4" or after "--"). The previous loop
     * already handled most, but bare tokens that follow a value-taking
     * option like "-print_format json" were skipped as "other option".
     * We now scan bare tokens and offer them; the callback will filter
     * non-files (like "json") by returning NULL. Duplicates are safe via
     * replaced[]. */
    for (int i = 1; i < argc; i++) {
        if (replaced && replaced[i]) continue;
        const char *tok = argv[i];
        if (!tok || !*tok) continue;
        if (tok[0] == '-') continue;
        // Don't treat a bare token that is the value of -i/-o (already handled)
        if (i > 0 && argv[i-1] && (!strcmp(argv[i-1], "-i") || !strcmp(argv[i-1], "-o"))) continue;
        // For ffprobe, bare tokens are inputs. Offer them.
        // this bare token is probably that option's value, not a file.
        // So skip it.
        if (i > 0 && argv[i-1] && argv[i-1][0] == '-') {
            // Check if previous option is known to take a value by looking
            // at its name: for ffprobe, most non-bool options take a value.
            // We conservatively assume any -<letter> with next bare token
            // is an option value unless it's a known file-like input.
            // To avoid false positives, only treat as file if previous
            // token is not an option or is "--"
            // Actually we want to treat "input.mp4" after "ffprobe -v quiet input.mp4"
            // where previous token is "quiet" (value of -v). That "input.mp4"
            // would be skipped by this heuristic incorrectly.
            // So we need a more precise check: only skip if previous option
            // is one of the known value-taking options (f, unit, etc.) and
            // current token looks like a value, not a file.
            // For reliability, we use a small allowlist of ffprobe value-taking
            // options and skip only those; otherwise treat as input.
            const char *prev = argv[i-1];
            // small list of ffprobe options that take a value and whose value is never a file path
            if (!strcmp(prev, "-f") || !strcmp(prev, "-unit") || !strcmp(prev, "-prefix")
                || !strcmp(prev, "-byte_binary_prefix") || !strcmp(prev, "-sexagesimal")
                || !strcmp(prev, "-pretty") || !strcmp(prev, "-output_format") || !strcmp(prev, "-print_format")
                || !strcmp(prev, "-of") || !strcmp(prev, "-select_streams") || !strcmp(prev, "-sections")
                || !strcmp(prev, "-data_dump_format") || !strcmp(prev, "-show_data_hash")
                || !strcmp(prev, "-c") || !strcmp(prev, "-codec") || !strcmp(prev, "-read_intervals")
                || !strcmp(prev, "-print_filename") || !strcmp(prev, "-v") || !strcmp(prev, "-loglevel")) {
                continue;
            }
        }
        // This bare token is a likely input file
        char *url = ffshell_path_hook_request(0, tok);
        if (url) {
            // Hardened: keep appfd:N as-is (no /proc fallback)
            argv[i] = url;
            replaced[i] = 1;
        }
    }
    free(replaced);
    return 0;
}
/* ---- end FFShell input-path rewrite ------------------------------------- */
FFSHELL_PROBE_HOOKS
	else
		echo "FFShell probe hooks already present."
	fi

	# Pure FD hook (merged stdout+stderr socketpair) now provides 1:1 raw
	# terminal capture via ffshell/src/ffshell_ffmpeg.c:setup_raw_terminal_capture.
	# No source patches needed for log_callback_help / log_callback_report —
	# help/version/report already go via stdout/stderr → pipe, preserving \r/ANSI.
	# Keep this block as no-op for backwards compat; skip patching.
	:

	return 0
}

buildLibx264(){
	TARGET_ARCH=$1; TARGET_CPU=$2; PREFIX=$3; CROSS_PREFIX=$4; EXTRA_CFLAGS=$5; EXTRA_CXXFLAGS=$6; EXTRA_CONFIG=$7
	# x264 configure needs --host and --cross-prefix without trailing dash for some versions
	# Map TARGET_ARCH to x264 host strings
	X264_HOST=""
	case "$TARGET_ARCH" in
		aarch64) X264_HOST="aarch64-linux-android" ;;
		arm)     X264_HOST="arm-linux-androideabi" ;;
		x86_64)  X264_HOST="x86_64-linux-android" ;;
		i686|x86) X264_HOST="i686-linux-android" ;;
		*)       X264_HOST="$TARGET_ARCH-linux-android" ;;
	esac

	cd "${SRC_DIR}/x264" || return 1
	# Clean previous build
	make distclean > /dev/null 2>&1 || true
	echo "Configuring libx264 for $TARGET_ARCH ($X264_HOST)..."
	# x264: keep ThinLTO for umbrella but build x264 without LTO to allow asm (2-4x gain) without override-stack-alignment conflicts
	X264_CFLAGS=$(echo "$EXTRA_CFLAGS" | sed 's/-flto[^ ]*//g')
	X264_CXXFLAGS=$(echo "$EXTRA_CXXFLAGS" | sed 's/-flto[^ ]*//g')
	# x264 asm: ARM uses clang, x86_64 uses nasm, x86 (i686) disable asm by default (emulator-only, ENABLE_X86_ASM=1 to enable)
	X264_AS="${CROSS_PREFIX}clang"
	X264_ASFLAGS="-fPIC"
	X264_DISABLE_ASM=""
	case "$TARGET_ARCH" in
		x86_64) X264_AS="nasm"; X264_ASFLAGS="" ;;
		i686|x86)
			X264_AS="nasm"; X264_ASFLAGS=""
			if [ "$ENABLE_X86_ASM" != "1" ]; then
				X264_DISABLE_ASM="--disable-asm"
			fi
			;;
	esac
	# x264 uses --host, --cross-prefix, --sysroot, --prefix
	CC="${CROSS_PREFIX}clang" \
	CXX="${CROSS_PREFIX}clang++" \
	AS="$X264_AS" \
	ASFLAGS="$X264_ASFLAGS" \
	AR="$LLVM_AR" \
	RANLIB="$LLVM_RANLIB" \
	STRIP="$LLVM_STRIP" \
	STRINGS="$LLVM_STRINGS" \
	./configure \
		--prefix="$PREFIX" \
		--host="$X264_HOST" \
		--cross-prefix="$CROSS_PREFIX" \
		--sysroot="$SYSROOT" \
		--enable-static \
		--enable-pic \
		--disable-cli \
		--disable-win32thread \
		--disable-avs \
		--disable-swscale \
		--disable-lavf \
		--disable-ffms \
		--disable-gpac \
		--disable-opencl \
		--disable-lsmash \
		$X264_DISABLE_ASM \
		--extra-cflags="-O3 -DNDEBUG -fPIC -DANDROID -D__BIONIC_NO_PAGE_SIZE_MACRO $X264_CFLAGS -I$PREFIX/include" \
		--extra-ldflags="-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384 -L$PREFIX/lib" \
		|| return 1

	# x264's configure probes -mstack-alignment/-mpreferred-stack-boundary and bakes them into CFLAGS.
	# Those set LLVM module flag `override-stack-alignment` which conflicts with ffmpeg's LTO objects
	# (ld.lld: error: linking module flags 'override-stack-alignment': IDs have conflicting values).
	# When x264 is built without LTO (no bitcode) this conflict disappears; keep sed as safety for any remaining flags.
	if [ -f config.mak ]; then
		sed -i 's/-mstack-alignment=[0-9]*//g; s/-mpreferred-stack-boundary=[0-9]*//g; s/-mstackrealign//g' config.mak 2>/dev/null || true
		# Also clean up extra spaces
		sed -i 's/  */ /g' config.mak 2>/dev/null || true
	fi

	make -j"$JOBS" || return 1
	make install || return 1
}

buildLibx265(){
	TARGET_ARCH=$1; TARGET_CPU=$2; PREFIX=$3; CROSS_PREFIX=$4; EXTRA_CFLAGS=$5; EXTRA_CXXFLAGS=$6; EXTRA_CONFIG=$7
	cd "${SRC_DIR}/x265" || return 1
	# x265 uses cmake; create build dir
	rm -rf build; mkdir -p build; cd build
	# Map to cmake system
	CMAKE_SYSTEM="Android"
	CMAKE_ARCH=""
	case "$TARGET_ARCH" in
		aarch64) CMAKE_ARCH="arm64-v8a" ;;
		arm)     CMAKE_ARCH="armeabi-v7a" ;;
		x86_64)  CMAKE_ARCH="x86_64" ;;
		i686|x86) CMAKE_ARCH="x86" ;;
	esac
	# x265: keep ThinLTO for umbrella but build x265 without LTO to avoid ThinLTO+asm conflicts
	X265_CFLAGS=$(echo "$EXTRA_CFLAGS" | sed 's/-flto[^ ]*//g')
	X265_CXXFLAGS=$(echo "$EXTRA_CXXFLAGS" | sed 's/-flto[^ ]*//g')
	X265_ASM="ON"
	case "$TARGET_ARCH" in
		arm|aarch64) X265_ASM="ON" ;;
		i686|x86)
			if [ "$ENABLE_X86_ASM" = "1" ]; then
				X265_ASM="ON"
			else
				X265_ASM="OFF"
			fi
			;;
		x86_64) X265_ASM="ON" ;;
	esac
	# Fix x265 ARM asm: inject --target into custom ASM commands and fix ARM_ALIASES for armv7-a
	if [ "$X265_ASM" = "ON" ] && { [ "$TARGET_ARCH" = "aarch64" ] || [ "$TARGET_ARCH" = "arm" ]; }; then
		# Patch ARM_ALIASES to include armv7-a and aarch64 variants
		if grep -q 'set(ARM_ALIASES' ../source/CMakeLists.txt; then
			sed -i 's|set(ARM_ALIASES.*|set(ARM_ALIASES armv6l armv7l armv7-a arm aarch64)|' ../source/CMakeLists.txt || true
		fi
		if grep -q 'set(ARM64_ALIASES' ../source/CMakeLists.txt; then
			sed -i 's|set(ARM64_ALIASES.*|set(ARM64_ALIASES arm64 arm64e aarch64 armv8-a)|' ../source/CMakeLists.txt || true
		fi
		# Inject --target into ASM custom commands (fixes unknown CPU 'armv8-a' with NDK r28c)
		# Use CMAKE_CXX_COMPILER_TARGET if available, else ANDROID_LLVM_TRIPLE
		if ! grep -q -- '--target=' ../source/CMakeLists.txt; then
			sed -i 's|COMMAND \${CMAKE_CXX_COMPILER}|COMMAND \${CMAKE_CXX_COMPILER} --target=\${CMAKE_CXX_COMPILER_TARGET}|g' ../source/CMakeLists.txt || true
			# Fallback if CMAKE_CXX_COMPILER_TARGET empty: use ANDROID_LLVM_TRIPLE
			sed -i 's|COMMAND \${CMAKE_CXX_COMPILER} --target=|COMMAND \${CMAKE_CXX_COMPILER} --target=\${ANDROID_LLVM_TRIPLE} --target=|g' ../source/CMakeLists.txt || true
		fi
	fi
	cmake ../source -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_PATH/build/cmake/android.toolchain.cmake" \
		-DANDROID_ABI="$CMAKE_ARCH" -DANDROID_PLATFORM="android-$ANDROID_API_LEVEL" \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DENABLE_ASSEMBLY=$X265_ASM \
		-DCMAKE_C_FLAGS="-fPIC $X265_CFLAGS" -DCMAKE_CXX_FLAGS="-fPIC $X265_CXXFLAGS" || { git -C ../source checkout -- CMakeLists.txt 2>/dev/null || true; return 1; }
	# Restore CMakeLists after successful configure (keep repo clean)
	git -C ../source checkout -- CMakeLists.txt 2>/dev/null || true
	make -j"$JOBS" || return 1
	make install || return 1
	# x265's CMake only generates x265.pc when X265_LATEST_TAG is known; for unknown git versions it skips pkg-config.
	# FFmpeg's configure checks `pkg-config --exists x265` and needs -lm/-lc++ for static link.
	# Create a minimal pc that exposes those in Libs (not just Libs.private) so `pkg-config --libs x265` links.
	if [ ! -f "$PREFIX/lib/pkgconfig/x265.pc" ]; then
		mkdir -p "$PREFIX/lib/pkgconfig"
		cat > "$PREFIX/lib/pkgconfig/x265.pc" <<EOF
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: x265
Description: H.265/HEVC video encoder
Version: 3.5
Libs: -L\${libdir} -lx265 -lc++ -lm
Libs.private: -lc++ -lm -pthread
Cflags: -I\${includedir}
EOF
		echo "Created fallback x265.pc at $PREFIX/lib/pkgconfig/x265.pc"
	else
		# Ensure existing pc exposes -lc++/-lm in Libs for ffmpeg's non-static pkg-config check
		sed -i 's|^Libs:.*|Libs: -L${libdir} -lx265 -lc++ -lm|' "$PREFIX/lib/pkgconfig/x265.pc" || true
	fi
}


buildLibdav1d(){
	TARGET_ARCH=$1; TARGET_CPU=$2; PREFIX=$3; CROSS_PREFIX=$4; EXTRA_CFLAGS=$5; EXTRA_CXXFLAGS=$6; EXTRA_CONFIG=$7
	CLANG="${CROSS_PREFIX}clang"
    CLANGXX="${CROSS_PREFIX}clang++"

	if [ "$TARGET_ARCH" = "i686" ]; then
	    TARGET_ARCH="x86"
	fi
 
	cd "${SRC_DIR}/dav1d" || return 1
	# --- Create cross file ---
  	CROSS_FILE="android-$TARGET_ARCH-$ANDROID_API_LEVEL-cross.messon"
	# Convert EXTRA_CFLAGS/CXXFLAGS into meson list format (e.g. '-O3', '-flto=thin')
	_DAV1D_C_ARGS=$(printf "%s" "$EXTRA_CFLAGS" | awk '{for(i=1;i<=NF;i++) printf "\x27%s\x27, ", $i}')
	_DAV1D_CPP_ARGS=$(printf "%s" "$EXTRA_CXXFLAGS" | awk '{for(i=1;i<=NF;i++) printf "\x27%s\x27, ", $i}')
	cat > "$CROSS_FILE" <<EOF

[binaries]
c = '$CLANG'
cpp = '$CLANGXX'
ar = '$LLVM_AR'
strip = '$LLVM_STRIP'
pkg-config = 'pkg-config'

[properties]
needs_exe_wrapper = true

[built-in options]
c_args = ['-fpic', ${_DAV1D_C_ARGS} '-DANDROID', '-D__BIONIC_NO_PAGE_SIZE_MACRO']
cpp_args = ['-fpic', ${_DAV1D_CPP_ARGS} '-DANDROID', '-D__BIONIC_NO_PAGE_SIZE_MACRO']
c_link_args = ['-Wl,-z,max-page-size=16384', '-Wl,-z,common-page-size=16384', '-flto=thin']
cpp_link_args = ['-Wl,-z,max-page-size=16384', '-Wl,-z,common-page-size=16384', '-flto=thin']

[host_machine]
system = 'android'
cpu_family = '$TARGET_ARCH'
cpu = '$TARGET_CPU'
endian = 'little'
EOF
	
	echo "Meson cross file created: $CROSS_FILE"
  	rm -rf build
	meson setup build \
  	  --default-library=static \
  	  --prefix=$PREFIX \
  	  --buildtype release \
 	  -Denable_tests=false \
 	  -Denable_tools=false \
 	  -Db_lto=true \
 	  --cross-file=$CROSS_FILE
	
	ninja -C build || return 1
	ninja -C build install || return 1
}


buildLibvpx(){
	TARGET_ARCH=$1; TARGET_CPU=$2; PREFIX=$3; CROSS_PREFIX=$4; EXTRA_CFLAGS=$5; EXTRA_CXXFLAGS=$6; EXTRA_CONFIG=$7
	VPX_TARGET=""
	case "$TARGET_ARCH" in
		aarch64) VPX_TARGET="arm64-android-gcc" ;;
		arm)     VPX_TARGET="armv7-android-gcc" ;;
		x86_64)  VPX_TARGET="x86_64-android-gcc" ;;
		i686|x86) VPX_TARGET="x86-android-gcc" ;;
	esac
	cd "${SRC_DIR}/libvpx" || return 1
	make distclean > /dev/null 2>&1 || true
	# libvpx's configure mis-handles inherited ASFLAGS=-fPIC (breaks nasm: nasm -fPIC -f elf64 => unrecognised output format `PIC').
	# Clear ASFLAGS and set proper NDK cross tools. For ARM, AS must be clang (NDK has no ${CROSS}as), for x86 use nasm.
	VPX_AS=""
	VPX_ASFLAGS=""
	case "$TARGET_ARCH" in
		aarch64|arm) VPX_AS="${CROSS_PREFIX}clang"; VPX_ASFLAGS="-c" ;;
		x86_64|x86|i686) VPX_AS="nasm"; VPX_ASFLAGS="" ;;
	esac
	# vpx's custom STRIP step (llvm-strip) can't handle ThinLTO bitcode; keep arch opts but no LTO
	VPX_CFLAGS=$(echo "$EXTRA_CFLAGS" | sed 's/-flto[^ ]*//g')
	VPX_CXXFLAGS=$(echo "$EXTRA_CXXFLAGS" | sed 's/-flto[^ ]*//g')
	if [ -n "$VPX_AS" ]; then
		CFLAGS="$VPX_CFLAGS -I$PREFIX/include" CXXFLAGS="$VPX_CXXFLAGS -I$PREFIX/include" LDFLAGS="-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384 -L$PREFIX/lib" \
		CC="${CROSS_PREFIX}clang" CXX="${CROSS_PREFIX}clang++" AR="$LLVM_AR" LD="${CROSS_PREFIX}clang" STRIP="$LLVM_STRIP" AS="$VPX_AS" ASFLAGS="$VPX_ASFLAGS" CROSS="$CROSS_PREFIX" \
		./configure --prefix="$PREFIX" --target="$VPX_TARGET" --enable-pic --disable-examples --disable-tools --disable-docs --disable-unit-tests || return 1
	else
		CFLAGS="$VPX_CFLAGS -I$PREFIX/include" CXXFLAGS="$VPX_CXXFLAGS -I$PREFIX/include" LDFLAGS="-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384 -L$PREFIX/lib" \
		CC="${CROSS_PREFIX}clang" CXX="${CROSS_PREFIX}clang++" AR="$LLVM_AR" LD="${CROSS_PREFIX}clang" STRIP="$LLVM_STRIP" \
		ASFLAGS="" CROSS="$CROSS_PREFIX" \
		./configure --prefix="$PREFIX" --target="$VPX_TARGET" --enable-pic --disable-examples --disable-tools --disable-docs --disable-unit-tests || return 1
	fi
	make -j"$JOBS" || return 1
	make install || return 1
}

buildLibopus(){
	TARGET_ARCH=$1; TARGET_CPU=$2; PREFIX=$3; CROSS_PREFIX=$4; EXTRA_CFLAGS=$5; EXTRA_CXXFLAGS=$6; EXTRA_CONFIG=$7
	cd "${SRC_DIR}/opus" || return 1
	# opus autogen downloads a large ML model from media.xiph.org which may be blocked in CI.
	# Remove any 0-byte or blocked-content tar left by previous failed download, then try autogen;
	# if it still fails (checksum/network), fall back to plain autoreconf so configure can still be generated.
	rm -f opus_data-a5177ec6fb7d15058e99e57029746100121f68e4890b1467d4094aa336b6013e.tar.gz 2>/dev/null || true
	if [ -f opus_data-a5177ec6fb7d15058e99e57029746100121f68e4890b1467d4094aa336b6013e.tar.gz ]; then
		sz=$(wc -c < opus_data-a5177ec6fb7d15058e99e57029746100121f68e4890b1467d4094aa336b6013e.tar.gz 2>/dev/null || echo 0)
		[ "$sz" -lt 1000 ] && rm -f opus_data-a5177ec6fb7d15058e99e57029746100121f68e4890b1467d4094aa336b6013e.tar.gz || true
	fi
	if ! ./autogen.sh > /dev/null 2>&1; then
		echo "opus autogen failed (likely network block for model download), falling back to autoreconf"
		# Bypass the model download in dnn/download_model.sh by making it a no-op for this build
		if [ -f dnn/download_model.sh ]; then
			sed -i 's/exit 1/exit 0/g' dnn/download_model.sh || true
		fi
		autoreconf -isf > /dev/null 2>&1 || true
	fi
	OPUS_HOST=""
	case "$TARGET_ARCH" in
		aarch64) OPUS_HOST="aarch64-linux-android" ;;
		arm)     OPUS_HOST="arm-linux-androideabi" ;;
		x86_64)  OPUS_HOST="x86_64-linux-android" ;;
		i686|x86) OPUS_HOST="i686-linux-android" ;;
	esac
	CFLAGS="$EXTRA_CFLAGS -I$PREFIX/include" CXXFLAGS="$EXTRA_CXXFLAGS -I$PREFIX/include" LDFLAGS="-flto=thin -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384 -L$PREFIX/lib" \
	CC="${CROSS_PREFIX}clang" CXX="${CROSS_PREFIX}clang++" AR="$LLVM_AR" RANLIB="$LLVM_RANLIB" \
	./configure --host="$OPUS_HOST" --prefix="$PREFIX" --with-sysroot="$SYSROOT" --enable-static --disable-shared --with-pic || return 1
	make -j"$JOBS" || return 1
	make install || return 1
	# opus.pc puts -lm in Libs.private, but ffmpeg's check_pkg_config for static opus needs -lm in Libs (pkg-config --libs without --static won't expose Libs.private).
	# Patch it so `pkg-config --libs opus` yields -lm and ffmpeg's opus check links correctly.
	if [ -f "$PREFIX/lib/pkgconfig/opus.pc" ]; then
		sed -i 's/^Libs:.*/Libs: -L${libdir} -lopus -lm/' "$PREFIX/lib/pkgconfig/opus.pc" || true
		sed -i 's/^Libs.private:.*/Libs.private: /' "$PREFIX/lib/pkgconfig/opus.pc" || true
	fi
}

buildLibmp3lame(){
	TARGET_ARCH=$1; TARGET_CPU=$2; PREFIX=$3; CROSS_PREFIX=$4; EXTRA_CFLAGS=$5; EXTRA_CXXFLAGS=$6; EXTRA_CONFIG=$7
	cd "${SRC_DIR}/lame" || return 1
	LAME_HOST=""
	case "$TARGET_ARCH" in
		aarch64) LAME_HOST="aarch64-linux-android" ;;
		arm)     LAME_HOST="arm-linux-androideabi" ;;
		x86_64)  LAME_HOST="x86_64-linux-android" ;;
		i686|x86) LAME_HOST="i686-linux-android" ;;
	esac
	CFLAGS="$EXTRA_CFLAGS -I$PREFIX/include" CXXFLAGS="$EXTRA_CXXFLAGS -I$PREFIX/include" LDFLAGS="-flto=thin -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384 -L$PREFIX/lib" \
	CC="${CROSS_PREFIX}clang" AR="$LLVM_AR" RANLIB="$LLVM_RANLIB" \
	./configure --host="$LAME_HOST" --prefix="$PREFIX" --enable-static --disable-shared --with-pic --disable-frontend || return 1
	make -j"$JOBS" || return 1
	make install || return 1
}

buildLibaom(){
	TARGET_ARCH=$1; TARGET_CPU=$2; PREFIX=$3; CROSS_PREFIX=$4; EXTRA_CFLAGS=$5; EXTRA_CXXFLAGS=$6; EXTRA_CONFIG=$7
	cd "${SRC_DIR}/aom" || return 1
	rm -rf build; mkdir -p build; cd build
	AOM_ABI=""
	case "$TARGET_ARCH" in
		aarch64) AOM_ABI="arm64-v8a" ;;
		arm)     AOM_ABI="armeabi-v7a" ;;
		x86_64)  AOM_ABI="x86_64" ;;
		i686|x86) AOM_ABI="x86" ;;
	esac
	cmake .. -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_PATH/build/cmake/android.toolchain.cmake" \
		-DANDROID_ABI="$AOM_ABI" -DANDROID_PLATFORM="android-$ANDROID_API_LEVEL" \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" -DENABLE_EXAMPLES=OFF -DENABLE_TESTS=OFF -DENABLE_DOCS=OFF -DBUILD_SHARED_LIBS=OFF \
		-DCMAKE_C_FLAGS="-fPIC $EXTRA_CFLAGS" -DCMAKE_CXX_FLAGS="-fPIC $EXTRA_CXXFLAGS" || return 1
	make -j"$JOBS" || return 1
	make install || return 1
}

buildFreetype(){
	TARGET_ARCH=$1; TARGET_CPU=$2; PREFIX=$3; CROSS_PREFIX=$4; EXTRA_CFLAGS=$5; EXTRA_CXXFLAGS=$6; EXTRA_CONFIG=$7
	cd "${SRC_DIR}/freetype" || return 1
	# freetype autotools may need autogen if from git, but tarball has configure
	[ -f ./autogen.sh ] && ./autogen.sh > /dev/null 2>&1 || true
	FREETYPE_HOST=""
	case "$TARGET_ARCH" in
		aarch64) FREETYPE_HOST="aarch64-linux-android" ;;
		arm)     FREETYPE_HOST="arm-linux-androideabi" ;;
		x86_64)  FREETYPE_HOST="x86_64-linux-android" ;;
		i686|x86) FREETYPE_HOST="i686-linux-android" ;;
	esac
	CFLAGS="$EXTRA_CFLAGS -I$PREFIX/include -DANDROID -D__BIONIC_NO_PAGE_SIZE_MACRO" CXXFLAGS="$EXTRA_CXXFLAGS -I$PREFIX/include -DANDROID -D__BIONIC_NO_PAGE_SIZE_MACRO" LDFLAGS="-flto=thin -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384 -L$PREFIX/lib" \
	CC="${CROSS_PREFIX}clang" CXX="${CROSS_PREFIX}clang++" AR="$LLVM_AR" RANLIB="$LLVM_RANLIB" STRIP="$LLVM_STRIP" PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" \
	./configure --host="$FREETYPE_HOST" --prefix="$PREFIX" --with-sysroot="$SYSROOT" --enable-static --disable-shared --with-pic --without-harfbuzz --without-brotli --without-bzip2 --without-png --without-zlib || return 1
	make -j"$JOBS" || return 1
	make install || return 1
}

buildFribidi(){
	TARGET_ARCH=$1; TARGET_CPU=$2; PREFIX=$3; CROSS_PREFIX=$4; EXTRA_CFLAGS=$5; EXTRA_CXXFLAGS=$6; EXTRA_CONFIG=$7
	CLANG="${CROSS_PREFIX}clang"
	CLANGXX="${CROSS_PREFIX}clang++"
	if [ "$TARGET_ARCH" = "i686" ]; then
		TARGET_ARCH="x86"
	fi
	cd "${SRC_DIR}/fribidi" || return 1
	CROSS_FILE="android-$TARGET_ARCH-$ANDROID_API_LEVEL-cross.meson"
	_FRIBIDI_C_ARGS=$(printf "%s" "$EXTRA_CFLAGS" | awk '{for(i=1;i<=NF;i++) printf "\x27%s\x27, ", $i}')
	_FRIBIDI_CPP_ARGS=$(printf "%s" "$EXTRA_CXXFLAGS" | awk '{for(i=1;i<=NF;i++) printf "\x27%s\x27, ", $i}')
	cat > "$CROSS_FILE" <<EOF
[binaries]
c = '$CLANG'
cpp = '$CLANGXX'
ar = '$LLVM_AR'
strip = '$LLVM_STRIP'
pkg-config = 'pkg-config'
[properties]
needs_exe_wrapper = true
[built-in options]
c_args = ['-fpic', ${_FRIBIDI_C_ARGS} '-DANDROID', '-D__BIONIC_NO_PAGE_SIZE_MACRO', '-I$PREFIX/include']
cpp_args = ['-fpic', ${_FRIBIDI_CPP_ARGS} '-DANDROID', '-D__BIONIC_NO_PAGE_SIZE_MACRO', '-I$PREFIX/include']
c_link_args = ['-Wl,-z,max-page-size=16384', '-Wl,-z,common-page-size=16384', '-flto=thin', '-L$PREFIX/lib']
cpp_link_args = ['-Wl,-z,max-page-size=16384', '-Wl,-z,common-page-size=16384', '-flto=thin', '-L$PREFIX/lib']
[host_machine]
system = 'android'
cpu_family = '$TARGET_ARCH'
cpu = '$TARGET_CPU'
endian = 'little'
EOF
	echo "Meson cross file created: $CROSS_FILE"
	rm -rf build
	meson setup build --default-library=static --prefix=$PREFIX --buildtype release -Ddocs=false -Dtests=false --cross-file=$CROSS_FILE || return 1
	ninja -C build || return 1
	ninja -C build install || return 1
}

buildHarfbuzz(){
	TARGET_ARCH=$1; TARGET_CPU=$2; PREFIX=$3; CROSS_PREFIX=$4; EXTRA_CFLAGS=$5; EXTRA_CXXFLAGS=$6; EXTRA_CONFIG=$7
	CLANG="${CROSS_PREFIX}clang"
	CLANGXX="${CROSS_PREFIX}clang++"
	if [ "$TARGET_ARCH" = "i686" ]; then
		TARGET_ARCH="x86"
	fi
	cd "${SRC_DIR}/harfbuzz" || return 1
	CROSS_FILE="android-$TARGET_ARCH-$ANDROID_API_LEVEL-cross.meson"
	_HARFBUZZ_C_ARGS=$(printf "%s" "$EXTRA_CFLAGS" | awk '{for(i=1;i<=NF;i++) printf "\x27%s\x27, ", $i}')
	_HARFBUZZ_CPP_ARGS=$(printf "%s" "$EXTRA_CXXFLAGS" | awk '{for(i=1;i<=NF;i++) printf "\x27%s\x27, ", $i}')
	cat > "$CROSS_FILE" <<EOF
[binaries]
c = '$CLANG'
cpp = '$CLANGXX'
ar = '$LLVM_AR'
strip = '$LLVM_STRIP'
pkg-config = 'pkg-config'
[properties]
needs_exe_wrapper = true
[built-in options]
c_args = ['-fpic', ${_HARFBUZZ_C_ARGS} '-DANDROID', '-D__BIONIC_NO_PAGE_SIZE_MACRO', '-I$PREFIX/include']
cpp_args = ['-fpic', ${_HARFBUZZ_CPP_ARGS} '-DANDROID', '-D__BIONIC_NO_PAGE_SIZE_MACRO', '-I$PREFIX/include']
c_link_args = ['-Wl,-z,max-page-size=16384', '-Wl,-z,common-page-size=16384', '-flto=thin', '-L$PREFIX/lib']
cpp_link_args = ['-Wl,-z,max-page-size=16384', '-Wl,-z,common-page-size=16384', '-flto=thin', '-L$PREFIX/lib']
[host_machine]
system = 'android'
cpu_family = '$TARGET_ARCH'
cpu = '$TARGET_CPU'
endian = 'little'
EOF
	echo "Meson cross file created: $CROSS_FILE"
	rm -rf build
	PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" meson setup build --default-library=static --prefix=$PREFIX --buildtype release -Dfreetype=enabled  -Dglib=disabled -Dgobject=disabled -Dcairo=disabled -Dicu=disabled -Dgraphite=disabled -Dgraphite2=disabled -Dtests=disabled -Ddocs=disabled -Dbenchmark=disabled --cross-file=$CROSS_FILE || return 1
	ninja -C build || return 1
	ninja -C build install || return 1
}

buildLibass(){
	TARGET_ARCH=$1; TARGET_CPU=$2; PREFIX=$3; CROSS_PREFIX=$4; EXTRA_CFLAGS=$5; EXTRA_CXXFLAGS=$6; EXTRA_CONFIG=$7
	cd "${SRC_DIR}/libass" || return 1
	./autogen.sh > /dev/null 2>&1 || true
	ASS_HOST=""
	case "$TARGET_ARCH" in
		aarch64) ASS_HOST="aarch64-linux-android" ;;
		arm)     ASS_HOST="arm-linux-androideabi" ;;
		x86_64)  ASS_HOST="x86_64-linux-android" ;;
		i686|x86) ASS_HOST="i686-linux-android" ;;
	esac
	CFLAGS="$EXTRA_CFLAGS -I$PREFIX/include" CXXFLAGS="$EXTRA_CXXFLAGS -I$PREFIX/include" LDFLAGS="-flto=thin -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384 -L$PREFIX/lib" \
	CC="${CROSS_PREFIX}clang" CXX="${CROSS_PREFIX}clang++" PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" \
	./configure --host="$ASS_HOST" --prefix="$PREFIX" --enable-static --disable-shared --with-pic --disable-fontconfig --disable-require-system-font-provider --disable-libunibreak --disable-test --disable-compare || return 1
	make -j"$JOBS" || return 1
	make install || return 1
}

buildLibfdkaac(){
	TARGET_ARCH=$1; TARGET_CPU=$2; PREFIX=$3; CROSS_PREFIX=$4; EXTRA_CFLAGS=$5; EXTRA_CXXFLAGS=$6; EXTRA_CONFIG=$7
	cd "${SRC_DIR}/fdk-aac" || return 1
	./autogen.sh > /dev/null 2>&1 || true
	FDK_HOST=""
	case "$TARGET_ARCH" in
		aarch64) FDK_HOST="aarch64-linux-android" ;;
		arm)     FDK_HOST="arm-linux-androideabi" ;;
		x86_64)  FDK_HOST="x86_64-linux-android" ;;
		i686|x86) FDK_HOST="i686-linux-android" ;;
	esac
	CFLAGS="$EXTRA_CFLAGS -I$PREFIX/include" CXXFLAGS="$EXTRA_CXXFLAGS -I$PREFIX/include" LDFLAGS="-flto=thin -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384 -L$PREFIX/lib" \
	CC="${CROSS_PREFIX}clang" CXX="${CROSS_PREFIX}clang++" AR="$LLVM_AR" RANLIB="$LLVM_RANLIB" \
	./configure --host="$FDK_HOST" --prefix="$PREFIX" --enable-static --disable-shared --with-pic || return 1
	make -j"$JOBS" || return 1
	make install || return 1
}

_android_cmake_abi() {
	case "$1" in
		aarch64) echo "arm64-v8a" ;;
		arm)     echo "armeabi-v7a" ;;
		x86_64)  echo "x86_64" ;;
		i686|x86) echo "x86" ;;
		*) echo "arm64-v8a" ;;
	esac
}

_android_host() {
	case "$1" in
		aarch64) echo "aarch64-linux-android" ;;
		arm)     echo "arm-linux-androideabi" ;;
		x86_64)  echo "x86_64-linux-android" ;;
		i686|x86) echo "i686-linux-android" ;;
		*) echo "aarch64-linux-android" ;;
	esac
}

buildLibogg(){
	TARGET_ARCH=$1; TARGET_CPU=$2; PREFIX=$3; CROSS_PREFIX=$4; EXTRA_CFLAGS=$5; EXTRA_CXXFLAGS=$6; EXTRA_CONFIG=$7
	cd "${SRC_DIR}/ogg" || return 1
	[ -f ./autogen.sh ] && ./autogen.sh >/dev/null 2>&1 || true
	CFLAGS="$EXTRA_CFLAGS -I$PREFIX/include" LDFLAGS="-L$PREFIX/lib" \
	CC="${CROSS_PREFIX}clang" CXX="${CROSS_PREFIX}clang++" AR="$LLVM_AR" RANLIB="$LLVM_RANLIB" \
	./configure --host="$(_android_host "$TARGET_ARCH")" --prefix="$PREFIX" --enable-static --disable-shared --with-pic || return 1
	make -j"$JOBS" || return 1
	make install || return 1
}

buildLibvorbis(){
	TARGET_ARCH=$1; TARGET_CPU=$2; PREFIX=$3; CROSS_PREFIX=$4; EXTRA_CFLAGS=$5; EXTRA_CXXFLAGS=$6; EXTRA_CONFIG=$7
	cd "${SRC_DIR}/vorbis" || return 1
	[ -f ./autogen.sh ] && ./autogen.sh >/dev/null 2>&1 || true
	CFLAGS="$EXTRA_CFLAGS -I$PREFIX/include" LDFLAGS="-L$PREFIX/lib" OGG_CFLAGS="-I$PREFIX/include" OGG_LIBS="-L$PREFIX/lib -logg" \
	CC="${CROSS_PREFIX}clang" CXX="${CROSS_PREFIX}clang++" AR="$LLVM_AR" RANLIB="$LLVM_RANLIB" \
	./configure --host="$(_android_host "$TARGET_ARCH")" --prefix="$PREFIX" --enable-static --disable-shared --with-pic || return 1
	make -j"$JOBS" || return 1
	make install || return 1
}

buildLibwebp(){
	TARGET_ARCH=$1; TARGET_CPU=$2; PREFIX=$3; CROSS_PREFIX=$4; EXTRA_CFLAGS=$5; EXTRA_CXXFLAGS=$6; EXTRA_CONFIG=$7
	cd "${SRC_DIR}/libwebp" || return 1
	rm -rf build; mkdir -p build; cd build
	cmake .. -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_PATH/build/cmake/android.toolchain.cmake" \
		-DANDROID_ABI="$(_android_cmake_abi "$TARGET_ARCH")" -DANDROID_PLATFORM="android-$ANDROID_API_LEVEL" \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" -DBUILD_SHARED_LIBS=OFF \
		-DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF \
		-DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF \
		-DWEBP_BUILD_EXTRAS=OFF -DCMAKE_C_FLAGS="-fPIC $EXTRA_CFLAGS" || return 1
	make -j"$JOBS" || return 1
	make install || return 1
	# FFmpeg's pkg-config check uses non-static Libs; include SharpYUV explicitly.
	WEBP_PC="$PREFIX/lib/pkgconfig/libwebp.pc"
	if [ -f "$WEBP_PC" ]; then
		sed -i 's|^Libs:.*|Libs: -L${libdir} -lwebp -lsharpyuv|' "$WEBP_PC" || true
	fi
}

buildLibsvtav1(){
	TARGET_ARCH=$1; TARGET_CPU=$2; PREFIX=$3; CROSS_PREFIX=$4; EXTRA_CFLAGS=$5; EXTRA_CXXFLAGS=$6; EXTRA_CONFIG=$7
	cd "${SRC_DIR}/SVT-AV1" || return 1
	rm -rf build; mkdir -p build; cd build
	cmake .. -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_PATH/build/cmake/android.toolchain.cmake" \
		-DANDROID_ABI="$(_android_cmake_abi "$TARGET_ARCH")" -DANDROID_PLATFORM="android-$ANDROID_API_LEVEL" \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" -DBUILD_SHARED_LIBS=OFF -DBUILD_APPS=OFF -DBUILD_TESTING=OFF \
		-DCMAKE_C_FLAGS="-fPIC $EXTRA_CFLAGS" -DCMAKE_CXX_FLAGS="-fPIC $EXTRA_CXXFLAGS" || return 1
	make -j"$JOBS" || return 1
	make install || return 1
}

buildLibjxl(){
	TARGET_ARCH=$1; TARGET_CPU=$2; PREFIX=$3; CROSS_PREFIX=$4; EXTRA_CFLAGS=$5; EXTRA_CXXFLAGS=$6; EXTRA_CONFIG=$7
	cd "${SRC_DIR}/libjxl" || return 1
	rm -rf build; mkdir -p build; cd build
	cmake .. -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_PATH/build/cmake/android.toolchain.cmake" \
		-DANDROID_ABI="$(_android_cmake_abi "$TARGET_ARCH")" -DANDROID_PLATFORM="android-$ANDROID_API_LEVEL" \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF \
		-DJPEGXL_ENABLE_TOOLS=OFF -DJPEGXL_ENABLE_BENCHMARK=OFF -DJPEGXL_ENABLE_EXAMPLES=OFF \
		-DJPEGXL_ENABLE_MANPAGES=OFF -DJPEGXL_ENABLE_VIEWERS=OFF -DJPEGXL_ENABLE_SJPEG=OFF \
		-DCMAKE_C_FLAGS="-fPIC $EXTRA_CFLAGS" -DCMAKE_CXX_FLAGS="-fPIC $EXTRA_CXXFLAGS" || return 1
	make -j"$JOBS" || return 1
	make install || return 1
}

buildLibsoxr(){
	TARGET_ARCH=$1; TARGET_CPU=$2; PREFIX=$3; CROSS_PREFIX=$4; EXTRA_CFLAGS=$5; EXTRA_CXXFLAGS=$6; EXTRA_CONFIG=$7
	cd "${SRC_DIR}/soxr" || return 1
	rm -rf build; mkdir -p build; cd build
	# x86 lacks a usable OpenMP runtime in this NDK toolchain; keep it on for ARM/ARM64.
	SOXR_OPENMP="-DWITH_OPENMP=ON"
	case "$TARGET_ARCH" in
		i686|x86) SOXR_OPENMP="-DWITH_OPENMP=OFF" ;;
	esac
	cmake .. -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_PATH/build/cmake/android.toolchain.cmake" \
		-DANDROID_ABI="$(_android_cmake_abi "$TARGET_ARCH")" -DANDROID_PLATFORM="android-$ANDROID_API_LEVEL" \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTS=OFF \
		-DCMAKE_POLICY_VERSION_MINIMUM=3.5 $SOXR_OPENMP \
		-DCMAKE_C_FLAGS="-fPIC $EXTRA_CFLAGS" || return 1
	make -j"$JOBS" || return 1
	make install || return 1
}

buildLibrubberband(){
	TARGET_ARCH=$1; TARGET_CPU=$2; PREFIX=$3; CROSS_PREFIX=$4; EXTRA_CFLAGS=$5; EXTRA_CXXFLAGS=$6; EXTRA_CONFIG=$7
	cd "${SRC_DIR}/rubberband" || return 1
	rm -rf build; mkdir -p build
	CROSS_FILE="$SCRIPT_DIR/android-$TARGET_ARCH-$ANDROID_API_LEVEL-cross.meson"
	[ -f "$CROSS_FILE" ] || CROSS_FILE="$(ls "$SCRIPT_DIR"/android-*-$ANDROID_API_LEVEL-cross.meson 2>/dev/null | head -1)"
	meson setup build --default-library=static --prefix="$PREFIX" --buildtype release -Dtests=disabled -Ddocs=disabled ${CROSS_FILE:+--cross-file="$CROSS_FILE"} || return 1
	ninja -C build || return 1
	ninja -C build install || return 1
}

buildLibvidstab(){
	TARGET_ARCH=$1; TARGET_CPU=$2; PREFIX=$3; CROSS_PREFIX=$4; EXTRA_CFLAGS=$5; EXTRA_CXXFLAGS=$6; EXTRA_CONFIG=$7
	cd "${SRC_DIR}/vid.stab" || return 1
	rm -rf build; mkdir -p build; cd build
	cmake .. -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_PATH/build/cmake/android.toolchain.cmake" \
		-DANDROID_ABI="$(_android_cmake_abi "$TARGET_ARCH")" -DANDROID_PLATFORM="android-$ANDROID_API_LEVEL" \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" -DBUILD_SHARED_LIBS=OFF \
		-DCMAKE_C_FLAGS="-fPIC $EXTRA_CFLAGS" || return 1
	make -j"$JOBS" || return 1
	make install || return 1
}

buildLibxvid(){
	TARGET_ARCH=$1; TARGET_CPU=$2; PREFIX=$3; CROSS_PREFIX=$4; EXTRA_CFLAGS=$5; EXTRA_CXXFLAGS=$6; EXTRA_CONFIG=$7
	cd "${SRC_DIR}/xvidcore" || return 1
	XVID_CONFIGURE=$(find . -type f -path "*/build/generic/configure.in" | head -1)
	[ -n "$XVID_CONFIGURE" ] || return 1
	cd "$(dirname "$XVID_CONFIGURE")" || return 1
	if [ ! -x ./configure ]; then
		[ -x ./bootstrap.sh ] && ./bootstrap.sh >/dev/null 2>&1 || true
	fi
	[ -x ./configure ] || return 1
	CFLAGS="$EXTRA_CFLAGS -I$PREFIX/include" LDFLAGS="-L$PREFIX/lib" \
	CC="${CROSS_PREFIX}clang" CXX="${CROSS_PREFIX}clang++" AR="$LLVM_AR" RANLIB="$LLVM_RANLIB" \
	./configure --host="$(_android_host "$TARGET_ARCH")" --prefix="$PREFIX" --disable-assembly || return 1
	make -j"$JOBS" || return 1
	make install || return 1
	rm -f "$PREFIX"/lib/libxvidcore.so* 2>/dev/null || true
}

# Conditional wrappers - only build if ENABLED_CONFIG requests it

maybeBuildLibx264(){
	if echo "$ENABLED_CONFIG" | grep -q "enable-libx264"; then
		buildLibx264 "$@"
	else
		echo -e "\e[1;33mSkipping libx264 build (not enabled)\e[0m"
		return 0
	fi
}

maybeBuildLibdav1d(){
	if echo "$ENABLED_CONFIG" | grep -q "enable-libdav1d"; then
		buildLibdav1d "$@"
	else
		echo -e "\e[1;33mSkipping libdav1d build (not enabled)\e[0m"
		return 0
	fi
}

# Generic dispatcher for any external lib
maybeBuildExternal(){
	local lib="$1"; shift
	local flag="enable-lib${lib}"
	if [ "$lib" = "mp3lame" ]; then flag="enable-libmp3lame"; fi
	if [ "$lib" = "fdk-aac" ]; then flag="enable-libfdk-aac"; fi
	# freetype/fribidi/harfbuzz are deps for libass, not directly in ENABLED_CONFIG
	if [ "$lib" = "freetype" ] || [ "$lib" = "fribidi" ] || [ "$lib" = "harfbuzz" ]; then
		if ! echo "$ENABLED_CONFIG" | grep -q "enable-libass"; then
			echo -e "\e[1;33mSkipping lib${lib} build (libass not enabled)\e[0m"
			return 0
		fi
		# Force flag to pass the check
		flag="enable-libass"
	fi
	if [ "$lib" = "ogg" ]; then
		if ! echo "$ENABLED_CONFIG" | grep -q "enable-libvorbis"; then
			echo -e "\e[1;33mSkipping libogg build (libvorbis not enabled)\e[0m"
			return 0
		fi
		flag="enable-libvorbis"
	fi
	if echo "$ENABLED_CONFIG" | grep -q "$flag"; then
		case "$lib" in
			x265)    buildLibx265 "$@" ;;
			vpx)     buildLibvpx "$@" ;;
			opus)    buildLibopus "$@" ;;
			mp3lame) buildLibmp3lame "$@" ;;
			aom)     buildLibaom "$@" ;;
			freetype) buildFreetype "$@" ;;
			fribidi) buildFribidi "$@" ;;
			harfbuzz) buildHarfbuzz "$@" ;;
			ass)     buildLibass "$@" ;;
			fdk-aac) buildLibfdkaac "$@" ;;
			ogg)     buildLibogg "$@" ;;
			vorbis)  buildLibvorbis "$@" ;;
			webp)    buildLibwebp "$@" ;;
			svtav1)  buildLibsvtav1 "$@" ;;
			jxl)     buildLibjxl "$@" ;;
			soxr)    buildLibsoxr "$@" ;;
			rubberband) buildLibrubberband "$@" ;;
			vidstab) buildLibvidstab "$@" ;;
			xvid)    buildLibxvid "$@" ;;
			*) echo -e "\e[1;33mNo build recipe for $lib (flag $flag) - skipping\e[0m"; return 0 ;;
		esac
		local rc=$?
		if [ $rc -ne 0 ]; then
			if [ "$lib" = "ass" ] || [ "$lib" = "freetype" ] || [ "$lib" = "fribidi" ] || [ "$lib" = "harfbuzz" ]; then
				echo -e "\e[1;33mWarning: lib${lib} build failed (likely missing deps), disabling --enable-libass and continuing without it\e[0m"
				ENABLED_CONFIG=$(echo "$ENABLED_CONFIG" | sed "s/--enable-libass//g")
				# Also ensure PKG_CONFIG won't find half-installed libs
				rm -rf "$3/lib/libass.a" "$3/lib/pkgconfig/libass.pc" "$3/lib/libfreetype.a" "$3/lib/pkgconfig/freetype2.pc" "$3/lib/libharfbuzz.a" "$3/lib/pkgconfig/harfbuzz.pc" "$3/lib/libfribidi.a" "$3/lib/pkgconfig/fribidi.pc" 2>/dev/null || true
				return 0
			fi
			case "$lib" in
				ogg|vorbis|webp|svtav1|jxl|soxr|rubberband|vidstab|xvid)
					echo -e "\e[1;33mWarning: lib${lib} build failed, disabling --enable-lib${lib} and continuing\e[0m"
					ENABLED_CONFIG=$(echo "$ENABLED_CONFIG" | sed "s/--enable-lib${lib}//g")
					[ "$lib" = "ogg" ] && ENABLED_CONFIG=$(echo "$ENABLED_CONFIG" | sed "s/--enable-libvorbis//g")
					return 0
					;;
			esac
			return $rc
		fi
	else
		echo -e "\e[1;33mSkipping lib${lib} build (not enabled)\e[0m"
		return 0
	fi
}

create_umbrella_library(){
	# Creates ONE umbrella shared library (${PREFIX}/lib/${FFMPEG_UMBRELLA_NAME})
	# containing the FFmpeg libraries, the patched fftools CLI frontend and the
	# FFShell wrapper API plus the statically built libdav1d.
	PREFIX=$1
	CROSS_PREFIX=$2
	TARGET_ARCH=$3
	CLANG="${CROSS_PREFIX}clang"
	UMBRELLA_OUT="${PREFIX}/lib/${FFMPEG_UMBRELLA_NAME}"
	UMBRELLA_VER="${PREFIX}/libffmpeg.ver"
	UMBRELLA_RSP="${PREFIX}/libffmpeg_objects.rsp"
	UMBRELLA_OBJLIST="${PREFIX}/libffmpeg_objects.list"
	FFSHELL_WRAPPER_OBJ="${PREFIX}/lib/ffshell_wrapper.o"
	MAKE_DB="$(mktemp "${TMPDIR:-/tmp}/ffmpeg_make_db.XXXXXX")"

	echo -e "\e[1;32mCreating umbrella library ${UMBRELLA_OUT}...\e[0m"

	if [ ! -f "$FFMPEG_SOURCE_DIR/ffbuild/config.mak" ]; then
		echo "Error: $FFMPEG_SOURCE_DIR/ffbuild/config.mak not found. FFmpeg was not configured/built."
		return 1
	fi

	### 1) Collect the exact object files from FFmpeg's build system ##########
	pushd "$FFMPEG_SOURCE_DIR" > /dev/null || return 1

	make -p -q -s --no-print-directory > "$MAKE_DB" 2>/dev/null || true

	# 1a) Library objects: ffbuild/library.mak links each
	#     $(SUBDIR)$(SLIBNAME_WITH_MAJOR) from $(OBJS) $(SHLIBOBJS); make has
	#     those fully expanded per library, so we take the prerequisites of
	#     each real shared library target. This includes arch-specific
	#     ASM/NEON objects and generated version objects - no guessing.
	: > "$UMBRELLA_OBJLIST"
	for LIBNAME in ${FFMPEG_UMBRELLA_LIBS}; do
		LIB_OBJS=$(awk -v target="^lib${LIBNAME}/lib${LIBNAME}\\\\.so\\\\.[0-9]+:$" \
			'$1 ~ target { for (i = 2; i <= NF; i++) if ($i ~ /\.o$/) print $i }' "$MAKE_DB" | sort -u)
		if [ -z "$LIB_OBJS" ]; then
			# Gracefully skip libs that are disabled in ENABLED_CONFIG
			# (e.g. avfilter when --disable-avfilter). Keeps umbrella
			# creation robust when config/unwrap libs drift.
			if echo "$ENABLED_CONFIG" | grep -q -- "--enable-${LIBNAME}"; then
				echo "Error: could not extract object list of lib${LIBNAME} from make database."
				rm -f "$MAKE_DB"
				popd > /dev/null
				return 1
			else
				echo "Skipping $LIBNAME (not enabled in ENABLED_CONFIG)"
				continue
			fi
		fi
		echo "$LIB_OBJS" >> "$UMBRELLA_OBJLIST"
	done

	# 1b) CLI frontend objects: prerequisites of fftools targets
	#     (ffmpeg_g + ffprobe_g) - every object the actual CLIs need:
	#     command parsing, options, transcoding, probing, textformat etc.
	FFTOOLS_OBJS=$(awk '$1 ~ /^ffmpeg(_g)?[^ :]*:$/ { for (i = 2; i <= NF; i++) if ($i ~ /\.o$/) print $i }' "$MAKE_DB" | sort -u)
	if [ -z "$FFTOOLS_OBJS" ]; then
		echo "Error: could not extract fftools object list from make database."
		rm -f "$MAKE_DB"
		popd > /dev/null
		return 1
	fi
	FFPROBE_OBJS=$(awk '$1 ~ /^ffprobe(_g)?[^ :]*:$/ { for (i = 2; i <= NF; i++) if ($i ~ /\.o$/) print $i }' "$MAKE_DB" | sort -u)
	if [ -z "$FFPROBE_OBJS" ]; then
		echo "Error: could not extract ffprobe object list from make database."
		rm -f "$MAKE_DB"
		popd > /dev/null
		return 1
	fi
	case "$FFTOOLS_OBJS" in
		*fftools/cmdutils.o*|*fftools/opt_common.o*) ;;
		*)
			echo "Error: fftools object list looks incomplete (missing cmdutils.o/opt_common.o)."
			popd > /dev/null
			return 1
			;;
	esac
	case "$FFPROBE_OBJS" in
		*fftools/ffprobe.o*) ;;
		*)
			echo "Error: ffprobe object list looks incomplete (missing ffprobe.o)."
			popd > /dev/null
			return 1
			;;
	esac
	echo "$FFTOOLS_OBJS" >> "$UMBRELLA_OBJLIST"
	echo "$FFPROBE_OBJS" >> "$UMBRELLA_OBJLIST"
	rm -f "$MAKE_DB"

	sort -u "$UMBRELLA_OBJLIST" -o "$UMBRELLA_OBJLIST"
	OBJ_COUNT=$(wc -l < "$UMBRELLA_OBJLIST")
	if [ "$OBJ_COUNT" -lt 120 ]; then
		echo "Error: implausibly few objects ($OBJ_COUNT) collected; refusing to link."
		popd > /dev/null
		return 1
	fi
	echo "Compiling only the ${OBJ_COUNT} objects needed by the umbrella library..."
	# CFLAGS-ffmpeg / CFLAGS-ffprobe rename CLI entry points ('main') without any
	# source patch; scoped by FFmpeg's own Makefile to the fftools objects only (16KB safe).
	# -Wno-macro-redefined suppresses duplicate -Dmain for shared textformat objects
	# (built for both ffmpeg and ffprobe, harmless). -O3 -flto=thin for max performance with lower memory (ThinLTO ~95% of full LTO).
	if ! make -j"$JOBS" CFLAGS-ffmpeg="-Dmain=ffmpeg_main -O3 -DNDEBUG -flto=thin -Wno-missing-prototypes -Wno-macro-redefined" CFLAGS-ffprobe="-Dmain=ffprobe_main -O3 -DNDEBUG -flto=thin -Wno-missing-prototypes -Wno-macro-redefined" $(cat "$UMBRELLA_OBJLIST"); then
		echo "Error: failed to compile umbrella library objects."
		popd > /dev/null
		return 1
	fi

	while IFS= read -r OBJ; do
		if [ ! -f "$OBJ" ]; then
			echo "Error: object file '$OBJ' listed by FFmpeg's build system does not exist."
			popd > /dev/null
			return 1
		fi
	done < "$UMBRELLA_OBJLIST"

	# 1c) FFShell wrapper object
	echo "Compiling FFShell wrapper API..."
	if ! $CLANG -c "${SCRIPT_DIR}/ffshell/src/ffshell_ffmpeg.c" \
		-o "$FFSHELL_WRAPPER_OBJ" \
		-fpic -O3 -DNDEBUG -flto=thin -DANDROID -D_FORTIFY_SOURCE=2 -Werror=format-security \
		-I"${SCRIPT_DIR}/ffshell/include" \
		-I"$FFMPEG_SOURCE_DIR"; then
		echo "Error: failed to compile the FFShell wrapper."
		popd > /dev/null
		return 1
	fi
	echo "$FFSHELL_WRAPPER_OBJ" >> "$UMBRELLA_OBJLIST"

	tr '\n' ' ' < "$UMBRELLA_OBJLIST" > "$UMBRELLA_RSP"
	echo >> "$UMBRELLA_RSP"
	LINK_INPUTS="@$UMBRELLA_RSP"

	### 2) Export list ########################################################
	# Scoping-only version script: exports the public FFmpeg API and the five
	# stable FFShell entry points; keeps everything else (ff_*, dav1d_*,
	# ffshell_cli_main, ...) local. Adds no symbol versions.
	{
		echo "{"
		echo "	global:"
		echo "		av*;"
		echo "		sws_*;"
		echo "		swscale_*;"
		echo "		swr_*;"
		echo "		swresample_*;"
		for SYM in ${FFSHELL_API_SYMBOLS}; do
			echo "		${SYM};"
		done
		echo "	local:"
		echo "		*;"
		echo "};"
	} > "$UMBRELLA_VER"

	### 3) System/external dependencies #######################################
	SYS_LIBS=""
	for VAR in EXTRALIBS EXTRALIBS-avutil EXTRALIBS-avcodec EXTRALIBS-avformat EXTRALIBS-avfilter EXTRALIBS-avdevice EXTRALIBS-swresample EXTRALIBS-swscale; do
		SYS_LIBS="$SYS_LIBS $(sed -n "s/^${VAR}=//p" ffbuild/config.mak)"
	done
	# Generic: any external static lib installed to PREFIX/lib/pkgconfig/*.pc
	# contributes its Libs.private to the umbrella link (dav1d, x264, x265, vpx, opus, etc.)
	if [ -d "${PREFIX}/lib/pkgconfig" ]; then
		for pc in "${PREFIX}/lib/pkgconfig/"*.pc; do
			[ -f "$pc" ] || continue
			# Add Libs.private (e.g. -ldav1d, -lx264) if not already via EXTRALIBS
			priv=$(sed -n 's/^Libs\.private://p' "$pc")
			if [ -n "$priv" ]; then
				SYS_LIBS="$SYS_LIBS $priv"
			fi
		done
	fi
	# Fallback for libs without pc or with bare .a (e.g. x264 if pc missing)
	for lib in dav1d x264 x265 vpx opus mp3lame aom freetype fribidi harfbuzz ass fdk-aac ogg vorbis webp svtav1 jxl soxr rubberband vidstab xvid; do
		a_path="${PREFIX}/lib/lib${lib}.a"
		# mp3lame is libmp3lame.a
		if [ "$lib" = "mp3lame" ]; then a_path="${PREFIX}/lib/libmp3lame.a"; fi
		if [ "$lib" = "freetype" ]; then a_path="${PREFIX}/lib/libfreetype.a"; fi
		if [ "$lib" = "fribidi" ]; then a_path="${PREFIX}/lib/libfribidi.a"; fi
		if [ "$lib" = "harfbuzz" ]; then a_path="${PREFIX}/lib/libharfbuzz.a"; fi
		if [ "$lib" = "fdk-aac" ]; then a_path="${PREFIX}/lib/libfdk-aac.a"; fi
		if [ -f "$a_path" ] && ! echo "$SYS_LIBS" | grep -q "$lib"; then
			# Convert lib name to -l flag (strip lib prefix, handle dash)
			flag="-l${lib}"
			if [ "$lib" = "fdk-aac" ]; then flag="-lfdk-aac"; fi
			if [ "$lib" = "mp3lame" ]; then flag="-lmp3lame"; fi
			SYS_LIBS="$SYS_LIBS $flag"
		fi
	done
	UNIQ_LIBS=""
	for TOK in $SYS_LIBS; do
		case "$TOK" in
			-lavutil|-lavcodec|-lavformat|-lavfilter|-lavdevice|-lpostproc|-lswscale|-lswresample)
				;;
			*)
				case " $UNIQ_LIBS " in
					*" $TOK "*) ;;
					*) UNIQ_LIBS="$UNIQ_LIBS $TOK" ;;
				esac
				;;
		esac
	done

	### 4) Final link #########################################################
	# Same NDK clang, same 16 KB page-size and hardening flags as the normal
	# per-library shared links. --allow-multiple-definition is required
	# because FFmpeg deliberately duplicates a handful of helper objects into
	# every shared library (SHLIBOBJS such as log2_tab.o); all copies are
	# identical compilations, and taking the first one mirrors what happens
	# when a static archive member is selected once.
	LINK_ARGS="\
-shared \
-flto=thin \
-Wl,-soname,${FFMPEG_UMBRELLA_NAME} \
-Wl,-z,max-page-size=16384 \
-Wl,-z,common-page-size=16384 \
-Wl,--build-id=sha1 \
-Wl,--no-rosegment \
-Wl,--no-undefined-version \
-Wl,--fatal-warnings \
-Wl,--no-undefined \
-Wl,--allow-multiple-definition \
-Wl,-z,relro \
-Wl,-z,now \
-Qunused-arguments \
-L$SYSROOT/usr/lib/$TARGET_ARCH-linux-android/$ANDROID_API_LEVEL \
-L$PREFIX/lib \
-o $UMBRELLA_OUT.tmp $LINK_INPUTS $UNIQ_LIBS -Wl,--version-script,$UMBRELLA_VER"

	echo "Linking umbrella library..."
	if ! $CLANG $LINK_ARGS; then
		echo "Error: failed to link ${UMBRELLA_OUT}"
		rm -f "$UMBRELLA_OUT.tmp"
		popd > /dev/null
		return 1
	fi
	mv "${UMBRELLA_OUT}.tmp" "$UMBRELLA_OUT"

	ls -lh "$UMBRELLA_OUT"
	file "$UMBRELLA_OUT" || true

	### 5) Validation #########################################################
	if [ ! -f "$UMBRELLA_OUT" ]; then
		echo "Error: ${UMBRELLA_OUT} was not created."
		popd > /dev/null
		return 1
	fi

	echo "--- file ---"
	FILE_OUTPUT=""
	if command -v file > /dev/null 2>&1; then
		FILE_OUTPUT=$(file "$UMBRELLA_OUT")
		echo "$FILE_OUTPUT"
	else
		echo "'file' utility not available, skipping."
	fi
	case "$FILE_OUTPUT" in
		*shared*object*Android*|*Android*shared*object*) ;;
		*shared*object*)
			echo "Warning: 'file' did not report Android tag (output: $FILE_OUTPUT) - relying on readelf for Android validation (16KB, DYN, SONAME)."
			;;
		"")
			echo "Warning: could not classify ELF with 'file'; relying on readelf checks."
			;;
		*)
			echo "Error: '${UMBRELLA_OUT}' is not a shared object: $FILE_OUTPUT"
			popd > /dev/null
			return 1
			;;
	esac

	echo "--- readelf -h ---"
	"$LLVM_READELF" -h "$UMBRELLA_OUT" || { popd > /dev/null; return 1; }
	if ! "$LLVM_READELF" -h "$UMBRELLA_OUT" | grep -q "Type: *DYN"; then
		echo "Error: ELF type is not DYN (shared object)."
		popd > /dev/null
		return 1
	fi

	echo "--- readelf -l ---"
	"$LLVM_READELF" -lW "$UMBRELLA_OUT" || { popd > /dev/null; return 1; }
	BAD_ALIGN=$("$LLVM_READELF" -lW "$UMBRELLA_OUT" | awk '/^  LOAD/ { print $NF }' | while read -r ALIGN_HEX; do
		ALIGN_HEX="${ALIGN_HEX#0x}"
		if [ $((16#$ALIGN_HEX)) -lt 16384 ]; then
			echo "0x$ALIGN_HEX"
		fi
	done)
	if [ -n "$BAD_ALIGN" ]; then
		echo "Error: PT_LOAD alignment not compatible with 16 KB page size: $BAD_ALIGN"
		popd > /dev/null
		return 1
	fi

	echo "--- readelf -d ---"
	READELF_D_OUTPUT=$("$LLVM_READELF" -d "$UMBRELLA_OUT") || { popd > /dev/null; return 1; }
	echo "$READELF_D_OUTPUT"
	if ! echo "$READELF_D_OUTPUT" | grep '(SONAME)' | grep -q "\[${FFMPEG_UMBRELLA_NAME}\]"; then
		echo "Error: DT_SONAME is not ${FFMPEG_UMBRELLA_NAME}."
		popd > /dev/null
		return 1
	fi
	NEEDED_LIBS=$(echo "$READELF_D_OUTPUT" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p')
	echo "DT_NEEDED entries: ${NEEDED_LIBS:-none}"
	for FORBIDDEN in ${FFMPEG_FORBIDDEN_DEPS}; do
		if echo "$NEEDED_LIBS" | grep -qx "$FORBIDDEN"; then
			echo "Error: umbrella library has forbidden runtime dependency on '$FORBIDDEN'."
			popd > /dev/null
			return 1
		fi
	done

	echo "--- exported symbols ---"
	DYN_SYMS=$("$LLVM_NM" -D --defined-only "$UMBRELLA_OUT" | awk '{ print $NF }')
	# Required public FFmpeg API symbols must be present...
	for REQUIRED_SYM in av_version_info av_frame_alloc avcodec_find_decoder avformat_open_input swr_alloc sws_getContext; do
		if ! echo "$DYN_SYMS" | grep -Eq "^${REQUIRED_SYM}(@.*)?$"; then
			echo "Error: required FFmpeg symbol '${REQUIRED_SYM}' is not exported."
			popd > /dev/null
			return 1
		fi
	done
	# ...and the complete stable FFShell API surface.
	for REQUIRED_SYM in ${FFSHELL_API_SYMBOLS}; do
		if ! echo "$DYN_SYMS" | grep -Eq "^${REQUIRED_SYM}(@.*)?$"; then
			echo "Error: required FFShell API symbol '${REQUIRED_SYM}' is not exported."
			popd > /dev/null
			return 1
		fi
	done
	# Internal integration symbols must stay hidden.
	for INTERNAL_SYM in ffshell_cli_main ffshell_request_cancel ffshell_reset_interrupt_state; do
		if echo "$DYN_SYMS" | grep -Eq "^${INTERNAL_SYM}(@.*)?$"; then
			echo "Error: internal symbol '${INTERNAL_SYM}' must not be exported."
			popd > /dev/null
			return 1
		fi
	done
	echo "$DYN_SYMS" | grep -E "^(av_|sw[sr]|ffshell_ffmpeg)" | head -12
	echo "... ($(echo "$DYN_SYMS" | wc -l) dynamic symbols total)"

	### 6) Install development headers ########################################
	if ! make -j"$JOBS" install-headers > /dev/null; then
		echo "Error: failed to install FFmpeg development headers."
		popd > /dev/null
		return 1
	fi

	### 7) Strip ONLY the final umbrella library ##############################
	if ! "$LLVM_STRIP" --strip-unneeded "$UMBRELLA_OUT"; then
		echo "Error: failed to strip ${UMBRELLA_OUT}."
		popd > /dev/null
		return 1
	fi
	if ! "$LLVM_READELF" -h "$UMBRELLA_OUT" | grep -q "Type: *DYN"; then
		echo "Error: stripped ${UMBRELLA_OUT} is not a valid shared object."
		popd > /dev/null
		return 1
	fi

	### 8) Final output contains only the umbrella library + headers ##########
	rm -f "${PREFIX}/lib/libavcodec.so"* \
	      "${PREFIX}/lib/libavformat.so"* \
	      "${PREFIX}/lib/libavutil.so"* \
	      "${PREFIX}/lib/libswscale.so"* \
	      "${PREFIX}/lib/libswresample.so"*
	rm -f "${PREFIX}/lib/libdav1d.a" "${PREFIX}/lib/libx264.a" "${PREFIX}/lib/libx265.a" "${PREFIX}/lib/libvpx.a" "${PREFIX}/lib/libopus.a" "${PREFIX}/lib/libmp3lame.a" "${PREFIX}/lib/libaom.a" "${PREFIX}/lib/libfreetype.a" "${PREFIX}/lib/libfribidi.a" "${PREFIX}/lib/libharfbuzz.a" "${PREFIX}/lib/libass.a" "${PREFIX}/lib/libfdk-aac.a"
	rm -rf "${PREFIX}/lib/pkgconfig"
	rm -rf "${PREFIX}/bin"
	rm -rf "${PREFIX}/include/dav1d" "${PREFIX}/include/x264" "${PREFIX}/include/x264.h" "${PREFIX}/include/vpx" "${PREFIX}/include/opus" "${PREFIX}/include/lame" "${PREFIX}/include/aom" "${PREFIX}/include/freetype2" "${PREFIX}/include/fribidi" "${PREFIX}/include/harfbuzz" "${PREFIX}/include/ass"
	rm -f "$FFSHELL_WRAPPER_OBJ" \
	      "${UMBRELLA_VER}" "${UMBRELLA_OBJLIST}" "${UMBRELLA_RSP}"

	### 9) Final output (consistent project layout) ##########
	ABI_DIR="$(basename "$PREFIX")"
	# Final consistent location: ${FFMPEG_BUILD_DIR}/${ABI_DIR}/lib/libffmpeg.so + include/
	# (without API-level prefix nesting)

	mkdir -p "${FFMPEG_BUILD_DIR}/${ABI_DIR}/lib"
	cp "$UMBRELLA_OUT" "${FFMPEG_BUILD_DIR}/${ABI_DIR}/lib/${FFMPEG_UMBRELLA_NAME}"

	# Mirror headers to final location (per-ABI)
	mkdir -p "${FFMPEG_BUILD_DIR}/${ABI_DIR}/include/ffshell"
	cp "${SCRIPT_DIR}/ffshell/include/ffshell/ffshell_ffmpeg.h" "${FFMPEG_BUILD_DIR}/${ABI_DIR}/include/ffshell/" 2>/dev/null || true
	if [ -d "${PREFIX}/include" ]; then
		mkdir -p "${FFMPEG_BUILD_DIR}/${ABI_DIR}/include"
		cp -r "${PREFIX}/include"/* "${FFMPEG_BUILD_DIR}/${ABI_DIR}/include/" 2>/dev/null || true
	fi
	if [ ! -d "${FFMPEG_BUILD_DIR}/${ABI_DIR}/include/libavcodec" ] && [ -d "${PREFIX}/include/libavcodec" ]; then
		cp -r "${PREFIX}/include/libavcodec" "${FFMPEG_BUILD_DIR}/${ABI_DIR}/include/" 2>/dev/null || true
	fi
	popd > /dev/null
	echo -e "\e[1;32mUmbrella library created successfully: ${UMBRELLA_OUT} -> ${FFMPEG_BUILD_DIR}/${ABI_DIR}/lib/${FFMPEG_UMBRELLA_NAME}\e[0m"
	return 0
}


configure_ffmpeg(){
   TARGET_ARCH=$1
   TARGET_CPU=$2
   PREFIX=$3
   CROSS_PREFIX=$4
   EXTRA_CFLAGS=$5
   EXTRA_CXXFLAGS=$6
   EXTRA_CONFIG=$7
   
   export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
   CLANG="${CROSS_PREFIX}clang"
   CLANGXX="${CROSS_PREFIX}clang++"
   
   cd "$FFMPEG_SOURCE_DIR"
   ./configure \
   --disable-everything \
   --target-os=android \
   --arch=$TARGET_ARCH \
   --cpu=$TARGET_CPU \
   --pkg-config=pkg-config \
   --enable-cross-compile \
   --cross-prefix="$CROSS_PREFIX" \
   --cc="$CLANG" \
   --cxx="$CLANGXX" \
   --sysroot="$SYSROOT" \
   --prefix="$PREFIX" \
   --extra-cflags="-fpic -DANDROID -fdata-sections -ffunction-sections -funwind-tables -fstack-protector-strong -no-canonical-prefixes -D__BIONIC_NO_PAGE_SIZE_MACRO -D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security $EXTRA_CFLAGS -I$PREFIX/include " \
   --extra-cxxflags="-fpic -DANDROID -fdata-sections -ffunction-sections -funwind-tables -fstack-protector-strong -no-canonical-prefixes -D__BIONIC_NO_PAGE_SIZE_MACRO -D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security -std=c++17 -fexceptions -frtti $EXTRA_CXXFLAGS -I$PREFIX/include " \
   --extra-ldflags=" -Wl,-z,max-page-size=16384 -Wl,--build-id=sha1 -Wl,--no-rosegment -Wl,--no-undefined-version -Wl,--fatal-warnings -Wl,--no-undefined -Qunused-arguments -L$SYSROOT/usr/lib/$TARGET_ARCH-linux-android/$ANDROID_API_LEVEL -L$PREFIX/lib" \
   --extra-libs="-lm" \
   --enable-pic \
   ${ENABLED_CONFIG} \
   ${DISABLED_CONFIG} \
   --ar="$LLVM_AR" \
   --nm="$LLVM_NM" \
   --ranlib="$LLVM_RANLIB" \
   --strip="$LLVM_STRIP" \
   ${EXTRA_CONFIG}
   RET=$?
   if [ $RET -ne 0 ]; then
       return $RET
   fi

   make clean
   # Umbrella-only: create_umbrella_library() compiles exactly the objects it
   # needs (FFmpeg libs + fftools CLI); per-library .so files and standalone
   # ffmpeg binaries are never generated or installed.
}

echo -e "\e[1;32mBuilding the FFShell FFmpeg runtime for Android...\e[0m"

if ! clean_and_fetch_sources; then
	echo -e "\e[1;31mError: failed to fetch/patch sources. Aborting.\e[0m"
	exit 1
fi

build_single_arch(){
	local ARCH="$1"
	# Isolate source tree for parallel builds
	if [ "${PARALLEL_ABIS:-0}" = "1" ]; then
		local SANDBOX="$SCRIPT_DIR/build-tools/sandbox-$ARCH"
		if [ -d "$SANDBOX/build-src" ]; then
			export SRC_DIR="$SANDBOX/build-src"
			export FFMPEG_SOURCE_DIR="$SRC_DIR/ffmpeg"
		fi
	fi
	cd "$SCRIPT_DIR" || return 1
    case "$ARCH" in
        "armv8-a"|"aarch64"|"arm64-v8a"|"armv8a")
            echo -e "\e[1;32m$ARCH Libraries\e[0m"
            TARGET_ARCH="aarch64"
            TARGET_CPU="armv8-a"
            TARGET_ABI="aarch64"
            PREFIX="${FFMPEG_BUILD_DIR}/$ANDROID_API_LEVEL/arm64-v8a"
            CROSS_PREFIX="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/$TARGET_ABI-linux-android${ANDROID_API_LEVEL}-"
            EXTRA_CFLAGS="-O3 -DNDEBUG -flto=thin -march=$TARGET_CPU -fomit-frame-pointer"
	        EXTRA_CXXFLAGS="-O3 -DNDEBUG -flto=thin -march=$TARGET_CPU -fomit-frame-pointer"
      
            EXTRA_CONFIG="\
	    	      	--enable-asm \
            		--enable-neon "
            ;;
        "armv7-a"|"armeabi-v7a"|"armv7a")
            echo -e "\e[1;32m$ARCH Libraries\e[0m"
            TARGET_ARCH="arm"
            TARGET_CPU="armv7-a"
            TARGET_ABI="armv7a"
            PREFIX="${FFMPEG_BUILD_DIR}/$ANDROID_API_LEVEL/armeabi-v7a"
            CROSS_PREFIX="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/$TARGET_ABI-linux-androideabi${ANDROID_API_LEVEL}-"
            EXTRA_CFLAGS="-O3 -DNDEBUG -flto=thin -march=$TARGET_CPU -mfpu=neon -fomit-frame-pointer"
	        EXTRA_CXXFLAGS="-O3 -DNDEBUG -flto=thin -march=$TARGET_CPU -mfpu=neon -fomit-frame-pointer"
     
            EXTRA_CONFIG="\
            		--disable-armv5te \
            		--disable-armv6 \
            		--disable-armv6t2 \
	      			--enable-asm \
            		--enable-neon "
            ;;
            
        "x86-64"|"x86_64")
            echo -e "\e[1;32m$ARCH Libraries\e[0m"
            TARGET_ARCH="x86_64"
            TARGET_CPU="x86-64"
            TARGET_ABI="x86_64"
            PREFIX="${FFMPEG_BUILD_DIR}/$ANDROID_API_LEVEL/x86_64"
            CROSS_PREFIX="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/$TARGET_ABI-linux-android${ANDROID_API_LEVEL}-"
            EXTRA_CFLAGS="-O3 -DNDEBUG -flto=thin -march=$TARGET_CPU -fomit-frame-pointer"
	        EXTRA_CXXFLAGS="-O3 -DNDEBUG -flto=thin -march=$TARGET_CPU -fomit-frame-pointer"
             		
            EXTRA_CONFIG="\
	    	      	--enable-asm "
            ;;
        "x86"|"i686")
            echo -e "\e[1;32m$ARCH Libraries\e[0m"
            TARGET_ARCH="i686"
            TARGET_CPU="i686"
            TARGET_ABI="i686"
            PREFIX="${FFMPEG_BUILD_DIR}/$ANDROID_API_LEVEL/x86"
            CROSS_PREFIX="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/$TARGET_ABI-linux-android${ANDROID_API_LEVEL}-"
            if [ "$ENABLE_X86_ASM" = "1" ]; then
                echo -e "\e[1;33mEmulator asm enabled (ENABLE_X86_ASM=1) – x86 will use asm with per-arch non-LTO (larger, emulator-only)\e[0m"
                EXTRA_CFLAGS="-O3 -DNDEBUG -march=$TARGET_CPU -mstackrealign -msse2 -mfpmath=sse -fomit-frame-pointer"
                EXTRA_CXXFLAGS="-O3 -DNDEBUG -march=$TARGET_CPU -mstackrealign -msse2 -mfpmath=sse -fomit-frame-pointer"
                EXTRA_CONFIG="\
            		 --enable-asm "
            else
                EXTRA_CFLAGS="-O3 -DNDEBUG -flto=thin -march=$TARGET_CPU -fomit-frame-pointer"
                EXTRA_CXXFLAGS="-O3 -DNDEBUG -flto=thin -march=$TARGET_CPU -fomit-frame-pointer"
                EXTRA_CONFIG="\
            		 --disable-asm "
            fi
            ;;
           * )
            echo "Unknown architecture: $ARCH"
            return 1
            ;;
    esac
	maybeBuildLibx264 "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CROSS_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG"
	if [ $? -ne 0 ]; then
		echo -e "\e[1;31mError compiling x264 for $ARCH. Aborting.\e[0m"
  		return 1
	fi
	maybeBuildLibdav1d "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CROSS_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG"
	if [ $? -ne 0 ]; then
		echo -e "\e[1;31mError compiling dav1d for $ARCH. Aborting.\e[0m"
  		return 1
	fi
	for ext in x265 vpx opus mp3lame aom freetype fribidi harfbuzz ass fdk-aac ogg vorbis webp svtav1 jxl soxr rubberband vidstab xvid; do
		maybeBuildExternal "$ext" "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CROSS_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG"
		if [ $? -ne 0 ]; then
			echo -e "\e[1;31mError compiling $ext for $ARCH. Aborting.\e[0m"
			return 1
		fi
	done
    configure_ffmpeg "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CROSS_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG"
	if [ $? -ne 0 ]; then
		echo -e "\e[1;31mError configuring FFmpeg for $ARCH. Aborting.\e[0m"
  		return 1
	fi
	create_umbrella_library "$PREFIX" "$CROSS_PREFIX" "$TARGET_ARCH"
	if [ $? -ne 0 ]; then
		echo -e "\e[1;31mError creating umbrella libffmpeg.so for $ARCH. Aborting.\e[0m"
		return 1
	fi
}

# Auto-detect parallel capability (override with PARALLEL_ABIS=0/1, FORCE_PARALLEL=1)
if [ -z "${PARALLEL_ABIS:-}" ]; then
	if [ "${#ARCH_LIST[@]}" -gt 1 ]; then
		MEM_KB=$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
		if [ "$MEM_KB" -eq 0 ]; then
			MEM_KB=$(free -k 2>/dev/null | awk '/^Mem:/ {print $7}' 2>/dev/null || echo 0)
		fi
		if [ "$NPROC" -ge 4 ] && [ "$MEM_KB" -ge 2621440 ]; then
			PARALLEL_ABIS=1
		else
			PARALLEL_ABIS=0
		fi
	else
		PARALLEL_ABIS=0
	fi
fi
if [ "${FORCE_PARALLEL:-0}" = "1" ]; then
	PARALLEL_ABIS=1
fi

# Ensure log dir exists
mkdir -p "${FFMPEG_BUILD_DIR}/logs" 2>/dev/null || true
# Cleanup sandboxes on exit (do not touch downloaded NDK)
trap 'rm -rf "$SCRIPT_DIR"/build-tools/sandbox-* 2>/dev/null || true' EXIT

if [ "$PARALLEL_ABIS" = "1" ]; then
	echo -e "\e[1;32mParallel ABI build enabled (JOBS=$JOBS, NPROC=$NPROC, ABIs=${#ARCH_LIST[@]})\e[0m"
	for ARCH in "${ARCH_LIST[@]}"; do
		SANDBOX="$SCRIPT_DIR/build-tools/sandbox-$ARCH"
		rm -rf "$SANDBOX"
		mkdir -p "$SANDBOX"
		cp -a "$SCRIPT_DIR/build-src" "$SANDBOX/" 2>/dev/null || true
	done
	declare -A PID_MAP
	FAIL=0
	for ARCH in "${ARCH_LIST[@]}"; do
		build_single_arch "$ARCH" > "${FFMPEG_BUILD_DIR}/logs/${ARCH}.log" 2>&1 &
		PID_MAP["$ARCH"]=$!
		echo "  -> $ARCH pid ${PID_MAP[$ARCH]} (log ${FFMPEG_BUILD_DIR}/logs/${ARCH}.log)"
	done
	for ARCH in "${ARCH_LIST[@]}"; do
		PID=${PID_MAP["$ARCH"]}
		if ! wait "$PID"; then
			echo -e "\e[1;31mFailed $ARCH (log ${FFMPEG_BUILD_DIR}/logs/${ARCH}.log)\e[0m"
			tail -80 "${FFMPEG_BUILD_DIR}/logs/${ARCH}.log" 2>/dev/null || true
			FAIL=1
		else
			echo -e "\e[1;32mBuilt $ARCH\e[0m"
		fi
	done
	if [ "$FAIL" -ne 0 ]; then
		echo -e "\e[1;31mOne or more ABIs failed\e[0m"
		exit 1
	fi
else
	echo -e "\e[1;32mSerial ABI build (JOBS=$JOBS, NPROC=$NPROC)\e[0m"
	for ARCH in "${ARCH_LIST[@]}"; do
		if ! build_single_arch "$ARCH"; then
			exit 1
		fi
	done
fi

echo -e "\e[1;32mFFShell runtime built: ${FFMPEG_BUILD_DIR}/{arm64-v8a,armeabi-v7a,x86,x86_64}/lib/libffmpeg.so (+ include/)\e[0m"
