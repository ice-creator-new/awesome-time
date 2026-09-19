import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/player_controller.dart';
import '../theme.dart';

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  static const _prefsKey = 'bridge_host';
  final _ctrl = TextEditingController(text: '192.168.1.10:8765');
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null && saved.isNotEmpty && mounted) {
      _ctrl.text = saved;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _connect({bool demo = false}) async {
    final c = context.read<PlayerController>();
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      if (demo) {
        c.startDemo();
      } else {
        final host = _ctrl.text.trim();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, host);
        await c.connect(host);
        // brief wait so UI shows connecting
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!c.isConnected && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(c.statusMessage ?? '连接失败，请检查地址与网络'),
              backgroundColor: AppColors.surface2,
            ),
          );
          setState(() => _busy = false);
          return;
        }
      }
      if (mounted) {
        // Root navigator owns route transitions (see main.dart).
        Navigator.of(
          context,
          rootNavigator: true,
        ).pushNamedAndRemoveUntil('/player', (_) => false);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'AWESOME TIME',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.accent,
                  fontSize: 13,
                  letterSpacing: 2.4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '连接电脑桥接',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontSize: 28, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                '在电脑上运行 bridge 后，把终端里打印的局域网地址填到这里。'
                '连接走 WebSocket 实时推送；手机与电脑需在同一 Wi-Fi。',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 36),
              TextField(
                controller: _ctrl,
                enabled: !_busy,
                autocorrect: false,
                keyboardType: TextInputType.url,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'[0-9a-zA-Z\.:\/\-]'),
                  ),
                ],
                style: const TextStyle(
                  fontSize: 16,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
                decoration: InputDecoration(
                  labelText: '桥接地址',
                  hintText: '192.168.1.10:8765',
                  labelStyle: const TextStyle(color: AppColors.muted),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.accent,
                      width: 1.5,
                    ),
                  ),
                ),
                onSubmitted: (_) => _connect(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : () => _connect(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.bg,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text('连接'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy ? null : () => _connect(demo: true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.muted,
                  minimumSize: const Size.fromHeight(48),
                  side: BorderSide(color: AppColors.track),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('演示模式（无需电脑）'),
              ),
              const Spacer(),
              Text(
                '电脑端：bridge/awesome_bridge.py\n默认端口 8765 · WebSocket 实时推送 · 同一局域网',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
