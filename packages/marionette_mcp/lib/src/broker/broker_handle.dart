import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Writes a broker handle file to the system temp directory so other CLI
/// invocations can discover a running broker.
///
/// The handle file contains the broker's port and auth token.
class BrokerHandle {
  BrokerHandle({required this.port, required this.token, this.pid});

  final int port;
  final String token;
  final int? pid;

  String get path => p.join(
        Platform.environment['TMPDIR'] ?? '/tmp',
        'marionette-broker-${pid ?? _currentPid()}.json',
      );

  Future<void> write() async {
    final file = File(path);
    await file.writeAsString(
      jsonEncode({
        'port': port,
        'token': token,
        'pid': pid ?? _currentPid(),
        'createdAt': DateTime.now().toIso8601String(),
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
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return BrokerHandle(
        port: data['port'] as int,
        token: data['token'] as String,
        pid: data['pid'] as int?,
      );
    } catch (_) {
      return null;
    }
  }

  static String directoryPath() {
    return Platform.environment['TMPDIR'] ?? '/tmp';
  }

  static int _currentPid() {
    // Use a unique identifier since Dart doesn't expose process PID directly
    return DateTime.now().millisecondsSinceEpoch;
  }
}
