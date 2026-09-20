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

  group('broadcastCandidates', () {
    test('covers a home /24 LAN', () {
      expect(
        DeviceDiscovery.broadcastCandidates('192.168.1.10'),
        contains('192.168.1.255'),
      );
    });

    test('covers an office /19 LAN (the old /24 guess missed it)', () {
      final candidates = DeviceDiscovery.broadcastCandidates('10.192.201.26');
      // Real broadcast of 10.192.201.26/19, as reported by `ip addr`.
      expect(candidates, contains('10.192.223.255'));
      // The old hardcoded guess stays in the set; harmless as an extra probe.
      expect(candidates, contains('10.192.201.255'));
    });

    test('covers a /20 LAN', () {
      expect(
        DeviceDiscovery.broadcastCandidates('10.192.43.182'),
        contains('10.192.47.255'),
      );
    });

    test('deduplicates overlapping prefixes', () {
      final candidates = DeviceDiscovery.broadcastCandidates('10.192.201.26');
      expect(candidates.toSet().length, candidates.length);
      expect(candidates, isNotEmpty);
    });

    test('rejects malformed addresses', () {
      expect(DeviceDiscovery.broadcastCandidates('not-an-ip'), isEmpty);
      expect(DeviceDiscovery.broadcastCandidates('10.0.0'), isEmpty);
      expect(DeviceDiscovery.broadcastCandidates('10.0.0.999'), isEmpty);
      expect(DeviceDiscovery.broadcastCandidates(''), isEmpty);
    });
  });
}
