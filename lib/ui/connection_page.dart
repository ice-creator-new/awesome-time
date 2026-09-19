import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/device_discovery.dart';
import '../state/player_controller.dart';
import '../theme.dart';

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  static const _prefsKey = 'bridge_host';
  static const _prefsPairKey = 'bridge_pair_code';
  final _ctrl = TextEditingController(text: '192.168.1.10:8765');
  final _pairCtrl = TextEditingController();
  bool _busy = false;
  bool _discovering = false;
  List<DiscoveredBridge> _devices = const [];
  DiscoveredBridge? _selected;
  String? _discoverError;

  bool get _pairLikelyRequired =>
      _selected?.pairRequired == true ||
      _devices.any((d) => d.host == _ctrl.text.trim() && d.pairRequired);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    final savedPair = prefs.getString(_prefsPairKey);
    if (saved != null && saved.isNotEmpty && mounted) {
      _ctrl.text = saved;
    }
    if (savedPair != null && savedPair.isNotEmpty && mounted) {
      _pairCtrl.text = savedPair;
    }
    await _startDiscovery();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _pairCtrl.dispose();
    super.dispose();
  }

  Future<void> _startDiscovery() async {
    if (_discovering || _busy) return;
    setState(() {
      _discovering = true;
      _discoverError = null;
      _devices = const [];
      _selected = null;
    });
    try {
      final devices = await DeviceDiscovery.discover();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        if (devices.length == 1) {
          _selected = devices.first;
          _ctrl.text = devices.first.host;
        } else if (devices.length > 1) {
          // Prefer a previously saved host when it is still online.
          final saved = _ctrl.text.trim();
          final match = devices.where((d) => d.host == saved).toList();
          _selected = match.isNotEmpty ? match.first : devices.first;
          _ctrl.text = _selected!.host;
        } else {
          _discoverError = '未发现设备，可手动输入地址';
        }
      });
      // Single device: auto-connect only when pairing is off or we already
      // have a saved pairing code.
      if (devices.length == 1 && mounted && !_busy) {
        final only = devices.first;
        final haveCode = _pairCtrl.text.trim().isNotEmpty;
        if (!only.pairRequired || haveCode) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          if (mounted && !_busy) {
            await _connect();
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _discoverError = '搜索失败：$e');
    } finally {
      if (mounted) setState(() => _discovering = false);
    }
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
        if (host.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('请先选择或输入桥接地址'),
                backgroundColor: AppColors.surface2,
              ),
            );
          }
          setState(() => _busy = false);
          return;
        }
        final prefs = await SharedPreferences.getInstance();
        final pairCode = _pairCtrl.text.trim().toUpperCase();
        if (_pairLikelyRequired && pairCode.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('请输入电脑终端显示的配对码'),
                backgroundColor: AppColors.surface2,
              ),
            );
          }
          setState(() => _busy = false);
          return;
        }
        await prefs.setString(_prefsKey, host);
        if (pairCode.isNotEmpty) {
          await prefs.setString(_prefsPairKey, pairCode);
        }
        await c.connect(host, pairCode: pairCode);
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
        Navigator.of(
          context,
          rootNavigator: true,
        ).pushNamedAndRemoveUntil('/player', (_) => false);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _selectDevice(DiscoveredBridge device) {
    setState(() {
      _selected = device;
      _ctrl.text = device.host;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showList = _devices.isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '妙时',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.accent,
                  fontSize: 13,
                  letterSpacing: 2.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'AWESOME TIME',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.muted,
                  fontSize: 11,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '连接电脑桥接',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontSize: 28, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    onPressed: (_busy || _discovering) ? null : _startDiscovery,
                    tooltip: '重新搜索',
                    icon: _discovering
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accent,
                            ),
                          )
                        : const Icon(Icons.refresh, color: AppColors.muted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _discovering
                    ? '正在搜索同一 Wi-Fi 下的桥接设备…'
                    : '自动搜索局域网设备，也可手动填地址。连接走 WebSocket，进度每秒推送。',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(height: 1.5),
              ),
              if (_discoverError != null && !showList) ...[
                const SizedBox(height: 8),
                Text(
                  _discoverError!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                    height: 1.4,
                  ),
                ),
              ],
              if (showList) ...[
                const SizedBox(height: 16),
                Text(
                  '发现的设备（${_devices.length}）',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.muted,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 196),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: _devices.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: AppColors.track,
                    ),
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      final selected = _selected?.host == device.host;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        selectedTileColor: selected
                            ? AppColors.surface2
                            : null,
                        title: Text(
                          device.name.isEmpty ? device.host : device.name,
                          style: TextStyle(
                            color: selected
                                ? AppColors.accent
                                : AppColors.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          device.pairRequired
                              ? '${device.host} · 需要配对码'
                              : device.host,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        trailing: selected
                            ? const Icon(
                                Icons.check_circle,
                                color: AppColors.accent,
                                size: 18,
                              )
                            : null,
                        onTap: () => _selectDevice(device),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),
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
                onChanged: (v) {
                  final host = v.trim();
                  final match = _devices.where((d) => d.host == host);
                  if (match.isNotEmpty && _selected?.host != host) {
                    setState(() => _selected = match.first);
                  }
                },
                onSubmitted: (_) => _connect(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pairCtrl,
                enabled: !_busy,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                keyboardType: TextInputType.visiblePassword,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9a-zA-Z]')),
                  LengthLimitingTextInputFormatter(8),
                ],
                style: const TextStyle(
                  fontSize: 16,
                  letterSpacing: 2,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
                decoration: InputDecoration(
                  labelText: _pairLikelyRequired ? '配对码（必填）' : '配对码（桥接开启时）',
                  hintText: '终端里的 6 位短码',
                  helperText: '看电脑运行 bridge 时打印的「配对码 / Pairing code」',
                  labelStyle: const TextStyle(color: AppColors.muted),
                  helperStyle: const TextStyle(color: AppColors.muted, fontSize: 11),
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
                '电脑端：bridge/awesome_bridge.py\n默认端口 8765 · UDP 发现 8766 · WebSocket 每秒推进度',
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
