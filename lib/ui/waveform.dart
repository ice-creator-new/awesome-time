import 'dart:math';
import 'dart:ui' as ui;

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
        final rise = (_levels[i] - _peaks[i]).abs();
        if (rise > maxDelta) maxDelta = rise;
        _peaks[i] = _levels[i];
      } else {
        final peakBefore = _peaks[i];
        _peaks[i] = max(_levels[i], _peaks[i] - peakFall);
        // The peak caps fall on their own clock, so their movement has to count
        // as a reason to repaint too — otherwise a quiet passage freezes them
        // mid-air and they jump when the level moves again.
        final fall = (peakBefore - _peaks[i]).abs();
        if (fall > maxDelta) maxDelta = fall;
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

  /// Bars per row, rounded so [paint] can widen each bar to span the width
  /// edge to edge at a pitch of ≈ 6.5px landscape / 6px on a cover.
  int _barCount(double width) {
    final pitch = widget.expanded ? 6.5 : 6.0;
    final gap = widget.expanded ? 3.3 : 2.8;
    final n = ((width + gap) / pitch).round();
    return max(16, min(160, n));
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

  /// Meter ink: the cover's own hue, lifted so the bars glow on dark *and*
  /// mid-tone artwork. Rotating the hue away from the backdrop (the old
  /// behaviour) made the meter fight the palette instead of belonging to it.
  static Color _meter(Color base) {
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withSaturation(hsl.saturation.clamp(0.25, 0.85))
        .withLightness((hsl.lightness + 0.18).clamp(0.52, 0.80))
        .toColor();
  }

  Color? _cacheInk;
  int _cachePal = -1;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || levels.isEmpty) return;
    canvas.clipRect(Offset.zero & size);

    final n = levels.length;
    // Fill the row: the bar width absorbs whatever the rounded bar count
    // leaves over, so the meter spans the full cover instead of floating in
    // the middle with dead space on both sides.
    final gap = expanded ? 3.3 : 2.8;
    final barW = ((size.width - gap * (n - 1)) / n).clamp(1.6, 12.0);
    final used = n * barW + gap * (n - 1);
    final originX = max(0.0, (size.width - used) / 2);
    final floor = size.height;
    final maxH = size.height * 0.92;
    final radius = Radius.circular(barW / 2);

    final palId = Object.hashAll([
      for (final c in colors.take(4)) c.toARGB32(),
      expanded,
    ]);
    if (_cachePal != palId || _cacheInk == null) {
      final raw = colors.isNotEmpty ? colors[0] : const Color(0xFFFF9F43);
      _cacheInk = _meter(raw);
      _cachePal = palId;
    }
    final ink = _cacheInk!;

    // One vertical ramp for the whole meter: quiet bars sit low in the
    // gradient, loud ones reach the bright end. A per-bar colour ramp (the old
    // behaviour) turned the field into flickering confetti, and per-bar drop
    // shadows plus near-white crowns read as dirt on top of the artwork.
    final body = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, floor - maxH),
        Offset(0, floor),
        [
          Color.lerp(ink, Colors.white, 0.55)!.withValues(alpha: 0.95),
          ink.withValues(alpha: 0.55),
        ],
      );
    final peakBase = Color.lerp(ink, Colors.white, 0.75)!;
    final peakPaint = Paint()
      ..color = peakBase.withValues(alpha: playing ? 0.5 : 0.22);
    final peakAlpha = playing ? 0.5 : 0.22;

    for (var i = 0; i < n; i++) {
      final x = originX + i * (barW + gap);
      if (x >= size.width) break;
      final w = min(barW, size.width - x);
      if (w <= 0) break;

      // Three-point smoothing keeps the envelope continuous instead of
      // flickering bar to bar.
      final prev = i > 0 ? levels[i - 1] : levels[i];
      final next = i < n - 1 ? levels[i + 1] : levels[i];
      final level =
          (levels[i] * 0.6 + prev * 0.22 + next * 0.18).clamp(0.0, 1.0);
      final h = max(1.6, maxH * pow(level, 0.82).toDouble());
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x, floor - h, x + w, floor),
          radius,
        ),
        body,
      );

      // Peak cap. It fades in as it separates from the bar and fades out again
      // as it drops back down, instead of popping in and out on a threshold —
      // and it dims near the baseline rather than being cut off there.
      final peak = peaks[i].clamp(0.0, 1.0);
      final peakGap = peak - level;
      if (peakGap > 0.015 && peak > 0.02) {
        final py = floor - maxH * pow(peak, 0.82).toDouble();
        final separation = (peakGap / 0.16).clamp(0.0, 1.0);
        final headroom = ((floor - py) / 14.0).clamp(0.0, 1.0);
        final alpha = peakAlpha * separation * headroom;
        if (alpha > 0.01) {
          peakPaint.color = peakBase.withValues(alpha: alpha);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTRB(x, py - 1.5, x + w, py),
              const Radius.circular(1),
            ),
            peakPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => true;
}
