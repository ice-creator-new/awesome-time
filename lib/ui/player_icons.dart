import 'package:flutter/material.dart';

enum PlayerGlyph {
  play,
  pause,
  next,
  prev,
  volumeMin,
  volumeMax,
  chevronDown,
  more,
}

/// Custom transport glyphs — rounded, slightly chunky, not stock Cupertino.
class PlayerIcon extends StatelessWidget {
  const PlayerIcon({
    super.key,
    required this.glyph,
    this.color = Colors.white,
    this.size = 28,
  });

  final PlayerGlyph glyph;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GlyphPainter(glyph: glyph, color: color),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter({required this.glyph, required this.color});

  final PlayerGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final s = size.shortestSide;
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);

    switch (glyph) {
      case PlayerGlyph.play:
        _play(canvas, s, paint);
      case PlayerGlyph.pause:
        _pause(canvas, s, paint);
      case PlayerGlyph.next:
        _skipNext(canvas, s, paint);
      case PlayerGlyph.prev:
        _skipPrev(canvas, s, paint);
      case PlayerGlyph.volumeMin:
        _volume(canvas, s, paint, bars: 1);
      case PlayerGlyph.volumeMax:
        _volume(canvas, s, paint, bars: 3);
      case PlayerGlyph.chevronDown:
        _chevron(canvas, s, paint);
      case PlayerGlyph.more:
        _more(canvas, s, paint);
    }
  }

  void _play(Canvas canvas, double s, Paint paint) {
    final path = Path()
      ..moveTo(s * 0.30, s * 0.16)
      ..quadraticBezierTo(s * 0.26, s * 0.18, s * 0.26, s * 0.24)
      ..lineTo(s * 0.26, s * 0.76)
      ..quadraticBezierTo(s * 0.26, s * 0.84, s * 0.34, s * 0.80)
      ..lineTo(s * 0.82, s * 0.54)
      ..quadraticBezierTo(s * 0.90, s * 0.50, s * 0.82, s * 0.46)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _pause(Canvas canvas, double s, Paint paint) {
    final r = Radius.circular(s * 0.09);
    canvas.drawRRect(
      RRect.fromLTRBR(s * 0.26, s * 0.18, s * 0.44, s * 0.82, r),
      paint,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(s * 0.56, s * 0.18, s * 0.74, s * 0.82, r),
      paint,
    );
  }

  /// Next: triangle pointing right, bar on the right  ▶|
  void _skipNext(Canvas canvas, double s, Paint paint) {
    final r = Radius.circular(s * 0.08);
    final tri = Path()
      ..moveTo(s * 0.08, s * 0.20)
      ..lineTo(s * 0.08, s * 0.80)
      ..lineTo(s * 0.62, s * 0.50)
      ..close();
    canvas.drawPath(tri, paint);
    canvas.drawRRect(
      RRect.fromLTRBR(s * 0.70, s * 0.20, s * 0.86, s * 0.80, r),
      paint,
    );
  }

  /// Previous: bar on the left, triangle pointing left  |◀
  void _skipPrev(Canvas canvas, double s, Paint paint) {
    final r = Radius.circular(s * 0.08);
    canvas.drawRRect(
      RRect.fromLTRBR(s * 0.14, s * 0.20, s * 0.30, s * 0.80, r),
      paint,
    );
    final tri = Path()
      ..moveTo(s * 0.92, s * 0.20)
      ..lineTo(s * 0.92, s * 0.80)
      ..lineTo(s * 0.38, s * 0.50)
      ..close();
    canvas.drawPath(tri, paint);
  }

  void _volume(Canvas canvas, double s, Paint paint, {required int bars}) {
    final r = Radius.circular(s * 0.08);
    canvas.drawRRect(
      RRect.fromLTRBR(s * 0.08, s * 0.38, s * 0.26, s * 0.62, r),
      paint,
    );
    final horn = Path()
      ..moveTo(s * 0.24, s * 0.38)
      ..lineTo(s * 0.44, s * 0.20)
      ..lineTo(s * 0.44, s * 0.80)
      ..lineTo(s * 0.24, s * 0.62)
      ..close();
    canvas.drawPath(horn, paint);
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.07
      ..strokeCap = StrokeCap.round;
    if (bars >= 1) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(s * 0.48, s * 0.50), radius: s * 0.18),
        -0.7,
        1.4,
        false,
        paint,
      );
    }
    if (bars >= 3) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(s * 0.48, s * 0.50), radius: s * 0.32),
        -0.7,
        1.4,
        false,
        paint,
      );
    }
  }

  void _chevron(Canvas canvas, double s, Paint paint) {
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.10
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(s * 0.26, s * 0.40)
      ..lineTo(s * 0.50, s * 0.64)
      ..lineTo(s * 0.74, s * 0.40);
    canvas.drawPath(path, paint);
  }

  void _more(Canvas canvas, double s, Paint paint) {
    canvas.drawCircle(Offset(s * 0.22, s * 0.50), s * 0.09, paint);
    canvas.drawCircle(Offset(s * 0.50, s * 0.50), s * 0.09, paint);
    canvas.drawCircle(Offset(s * 0.78, s * 0.50), s * 0.09, paint);
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}
