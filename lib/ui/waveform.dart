import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Landscape spectrum: dense thin analyzer bars, snappy envelope.
/// Colors are forced away from the ambient wash so bars stay readable
/// on any cover.
///
/// Updates go through a repaint listenable (not setState) so the ticker only
/// invalidates paint — avoids rebuild/layout jank at 60fps.
class Waveform extends StatefulWidget {
  const Waveform({
    super.key,
    required this.spectrum,
    required this.playing,
    required this.colors,
    this.expanded = false,
  });

  final ValueListenable<List<double>> spectrum;
  final bool playing;
  final List<Color> colors;
  final bool expanded;

  @override
  State<Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<Waveform>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  List<double> _levels = const [];
  List<double> _peaks = const [];
  Duration _last = Duration.zero;
  bool _needPaint = true;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _ensure(int n) {
    if (_levels.length == n) return;
    _levels = List<double>.filled(n, 0);
    _peaks = List<double>.filled(n, 0);
    _needPaint = true;
  }

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 0.016
        : ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    if (_levels.isEmpty) return;

    final src = widget.spectrum.value;
    final playing = widget.playing;
    final n = _levels.length;
    final last = n - 1;
    var maxDelta = 0.0;

    final attack = 1 - exp(-dt * 28);
    final release = 1 - exp(-dt * 10);
    final peakFall = dt * 0.5;

    for (var i = 0; i < n; i++) {
      final u = last == 0 ? 0.0 : i / last;
      var raw = src.isEmpty ? 0.0 : _sample(src, u).clamp(0.0, 1.0);
      raw = (raw * (1.0 + 0.22 * u * u)).clamp(0.0, 1.0);
      if (!playing) raw *= 0.05;

      final k = raw > _levels[i] ? attack : release;
      final before = _levels[i];
      _levels[i] += (raw - _levels[i]) * k;
      final d = (_levels[i] - before).abs();
      if (d > maxDelta) maxDelta = d;

      if (_levels[i] >= _peaks[i]) {
        _peaks[i] = _levels[i];
      } else {
        _peaks[i] = max(_levels[i], _peaks[i] - peakFall);
      }
    }

    if (maxDelta > 0.0004 || _needPaint) {
      _needPaint = false;
      _repaint.value++;
    }
  }

  double _sample(List<double> bands, double u) {
    if (bands.isEmpty) return 0;
    final x = u * (bands.length - 1);
    final i = x.floor().clamp(0, bands.length - 1);
    final j = min(i + 1, bands.length - 1);
    final t = x - i;
    return bands[i] * (1 - t) + bands[j] * t;
  }

  @override
  void didUpdateWidget(covariant Waveform old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing ||
        old.expanded != widget.expanded ||
        old.colors != widget.colors) {
      _needPaint = true;
      _repaint.value++;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  /// Dense thin bars: pitch ≈ 5px (2.5px bar + 2.5px gap), square ends.
  int _barCount(double width) {
    final pitch = widget.expanded ? 5.0 : 4.5;
    final gap = widget.expanded ? 2.5 : 2.0;
    final n = ((width + gap) / pitch).floor();
    return max(32, min(120, n));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final n = _barCount(constraints.maxWidth);
        _ensure(n);
        return ClipRect(
          child: CustomPaint(
            painter: _WavePainter(
              levels: _levels,
              peaks: _peaks,
              playing: widget.playing,
              colors: widget.colors,
              expanded: widget.expanded,
              repaint: _repaint,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.levels,
    required this.peaks,
    required this.playing,
    required this.colors,
    required this.expanded,
    super.repaint,
  });

  final List<double> levels;
  final List<double> peaks;
  final bool playing;
  final List<Color> colors;
  final bool expanded;

  static double _hueDist(double a, double b) {
    final d = (a - b).abs();
    return d > 180 ? 360 - d : d;
  }

  /// Meter ink: bright, saturated, and pushed off the ambient wash hue
  /// when it would otherwise disappear into the background.
  static Color _meter(Color base, List<Color> ambient) {
    var hsl = HSLColor.fromColor(base);
    // If this hue is already used by the backdrop, rotate toward the
    // opposite side of the wheel so bars never share the wash hue.
    var minAmbient = 360.0;
    for (final a in ambient) {
      final d = _hueDist(hsl.hue, HSLColor.fromColor(a).hue);
      if (d < minAmbient) minAmbient = d;
    }
    if (minAmbient < 40) {
      hsl = hsl.withHue((hsl.hue + 150) % 360);
    } else if (minAmbient < 70) {
      hsl = hsl.withHue((hsl.hue + 55) % 360);
    }

    // High lightness so thin bars read on dark *and* mid ambient.
    return hsl
        .withSaturation((hsl.saturation * 1.1 + 0.35).clamp(0.55, 1.0))
        .withLightness(0.74)
        .toColor();
  }

  Color? _cacheC0;
  Color? _cacheC1;
  int _cachePal = -1;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || levels.isEmpty) return;
    canvas.clipRect(Offset.zero & size);

    final n = levels.length;
    final gap = expanded ? 2.5 : 2.0;
    const targetBar = 2.5;
    var barW = targetBar;
    final totalGaps = gap * (n - 1);
    if (totalGaps + barW * n > size.width) {
      barW = max(1.5, (size.width - totalGaps) / n);
    }
    final used = n * barW + totalGaps;
    final originX = max(0.0, (size.width - used) / 2);
    final floor = size.height;
    final maxH = size.height * 0.94;

    final palId = Object.hashAll([
      for (final c in colors.take(4)) c.toARGB32(),
      expanded,
    ]);
    if (_cachePal != palId || _cacheC0 == null) {
      final raw0 = colors.isNotEmpty ? colors[0] : const Color(0xFFFF9F43);
      final raw1 = colors.length > 1 ? colors[1] : raw0;
      _cacheC0 = _meter(raw0, colors);
      _cacheC1 = _meter(raw1, colors);
      _cachePal = palId;
    }
    final c0 = _cacheC0!;
    final c1 = _cacheC1!;

    // No scrim behind bars — a dark trough read as a hard layered band
    // against the ambient wash. Contrast comes from meter color + edges only.
    canvas.drawLine(
      Offset(originX, floor - 0.5),
      Offset(min(size.width, originX + used), floor - 0.5),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..strokeWidth = 1,
    );

    final bodyPaint = Paint();
    final shadowPaint = Paint()
      ..color = const Color(0x66000000)
      ..strokeWidth = 0;
    final tipPaint = Paint();
    final peakPaint = Paint()
      ..color = Colors.white.withValues(alpha: playing ? 0.85 : 0.35);

    for (var i = 0; i < n; i++) {
      final x = originX + i * (barW + gap);
      if (x >= size.width) break;
      final w = min(barW, size.width - x);
      if (w <= 0) break;

      final level = levels[i].clamp(0.0, 1.0);
      final h = maxH * pow(level, 0.88).toDouble();
      final u = n == 1 ? 0.0 : i / (n - 1);

      final base = Color.lerp(c0, c1, u)!;
      // Floor opacity so quiet bars still punch through the wash.
      final energy = playing ? level : level * 0.5;
      final a = (0.55 + 0.45 * energy).clamp(0.5, 1.0);

      if (h >= 3) {
        final rect = Rect.fromLTRB(x, floor - h, x + w, floor);
        // Soft dark edge behind the bar for contrast on matching hues.
        canvas.drawRect(
          rect.translate(0.75, 0.75),
          shadowPaint..color = const Color(0x55000000),
        );
        bodyPaint.color = base.withValues(alpha: a);
        canvas.drawRect(rect, bodyPaint);

        // Near-white crown on hits — always separates from ambient.
        if (h >= 16 && level > 0.35) {
          final tipH = min(h * 0.14, 7.0);
          tipPaint.color = Color.lerp(base, Colors.white, 0.7)!
              .withValues(alpha: (a * 0.95).clamp(0.0, 1.0));
          canvas.drawRect(
            Rect.fromLTRB(x, floor - h, x + w, floor - h + tipH),
            tipPaint,
          );
        }
      }

      final peak = peaks[i].clamp(0.0, 1.0);
      if (peak > 0.15 && peak - level > 0.08) {
        final py = floor - maxH * pow(peak, 0.88).toDouble();
        if (py < floor - 6) {
          canvas.drawRect(Rect.fromLTRB(x, py - 2, x + w, py), peakPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => true;
}
