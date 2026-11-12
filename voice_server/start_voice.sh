#!/bin/bash
# Lends this Mac's voice model to the game, so the doll speaks her chat answers in her own voice.
# Run it, leave the window open, and press Ctrl+C to stop. See "Voice" in readme.txt.
#
#   ./voice_server/start_voice.sh                       # uses ~/VoiceStudio/voices/coco.wav
#   ./voice_server/start_voice.sh path/to/clip.wav      # or another clip
#   ./voice_server/start_voice.sh --local               # only this Mac, no Tailscale (for testing)
#
# Her clip needs its exact words in a .txt file next to it (coco.wav, coco.txt).

set -euo pipefail

MODEL="mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16" # the fast one; the 1.7B Base sounds better but is slower
MLX_PORT=8000
GUARD_PORT=8765

local_only=false
voice="$HOME/VoiceStudio/voices/coco.wav"
for arg in "$@"; do
	case "$arg" in
		--local) local_only=true ;;
		*) voice="$arg" ;;
	esac
done

here="$(cd "$(dirname "$0")" && pwd)"
source "$HOME/mlx-env/bin/activate"

tailscale="$(command -v tailscale || echo /Applications/Tailscale.app/Contents/MacOS/Tailscale)"
if ! $local_only && ! [ -x "$tailscale" ]; then
	echo "Tailscale isn't installed. Get it from https://tailscale.com/download/mac, or run with --local."
	exit 1
fi

# Everything started here stops when this script does
trap 'kill $(jobs -p) 2>/dev/null' EXIT

mkdir -p "$HOME/VoiceStudio/logs"
mlx_audio.server --host 127.0.0.1 --port "$MLX_PORT" --log-dir "$HOME/VoiceStudio/logs" > "$HOME/VoiceStudio/logs/mlx_server.log" 2>&1 &
python3 "$here/voice_guard.py" --voice "$voice" --model "$MODEL" --mlx-server "http://127.0.0.1:$MLX_PORT" --port "$GUARD_PORT" &
caffeinate -i -w $$ & # keeps the Mac awake while she's talking

echo "Warming up her voice (the first time, the model downloads)..."
for i in $(seq 60); do
	curl -sf "http://127.0.0.1:$MLX_PORT/docs" > /dev/null && break
	sleep 1
done
if ! curl -sf -X POST "http://127.0.0.1:$GUARD_PORT/speak" -d '{"text": "Hello!"}' -o /dev/null --max-time 300; then
	echo "She couldn't speak. See $HOME/VoiceStudio/logs/mlx_server.log"
	exit 1
fi
echo "Ready."

if $local_only; then
	echo "Her voice is at http://127.0.0.1:$GUARD_PORT (this Mac only). Press Ctrl+C to stop."
	wait
else
	echo "Sharing it through Tailscale Funnel. Put the https://...ts.net address below in the"
	echo "DollVoice node's \"Server Url\" (Popups/DollChat/DollVoice in dress_up.tscn). Press Ctrl+C to stop."
	"$tailscale" funnel "$GUARD_PORT"
fi
