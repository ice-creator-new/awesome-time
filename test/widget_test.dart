import 'package:awesome_time/main.dart';
import 'package:awesome_time/services/device_discovery.dart';
import 'package:awesome_time/state/player_controller.dart';
import 'package:awesome_time/theme.dart';
import 'package:awesome_time/ui/ambient_backdrop.dart';
import 'package:awesome_time/ui/connection_page.dart';
import 'package:awesome_time/ui/player_icons.dart';
import 'package:awesome_time/ui/waveform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Future<List<DiscoveredBridge>> _noDevices() async => const [];

Future<List<DiscoveredBridge>> _oneBridge() async => const [
  DiscoveredBridge(ip: '192.168.1.10', port: 8765, name: 'iMac'),
];

Future<List<DiscoveredBridge>> _twoBridges() async => const [
  DiscoveredBridge(ip: '192.168.1.10', port: 8765, name: 'iMac'),
  DiscoveredBridge(ip: '192.168.1.22', port: 8765, name: 'MacBook Pro'),
];

/// Pumps the pairing page in isolation so discovery is a deterministic fake
/// (no UDP socket, no pending timers).
Widget _pairingPage(Future<List<DiscoveredBridge>> Function() discover) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: ChangeNotifierProvider(
      create: (_) => PlayerController(),
      child: ConnectionPage(discover: discover),
    ),
  );
}

Future<void> _pumpScan(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

/// Runs the pairing flow in demo mode, landing on the chooser.
Future<void> _openChooser(WidgetTester tester) async {
  await tester.pumpWidget(AwesomeTimeApp(discover: _noDevices));
  await _pumpScan(tester);
  await tester.tap(find.text('演示模式'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
}

/// Swipes (if needed) and presses the chooser's explicit enter button.
///
/// The clock card starts parked off screen, so it is swiped in first — exactly
/// what a user has to do before the button offers the clock.
Future<void> _enterPanel(WidgetTester tester, {required bool clock}) async {
  if (clock) {
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    // The swipe is horizontal in every orientation.
    await tester.fling(
      find.byType(PageView),
      Offset(-size.width * 0.35, 0),
      1600,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.text('进入时钟'),
      findsOneWidget,
      reason: 'swiping should hand the chooser over to the clock card',
    );
  }
  await tester.tap(find.byKey(const Key('mode-enter')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  expect(
    find.byKey(const Key('mode-enter')),
    findsNothing,
    reason: 'entering should leave the chooser',
  );
}

void main() {
  testWidgets('pairing page: large title, one primary action, folded extras', (
    tester,
  ) async {
    await tester.pumpWidget(_pairingPage(_noDevices));
    await _pumpScan(tester);

    expect(find.text('妙时'), findsOneWidget);
    expect(find.text('选择要连接的电脑'), findsOneWidget);
    expect(find.text('连接'), findsOneWidget);
    expect(find.text('其他方式'), findsOneWidget);
    expect(find.text('演示模式'), findsOneWidget);
    expect(find.text('手动输入地址'), findsOneWidget);
  });

  testWidgets('a single discovered bridge is offered, never auto-chosen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_pairingPage(_oneBridge));
    await _pumpScan(tester);

    // The bridge is listed...
    expect(find.text('iMac'), findsOneWidget);
    expect(find.text('192.168.1.10:8765'), findsOneWidget);
    // ...but nothing is checked for the user...
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    // ...and the app stays on the pairing page (no sneaking into playback).
    expect(find.text('选择要连接的电脑'), findsOneWidget);
    expect(find.byType(Waveform), findsNothing);
    // Tapping is what selects.
    await tester.tap(find.text('iMac'));
    await tester.pump();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('pairing page fits landscape without overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_pairingPage(_twoBridges));
    await _pumpScan(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('连接'), findsOneWidget);
    expect(find.text('iMac'), findsOneWidget);
    expect(find.text('MacBook Pro'), findsOneWidget);
    expect(find.text('选择要连接的电脑'), findsOneWidget);
  });

  testWidgets('pairing page fits a short portrait screen', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_pairingPage(_noDevices));
    await _pumpScan(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('连接'), findsOneWidget);
  });

  testWidgets('chooser offers both panels and previews them live', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openChooser(tester);

    expect(find.byKey(const Key('mode-media')), findsOneWidget);
    expect(find.byKey(const Key('mode-clock')), findsOneWidget);
    expect(find.text('媒体'), findsOneWidget);
    expect(find.text('时钟'), findsOneWidget);
    // Nothing has been entered yet — these are the chooser's own cards.
    expect(find.byKey(const Key('clock-hour')), findsNothing);
    expect(find.byKey(const Key('cover-tap')), findsNothing);

    // The clock card carries a running preview.
    final miniHour = tester
        .widget<Text>(find.byKey(const Key('mini-clock-hour')))
        .data!;
    final miniMinute = tester
        .widget<Text>(find.byKey(const Key('mini-clock-minute')))
        .data!;
    expect(RegExp(r'^\d{2}$').hasMatch(miniHour), isTrue, reason: miniHour);
    expect(RegExp(r'^\d{2}$').hasMatch(miniMinute), isTrue, reason: miniMinute);
    expect(find.text('进入媒体'), findsOneWidget);
    expect(find.text('左右滑动选择'), findsOneWidget);
  });

  testWidgets('chooser scrolls sideways in portrait, cards stacked inside', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openChooser(tester);

    final media = tester.getRect(find.byKey(const Key('mode-media')));
    final clock = tester.getRect(find.byKey(const Key('mode-clock')));
    // Cards sit in a row even in portrait: the swipe is horizontal.
    expect((clock.top - media.top).abs(), lessThan(1));
    expect(clock.left, greaterThan(media.left));
    // Each card is a tall composition: preview above its label.
    expect(media.height, greaterThan(media.width));
    final preview = tester.getRect(find.byKey(const Key('mode-media-preview')));
    final label = tester.getRect(find.byKey(const Key('mode-media-label')));
    expect(preview.top, lessThan(label.top));
    expect((preview.left - label.left).abs(), lessThan(1));
    expect(preview.bottom, lessThanOrEqualTo(label.top + 1));

    // Swiping left hands the centre to the clock card.
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1600);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final clockAfter = tester.getCenter(find.byKey(const Key('mode-clock')));
    expect(clockAfter.dx, greaterThan(0));
    expect(clockAfter.dx, lessThan(400));

    await tester.tap(find.byKey(const Key('mode-enter')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('clock-hour')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('chooser keeps the same row in landscape, cards laid out side '
      'by side', (tester) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openChooser(tester);

    final media = tester.getRect(find.byKey(const Key('mode-media')));
    final clock = tester.getRect(find.byKey(const Key('mode-clock')));
    // Same row, clock to the right …
    expect((clock.top - media.top).abs(), lessThan(1));
    expect(clock.left, greaterThan(media.left));
    // … and each card is still a tall column, but its content is now a row:
    // preview on the left, label beside it.
    expect(media.height, greaterThan(media.width));
    final preview = tester.getRect(find.byKey(const Key('mode-media-preview')));
    final label = tester.getRect(find.byKey(const Key('mode-media-label')));
    expect((preview.top - label.top).abs(), lessThan(1));
    expect(preview.left, lessThan(label.left));
    expect(preview.right, lessThanOrEqualTo(label.left + 1));

    expect(find.text('左右滑动选择'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _enterPanel(tester, clock: true);
    expect(find.byKey(const Key('clock-hour')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the switch chip returns from a panel to the chooser', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openChooser(tester);
    await _enterPanel(tester, clock: false);
    expect(find.text('夜空中最亮的星'), findsOneWidget);
    expect(find.byKey(const Key('panel-back')), findsOneWidget);

    await tester.tap(find.byKey(const Key('panel-back')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(const Key('mode-media')), findsOneWidget);
    expect(find.byKey(const Key('mode-clock')), findsOneWidget);
    expect(find.byKey(const Key('panel-back')), findsNothing);

    // …and the clock panel opens the same way.
    await _enterPanel(tester, clock: true);
    expect(find.byKey(const Key('clock-hour')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('demo mode opens now playing with artwork title', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openChooser(tester);
    await _enterPanel(tester, clock: false);

    expect(find.text('夜空中最亮的星'), findsOneWidget);
    expect(find.textContaining('逃跑计划'), findsOneWidget);
    expect(find.text('正在播放'), findsNothing);
    // Portrait: the spectrum is painted on the cover and clipped by its radius.
    expect(find.byType(Waveform), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(Waveform),
        matching: find.byType(ClipRRect),
      ),
      findsWidgets,
    );
  });

  testWidgets('landscape aligns the title and meter with the cover', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openChooser(tester);
    await _enterPanel(tester, clock: false);

    expect(find.text('夜空中最亮的星'), findsOneWidget);
    expect(find.byType(Waveform), findsOneWidget);
    // The transport rides the cover in landscape.
    expect(
      find.byWidgetPredicate(
        (w) => w is PlayerIcon && w.glyph == PlayerGlyph.pause,
      ),
      findsOneWidget,
    );

    final cover = tester.getRect(find.byKey(const Key('cover-tap')));
    final title = tester.getRect(find.text('夜空中最亮的星'));
    final meter = tester.getRect(find.byType(Waveform));
    // Title top edge shares the cover's top edge …
    expect((title.top - cover.top).abs(), lessThan(4));
    // … and the meter's bottom edge shares the cover's bottom edge.
    expect((meter.bottom - cover.bottom).abs(), lessThan(2));
  });

  testWidgets('cover tap reveals the transport, which auto-hides after 5s', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openChooser(tester);
    await _enterPanel(tester, clock: false);

    AnimatedOpacity overlay() => tester.widget<AnimatedOpacity>(
      find.byKey(const Key('cover-controls')),
    );
    final cover = tester.getRect(find.byKey(const Key('cover-tap')));
    Future<void> tapCover() async {
      // A corner, so the tap never lands on a transport button.
      await tester.tapAt(cover.topLeft + const Offset(16, 16));
      await tester.pump();
    }

    // Hidden until asked for.
    expect(overlay().opacity, 0.0);

    await tapCover();
    expect(overlay().opacity, 1.0);

    // Auto-hides once the user stops interacting.
    await tester.pump(const Duration(seconds: 5));
    expect(overlay().opacity, 0.0);

    // Tapping the cover again hides it immediately (deliberate interrupt).
    await tapCover();
    expect(overlay().opacity, 1.0);
    await tapCover();
    expect(overlay().opacity, 0.0);

    // Pressing a transport button restarts the countdown.
    await tapCover();
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is PlayerIcon && w.glyph == PlayerGlyph.pause,
      ),
    );
    await tester.pump();
    expect(overlay().opacity, 1.0);
    await tester.pump(const Duration(seconds: 3));
    expect(
      overlay().opacity,
      1.0,
      reason: 'transport press should have reset the auto-hide timer',
    );
    await tester.pump(const Duration(seconds: 3));
    expect(overlay().opacity, 0.0);
  });

  testWidgets('clock panel lays out in landscape without overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openChooser(tester);
    await _enterPanel(tester, clock: true);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('clock-hour')), findsOneWidget);
    expect(find.byKey(const Key('clock-minute')), findsOneWidget);
    expect(find.byKey(const Key('clock-second-ring')), findsOneWidget);
    // The old full-width second bar is gone.
    expect(find.byKey(const Key('clock-second-bar')), findsNothing);
    expect(find.byKey(const Key('clock-date')), findsOneWidget);
    expect(find.byKey(const Key('clock-weekday')), findsOneWidget);
    // The calendar grid is gone for good.
    expect(find.byKey(const Key('clock-today')), findsNothing);

    // Centred in landscape too, just larger (Apple StandBy proportions).
    final hour = tester.getRect(find.byKey(const Key('clock-hour')));
    final ring = tester.getRect(find.byKey(const Key('clock-second-ring')));
    final date = tester.getRect(find.byKey(const Key('clock-date')));
    final weekday = tester.getRect(find.byKey(const Key('clock-weekday')));
    expect(((hour.left + ring.right) / 2 - 1600 / 2).abs(), lessThan(6));
    // The date *line* is centred; `clock-date` alone is only its left half.
    expect(((date.left + weekday.right) / 2 - 1600 / 2).abs(), lessThan(6));
    expect(date.bottom, lessThanOrEqualTo(hour.top));
    // Square, so the ring never distorts.
    expect((ring.width - ring.height).abs(), lessThan(1));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('clock panel centres the time, with the date above it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openChooser(tester);
    await _enterPanel(tester, clock: true);

    expect(tester.takeException(), isNull);
    final hour = tester.getRect(find.byKey(const Key('clock-hour')));
    final minute = tester.getRect(find.byKey(const Key('clock-minute')));
    final colon = tester.getRect(find.byKey(const Key('clock-colon')));
    final ring = tester.getRect(find.byKey(const Key('clock-second-ring')));
    final date = tester.getRect(find.byKey(const Key('clock-date')));
    final weekday = tester.getRect(find.byKey(const Key('clock-weekday')));

    // `hh:mm` on one line, with the seconds ring following the minutes.
    expect(minute.left, greaterThan(hour.right));
    expect((hour.top - minute.top).abs(), lessThan(2));
    expect(colon.left, greaterThan(hour.right));
    expect(colon.right, lessThan(minute.left));
    expect(ring.left, greaterThan(minute.right));
    expect((ring.width - ring.height).abs(), lessThan(1));

    // The colon and the ring ride a hair above the em-box centre — a digit's
    // optical centre sits slightly high, so a small lift is what reads as
    // centred. A full cap-height correction read as too high and no lift at all
    // as too low, both on user feedback.
    final lift = hour.center.dy - colon.center.dy;
    expect(lift, greaterThan(0));
    expect(lift, lessThan(hour.height * 0.06));
    // Colon and ring sit on the same lifted line.
    expect((colon.center.dy - ring.center.dy).abs(), lessThan(1));

    // The ring reads as the same height as the digits, just slightly under:
    // digit cap height is ~0.70 em, and the Text box we can measure is a full
    // em, so the ring lands between those two.
    expect(ring.height, greaterThan(hour.height * 0.62));
    expect(ring.height, lessThan(hour.height * 0.85));

    // Everything is centred — Apple's clock does not hang off a rail.
    expect(((hour.left + ring.right) / 2 - 400 / 2).abs(), lessThan(6));
    // The date *line* is centred; `clock-date` alone is only its left half.
    expect(((date.left + weekday.right) / 2 - 400 / 2).abs(), lessThan(6));

    // The time is centred on the panel itself, not on a time+date stack.
    expect((hour.center.dy - 860 / 2).abs(), lessThan(2));
    // The ring rides the deliberate hair-lift above that line.
    expect((ring.center.dy - 860 / 2).abs(), lessThan(860 * 0.01));
    // The date rides near the top, well clear of the numerals.
    expect(date.top, lessThan(860 * 0.18));
    expect(date.bottom, lessThan(hour.top - 100));

    // Big enough to read across a room.
    expect(hour.height, greaterThan(65));

    // Every glyph is its own widget, with real air between them (they used to
    // be one Text run crushed by negative tracking).
    final h0 = tester.getRect(find.byKey(const Key('clock-digit-h0')));
    final h1 = tester.getRect(find.byKey(const Key('clock-digit-h1')));
    final m0 = tester.getRect(find.byKey(const Key('clock-digit-m0')));
    final m1 = tester.getRect(find.byKey(const Key('clock-digit-m1')));
    expect(h1.left, greaterThan(h0.right));
    expect(m1.left, greaterThan(m0.right));
    expect(h1.left - h0.right, greaterThan(hour.height * 0.02));
    expect(m1.left - m0.right, greaterThan(hour.height * 0.02));
    // All four share one centre line.
    for (final r in [h1, m0, m1]) {
      expect((r.center.dy - h0.center.dy).abs(), lessThan(1));
    }

    // Date above the time; no full-width second bar anywhere.
    expect(date.bottom, lessThanOrEqualTo(hour.top));
    expect(find.byKey(const Key('clock-second-bar')), findsNothing);
    expect(find.byKey(const Key('clock-second')), findsNothing);

    expect(find.byKey(const Key('clock-today')), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('clock panel survives a rotation, and the playing card is gone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openChooser(tester);
    await _enterPanel(tester, clock: true);

    // Demo mode is playing a track, yet the clock shows no track card.
    expect(find.byIcon(Icons.music_note_rounded), findsNothing);

    final portrait = tester.getRect(find.byKey(const Key('clock-hour')));
    expect(portrait.height, greaterThan(56));

    // Rotate: the panel must lay out again without throwing.
    tester.view.physicalSize = const Size(1600, 800);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    final landscape = tester.getRect(find.byKey(const Key('clock-hour')));
    expect(landscape.height, greaterThan(portrait.height));

    // …and back.
    tester.view.physicalSize = const Size(400, 860);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('clock-hour')), findsOneWidget);
    expect(find.byKey(const Key('clock-second-ring')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the switch chip is a thin, frosted pill', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openChooser(tester);
    await _enterPanel(tester, clock: false);

    final chip = find.byKey(const Key('panel-back'));
    expect(chip, findsOneWidget);
    // Frosted: the chip blurs what is painted behind it.
    expect(
      find.descendant(of: chip, matching: find.byType(BackdropFilter)),
      findsOneWidget,
    );

    // Hairline stroke instead of a full-weight border.
    final box = tester.widget<Container>(
      find.descendant(of: chip, matching: find.byType(Container)).first,
    );
    final border = (box.decoration! as BoxDecoration).border! as Border;
    expect(border.top.width, lessThan(0.8));

    // Light label, not a bold one.
    final label = tester.widget<Text>(find.text('切换'));
    expect(label.style!.fontWeight, FontWeight.w400);
    expect(label.style!.fontSize, lessThan(13));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pulling the clock down opens the customisation sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openChooser(tester);
    await _enterPanel(tester, clock: true);

    expect(find.byKey(const Key('clock-settings-sheet')), findsNothing);

    // Pull down from near the top of the panel.
    await tester.dragFrom(const Offset(200, 18), const Offset(0, 150));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.byKey(const Key('clock-settings-sheet')), findsOneWidget);
    expect(find.text('时钟定制'), findsOneWidget);
    for (final label in ['字体', '粗细', '颜色', '字形', '背景', '字号']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('clock settings repaint the digits, and the backdrop can follow '
      'the cover', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openChooser(tester);
    await _enterPanel(tester, clock: true);
    await tester.dragFrom(const Offset(200, 18), const Offset(0, 150));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    // Every glyph is its own Text now; check one of them.
    Text hour() =>
        tester.widget<Text>(find.byKey(const Key('clock-digit-h0')));

    // Colour.
    await tester.tap(find.byKey(const Key('swatch-amber')));
    await tester.pump();
    expect(hour().style!.color, AppColors.accent);

    // Weight.
    await tester.tap(find.byKey(const Key('chip-细')));
    await tester.pump();
    expect(hour().style!.fontWeight, FontWeight.w300);

    // Face: frosted clips a real backdrop blur through the glyph mask, and
    // takes no ink colour at all (the glass is neutral white).
    await tester.tap(find.byKey(const Key('chip-毛玻璃')));
    await tester.pump();
    // Let the 180 ms digit cross-fade finish so only one glyph run is live.
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(BackdropFilter), findsWidgets);
    expect(find.byType(ShaderMask), findsWidgets);
    final frosted = find.byKey(const Key('clock-digit-h0'));
    expect(frosted, findsOneWidget);
    expect(
      find.descendant(of: frosted, matching: find.byType(BackdropFilter)),
      findsOneWidget,
      reason: 'the frosted glyph itself must clip the backdrop blur',
    );

    // Backdrop: follow the album cover instead of the night tone.
    await tester.tap(find.byKey(const Key('chip-封面取色')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('clock-settings-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    final backdrop = tester.widget<AmbientBackdrop>(
      find.byType(AmbientBackdrop),
    );
    expect(
      backdrop.colors,
      isNot(
        equals(const [
          Color(0xFF101A2B),
          Color(0xFF1C1610),
          Color(0xFF0A0C10),
        ]),
      ),
      reason: 'backdrop should have switched away from the night tone',
    );

    await tester.pumpWidget(const SizedBox());
  });
}
