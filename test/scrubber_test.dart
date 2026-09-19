import 'package:awesome_time/state/playback_clock.dart';
import 'package:awesome_time/ui/now_playing_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('seek fill is visibly wide at mid progress', (tester) async {
    final clock = PlaybackClock();
    clock.applyRemote(
      positionMs: 50000,
      durationMs: 100000,
      playing: true,
      force: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: NowPlayingScrubber(
              clock: clock,
              enabled: true,
              onSeek: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final fill = tester.getSize(find.byKey(const Key('seek-fill')));
    expect(fill.width, greaterThan(80));
    expect(fill.height, greaterThan(2));
  });
}
