import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A bridge found on the local network via UDP discovery.
class DiscoveredBridge {
  const DiscoveredBridge({
    required this.ip,
    required this.port,
    required this.name,
  });

  final String ip;
  final int port;
  final String name;

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
      return DiscoveredBridge(ip: ip, port: port, name: name);
    } catch (_) {
      return null;
    }
  }

  /// Prefix lengths worth probing. /24 is the home default, but office and
  /// campus LANs are routinely /19../22 and [NetworkInterface] does not expose
  /// the netmask, so every plausible subnet broadcast is offered rather than
  /// guessing one of them.
  static const List<int> probePrefixLengths = <int>[
    16, 17, 18, 19, 20, 21, 22, 23, 24,
  ];

  /// Subnet broadcast addresses [ip] could belong to, most specific last.
  ///
  /// A hardcoded /24 (the previous behaviour) turns `10.192.201.26` into
  /// `10.192.201.255`, which on a real /19 LAN is just some host address — the
  /// probe never reaches the bridge. Enumerating prefixes keeps the correct
  /// broadcast in the set no matter how the network is carved up. Exposed for
  /// tests.
  static List<String> broadcastCandidates(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return const <String>[];
    final octets = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return const <String>[];
      octets.add(value);
    }
    final address =
        (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3];
    final seen = <int>{};
    final out = <String>[];
    for (final length in probePrefixLengths) {
      final mask = (0xFFFFFFFF << (32 - length)) & 0xFFFFFFFF;
      final broadcast = (address & mask) | (~mask & 0xFFFFFFFF);
      if (!seen.add(broadcast)) continue;
      out.add(
        '${(broadcast >> 24) & 0xFF}.${(broadcast >> 16) & 0xFF}'
        '.${(broadcast >> 8) & 0xFF}.${broadcast & 0xFF}',
      );
    }
    return out;
  }

  static Future<List<InternetAddress>> _broadcastAddresses() async {
    final addrs = <InternetAddress>{
      // Limited broadcast: always valid inside our own broadcast domain, and
      // the one target that needs no netmask knowledge at all.
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
          for (final candidate in broadcastCandidates(addr.address)) {
            addrs.add(InternetAddress(candidate));
          }
        }
      }
    } catch (_) {}
    return addrs.toList(growable: false);
  }
}
