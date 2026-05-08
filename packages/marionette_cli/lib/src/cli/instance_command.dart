import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:marionette_cli/src/cli/broker_connector.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/broker/broker_discovery.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

/// Base class for commands that operate on a connected Flutter app instance.
///
/// Handles resolving the instance name from the global `--instance` flag,
/// looking up the URI from the registry, connecting, executing, and
/// disconnecting.
///
/// Supports both VM service mode (default) and broker mode (--broker flag).
abstract class InstanceCommand extends Command<int> {
  InstanceRegistry get registry;

  /// Subclasses implement this to perform their operation on a connected
  /// [connector].
  Future<int> execute(VmServiceConnector connector);

  /// Subclasses can override this to perform their operation via a broker.
  /// Default implementation falls back to [execute] with a shim connector.
  Future<int> executeBroker(BrokerConnector connector) async {
    // Default: not supported in broker mode
    stderr.writeln('This command does not support broker mode.');
    return 1;
  }

  @override
  Future<int> run() async {
    final rawInstance = globalResults?['instance'] as String?;
    final rawUri = globalResults?['uri'] as String?;
    final rawBroker = globalResults?['broker'] as String?;
    final instanceName =
        (rawInstance != null && rawInstance.isNotEmpty) ? rawInstance : null;
    final directUri = (rawUri != null && rawUri.isNotEmpty) ? rawUri : null;

    if (rawBroker != null) {
      return _runBroker(rawBroker);
    }

    if (instanceName != null && directUri != null) {
      usageException(
        '--instance (-i) and --uri are mutually exclusive. Use one or the other.',
      );
    }

    if (instanceName == null && directUri == null) {
      usageException('--instance (-i) or --uri is required for this command.');
    }

    late final String uri;
    late final String displayName;
    final isStateless = directUri != null;

    if (directUri != null) {
      uri = directUri;
      displayName = directUri;
    } else if (instanceName != null) {
      final info = registry.get(instanceName);
      if (info == null) {
        stderr.writeln(
          'Instance "$instanceName" not found. '
          'Use "marionette list" to see registered instances.',
        );
        return 1;
      }
      uri = info.uri;
      displayName = instanceName;
    }

    final rawTimeout = globalResults?['timeout'] as String? ?? '5';
    final timeoutSeconds = int.tryParse(rawTimeout);
    if (timeoutSeconds == null) {
      stderr.writeln('Invalid timeout value: "$rawTimeout"');
      return 64;
    }
    final connector = VmServiceConnector();

    try {
      await connector.connect(uri).timeout(
            Duration(seconds: timeoutSeconds),
            onTimeout: () => throw TimeoutException(
              'Connection to "$displayName" at $uri timed out '
              'after ${timeoutSeconds}s. Is the app still running?',
            ),
          );
      return await execute(connector);
    } on SocketException catch (e) {
      final hint = isStateless
          ? 'Check the URI and ensure the app is still running.'
          : 'The app may have stopped. '
              'Try "marionette doctor" or "marionette unregister $displayName".';
      stderr.writeln('Could not connect to "$displayName" at $uri: $e\n$hint');
      return 1;
    } on TimeoutException catch (e) {
      stderr.writeln(e.message);
      return 1;
    } catch (e) {
      stderr.writeln('Error: $e');
      return 1;
    } finally {
      await connector.disconnect();
    }
  }

  Future<int> _runBroker(String brokerArg) async {
    late final Uri uri;
    late final String token;

    if (brokerArg.isEmpty) {
      // Auto-discover
      final handle = await BrokerDiscovery.findRunning();
      if (handle == null) {
        stderr.writeln(
          'No broker found. Run "marionette broker start" first.',
        );
        return 1;
      }
      uri = Uri.parse('ws://127.0.0.1:${handle.port}');
      token = handle.token;
    } else {
      // Parse broker URI (ws://host:port?token=xxx)
      final parsed = Uri.parse(brokerArg);
      uri = parsed;
      token = parsed.queryParameters['token'] ?? '';
      if (token.isEmpty) {
        stderr.writeln('Broker URI must include ?token= parameter.');
        return 1;
      }
    }

    final connector = BrokerConnector(uri: uri, token: token);

    try {
      await connector.connect();
      return await executeBroker(connector);
    } catch (e) {
      stderr.writeln('Broker error: $e');
      return 1;
    } finally {
      await connector.disconnect();
    }
  }
}
