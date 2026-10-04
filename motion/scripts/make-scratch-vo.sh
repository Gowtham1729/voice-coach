#!/usr/bin/env bash
# Scratch timed read for animatic pacing. Not final VO.
# Re-run from anywhere: motion/scripts/make-scratch-vo.sh
set -euo pipefail

RATE_WPM=168
VOICE="Samantha"

# Samantha (en_US) misreads the brand name. Spoken text uses a phonetic
# stand-in; vo.json keeps the display spelling "Ichido".
# Tried against the target ee-CHEE-doh:
#   Ee-chee-doh  — three forced syllables: Ee /i/, chee /tʃi/, doh /doʊ/
#   Eechee-doh   — one token "Eechee" can stress the first syllable (EE-chee)
#   Ichi-doh     — leading "I" can become "eye" or "itch"
# Ee-chee-doh is the simple spelling that maps onto ee-CHEE-doh.
ICHIDO_PHONETIC="Ee-chee-doh"

SAY="/usr/bin/say"
FFMPEG="/opt/homebrew/bin/ffmpeg"
FFPROBE="/opt/homebrew/bin/ffprobe"

MOTION_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${MOTION_ROOT}/public/promo-2026-10-04/scratch-vo"
mkdir -p "${OUT_DIR}"

# Keep ~10 ms before speech onset and ~60 ms after the last audible sample.
# start_periods only (plus a reverse pass) so intentional [[slnc]] gaps stay.
TRIM_FILTER="silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.01:detection=peak:window=0.005,areverse,silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.06:detection=peak:window=0.005,areverse"

render_clip() {
  local id="$1"
  local spoken="$2"
  local aiff="${OUT_DIR}/${id}.aiff"
  local pcm="${OUT_DIR}/${id}.pcm.wav"
  local wav="${OUT_DIR}/${id}.wav"

  "${SAY}" -v "${VOICE}" -r "${RATE_WPM}" -o "${aiff}" "${spoken}"
  "${FFMPEG}" -y -loglevel error -i "${aiff}" -ar 48000 -ac 1 -c:a pcm_s16le "${pcm}"
  rm -f "${aiff}"
  "${FFMPEG}" -y -loglevel error -i "${pcm}" -af "${TRIM_FILTER}" -ar 48000 -ac 1 -c:a pcm_s16le "${wav}"
  rm -f "${pcm}"
}

manifest="$(mktemp "${TMPDIR:-/tmp}/scratch-vo.XXXXXX")"
trap 'rm -f "${manifest}"' EXIT

while IFS=$'\t' read -r id scene display spoken; do
  [[ -z "${id}" || "${id}" == \#* ]] && continue
  spoken="${spoken//__ICHIDO__/${ICHIDO_PHONETIC}}"
  printf 'say %s\n' "${id}" >&2
  render_clip "${id}" "${spoken}"
  printf '%s\t%s\t%s\n' "${id}" "${scene}" "${display}" >> "${manifest}"
done << 'CLIPS'
vo01	S01	One more try.	One more try.
vo02a	S02	Meet Ichido, your private speaking room for Mac.	Meet __ICHIDO__, your private speaking room for Mac.
vo02b	S02	Import a clip, or capture Mac audio.	Import a clip, or capture Mac audio.
vo03a	S03	Listen to a phrase.	Listen to a phrase.
vo03u	S03b	Explore the words, right on your Mac.	Explore the words, right on your Mac.
vo03b	S03c	Then record your version.	Then record your version.
vo04	S04	Compare pitch, timing, and loudness with the reference.	Compare pitch, timing, and loudness with the reference.
vo05	S05	When enough words match reliably, two measured targets help you choose what to try next.	When enough words match reliably, two measured targets help you choose what to try next.
vo06a	S06	Record yourself, too.	Record yourself, too.
vo06b	S06	Click a word to replay that moment.	Click a word to replay that moment.
vo07a	S07	No account. No recording uploads. No analytics.	No account. [[slnc 220]] No recording uploads. [[slnc 220]] No analytics.
vo07b	S07	Your recordings, transcripts, analysis, and language chat stay on your Mac.	Your recordings, transcripts, analysis, and language chat stay on your Mac.
vo07c	S07	Update checks and optional model downloads use the network.	Update checks and optional model downloads use the network.
vo08	S08	Ichido. One more try.	__ICHIDO__. [[slnc 250]] One more try.
CLIPS

MANIFEST="${manifest}" OUT_DIR="${OUT_DIR}" RATE_WPM="${RATE_WPM}" FFPROBE="${FFPROBE}" \
  python3 - << 'PY'
import json
import os
import subprocess

manifest = os.environ["MANIFEST"]
out_dir = os.environ["OUT_DIR"]
ffprobe = os.environ["FFPROBE"]
rate = int(os.environ["RATE_WPM"])

clips = []
with open(manifest, encoding="utf-8") as handle:
    for line in handle:
        clip_id, scene, text = line.rstrip("\n").split("\t")
        wav = os.path.join(out_dir, f"{clip_id}.wav")
        raw = subprocess.check_output(
            [
                ffprobe,
                "-v", "error",
                "-show_entries", "format=duration",
                "-of", "csv=p=0",
                wav,
            ],
            text=True,
        ).strip()
        clips.append(
            {
                "id": clip_id,
                "scene": scene,
                "text": text,
                "file": f"promo-2026-10-04/scratch-vo/{clip_id}.wav",
                "duration_s": float(f"{float(raw):.3f}"),
            }
        )

payload = {
    "voice": "Samantha",
    "rate_wpm": rate,
    "generated_by": "scripts/make-scratch-vo.sh",
    "note": "Scratch timed read for animatic pacing only. Not final VO.",
    "clips": clips,
}

encoded = json.dumps(payload, indent=2)
encoded = __import__("re").sub(
    r'("duration_s": )(-?\d+(?:\.\d+)?)',
    lambda match: f"{match.group(1)}{float(match.group(2)):.3f}",
    encoded,
)
path = os.path.join(out_dir, "vo.json")
with open(path, "w", encoding="utf-8") as handle:
    handle.write(encoded)
    handle.write("\n")
print(path)
PY
