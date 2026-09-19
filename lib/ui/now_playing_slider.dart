import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../state/playback_clock.dart';
import 'player_icons.dart';

/// Thin Apple Music scrubber. Progress is driven by [PlaybackClock] at display refresh.
class NowPlayingScrubber extends StatefulWidget {
  const NowPlayingScrubber({
    super.key,
    required this.clock,
    required this.enabled,
    required this.onSeek,
  });

  final PlaybackClock clock;
  final bool enabled;
  final ValueChanged<double> onSeek;

  @override
  State<NowPlayingScrubber> createState() => _NowPlayingScrubberState();
}

class _NowPlayingScrubberState extends State<NowPlayingScrubber>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double? _drag;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (_drag == null && mounted) setState(() {});
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _drag ?? widget.clock.progress;
    final pos = _drag == null
        ? Duration(milliseconds: widget.clock.positionMs)
        : Duration(
            milliseconds: (widget.clock.durationMs * (_drag ?? 0)).round(),
          );
    final remaining = Duration(milliseconds: widget.clock.durationMs) - pos;
    final hasDuration = widget.clock.durationMs > 0;

    return Column(
      children: [
        _HairlineSlider(
          value: hasDuration ? progress : 0,
          enabled: widget.enabled && hasDuration,
          onChanged: (v) => setState(() => _drag = v),
          onChangeEnd: (v) {
            setState(() => _drag = null);
            HapticFeedback.selectionClick();
            widget.onSeek(v);
          },
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(formatClock(pos), style: _timeStyle),
            const Spacer(),
            Text(
              hasDuration
                  ? '-${formatClock(remaining.isNegative ? Duration.zero : remaining)}'
                  : '--:--',
              style: _timeStyle,
            ),
          ],
        ),
      ],
    );
  }
}

const _timeStyle = TextStyle(
  color: Color(0xB3FFFFFF),
  fontSize: 12,
  fontWeight: FontWeight.w500,
  letterSpacing: 0.2,
  fontFeatures: [FontFeature.tabularFigures()],
);

class NowPlayingVolume extends StatelessWidget {
  const NowPlayingVolume({
    super.key,
    required this.volume,
    required this.onChange,
  });

  final double volume;
  final ValueChanged<double> onChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const PlayerIcon(
          glyph: PlayerGlyph.volumeMin,
          color: Color(0x99FFFFFF),
          size: 20,
        ),
        Expanded(
          child: _HairlineSlider(
            value: volume.clamp(0.0, 1.0),
            enabled: true,
            onChanged: onChange,
            onChangeEnd: onChange,
          ),
        ),
        const PlayerIcon(
          glyph: PlayerGlyph.volumeMax,
          color: Color(0x99FFFFFF),
          size: 20,
        ),
      ],
    );
  }
}

class _HairlineSlider extends StatefulWidget {
  const _HairlineSlider({
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_HairlineSlider> createState() => _HairlineSliderState();
}

class _HairlineSliderState extends State<_HairlineSlider>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 320),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _setActive(bool on) {
    if (_active == on) return;
    _active = on;
    if (on) {
      _press.forward();
    } else {
      _press.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.enabled ? (_) => _setActive(true) : null,
          onTapCancel: widget.enabled ? () => _setActive(false) : null,
          onHorizontalDragStart: widget.enabled
              ? (d) {
                  _setActive(true);
                  widget.onChanged((d.localPosition.dx / width).clamp(0.0, 1.0));
                }
              : null,
          onHorizontalDragUpdate: widget.enabled
              ? (d) => widget.onChanged(
                    (d.localPosition.dx / width).clamp(0.0, 1.0),
                  )
              : null,
          onHorizontalDragEnd: widget.enabled
              ? (_) {
                  _setActive(false);
                  widget.onChangeEnd(v);
                }
              : null,
          onTapUp: widget.enabled
              ? (d) {
                  final next = (d.localPosition.dx / width).clamp(0.0, 1.0);
                  widget.onChanged(next);
                  widget.onChangeEnd(next);
                  _setActive(false);
                }
              : null,
          child: SizedBox(
            height: 36,
            width: double.infinity,
            child: AnimatedBuilder(
              animation: _press,
              builder: (context, _) {
                final t = Curves.easeOutCubic.transform(_press.value);
                final trackH = 3.0 + 9.0 * t;
                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: trackH,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Color.lerp(
                          const Color(0x33FFFFFF),
                          const Color(0x55FFFFFF),
                          t,
                        ),
                        borderRadius: BorderRadius.circular(trackH),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: v,
                      child: Container(
                        key: const Key('seek-fill'),
                        height: trackH,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(trackH),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
