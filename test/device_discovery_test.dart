import 'dart:convert';

import 'package:awesome_time/services/device_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parse bridge discovery reply', () {
    final payload = utf8.encode(
      jsonEncode({
        'app': 'awesome-time-bridge',
        'name': 'MacBook-Pro',
        'port': 8765,
      }),
    );
    // _parseReply is private; exercise via the public label/host helpers
    // by constructing an equivalent model from a raw map path used in tests.
    final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    expect(json['app'], 'awesome-time-bridge');
    final bridge = DiscoveredBridge(
      ip: '192.168.1.20',
      port: json['port'] as int,
      name: json['name'] as String,
    );
    expect(bridge.host, '192.168.1.20:8765');
    expect(bridge.label, 'MacBook-Pro · 192.168.1.20:8765');
  });

  test('discovery magic constant is stable for bridge interop', () {
    expect(DeviceDiscovery.magic, 'AWESOME_TIME_DISCOVER');
    expect(DeviceDiscovery.discoveryPort, 8766);
  });
}
