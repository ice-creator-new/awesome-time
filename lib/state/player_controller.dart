import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/media_state.dart';
import '../services/bridge_client.dart';
import '../ui/artwork_palette.dart';
import 'playback_clock.dart';

class PlayerController extends ChangeNotifier {
  PlayerController();

  final BridgeClient client = BridgeClient();
  final PlaybackClock clock = PlaybackClock();

  /// Navigator hooks set by the shell (main.dart).
  VoidCallback? onConnected;
  VoidCallback? onDisconnected;

  MediaState state = emptyMediaState;
  BridgeStatus status = BridgeStatus.idle;
  String? statusMessage;
  bool demoMode = false;
  bool everConnected = false;
  String host = '';

  DateTime? _lastRemoteAt;
  DateTime? _holdRemoteUntil;
  Timer? _volumeDebounce;
  Uint8List? artworkBytes;
  List<Color> palette = ArtworkPalette.fallback;
  String _artIdentity = '';
  final ValueNotifier<List<double>> spectrum = ValueNotifier<List<double>>(
    const <double>[],
  );

  String get statusLabel {
    if (demoMode) return '演示模式';
    return switch (status) {
      BridgeStatus.idle => '未连接',
      BridgeStatus.connecting => '连接中…',
      BridgeStatus.connected => '已连接',
      BridgeStatus.error => '连接异常',
    };
  }

  bool get isConnected =>
      demoMode ||
      status == BridgeStatus.connected ||
      status == BridgeStatus.connecting;

  Future<void> connect(String rawHost) async {
    await disconnect(keepNav: true);
    demoMode = false;
    host = rawHost.trim();
    everConnected = false;
    _lastRemoteAt = null;
    status = BridgeStatus.connecting;
    statusMessage = null;
    notifyListeners();

    await client.connect(
      host,
      onState: _onRemoteState,
      previousState: () => state,
      onSpectrum: (bands) => spectrum.value = bands,
      onArt: _pullArtwork,
      onStatus: _onStatus,
    );
  }

  void _onRemoteState(MediaState remote) {
    final now = DateTime.now();
    _lastRemoteAt = now;

    final trackChanged =
        state.title != remote.title ||
        state.source != remote.source ||
        state.updatedAtMs == 0;

    final holding = _holdRemoteUntil != null && now.isBefore(_holdRemoteUntil!);

    if (!holding || trackChanged) {
      clock.applyRemote(
        positionMs: remote.positionMs,
        durationMs: remote.durationMs,
        playing: remote.playing,
        force: trackChanged,
      );
    } else {
      clock.durationMs = remote.durationMs;
    }

    var volume = remote.volume;
    if (volume <= 0 && state.volume > 0 && !trackChanged) {
      volume = state.volume;
    }

    final playing = (holding && !trackChanged) ? state.playing : remote.playing;

    final visualChanged =
        trackChanged ||
        state.playing != playing ||
        (state.volume - volume).abs() > 0.008 ||
        state.artist != remote.artist;

    state = remote.copyWith(
      playing: playing,
      positionMs: clock.positionMs,
      volume: volume,
      updatedAtMs: now.millisecondsSinceEpoch,
    );

    if (!everConnected && status == BridgeStatus.connected) {
      everConnected = true;
    }

    if (trackChanged) {
      _pullArtwork();
    }
    if (visualChanged || trackChanged) {
      notifyListeners();
    }
  }

  void _onStatus(BridgeStatus next, String? message) {
    if (next == BridgeStatus.error &&
        status == BridgeStatus.connected &&
        DateTime.now().difference(
              _lastRemoteAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            ) <
            const Duration(seconds: 3)) {
      return;
    }

    final wasConnected = everConnected;
    status = next;
    if (next == BridgeStatus.connected) {
      statusMessage = null;
      everConnected = true;
    } else if (message != null) {
      statusMessage = message;
    }

    if (wasConnected &&
        everConnected &&
        next == BridgeStatus.error &&
        statusMessage != null &&
        _staleBeyondGrace()) {
      status = BridgeStatus.error;
      notifyListeners();
      _teardownSession(nav: true);
      return;
    }

    notifyListeners();
  }

  bool _staleBeyondGrace() {
    final last = _lastRemoteAt;
    if (last == null) return true;
    return DateTime.now().difference(last) > const Duration(seconds: 4);
  }

  Future<void> disconnect({bool keepNav = false}) async {
    final hadSession = everConnected || demoMode;
    demoMode = false;
    _demoTimer?.cancel();
    _demoTimer = null;
    _volumeDebounce?.cancel();
    _lastRemoteAt = null;
    everConnected = false;
    await client.disconnect();
    status = BridgeStatus.idle;
    statusMessage = null;
    state = emptyMediaState;
    artworkBytes = null;
    palette = ArtworkPalette.fallback;
    _artIdentity = '';
    spectrum.value = const <double>[];
    host = '';
    notifyListeners();
    if (hadSession && !keepNav) {
      onDisconnected?.call();
    }
  }

  Future<void> leaveToConnect() async {
    final hadSession = everConnected || demoMode || status != BridgeStatus.idle;
    demoMode = false;
    _demoTimer?.cancel();
    _demoTimer = null;
    _volumeDebounce?.cancel();
    _lastRemoteAt = null;
    everConnected = false;
    await client.disconnect();
    status = BridgeStatus.idle;
    statusMessage = null;
    state = emptyMediaState;
    artworkBytes = null;
    palette = ArtworkPalette.fallback;
    _artIdentity = '';
    spectrum.value = const <double>[];
    host = '';
    notifyListeners();
    if (hadSession) {
      onDisconnected?.call();
    }
  }

  void _teardownSession({required bool nav}) {
    _demoTimer?.cancel();
    _demoTimer = null;
    _lastRemoteAt = null;
    everConnected = false;
    client.disconnect();
    status = BridgeStatus.error;
    demoMode = false;
    if (nav) {
      onDisconnected?.call();
    }
  }

  Future<void> playPause() => _cmd(action: 'playPause');
  Future<void> next() => _cmd(action: 'next');
  Future<void> prev() => _cmd(action: 'prev');

  Future<void> seekFraction(double f) async {
    if (!state.hasDuration) return;
    final ms = (f.clamp(0.0, 1.0) * state.durationMs).round();
    clock.durationMs = state.durationMs;
    clock.seek(ms);
    _holdRemoteUntil = DateTime.now().add(const Duration(milliseconds: 700));
    state = state.copyWith(
      positionMs: ms,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    notifyListeners();
    await _cmd(action: 'seek', valueMs: ms);
  }

  Future<void> setVolume(double v) async {
    final vol = v.clamp(0.0, 1.0);
    state = state.copyWith(
      volume: vol,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    notifyListeners();
    _volumeDebounce?.cancel();
    _volumeDebounce = Timer(const Duration(milliseconds: 70), () {
      _cmd(action: 'volume', value: vol);
    });
  }

  Future<void> _cmd({
    required String action,
    double? value,
    int? valueMs,
  }) async {
    if (demoMode) {
      _demoCommand(action, value: value, valueMs: valueMs);
      return;
    }
    if (status != BridgeStatus.connected && status != BridgeStatus.error) {
      return;
    }

    if (action == 'playPause' || action == 'next' || action == 'prev') {
      _holdRemoteUntil = DateTime.now().add(const Duration(milliseconds: 1400));
    }

    if (action == 'playPause') {
      final nextPlaying = !state.playing;
      clock.applyRemote(
        positionMs: clock.positionMs,
        durationMs: state.durationMs,
        playing: nextPlaying,
        force: true,
      );
      state = state.copyWith(
        playing: nextPlaying,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      notifyListeners();
    }

    try {
      await client.send(action: action, value: value, valueMs: valueMs);
    } catch (e) {
      statusMessage = e.toString();
      if (action == 'playPause') {
        clock.applyRemote(
          positionMs: clock.positionMs,
          durationMs: state.durationMs,
          playing: !state.playing,
          force: true,
        );
        state = state.copyWith(
          playing: !state.playing,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
      }
      notifyListeners();
    }
  }

  Future<void> _pullArtwork() async {
    if (demoMode) return;
    final key = '${state.title}|${state.album}|${state.artist}';
    try {
      final dataUrl = await client.fetchArtwork();
      final identity = '$key|${dataUrl.length}';
      if (identity == _artIdentity) return;
      _artIdentity = identity;
      final bytes = decodeArtworkBytes(dataUrl);
      if (bytes != null) {
        artworkBytes = bytes;
        palette = await ArtworkPalette.fromBytes(bytes);
      } else {
        artworkBytes = null;
        palette = ArtworkPalette.fallback;
      }
      notifyListeners();
    } catch (_) {}
  }

  // ---- demo mode (no bridge required) ----
  Timer? _demoTimer;
  final _demoTracks = const <(String, String, String, Duration)>[
    ('夜空中最亮的星', '逃跑计划', '世界', Duration(minutes: 4, seconds: 12)),
    (
      'Space Song',
      'Beach House',
      'Depression Cherry',
      Duration(minutes: 5, seconds: 21),
    ),
    ('起风了', '买辣椒也用券', '起风了', Duration(minutes: 5, seconds: 26)),
    (
      'Weightless',
      'Marconi Union',
      'Weightless',
      Duration(minutes: 8, seconds: 8),
    ),
  ];
  int _demoIndex = 0;

  void startDemo() {
    demoMode = true;
    host = 'demo';
    status = BridgeStatus.connected;
    statusMessage = null;
    everConnected = true;
    _demoIndex = 0;
    _loadDemoTrack(positionMs: 42000);
    _demoTimer?.cancel();
    _demoTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!demoMode) return;
      if (!state.playing) return;
      if (clock.positionMs >= state.durationMs && state.durationMs > 0) {
        _demoIndex = (_demoIndex + 1) % _demoTracks.length;
        _loadDemoTrack(positionMs: 0);
      }
    });
    notifyListeners();
  }

  void _loadDemoTrack({required int positionMs}) {
    final t = _demoTracks[_demoIndex];
    palette = ArtworkPalette.forDemo(_demoIndex);
    artworkBytes = null;
    _artIdentity = 'demo-$_demoIndex';
    state = MediaState(
      playing: true,
      title: t.$1,
      artist: t.$2,
      album: t.$3,
      source: 'Demo Player',
      positionMs: positionMs,
      durationMs: t.$4.inMilliseconds,
      volume: 0.62,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    clock.applyRemote(
      positionMs: positionMs,
      durationMs: t.$4.inMilliseconds,
      playing: true,
      force: true,
    );
    notifyListeners();
  }

  void _demoCommand(String action, {double? value, int? valueMs}) {
    switch (action) {
      case 'playPause':
        final nextPlaying = !state.playing;
        clock.applyRemote(
          positionMs: clock.positionMs,
          durationMs: state.durationMs,
          playing: nextPlaying,
          force: true,
        );
        state = state.copyWith(
          playing: nextPlaying,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
      case 'next':
        _demoIndex = (_demoIndex + 1) % _demoTracks.length;
        _loadDemoTrack(positionMs: 0);
        return;
      case 'prev':
        _demoIndex = (_demoIndex - 1 + _demoTracks.length) % _demoTracks.length;
        _loadDemoTrack(positionMs: 0);
        return;
      case 'seek':
        if (valueMs != null) {
          clock.seek(valueMs);
          state = state.copyWith(
            positionMs: valueMs.clamp(0, state.durationMs),
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          );
        }
      case 'volume':
        if (value != null) {
          state = state.copyWith(
            volume: value.clamp(0.0, 1.0),
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          );
        }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    _volumeDebounce?.cancel();
    spectrum.dispose();
    client.disconnect();
    super.dispose();
  }
}

Uint8List? decodeArtworkBytes(String dataUrl) {
  if (dataUrl.isEmpty) return null;
  final comma = dataUrl.indexOf(',');
  final b64 = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
  try {
    final cleaned = b64.replaceAll(RegExp(r'\s'), '');
    if (cleaned.isEmpty) return null;
    return base64Decode(cleaned);
  } catch (_) {
    return null;
  }
}
