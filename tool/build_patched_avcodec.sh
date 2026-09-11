#!/bin/bash
set -euo pipefail

# Build patched Avcodec.framework with Blu-ray PGS subtitle support (hdmv_pgs_subtitle / pgssub)
# for both arm64 and x86_64 macOS architectures.

BUILD_DIR="/tmp/ffmpeg_avcodec_build"
FFMPEG_VERSION="6.0"
FFMPEG_TAR="ffmpeg-${FFMPEG_VERSION}.tar.xz"
FFMPEG_URL="https://ffmpeg.org/releases/${FFMPEG_TAR}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_XCFRAMEWORK="${REPO_ROOT}/macos/Frameworks/Avcodec.xcframework"

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

if [ ! -f "${FFMPEG_TAR}" ]; then
  echo "Downloading FFmpeg ${FFMPEG_VERSION}..."
  curl -LO "${FFMPEG_URL}"
fi

if [ ! -d "ffmpeg-${FFMPEG_VERSION}" ]; then
  echo "Extracting FFmpeg ${FFMPEG_VERSION}..."
  tar -xf "${FFMPEG_TAR}"
fi

COMMON_FLAGS=(
  --disable-autodetect
  --disable-all
  --disable-x86asm
  --disable-runtime-cpudetect
  --disable-debug
  --disable-static
  --enable-small
  --enable-optimizations
  --enable-shared
  --enable-network
  --enable-pthreads
  --enable-pic
  --enable-version3
  --enable-safe-bitstream-reader
  --enable-stripping
  --enable-avcodec
  --enable-avformat
  --enable-swresample
  --enable-swscale
  --enable-avfilter
  --enable-zlib
  --enable-audiotoolbox
  --enable-videotoolbox

  # Subtitles (including Blu-ray PGS and DVD VobSub)
  --enable-decoder=pgssub
  --enable-decoder=dvdsub
  --enable-decoder=dvbsub
  --enable-decoder=ass
  --enable-decoder=ssa
  --enable-decoder=srt
  --enable-decoder=stl
  --enable-decoder=subrip
  --enable-decoder=subviewer
  --enable-decoder=subviewer1
  --enable-decoder=text
  --enable-decoder=vplayer
  --enable-decoder=webvtt
  --enable-decoder=movtext

  # Audio decoders
  --enable-decoder=aac*
  --enable-decoder=ac3
  --enable-decoder=alac
  --enable-decoder=als
  --enable-decoder=ape
  --enable-decoder=atrac*
  --enable-decoder=eac3
  --enable-decoder=flac
  --enable-decoder=gsm*
  --enable-decoder=mp1*
  --enable-decoder=mp2*
  --enable-decoder=mp3*
  --enable-decoder=mpc*
  --enable-decoder=opus
  --enable-decoder=ra*
  --enable-decoder=ralf
  --enable-decoder=shorten
  --enable-decoder=tak
  --enable-decoder=tta
  --enable-decoder=vorbis
  --enable-decoder=wavpack
  --enable-decoder=wma*
  --enable-decoder=pcm*
  --enable-decoder=dsd*
  --enable-decoder=dca

  # Video decoders
  --enable-decoder=flv
  --enable-decoder=h263
  --enable-decoder=h263i
  --enable-decoder=h263p
  --enable-decoder=h264
  --enable-decoder=mpeg1video
  --enable-decoder=mpeg2video
  --enable-decoder=mpeg4
  --enable-decoder=vp6
  --enable-decoder=vp6a
  --enable-decoder=vp6f
  --enable-decoder=vp8
  --enable-decoder=vp9
  --enable-decoder=hevc
  --enable-decoder=av1
  --enable-decoder=theora
  --enable-decoder=msmpeg4v1
  --enable-decoder=msmpeg4v2
  --enable-decoder=msmpeg4v3
  --enable-decoder=mjpeg
  --enable-decoder=wmv1
  --enable-decoder=wmv2
  --enable-decoder=wmv3
  --enable-decoder=wmv3image

  # Parsers
  --enable-parser=aac*
  --enable-parser=ac3
  --enable-parser=cook
  --enable-parser=dca
  --enable-parser=flac
  --enable-parser=gsm
  --enable-parser=mpegaudio
  --enable-parser=tak
  --enable-parser=vorbis
  --enable-parser=h263
  --enable-parser=h264
  --enable-parser=hevc
  --enable-parser=mpeg4video
  --enable-parser=mpegvideo

  # Hardware acceleration
  --enable-hwaccel=h263_videotoolbox
  --enable-hwaccel=h264_videotoolbox
  --enable-hwaccel=hevc_videotoolbox
  --enable-hwaccel=mpeg1_videotoolbox
  --enable-hwaccel=mpeg2_videotoolbox
  --enable-hwaccel=mpeg4_videotoolbox
  --enable-hwaccel=vp9_videotoolbox
)

NCPU=$(sysctl -n hw.ncpu || echo 4)

for ARCH in arm64 x86_64; do
  echo "=== Building FFmpeg Avcodec for ${ARCH} ==="
  BUILD_ARCH_DIR="${BUILD_DIR}/build_${ARCH}"
  rm -rf "${BUILD_ARCH_DIR}"
  mkdir -p "${BUILD_ARCH_DIR}"
  cd "${BUILD_ARCH_DIR}"

  ARCH_FLAGS=()
  if [ "${ARCH}" = "arm64" ]; then
    ARCH_FLAGS+=(--arch=aarch64 --enable-neon)
  else
    ARCH_FLAGS+=(--arch=x86_64)
  fi

  "${BUILD_DIR}/ffmpeg-${FFMPEG_VERSION}/configure" \
    --prefix="${BUILD_ARCH_DIR}/install" \
    --cc=clang \
    --cxx=clang++ \
    --extra-cflags="-arch ${ARCH} -mmacosx-version-min=10.9" \
    --extra-ldflags="-arch ${ARCH} -mmacosx-version-min=10.9" \
    "${COMMON_FLAGS[@]}" \
    "${ARCH_FLAGS[@]}"

  make -j"${NCPU}"
done

echo "=== Packaging Universal Avcodec.xcframework ==="
UNIVERSAL_DIR="${BUILD_DIR}/universal"
rm -rf "${UNIVERSAL_DIR}"
mkdir -p "${UNIVERSAL_DIR}"

# Combine arm64 and x86_64 slices
lipo -create \
  "${BUILD_DIR}/build_arm64/libavcodec/libavcodec.60.dylib" \
  "${BUILD_DIR}/build_x86_64/libavcodec/libavcodec.60.dylib" \
  -output "${UNIVERSAL_DIR}/Avcodec"

# Adjust install name and @rpath dependencies
install_name_tool -id "@rpath/Avcodec.framework/Versions/A/Avcodec" "${UNIVERSAL_DIR}/Avcodec"

# Update dependent lib references to @rpath framework structure
for dep in $(otool -L "${UNIVERSAL_DIR}/Avcodec" | grep -E "libavutil|libswresample" | awk '{print $1}'); do
  if [[ "$dep" == *"libavutil"* ]]; then
    install_name_tool -change "$dep" "@rpath/Avutil.framework/Versions/A/Avutil" "${UNIVERSAL_DIR}/Avcodec"
  elif [[ "$dep" == *"libswresample"* ]]; then
    install_name_tool -change "$dep" "@rpath/Swresample.framework/Versions/A/Swresample" "${UNIVERSAL_DIR}/Avcodec"
  fi
done

# Assemble Framework & XCFramework
FRAMEWORK_DIR="${OUTPUT_XCFRAMEWORK}/macos-arm64_x86_64/Avcodec.framework"
rm -rf "${OUTPUT_XCFRAMEWORK}"
mkdir -p "${FRAMEWORK_DIR}/Versions/A/Resources"

cp "${UNIVERSAL_DIR}/Avcodec" "${FRAMEWORK_DIR}/Versions/A/Avcodec"

# Copy Info.plist from pub cache framework if present, or create standard Info.plist
PUB_CACHE_AVCODEC="/Users/shubham/.pub-cache/hosted/pub.dev/media_kit_libs_macos_video-1.1.4/macos/Frameworks/Avcodec.xcframework"
if [ -f "${PUB_CACHE_AVCODEC}/Info.plist" ]; then
  cp "${PUB_CACHE_AVCODEC}/Info.plist" "${OUTPUT_XCFRAMEWORK}/Info.plist"
fi
if [ -f "${PUB_CACHE_AVCODEC}/macos-arm64_x86_64/Avcodec.framework/Versions/A/Resources/Info.plist" ]; then
  cp "${PUB_CACHE_AVCODEC}/macos-arm64_x86_64/Avcodec.framework/Versions/A/Resources/Info.plist" "${FRAMEWORK_DIR}/Versions/A/Resources/Info.plist"
fi

cd "${FRAMEWORK_DIR}/Versions"
ln -sf A Current
cd "${FRAMEWORK_DIR}"
ln -sf Versions/Current/Avcodec Avcodec
ln -sf Versions/Current/Resources Resources

echo "=== Verification ==="
lipo -info "${FRAMEWORK_DIR}/Avcodec"
otool -L "${FRAMEWORK_DIR}/Avcodec"
strings "${FRAMEWORK_DIR}/Avcodec" | grep -E "pgssub|dvdsub" | head -n 5

echo "=== Successfully built patched Avcodec.xcframework at: ${OUTPUT_XCFRAMEWORK} ==="
