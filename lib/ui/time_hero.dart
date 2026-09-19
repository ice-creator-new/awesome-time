import 'package:flutter/material.dart';

import '../format.dart';
import '../theme.dart';

/// Signature hero: giant remaining-time with a hairline progress rail.
class TimeHero extends StatelessWidget {
  const TimeHero({
    super.key,
    required this.position,
    required this.duration,
    required this.progress,
    required this.playing,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final double progress;
  final bool playing;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    final remaining = duration - position;
    final hasDuration = duration.inMilliseconds > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'REMAINING',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasDuration
                        ? formatRemainingLabel(
                            remaining.isNegative ? Duration.zero : remaining,
                          )
                        : '--:--',
                    key: const ValueKey('remaining'),
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 72,
                      fontWeight: FontWeight.w300,
                      letterSpacing: -3,
                      height: 1.0,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'ELAPSED',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasDuration ? formatClock(position) : '--:--',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _ProgressRail(
          progress: hasDuration ? progress : 0,
          enabled: hasDuration,
          onSeek: onSeek,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              hasDuration ? formatClock(position) : '00:00',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              playing ? 'PLAYING' : (hasDuration ? 'PAUSED' : 'STANDBY'),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: playing ? AppColors.accent : AppColors.muted,
              ),
            ),
            Text(
              hasDuration ? formatClock(duration) : '--:--',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProgressRail extends StatefulWidget {
  const _ProgressRail({
    required this.progress,
    required this.enabled,
    required this.onSeek,
  });

  final double progress;
  final bool enabled;
  final ValueChanged<double> onSeek;

  @override
  State<_ProgressRail> createState() => _ProgressRailState();
}

class _ProgressRailState extends State<_ProgressRail> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final value = _drag ?? widget.progress;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const railH = 6.0;
        return GestureDetector(
          onHorizontalDragStart: widget.enabled
              ? (d) => _drag = (d.localPosition.dx / width).clamp(0.0, 1.0)
              : null,
          onHorizontalDragUpdate: widget.enabled
              ? (d) => setState(() {
                  _drag = (d.localPosition.dx / width).clamp(0.0, 1.0);
                })
              : null,
          onHorizontalDragEnd: widget.enabled
              ? (_) {
                  final v = _drag ?? widget.progress;
                  setState(() => _drag = null);
                  widget.onSeek(v);
                }
              : null,
          onTapUp: widget.enabled
              ? (d) {
                  final v = (d.localPosition.dx / width).clamp(0.0, 1.0);
                  setState(() => _drag = null);
                  widget.onSeek(v);
                }
              : null,
          child: SizedBox(
            height: 28,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: railH,
                  decoration: BoxDecoration(
                    color: AppColors.track,
                    borderRadius: BorderRadius.circular(railH),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: value.clamp(0.0, 1.0),
                  child: Container(
                    height: railH,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(railH),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment(-1 + 2 * value.clamp(0.0, 1.0), 0),
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.ink,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.bg, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.45),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
