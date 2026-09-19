import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Three dominant colors sampled from album art.
/// Only real pixels from the cover are returned — no hue spin, no invented hues.
class ArtworkPalette {
  /// Min hue gap between any two picks (degrees). Relaxed if the cover
  /// has fewer distinct hues; never fabricates a missing color.
  static const _minHueGap = 48.0;

  static const fallback = <Color>[
    Color(0xFF6A3A9A),
    Color(0xFF1A6A72),
    Color(0xFF8A4A30),
  ];

  static const _demo = <List<Color>>[
    [Color(0xFF6A3A9A), Color(0xFF1A5A8A), Color(0xFF8A6A20)],
    [Color(0xFFA03A58), Color(0xFF206060), Color(0xFF5A3A90)],
    [Color(0xFF2A7A5A), Color(0xFF8A4A20), Color(0xFF3A3A8A)],
    [Color(0xFF2A5A8A), Color(0xFF8A3A6A), Color(0xFF6A7A20)],
  ];

  static List<Color> forDemo(int index) => _demo[index % _demo.length];

  /// Complementary helper (UI accents only — not used for ambient extraction).
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
    const binCount = 18;
    final bins = List.generate(binCount, (_) => _Bin());

    for (var i = 0; i + 3 < rgba.length; i += 4) {
      if (rgba[i + 3] < 200) continue;
      final color = Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]);
      final hsl = HSLColor.fromColor(color);
      if (hsl.lightness < 0.10 || hsl.lightness > 0.78) continue;
      if (hsl.saturation < 0.10) continue;
      final idx =
          ((hsl.hue / 360.0) * binCount).floor().clamp(0, binCount - 1);
      bins[idx].add(color, hsl);
    }

    final ranked = bins.where((b) => b.count > 0).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    if (ranked.isEmpty) return fallback;

    // Only real cover pixels — never synthesized / hue-shifted fills.
    return _pickThree(ranked);
  }

  /// Greedy farthest-hue pick among actual sampled colors.
  /// Pads only with other real samples (repeats if the cover is mono).
  static List<Color> _pickThree(List<_Bin> ranked) {
    final candidates = ranked.map((b) => b.representative()).toList();
    final hues = ranked.map((b) => b.representativeHue()).toList();
    final outIdx = <int>[];

    final gaps = <double>[_minHueGap, 32.0, 16.0];
    for (final gap in gaps) {
      outIdx.clear();
      outIdx.add(0);
      while (outIdx.length < 3 && candidates.length > outIdx.length) {
        var best = -1;
        var bestScore = -1.0;
        for (var i = 0; i < candidates.length; i++) {
          if (outIdx.contains(i)) continue;
          var minD = 360.0;
          for (final j in outIdx) {
            final d = _hueDist(hues[j], hues[i]);
            if (d < minD) minD = d;
          }
          final score = minD >= gap ? minD + 1000.0 : minD;
          if (score > bestScore) {
            bestScore = score;
            best = i;
          }
        }
        if (best < 0) break;
        var minD = 360.0;
        for (final j in outIdx) {
          final d = _hueDist(hues[j], hues[best]);
          if (d < minD) minD = d;
        }
        // Reject near-twins when we already have ≥2 distinct colors.
        if (outIdx.length >= 2 && minD < gap * 0.45) break;
        outIdx.add(best);
      }
      if (outIdx.length >= 3) break;
    }

    // Pad with remaining real samples only (no invented hues).
    var i = 0;
    while (outIdx.length < 3 && i < candidates.length) {
      if (!outIdx.contains(i)) outIdx.add(i);
      i++;
    }
    while (outIdx.length < 3 && candidates.isNotEmpty) {
      outIdx.add(outIdx.length % candidates.length);
    }

    return [for (final idx in outIdx) candidates[idx % candidates.length]];
  }

  static double _hueDist(double a, double b) {
    final d = (a - b).abs();
    return d > 180 ? 360 - d : d;
  }
}

class _Bin {
  final List<Color> _rgb = [];
  final List<HSLColor> _hsl = [];

  void add(Color c, HSLColor h) {
    _rgb.add(c);
    _hsl.add(h);
  }

  int get count => _rgb.length;

  double get score {
    if (_hsl.isEmpty) return 0;
    var sat = 0.0;
    for (final c in _hsl) {
      sat += c.saturation;
    }
    return count * (0.4 + sat / count);
  }

  /// Actual pixel color at the saturation-median of this hue bin.
  Color representative() {
    final order = List<int>.generate(_hsl.length, (i) => i)
      ..sort((a, b) => _hsl[a].saturation.compareTo(_hsl[b].saturation));
    return _rgb[order[order.length ~/ 2]];
  }

  double representativeHue() => HSLColor.fromColor(representative()).hue;
}
