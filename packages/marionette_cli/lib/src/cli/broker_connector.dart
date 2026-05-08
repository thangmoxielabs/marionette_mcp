import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Connector that routes marionette requests through a local broker server
/// instead of the VM service.
class BrokerConnector {
  BrokerConnector({required this.uri, required this.token});

  final Uri uri;
  final String token;

  WebSocketChannel? _channel;
  bool _connected = false;
  int _nextRequestId = 1;
  final _pendingRequests = <int, Completer<Map<String, dynamic>>>{};

  Future<void> connect() async {
    _channel = WebSocketChannel.connect(uri);

    // Send auth
    _channel!.sink.add(_encodeFrame(
      0x01,
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 0,
        'method': 'auth',
        'params': {'token': token},
      }).codeUnits,
    ));

    // Wait for auth response
    final msg = await _channel!.stream.first.timeout(const Duration(seconds: 5));
    final bytes = _toBytes(msg);
    final text = String.fromCharCodes(bytes.sublist(1));
    final rpc = jsonDecode(text) as Map<String, dynamic>;

    if (rpc.containsKey('error')) {
      throw Exception('Auth failed: ${rpc['error']['message']}');
    }

    _connected = true;

    // Listen for responses
    _channel!.stream.listen(
      (msg) {
        final bytes = _toBytes(msg);
        if (bytes[0] != 0x01) return;
        final text = String.fromCharCodes(bytes.sublist(1));
        final rpc = jsonDecode(text) as Map<String, dynamic>;
        final id = rpc['id'] as int?;
        if (id != null && _pendingRequests.containsKey(id)) {
          final completer = _pendingRequests.remove(id)!;
          if (rpc.containsKey('error')) {
            completer.completeError(Exception(rpc['error']['message']));
          } else {
            completer.complete(rpc['result'] as Map<String, dynamic>);
          }
        }
      },
      onDone: () {
        _connected = false;
        for (final completer in _pendingRequests.values) {
          completer.completeError(Exception('broker disconnected'));
        }
        _pendingRequests.clear();
      },
    );
  }

  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic> params,
  ) async {
    if (!_connected) throw Exception('Not connected to broker');

    final id = _nextRequestId++;
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;

    _channel!.sink.add(_encodeFrame(
      0x01,
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }).codeUnits,
    ));

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pendingRequests.remove(id);
        throw TimeoutException('Request timed out: $method');
      },
    );
  }

  // High-level methods matching VmServiceConnector interface

  Future<Map<String, dynamic>> getInteractiveElements() {
    return request('interactiveElements', {});
  }

  Future<Map<String, dynamic>> tap(Map<String, dynamic> params) {
    return request('tap', params);
  }

  Future<Map<String, dynamic>> doubleTap(Map<String, dynamic> params) {
    return request('doubleTap', params);
  }

  Future<Map<String, dynamic>> longPress(Map<String, dynamic> params) {
    return request('longPress', params);
  }

  Future<Map<String, dynamic>> pinchZoom(Map<String, dynamic> params) {
    return request('pinchZoom', params);
  }

  Future<Map<String, dynamic>> enterText(Map<String, dynamic> params) {
    return request('enterText', params);
  }

  Future<Map<String, dynamic>> scrollTo(Map<String, dynamic> params) {
    return request('scrollTo', params);
  }

  Future<Map<String, dynamic>> pressBackButton() {
    return request('pressBackButton', {});
  }

  Future<Map<String, dynamic>> hotReload() {
    return request('hotReload', {});
  }

  Future<Map<String, dynamic>> getLogs() {
    return request('getLogs', {});
  }

  Future<Map<String, dynamic>> takeScreenshots(Map<String, dynamic> params) {
    return request('takeScreenshots', params);
  }

  Future<void> disconnect() async {
    await _channel?.sink.close();
    _connected = false;
  }

  static List<int> _encodeFrame(int discriminator, List<int> payload) {
    return [discriminator, ...payload];
  }

  static List<int> _toBytes(dynamic msg) {
    if (msg is String) return msg.codeUnits;
    if (msg is List<int>) return msg;
    if (msg is List) return msg.cast<int>();
    throw FormatException('unexpected message type: ${msg.runtimeType}');
  }
}
