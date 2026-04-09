#!/usr/bin/env bash
#
# Reproducible audio fixture generator for JamBoxTests.
#
# Produces six tiny test files (each < 100 KB):
#
#   tone.mp3           1s MP3 (CBR 64k), ID3v2 tags
#   tone.m4a           1s AAC / M4A, iTunes-style tags
#   tone-16.flac       1s 16-bit FLAC, Vorbis Comments
#   tone-24.flac       1s 24-bit FLAC, Vorbis Comments  (card 0020 regression)
#   tone.wav           1s 16-bit LPCM WAV
#   tone.aiff          1s 16-bit LPCM AIFF
#
# Every file contains a 440 Hz sine tone at -20 dBFS, mono, 44.1 kHz,
# exactly 1.000 seconds long unless the container forces otherwise.
# Tags are fully deterministic so that unit tests in card 0006b can
# assert against known values.
#
# Requirements: ffmpeg (for mp3/m4a/wav/aiff/flac16), flac (for flac24
# from a wav source), afconvert is NOT required at present but is
# listed in the card for future extension.
#
# Usage:
#   cd JamBoxTests/Fixtures
#   ./generate.sh
#
# The script is idempotent — running it twice produces functionally
# identical fixtures (same sample rate, bit depth, duration, tags).
# Binary equality is NOT guaranteed (ffmpeg writes encoder version
# strings into some headers) but durations, formats, and tags are.

set -euo pipefail

FIX_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$FIX_DIR"

# Fixed tag values. Anything that changes here MUST be updated in the
# unit tests that rely on them (0006b).
TITLE="JamBox Test Tone"
ARTIST="JamBox Test Suite"
ALBUM="Fixture Album"
TRACK="3"
GENRE="Test"
YEAR="2026"

DUR="1.0"
FREQ="440"
RATE="44100"
CH="1"
# -20 dBFS so the sine never clips any codec.
GAIN="0.1"

# Clean previous outputs to keep the process reproducible.
rm -f tone.mp3 tone.m4a tone-16.flac tone-24.flac tone.wav tone.aiff

# Require deps
need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
need ffmpeg
need ffprobe
need flac

# Common ffmpeg sine source.
SINE="sine=frequency=${FREQ}:sample_rate=${RATE}:duration=${DUR}"

echo "[generate.sh] writing tone.wav"
ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "${SINE}" \
    -ac "${CH}" -ar "${RATE}" \
    -af "volume=${GAIN}" \
    -c:a pcm_s16le \
    -map_metadata -1 \
    tone.wav

echo "[generate.sh] writing tone.aiff"
ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "${SINE}" \
    -ac "${CH}" -ar "${RATE}" \
    -af "volume=${GAIN}" \
    -c:a pcm_s16be \
    -map_metadata -1 \
    -write_id3v2 0 \
    tone.aiff

echo "[generate.sh] writing tone.mp3"
ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "${SINE}" \
    -ac "${CH}" -ar "${RATE}" \
    -af "volume=${GAIN}" \
    -c:a libmp3lame -b:a 64k \
    -map_metadata -1 \
    -id3v2_version 3 \
    -write_xing 0 \
    -metadata title="${TITLE}" \
    -metadata artist="${ARTIST}" \
    -metadata album="${ALBUM}" \
    -metadata track="${TRACK}" \
    -metadata genre="${GENRE}" \
    -metadata date="${YEAR}" \
    tone.mp3

echo "[generate.sh] writing tone.m4a"
ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "${SINE}" \
    -ac "${CH}" -ar "${RATE}" \
    -af "volume=${GAIN}" \
    -c:a aac -b:a 64k \
    -map_metadata -1 \
    -metadata title="${TITLE}" \
    -metadata artist="${ARTIST}" \
    -metadata album="${ALBUM}" \
    -metadata track="${TRACK}" \
    -metadata genre="${GENRE}" \
    -metadata date="${YEAR}" \
    tone.m4a

echo "[generate.sh] writing tone-16.flac"
ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "${SINE}" \
    -ac "${CH}" -ar "${RATE}" \
    -af "volume=${GAIN}" \
    -c:a flac -sample_fmt s16 \
    -map_metadata -1 \
    -metadata title="${TITLE}" \
    -metadata artist="${ARTIST}" \
    -metadata album="${ALBUM}" \
    -metadata tracknumber="${TRACK}" \
    -metadata genre="${GENRE}" \
    -metadata date="${YEAR}" \
    tone-16.flac

# 24-bit FLAC: card 0020 regression coverage.
# ffmpeg's flac encoder supports s32 with `-bits_per_raw_sample 24`,
# but the simplest deterministic path is to produce a 24-bit WAV first,
# then encode with `flac` CLI which honors the source bit depth exactly.
echo "[generate.sh] writing tone-24.flac (via 24-bit WAV intermediate)"
ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "${SINE}" \
    -ac "${CH}" -ar "${RATE}" \
    -af "volume=${GAIN}" \
    -c:a pcm_s24le \
    -map_metadata -1 \
    _tone-24.wav

flac --silent --force \
    --tag=TITLE="${TITLE}" \
    --tag=ARTIST="${ARTIST}" \
    --tag=ALBUM="${ALBUM}" \
    --tag=TRACKNUMBER="${TRACK}" \
    --tag=GENRE="${GENRE}" \
    --tag=DATE="${YEAR}" \
    -o tone-24.flac \
    _tone-24.wav
rm -f _tone-24.wav

# Verify 24-bit FLAC actually is 24-bit — the whole point of the fixture.
BITS="$(ffprobe -hide_banner -loglevel error -select_streams a:0 \
    -show_entries stream=bits_per_raw_sample -of default=nw=1:nk=1 tone-24.flac)"
if [[ "${BITS}" != "24" ]]; then
    echo "[generate.sh] ERROR: tone-24.flac is ${BITS}-bit, expected 24" >&2
    exit 2
fi

# Verify size budget (each under 100 KB).
for f in tone.mp3 tone.m4a tone-16.flac tone-24.flac tone.wav tone.aiff; do
    sz=$(stat -f%z "$f")
    if (( sz > 100 * 1024 )); then
        echo "[generate.sh] ERROR: $f is ${sz} bytes (> 100 KB)" >&2
        exit 3
    fi
    printf "  %-16s %6d bytes\n" "$f" "$sz"
done

echo "[generate.sh] done."
