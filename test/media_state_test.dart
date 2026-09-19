import 'package:awesome_time/models/media_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light WS payload keeps previous artwork when artwork key is omitted', () {
    const previous = MediaState(
      title: 'Space Song',
      artworkDataUrl: 'data:image/jpeg;base64,abc',
      artworkUrl: 'https://example/art.jpg',
      positionMs: 1000,
      durationMs: 5000,
    );
    final next = MediaState.fromJson({
      'playing': true,
      'title': 'Space Song',
      'positionMs': 1400,
      'durationMs': 5000,
    }, previous: previous);

    expect(next.artworkDataUrl, 'data:image/jpeg;base64,abc');
    expect(next.artworkUrl, 'https://example/art.jpg');
    expect(next.positionMs, 1400);
  });

  test('explicit empty artwork on a new track clears the cover', () {
    const previous = MediaState(
      title: 'Old',
      artworkDataUrl: 'data:image/jpeg;base64,abc',
    );
    final next = MediaState.fromJson({
      'title': 'New',
      'artwork': '',
    }, previous: previous);

    expect(next.artworkDataUrl, isEmpty);
    expect(next.title, 'New');
  });
}
