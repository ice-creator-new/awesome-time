/// Wall-clock playhead. Between WS samples the UI interpolates for smoothness;
/// each remote sample is treated as authoritative (server drives progress).
class PlaybackClock {
  int durationMs = 0;
  bool playing = false;

  int _baseMs = 0;
  int _baseWallMs = 0;

  int positionAt({int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    var pos = _baseMs;
    if (playing) {
      pos += now - _baseWallMs;
    }
    if (durationMs > 0) {
      if (pos < 0) return 0;
      if (pos > durationMs) return durationMs;
    }
    return pos < 0 ? 0 : pos;
  }

  double progressAt({int? nowMs}) {
    if (durationMs <= 0) return 0;
    return (positionAt(nowMs: nowMs) / durationMs).clamp(0.0, 1.0);
  }

  int get positionMs => positionAt();
  double get progress => progressAt();

  void seek(int ms, {int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    _baseMs = durationMs > 0 ? ms.clamp(0, durationMs) : (ms < 0 ? 0 : ms);
    _baseWallMs = now;
  }

  void applyRemote({
    required int positionMs,
    required int durationMs,
    required bool playing,
    required bool force,
    int? nowMs,
  }) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    this.durationMs = durationMs;
    var next = positionMs < 0 ? 0 : positionMs;
    if (durationMs > 0 && next > durationMs) next = durationMs;
    // Server sample is authoritative — both first paint (force) and later
    // corrections rebase here so local wall clock cannot drift away from WS.
    _baseMs = next;
    _baseWallMs = now;
    this.playing = playing;
  }
}
