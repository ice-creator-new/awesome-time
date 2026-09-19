import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'artwork_palette.dart';

/// Three-color flowing field sampled from the album, heavily blurred.
class AmbientBackdrop extends StatefulWidget {
  const AmbientBackdrop({
    super.key,
    required this.colors,
    required this.playing,
  });

  final List<Color> colors;
  final bool playing;

  @override
  State<AmbientBackdrop> createState() => _AmbientBackdropState();
}

class _AmbientBackdropState extends State<AmbientBackdrop>
    with SingleTickerProviderStateMixin {
  ui.FragmentProgram? _program;
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  double _time = 0;
  double _mix = 1;
  List<Color> _from = ArtworkPalette.fallback;
  List<Color> _to = ArtworkPalette.fallback;

  @override
  void initState() {
    super.initState();
    _to = _trio(widget.colors);
    _from = _to;
    _ticker = createTicker(_onTick)..start();
    _loadShader();
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/ambient_flow.frag',
      );
      if (mounted) setState(() => _program = program);
    } catch (_) {}
  }

  void _onTick(Duration elapsed) {
    final dt = (_lastElapsed == Duration.zero)
        ? 0.016
        : (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    // Playing: gentle readable drift; paused: barely-there crawl.
    _time += dt * (widget.playing ? 0.70 : 0.18);
    if (_mix < 1) {
      _mix = (_mix + dt / 0.7).clamp(0.0, 1.0);
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(AmbientBackdrop old) {
    super.didUpdateWidget(old);
    if (!_sameColors(old.colors, widget.colors)) {
      _from = _mixed();
      _to = _trio(widget.colors);
      _mix = 0;
    }
  }

  List<Color> _trio(List<Color> colors) {
    final fb = ArtworkPalette.fallback;
    if (colors.length >= 3) return colors.sublist(0, 3);
    if (colors.length == 2) return [colors[0], colors[1], fb[2]];
    if (colors.length == 1) return [colors[0], fb[1], fb[2]];
    return fb;
  }

  bool _sameColors(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<Color> _mixed() {
    final t = Curves.easeInOut.transform(_mix);
    final from = _trio(_from);
    final to = _trio(_to);
    return [
      Color.lerp(from[0], to[0], t)!,
      Color.lerp(from[1], to[1], t)!,
      Color.lerp(from[2], to[2], t)!,
    ];
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final colors = _mixed();
    final program = _program;
    final field = program != null && !reduce
        ? CustomPaint(
            painter: _ShaderPainter(
              program: program,
              time: _time,
              speed: widget.playing ? 1 : 0.15,
              colors: colors,
            ),
            child: const SizedBox.expand(),
          )
        : CustomPaint(
            painter: _BlobPainter(time: reduce ? 0 : _time, colors: colors),
            child: const SizedBox.expand(),
          );

    return IgnorePointer(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: colors.first),
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: 64,
                  sigmaY: 64,
                  tileMode: TileMode.clamp,
                ),
                child: field,
              ),
            ),
            const ColoredBox(color: Color(0x14000000)),
          ],
        ),
      ),
    );
  }
}

class _ShaderPainter extends CustomPainter {
  _ShaderPainter({
    required this.program,
    required this.time,
    required this.speed,
    required this.colors,
  });

  final ui.FragmentProgram program;
  final double time;
  final double speed;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final shader = program.fragmentShader();
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, time);
    shader.setFloat(3, speed);
    var i = 4;
    for (final c in colors.take(3)) {
      shader.setFloat(i++, c.r);
      shader.setFloat(i++, c.g);
      shader.setFloat(i++, c.b);
      shader.setFloat(i++, 1);
    }
    // Shader expects 3 colors; pad if caller passed fewer.
    while (i < 4 + 12) {
      shader.setFloat(i++, 0);
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _ShaderPainter old) =>
      old.time != time || old.speed != speed || old.colors != colors;
}

class _BlobPainter extends CustomPainter {
  _BlobPainter({required this.time, required this.colors});

  final double time;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final a = colors.isNotEmpty ? colors[0] : ArtworkPalette.fallback[0];
    final b = colors.length > 1 ? colors[1] : a;
    final c = colors.length > 2 ? colors[2] : b;
    canvas.drawRect(Offset.zero & size, Paint()..color = a);
    final cx = size.width / 2;
    final cy = size.height / 2;
    final m = size.longestSide;
    final t = time * 0.35;
    final blobs = <(Offset, Color, double)>[
      (
        Offset(
          cx + m * 0.22 * math.sin(t * 0.75),
          cy - m * 0.18 * math.cos(t * 0.60),
        ),
        a,
        m * 0.85,
      ),
      (
        Offset(
          cx - m * 0.24 * math.cos(t * 0.55),
          cy + m * 0.20 * math.sin(t * 0.70),
        ),
        b,
        m * 0.80,
      ),
      (
        Offset(
          cx + m * 0.18 * math.sin(t * 0.90 + 1.4),
          cy + m * 0.22 * math.cos(t * 0.65 + 0.4),
        ),
        c,
        m * 0.75,
      ),
    ];
    // Overlapping soft lobes — paint order + alpha produces a melt look.
    for (final (origin, color, radius) in blobs) {
      canvas.drawCircle(
        origin,
        radius,
        Paint()
          ..blendMode = BlendMode.srcOver
          ..shader = ui.Gradient.radial(
            origin,
            radius,
            [
              color.withValues(alpha: 0.95),
              color.withValues(alpha: 0.55),
              color.withValues(alpha: 0.0),
            ],
            const [0.0, 0.45, 1.0],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BlobPainter old) =>
      old.time != time || old.colors != colors;
}
