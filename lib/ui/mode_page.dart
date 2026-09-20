import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/player_controller.dart';
import '../theme.dart';
import 'ambient_backdrop.dart';
import 'artwork_palette.dart';
import 'generated_cover.dart';

/// Chooser shown right after connecting.
///
/// Cards always scroll horizontally (portrait and landscape alike). What
/// changes with orientation is the *card content*: portrait stacks the preview
/// above its label, landscape puts the preview beside it.
class ModePage extends StatefulWidget {
  const ModePage({super.key});

  @override
  State<ModePage> createState() => _ModePageState();
}

class _ModePageState extends State<ModePage> {
  /// Clock ambience, lerped in as the clock card takes over the screen.
  /// Neutral ink-blue and warm charcoal (no violet).
  static const _clockTone = <Color>[
    Color(0xFF101A2B),
    Color(0xFF1C1610),
    Color(0xFF0A0C10),
  ];

  PageController? _pager;
  bool? _landscape;
  double _page = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height * 1.2;
    if (_landscape == landscape) return;
    _landscape = landscape;
    _page = 0;
    _pager?.removeListener(_onScroll);
    _pager?.dispose();
    _pager = PageController(
      // Portrait: a wide-ish card so the stacked preview still reads. Landscape:
      // a narrow column beside its label.
      viewportFraction: landscape ? 0.30 : 0.78,
    )..addListener(_onScroll);
  }

  void _onScroll() {
    final next = _pager?.page;
    if (next == null) return;
    if ((next - _page).abs() < 0.001) return;
    // A viewport that just changed size — a rotation, a window resize — reports
    // its new position while the framework is still building, and marking the
    // tree dirty there throws. Defer that one update to the end of the frame.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final value = _pager?.page;
        if (value == null || (value - _page).abs() < 0.001) return;
        setState(() => _page = value);
      });
      return;
    }
    setState(() => _page = next);
  }

  @override
  void dispose() {
    _pager?.removeListener(_onScroll);
    _pager?.dispose();
    super.dispose();
  }

  void _open(int index) {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pushNamed(index == 0 ? '/media' : '/clock');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlayerController>();
    final st = c.state;
    final landscape = _landscape ?? false;
    final t = Curves.easeInOutCubic.transform(_page.clamp(0.0, 1.0));
    final media = c.isConnected ? c.palette : ArtworkPalette.fallback;
    final colors = <Color>[
      for (var i = 0; i < 3; i++)
        Color.lerp(_toneAt(media, i), _clockTone[i], t * 0.9)!,
    ];

    return Scaffold(
      backgroundColor: AppColors.bg,
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AmbientBackdrop(
            colors: colors,
            playing: c.isConnected && st.playing && st.hasTrack,
          ),
          SafeArea(
            child: Column(
              children: [
                SizedBox(height: landscape ? 4 : 12),
                Text(
                  '妙时',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: landscape ? 17 : 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: landscape ? 3 : 4,
                  ),
                ),
                SizedBox(height: landscape ? 3 : 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _subtitle(c, st.title, st.artist),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: landscape ? 11.5 : 12.5,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                SizedBox(height: landscape ? 8 : 18),
                Expanded(
                  child: PageView(
                    // Always horizontal: the swipe never changes with rotation.
                    scrollDirection: Axis.horizontal,
                    controller: _pager,
                    children: [
                      _ModeCard(
                        key: const Key('mode-media'),
                        page: _page,
                        index: 0,
                        landscape: landscape,
                        label: '媒体',
                        caption: '电脑播放，手机同步',
                        preview: _ArtworkPreview(controller: c),
                        previewKey: const Key('mode-media-preview'),
                        labelKey: const Key('mode-media-label'),
                      ),
                      _ModeCard(
                        key: const Key('mode-clock'),
                        page: _page,
                        index: 1,
                        landscape: landscape,
                        label: '时钟',
                        caption: '超大时间与日历',
                        preview: const _MiniClock(),
                        previewKey: const Key('mode-clock-preview'),
                        labelKey: const Key('mode-clock-label'),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: landscape ? 12 : 18),
                _Dots(page: _page),
                SizedBox(height: landscape ? 10 : 16),
                _EnterButton(
                  current: _page < 0.5 ? 0 : 1,
                  onPressed: () => _open(_page < 0.5 ? 0 : 1),
                ),
                SizedBox(height: landscape ? 4 : 9),
                Text(
                  '左右滑动选择',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.34),
                    fontSize: 11.5,
                    letterSpacing: 0.8,
                  ),
                ),
                SizedBox(height: landscape ? 6 : 14),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _subtitle(PlayerController c, String title, String artist) {
    if (!c.isConnected) return '未连接';
    if (title.isEmpty) return '已连接 ${c.host}';
    return artist.isEmpty ? title : '$title · $artist';
  }

  static Color _toneAt(List<Color> palette, int i) {
    if (i < palette.length) return palette[i];
    final fb = ArtworkPalette.fallback;
    return fb[i % fb.length];
  }
}

/// A card that turns and fades as it leaves the centre.
///
/// Purely presentational: the chooser's own button is the single, reliable
/// commit action (a tap target that can sit geometrically outside a
/// fractionally-sized [PageView] page is a hit-test trap).
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    super.key,
    required this.page,
    required this.index,
    required this.landscape,
    required this.label,
    required this.caption,
    required this.preview,
    required this.previewKey,
    required this.labelKey,
  });

  final double page;
  final int index;
  final bool landscape;
  final String label;
  final String caption;
  final Widget preview;
  final Key previewKey;
  final Key labelKey;

  @override
  Widget build(BuildContext context) {
    final delta = (page - index).clamp(-1.0, 1.0);
    final t = delta.abs();
    final scale = 1 - 0.12 * t;

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0015)
        ..rotateY(delta * 0.30)
        ..scaleByDouble(scale, scale, 1, 1),
      child: Opacity(
        opacity: (1 - 0.5 * t).clamp(0.0, 1.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              color: Colors.white.withValues(alpha: 0.055),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 34,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              // Orientation only re-arranges the inside of the card: portrait
              // stacks preview over label, landscape puts them side by side.
              child: landscape
                  ? Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: KeyedSubtree(key: previewKey, child: preview),
                        ),
                        Expanded(
                          flex: 4,
                          child: KeyedSubtree(
                            key: labelKey,
                            child: _SideLabel(label: label, caption: caption, t: t),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: KeyedSubtree(key: previewKey, child: preview),
                        ),
                        KeyedSubtree(
                          key: labelKey,
                          child: _BottomLabel(
                            label: label,
                            caption: caption,
                            t: t,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Portrait: label row under the preview.
class _BottomLabel extends StatelessWidget {
  const _BottomLabel({
    required this.label,
    required this.caption,
    required this.t,
  });

  final String label;
  final String caption;
  final double t;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 18, 16),
      child: Row(
        children: [
          Expanded(child: _LabelText(label: label, caption: caption)),
          Icon(
            Icons.arrow_forward_rounded,
            size: 19,
            color: AppColors.accent.withValues(alpha: 0.3 + 0.7 * (1 - t)),
          ),
        ],
      ),
    );
  }
}

/// Landscape: label column beside the preview.
class _SideLabel extends StatelessWidget {
  const _SideLabel({
    required this.label,
    required this.caption,
    required this.t,
  });

  final String label;
  final String caption;
  final double t;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 26, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 3),
          _LabelText(label: label, caption: caption),
          const Spacer(flex: 4),
          Icon(
            Icons.arrow_forward_rounded,
            size: 19,
            color: AppColors.accent.withValues(alpha: 0.3 + 0.7 * (1 - t)),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _LabelText extends StatelessWidget {
  const _LabelText({required this.label, required this.caption});

  final String label;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 19,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          caption,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

/// Live album art (or a generated cover when nothing is playing).
class _ArtworkPreview extends StatelessWidget {
  const _ArtworkPreview({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final st = controller.state;
    final bytes = controller.artworkBytes;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (bytes != null)
          Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
        else
          GeneratedCover(
            title: st.hasTrack ? st.title : '妙时',
            colors: controller.palette,
          ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: [
                  Colors.black.withValues(alpha: 0.5),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Live clock preview — same Ticker discipline as the real clock panel.
class _MiniClock extends StatefulWidget {
  const _MiniClock();

  @override
  State<_MiniClock> createState() => _MiniClockState();
}

class _MiniClockState extends State<_MiniClock>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late DateTime _now;
  late int _second;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _second = _now.second;
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration _) {
    final now = DateTime.now();
    if (now.second == _second) return;
    setState(() {
      _now = now;
      _second = now.second;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF16202F), Color(0xFF0B0E14)],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(hh, key: const Key('mini-clock-hour'), style: _style),
                Text(':', style: _style.copyWith(color: AppColors.muted)),
                Text(mm, key: const Key('mini-clock-minute'), style: _style),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _style = TextStyle(
    color: AppColors.ink,
    fontSize: 96,
    fontWeight: FontWeight.w200,
    letterSpacing: -4,
    height: 1.05,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// The explicit commit step: swiping only browses, this is what enters.
class _EnterButton extends StatelessWidget {
  const _EnterButton({required this.current, required this.onPressed});

  final int current;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      key: const Key('mode-enter'),
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        minimumSize: const Size(210, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      child: Text(
        current == 0 ? '进入媒体' : '进入时钟',
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// Two dots; the active one stretches into a capsule. Always horizontal, in
/// step with the always-horizontal swipe.
class _Dots extends StatelessWidget {
  const _Dots({required this.page});

  final double page;

  @override
  Widget build(BuildContext context) {
    final t = page.clamp(0.0, 1.0);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 2; i++)
          Builder(
            builder: (context) {
              final near = (1 - (t - i).abs()).clamp(0.0, 1.0);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 8 + 12 * near,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22 + 0.55 * near),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            },
          ),
      ],
    );
  }
}
