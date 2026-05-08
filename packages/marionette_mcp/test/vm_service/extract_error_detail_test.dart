import 'dart:convert';

import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  group('extractErrorDetail', () {
    test('extracts exception from JSON-encoded message', () {
      final error = RPCError(
        'callServiceExtension',
        -32000,
        json.encode({
          'exception': 'StateError: Widget not found after 200 scroll attempts',
          'stack': '#0 ScrollSimulator._dragUntilVisible\n#1 ...',
          'method': 'ext.flutter.marionette.scrollTo',
        }),
      );

      expect(
        extractErrorDetail(error),
        'StateError: Widget not found after 200 scroll attempts',
      );
    });

    test('extracts exception from JSON even with empty stack', () {
      final error = RPCError(
        'callServiceExtension',
        -32000,
        json.encode({
          'exception': 'Exception: No Scrollable widget found in the tree',
          'stack': '',
          'method': 'ext.flutter.marionette.scrollTo',
        }),
      );

      expect(
        extractErrorDetail(error),
        'Exception: No Scrollable widget found in the tree',
      );
    });

    test('falls back to details when message is not JSON', () {
      final error = RPCError.withDetails(
        'callServiceExtension',
        -32000,
        'Server error',
        details: 'Element with key "submit_button" not found',
      );

      expect(
        extractErrorDetail(error),
        'Element with key "submit_button" not found',
      );
    });

    test('falls back to message when no JSON and no details', () {
      final error = RPCError(
        'callServiceExtension',
        -32000,
        'Server error',
      );

      expect(extractErrorDetail(error), 'Server error');
    });

    test('falls back to raw message when JSON has empty exception', () {
      final jsonMessage = json.encode({
        'exception': '',
        'stack': '',
        'method': 'ext.flutter.marionette.scrollTo',
      });
      final error = RPCError(
        'callServiceExtension',
        -32000,
        jsonMessage,
      );

      // Falls back to raw message since exception is empty.
      expect(extractErrorDetail(error), jsonMessage);
    });

    test('falls back to raw message when JSON has no exception key', () {
      final jsonMessage =
          json.encode({'stack': 'some stack', 'method': 'some.method'});
      final error = RPCError(
        'callServiceExtension',
        -32000,
        jsonMessage,
      );

      expect(extractErrorDetail(error), jsonMessage);
    });

    test('produces verbose VmServiceExtensionException toString', () {
      final exception = VmServiceExtensionException(
        'Extension marionette.scrollTo failed',
        errorCode: -32000,
        error: 'StateError: Widget not found after 200 scroll attempts',
      );

      expect(
        exception.toString(),
        'Extension marionette.scrollTo failed\n'
        'Error: StateError: Widget not found after 200 scroll attempts',
      );
    });
  });
}
