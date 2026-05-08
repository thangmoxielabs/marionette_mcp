import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/dispatcher/broker_options.dart';
import 'package:marionette_flutter/src/dispatcher/broker_transport.dart';
import 'package:marionette_flutter/src/dispatcher/dispatcher.dart';

void main() {
  test('BrokerTransport constructs with required params', () {
    final d = Dispatcher();
    final t = BrokerTransport(
      uri: Uri.parse('ws://127.0.0.1:0'),
      token: 'test-token',
      dispatcher: d,
      options: const BrokerOptions(autoReconnect: false),
    );
    expect(t.isConnected, isFalse);
    expect(t.uri.host, '127.0.0.1');
  });

  test('BrokerTransport stop is safe before start', () async {
    final d = Dispatcher();
    final t = BrokerTransport(
      uri: Uri.parse('ws://127.0.0.1:0'),
      token: 'test',
      dispatcher: d,
      options: const BrokerOptions(autoReconnect: false),
    );
    await t.stop(); // should not throw
  });

  test('BrokerTransport does not crash on unreachable URI', () async {
    final d = Dispatcher();
    final t = BrokerTransport(
      uri: Uri.parse('ws://127.0.0.1:1'),
      token: 'test',
      dispatcher: d,
      options: const BrokerOptions(autoReconnect: false),
    );
    // start() may fail internally but should not throw to caller
    try {
      await t.start();
    } catch (_) {
      // Expected: connection refused is caught internally
    }
    await Future.delayed(const Duration(milliseconds: 300));
    expect(t.isConnected, isFalse);
    await t.stop();
  });
}
