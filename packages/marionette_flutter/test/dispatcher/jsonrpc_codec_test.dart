import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/dispatcher/jsonrpc_codec.dart';

void main() {
  test('encodes a request', () {
    expect(
      JsonRpcCodec.encodeRequest(id: 1, method: 'tap', params: {'ref': '@1'}),
      '{"jsonrpc":"2.0","id":1,"method":"tap","params":{"ref":"@1"}}',
    );
  });

  test('decodes a request', () {
    final m = JsonRpcCodec.decode(
      '{"jsonrpc":"2.0","id":1,"method":"tap","params":{}}',
    );
    expect(m.id, 1);
    expect(m.method, 'tap');
  });

  test('encodes a result response', () {
    expect(
      JsonRpcCodec.encodeResult(id: 1, result: {'ok': true}),
      '{"jsonrpc":"2.0","id":1,"result":{"ok":true}}',
    );
  });

  test('encodes an error response', () {
    final s = JsonRpcCodec.encodeError(
      id: 1,
      code: -32601,
      message: 'Method not found',
    );
    expect(s.contains('"code":-32601'), isTrue);
  });

  test('decodes a response with result', () {
    final m = JsonRpcCodec.decode(
      '{"jsonrpc":"2.0","id":42,"result":{"value":1}}',
    );
    expect(m.id, 42);
    expect(m.method, '');
    expect(m.params, isNull);
  });

  test('encodeRequest without params omits params key', () {
    final s = JsonRpcCodec.encodeRequest(id: 1, method: 'ping');
    expect(s.contains('params'), isFalse);
  });
}
