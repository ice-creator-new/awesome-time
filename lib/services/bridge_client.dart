import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/media_state.dart';

enum BridgeStatus { idle, connecting, connected, error }

class BridgeException implements Exception {
  BridgeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Realtime client: WebSocket push for state, WS (or HTTP fallback) for commands.
class BridgeClient {
  BridgeClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  bool _disposed = false;
  bool _everUp = false;
  int _retry = 0;
  String _base = '';
  String _wsUrl = '';

  void Function(MediaState state)? _onState;
  MediaState Function()? _previousState;
  void Function(List<double> bands)? _onSpectrum;
  void Function()? _onArt;
  void Function(BridgeStatus status, String? message)? _onStatus;

  String get base => _base;

  Uri get _stateUri => Uri.parse('$_base/state');
  Uri get _cmdUri => Uri.parse('$_base/cmd');

  Future<void> connect(
    String host, {
    required void Function(MediaState state) onState,
    MediaState Function()? previousState,
    void Function(List<double> bands)? onSpectrum,
    void Function()? onArt,
    required void Function(BridgeStatus status, String? message) onStatus,
    Duration requestTimeout = const Duration(seconds: 3),
  }) async {
    await disconnect();
    _disposed = false;
    _onState = onState;
    _previousState = previousState;
    _onSpectrum = onSpectrum;
    _onArt = onArt;
    _onStatus = onStatus;
    final normalized = normalizeHost(host);
    _base = normalized;
    _wsUrl = '${httpToWs(normalized)}/ws';
    _retry = 0;
    _everUp = false;
    onStatus(BridgeStatus.connecting, null);
    await _openSocket(isInitial: true);
  }

  Future<void> _openSocket({required bool isInitial}) async {
    if (_disposed) return;
    try {
      final ch = WebSocketChannel.connect(
        Uri.parse(_wsUrl),
        protocols: const ['awesome-time'],
      );
      _channel = ch;
      _wsSub = ch.stream.listen(
        _handleMessage,
        onError: (Object e) => _handleDown(e.toString()),
        onDone: () => _handleDown('WebSocket 已断开'),
        cancelOnError: false,
      );

      // Wait briefly for first state / handshake before declaring success.
      final up = await Future.any([
        Future<bool>(() async {
          for (var i = 0; i < 20; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            if (_everUp) return true;
            if (_disposed) return false;
          }
          return _everUp;
        }),
        Future<void>.delayed(
          isInitial ? const Duration(seconds: 3) : const Duration(seconds: 2),
        ).then((_) => _everUp),
      ]).timeout(
        isInitial ? const Duration(seconds: 4) : const Duration(seconds: 3),
        onTimeout: () => _everUp,
      );

      if (up) {
        _retry = 0;
        _onStatus?.call(BridgeStatus.connected, null);
        ch.sink.add(jsonEncode({'type': 'hello'}));
        _startHeartbeat();
        return;
      }

      // Fallback probe via HTTP /state to confirm bridge is up.
      try {
        final st = await fetchState();
        _onState?.call(st);
        _everUp = true;
        _retry = 0;
        _onStatus?.call(BridgeStatus.connected, null);
        _startHeartbeat();
        // Keep trying WS in background for pushes.
        _scheduleReconnect();
        return;
      } catch (_) {
        _handleDown(isInitial ? '无法连接桥接 (WebSocket/HTTP)' : '重连失败');
      }
    } catch (e) {
      if (isInitial) {
        // HTTP probe as last resort so user still gets data if WS blocked.
        try {
          final st = await fetchState();
          _onState?.call(st);
          _everUp = true;
          _retry = 0;
          _onStatus?.call(BridgeStatus.connected, null);
          _scheduleReconnect();
          return;
        } catch (_) {}
      }
      _handleDown(e.toString());
    }
  }

  void _handleMessage(dynamic raw) {
    if (_disposed) return;
    try {
      final text = raw is String ? raw : utf8.decode(raw as List<int>);
      if (text.isEmpty) return;
      final json = jsonDecode(text) as Map<String, dynamic>;
      final type = json['type'] as String? ?? '';
      if (type == 'pong') {
        _everUp = true;
        _onStatus?.call(BridgeStatus.connected, null);
        return;
      }
      if (type == 'spectrum') {
        final raw = json['v'];
        if (raw is List) {
          _onSpectrum?.call(
            raw.map((e) => (e is num) ? e.toDouble() : 0.0).toList(),
          );
        }
        return;
      }
      if (type == 'art') {
        _onArt?.call();
        return;
      }
      if (type == 'state' || json.containsKey('title')) {
        final stateJson = type == 'state'
            ? (Map<String, dynamic>.from(json)..remove('type'))
            : json;
        final state = MediaState.fromJson(
          stateJson,
          previous: _previousState?.call(),
        );
        _everUp = true;
        _retry = 0;
        _onState?.call(state);
        _onStatus?.call(BridgeStatus.connected, null);
      }
    } catch (_) {
      // ignore malformed frames
    }
  }

  void _handleDown(String message) {
    if (_disposed) return;
    final wasUp = _everUp;
    _wsSub?.cancel();
    _wsSub = null;
    _channel?.sink.close();
    _channel = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _onStatus?.call(
      BridgeStatus.error,
      wasUp ? message : (message.isEmpty ? '连接失败' : message),
    );
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    final delayMs = min(4000, 400 * (1 << min(_retry, 4)));
    _retry++;
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_disposed) return;
      _onStatus?.call(BridgeStatus.connecting, null);
      _openSocket(isInitial: false);
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_disposed) return;
      final ch = _channel;
      if (ch == null) return;
      try {
        ch.sink.add(jsonEncode({'type': 'ping', 't': DateTime.now().millisecondsSinceEpoch}));
      } catch (_) {
        _handleDown('心跳失败');
      }
    });
  }

  Future<void> disconnect() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _base = '';
    _wsUrl = '';
    _everUp = false;
    _onState = null;
    _previousState = null;
    _onSpectrum = null;
    _onArt = null;
    _onStatus = null;
  }

  Future<MediaState> fetchState({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (_base.isEmpty) throw BridgeException('未连接桥接服务');
    final res = await _client.get(_stateUri).timeout(timeout);
    if (res.statusCode != 200) {
      throw BridgeException('状态接口返回 ${res.statusCode}');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return MediaState.fromJson(json, previous: _previousState?.call());
  }

  Future<String> fetchArtwork({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (_base.isEmpty) return '';
    final res = await _client.get(Uri.parse('$_base/artwork')).timeout(timeout);
    if (res.statusCode != 200) return '';
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return (json['artwork'] as String?) ?? '';
  }

  Future<void> send({
    required String action,
    double? value,
    int? valueMs,
  }) async {
    if (_base.isEmpty) throw BridgeException('未连接桥接服务');
    final body = <String, dynamic>{'type': 'cmd', 'action': action};
    if (value != null) body['value'] = value;
    if (valueMs != null) body['valueMs'] = valueMs;

    final ch = _channel;
    if (ch != null && _everUp) {
      try {
        ch.sink.add(jsonEncode(body));
        return;
      } catch (_) {
        // fall through to HTTP
      }
    }

    final httpBody = <String, Object?>{'action': action};
    if (value != null) httpBody['value'] = value;
    if (valueMs != null) httpBody['valueMs'] = valueMs;
    final res = await _client
        .post(
          _cmdUri,
          headers: {'content-type': 'application/json'},
          body: utf8.encode(jsonEncode(httpBody)),
        )
        .timeout(const Duration(seconds: 3));
    if (res.statusCode != 200) {
      throw BridgeException('控制命令失败 (${res.statusCode})');
    }
  }

  static String normalizeHost(String host) {
    var h = host.trim();
    if (h.isEmpty) throw BridgeException('请输入桥接地址');
    // Accept pasted ws://…/ws or http://…/state and reduce to scheme+host:port only.
    h = h.replaceFirst(RegExp(r'^wss://', caseSensitive: false), 'https://');
    h = h.replaceFirst(RegExp(r'^ws://', caseSensitive: false), 'http://');
    h = h.replaceFirst(RegExp(r'/+$'), '');
    if (h.startsWith('http://') || h.startsWith('https://')) {
      return _originOnly(h);
    }
    if (!h.contains(':')) h = '$h:8765';
    // bare host with accidental path: strip after first path slash if any
    if (h.contains('/')) {
      final cut = h.indexOf('/');
      h = h.substring(0, cut);
      if (!h.contains(':')) h = '$h:8765';
    }
    return 'http://$h';
  }

  /// Keep only scheme://host:port — drop /ws, /state, etc.
  static String _originOnly(String url) {
    try {
      final u = Uri.parse(url);
      if (u.hasScheme && u.host.isNotEmpty) {
        final port = u.hasPort ? ':${u.port}' : '';
        final scheme = u.scheme.toLowerCase() == 'https' ? 'https' : 'http';
        return '$scheme://${u.host}$port';
      }
    } catch (_) {}
    // fallback: cut at first path segment after host
    final m = RegExp(r'^(https?://[^/]+)').firstMatch(url);
    return m != null ? m.group(1)! : url;
  }

  static String httpToWs(String httpBase) {
    if (httpBase.startsWith('https://')) {
      return 'wss://${httpBase.substring('https://'.length)}';
    }
    if (httpBase.startsWith('http://')) {
      return 'ws://${httpBase.substring('http://'.length)}';
    }
    return 'ws://$httpBase';
  }
}
