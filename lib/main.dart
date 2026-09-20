import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'services/device_discovery.dart';
import 'state/clock_settings.dart';
import 'state/player_controller.dart';
import 'theme.dart';
import 'ui/clock_view.dart';
import 'ui/connection_page.dart';
import 'ui/mode_page.dart';
import 'ui/panel_scaffold.dart';
import 'ui/player_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const AwesomeTimeApp());
}

class AwesomeTimeApp extends StatefulWidget {
  const AwesomeTimeApp({super.key, this.discover});

  /// Test seam forwarded to the pairing page; null uses the real UDP scan.
  final Future<List<DiscoveredBridge>> Function()? discover;

  @override
  State<AwesomeTimeApp> createState() => _AwesomeTimeAppState();
}

class _AwesomeTimeAppState extends State<AwesomeTimeApp> {
  final _controller = PlayerController();
  final _clock = ClockSettings();
  final _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _controller.onConnected = _goMode;
    _controller.onDisconnected = _goConnect;
    // Restores the last clock look; the defaults stand until it lands.
    _clock.load();
  }

  void _goMode() {
    final ctx = _navKey.currentContext;
    if (ctx == null) return;
    final route = ModalRoute.of(ctx);
    if (route?.settings.name != '/mode') {
      Navigator.of(ctx).pushNamedAndRemoveUntil('/mode', (_) => false);
    }
  }

  void _goConnect() {
    final ctx = _navKey.currentContext;
    if (ctx == null) return;
    final route = ModalRoute.of(ctx);
    if (route?.settings.name != '/connect') {
      Navigator.of(ctx).pushNamedAndRemoveUntil('/connect', (_) => false);
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PlayerController>.value(value: _controller),
        ChangeNotifierProvider<ClockSettings>.value(value: _clock),
      ],
      child: MaterialApp(
        title: '妙时',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        navigatorKey: _navKey,
        initialRoute: '/connect',
        routes: {
          '/connect': (_) => ConnectionPage(discover: widget.discover),
          // Chooser: swipe between the two panels, tap one to enter it.
          '/mode': (_) => const ModePage(),
          '/media': (_) => const PanelScaffold(child: MediaView()),
          '/clock': (_) => const PanelScaffold(
            clockTone: true,
            clockBackdrop: true,
            child: ClockView(),
          ),
        },
      ),
    );
  }
}
