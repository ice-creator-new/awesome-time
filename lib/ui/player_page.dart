import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/player_controller.dart';
import 'generated_cover.dart';
import 'now_playing_slider.dart';
import 'player_icons.dart';
import 'waveform.dart';

/// Media panel: the now-playing instrument.
///
/// Deliberately has no scaffold or background of its own — the home pager
/// slides it over the shared ambient backdrop.
class MediaView extends StatelessWidget {
  const MediaView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlayerController>();
    return c.isConnected
        ? _NowPlaying(controller: c)
        : _DisconnectedPanel(controller: c);
  }
}

class _NowPlaying extends StatefulWidget {
  const _NowPlaying({required this.controller});

  final PlayerController controller;

  @override
  State<_NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<_NowPlaying> {
  /// Landscape only: the transport rides the cover, starts hidden, and fades
  /// out again once the user stops interacting with it.
  static const Duration _autoHideAfter = Duration(seconds: 5);

  bool _controlsVisible = false;
  Timer? _hideTimer;

  PlayerController get controller => widget.controller;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_autoHideAfter, () {
      if (!mounted) return;
      setState(() => _controlsVisible = false);
    });
  }

  /// Any deliberate interaction — tapping the cover or pressing a transport
  /// button — restarts the countdown.
  void _keepControlsAlive() {
    if (_controlsVisible) _restartHideTimer();
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      _hideTimer = null;
      setState(() => _controlsVisible = false);
    } else {
      setState(() => _controlsVisible = true);
      _restartHideTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return landscape ? _landscape(context) : _portrait(context);
  }

  Widget _portrait(BuildContext context) {
    final st = controller.state;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: _ArtworkHero(
                  playing: st.playing && st.hasTrack,
                  title: st.title,
                  bytes: controller.artworkBytes,
                  colors: controller.palette,
                  maxSide: 360,
                  // Spectrum rides the cover: bottom-aligned with no gap, and
                  // clipped by the cover's rounded corners.
                  overlay: Align(
                    alignment: Alignment.bottomCenter,
                    child: DecoratedBox(
                      // Faint scrim: the meter has to stay legible on pale
                      // artwork, and it keeps the bottom edge from reading as a
                      // hard cut.
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0x8A000000), Color(0x00000000)],
                        ),
                      ),
                      child: FractionallySizedBox(
                        heightFactor: 0.38,
                        widthFactor: 1,
                        child: Waveform(
                          spectrum: controller.spectrum,
                          playing: st.playing && st.hasTrack,
                          colors: controller.palette,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          _PlaybackStack(controller: controller, compact: false),
        ],
      ),
    );
  }

  Widget _landscape(BuildContext context) {
    final st = controller.state;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 20, 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Cover spans the content box, so the title shares its top edge and
          // the meter shares its bottom edge.
          final art = constraints.maxHeight
              .clamp(120.0, 900.0)
              .clamp(0.0, constraints.maxWidth * 0.52);
          final waveHeight = (constraints.maxHeight * 0.28).clamp(56.0, 108.0);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  key: const Key('cover-tap'),
                  // Tap the cover to show/hide the transport.
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  child: SizedBox(
                    width: art,
                    height: art,
                    child: _ArtworkHero(
                      playing: st.playing && st.hasTrack,
                      title: st.title,
                      bytes: controller.artworkBytes,
                      colors: controller.palette,
                      maxSide: art,
                      overlay: _coverControls(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 28),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TitleBlock(
                      title: st.hasTrack ? st.title : '等待媒体…',
                      artist: st.hasTrack
                          ? [
                              if (st.artist.isNotEmpty) st.artist,
                              if (st.album.isNotEmpty) st.album,
                            ].join(' · ')
                          : (st.source.isEmpty ? '电脑上开始播放' : st.source),
                      hasTrack: st.hasTrack,
                      compact: true,
                    ),
                    const SizedBox(height: 14),
                    // Progress takes 2/3, volume 1/3; each keeps its labels
                    // underneath the bar.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: NowPlayingScrubber(
                            clock: controller.clock,
                            enabled: st.hasDuration,
                            onSeek: controller.seekFraction,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          flex: 1,
                          child: NowPlayingVolume(
                            volume: st.volume,
                            onChange: controller.setVolume,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(
                      height: waveHeight,
                      child: ClipRect(
                        child: Waveform(
                          spectrum: controller.spectrum,
                          playing: st.playing && st.hasTrack,
                          colors: controller.palette,
                          expanded: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Landscape transport, painted on the cover and toggled by tapping it.
  Widget _coverControls() {
    final st = controller.state;
    return IgnorePointer(
      ignoring: !_controlsVisible,
      child: AnimatedOpacity(
        key: const Key('cover-controls'),
        opacity: _controlsVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: ColoredBox(
          // Light scrim so white glyphs stay readable on pale covers.
          color: Colors.black.withValues(alpha: 0.26),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _Transport(
                playing: st.playing,
                enabled: true,
                compact: true,
                onPlayPause: () {
                  controller.playPause();
                  _keepControlsAlive();
                },
                onNext: () {
                  controller.next();
                  _keepControlsAlive();
                },
                onPrev: () {
                  controller.prev();
                  _keepControlsAlive();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaybackStack extends StatelessWidget {
  const _PlaybackStack({required this.controller, required this.compact});

  final PlayerController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final st = controller.state;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TitleBlock(
          title: st.hasTrack ? st.title : '等待媒体…',
          artist: st.hasTrack
              ? [
                  if (st.artist.isNotEmpty) st.artist,
                  if (st.album.isNotEmpty) st.album,
                ].join(' · ')
              : (st.source.isEmpty ? '电脑上开始播放' : st.source),
          hasTrack: st.hasTrack,
          compact: compact,
        ),
        SizedBox(height: compact ? 12 : 16),
        NowPlayingScrubber(
          clock: controller.clock,
          enabled: st.hasDuration,
          onSeek: controller.seekFraction,
        ),
        SizedBox(height: compact ? 8 : 12),
        _Transport(
          playing: st.playing,
          enabled: true,
          onPlayPause: controller.playPause,
          onNext: controller.next,
          onPrev: controller.prev,
        ),
        SizedBox(height: compact ? 4 : 8),
        NowPlayingVolume(volume: st.volume, onChange: controller.setVolume),
      ],
    );
  }
}

class _ArtworkHero extends StatelessWidget {
  const _ArtworkHero({
    required this.playing,
    required this.title,
    required this.bytes,
    required this.colors,
    this.maxSide = 360,
    this.overlay,
  });

  final bool playing;
  final String title;
  final Uint8List? bytes;
  final List<Color> colors;
  final double maxSide;

  /// Painted on top of the artwork, inside the cover's rounded clip.
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final art = bytes == null
        ? GeneratedCover(title: title, colors: colors)
        : Image.memory(
            bytes!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.biggest.shortestSide;
        final side = available.clamp(0.0, maxSide);
        return AnimatedScale(
          scale: playing ? 1.0 : 0.88,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeInOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeInOutCubic,
            width: side,
            height: side,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: playing ? 0.40 : 0.18),
                  blurRadius: playing ? 32 : 14,
                  offset: Offset(0, playing ? 16 : 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  art,
                  ?overlay,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.title,
    required this.artist,
    required this.hasTrack,
    this.compact = false,
  });

  final String title;
  final String artist;
  final bool hasTrack;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: hasTrack ? 1 : 0.55),
            fontSize: compact ? 18 : 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: compact ? 15 : 17,
            fontWeight: FontWeight.w400,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({
    required this.playing,
    required this.enabled,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrev,
    this.compact = false,
  });

  final bool playing;
  final bool enabled;
  final bool compact;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrev;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? Colors.white : Colors.white38;
    return Row(
      children: [
        Expanded(
          child: _TransportButton(
            glyph: PlayerGlyph.prev,
            size: compact ? 24 : 28,
            color: color,
            label: '上一首',
            onTap: enabled ? onPrev : null,
          ),
        ),
        Expanded(
          child: _TransportButton(
            glyph: playing ? PlayerGlyph.pause : PlayerGlyph.play,
            size: compact ? 36 : 46,
            color: color,
            label: playing ? '暂停' : '播放',
            onTap: enabled ? onPlayPause : null,
          ),
        ),
        Expanded(
          child: _TransportButton(
            glyph: PlayerGlyph.next,
            size: compact ? 24 : 28,
            color: color,
            label: '下一首',
            onTap: enabled ? onNext : null,
          ),
        ),
      ],
    );
  }
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.glyph,
    required this.size,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final PlayerGlyph glyph;
  final double size;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Semantics(
            button: true,
            label: label,
            child: Center(
              child: PlayerIcon(glyph: glyph, size: size, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

class _DisconnectedPanel extends StatelessWidget {
  const _DisconnectedPanel({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.link_off_rounded,
            size: 48,
            color: Colors.white.withValues(alpha: 0.55),
          ),
          const SizedBox(height: 16),
          const Text(
            '桥接未连接',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            controller.statusMessage ?? '在电脑上启动 bridge，填写局域网地址后连接。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 15,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: controller.leaveToConnect,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              minimumSize: const Size(180, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: const Text('前往连接'),
          ),
        ],
      ),
    );
  }
}
