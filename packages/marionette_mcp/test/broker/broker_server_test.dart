import 'dart:async';
import 'dart:convert';

import 'package:marionette_mcp/src/broker/broker_server.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  late BrokerServer server;

  tearDown(() async {
    await server.stop();
  });

  group('BrokerServer auth', () {
    test('rejects connection with bad token', () async {
      server = BrokerServer(token: 'secret-token');
      final port = await server.start();

      final ws = WebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:$port'),
      );

      // Send bad token
      ws.sink.add(_encodeFrame(
        0x01,
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 0,
          'method': 'auth',
          'params': {'token': 'wrong'},
        }).codeUnits,
      ));

      // Should be closed with 4401
      await Future.delayed(const Duration(milliseconds: 200));
      expect(ws.closeCode, 4401);
    });

    test('accepts connection with valid token', () async {
      server = BrokerServer(token: 'secret-token');
      final port = await server.start();

      final ws = WebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:$port'),
      );

      // Send valid token
      ws.sink.add(_encodeFrame(
        0x01,
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 0,
          'method': 'auth',
          'params': {'token': 'secret-token'},
        }).codeUnits,
      ));

      // Should receive auth success
      final msg = await ws.stream.first.timeout(const Duration(seconds: 5));
      final bytes = _toBytes(msg);
      expect(bytes[0], 0x01);
      final text = String.fromCharCodes(bytes.sublist(1));
      final rpc = jsonDecode(text) as Map<String, dynamic>;
      expect(rpc['id'], 0);
      expect(rpc['result'], isNotNull);
    });
  });

  group('BrokerServer request/response', () {
    test('relays JSON-RPC request to app and returns response', () async {
      server = BrokerServer(token: 'secret-token');
      final port = await server.start();

      // Connect and auth app
      final appWs = WebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:$port'),
      );

      // Set up listener before sending auth
      final authReceived = Completer<void>();
      final requestReceived = Completer<Map<String, dynamic>>();

      appWs.stream.listen((msg) {
        final bytes = _toBytes(msg);
        final text = String.fromCharCodes(bytes.sublist(1));
        final rpc = jsonDecode(text) as Map<String, dynamic>;
        if (rpc.containsKey('result') && !authReceived.isCompleted) {
          authReceived.complete();
        } else if (rpc.containsKey('method') && !requestReceived.isCompleted) {
          requestReceived.complete(rpc);
        }
      });

      appWs.sink.add(_encodeFrame(
        0x01,
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 0,
          'method': 'auth',
          'params': {'token': 'secret-token'},
        }).codeUnits,
      ));

      // Wait for auth success
      await authReceived.future.timeout(const Duration(seconds: 5));

      // Now make a request from the server side
      final responseFuture = server.request('echo', {'data': 'hello'});

      // Wait for app to receive request
      final reqRpc = await requestReceived.future.timeout(const Duration(seconds: 5));
      expect(reqRpc['method'], 'echo');

      // Send response
      appWs.sink.add(_encodeFrame(
        0x01,
        jsonEncode({
          'jsonrpc': '2.0',
          'id': reqRpc['id'],
          'result': {'echoed': reqRpc['params']},
        }).codeUnits,
      ));

      final result = await responseFuture;
      expect(result['echoed']['data'], 'hello');
    });
  });

  group('BrokerServer idle timeout', () {
    test('closes connection after idle timeout', () async {
      server = BrokerServer(
        token: 'secret-token',
        idleTimeout: const Duration(milliseconds: 100),
      );
      final port = await server.start();

      final ws = WebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:$port'),
      );

      // Auth
      ws.sink.add(_encodeFrame(
        0x01,
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 0,
          'method': 'auth',
          'params': {'token': 'secret-token'},
        }).codeUnits,
      ));

      // Wait for auth
      await ws.stream.first.timeout(const Duration(seconds: 5));

      // Wait for idle timeout to close
      await Future.delayed(const Duration(milliseconds: 300));
      expect(ws.closeCode, 4408);
    });
  });
}

List<int> _encodeFrame(int discriminator, List<int> payload) {
  return [discriminator, ...payload];
}

List<int> _toBytes(dynamic msg) {
  if (msg is String) return msg.codeUnits;
  if (msg is List<int>) return msg;
  if (msg is List) return msg.cast<int>();
  throw FormatException('unexpected message type: ${msg.runtimeType}');
}
