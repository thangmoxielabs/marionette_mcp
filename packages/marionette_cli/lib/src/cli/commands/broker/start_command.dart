import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:args/command_runner.dart';
import 'package:marionette_mcp/src/broker/broker_discovery.dart';
import 'package:marionette_mcp/src/broker/broker_handle.dart';
import 'package:marionette_mcp/src/broker/broker_server.dart';

class BrokerStartCommand extends Command<int> {
  @override
  String get name => 'start';

  @override
  String get description => 'Start a local broker server.';

  BrokerStartCommand() {
    argParser
      ..addOption(
        'port',
        help: 'Port to listen on (0 for random available port).',
        defaultsTo: '0',
      )
      ..addOption(
        'token',
        help: 'Auth token for app connections (random if omitted).',
      );
  }

  @override
  Future<int> run() async {
    // Check if a broker is already running
    final existing = await BrokerDiscovery.findRunning();
    if (existing != null) {
      stdout.writeln(
        'Broker already running on port ${existing.port}.',
      );
      stdout.writeln(
        'Activation URL: ws://127.0.0.1:${existing.port}?token=${existing.token}',
      );
      return 0;
    }

    final port = int.tryParse(argResults!['port'] as String) ?? 0;
    final token = argResults!['token'] as String? ?? _generateToken();

    final server = BrokerServer(port: port, token: token);
    final actualPort = await server.start();

    final handle = BrokerHandle(
      port: actualPort,
      token: token,
      pid: DateTime.now().millisecondsSinceEpoch,
    );
    await handle.write();

    stdout.writeln('Broker started on port $actualPort');
    stdout.writeln('Activation URL: ws://127.0.0.1:$actualPort?token=$token');
    stdout.writeln('Handle file: ${handle.path}');
    stdout.writeln();
    stdout.writeln('Press Ctrl+C to stop.');

    // Wait for SIGINT
    final completer = Completer<void>();
    ProcessSignal.sigint.watch().listen((_) {
      completer.complete();
    });
    ProcessSignal.sigterm.watch().listen((_) {
      completer.complete();
    });

    await completer.future;

    await handle.delete();
    await server.stop();
    stdout.writeln('Broker stopped.');
    return 0;
  }

  static String _generateToken() {
    final random = Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(32, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
