import 'dart:convert';
import 'dart:io';

import 'package:marionette_mcp/src/broker/broker_discovery.dart';
import 'package:marionette_mcp/src/broker/broker_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('BrokerDiscovery', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('broker_discovery_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('findRunning returns null when no brokers exist', () async {
      final result = await BrokerDiscovery.findRunning();
      expect(result, isNull);
    });

    test('findRunning returns reachable broker', () async {
      final server = BrokerServer(token: 'test-token');
      final port = await server.start();

      // Write a handle file manually
      final handlePath = p.join(
        Platform.environment['TMPDIR'] ?? '/tmp',
        'marionette-broker-test.json',
      );
      final handleFile = File(handlePath);
      await handleFile.writeAsString(jsonEncode({
        'port': port,
        'token': 'test-token',
        'pid': 12345,
        'createdAt': DateTime.now().toIso8601String(),
      }));

      try {
        final result = await BrokerDiscovery.findRunning();
        expect(result, isNotNull);
        expect(result!.port, port);
        expect(result.token, 'test-token');
      } finally {
        try { await handleFile.delete(); } catch (_) {}
        await server.stop();
      }
    });

    test('findRunning GCs stale handles', () async {
      // Write a handle for a non-existent broker
      final stalePath = p.join(
        Platform.environment['TMPDIR'] ?? '/tmp',
        'marionette-broker-99999.json',
      );
      final staleFile = File(stalePath);
      await staleFile.writeAsString(jsonEncode({
        'port': 59999, // unlikely to be in use
        'token': 'stale',
        'pid': 99999,
        'createdAt': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
      }));

      try {
        final result = await BrokerDiscovery.findRunning();
        expect(result, isNull);
        // Stale file should be deleted
        expect(await staleFile.exists(), isFalse);
      } finally {
        try { await staleFile.delete(); } catch (_) {}
      }
    });

    test('findRunning returns the most recently created reachable broker',
        () async {
      final older = BrokerServer(token: 'older');
      final olderPort = await older.start();
      final newer = BrokerServer(token: 'newer');
      final newerPort = await newer.start();

      final olderPath = p.join(
        Platform.environment['TMPDIR'] ?? '/tmp',
        'marionette-broker-orderingA.json',
      );
      final newerPath = p.join(
        Platform.environment['TMPDIR'] ?? '/tmp',
        'marionette-broker-orderingB.json',
      );

      final olderTs = DateTime.now().subtract(const Duration(minutes: 5));
      final newerTs = DateTime.now();

      await File(olderPath).writeAsString(jsonEncode({
        'port': olderPort,
        'token': 'older',
        'pid': 11111,
        'createdAt': olderTs.toIso8601String(),
      }));
      await File(newerPath).writeAsString(jsonEncode({
        'port': newerPort,
        'token': 'newer',
        'pid': 22222,
        'createdAt': newerTs.toIso8601String(),
      }));

      try {
        final result = await BrokerDiscovery.findRunning();
        expect(result, isNotNull);
        expect(result!.token, 'newer');
      } finally {
        try { await File(olderPath).delete(); } catch (_) {}
        try { await File(newerPath).delete(); } catch (_) {}
        await older.stop();
        await newer.stop();
      }
    });

    test('listRunning returns all reachable brokers', () async {
      final server1 = BrokerServer(token: 'token1');
      final port1 = await server1.start();

      final server2 = BrokerServer(token: 'token2');
      final port2 = await server2.start();

      // Write handle files
      final handle1Path = p.join(
        Platform.environment['TMPDIR'] ?? '/tmp',
        'marionette-broker-test1.json',
      );
      final handle2Path = p.join(
        Platform.environment['TMPDIR'] ?? '/tmp',
        'marionette-broker-test2.json',
      );

      await File(handle1Path).writeAsString(jsonEncode({
        'port': port1,
        'token': 'token1',
        'pid': 12345,
        'createdAt': DateTime.now().toIso8601String(),
      }));
      await File(handle2Path).writeAsString(jsonEncode({
        'port': port2,
        'token': 'token2',
        'pid': 12346,
        'createdAt': DateTime.now().toIso8601String(),
      }));

      try {
        final results = await BrokerDiscovery.listRunning();
        expect(results.length, greaterThanOrEqualTo(2));
      } finally {
        try { await File(handle1Path).delete(); } catch (_) {}
        try { await File(handle2Path).delete(); } catch (_) {}
        await server1.stop();
        await server2.stop();
      }
    });
  });
}
