# Lets the game speak the doll's chat answers in her own designed voice, using this Mac.
# start_voice.sh runs it between the internet (through Tailscale Funnel) and
# mlx_audio.server. That server has no password and lets callers pick any model
# or any reference file on this Mac, so it only listens to this Mac, and this
# guard lets callers choose the words and nothing else, a few lines at a time.
#
# The game sends: POST /speak with {"text": "..."}, and gets back a WAV file.
# Open the address in a browser to check that it's running.
#
# Uses only Python's own library, so it runs in the same ~/mlx-env as mlx-audio.

import argparse
import json
import socketserver
import threading
import time
import urllib.error
import urllib.request
from collections import defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

# Her chat answers are one or two short sentences
MAX_LETTERS = 300
# Lines per minute, for each player and for everyone together
PER_PLAYER = 8
EVERYONE = 40
# Lines waiting for their turn; beyond this, players hear the built-in voice instead
MAX_WAITING = 3
# Websites allowed to use it (the game on GitHub Pages, and the editor's web preview).
# The game run from the editor or as an app sends no Origin, and is allowed too.
ALLOWED_ORIGINS = ["https://pmgrnts.github.io", "http://localhost", "http://127.0.0.1"]


def main():
    parser = argparse.ArgumentParser(description="Lets the game use this Mac's voice model, safely.")
    parser.add_argument("--voice", required=True, help="her reference clip (.wav); its exact words go in a .txt file next to it")
    parser.add_argument("--model", default="mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16")
    parser.add_argument("--language", default="English")
    parser.add_argument("--mlx-server", default="http://127.0.0.1:8000")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()

    clip = Path(args.voice).expanduser().resolve()
    words = clip.with_suffix(".txt")
    if not clip.exists():
        raise SystemExit(f"Can't find her voice clip: {clip}")
    if not words.exists():
        raise SystemExit(f"Put the exact words spoken in {clip.name} in {words}")

    Guard.speech = {
        "model": args.model,
        "ref_audio": str(clip),
        "ref_text": words.read_text().strip(),
        "lang_code": args.language,
        "response_format": "wav",
    }
    Guard.mlx_url = args.mlx_server.rstrip("/") + "/v1/audio/speech"
    server = Server(("127.0.0.1", args.port), Guard)
    print(f"Voice guard on http://127.0.0.1:{args.port}, speaking as {clip.name}", flush=True)
    server.serve_forever()


class Server(ThreadingHTTPServer):
    daemon_threads = True

    # HTTPServer looks up this Mac's full name here, which can hang for a long time
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


class Guard(BaseHTTPRequestHandler):
    speech = {}
    mlx_url = ""
    turn = threading.Lock() # the Mac makes one line at a time
    waiting = 0
    waiting_lock = threading.Lock()
    recent = defaultdict(deque) # player: times of their recent lines ("" is everyone)
    recent_lock = threading.Lock()

    def do_GET(self):
        self._send(200, b"Her voice is running.\n", "text/plain")

    def do_OPTIONS(self):
        if not self._origin_allowed():
            return self._send(403, b"", "text/plain")
        self.send_response(204)
        self._cors()
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Max-Age", "86400")
        self.end_headers()

    def do_POST(self):
        if self.path.rstrip("/") != "/speak":
            return self._fail(404, "Not here. The game sends lines to /speak.")
        if not self._origin_allowed():
            return self._fail(403, "This website can't use her voice.")
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > 4096:
            return self._fail(400, "Send {\"text\": \"...\"}.")
        try:
            text = str(json.loads(self.rfile.read(length)).get("text", "")).strip()
        except (ValueError, AttributeError):
            return self._fail(400, "Send {\"text\": \"...\"}.")
        if text == "" or len(text) > MAX_LETTERS:
            return self._fail(400, f"Lines must be 1 to {MAX_LETTERS} letters.")
        if not self._take_slot():
            return self._fail(429, "She's talking too much. Try again in a minute.")

        with Guard.waiting_lock:
            if Guard.waiting >= MAX_WAITING:
                return self._fail(503, "She's busy talking to other players.")
            Guard.waiting += 1
        try:
            with Guard.turn:
                audio = self._ask_mlx(text)
        except (urllib.error.URLError, TimeoutError) as error:
            print(f"mlx_audio.server didn't answer: {error}", flush=True)
            return self._fail(502, "Her voice isn't ready. Is mlx_audio.server running?")
        finally:
            with Guard.waiting_lock:
                Guard.waiting -= 1
        self._send(200, audio, "audio/wav")

    def _ask_mlx(self, text):
        body = json.dumps(dict(Guard.speech, input=text)).encode()
        request = urllib.request.Request(Guard.mlx_url, body, {"Content-Type": "application/json"})
        with urllib.request.urlopen(request, timeout=120) as response:
            return response.read()

    # Counts the line against the player's and everyone's limits, if there's room
    def _take_slot(self):
        # Tailscale Funnel says who the player is in X-Forwarded-For
        player = (self.headers.get("X-Forwarded-For") or self.client_address[0]).split(",")[0].strip()
        now = time.monotonic()
        with Guard.recent_lock:
            for who, limit in [(player, PER_PLAYER), ("", EVERYONE)]:
                times = Guard.recent[who]
                while times and now - times[0] > 60:
                    times.popleft()
                if len(times) >= limit:
                    return False
            Guard.recent[player].append(now)
            Guard.recent[""].append(now)
            if len(Guard.recent) > 1000: # forget players who've gone quiet
                for who in [who for who, times in Guard.recent.items() if who and not times]:
                    del Guard.recent[who]
        return True

    def _origin_allowed(self):
        origin = self.headers.get("Origin")
        if origin is None:
            return True
        return any(origin == allowed or origin.startswith(allowed + ":") for allowed in ALLOWED_ORIGINS)

    def _cors(self):
        origin = self.headers.get("Origin")
        if origin and self._origin_allowed():
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")

    def _fail(self, code, message):
        self._send(code, (message + "\n").encode(), "text/plain")

    def _send(self, code, body, content_type):
        self.send_response(code)
        self._cors()
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        # one short line per request, without players' addresses
        print(f"{time.strftime('%H:%M:%S')} {self.command} {self.path} {args[1] if len(args) > 1 else ''}", flush=True)


if __name__ == "__main__":
    main()
