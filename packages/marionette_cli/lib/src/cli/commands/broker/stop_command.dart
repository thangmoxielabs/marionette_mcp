import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:marionette_mcp/src/broker/broker_discovery.dart';
import 'package:marionette_mcp/src/broker/broker_handle.dart';
import 'package:path/path.dart' as p;

class BrokerStopCommand extends Command<int> {
  @override
  String get name => 'stop';

  @override
  String get description => 'Stop a running broker server.';

  BrokerStopCommand() {
    argParser.addOption(
      'port',
      help: 'Port of the broker to stop (stops most recent if omitted).',
    );
  }

  @override
  Future<int> run() async {
    final brokers = await BrokerDiscovery.listRunning();

    if (brokers.isEmpty) {
      stderr.writeln('No broker servers running.');
      return 1;
    }

    final portArg = argResults!['port'] as String?;
    BrokerHandle? target;

    if (portArg != null) {
      final port = int.tryParse(portArg);
      if (port == null) {
        stderr.writeln('Invalid port: $portArg');
        return 1;
      }
      target = brokers.firstWhere(
        (b) => b.port == port,
        orElse: () => throw Exception('No broker on port $port'),
      );
    } else {
      // Stop the most recent one
      target = brokers.first;
    }

    // Delete handle file (broker process will exit when handle is removed)
    final handlePath = p.join(
      BrokerHandle.directoryPath(),
      'marionette-broker-${target.pid}.json',
    );
    final handleFile = File(handlePath);
    if (await handleFile.exists()) {
      await handleFile.delete();
    }

    stdout.writeln('Broker on port ${target.port} stopped.');
    return 0;
  }
}
