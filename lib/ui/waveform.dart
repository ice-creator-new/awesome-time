import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'artwork_palette.dart';

/// Bottom-up spectrum bars tinted with the album's complementary colors.
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
  List<double> _levels = const [];
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _ensure(int n) {
    if (_levels.length == n) return;
    _levels = List<double>.filled(n, 0.04);
  }

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 0.016
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_levels.isEmpty) return;
    final src = widget.spectrum.value;
    final playing = widget.playing;
    final last = _levels.length - 1;
    for (var i = 0; i < _levels.length; i++) {
      final u = last == 0 ? 0.0 : i / last;
      var target = src.isEmpty ? 0.0 : _sample(src, u);
      if (!playing) target *= 0.12;
      target = target.clamp(0.0, 1.0);
      final k = target > _levels[i] ? (1 - exp(-dt * 20)) : (1 - exp(-dt * 6));
      _levels[i] += (target - _levels[i]) * k;
    }
    if (mounted) setState(() {});
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
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final n = max(18, min(32, (constraints.maxWidth / 16).floor()));
        _ensure(n);
        return ClipRect(
          child: CustomPaint(
            painter: _WavePainter(
              levels: _levels,
              playing: widget.playing,
              colors: widget.colors,
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
    required this.playing,
    required this.colors,
  });

  final List<double> levels;
  final bool playing;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || levels.isEmpty) return;
    canvas.clipRect(Offset.zero & size);

    final n = levels.length;
    const gap = 5.0;
    var barW = (size.width - gap * (n - 1)) / n;
    if (barW < 3) barW = 3;
    final used = n * barW + (n - 1) * gap;
    final originX = max(0.0, (size.width - used) / 2);
    final floor = size.height;
    final maxH = size.height * 0.92;
    final c0 = ArtworkPalette.invert(
      colors.isNotEmpty ? colors[0] : const Color(0xFF2A1838),
    );
    final c1 = ArtworkPalette.invert(
      colors.length > 1 ? colors[1] : c0,
    );
    final radius = Radius.circular(barW / 2);

    for (var i = 0; i < n; i++) {
      final x = originX + i * (barW + gap);
      if (x >= size.width) break;
      final w = min(barW, size.width - x);
      if (w <= 0) break;
      final h = max(4.0, maxH * levels[i].clamp(0.0, 1.0));
      final u = n == 1 ? 0.0 : i / (n - 1);
      final color = Color.lerp(c0, c1, u)!;
      final top = Color.lerp(color, Colors.white, 0.28)!;
      final rect = Rect.fromLTRB(x, floor - h, x + w, floor);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, radius),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              color.withValues(alpha: playing ? 0.95 : 0.4),
              top.withValues(alpha: playing ? 0.95 : 0.4),
            ],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => true;
}
