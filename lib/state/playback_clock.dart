/// Wall-clock playhead. The UI interpolates locally so progress is 60fps-smooth
/// even when the bridge only sends sparse corrections.
class PlaybackClock {
  int durationMs = 0;
  bool playing = false;

  int _baseMs = 0;
  int _baseWallMs = 0;

  static const _snapJumpMs = 900;
  static const _ignoreErrorMs = 80;

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
    final wasPlaying = this.playing;
    final predicted = positionAt(nowMs: now);
    this.durationMs = durationMs;

    if (force) {
      _baseMs = positionMs < 0 ? 0 : positionMs;
      _baseWallMs = now;
      this.playing = playing;
      return;
    }

    final jump = (positionMs - predicted).abs();

    if (playing != wasPlaying) {
      _baseMs = predicted;
      _baseWallMs = now;
      this.playing = playing;
      return;
    }

    this.playing = playing;

    if (jump > _snapJumpMs) {
      _baseMs = positionMs < 0 ? 0 : positionMs;
      _baseWallMs = now;
      return;
    }

    if (jump > _ignoreErrorMs) {
      _baseMs = predicted + ((positionMs - predicted) * 0.25).round();
      _baseWallMs = now;
    }
  }
}
