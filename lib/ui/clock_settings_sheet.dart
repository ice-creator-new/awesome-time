import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/clock_settings.dart';
import '../state/player_controller.dart';
import '../theme.dart';

/// Opens the clock customisation sheet (frosted, slides up from the bottom).
Future<void> showClockSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    isScrollControlled: true,
    builder: (_) => const ClockSettingsSheet(),
  );
}

/// Everything the clock's look is made of: face family, weight, ink colour,
/// fill style, backdrop and size.
class ClockSettingsSheet extends StatelessWidget {
  const ClockSettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ClockSettings>();
    final highContrast = MediaQuery.maybeOf(context)?.highContrast ?? false;
    final radius = BorderRadius.circular(28);

    return KeyedSubtree(
      key: const Key('clock-settings-sheet'),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: Container(
            decoration: BoxDecoration(
              color: highContrast
                  ? const Color(0xFF12161C)
                  : const Color(0xFF12161C).withValues(alpha: 0.72),
              borderRadius: radius,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.10),
                width: 0.5,
              ),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '时钟定制',
                            style: TextStyle(
                              color: AppColors.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        GestureDetector(
                          key: const Key('clock-settings-close'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.of(context).maybePop(),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: Colors.white.withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    const _Label('字体'),
                    _Chips<String>(
                      value: s.font,
                      options: [
                        for (final entry in ClockSettings.fonts.entries)
                          _Option(entry.key, _fontLabel(entry.key)),
                      ],
                      onPick: (value) => s.font = value,
                    ),
                    const SizedBox(height: 20),
                    const _Label('粗细'),
                    _Chips<int>(
                      value: s.weightIndex,
                      options: [
                        for (var i = 0; i < ClockSettings.weights.length; i++)
                          _Option(i, _weightLabel(ClockSettings.weights[i])),
                      ],
                      onPick: (value) => s.weightIndex = value,
                    ),
                    const SizedBox(height: 20),
                    const _Label('颜色'),
                    _Swatches(
                      value: s.ink,
                      // The "cover" swatch previews the album colours that are
                      // actually playing right now.
                      coverColors: context.watch<PlayerController>().palette,
                      onPick: (value) => s.ink = value,
                    ),
                    const SizedBox(height: 20),
                    const _Label('字形'),
                    _Chips<ClockFace>(
                      value: s.face,
                      options: [
                        for (final face in ClockFace.values)
                          _Option(face, face.label),
                      ],
                      onPick: (value) => s.face = value,
                    ),
                    const SizedBox(height: 20),
                    const _Label('背景'),
                    _Chips<ClockBackdrop>(
                      value: s.backdrop,
                      options: [
                        for (final backdrop in ClockBackdrop.values)
                          _Option(backdrop, backdrop.label),
                      ],
                      onPick: (value) => s.backdrop = value,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const _Label('字号'),
                        const Spacer(),
                        Text(
                          '${(s.scale * 100).round()}%',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        activeTrackColor: AppColors.accent,
                        inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                        thumbColor: Colors.white,
                        overlayShape: SliderComponentShape.noOverlay,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7,
                        ),
                      ),
                      child: Slider(
                        key: const Key('clock-settings-scale'),
                        value: s.scale,
                        min: 0.8,
                        max: 1.25,
                        onChanged: (value) => s.scale = value,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: GestureDetector(
                        key: const Key('clock-settings-reset'),
                        behavior: HitTestBehavior.opaque,
                        onTap: s.reset,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.16),
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            '恢复默认',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _fontLabel(String key) => switch (key) {
    'system' => '系统',
    'mono' => '等宽',
    'serif' => '衬线',
    _ => '窄体',
  };

  static String _weightLabel(FontWeight weight) => switch (weight.value) {
    200 => '极细',
    300 => '细',
    400 => '常规',
    500 => '中',
    600 => '中粗',
    _ => '粗',
  };
}

class _Option<T> {
  const _Option(this.value, this.label);

  final T value;
  final String label;
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.45),
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.6,
        ),
      ),
    );
  }
}

/// Pill row. One shape language with the rest of the app: full-radius pills,
/// hairline strokes, no shadows.
class _Chips<T> extends StatelessWidget {
  const _Chips({
    required this.value,
    required this.options,
    required this.onPick,
  });

  final T value;
  final List<_Option<T>> options;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          Builder(
            builder: (context) {
              final selected = option.value == value;
              return GestureDetector(
                key: Key('chip-${option.label}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onPick(option.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.92)
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(
                        alpha: selected ? 0.0 : 0.12,
                      ),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    option.label,
                    style: TextStyle(
                      color: selected
                          ? Colors.black
                          : Colors.white.withValues(alpha: 0.78),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Ink colour swatches. The last one follows the album cover and is drawn as
/// a three-stop sweep so it reads as "whatever is playing".
class _Swatches extends StatelessWidget {
  const _Swatches({required this.value, required this.onPick, this.coverColors});

  final ClockInk value;
  final ValueChanged<ClockInk> onPick;
  final List<Color>? coverColors;

  @override
  Widget build(BuildContext context) {
    final cover = coverColors ?? const <Color>[];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final option in ClockInk.values)
          Builder(
            builder: (context) {
              final selected = option == value;
              return GestureDetector(
                key: Key('swatch-${option.name}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onPick(option),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(
                        alpha: selected ? 0.85 : 0.14,
                      ),
                      width: selected ? 1.5 : 0.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: option == ClockInk.cover && cover.isEmpty
                            ? AppColors.muted
                            : option.resolve(cover),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
