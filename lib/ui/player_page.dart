import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/player_controller.dart';
import 'ambient_backdrop.dart';
import 'generated_cover.dart';
import 'now_playing_slider.dart';
import 'player_icons.dart';
import 'waveform.dart';

class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlayerController>();
    final st = c.state;
    final connected = c.isConnected;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0C10),
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            AmbientBackdrop(
              colors: c.palette,
              playing: st.playing && st.hasTrack,
            ),
            SafeArea(
              top: false,
              bottom: false,
              child: connected
                  ? _NowPlaying(controller: c)
                  : _DisconnectedPanel(controller: c),
            ),
          ],
        ),
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.controller});

  final PlayerController controller;

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
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 20, 20),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final art = (constraints.maxHeight * 0.88)
                  .clamp(160.0, 420.0)
                  .clamp(0.0, constraints.maxWidth * 0.42);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: SizedBox(
                      width: art,
                      height: art,
                      child: _ArtworkHero(
                        playing: st.playing && st.hasTrack,
                        title: st.title,
                        bytes: controller.artworkBytes,
                        colors: controller.palette,
                        maxSide: art,
                      ),
                    ),
                  ),
                  const SizedBox(width: 28),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
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
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              flex: 5,
                              child: _Transport(
                                playing: st.playing,
                                enabled: true,
                                compact: true,
                                onPlayPause: controller.playPause,
                                onNext: controller.next,
                                onPrev: controller.prev,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 6,
                              child: Column(
                                children: [
                                  NowPlayingScrubber(
                                    clock: controller.clock,
                                    enabled: st.hasDuration,
                                    onSeek: controller.seekFraction,
                                  ),
                                  NowPlayingVolume(
                                    volume: st.volume,
                                    onChange: controller.setVolume,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
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
        ),
      ],
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
  });

  final bool playing;
  final String title;
  final Uint8List? bytes;
  final List<Color> colors;
  final double maxSide;

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
              child: art,
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
