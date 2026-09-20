import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/device_discovery.dart';
import '../state/player_controller.dart';
import '../theme.dart';

/// Pairing page. iOS-shaped on purpose: one large title, one inset grouped
/// card, one primary button, secondary paths folded under "其他方式".
///
/// Scanning only *offers* bridges. Nothing is auto-selected and nothing is
/// auto-entered — the user taps a device and then taps 连接.
class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key, this.discover});

  /// Test seam. Defaults to the real UDP scan.
  final Future<List<DiscoveredBridge>> Function()? discover;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  static const _prefsKey = 'bridge_host';

  final TextEditingController _hostCtrl = TextEditingController();
  bool _busy = false;
  bool _discovering = false;
  bool _manualOpen = false;
  List<DiscoveredBridge> _devices = const [];
  String? _selectedHost;
  String? _savedHost;
  String? _error;

  /// Selected device wins; otherwise whatever was typed by hand.
  String get _host => (_selectedHost ?? _hostCtrl.text).trim();

  bool get _canConnect => !_busy && _host.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Scan and prefs load run in parallel on purpose: a slow preferences read
    // must never hold back device discovery.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scan();
      _restoreSavedHost();
    });
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    super.dispose();
  }

  Future<void> _restoreSavedHost() async {
    final saved = await _readSavedHost();
    if (!mounted || (saved ?? '').isEmpty) return;
    final host = saved!;
    setState(() {
      _savedHost = host;
      if (_hostCtrl.text.trim().isEmpty) {
        _hostCtrl.text = host;
      }
      // Pre-select only when that bridge is really on the LAN right now.
      if (_devices.any((d) => d.host == host)) {
        _selectedHost = host;
      }
    });
  }

  Future<String?> _readSavedHost() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefsKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveHost(String host) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, host);
    } catch (_) {
      // Pairing still works without prefs (tests, first run without plugin).
    }
  }

  Future<void> _scan() async {
    if (_discovering || _busy) return;
    setState(() {
      _discovering = true;
      _error = null;
      _devices = const [];
    });

    final scan = widget.discover ?? () => DeviceDiscovery.discover();
    List<DiscoveredBridge> found = const [];
    String? failure;
    try {
      found = await scan();
    } catch (e) {
      failure = '搜索失败：$e';
    }
    if (!mounted) return;

    setState(() {
      _devices = found;
      _discovering = false;
      _error = failure;
      // Restore the previous bridge only when it is really on the LAN again.
      // A fresh scan never picks for the user.
      final saved = _savedHost;
      if ((saved ?? '').isNotEmpty && found.any((d) => d.host == saved)) {
        _selectedHost = saved;
      } else if (_selectedHost != null &&
          !found.any((d) => d.host == _selectedHost)) {
        _selectedHost = null;
      }
      if (found.isEmpty) {
        // Nothing to tap: the manual path becomes the primary path.
        _manualOpen = true;
        _error ??= '未发现设备';
      }
    });
  }

  void _select(DiscoveredBridge device) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedHost = device.host;
      _hostCtrl.text = device.host;
    });
  }

  Future<void> _connect({bool demo = false}) async {
    final controller = context.read<PlayerController>();
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      if (demo) {
        controller.startDemo();
      } else {
        final host = _host;
        if (host.isEmpty) {
          _toast('请先选择设备或填写地址');
          return;
        }
        await _saveHost(host);
        await controller.connect(host);
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!controller.isConnected) {
          _toast(controller.statusMessage ?? '连接失败，请检查地址与网络');
          return;
        }
      }
      if (mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).pushNamedAndRemoveUntil('/mode', (_) => false);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.surface2,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Height, not orientation enum: works for split screen and tests.
            final landscape =
                constraints.maxWidth > constraints.maxHeight * 1.2;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                landscape ? 18 : 30,
                20,
                24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: landscape ? 780 : 520,
                  ),
                  child: landscape ? _wide() : _tall(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _tall() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _brand(),
        const SizedBox(height: 26),
        _deviceCard(),
        const SizedBox(height: 18),
        _primaryButton(),
        const SizedBox(height: 30),
        _otherWays(),
        const SizedBox(height: 22),
        _footer(),
      ],
    );
  }

  Widget _wide() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _brand(),
              const SizedBox(height: 24),
              _primaryButton(),
              const SizedBox(height: 24),
              _otherWays(),
              const SizedBox(height: 18),
              _footer(),
            ],
          ),
        ),
        const SizedBox(width: 28),
        Expanded(flex: 6, child: _deviceCard()),
      ],
    );
  }

  Widget _brand() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '妙时',
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '选择要连接的电脑',
          style: TextStyle(
            color: AppColors.muted.withValues(alpha: 0.95),
            fontSize: 15,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _deviceCard() {
    final rows = _devices;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHeader(),
          for (final device in rows) ...[
            const _CardDivider(),
            _deviceRow(device),
          ],
          if (_error != null && rows.isEmpty) ...[
            const _CardDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Text(
                _error!,
                style: TextStyle(
                  color: AppColors.muted.withValues(alpha: 0.9),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cardHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          if (_discovering) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 10),
            const Flexible(
              child: Text(
                '正在搜索…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.muted, fontSize: 14),
              ),
            ),
          ] else
            Flexible(
              child: Text(
                _devices.isEmpty ? '未发现设备' : '发现的电脑 ${_devices.length}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 14),
              ),
            ),
          const Spacer(),
          if (!_discovering)
            TextButton(
              onPressed: _busy ? null : _scan,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              child: const Text('重新搜索'),
            ),
        ],
      ),
    );
  }

  Widget _deviceRow(DiscoveredBridge device) {
    final selected = _selectedHost == device.host;
    final name = device.name.trim().isEmpty ? device.host : device.name.trim();
    return InkWell(
      onTap: _busy ? null : () => _select(device),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    device.host,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (selected)
              const Icon(
                Icons.check_rounded,
                color: AppColors.accent,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Widget _primaryButton() {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: _canConnect ? () => _connect() : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.bg,
          disabledBackgroundColor: AppColors.surface2,
          disabledForegroundColor: AppColors.muted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
        child: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: AppColors.bg,
                ),
              )
            : const Text('连接'),
      ),
    );
  }

  Widget _otherWays() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '其他方式',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 13,
              letterSpacing: 0.2,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _manualRow(),
              const _CardDivider(),
              _demoRow(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _manualRow() {
    final typed = _hostCtrl.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _busy ? null : () => setState(() => _manualOpen = !_manualOpen),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, _manualOpen ? 6 : 14),
            child: Row(
              children: [
                const Text(
                  '手动输入地址',
                  style: TextStyle(color: AppColors.ink, fontSize: 15),
                ),
                const Spacer(),
                if (!_manualOpen && typed.isNotEmpty)
                  Flexible(
                    child: Text(
                      typed,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(
                  _manualOpen
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AppColors.muted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (_manualOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: TextField(
              controller: _hostCtrl,
              enabled: !_busy,
              autocorrect: false,
              keyboardType: TextInputType.url,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-zA-Z\.:\/\-]')),
              ],
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 15,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: '192.168.1.10:8765',
                hintStyle: TextStyle(
                  color: AppColors.muted.withValues(alpha: 0.7),
                  fontSize: 15,
                ),
                filled: true,
                fillColor: AppColors.surface2,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppColors.accent,
                    width: 1.5,
                  ),
                ),
              ),
              onChanged: (_) {
                // Typing means "not the scanned device".
                setState(() {
                  _selectedHost = null;
                });
              },
              onSubmitted: (_) => _connect(),
            ),
          ),
      ],
    );
  }

  Widget _demoRow() {
    return InkWell(
      onTap: _busy ? null : () => _connect(demo: true),
      child: const Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Flexible(
              child: Text(
                '演示模式',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.ink, fontSize: 15),
              ),
            ),
            Spacer(),
            Flexible(
              child: Text(
                '无需电脑',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    return Text(
      '在电脑上运行 bridge/awesome_bridge.py，手机与电脑连同一 Wi-Fi 即可。',
      style: TextStyle(
        color: AppColors.muted.withValues(alpha: 0.7),
        fontSize: 12,
        height: 1.5,
      ),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      indent: 16,
      endIndent: 16,
      color: AppColors.track,
    );
  }
}
