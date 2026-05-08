import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/dispatcher/dispatcher.dart';

void main() {
  test('register and dispatch returns handler result', () async {
    final d = Dispatcher();
    d.register('echo', (params) async => {'echoed': params});
    final result = await d.dispatch('echo', {'a': 1});
    expect(result, {'echoed': {'a': 1}});
  });

  test('dispatch unknown method throws', () async {
    final d = Dispatcher();
    expect(
      () => d.dispatch('missing', const {}),
      throwsA(isA<DispatcherError>()),
    );
  });

  test('registeredMethods lists all registered methods', () async {
    final d = Dispatcher();
    d.register('foo', (p) async => {});
    d.register('bar', (p) async => {});
    expect(d.registeredMethods, containsAll(['foo', 'bar']));
  });

  test('double register throws StateError', () async {
    final d = Dispatcher();
    d.register('dup', (p) async => {});
    expect(
      () => d.register('dup', (p) async => {}),
      throwsA(isA<StateError>()),
    );
  });
}
