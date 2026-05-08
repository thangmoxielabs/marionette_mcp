import 'dart:convert';
import 'dart:io' as io;
import 'dart:io';

import 'package:path/path.dart' as p;

/// Writes a broker handle file to the system temp directory so other CLI
/// invocations can discover a running broker.
///
/// The handle file contains the broker's port and auth token.
class BrokerHandle {
  BrokerHandle({
    required this.port,
    required this.token,
    int? pid,
    DateTime? createdAt,
  })  : pid = pid ?? io.pid,
        createdAt = createdAt ?? DateTime.now();

  final int port;
  final String token;
  final int pid;
  final DateTime createdAt;

  String get path => p.join(
        Platform.environment['TMPDIR'] ?? '/tmp',
        'marionette-broker-$pid.json',
      );

  Future<void> write() async {
    final file = File(path);
    await file.writeAsString(
      jsonEncode({
        'port': port,
        'token': token,
        'pid': pid,
        'createdAt': createdAt.toIso8601String(),
      }),
    );
  }

  Future<void> delete() async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<BrokerHandle?> read(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final createdAtRaw = data['createdAt'] as String?;
      return BrokerHandle(
        port: data['port'] as int,
        token: data['token'] as String,
        pid: data['pid'] as int?,
        createdAt:
            createdAtRaw != null ? DateTime.tryParse(createdAtRaw) : null,
      );
    } catch (_) {
      return null;
    }
  }

  static String directoryPath() {
    return Platform.environment['TMPDIR'] ?? '/tmp';
  }
}
