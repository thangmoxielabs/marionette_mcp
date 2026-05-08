import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/dispatcher/broker_options.dart';

void main() {
  test('MarionetteConfiguration without enableBroker has null broker opts', () {
    const config = MarionetteConfiguration();
    expect(config.enableBroker, isNull);
  });

  test('MarionetteConfiguration with enableBroker has broker opts', () {
    final config = MarionetteConfiguration(
      enableBroker: const BrokerOptions(autoActivate: false),
    );
    expect(config.enableBroker, isNotNull);
    expect(config.enableBroker!.autoActivate, isFalse);
  });

  test('BrokerOptions default autoActivate is true', () {
    const opts = BrokerOptions();
    expect(opts.autoActivate, isTrue);
  });
}
