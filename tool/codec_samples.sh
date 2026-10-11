#!/usr/bin/env bash
# Generates the codec conformance sample set: one 4 s clip per codec we promise
# to play (docs/codec-support.md). Needs ffmpeg on PATH; encoders it lacks are
# skipped with a note, so a thin ffmpeg gives a thinner (not broken) set.
#
#   tool/codec_samples.sh <out-dir>
set -uo pipefail
out="${1:?usage: codec_samples.sh <out-dir>}"
mkdir -p "$out"
src=(-f lavfi -i "testsrc2=size=640x360:rate=24:duration=4" -f lavfi -i "sine=frequency=440:duration=4:sample_rate=48000")
have() { ffmpeg -hide_banner -encoders 2>/dev/null | grep -qE " $1 "; }

gen() { # <file> <video-enc> <audio-enc> [extra ffmpeg args...]
  local file=$1 v=$2 a=$3; shift 3
  for enc in $v $a; do [ "$enc" = none ] || have "$enc" || { echo "skip  $file (no $enc encoder)"; return; }; done
  local args=(-hide_banner -loglevel error -y "${src[@]}")
  [ "$v" = none ] && args+=(-vn) || args+=(-c:v "$v")
  [ "$a" = none ] && args+=(-an) || args+=(-c:a "$a" -ac 2)
  ffmpeg "${args[@]}" "$@" "$out/$file" && echo "ok    $file"
}

gen h264_aac.mp4            libx264     aac        -pix_fmt yuv420p
gen hevc10_aac.mkv          libx265     aac        -pix_fmt yuv420p10le
gen vp9_opus.webm           libvpx-vp9  libopus
gen av1_opus.mkv            libaom-av1  libopus    -cpu-used 8
gen mpeg2_ac3.ts            mpeg2video  ac3
gen mpeg4_mp3.avi           mpeg4       libmp3lame
gen wmv2_wma.wmv            wmv2        wmav2
gen prores_pcm.mov          prores_ks   pcm_s16le
gen dnxhd_pcm.mxf           dnxhd       pcm_s16le  -s 1920x1080 -b:v 36M -pix_fmt yuv422p
gen ffv1_pcm.avi            ffv1        pcm_s16le
gen huffyuv_pcm.avi         huffyuv     pcm_s16le
gen utvideo_pcm.avi         utvideo     pcm_s16le
gen cinepak_pcm.mov         cinepak     pcm_s16le
gen jpeg2000_pcm.mkv        jpeg2000    pcm_s16le
gen truehd_only.mkv         libx264     truehd     -strict -2 -pix_fmt yuv420p
gen eac3_only.mkv           libx264     eac3       -pix_fmt yuv420p
gen dts_only.mkv            libx264     dca        -strict -2 -pix_fmt yuv420p
gen alac_only.mov           libx264     alac       -pix_fmt yuv420p
gen vorbis_only.mkv         libx264     vorbis     -strict -2 -pix_fmt yuv420p

# Known gap, kept visible rather than hidden: mpv 0.36's own Matroska demuxer
# cannot open FFV1 (mpv 0.41, i.e. Windows, can), so this one differs by
# platform. The probe reports it but does not fail the run on it.
gen known_gap_ffv1.mkv      ffv1        pcm_s16le

# TrueHD beside AC3: mpv auto-picks TrueHD, so a build without it plays silence.
if have truehd && have ac3 && have libx264; then
  ffmpeg -hide_banner -loglevel error -y "${src[@]}" -map 0:v -map 1:a -map 1:a \
    -c:v libx264 -pix_fmt yuv420p -c:a:0 truehd -strict -2 -c:a:1 ac3 "$out/truehd_plus_ac3.mkv" && echo "ok    truehd_plus_ac3.mkv"
fi
