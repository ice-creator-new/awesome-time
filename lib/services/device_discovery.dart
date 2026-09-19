import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A bridge found on the local network via UDP discovery.
class DiscoveredBridge {
  const DiscoveredBridge({
    required this.ip,
    required this.port,
    required this.name,
    this.pairRequired = false,
  });

  final String ip;
  final int port;
  final String name;
  final bool pairRequired;

  String get host => '$ip:$port';

  String get label {
    final n = name.trim();
    if (n.isEmpty || n == ip) return host;
    return '$n · $host';
  }

  @override
  bool operator ==(Object other) =>
      other is DiscoveredBridge && other.host == host && other.name == name;

  @override
  int get hashCode => Object.hash(host, name);
}

/// Broadcasts a UDP probe and collects bridge replies on the LAN.
class DeviceDiscovery {
  DeviceDiscovery._();

  static const int discoveryPort = 8766;
  static const String magic = 'AWESOME_TIME_DISCOVER';
  static const Duration defaultTimeout = Duration(milliseconds: 1800);

  static Future<List<DiscoveredBridge>> discover({
    Duration timeout = defaultTimeout,
  }) async {
    final found = <String, DiscoveredBridge>{};
    RawDatagramSocket? socket;

    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket?.receive();
        if (datagram == null) return;
        final bridge = _parseReply(datagram.data, datagram.address.address);
        if (bridge != null) {
          found[bridge.host] = bridge;
        }
      });

      final payload = utf8.encode(magic);
      final targets = await _broadcastAddresses();
      for (final addr in targets) {
        try {
          socket.send(payload, addr, discoveryPort);
        } catch (_) {
          // Some interfaces reject broadcast; keep trying the rest.
        }
      }

      await Future<void>.delayed(timeout);
    } on SocketException {
      return found.values.toList(growable: false);
    } finally {
      socket?.close();
    }

    final list = found.values.toList(growable: false)
      ..sort((a, b) => a.host.compareTo(b.host));
    return list;
  }

  static DiscoveredBridge? _parseReply(List<int> data, String fromIp) {
    try {
      final text = utf8.decode(data, allowMalformed: true).trim();
      if (text.isEmpty) return null;
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return null;
      if (json['app'] != 'awesome-time-bridge') return null;
      final port = switch (json['port']) {
        final int p => p,
        final num p => p.toInt(),
        final String s => int.tryParse(s) ?? 0,
        _ => 0,
      };
      if (port <= 0 || port > 65535) return null;
      final ip = (json['ip'] as String?)?.trim().isNotEmpty == true
          ? json['ip'] as String
          : fromIp;
      if (ip.isEmpty || ip.startsWith('127.')) return null;
      final name = (json['name'] as String?)?.trim() ?? '';
      final pairRequired = json['pairRequired'] == true;
      return DiscoveredBridge(
        ip: ip,
        port: port,
        name: name,
        pairRequired: pairRequired,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<List<InternetAddress>> _broadcastAddresses() async {
    final addrs = <InternetAddress>{
      InternetAddress('255.255.255.255'),
    };
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final parts = addr.address.split('.');
          if (parts.length != 4) continue;
          // Classful-ish /24 broadcast for the interface subnet.
          addrs.add(InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'));
        }
      }
    } catch (_) {}
    return addrs.toList(growable: false);
  }
}
