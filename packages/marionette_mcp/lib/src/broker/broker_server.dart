import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart' as logging;
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A local WebSocket broker server that accepts a single app connection,
/// enforces token authentication and idle timeout, and relays JSON-RPC
/// requests between the MCP server and the Flutter app.
///
/// The broker uses a frame discriminator protocol:
/// - 0x01 prefix: JSON-RPC text frame
/// - 0x02 prefix: Binary screencast frame
class BrokerServer {
  BrokerServer({
    this.port = 0,
    required this.token,
    this.idleTimeout = const Duration(minutes: 30),
  });

  final int port;
  final String token;
  final Duration idleTimeout;

  late HttpServer _server;
  WebSocketChannel? _appChannel;
  bool _started = false;

  final _logger = logging.Logger('BrokerServer');

  final _pendingRequests = <int, Completer<Map<String, dynamic>>>{};
  int _nextRequestId = 1;

  int get actualPort => _server.port;

  /// Starts the broker server and returns the actual port it's listening on.
  Future<int> start() async {
    if (_started) throw StateError('BrokerServer already started');
    _started = true;

    final handler = webSocketHandler((WebSocketChannel ws) {
      _handleAppConnection(ws);
    });

    _server = await io.serve(
      handler,
      InternetAddress.loopbackIPv4,
      port,
    );

    _logger.info('Broker server started on port ${_server.port}');
    return _server.port;
  }

  void _handleAppConnection(WebSocketChannel ws) {
    if (_appChannel != null) {
      _logger.warning('Rejecting duplicate app connection');
      ws.sink.close(4409, 'already connected');
      return;
    }

    var authed = false;
    Timer? idleTimer;

    void resetIdle() {
      idleTimer?.cancel();
      idleTimer = Timer(idleTimeout, () {
        _logger.info('Idle timeout, closing app connection');
        ws.sink.close(4408, 'idle');
      });
    }

    resetIdle();

    ws.stream.listen(
      (msg) async {
        resetIdle();

        final bytes = _toBytes(msg);
        if (bytes.isEmpty) return;

        final discriminator = bytes[0];
        final payload = bytes.sublist(1);

        if (!authed) {
          // First message must be JSON-RPC auth request
          if (discriminator != 0x01) {
            ws.sink.close(4401, 'auth required');
            return;
          }
          final text = String.fromCharCodes(payload);
          try {
            final rpc = jsonDecode(text) as Map<String, dynamic>;
            if (rpc['method'] == 'auth') {
              final params = rpc['params'] as Map<String, dynamic>;
              if (params['token'] == token) {
                authed = true;
                _appChannel = ws;
                _logger.info('App authenticated');
                // Send auth success
                final response = jsonEncode({
                  'jsonrpc': '2.0',
                  'id': rpc['id'],
                  'result': {},
                });
                ws.sink.add(_encodeFrame(0x01, response.codeUnits));
                return;
              }
            }
            ws.sink.close(4401, 'invalid token');
          } catch (e) {
            ws.sink.close(4401, 'auth parse error');
          }
          return;
        }

        // Authed: handle responses and screencast frames
        if (discriminator == 0x01) {
          final text = String.fromCharCodes(payload);
          try {
            final rpc = jsonDecode(text) as Map<String, dynamic>;
            final id = rpc['id'] as int?;
            if (id != null && _pendingRequests.containsKey(id)) {
              final completer = _pendingRequests.remove(id)!;
              if (rpc.containsKey('error')) {
                completer.completeError(
                  Exception(rpc['error']['message'] ?? 'unknown error'),
                );
              } else {
                completer.complete(rpc['result'] as Map<String, dynamic>);
              }
            }
          } catch (e) {
            _logger.warning('Failed to parse app response: $e');
          }
        } else if (discriminator == 0x02) {
          // Screencast frame — handled by subscribers (not implemented here)
          _logger.fine('Received screencast frame (${payload.length} bytes)');
        }
      },
      onDone: () {
        idleTimer?.cancel();
        _logger.info('App connection closed');
        if (_appChannel == ws) {
          _appChannel = null;
        }
        // Fail all pending requests
        for (final completer in _pendingRequests.values) {
          completer.completeError(Exception('app disconnected'));
        }
        _pendingRequests.clear();
      },
      onError: (e) {
        idleTimer?.cancel();
        _logger.warning('App connection error: $e');
        if (_appChannel == ws) {
          _appChannel = null;
        }
      },
    );
  }

  /// Sends a JSON-RPC request to the connected app and awaits the response.
  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic> params,
  ) async {
    if (_appChannel == null) {
      throw StateError('No app connected');
    }

    final id = _nextRequestId++;
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;

    final rpc = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });

    _appChannel!.sink.add(_encodeFrame(0x01, rpc.codeUnits));

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pendingRequests.remove(id);
        throw TimeoutException('Request timed out: $method');
      },
    );
  }

  /// Checks if an app is currently connected.
  bool get hasAppConnected => _appChannel != null;

  /// Stops the broker server.
  Future<void> stop() async {
    if (!_started) return;
    await _appChannel?.sink.close();
    await _server.close();
    _started = false;
    _logger.info('Broker server stopped');
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
