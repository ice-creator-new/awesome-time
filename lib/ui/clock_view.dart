import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/clock_settings.dart';
import '../state/player_controller.dart';
import '../theme.dart';
import 'clock_settings_sheet.dart';

/// Ambient clock panel, in the spirit of Apple's StandBy / lock-screen clock:
///
/// * one enormous time, centred, at the lightest weight the system font offers
/// * the date above it in the secondary label colour
/// * seconds as a hairline that fills over a minute (motion instead of digits)
/// * what is playing floats in a glass card below
///
/// No calendar grid, no chrome. Pull down anywhere for the customisation sheet.
class ClockView extends StatefulWidget {
  const ClockView({super.key});

  @override
  State<ClockView> createState() => _ClockViewState();
}

class _ClockViewState extends State<ClockView>
    with SingleTickerProviderStateMixin {
  static const _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

  /// How far the user must pull before the settings sheet opens.
  static const _pullThreshold = 64.0;

  late final Ticker _ticker;
  late DateTime _now;

  /// Seconds within the minute, with sub-second smoothing. Drives the second
  /// bar through a listenable so the bar repaints every frame without
  /// rebuilding the panel.
  late final ValueNotifier<double> _second;

  double _pull = 0;
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _second = ValueNotifier(_now.second + _now.millisecond / 1000);
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration _) {
    final now = DateTime.now();
    _second.value = now.second + now.millisecond / 1000;
    // Only the minute (or a date rollover) needs a rebuild.
    if (now.minute == _now.minute &&
        now.hour == _now.hour &&
        now.day == _now.day) {
      return;
    }
    setState(() => _now = now);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _second.dispose();
    super.dispose();
  }

  void _onPull(DragUpdateDetails details) {
    if (details.delta.dy <= 0) {
      _pull = 0;
      return;
    }
    _pull += details.delta.dy;
    if (_pull < _pullThreshold || _sheetOpen) return;
    _pull = 0;
    _sheetOpen = true;
    HapticFeedback.mediumImpact();
    showClockSettingsSheet(context).whenComplete(() => _sheetOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlayerController>();
    final settings = context.watch<ClockSettings>();
    // Respect the platform's reduce-motion setting: no digit animation.
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final ink = settings.ink.resolve(c.palette);

    return GestureDetector(
      // Pull down to customise.
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: _onPull,
      onVerticalDragEnd: (_) => _pull = 0,
      child: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final landscape =
                    constraints.maxWidth > constraints.maxHeight * 1.2;
                // Tight side padding so the numerals can use nearly the whole
                // width — on a phone the row is width-bound, not height-bound,
                // so this is what actually buys type size.
                final pad = landscape ? 56.0 : 24.0;
                final avail = constraints.maxWidth - pad * 2;
                // `hh:mm` runs ~4.6 em with tabular figures, loosened a touch;
                // the colon's padding plus the seconds ring add roughly
                // 0.8 em. The row is wrapped in a scaleDown FittedBox, so this
                // only sets the type size.
                final unit =
                    (avail / 5.0).clamp(44.0, landscape ? 258.0 : 206.0) *
                    settings.scale;
                // The ring's stroke rides the type weight. These are absolute
                // shares of the type size, tuned up twice on user feedback —
                // the lightest weight still has to read as a drawn ring, not
                // a hairline.
                final ringStroke =
                    unit *
                    switch (settings.weight) {
                      FontWeight.w200 => 0.055,
                      FontWeight.w300 => 0.061,
                      FontWeight.w400 => 0.068,
                      FontWeight.w500 => 0.076,
                      FontWeight.w600 => 0.083,
                      _ => 0.091,
                    };

                return Stack(
                  children: [
                    // The time is centred on the panel itself, independent of
                    // anything else on screen.
                    Positioned.fill(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _TimeRow(
                            now: _now,
                            size: unit,
                            reduceMotion: reduceMotion,
                            ink: ink,
                            fontFamily: settings.fontFamily,
                            fontWeight: settings.weight,
                            face: settings.face,
                            seconds: _second,
                            ringStroke: ringStroke,
                          ),
                        ),
                      ),
                    ),
                    // The date rides near the top, clear of the time.
                    Positioned(
                      top: constraints.maxHeight * 0.11,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: _DateLine(
                          now: _now,
                          landscape: landscape,
                          fontFamily: settings.fontFamily,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // Pull-down affordance.
          Positioned(
            top: 6,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  key: const Key('clock-pull-hint'),
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `hh:mm` with a solid colon — Apple's clock colon does not blink — closing
/// with a small ring that fills over one minute. The ring replaces the old
/// full-width second bar: same information, tucked against the minutes.
class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.now,
    required this.size,
    required this.reduceMotion,
    required this.ink,
    required this.fontFamily,
    required this.fontWeight,
    required this.face,
    required this.seconds,
    required this.ringStroke,
  });

  final DateTime now;
  final double size;
  final bool reduceMotion;
  final Color ink;
  final String? fontFamily;
  final FontWeight fontWeight;
  final ClockFace face;
  final ValueListenable<double> seconds;
  final double ringStroke;

  @override
  Widget build(BuildContext context) {
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final style = TextStyle(
      color: ink,
      fontSize: size,
      fontWeight: fontWeight,
      fontFamily: fontFamily,
      // Display-size tracking, loosened: the user wanted a little more air
      // Each digit is its own widget now, so the spacing between them is set
      // explicitly instead of by tracking — no tracking at all.
      letterSpacing: 0,
      height: 1.0,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // 0.78 em: told twice to make the ring bigger. (It started at digit cap
    // height ~0.70 em, then the user asked for more.)
    final ring = size * 0.78;
    // Air between digits. They used to be crushed together by negative
    // tracking; the user asked for them to breathe.
    final digitGap = size * 0.055;
    // A hair of lift for the ring and the dots. They are geometrically centred
    // on the em box, but a digit's optical centre sits a little above it; full
    // cap-height correction read as "too high", none at all as "too low", so
    // this is deliberately a small fraction of the em size.
    final opticalLift = size * 0.03;

    Widget digit(String text, String slot, bool reduce) => _Digit(
      text: text,
      style: style,
      face: face,
      slot: slot,
      reduceMotion: reduce,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // `clock-hour` / `clock-minute` stay as group keys for the tests; every
        // glyph inside is a separate widget.
        Row(
          key: const Key('clock-hour'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            digit(hh[0], 'h0', reduceMotion),
            SizedBox(width: digitGap),
            digit(hh[1], 'h1', reduceMotion),
          ],
        ),
        Transform.translate(
          offset: Offset(0, -opticalLift),
          child: _Colon(size: size, ink: ink, face: face, weight: fontWeight),
        ),
        Row(
          key: const Key('clock-minute'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            digit(mm[0], 'm0', reduceMotion),
            SizedBox(width: digitGap),
            digit(mm[1], 'm1', reduceMotion),
          ],
        ),
        Transform.translate(
          offset: Offset(0, -opticalLift),
          child: Padding(
            // Optical gap between the minutes and the ring.
            padding: EdgeInsets.only(left: size * 0.13),
            child: _SecondRing(
              progress: seconds,
              ink: ink,
              diameter: ring,
              stroke: ringStroke,
            ),
          ),
        ),
      ],
    );
  }
}

/// One glyph run, painted according to the chosen face:
/// * solid — plain ink
/// * translucent — the ink at 55% so the backdrop reads through
/// * frosted — real glass: the glyphs are rasterised into a mask and used to
///   clip a [BackdropFilter], so the letters *are* the blurred backdrop with a
///   faint white thickness. No ink colour is applied at all.
class _Digit extends StatelessWidget {
  const _Digit({
    required this.text,
    required this.style,
    required this.face,
    required this.slot,
    required this.reduceMotion,
  });

  final String text;
  final TextStyle style;
  final ClockFace face;
  final String slot;
  final bool reduceMotion;

  /// Stable handles for tests, one per glyph.
  static const keys = <String, Key>{
    'h0': Key('clock-digit-h0'),
    'h1': Key('clock-digit-h1'),
    'm0': Key('clock-digit-m0'),
    'm1': Key('clock-digit-m1'),
  };

  @override
  Widget build(BuildContext context) {
    final key = keys[slot];
    final Widget painted = switch (face) {
      ClockFace.solid => Text(text, key: key, style: style),
      ClockFace.translucent => Text(
        text,
        key: key,
        style: style.copyWith(color: style.color!.withValues(alpha: 0.55)),
      ),
      ClockFace.frosted => _FrostedText(
        key: key,
        text: text,
        style: style.copyWith(color: Colors.white),
      ),
    };

    if (reduceMotion) return painted;

    // A short cross-fade on the boundary — Apple does not roll digits.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: KeyedSubtree(key: ValueKey('$slot-$text-$face'), child: painted),
    );
  }
}

/// Frosted glass lettering.
///
/// A `BackdropFilter` can only blur what is already painted behind it, and
/// Flutter has no widget-level "mask this layer with those glyphs" primitive,
/// so the glyphs are rasterised once per text/style change and fed back in as
/// a `dstIn` shader. The result is the actual blurred backdrop showing through
/// the letters, tinted only by a neutral white thickness — never by the user's
/// ink colour.
class _FrostedText extends StatefulWidget {
  const _FrostedText({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_FrostedText> createState() => _FrostedTextState();
}

class _FrostedTextState extends State<_FrostedText> {
  ui.Image? _mask;
  Size _maskSize = Size.zero;
  String? _forText;
  TextStyle? _forStyle;

  @override
  void didUpdateWidget(covariant _FrostedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _mask = null;
    }
  }

  @override
  void dispose() {
    _mask?.dispose();
    super.dispose();
  }

  void _rasterise() {
    _forText = widget.text;
    _forStyle = widget.style;
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width.ceil();
    final height = painter.height.ceil();
    if (width <= 0 || height <= 0) {
      _mask = null;
      return;
    }
    _maskSize = Size(width.toDouble(), height.toDouble());
    final previous = _mask;
    try {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), Offset.zero);
      _mask = recorder.endRecording().toImageSync(width, height);
      previous?.dispose();
    } catch (_) {
      // Software rasterisers (and some headless test setups) cannot snapshot
      // synchronously; fall back to translucent white type.
      _mask = null;
      previous?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_mask == null ||
        _forText != widget.text ||
        _forStyle != widget.style) {
      _rasterise();
    }
    final mask = _mask;
    if (mask == null) {
      return Text(
        widget.text,
        style: widget.style.copyWith(
          color: Colors.white.withValues(alpha: 0.45),
        ),
      );
    }

    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => ui.ImageShader(
        mask,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.identity().storage,
      ),
      child: BackdropFilter(
        // Heavy blur: the user wanted the glass to read as glass, not as a
        // slightly soft version of the backdrop.
        filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: SizedBox(
          width: _maskSize.width,
          height: _maskSize.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Deepen the backdrop first, then add the glass's own neutral
              // body. Together they leave the glyphs clearly legible while
              // still being the blurred backdrop — and never the ink colour.
              ColoredBox(color: Colors.black.withValues(alpha: 0.26)),
              ColoredBox(color: Colors.white.withValues(alpha: 0.34)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The colon.
///
/// Drawn as two dots rather than `Text(':')`: a colon glyph sits low in its em
/// box (upper dot around the cap-height middle, lower dot on the baseline), so
/// it can never be optically centred against the numerals. Two dots are placed
/// by construction, and their size follows the chosen weight.
class _Colon extends StatelessWidget {
  const _Colon({
    required this.size,
    required this.ink,
    required this.face,
    required this.weight,
  });

  final double size;
  final Color ink;
  final ClockFace face;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    // Frosted never takes the ink colour — the colon is glass too.
    final alpha = switch (face) {
      ClockFace.solid => 1.0,
      ClockFace.translucent => 0.62,
      ClockFace.frosted => 0.42,
    };
    final color = (face == ClockFace.frosted ? Colors.white : ink)
        .withValues(alpha: alpha);
    // Heavier type gets slightly chunkier dots, like a heavier glyph would.
    final weightScale = switch (weight) {
      FontWeight.w200 => 0.86,
      FontWeight.w300 => 0.94,
      FontWeight.w400 => 1.02,
      FontWeight.w500 => 1.12,
      FontWeight.w600 => 1.22,
      _ => 1.32,
    };
    final dot = size * 0.055 * weightScale;
    final gap = size * 0.20;
    final bar = size * 0.058 * weightScale;

    return Padding(
      // Optical breathing room around the colon at display sizes.
      padding: EdgeInsets.symmetric(horizontal: size * 0.075),
      child: SizedBox(
        key: const Key('clock-colon'),
        width: bar,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dot(dot, color),
            SizedBox(height: gap),
            _dot(dot, color),
          ],
        ),
      ),
    );
  }

  Widget _dot(double diameter, Color color) => Container(
    width: diameter,
    height: diameter,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Seconds as a ring that fills over one minute, sitting right after the
/// minutes. Diameter follows the type size; stroke follows both the type size
/// and the chosen weight, so it never looks pasted on.
class _SecondRing extends StatelessWidget {
  const _SecondRing({
    required this.progress,
    required this.ink,
    required this.diameter,
    required this.stroke,
  });

  final ValueListenable<double> progress;
  final Color ink;
  final double diameter;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: diameter,
      height: diameter,
      child: CustomPaint(
        key: const Key('clock-second-ring'),
        painter: _SecondRingPainter(progress, ink, stroke),
      ),
    );
  }
}

class _SecondRingPainter extends CustomPainter {
  _SecondRingPainter(this.progress, this.ink, this.stroke)
    : super(repaint: progress);

  final ValueListenable<double> progress;
  final Color ink;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    if (radius <= 0) return;

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Colors.white.withValues(alpha: 0.18),
    );

    final t = (progress.value / 60).clamp(0.0, 1.0);
    if (t <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      2 * math.pi * t,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = ink,
    );
  }

  // Frame-to-frame repaints come from the listenable passed to `super.repaint`;
  // this only covers settings changes.
  @override
  bool shouldRepaint(covariant _SecondRingPainter oldDelegate) =>
      oldDelegate.stroke != stroke || oldDelegate.ink != ink;
}

/// `9月20日 · 星期六` in the secondary label colour, centred above the time.
class _DateLine extends StatelessWidget {
  const _DateLine({
    required this.now,
    required this.landscape,
    required this.fontFamily,
  });

  final DateTime now;
  final bool landscape;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    final weekday = _ClockViewState._weekdayNames[now.weekday - 1];
    final size = landscape ? 19.0 : 17.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${now.month}月${now.day}日',
          key: const Key('clock-date'),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.62),
            fontSize: size,
            fontWeight: FontWeight.w400,
            fontFamily: fontFamily,
            letterSpacing: 0.4,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Container(
          width: 3,
          height: 3,
          margin: EdgeInsets.symmetric(horizontal: size * 0.55),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.26),
            shape: BoxShape.circle,
          ),
        ),
        Text(
          '星期$weekday',
          key: const Key('clock-weekday'),
          style: TextStyle(
            color: AppColors.accent.withValues(alpha: 0.92),
            fontSize: size * 0.86,
            fontWeight: FontWeight.w500,
            fontFamily: fontFamily,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}
