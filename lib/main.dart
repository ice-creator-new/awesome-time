import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'state/player_controller.dart';
import 'theme.dart';
import 'ui/connection_page.dart';
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
  const AwesomeTimeApp({super.key});

  @override
  State<AwesomeTimeApp> createState() => _AwesomeTimeAppState();
}

class _AwesomeTimeAppState extends State<AwesomeTimeApp> {
  final _controller = PlayerController();
  final _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _controller.onConnected = _goPlayer;
    _controller.onDisconnected = _goConnect;
  }

  void _goPlayer() {
    final ctx = _navKey.currentContext;
    if (ctx == null) return;
    final route = ModalRoute.of(ctx);
    if (route?.settings.name != '/player') {
      Navigator.of(ctx).pushNamedAndRemoveUntil('/player', (_) => false);
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
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PlayerController>.value(
      value: _controller,
      child: MaterialApp(
        title: '妙时',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        navigatorKey: _navKey,
        initialRoute: '/connect',
        routes: {
          '/connect': (_) => const ConnectionPage(),
          '/player': (_) => const PlayerPage(),
        },
      ),
    );
  }
}
