import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/clock_settings.dart';
import '../state/player_controller.dart';
import '../theme.dart';
import 'ambient_backdrop.dart';
import 'artwork_palette.dart';

/// Full-screen shell for a single panel: shared ambient backdrop, a back chip,
/// and nothing else. Used by the media and clock routes.
class PanelScaffold extends StatelessWidget {
  const PanelScaffold({
    super.key,
    this.clockTone = false,
    this.clockBackdrop = false,
    required this.child,
  });

  final Widget child;

  /// Clock panels use their own ambience instead of the album palette.
  final bool clockTone;

  /// When true, the backdrop also follows the user's clock settings, which can
  /// switch the background to the album cover colours.
  final bool clockBackdrop;

  /// Clock ambience: neutral ink-blue and warm charcoal. No violet (the
  /// "AI purple" tell) — one amber accent against near-neutrals.
  static const _clockTone = <Color>[
    Color(0xFF101A2B),
    Color(0xFF1C1610),
    Color(0xFF0A0C10),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlayerController>();
    final st = c.state;
    final useCover =
        clockBackdrop &&
        context.watch<ClockSettings>().backdrop == ClockBackdrop.cover;
    final colors = clockTone
        ? (useCover && c.isConnected ? c.palette : _clockTone)
        : (c.isConnected ? c.palette : ArtworkPalette.fallback);

    return Scaffold(
      backgroundColor: AppColors.bg,
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AmbientBackdrop(
            colors: colors,
            playing: !clockTone && c.isConnected && st.playing && st.hasTrack,
          ),
          SafeArea(
            child: Stack(
              children: [
                Positioned.fill(child: child),
                const Positioned(top: 4, right: 12, child: _BackChip()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Quiet way back to the chooser — the system back gesture does the same.
///
/// Frosted chip: a backdrop blur over whatever panel is underneath, a hairline
/// stroke and a light-weight label. This is a glass *approximation* (blur +
/// translucent fill + hairline), not an Apple platform material. Where the
/// platform asks for high contrast we drop the blur and use a solid fill.
class _BackChip extends StatelessWidget {
  const _BackChip();

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.maybeOf(context)?.highContrast ?? false;
    final radius = BorderRadius.circular(22);

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: highContrast
            ? const Color(0xFF161A20)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: radius,
        border: Border.all(
          color: Colors.white.withValues(alpha: highContrast ? 0.22 : 0.14),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.grid_view_rounded,
            size: 13.5,
            color: Colors.white.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 5),
          Text(
            '切换',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 12,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      key: const Key('panel-back'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).maybePop();
      },
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: radius,
          // Blurs only what sits behind the chip (a small area), so the cost
          // stays local instead of re-blurring the whole panel.
          child: highContrast
              ? content
              : BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: content,
                ),
        ),
      ),
    );
  }
}
