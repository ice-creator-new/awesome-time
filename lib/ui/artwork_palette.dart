import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Two dominant colors from album art, darkened for a flowing backdrop.
class ArtworkPalette {
  static const fallback = <Color>[
    Color(0xFF2A1838),
    Color(0xFF0E2A3A),
  ];

  static const _demo = <List<Color>>[
    [Color(0xFF3A1E68), Color(0xFF12102A)],
    [Color(0xFF6A2840), Color(0xFF1A0C18)],
    [Color(0xFF1E4A3C), Color(0xFF0A1814)],
    [Color(0xFF1E3A58), Color(0xFF0A141C)],
  ];

  static List<Color> forDemo(int index) => _demo[index % _demo.length];

  /// Complementary, lifted so bars read on a dark wash of the same cover.
  static Color invert(Color c) {
    final hsl = HSLColor.fromColor(c);
    return HSLColor.fromAHSL(
      1,
      (hsl.hue + 180) % 360,
      (hsl.saturation * 0.55 + 0.38).clamp(0.42, 0.82),
      (0.92 - hsl.lightness * 0.35).clamp(0.58, 0.86),
    ).toColor();
  }

  static Future<List<Color>> fromBytes(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 48,
        targetHeight: 48,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      if (data == null) return fallback;
      return _extract(data.buffer.asUint8List());
    } catch (_) {
      return fallback;
    }
  }

  static List<Color> _extract(Uint8List rgba) {
    final bins = List.generate(12, (_) => _Bin());

    for (var i = 0; i + 3 < rgba.length; i += 4) {
      if (rgba[i + 3] < 200) continue;
      final hsl = HSLColor.fromColor(
        Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]),
      );
      // Drop near-white / near-black so the wash stays saturated, not chalky.
      if (hsl.lightness < 0.12 || hsl.lightness > 0.72) continue;
      if (hsl.saturation < 0.12) continue;
      final idx = ((hsl.hue / 360.0) * 12).floor().clamp(0, 11);
      bins[idx].add(hsl);
    }

    final ranked = bins.where((b) => b.count > 0).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    if (ranked.isEmpty) return fallback;

    final first = ranked.first.median();
    HSLColor second = first;
    for (final bin in ranked.skip(1)) {
      final c = bin.median();
      if (_hueDist(first.hue, c.hue) >= 32) {
        second = c;
        break;
      }
    }
    if (identical(second, first) && ranked.length > 1) {
      second = ranked[1].median();
    }

    return [_toAmbient(first, 0.22), _toAmbient(second, 0.16)];
  }

  static Color _toAmbient(HSLColor c, double light) {
    return HSLColor.fromAHSL(
      1,
      c.hue,
      (c.saturation * 0.85).clamp(0.35, 0.72),
      light,
    ).toColor();
  }

  static double _hueDist(double a, double b) {
    final d = (a - b).abs();
    return d > 180 ? 360 - d : d;
  }
}

class _Bin {
  final List<HSLColor> _colors = [];

  void add(HSLColor c) => _colors.add(c);

  int get count => _colors.length;

  double get score {
    if (_colors.isEmpty) return 0;
    var sat = 0.0;
    for (final c in _colors) {
      sat += c.saturation;
    }
    return count * (0.4 + sat / count);
  }

  HSLColor median() {
    final bySat = [..._colors]
      ..sort((a, b) => a.saturation.compareTo(b.saturation));
    return bySat[bySat.length ~/ 2];
  }
}
