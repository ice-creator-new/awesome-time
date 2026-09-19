import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Abstract album square used when the bridge has no artwork (and in demo).
class GeneratedCover extends StatelessWidget {
  const GeneratedCover({
    super.key,
    required this.title,
    required this.colors,
  });

  final String title;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final c0 = colors.isNotEmpty ? colors[0] : const Color(0xFF1A1024);
    final c1 = colors.length > 1 ? colors[1] : const Color(0xFF4A1F8A);
    final c2 = colors.length > 2 ? colors[2] : c0;
    final letter = title.isEmpty ? '♪' : String.fromCharCode(title.runes.first);

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [c1, c0, c2],
            ),
          ),
        ),
        CustomPaint(painter: _GrainPainter(color: c1)),
        Center(
          child: Text(
            letter,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 86,
              fontWeight: FontWeight.w600,
              letterSpacing: -2,
              height: 1,
            ),
          ),
        ),
      ],
    );
  }
}

class _GrainPainter extends CustomPainter {
  _GrainPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18;
    final m = size.shortestSide;
    canvas.drawCircle(Offset(size.width * 0.72, size.height * 0.28), m * 0.42, paint);
    canvas.drawCircle(Offset(size.width * 0.18, size.height * 0.78), m * 0.34, paint);
    final sweep = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.12),
          Colors.white.withValues(alpha: 0.0),
        ],
        transform: GradientRotation(math.pi / 5),
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sweep);
  }

  @override
  bool shouldRepaint(covariant _GrainPainter old) => old.color != color;
}
