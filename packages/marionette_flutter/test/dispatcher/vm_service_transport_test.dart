import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/dispatcher/dispatcher.dart';
import 'package:marionette_flutter/src/dispatcher/transport.dart';
import 'package:marionette_flutter/src/dispatcher/vm_service_transport.dart';

void main() {
  test('VmServiceTransport start is idempotent', () async {
    final d = Dispatcher();
    d.register('foo', (p) async => {'ok': true});
    final t = VmServiceTransport(dispatcher: d, prefix: 'marionette');
    await t.start();
    await t.start(); // should not throw
    expect(t, isA<Transport>());
  });

  test('VmServiceTransport stop does not throw', () async {
    final d = Dispatcher();
    d.register('bar', (p) async => {});
    final t = VmServiceTransport(dispatcher: d);
    await t.start();
    await t.stop();
  });
}
