import 'dart:convert';
import 'dart:developer' as developer;

import 'dispatcher.dart';
import 'transport.dart';

class VmServiceTransport implements Transport {
  VmServiceTransport({
    required this.dispatcher,
    this.prefix = 'marionette',
  });

  final Dispatcher dispatcher;
  final String prefix;

  bool _started = false;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    for (final method in dispatcher.registeredMethods) {
      developer.registerExtension(
        'ext.$prefix.$method',
        (_, params) async {
          try {
            final result = await dispatcher.dispatch(method, params);
            return developer.ServiceExtensionResponse.result(
              jsonEncode(result),
            );
          } on DispatcherError catch (e) {
            return developer.ServiceExtensionResponse.error(
              developer.ServiceExtensionResponse.invalidParams,
              jsonEncode({'code': e.code, 'message': e.message}),
            );
          }
        },
      );
    }
  }

  @override
  Future<void> stop() async {
    // VM service extensions cannot be unregistered.
  }
}
