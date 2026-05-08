import 'dart:io';

import 'package:path/path.dart' as p;

import 'broker_handle.dart';

/// Discovers running broker servers by scanning handle files in the temp
/// directory and verifying liveness via TCP connect.
class BrokerDiscovery {
  /// Finds the freshest reachable broker server.
  ///
  /// Scans `${TMPDIR}/marionette-broker-*.json`, parses each handle,
  /// verifies the broker is still reachable via TCP, and returns the most
  /// recently created one. Unreachable handles are garbage-collected.
  static Future<BrokerHandle?> findRunning() async {
    final handles = await listRunning();
    if (handles.isEmpty) return null;
    handles.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return handles.first;
  }

  /// Lists all reachable brokers (for status/debugging).
  static Future<List<BrokerHandle>> listRunning() async {
    final dir = Directory(BrokerHandle.directoryPath());
    if (!await dir.exists()) return [];

    final handles = <BrokerHandle>[];

    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final filename = p.basename(entity.path);
      if (!filename.startsWith('marionette-broker-') ||
          !filename.endsWith('.json')) {
        continue;
      }

      final handle = await BrokerHandle.read(entity.path);
      if (handle == null) continue;

      if (await _isReachable(handle.port)) {
        handles.add(handle);
      } else {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }

    return handles;
  }

  static Future<bool> _isReachable(int port) async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(seconds: 1),
      );
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }
}
