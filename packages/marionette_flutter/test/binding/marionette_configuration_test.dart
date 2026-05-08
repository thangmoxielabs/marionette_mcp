import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/dispatcher/broker_options.dart';

void main() {
  test('MarionetteConfiguration defaults enableBroker to null', () {
    const config = MarionetteConfiguration();
    expect(config.enableBroker, isNull);
  });

  test('MarionetteConfiguration accepts BrokerOptions', () {
    final config = MarionetteConfiguration(
      enableBroker: const BrokerOptions(),
    );
    expect(config.enableBroker, isNotNull);
    expect(config.enableBroker!.autoReconnect, isTrue);
    expect(config.enableBroker!.idleTimeout, const Duration(minutes: 30));
    expect(config.enableBroker!.allowRemote, isFalse);
  });

  test('BrokerOptions custom values', () {
    const opts = BrokerOptions(
      idleTimeout: Duration(minutes: 5),
      autoReconnect: false,
      autoActivate: false,
      showOverlay: false,
      allowRemote: true,
    );
    expect(opts.idleTimeout, const Duration(minutes: 5));
    expect(opts.autoReconnect, isFalse);
    expect(opts.autoActivate, isFalse);
    expect(opts.showOverlay, isFalse);
    expect(opts.allowRemote, isTrue);
  });
}
