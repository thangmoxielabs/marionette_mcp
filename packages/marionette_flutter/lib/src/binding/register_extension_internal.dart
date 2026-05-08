import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';
import 'package:marionette_flutter/src/binding/register_extension.dart';
import 'package:marionette_flutter/src/dispatcher/dispatcher.dart';

/// Global dispatcher that all Marionette handlers register against.
final marionetteDispatcher = Dispatcher();

/// Callback type for Marionette extension handlers (VM service params).
typedef MarionetteExtensionCallback = Future<MarionetteExtensionResult>
    Function(Map<String, String> params);

/// Registers a built-in Marionette service extension.
///
/// This is intended for internal use by [MarionetteBinding] only. Unlike
/// [registerMarionetteExtension], it does **not** add the extension to the
/// [customExtensionRegistry].
///
/// The `ext.flutter.` prefix is added automatically to [name].
///
/// Registers the handler on the global [marionetteDispatcher]. The VM service
/// binding is handled separately by [VmServiceTransport].
void registerInternalMarionetteExtension({
  required String name,
  required MarionetteExtensionCallback callback,
}) {
  // strip 'marionette.' prefix; register on dispatcher
  final method = name.replaceFirst(RegExp(r'^marionette\.'), '');
  marionetteDispatcher.register(method, (params) async {
    final r = await callback(_toVmParams(params));
    return _resultToJson(r);
  });
}

Map<String, String> _toVmParams(Map<String, dynamic> params) {
  return params.map((k, v) => MapEntry(k, v?.toString() ?? ''));
}

Map<String, dynamic> _resultToJson(MarionetteExtensionResult result) {
  return switch (result) {
    MarionetteExtensionSuccess(data: final data) => data,
    MarionetteExtensionError(code: final code, detail: final detail) =>
      throw DispatcherError('extension_error_$code', detail),
    MarionetteExtensionInvalidParams(detail: final detail) =>
      throw DispatcherError('invalid_params', detail),
  };
}
