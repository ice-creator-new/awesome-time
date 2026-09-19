import 'package:flutter/material.dart';

import '../theme.dart';

class TransportControls extends StatelessWidget {
  const TransportControls({
    super.key,
    required this.playing,
    required this.enabled,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrev,
  });

  final bool playing;
  final bool enabled;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrev;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RoundButton(
          icon: Icons.skip_previous_rounded,
          label: '上一首',
          size: 56,
          onTap: enabled ? onPrev : null,
        ),
        const SizedBox(width: 28),
        _RoundButton(
          icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          label: playing ? '暂停' : '继续',
          size: 80,
          filled: true,
          onTap: enabled ? onPlayPause : null,
        ),
        const SizedBox(width: 28),
        _RoundButton(
          icon: Icons.skip_next_rounded,
          label: '下一首',
          size: 56,
          onTap: enabled ? onNext : null,
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.size,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final double size;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final bg = filled
        ? (enabled ? AppColors.accent : AppColors.surface2)
        : AppColors.surface2;
    final fg = filled
        ? (enabled ? AppColors.bg : AppColors.muted)
        : (enabled ? AppColors.ink : AppColors.muted);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                boxShadow: filled && enabled
                    ? [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.35),
                          blurRadius: 24,
                          spreadRadius: -4,
                        ),
                      ]
                    : null,
              ),
              child: Icon(icon, size: size * 0.45, color: fg),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class VolumeRow extends StatelessWidget {
  const VolumeRow({
    super.key,
    required this.volume,
    required this.enabled,
    required this.onChange,
  });

  final double volume;
  final bool enabled;
  final ValueChanged<double> onChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          volume <= 0.01
              ? Icons.volume_off_rounded
              : volume < 0.4
              ? Icons.volume_down_rounded
              : Icons.volume_up_rounded,
          color: AppColors.muted,
          size: 22,
        ),
        Expanded(
          child: Slider(
            value: volume.clamp(0.0, 1.0),
            onChanged: enabled ? onChange : null,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${(volume * 100).round()}',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
      ],
    );
  }
}
