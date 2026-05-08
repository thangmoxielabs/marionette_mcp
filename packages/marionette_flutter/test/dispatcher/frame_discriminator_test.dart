import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/dispatcher/frame_discriminator.dart';

void main() {
  test('round-trip JSON-RPC frame', () {
    final original = Frame.jsonRpc('{"jsonrpc":"2.0","id":1}');
    final encoded = FrameCodec.encodeBinary(original);
    expect(encoded[0], FrameCodec.kJsonRpc);
    final decoded = FrameCodec.decodeBinary(encoded);
    expect(decoded.kind, FrameKind.jsonRpc);
    expect(decoded.jsonRpcText, '{"jsonrpc":"2.0","id":1}');
  });

  test('round-trip screencast frame', () {
    final payload = [0xDE, 0xAD, 0xBE, 0xEF];
    final original = Frame.screencast(payload);
    final encoded = FrameCodec.encodeBinary(original);
    expect(encoded[0], FrameCodec.kScreencast);
    final decoded = FrameCodec.decodeBinary(encoded);
    expect(decoded.kind, FrameKind.screencast);
    expect(decoded.binaryPayload, payload);
  });

  test('decode empty frame throws', () {
    expect(
      () => FrameCodec.decodeBinary([]),
      throwsA(isA<FormatException>()),
    );
  });

  test('decode unknown discriminator throws', () {
    expect(
      () => FrameCodec.decodeBinary([0xFF, 0x00]),
      throwsA(isA<FormatException>()),
    );
  });

  test('JSON-RPC discriminator byte is 0x01', () {
    expect(FrameCodec.kJsonRpc, 0x01);
  });

  test('screencast discriminator byte is 0x02', () {
    expect(FrameCodec.kScreencast, 0x02);
  });
}
