#!/usr/bin/env python3
"""Awesome Time desktop bridge.

Serves Now Playing state over LAN and pushes updates in real time.

  GET  /health  -> {"ok": true}
  GET  /state   -> MediaState JSON (HTTP fallback)
  POST /cmd     -> {"action": playPause|next|prev|seek|volume", ...}
  GET  /ws      -> WebSocket: server pushes {"type":"state",...};
                   client may send {"type":"cmd", ...}

No third-party dependencies (stdlib only).
macOS: nowplaying-cli (MediaRemote) first, then broad AppleScript fallbacks.
"""

from __future__ import annotations

import argparse
import base64
import errno
import hashlib
import json
import platform
import select
import shutil
import socket
import struct
import subprocess
import sys
import threading
import time
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Optional


DEFAULT_PORT = 8765
DEFAULT_DISCOVERY_PORT = 8766
DISCOVERY_MAGIC = "AWESOME_TIME_DISCOVER"
VALID_ACTIONS = ("playPause", "next", "prev", "seek", "volume")
# Push at least this often while clients are attached so the phone does not
# rely on long stretches of local wall-clock interpolation.
POSITION_PUSH_INTERVAL_S = 0.5


def _empty_state(source: str = "") -> dict[str, Any]:
    return {
        "playing": False,
        "title": "",
        "artist": "",
        "album": "",
        "source": source,
        "artworkUrl": "",
        "artwork": "",
        "positionMs": 0,
        "durationMs": 0,
        "volume": 0.5,
        "updatedAtMs": 0,
    }


class StateStore:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.state: dict[str, Any] = _empty_state()
        self._local_pos_ms = 0
        self._local_pos_wall = 0.0
        self._playing = False
        self._seq = 0
        self._hold_until = 0.0
        # Last positive position sample from the OS player (detects staleness).
        self._last_raw_pos = -1
        self._last_raw_wall = 0.0
        self.spectrum: list[float] = [0.0] * 32

    def set_spectrum(self, bands: list[float]) -> None:
        with self.lock:
            n = max(1, len(self.spectrum))
            if len(bands) == n:
                self.spectrum = [max(0.0, min(1.0, float(x))) for x in bands]
            elif bands:
                # Resample incoming bins into the store size.
                out = []
                last = len(bands) - 1
                for i in range(n):
                    u = 0.0 if n == 1 else i / (n - 1)
                    x = u * last
                    lo = int(x)
                    hi = min(last, lo + 1)
                    t = x - lo
                    out.append(
                        max(
                            0.0,
                            min(
                                1.0,
                                float(bands[lo]) * (1 - t) + float(bands[hi]) * t,
                            ),
                        )
                    )
                self.spectrum = out

    def spectrum_copy(self) -> list[float]:
        with self.lock:
            return [round(x, 3) for x in self.spectrum]

    def update_from_capture(self, incoming: dict[str, Any]) -> bool:
        """Fold an OS sample into the store.

        Returns True when metadata/playing changed OR the playhead jumped
        (seek on the phone or on the computer) so the poller can push at once.
        """
        with self.lock:
            title = str(incoming.get("title") or "")
            playing = bool(incoming.get("playing"))
            raw_pos = int(incoming.get("positionMs") or 0)
            dur = int(incoming.get("durationMs") or 0)
            now_ms = int(time.time() * 1000)
            wall = time.time()

            prev_title = self.state.get("title") or ""
            prev_src = self.state.get("source") or ""
            src = str(incoming.get("source") or "")
            # Provisional: filled more carefully after new_title is known below.
            track_changed = bool(title) and (
                title != prev_title or (src and prev_src and src != prev_src)
            )
            holding = (not track_changed) and wall < self._hold_until
            if holding:
                playing = self._playing

            pos_before = self._local_pos_ms

            if track_changed:
                self._hold_until = 0.0
                # Only snap to 0 when the OS really reports start-of-track.
                # A dead MediaRemote (elapsed=0) must not reset a mid-song head.
                if raw_pos > 0:
                    self._local_pos_ms = raw_pos
                    self._local_pos_wall = wall
                    self._last_raw_pos = raw_pos
                    self._last_raw_wall = wall
                else:
                    # New/unknown head: keep wall base at 0 start, but let the
                    # next positive classic-player sample correct us immediately.
                    self._local_pos_ms = 0
                    self._local_pos_wall = wall
                    self._last_raw_pos = -1
                    self._last_raw_wall = 0.0
            elif playing:
                extrap = self._read_extrapolated_locked()
                if raw_pos > 0:
                    # Any positive sample wins — classic player / working elapsed.
                    # This is what picks up scrubbing on the Mac.
                    if (
                        self._last_raw_pos < 0
                        or raw_pos != self._last_raw_pos
                        or abs(raw_pos - extrap) > 400
                    ):
                        self._local_pos_ms = raw_pos
                        self._local_pos_wall = wall
                        self._last_raw_pos = raw_pos
                        self._last_raw_wall = wall
                        if abs(raw_pos - pos_before) >= 400:
                            pass  # caller marks changed via pos_before diff
                    # else: same sample, keep extrapolating
                elif self._local_pos_wall == 0:
                    self._local_pos_ms = 0
                    self._local_pos_wall = wall
                # else: playing with dead elapsed — extrapolate last trusted head
            else:
                if raw_pos > 0:
                    self._local_pos_ms = raw_pos
                    self._local_pos_wall = wall
                    self._last_raw_pos = raw_pos
                    self._last_raw_wall = wall
                else:
                    self._local_pos_ms = self._read_extrapolated_locked()
                    self._local_pos_wall = wall

            if not holding:
                self._playing = playing

            vol = incoming.get("volume")
            if vol is None:
                vol = self.state.get("volume", 0.5)

            # Never blank the title mid-track because one capture returned "".
            new_title = title if title else prev_title
            new_src = src if src else prev_src
            # Title really changed only when both sides non-empty and differ,
            # or incoming is a clear new non-empty title.
            if title and prev_title and title != prev_title:
                track_changed = True
                self._hold_until = 0.0
            elif title and not prev_title:
                track_changed = True
            elif not title:
                track_changed = False

            incoming_art = str(incoming.get("artwork") or "")
            incoming_art_url = str(incoming.get("artworkUrl") or "")
            prev = self.state
            prev_art = str(prev.get("artwork") or "")
            prev_art_url = str(prev.get("artworkUrl") or "")
            new_art = incoming_art if incoming_art else prev_art
            new_art_url = incoming_art_url if incoming_art_url else prev_art_url
            changed = (
                prev.get("title") != new_title
                or prev.get("artist") != str(incoming.get("artist") or "")
                or prev.get("album") != str(incoming.get("album") or "")
                or prev.get("source") != new_src
                or prev.get("playing") != playing
                or prev.get("durationMs") != dur
                or abs((prev.get("volume") or 0) - (float(vol) if vol is not None else 0.5)) > 0.01
            )
            if incoming_art and incoming_art != prev_art:
                changed = True
            if incoming_art_url and incoming_art_url != prev_art_url:
                changed = True

            # Large playhead jump (seek on Mac or phone) → push immediately.
            if abs(self._local_pos_ms - pos_before) >= 400:
                changed = True

            self.state.update(
                {
                    "playing": playing,
                    "title": new_title,
                    "artist": str(incoming.get("artist") or ""),
                    "album": str(incoming.get("album") or ""),
                    "source": new_src,
                    "artworkUrl": new_art_url,
                    "artwork": new_art,
                    "durationMs": dur,
                    "volume": float(vol) if vol is not None else 0.5,
                    "updatedAtMs": now_ms,
                    "positionMs": self._read_extrapolated_locked(),
                }
            )
            if dur:
                self.state["positionMs"] = min(
                    int(self.state["positionMs"]), int(dur)
                )
            self._seq += 1
            return changed

    def set_artwork(self, artwork: str, artwork_url: str = "") -> bool:
        with self.lock:
            prev = str(self.state.get("artwork") or "")
            prev_url = str(self.state.get("artworkUrl") or "")
            if prev == artwork and prev_url == artwork_url:
                return False
            self.state["artwork"] = artwork
            if artwork_url:
                self.state["artworkUrl"] = artwork_url
            self.state["updatedAtMs"] = int(time.time() * 1000)
            self._seq += 1
            return True

    def _local_pos_pos_reset(self, pos: int) -> None:
        self._local_pos_ms = pos
        self._local_pos_wall = time.time()

    def snapshot(self) -> dict[str, Any]:
        with self.lock:
            out = {k: v for k, v in self.state.items() if k != "artwork"}
            out["positionMs"] = self._read_extrapolated_locked()
            if out["durationMs"]:
                out["positionMs"] = min(out["positionMs"], out["durationMs"])
            out["updatedAtMs"] = int(time.time() * 1000)
            out["seq"] = self._seq
            return out

    def artwork_only(self) -> str:
        with self.lock:
            return str(self.state.get("artwork") or "")

    def apply_local_control(
        self, action: str, value: Any = None, value_ms: Any = None
    ) -> dict[str, Any]:
        with self.lock:
            self._hold_until = time.time() + 1.35
            if action == "playPause":
                self._playing = not self._playing
                self.state["playing"] = self._playing
                if not self._playing:
                    self._local_pos_ms = self._read_extrapolated_locked()
                    self._local_pos_wall = time.time()
                else:
                    self._local_pos_wall = time.time()
            elif action == "seek" and value_ms is not None:
                self._local_pos_ms = max(0, int(value_ms))
                self._local_pos_wall = time.time()
                self._last_raw_pos = self._local_pos_ms
                self._last_raw_wall = time.time()
                self.state["positionMs"] = self._local_pos_ms
            elif action == "volume" and value is not None:
                try:
                    self.state["volume"] = max(0.0, min(1.0, float(value)))
                except (TypeError, ValueError):
                    pass
            elif action in ("next", "prev"):
                self.state["positionMs"] = 0
                self._local_pos_ms = 0
                self._local_pos_wall = time.time()
                self._last_raw_pos = -1
                self._last_raw_wall = 0.0
            self.state["updatedAtMs"] = int(time.time() * 1000)
            self._seq += 1
            out = dict(self.state)
            out["positionMs"] = self._read_extrapolated_locked()
            out["updatedAtMs"] = self.state["updatedAtMs"]
            out["seq"] = self._seq
            return out

    def _read_extrapolated_locked(self) -> int:
        pos = self._local_pos_ms
        if self._playing and self._local_pos_wall:
            elapsed = int((time.time() - self._local_pos_wall) * 1000)
            pos = self._local_pos_ms + elapsed
        return max(0, pos)


STORE = StateStore()
LAST_SOURCE = ""
_last_script_pos_at = 0.0
_os_cmd_lock = threading.Lock()
_os_exec_lock = threading.Lock()
_os_cmd_seq = 0
CLASSIC_PLAYERS = ("Music", "Spotify", "Podcasts", "Audible", "VLC", "IINA")


def _classic_player_sample(preferred: str = "") -> Optional[dict[str, Any]]:
    """Read real transport from a desktop player via AppleScript.

    MediaRemote on this machine often reports elapsedTime=0 and
    applicationDisplayName=null — phone seek still worked only because it
    wrote the store directly. Computer-side scrubbing needs this path.
    """
    global _last_script_pos_at
    apps: list[str] = []
    if preferred and preferred in CLASSIC_PLAYERS:
        apps.append(preferred)
    if LAST_SOURCE in CLASSIC_PLAYERS and LAST_SOURCE not in apps:
        apps.append(LAST_SOURCE)
    for app in CLASSIC_PLAYERS:
        if app not in apps:
            apps.append(app)

    now = time.time()
    # Avoid hammering osascript on every 250ms tick when nothing changed.
    if now - _last_script_pos_at < 0.2:
        return None

    for app in apps:
        script = f'''
        tell application "System Events"
          if not (exists process "{app}") then return ""
        end tell
        tell application "{app}"
          try
            set t to name of current track
          on error
            return ""
          end try
          if t is "" then return ""
          set ar to artist of current track
          set al to album of current track
          set dur to duration of current track
          set playState to (player state as text)
          set pos to 0
          try
            set pos to player position
          end try
          return t & "\\t" & ar & "\\t" & al & "\\t" & dur & "\\t" & pos & "\\t" & playState
        end tell
        '''
        out = run_osascript(script, timeout=0.4)
        if not out or "\t" not in out:
            continue
        parts = out.split("\t")
        while len(parts) < 6:
            parts.append("")
        t, ar, al, dur, pos, play_raw = parts[:6]
        if not t:
            continue
        pos_ms = int(_to_float(pos) * 1000)
        dur_ms = int(_to_float(dur) * 1000)
        st_l = play_raw.lower()
        playing = st_l.startswith("play") or st_l in (
            "fast forwarding",
            "rewinding",
        )
        _last_script_pos_at = now
        return {
            "playing": playing,
            "title": t,
            "artist": ar,
            "album": al,
            "source": app,
            "positionMs": pos_ms,
            "durationMs": dur_ms,
        }
    return None


# ---------------------------------------------------------------------------
# WebSocket hub (stdlib RFC6455, text frames only)
# ---------------------------------------------------------------------------

_WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def _ws_accept_key(key: str) -> str:
    digest = hashlib.sha1((key + _WS_GUID).encode("utf-8")).digest()
    return base64.b64encode(digest).decode("ascii")


def _encode_text_frame(payload: str) -> bytes:
    data = payload.encode("utf-8")
    n = len(data)
    if n < 126:
        header = struct.pack("!BB", 0x81, n)
    elif n < 65536:
        header = struct.pack("!BBH", 0x81, 126, n)
    else:
        header = struct.pack("!BBQ", 0x81, 127, n)
    return header + data


def _encode_binary_frame(payload: bytes) -> bytes:
    """WS binary frame (opcode 0x2). Spectrum uses this — no JSON on the wire."""
    n = len(payload)
    if n < 126:
        header = struct.pack("!BB", 0x82, n)
    elif n < 65536:
        header = struct.pack("!BBH", 0x82, 126, n)
    else:
        header = struct.pack("!BBQ", 0x82, 127, n)
    return header + payload


def encode_spectrum_frame(bands: list[float]) -> bytes:
    """Binary spectrum: 0x53, count, uint8 levels[count]."""
    n = len(bands)
    buf = bytearray(n + 2)
    buf[0] = 0x53  # 'S'
    buf[1] = n & 0xFF
    for i, x in enumerate(bands):
        v = int(x * 255.0 + 0.5)
        buf[2 + i] = 0 if v < 0 else (255 if v > 255 else v)
    return _encode_binary_frame(bytes(buf))


def _encode_control_frame(opcode: int, payload: bytes = b"") -> bytes:
    n = len(payload)
    if n > 125:
        payload = payload[:125]
        n = len(payload)
    return struct.pack("!BB", 0x80 | (opcode & 0x0F), n) + payload


class WSClient:
    """Outbound WS with a dedicated sender thread.

    Critical for spectrum: never block the audio reader on a slow TCP window.
    Droppable frames (spectrum) coalesce to the latest only.
    """

    def __init__(self, sock: Any) -> None:
        self.sock = sock
        try:
            self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        except OSError:
            pass
        self.alive = True
        self._cv = threading.Condition()
        self._queue: deque[bytes] = deque()
        self._droppable: bytes | None = None
        self._out = bytearray()
        self._sender = threading.Thread(
            target=self._send_loop,
            name="ws-send",
            daemon=True,
        )
        self._sender.start()

    def send_text(self, text: str, *, droppable: bool = False) -> bool:
        if not self.alive:
            return False
        try:
            frame = _encode_text_frame(text)
        except Exception:  # noqa: BLE001
            return False
        return self.send_frame(frame, droppable=droppable)

    def send_frame(self, frame: bytes, *, droppable: bool = False) -> bool:
        if not self.alive:
            return False
        with self._cv:
            if droppable:
                # Latest-wins: drop any unsent spectrum frame.
                self._droppable = frame
            else:
                if len(self._queue) > 64:
                    self._queue.popleft()
                self._queue.append(frame)
            self._cv.notify()
        return True

    def _send_loop(self) -> None:
        # Keep the socket blocking for the reader thread. Only this send
        # path is non-blocking (MSG_DONTWAIT) so a full TCP window cannot
        # stall stdout reads or the state pusher.
        flags = getattr(socket, "MSG_DONTWAIT", 0)
        would_block = {errno.EAGAIN, errno.EWOULDBLOCK}
        while self.alive:
            with self._cv:
                if not self._out:
                    # Spectrum first when both are ready: visual cadence
                    # matters more than a queued state duplicate.
                    if self._droppable is not None:
                        self._out.extend(self._droppable)
                        self._droppable = None
                    elif self._queue:
                        self._out.extend(self._queue.popleft())
                    else:
                        self._cv.wait(0.1)
                        continue
            blocked = False
            while self._out and self.alive:
                try:
                    n = self.sock.send(self._out, flags)
                    if n <= 0:
                        raise ConnectionError("send returned 0")
                    del self._out[:n]
                except (BlockingIOError, InterruptedError):
                    blocked = True
                    break
                except OSError as exc:
                    if exc.errno in would_block:
                        blocked = True
                        break
                    self._fail()
                    break
            if self.alive and blocked and self._out:
                try:
                    select.select([], [self.sock], [], 0.05)
                except (OSError, ValueError):
                    self._fail()

    def _fail(self) -> None:
        self.alive = False
        with self._cv:
            self._cv.notify_all()
        try:
            self.sock.shutdown(2)
        except OSError:
            pass

    def flush(self, timeout: float = 0.2) -> None:
        deadline = time.time() + timeout
        while time.time() < deadline:
            with self._cv:
                if not self._out and not self._queue and self._droppable is None:
                    return
            time.sleep(0.01)

    def close(self) -> None:
        if self.alive:
            self.flush(0.15)
        self.alive = False
        with self._cv:
            self._cv.notify_all()
        try:
            self.sock.shutdown(2)
        except OSError:
            pass
        try:
            self.sock.close()
        except OSError:
            pass

    def recv_exact(self, n: int) -> bytes:
        buf = bytearray()
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise ConnectionError("peer closed")
            buf.extend(chunk)
        return bytes(buf)

    def read_frame(self) -> tuple[int, bytes]:
        b1, b2 = self.recv_exact(2)
        opcode = b1 & 0x0F
        masked = bool(b2 & 0x80)
        length = b2 & 0x7F
        if length == 126:
            (length,) = struct.unpack("!H", self.recv_exact(2))
        elif length == 127:
            (length,) = struct.unpack("!Q", self.recv_exact(8))
        mask = self.recv_exact(4) if masked else None
        payload = self.recv_exact(length) if length else b""
        if mask:
            payload = bytes(payload[i] ^ mask[i % 4] for i in range(len(payload)))
        return opcode, payload


class WSHub:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._clients: set[WSClient] = set()

    def add(self, client: WSClient) -> None:
        with self._lock:
            self._clients.add(client)

    def remove(self, client: WSClient) -> None:
        with self._lock:
            self._clients.discard(client)

    def broadcast_obj(self, obj: Any, *, droppable: bool = False) -> None:
        text = json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
        frame = _encode_text_frame(text)
        self._broadcast_frame(frame, droppable=droppable)

    def broadcast_spectrum(self, bands: list[float]) -> None:
        """Binary latest-wins spectrum — smaller and faster than JSON."""
        if not bands:
            return
        self._broadcast_frame(encode_spectrum_frame(bands), droppable=True)

    def _broadcast_frame(self, frame: bytes, *, droppable: bool = False) -> None:
        with self._lock:
            clients = list(self._clients)
        if not clients:
            return
        dead: list[WSClient] = []
        for c in clients:
            if not c.send_frame(frame, droppable=droppable):
                dead.append(c)
        if dead:
            with self._lock:
                for c in dead:
                    self._clients.discard(c)
            for c in dead:
                c.close()

    @property
    def count(self) -> int:
        with self._lock:
            return len(self._clients)


HUB = WSHub()


def handle_ws_connection(client: WSClient) -> None:
    HUB.add(client)
    try:
        # Immediate snapshot so UI paints right away.
        client.send_text(
            json.dumps(
                {"type": "state", **_light_state(STORE.snapshot())},
                ensure_ascii=False,
                separators=(",", ":"),
            )
        )
        client.send_text(json.dumps({"type": "art", "seq": STORE.snapshot().get("seq", 0)}))
        while client.alive:
            try:
                opcode, payload = client.read_frame()
            except (OSError, ConnectionError, struct.error):
                break
            if opcode == 0x8:  # close — enqueue so we don't block the reader
                client.send_frame(_encode_control_frame(0x8, payload[:125]))
                break
            if opcode == 0x9:  # ping -> pong
                if not client.send_frame(_encode_control_frame(0xA, payload)):
                    break
                continue
            if opcode == 0xA:  # pong
                continue
            if opcode != 0x1:  # only text JSON from phone
                continue
            try:
                data = json.loads(payload.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                continue
            if not isinstance(data, dict):
                continue
            msg_type = str(data.get("type") or "")
            if msg_type == "cmd":
                action = str(data.get("action") or "")
                if action in VALID_ACTIONS:
                    execute_command(action, data.get("value"), data.get("valueMs"))
            elif msg_type == "ping":
                client.send_text(json.dumps({"type": "pong", "t": int(time.time() * 1000)}))
            elif msg_type == "hello":
                client.send_text(
                    json.dumps(
                        {"type": "state", **_light_state(STORE.snapshot())},
                        ensure_ascii=False,
                        separators=(",", ":"),
                    )
                )
                client.send_text(json.dumps({"type": "art", "seq": STORE.snapshot().get("seq", 0)}))
    finally:
        HUB.remove(client)
        client.close()


# ---------------------------------------------------------------------------
# Command execution (macOS / Windows / Linux best-effort)
# ---------------------------------------------------------------------------

def run_osascript(script: str, timeout: float = 0.8) -> str:
    try:
        proc = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        return (proc.stdout or "").strip()
    except Exception:
        return ""


def nowplaying_cli(args: list[str], timeout: float = 2.0) -> Optional[str]:
    exe = shutil.which("nowplaying-cli")
    if not exe:
        return None
    try:
        proc = subprocess.run(
            [exe, *args],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        if proc.returncode != 0:
            return None
        return (proc.stdout or "").strip()
    except Exception:
        return None


def _parse_kv_output(raw: str) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        if ":" in line:
            k, v = line.split(":", 1)
            out[k.strip()] = v.strip()
        elif "=" in line:
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def _to_float(v: Any, default: float = 0.0) -> float:
    if v is None:
        return default
    if isinstance(v, (int, float)):
        return float(v)
    s = str(v).strip()
    if not s or s.lower() in ("null", "none", "(null)"):
        return default
    # strip units like "s"
    s = s.rstrip("sS")
    try:
        return float(s)
    except ValueError:
        return default


def _is_playing(v: Any) -> bool:
    if v is None:
        # Callers only use this when a title is present. MediaRemote often
        # omits isPlaying — assume playing so the clock keeps moving with the PC.
        return True
    if isinstance(v, bool):
        return v
    if isinstance(v, (int, float)):
        return v == 1
    s = str(v).strip().lower()
    if s in ("null", "none", ""):
        return True
    if s in ("0", "false", "no", "paused", "stopped"):
        return False
    return s in ("1", "true", "yes", "playing")


def capture_macos() -> dict[str, Any]:
    """MediaRemote via nowplaying-cli, then AppleScript, then browser title.

    nowplaying-cli v2 short keys (with --json):
      title, artist, album, duration, elapsedTime, isPlaying,
      applicationDisplayName, artworkData, playbackRate
    kMR... long keys only work via `get-raw`.
    """
    art_keys = [
        "title",
        "artist",
        "album",
        "duration",
        "elapsedTime",
        "isPlaying",
        "applicationDisplayName",
        "playbackRate",
    ]
    # Hot path: never fetch artworkData (huge, slow). Cover is polled on track change.
    raw = nowplaying_cli(["get", "--json", *art_keys], timeout=0.35)
    if not raw:
        raw = nowplaying_cli(["get-raw"], timeout=0.45)

    data: dict[str, Any] = {}
    if raw:
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, dict):
                data = parsed
        except json.JSONDecodeError:
            data = _parse_kv_output(raw)

    def pick(*keys: str) -> Any:
        lower_map = {str(k).lower(): v for k, v in data.items()}
        for k in keys:
            if k in data and data[k] not in (None, "", "null"):
                return data[k]
            lk = k.lower()
            if lk in lower_map and lower_map[lk] not in (None, "", "null"):
                return lower_map[lk]
        return None

    title = pick("title", "kMRMediaRemoteNowPlayingInfoTitle", "Title")
    if title:
        duration = pick(
            "duration",
            "kMRMediaRemoteNowPlayingInfoDuration",
            "Duration",
        )
        elapsed = pick(
            "elapsedTime",
            "kMRMediaRemoteNowPlayingInfoElapsedTime",
            "ElapsedTime",
            "position",
        )
        playing = pick(
            "isPlaying",
            "kMRMediaRemoteNowPlayingApplicationIsPlaying",
            "playing",
        )
        rate = pick(
            "playbackRate",
            "kMRMediaRemoteNowPlayingInfoPlaybackRate",
        )
        source = pick(
            "applicationDisplayName",
            "kMRMediaRemoteNowPlayingApplicationDisplayName",
            "source",
            "application",
        )
        bundle = pick(
            "kMRMediaRemoteNowPlayingInfoClientBundleIdentifier",
            "bundleIdentifier",
        )

        if playing is None and rate is not None:
            playing = _to_float(rate, 0.0) > 0

        src_label = str(source or "")
        if not src_label and isinstance(bundle, str) and bundle:
            src_label = bundle.rsplit(".", 1)[-1]

        artist = str(
            pick("artist", "kMRMediaRemoteNowPlayingInfoArtist", "Artist") or ""
        )
        album = str(
            pick("album", "kMRMediaRemoteNowPlayingInfoAlbum", "Album") or ""
        )
        pos_ms = int(_to_float(elapsed) * 1000)
        dur_ms = int(_to_float(duration) * 1000)
        is_pl = _is_playing(playing)

        # MediaRemote elapsed is hard-zero on many Macs; displayName may be null.
        # Always resolve position from a real player when elapsed is dead.
        preferred = src_label if src_label in CLASSIC_PLAYERS else ""
        if pos_ms <= 0 or not is_pl or not src_label or src_label in ("", "macOS"):
            hint = _classic_player_sample(preferred)
            if hint:
                if hint["positionMs"] > 0:
                    pos_ms = hint["positionMs"]
                if hint["durationMs"] > 0 and dur_ms <= 0:
                    dur_ms = hint["durationMs"]
                is_pl = hint["playing"]
                src_label = hint["source"]
                # Dead MediaRemote metadata → trust the live player wholesale.
                if pos_ms <= 0 or str(title) != hint["title"]:
                    if pos_ms <= 0:
                        title = hint["title"]
                        artist = hint.get("artist") or artist
                        album = hint.get("album") or album
                        if hint["durationMs"] > 0:
                            dur_ms = hint["durationMs"]
                        is_pl = hint["playing"]
                        src_label = hint["source"]
                        # Keep MediaRemote duration when present and plausible.
                        if int(_to_float(duration) * 1000) > 0:
                            dur_ms = int(_to_float(duration) * 1000)

        return {
            "playing": is_pl,
            "title": str(title),
            "artist": artist,
            "album": album,
            "source": src_label or "macOS",
            "artworkUrl": "",
            "artwork": "",
            "positionMs": pos_ms,
            "durationMs": dur_ms,
        }

    # --- No MediaRemote title: fall back to a live classic player ---
    hint = _classic_player_sample("")
    if hint and hint["title"]:
        return {
            "playing": hint["playing"],
            "title": hint["title"],
            "artist": hint["artist"],
            "album": hint["album"],
            "source": hint["source"],
            "artworkUrl": "",
            "artwork": "",
            "positionMs": hint["positionMs"],
            "durationMs": hint["durationMs"],
        }

    # --- AppleScript fallbacks: classic players with full transport ---
    # Short timeouts — this loop must not freeze capture for seconds.
    for app in ("Music", "Spotify", "Podcasts", "Audible", "VLC", "IINA"):
        script = f'''
        tell application "System Events"
          if not (exists process "{app}") then return ""
        end tell
        tell application "{app}"
          try
            set t to name of current track
          on error
            return ""
          end try
          set ar to artist of current track
          set al to album of current track
          set dur to duration of current track
          set playState to (player state as text)
          set pos to 0
          try
            set pos to player position
          end try
          return t & "\\t" & ar & "\\t" & al & "\\t" & dur & "\\t" & pos & "\\t" & playState
        end tell
        '''
        out = run_osascript(script, timeout=0.45)
        if out and "\t" in out:
            parts = out.split("\t")
            while len(parts) < 6:
                parts.append("")
            t, ar, al, dur, pos, play_raw = parts[:6]
            st_l = play_raw.lower()
            return {
                "playing": st_l.startswith("play")
                or st_l in (
                    "fast forwarding",
                    "rewinding",
                    "playing",
                ),
                "title": t,
                "artist": ar,
                "album": al,
                "source": app,
                "artworkUrl": "",
                "artwork": "",
                "positionMs": int(_to_float(pos) * 1000),
                "durationMs": int(_to_float(dur) * 1000),
            }

    # --- Browser tab title heuristic (progress unknown without MediaRemote) ---
    browser_title = _capture_browser_tab()
    if browser_title:
        return {
            "playing": True,
            "title": browser_title,
            "artist": "",
            "album": "",
            "source": "Browser",
            "artworkUrl": "",
            "artwork": "",
            "positionMs": 0,
            "durationMs": 0,
        }

    return _empty_state("macOS")


def _capture_browser_tab() -> str:
    """Best-effort: active tab/page name of common browsers (no duration)."""
    scripts = [
        # Chrome
        '''
        tell application "System Events"
          if not (exists process "Google Chrome") then return ""
        end tell
        tell application "Google Chrome"
          if (count of windows) is 0 then return ""
          set w to front window
          if (count of tabs of w) is 0 then return ""
          return title of active tab of w
        end tell
        ''',
        # Safari
        '''
        tell application "System Events"
          if not (exists process "Safari") then return ""
        end tell
        tell application "Safari"
          if (count of windows) is 0 then return ""
          return name of front document
        end tell
        ''',
        # Edge
        '''
        tell application "System Events"
          if not (exists process "Microsoft Edge") then return ""
        end tell
        tell application "Microsoft Edge"
          if (count of windows) is 0 then return ""
          set w to front window
          if (count of tabs of w) is 0 then return ""
          return title of active tab of w
        end tell
        ''',
        # Firefox — title via System Events
        '''
        tell application "System Events"
          if not (exists process "firefox") then return ""
          try
            return name of first window of process "firefox"
          on error
            return ""
          end try
        end tell
        ''',
        # Brave
        '''
        tell application "System Events"
          if not (exists process "Brave Browser") then return ""
        end tell
        tell application "Brave Browser"
          if (count of windows) is 0 then return ""
          set w to front window
          if (count of tabs of w) is 0 then return ""
          return title of active tab of w
        end tell
        ''',
    ]
    for script in scripts:
        title = run_osascript(script, timeout=1.0)
        if not title:
            continue
        t = title.strip()
        if not t or t.lower() in ("new tab", "start page", "untitled"):
            continue
        # Common "Title - Site" video/music markers
        lowered = t.lower()
        if any(
            k in lowered
            for k in (
                "youtube",
                "bilibili",
                "music",
                "spotify",
                "netease",
                "qq音乐",
                "网易云",
                "soundcloud",
                "播客",
                "podcast",
                " - youtube",
                ".netflix",
                "视频",
            )
        ):
            return t[:120]
        # Prefer anything that looks like "Song - Artist" / "Song｜..."
        if " - " in t or " — " in t or "｜" in t or "|" in t:
            return t[:120]
    return ""


def capture_windows() -> dict[str, Any]:
    # Best-effort: rely on optional companion. Keep last/empty state.
    return _empty_state("Windows")


def capture_linux() -> dict[str, Any]:
    if shutil.which("playerctl"):
        def pc(*args: str) -> str:
            try:
                p = subprocess.run(
                    ["playerctl", *args],
                    capture_output=True,
                    text=True,
                    timeout=1.5,
                    check=False,
                )
                return (p.stdout or "").strip()
            except Exception:
                return ""

        title = pc("metadata", "title")
        if title:
            pos = pc("position") or "0"
            dur = pc("metadata", "mpris:length") or "0"
            try:
                pos_ms = int(float(pos) * 1000)
            except ValueError:
                pos_ms = 0
            try:
                dur_ms = int(int(dur) / 1000)
            except ValueError:
                try:
                    dur_ms = int(float(dur) * 1000)
                except ValueError:
                    dur_ms = 0
            status = pc("status")
            art = pc("metadata", "mpris:artUrl") or ""
            return {
                "playing": status == "Playing",
                "title": title,
                "artist": pc("metadata", "artist"),
                "album": pc("metadata", "album"),
                "source": pc("player") or "Linux",
                "artworkUrl": art if art.startswith(("http://", "https://", "file://")) else "",
                "artwork": "",
                "positionMs": pos_ms,
                "durationMs": dur_ms,
                "volume": STORE.snapshot().get("volume", 0.5),
            }
    return _empty_state("Linux")


def capture() -> dict[str, Any]:
    system = platform.system()
    if system == "Darwin":
        return capture_macos()
    if system == "Windows":
        return capture_windows()
    return capture_linux()


def _active_macos_app() -> str:
    out = run_osascript(
        'tell application "System Events" to get name of first application process whose frontmost is true',
        timeout=1.0,
    )
    return out or ""


def _match_classic(src: str) -> str:
    s = (src or "").lower()
    mapping = (
        ("spotify", "Spotify"),
        ("music", "Music"),
        ("音乐", "Music"),
        ("podcasts", "Podcasts"),
        ("播客", "Podcasts"),
        ("audible", "Audible"),
        ("vlc", "VLC"),
        ("iina", "IINA"),
    )
    for needle, app in mapping:
        if needle in s:
            return app
    if src in CLASSIC_PLAYERS:
        return src
    return ""


def _process_exists(app: str) -> bool:
    out = run_osascript(
        f'tell application "System Events" to (exists process "{app}")',
        timeout=0.35,
    )
    return out.lower() == "true"


def _app_set_playing(app: str, playing: bool) -> bool:
    if not _process_exists(app):
        return False
    verb = "play" if playing else "pause"
    script = f'''
    tell application "{app}" to {verb}
    return "ok"
    '''
    return run_osascript(script, timeout=0.8) == "ok"


def _media_key(kind: str) -> None:
    # F7 prev / F8 play / F9 next. Function-modified 16 is the media play key.
    if kind == "play":
        run_osascript(
            'tell application "System Events" to key code 16 using {function down}',
            timeout=0.35,
        )
    elif kind == "next":
        run_osascript(
            'tell application "System Events" to key code 101 using {function down}',
            timeout=0.35,
        )
    elif kind == "prev":
        run_osascript(
            'tell application "System Events" to key code 98 using {function down}',
            timeout=0.35,
        )


def cmd_play_pause_macos() -> None:
    want = bool(STORE.snapshot().get("playing"))
    app = _match_classic(LAST_SOURCE)
    if app and _app_set_playing(app, want):
        return

    nowplaying_cli(["play"] if want else ["pause"])
    time.sleep(0.18)
    cap = capture()
    if bool(cap.get("playing")) == want:
        return

    nowplaying_cli(["togglePlayPause"])
    time.sleep(0.15)
    cap = capture()
    if bool(cap.get("playing")) == want:
        return
    _media_key("play")


def _app_skip(app: str, which: str) -> bool:
    if not _process_exists(app):
        return False
    verb = "next track" if which == "next" else "previous track"
    script = f'''
    tell application "{app}" to {verb}
    return "ok"
    '''
    return run_osascript(script, timeout=0.8) == "ok"


def cmd_next_macos() -> None:
    # nowplaying-cli command is `next`, not next-track.
    if nowplaying_cli(["next"]) is not None:
        return
    app = _match_classic(LAST_SOURCE)
    if app and _app_skip(app, "next"):
        return
    _media_key("next")


def cmd_prev_macos() -> None:
    if nowplaying_cli(["previous"]) is not None:
        return
    app = _match_classic(LAST_SOURCE)
    if app and _app_skip(app, "prev"):
        return
    _media_key("prev")


def cmd_seek_macos(pos_s: float) -> None:
    app = _match_classic(LAST_SOURCE)
    if app and _process_exists(app):
        script = f'''
        tell application "{app}" to set player position to {pos_s}
        return "ok"
        '''
        if run_osascript(script, timeout=0.8) == "ok":
            return
    nowplaying_cli(["seek", str(pos_s)])


def cmd_volume_macos(vol: float) -> None:
    pct = int(round(vol * 100))
    run_osascript(f"set volume output volume {pct}", timeout=0.5)
    if LAST_SOURCE == "Spotify":
        run_osascript(
            f'tell application "Spotify" to set sound volume to {pct}',
            timeout=0.5,
        )


def _light_state(snap: dict[str, Any], include_artwork: bool = False) -> dict[str, Any]:
    # Artwork never rides the WS — phone fetches GET /artwork so spectrum isn't blocked.
    skip = {"artwork", "spectrum"}
    return {k: v for k, v in snap.items() if k not in skip}


def execute_command(action: str, value: Any, value_ms: Any) -> None:
    global _os_cmd_seq
    snap = STORE.apply_local_control(action, value=value, value_ms=value_ms)
    HUB.broadcast_obj({"type": "state", **_light_state(snap)})
    with _os_cmd_lock:
        _os_cmd_seq += 1
        seq = _os_cmd_seq
    threading.Thread(
        target=_run_os_command,
        args=(seq, action, value, value_ms),
        daemon=True,
    ).start()


def _run_os_command(seq: int, action: str, value: Any, value_ms: Any) -> None:
    with _os_exec_lock:
        if action == "volume":
            with _os_cmd_lock:
                if seq != _os_cmd_seq:
                    return
        system = platform.system()
        try:
            if action == "playPause":
                if system == "Darwin":
                    cmd_play_pause_macos()
                elif system == "Linux" and shutil.which("playerctl"):
                    subprocess.run(["playerctl", "play-pause"], check=False, timeout=1.0)
            elif action == "next":
                if system == "Darwin":
                    cmd_next_macos()
                elif system == "Linux" and shutil.which("playerctl"):
                    subprocess.run(["playerctl", "next"], check=False, timeout=1.0)
            elif action == "prev":
                if system == "Darwin":
                    cmd_prev_macos()
                elif system == "Linux" and shutil.which("playerctl"):
                    subprocess.run(["playerctl", "previous"], check=False, timeout=1.0)
            elif action == "seek" and value_ms is not None:
                if system == "Darwin":
                    cmd_seek_macos(int(value_ms) / 1000.0)
                elif system == "Linux" and shutil.which("playerctl"):
                    subprocess.run(
                        ["playerctl", "position", str(int(value_ms) / 1000.0)],
                        check=False,
                        timeout=1.0,
                    )
            elif action == "volume" and value is not None:
                if system == "Darwin":
                    cmd_volume_macos(float(value))
                elif system == "Linux" and shutil.which("playerctl"):
                    subprocess.run(
                        ["playerctl", "volume", str(float(value))],
                        check=False,
                        timeout=1.0,
                    )
        except Exception as exc:  # noqa: BLE001 — command best-effort
            print(f"[bridge] command error: {action}: {exc}", file=sys.stderr)


def handle_cmd_payload(data: dict[str, Any]) -> tuple[int, dict[str, Any]]:
    action = str(data.get("action") or "")
    if action not in VALID_ACTIONS:
        return 400, {"error": f"unknown action: {action}"}
    execute_command(action, data.get("value"), data.get("valueMs"))
    return 200, {"ok": True}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "AwesomeTimeBridge/2.0"

    def log_message(self, fmt: str, *args: Any) -> None:
        # Keep access log quiet-ish; still show path for debugging.
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _send_json(self, code: int, obj: Any) -> None:
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self) -> None:  # noqa: N802
        self._send_json(200, {"ok": True})

    def do_GET(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        if path == "/ws" or (
            path in ("/", "/ws")
            and (self.headers.get("Upgrade", "").lower() == "websocket")
        ):
            self._try_websocket()
            return
        if path in ("/", "/health"):
            self._send_json(
                200,
                {
                    "ok": True,
                    "app": "awesome-time-bridge",
                    "name": _bridge_name(),
                    "port": int(getattr(self.server, "bridge_port", 0) or 0),
                    "ws": "/ws",
                    "artwork": "/artwork",
                    "clients": HUB.count,
                },
            )
        elif path == "/state":
            self._send_json(200, _light_state(STORE.snapshot()))
        elif path == "/artwork":
            self._send_json(200, {"artwork": STORE.artwork_only()})
        elif path == "/ws" and self.headers.get("Upgrade", "").lower() != "websocket":
            # browser opened /ws without upgrade — explain
            self._send_json(426, {"error": "WebSocket Upgrade required", "path": "/ws"})
        else:
            self._send_json(404, {"error": "not found"})

    def _try_websocket(self) -> None:
        key = self.headers.get("Sec-WebSocket-Key")
        upgrade = (self.headers.get("Upgrade") or "").lower()
        if not key or upgrade != "websocket":
            self._send_json(426, {"error": "WebSocket Upgrade required"})
            return
        accept = _ws_accept_key(key)
        # Echo the client's subprotocol when present (Dart requests awesome-time).
        req_proto = (self.headers.get("Sec-WebSocket-Protocol") or "").strip()
        proto_header = ""
        if req_proto:
            # Accept the first token only.
            first = req_proto.split(",")[0].strip()
            if first and all(c.isalnum() or c in "-_" for c in first):
                proto_header = f"Sec-WebSocket-Protocol: {first}\r\n"
        try:
            self.wfile.write(
                (
                    "HTTP/1.1 101 Switching Protocols\r\n"
                    "Upgrade: websocket\r\n"
                    "Connection: Upgrade\r\n"
                    f"Sec-WebSocket-Accept: {accept}\r\n"
                    f"{proto_header}"
                    "\r\n"
                ).encode("ascii")
            )
            self.wfile.flush()
        except OSError:
            return

        # Hijack the TCP socket for the WS session (thread-per-connection).
        client = WSClient(self.connection)
        try:
            handle_ws_connection(client)
        finally:
            # Prevent BaseHTTPRequestHandler from closing a shared lifecycle twice.
            self.close_connection = True

    def do_POST(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        if path != "/cmd":
            self._send_json(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(length) if length else b"{}"
            data = json.loads(raw.decode("utf-8") or "{}")
            code, body = handle_cmd_payload(data)
            self._send_json(code, body)
        except json.JSONDecodeError as exc:
            self._send_json(400, {"error": f"bad json: {exc}"})
        except Exception as exc:  # noqa: BLE001
            self._send_json(500, {"error": str(exc)})


def _artwork_data_url(raw: str) -> str:
    if not raw:
        return ""
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, dict):
            art = parsed.get("artworkData") or parsed.get("artwork") or ""
        else:
            art = ""
    except json.JSONDecodeError:
        kv = _parse_kv_output(raw)
        art = str(kv.get("artworkData") or kv.get("artwork") or "")
    if not isinstance(art, str) or not art:
        return ""
    if art.startswith("data:"):
        return art
    cleaned = "".join(art.split())
    if cleaned and len(cleaned) > 32:
        return f"data:image/jpeg;base64,{cleaned}"
    return ""


def fetch_artwork_macos() -> str:
    raw = nowplaying_cli(["get", "--json", "artworkData"], timeout=1.6)
    return _artwork_data_url(raw or "")


def artwork_poller() -> None:
    last_key: tuple[Any, ...] = ()
    while True:
        try:
            if platform.system() == "Darwin":
                snap = STORE.snapshot()
                key = (snap.get("title"), snap.get("artist"), snap.get("album"))
                if key != last_key:
                    last_key = key
                    art = fetch_artwork_macos() if snap.get("title") else ""
                    if STORE.set_artwork(art) and HUB.count:
                        HUB.broadcast_obj({"type": "art", "seq": STORE.snapshot().get("seq", 0)})
        except Exception as exc:  # noqa: BLE001
            print(f"[bridge] artwork poll error: {exc}", file=sys.stderr)
        time.sleep(0.4)


def _audio_tap_bin() -> Path:
    return Path(__file__).resolve().parent / "audio_tap"


def ensure_audio_tap_binary() -> Optional[Path]:
    if platform.system() != "Darwin":
        return None
    src = Path(__file__).resolve().parent / "audio_tap.swift"
    dest = _audio_tap_bin()
    if not src.exists():
        return dest if dest.exists() else None
    if dest.exists() and dest.stat().st_mtime >= src.stat().st_mtime:
        return dest
    swiftc = shutil.which("swiftc")
    if not swiftc:
        print("[bridge] swiftc not found — cannot build audio tap", file=sys.stderr)
        return dest if dest.exists() else None
    print("[bridge] compiling system-audio FFT tap…", file=sys.stderr)
    proc = subprocess.run(
        [
            swiftc,
            "-O",
            "-parse-as-library",
            "-o",
            str(dest),
            str(src),
            "-framework",
            "ScreenCaptureKit",
            "-framework",
            "Accelerate",
            "-framework",
            "CoreMedia",
            "-framework",
            "AVFoundation",
        ],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        print(f"[bridge] audio tap compile failed:\n{proc.stderr}", file=sys.stderr)
        return dest if dest.exists() else None
    try:
        dest.chmod(dest.stat().st_mode | 0o111)
    except OSError:
        pass
    return dest


def audio_tap_loop() -> None:
    """Read 32 FFT bands from the system-audio tap into the store only.

    Network I/O lives in spectrum_pusher so a slow client cannot stall
    the stdout reader (that was the stutter source).
    """
    while True:
        if platform.system() != "Darwin":
            time.sleep(5)
            continue
        binp = ensure_audio_tap_binary()
        if binp is None or not binp.exists():
            time.sleep(8)
            continue
        print(
            "[bridge] starting system-audio tap (needs Screen Recording permission)",
            file=sys.stderr,
        )
        try:
            proc = subprocess.Popen(
                [str(binp)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,
            )
        except OSError as exc:
            print(f"[bridge] audio tap launch failed: {exc}", file=sys.stderr)
            time.sleep(8)
            continue

        def _stderr() -> None:
            assert proc.stderr is not None
            for line in proc.stderr:
                print(f"[audio-tap] {line.rstrip()}", file=sys.stderr)

        threading.Thread(target=_stderr, daemon=True).start()
        try:
            assert proc.stdout is not None
            for line in proc.stdout:
                line = line.strip()
                if not line.startswith("s "):
                    continue
                parts = line.split()[1:]
                try:
                    bands = [float(x) for x in parts]
                except ValueError:
                    continue
                if len(bands) < 8:
                    continue
                STORE.set_spectrum(bands)
        except Exception as exc:  # noqa: BLE001
            print(f"[bridge] audio tap read error: {exc}", file=sys.stderr)
        rc = proc.poll()
        try:
            proc.kill()
        except OSError:
            pass
        if rc not in (None, 0):
            print(
                "[bridge] audio tap exited — 系统设置 → 隐私与安全性 → 屏幕录制，允许终端后重启 bridge",
                file=sys.stderr,
            )
            time.sleep(12)
        else:
            time.sleep(2)


SPECTRUM_PUSH_HZ = 50.0


def spectrum_pusher() -> None:
    """Deadline-based sample-and-hold push at a fixed rate.

    No wall-clock 10ms polling (that quantized periods to ~40ms and left
    50–75ms gaps). Always send the latest store — never skip "unchanged"
    keys (that stalled the bar animation on stable spectra).
    """
    interval = 1.0 / SPECTRUM_PUSH_HZ
    next_t = time.perf_counter()
    print(f"[bridge] spectrum pusher {SPECTRUM_PUSH_HZ:.0f}Hz binary", file=sys.stderr)
    while True:
        next_t += interval
        now = time.perf_counter()
        if next_t < now - 0.05:
            # Fell far behind (laptop sleep / GC) — realign, don't burst.
            next_t = now + interval
        delay = next_t - now
        if delay > 0:
            time.sleep(delay)
        try:
            if not HUB.count:
                next_t = time.perf_counter()
                continue
            HUB.broadcast_spectrum(STORE.spectrum_copy())
        except Exception as exc:  # noqa: BLE001
            print(f"[bridge] spectrum push error: {exc}", file=sys.stderr)


def poller(interval: float) -> None:
    print(f"[bridge] poller every {interval:.2f}s", file=sys.stderr)
    last_meta_json = ""
    global LAST_SOURCE
    while True:
        started = time.time()
        try:
            snap_cap = capture()
            changed = STORE.update_from_capture(snap_cap)
            snap = STORE.snapshot()
            LAST_SOURCE = str(snap.get("source") or LAST_SOURCE)
            if changed:
                # Metadata / seek — push ASAP (position pusher handles cadence).
                light = _light_state(snap)
                meta = {
                    k: light.get(k)
                    for k in (
                        "playing",
                        "title",
                        "artist",
                        "album",
                        "source",
                        "durationMs",
                    )
                }
                last_meta_json = json.dumps(meta, ensure_ascii=False, sort_keys=True)
                if HUB.count:
                    HUB.broadcast_obj({"type": "state", **light})
            else:
                # Detect meta-only changes without requiring a full push here.
                light = _light_state(snap)
                meta = {
                    k: light.get(k)
                    for k in (
                        "playing",
                        "title",
                        "artist",
                        "album",
                        "source",
                        "durationMs",
                    )
                }
                meta_json = json.dumps(meta, ensure_ascii=False, sort_keys=True)
                if meta_json != last_meta_json:
                    last_meta_json = meta_json
                    if HUB.count:
                        HUB.broadcast_obj({"type": "state", **light})
        except Exception as exc:  # noqa: BLE001
            print(f"[bridge] poll error: {exc}", file=sys.stderr)
        elapsed = time.time() - started
        time.sleep(max(0.02, interval - elapsed))


def state_pusher() -> None:
    """Independent of capture() so a slow AppleScript never stalls WS state."""
    last_push = 0.0
    print(
        f"[bridge] state pusher every {POSITION_PUSH_INTERVAL_S}s",
        file=sys.stderr,
    )
    while True:
        try:
            if HUB.count:
                now = time.time()
                if (now - last_push) + 1e-9 >= POSITION_PUSH_INTERVAL_S:
                    light = _light_state(STORE.snapshot())
                    HUB.broadcast_obj({"type": "state", **light})
                    last_push = now
        except Exception as exc:  # noqa: BLE001
            print(f"[bridge] state push error: {exc}", file=sys.stderr)
        time.sleep(0.1)


def lan_ips() -> list[str]:
    import socket

    ips: list[str] = []
    try:
        hostname = socket.gethostname()
        ips.append(socket.gethostbyname(hostname))
    except Exception:
        pass
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ips.append(s.getsockname()[0])
        s.close()
    except Exception:
        pass
    seen = set()
    out = []
    for ip in ips:
        if ip and ip not in seen and not ip.startswith("127."):
            seen.add(ip)
            out.append(ip)
    return out


def _bridge_name() -> str:
    import socket

    try:
        return socket.gethostname() or "Awesome Time Bridge"
    except Exception:
        return "Awesome Time Bridge"


def discovery_loop(discovery_port: int, http_port: int) -> None:
    """Answer UDP probes so the phone can list every bridge on the LAN."""
    import socket

    name = _bridge_name()
    reply = json.dumps(
        {
            "app": "awesome-time-bridge",
            "name": name,
            "port": http_port,
            "ws": "/ws",
        },
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        except OSError:
            pass
        sock.bind(("", discovery_port))
        sock.settimeout(1.0)
    except OSError as exc:
        print(f"[bridge] discovery bind failed on {discovery_port}: {exc}", file=sys.stderr)
        return

    print(
        f"[bridge] discovery udp://{discovery_port} ({name})",
        file=sys.stderr,
    )
    while True:
        try:
            data, addr = sock.recvfrom(2048)
        except socket.timeout:
            continue
        except OSError:
            break
        try:
            text = data.decode("utf-8", errors="ignore").strip()
        except Exception:
            continue
        if not text:
            continue
        # Accept bare magic or small JSON probes containing the magic.
        if text == DISCOVERY_MAGIC or (
            len(text) < 256 and DISCOVERY_MAGIC in text
        ):
            try:
                sock.sendto(reply, addr)
            except OSError:
                pass
    try:
        sock.close()
    except OSError:
        pass


def main() -> int:
    parser = argparse.ArgumentParser(description="Awesome Time LAN bridge")
    parser.add_argument("--host", default="0.0.0.0", help="bind address")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument(
        "--discovery-port",
        type=int,
        default=DEFAULT_DISCOVERY_PORT,
        help="UDP port for LAN device discovery (default 8766)",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=0.25,
        help="poll seconds (default 0.25; progress is pushed over WS every 1s)",
    )
    args = parser.parse_args()

    print("Awesome Time Bridge", file=sys.stderr)
    print(f"platform: {platform.system()} {platform.release()}", file=sys.stderr)
    if shutil.which("nowplaying-cli"):
        print("nowplaying-cli: found", file=sys.stderr)
    else:
        print(
            "nowplaying-cli: not found — browser/系统级媒体请安装: brew install nowplaying-cli",
            file=sys.stderr,
        )
    print(
        "transport: WebSocket /ws (state ~0.5s) + HTTP fallback /state /cmd + UDP discovery",
        file=sys.stderr,
    )

    th = threading.Thread(target=poller, args=(args.interval,), daemon=True)
    th.start()
    threading.Thread(target=state_pusher, daemon=True).start()
    if platform.system() == "Darwin":
        threading.Thread(target=spectrum_pusher, daemon=True).start()
    threading.Thread(target=artwork_poller, daemon=True).start()
    threading.Thread(target=audio_tap_loop, daemon=True).start()
    threading.Thread(
        target=discovery_loop,
        args=(args.discovery_port, args.port),
        daemon=True,
    ).start()

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    server.daemon_threads = True
    server.bridge_port = args.port  # type: ignore[attr-defined]
    ips = lan_ips()
    print(f"listening on {args.host}:{args.port}", file=sys.stderr)
    print(f"discovery udp:{args.discovery_port}", file=sys.stderr)
    for ip in ips or ["<ip>"]:
        print(f"  → ws://{ip}:{args.port}/ws", file=sys.stderr)
        print(f"  → http://{ip}:{args.port}", file=sys.stderr)
    print("在副手机上自动搜索设备，或填入上面任一地址即可连接。", file=sys.stderr)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[bridge] bye", file=sys.stderr)
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
