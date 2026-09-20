#!/usr/bin/env python3
"""Targeted tests for the bridge artwork path.

Run:  python3 -m unittest bridge.test_awesome_bridge -v
(or:  python3 bridge/test_awesome_bridge.py)

Covers the fix for "封面在客户端显示不了": the bridge used to source covers
only from nowplaying-cli, so without that optional helper (and without it on
PATH) /artwork returned "" forever.
"""

from __future__ import annotations

import base64
import importlib.util
import json
import unittest
from pathlib import Path
from unittest import mock

_MOD_PATH = Path(__file__).resolve().parent / "awesome_bridge.py"
_spec = importlib.util.spec_from_file_location("awesome_bridge", _MOD_PATH)
assert _spec and _spec.loader
bridge = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bridge)

JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 256
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 256
JPEG_B64 = base64.b64encode(JPEG).decode("ascii")
PNG_B64 = base64.b64encode(PNG).decode("ascii")


class ImageSniffTests(unittest.TestCase):
    def test_sniffs_real_types(self):
        self.assertEqual(bridge._image_mime(JPEG), "image/jpeg")
        self.assertEqual(bridge._image_mime(PNG), "image/png")
        self.assertEqual(bridge._image_mime(b"GIF89a" + b"\x00" * 32), "image/gif")
        self.assertEqual(
            bridge._image_mime(b"RIFF\x00\x00\x00\x00WEBP" + b"\x00" * 32),
            "image/webp",
        )
        self.assertEqual(bridge._image_mime(b"BM" + b"\x00" * 32), "image/bmp")

    def test_rejects_non_images(self):
        self.assertEqual(bridge._image_mime(b"not an image at all"), "")
        self.assertEqual(bridge._image_mime(b""), "")
        # Music's `data` property is legacy PICT — sniffing must not claim it.
        pict = b"\x00" * 512 + b"\x00\x11\x02\xff" + b"\x00" * 64
        self.assertEqual(bridge._image_mime(pict), "")

    def test_data_url_uses_real_mime_and_drops_tiny_payloads(self):
        url = bridge._data_url_from_bytes(PNG)
        self.assertTrue(url.startswith("data:image/png;base64,"))
        self.assertEqual(bridge._data_url_from_bytes(b"\xff\xd8\xff" + b"\x00" * 8), "")
        self.assertEqual(bridge._data_url_from_bytes(b"garbage" * 40), "")


class ArtworkDataUrlTests(unittest.TestCase):
    def test_nowplaying_cli_json_artwork_data(self):
        raw = json.dumps({"artworkData": JPEG_B64})
        self.assertEqual(
            bridge._artwork_data_url(raw), f"data:image/jpeg;base64,{JPEG_B64}"
        )

    def test_raw_mediaremote_long_key(self):
        raw = json.dumps({"kMRMediaRemoteNowPlayingInfoArtworkData": PNG_B64})
        self.assertEqual(
            bridge._artwork_data_url(raw), f"data:image/png;base64,{PNG_B64}"
        )

    def test_key_value_output(self):
        raw = f"artworkData: {JPEG_B64}"
        self.assertEqual(
            bridge._artwork_data_url(raw), f"data:image/jpeg;base64,{JPEG_B64}"
        )

    def test_existing_data_url_passes_through(self):
        url = "data:image/png;base64," + "A" * 200
        self.assertEqual(bridge._artwork_data_url(url), url)

    def test_short_data_url_rejected(self):
        self.assertEqual(bridge._artwork_data_url("data:image/png;base64,AAAA"), "")

    def test_byte_description_is_rejected(self):
        # nowplaying-cli prints "<...>" style descriptions when there is no art.
        raw = json.dumps({"artworkData": "<<data 0x1f8b 4096 bytes>>"})
        self.assertEqual(bridge._artwork_data_url(raw), "")

    def test_empty_and_missing(self):
        self.assertEqual(bridge._artwork_data_url(""), "")
        self.assertEqual(bridge._artwork_data_url("{}"), "")
        self.assertEqual(bridge._artwork_data_url("not json"), "")


class FetchArtworkChainTests(unittest.TestCase):
    """The three-step chain must degrade, and must never launch Music.app."""

    def test_helper_wins_when_present(self):
        with mock.patch.object(bridge, "nowplaying_cli", return_value=json.dumps(
            {"artworkData": JPEG_B64}
        )) as helper, mock.patch.object(
            bridge, "_fetch_artwork_applescript"
        ) as script:
            self.assertTrue(bridge.fetch_artwork_macos().startswith("data:image/jpeg"))
            helper.assert_called_once()
            script.assert_not_called()

    def test_falls_back_to_music_applescript(self):
        expected = f"data:image/png;base64,{PNG_B64}"
        with mock.patch.object(bridge, "nowplaying_cli", return_value=None), \
                mock.patch.object(
                    bridge, "_fetch_artwork_applescript", return_value=expected
                ), \
                mock.patch.object(bridge, "_fetch_artwork_spotify") as spotify:
            self.assertEqual(bridge.fetch_artwork_macos(), expected)
            spotify.assert_not_called()

    def test_falls_back_to_spotify_url(self):
        expected = f"data:image/jpeg;base64,{JPEG_B64}"
        with mock.patch.object(bridge, "nowplaying_cli", return_value=None), \
                mock.patch.object(bridge, "_fetch_artwork_applescript", return_value=""), \
                mock.patch.object(bridge, "_fetch_artwork_spotify", return_value=expected):
            self.assertEqual(bridge.fetch_artwork_macos(), expected)

    def test_all_sources_empty_returns_empty(self):
        with mock.patch.object(bridge, "nowplaying_cli", return_value=None), \
                mock.patch.object(bridge, "_fetch_artwork_applescript", return_value=""), \
                mock.patch.object(bridge, "_fetch_artwork_spotify", return_value=""):
            self.assertEqual(bridge.fetch_artwork_macos(), "")

    def test_applescript_source_never_launches_music(self):
        with mock.patch.object(bridge, "_process_exists", return_value=False), \
                mock.patch.object(bridge, "run_osascript") as run:
            self.assertEqual(bridge._fetch_artwork_applescript(), "")
            run.assert_not_called()

    def test_applescript_source_reads_written_file(self):
        def fake_run(_script: str, timeout: float = 0.0) -> str:
            bridge._ARTWORK_TMP.write_bytes(PNG)
            return "OK"

        with mock.patch.object(bridge, "_process_exists", return_value=True), \
                mock.patch.object(bridge, "run_osascript", side_effect=fake_run):
            self.assertEqual(
                bridge._fetch_artwork_applescript(),
                f"data:image/png;base64,{PNG_B64}",
            )
        self.assertFalse(bridge._ARTWORK_TMP.exists(), "temp cover left behind")

    def test_applescript_script_writes_then_reports_failure(self):
        with mock.patch.object(bridge, "_process_exists", return_value=True), \
                mock.patch.object(bridge, "run_osascript", return_value="NO_ART"):
            self.assertEqual(bridge._fetch_artwork_applescript(), "")

    def test_script_prefers_raw_data_over_pict(self):
        captured = {}

        def fake_run(script: str, timeout: float = 0.0) -> str:
            captured["script"] = script
            return "NO_ART"

        with mock.patch.object(bridge, "_process_exists", return_value=True), \
                mock.patch.object(bridge, "run_osascript", side_effect=fake_run):
            bridge._fetch_artwork_applescript()
        # `data` is typed `picture` (PICT); `raw data` carries the real bytes.
        self.assertIn("raw data of artwork 1", captured["script"])
        self.assertIn("set artData to data of artwork 1", captured["script"])

    def test_pict_payload_goes_through_sips(self):
        pict = b"\x00" * 512 + b"\x00\x11\x02\xff" + b"\x00" * 64
        expected = f"data:image/jpeg;base64,{JPEG_B64}"

        def fake_run(_script: str, timeout: float = 0.0) -> str:
            bridge._ARTWORK_TMP.write_bytes(pict)
            return "OK"

        with mock.patch.object(bridge, "_process_exists", return_value=True), \
                mock.patch.object(bridge, "run_osascript", side_effect=fake_run), \
                mock.patch.object(
                    bridge, "_sips_to_data_url", return_value=expected
                ) as sips:
            self.assertEqual(bridge._fetch_artwork_applescript(), expected)
            sips.assert_called_once()
        self.assertFalse(bridge._ARTWORK_TMP.exists(), "temp cover left behind")

    def test_sips_on_missing_file_is_safe(self):
        self.assertEqual(bridge._sips_to_data_url(Path("/tmp/at-nope-xyz.bin")), "")

    def test_probe_reports_the_working_source(self):
        store = FakeStore({"title": "雨天"})
        with mock.patch.object(bridge, "STORE", store), \
                mock.patch.object(bridge, "_nowplaying_exe", return_value=None), \
                mock.patch.object(bridge, "_process_exists", return_value=True), \
                mock.patch.object(
                    bridge,
                    "_fetch_artwork_applescript",
                    return_value=f"data:image/jpeg;base64,{JPEG_B64}",
                ), \
                mock.patch.object(bridge, "_fetch_artwork_spotify", return_value=""):
            out = bridge.probe_artwork_sources()
        self.assertEqual(out["chosen"], "music-applescript")
        self.assertGreater(out["sources"]["music-applescript"]["bytes"], 0)
        self.assertTrue(out["sources"]["music-applescript"]["musicRunning"])

    def test_helper_path_finds_homebrew_binary(self):
        with mock.patch("shutil.which", side_effect=lambda _n, path=None: (
            "/opt/homebrew/bin/nowplaying-cli" if path == "/opt/homebrew/bin" else None
        )):
            self.assertEqual(
                bridge._nowplaying_exe(), "/opt/homebrew/bin/nowplaying-cli"
            )


class FakeStore:
    def __init__(self, snap: dict, art: str = "") -> None:
        self.snap = snap
        self.art = art
        self.writes: list[str] = []

    def snapshot(self) -> dict:
        return dict(self.snap, seq=1)

    def artwork_only(self) -> str:
        return self.art

    def set_artwork(self, artwork: str, artwork_url: str = "") -> bool:
        self.writes.append(artwork)
        if artwork == self.art:
            return False
        self.art = artwork
        return True


class _Stop(BaseException):
    pass


class ArtworkPollerTests(unittest.TestCase):
    """A missing cover must be retried, and a stale cover must not stick."""

    def _run_poller(self, store: FakeStore, fetches: list[str], cycles: int) -> None:
        calls = {"n": 0}

        def fake_fetch() -> str:
            calls["n"] += 1
            return fetches[min(calls["n"] - 1, len(fetches) - 1)]

        def fake_sleep(_s: float) -> None:
            calls["sleep"] = calls.get("sleep", 0) + 1
            if calls["sleep"] > cycles:
                raise _Stop

        with mock.patch.object(bridge, "STORE", store), \
                mock.patch.object(bridge, "HUB", mock.Mock(count=0)), \
                mock.patch.object(bridge.platform, "system", return_value="Darwin"), \
                mock.patch.object(bridge, "fetch_artwork_macos", side_effect=fake_fetch), \
                mock.patch.object(bridge, "ARTWORK_RETRY_S", 0.0), \
                mock.patch("time.sleep", side_effect=fake_sleep):
            with self.assertRaises(_Stop):
                bridge.artwork_poller()
        self.fetches = calls["n"]

    def test_retries_until_a_cover_appears(self):
        store = FakeStore({"title": "雨天", "artist": "孙燕姿", "album": "My Story"})
        self._run_poller(store, ["", "", "", "data:image/jpeg;base64," + JPEG_B64], 5)
        self.assertGreater(self.fetches, 1, "poller cached the miss and never retried")
        self.assertTrue(store.art.startswith("data:image/jpeg"))

    def test_stops_retrying_once_cover_is_held(self):
        store = FakeStore(
            {"title": "雨天", "artist": "孙燕姿", "album": "My Story"},
            art="data:image/jpeg;base64," + JPEG_B64,
        )
        self._run_poller(store, ["data:image/jpeg;base64," + JPEG_B64], 4)
        # One fetch on track entry, then never again while the cover is held.
        self.assertEqual(self.fetches, 1, "poller refetched a cover it already had")

    def test_new_track_without_cover_clears_the_old_one(self):
        store = FakeStore(
            {"title": "新歌", "artist": "a", "album": "b"},
            art="data:image/jpeg;base64," + JPEG_B64,
        )
        self._run_poller(store, [""], 2)
        self.assertEqual(store.art, "", "stale cover stuck to the next track")

    def test_nothing_playing_does_not_retry_forever(self):
        store = FakeStore({"title": "", "artist": "", "album": ""})
        self._run_poller(store, [""], 4)
        # No title → no fetch at all, and no spinning retry loop.
        self.assertEqual(self.fetches, 0)
        self.assertEqual(store.art, "")


class BridgeNameTests(unittest.TestCase):
    """The phone's device list must show a name a human recognises."""

    def test_prefers_computer_name_on_macos(self):
        with (
            mock.patch.object(bridge.sys, "platform", "darwin"),
            mock.patch.object(bridge.subprocess, "run") as run,
            mock.patch.object(bridge.socket, "gethostname", return_value="bogon"),
        ):
            run.return_value = mock.Mock(returncode=0, stdout="Ice的Mac mini\n")
            self.assertEqual(bridge._bridge_name(), "Ice的Mac mini")

    def test_ignores_bogon_computer_name(self):
        with (
            mock.patch.object(bridge.sys, "platform", "darwin"),
            mock.patch.object(bridge.subprocess, "run") as run,
            mock.patch.object(
                bridge.socket, "gethostname", return_value="IcedeMac-mini"
            ),
        ):
            run.return_value = mock.Mock(returncode=0, stdout="bogon\n")
            self.assertEqual(bridge._bridge_name(), "IcedeMac-mini")

    def test_scutil_failure_falls_back_to_hostname(self):
        with (
            mock.patch.object(bridge.sys, "platform", "darwin"),
            mock.patch.object(bridge.subprocess, "run", side_effect=OSError("boom")),
            mock.patch.object(bridge.socket, "gethostname", return_value="MyMac"),
        ):
            self.assertEqual(bridge._bridge_name(), "MyMac")

    def test_placeholder_hostname_without_computer_name(self):
        with (
            mock.patch.object(bridge.sys, "platform", "linux"),
            mock.patch.object(bridge.socket, "gethostname", return_value="bogon"),
        ):
            self.assertEqual(bridge._bridge_name(), "Awesome Time Bridge")

    def test_plain_hostname_is_used(self):
        with (
            mock.patch.object(bridge.sys, "platform", "linux"),
            mock.patch.object(bridge.socket, "gethostname", return_value="Mac-mini"),
        ):
            self.assertEqual(bridge._bridge_name(), "Mac-mini")


if __name__ == "__main__":
    unittest.main(verbosity=2)
