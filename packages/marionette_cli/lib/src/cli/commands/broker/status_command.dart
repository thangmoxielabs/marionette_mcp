import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:marionette_mcp/src/broker/broker_discovery.dart';

class BrokerStatusCommand extends Command<int> {
  @override
  String get name => 'status';

  @override
  String get description => 'Show running broker servers.';

  @override
  Future<int> run() async {
    final brokers = await BrokerDiscovery.listRunning();

    if (brokers.isEmpty) {
      stdout.writeln('No broker servers running.');
      stdout.writeln('Start one with: marionette broker start');
      return 0;
    }

    stdout.writeln('Running broker servers:');
    for (final broker in brokers) {
      stdout.writeln('  Port: ${broker.port}');
      stdout.writeln('  Token: ${broker.token}');
      if (broker.pid != null) {
        stdout.writeln('  PID: ${broker.pid}');
      }
      stdout.writeln(
        '  URL: ws://127.0.0.1:${broker.port}?token=${broker.token}',
      );
      stdout.writeln();
    }

    return 0;
  }
}
