import 'package:awesome_time/state/playback_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('playing clock advances with wall time instead of discrete ticks', () {
    final clock = PlaybackClock();
    clock.applyRemote(
      positionMs: 1000,
      durationMs: 10000,
      playing: true,
      force: true,
      nowMs: 5_000_000,
    );

    expect(clock.positionAt(nowMs: 5_000_000), 1000);
    expect(clock.positionAt(nowMs: 5_000_250), 1250);
    expect(clock.positionAt(nowMs: 5_001_000), 2000);
    expect(clock.progressAt(nowMs: 5_001_000), closeTo(0.2, 0.0001));
  });

  test('paused clock does not advance', () {
    final clock = PlaybackClock();
    clock.applyRemote(
      positionMs: 3000,
      durationMs: 10000,
      playing: false,
      force: true,
      nowMs: 1_000,
    );
    expect(clock.positionAt(nowMs: 1_800), 3000);
  });

  test('every remote sample rebases onto the server position', () {
    final clock = PlaybackClock();
    clock.applyRemote(
      positionMs: 2000,
      durationMs: 20000,
      playing: true,
      force: true,
      nowMs: 10_000,
    );
    // Local would have predicted 2200; server says 2240 — trust server.
    clock.applyRemote(
      positionMs: 2240,
      durationMs: 20000,
      playing: true,
      force: false,
      nowMs: 10_200,
    );
    expect(clock.positionAt(nowMs: 10_200), 2240);
    expect(clock.positionAt(nowMs: 10_700), 2740);
  });

  test('large remote jump is treated as a real seek', () {
    final clock = PlaybackClock();
    clock.applyRemote(
      positionMs: 2000,
      durationMs: 20000,
      playing: true,
      force: true,
      nowMs: 10_000,
    );
    clock.applyRemote(
      positionMs: 8000,
      durationMs: 20000,
      playing: true,
      force: false,
      nowMs: 10_100,
    );
    expect(clock.positionAt(nowMs: 10_100), 8000);
  });

  test('play/pause adopts the remote sample position', () {
    final clock = PlaybackClock();
    clock.applyRemote(
      positionMs: 1000,
      durationMs: 20000,
      playing: true,
      force: true,
      nowMs: 0,
    );
    // Server paused at 1000 even though local had already run to 1500.
    clock.applyRemote(
      positionMs: 1000,
      durationMs: 20000,
      playing: false,
      force: false,
      nowMs: 500,
    );
    expect(clock.positionAt(nowMs: 500), 1000);
    expect(clock.positionAt(nowMs: 900), 1000);
  });

  test('position is clamped to duration', () {
    final clock = PlaybackClock();
    clock.applyRemote(
      positionMs: 25_000,
      durationMs: 20_000,
      playing: false,
      force: true,
      nowMs: 0,
    );
    expect(clock.positionMs, 20_000);
  });
}
