import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'broker_options.dart';
import 'dispatcher.dart';
import 'frame_discriminator.dart';
import 'jsonrpc_codec.dart';
import 'transport.dart';

class BrokerTransport implements Transport {
  BrokerTransport({
    required this.uri,
    required this.token,
    required this.dispatcher,
    required this.options,
  });

  final Uri uri;
  final String token;
  final Dispatcher dispatcher;
  final BrokerOptions options;

  WebSocketChannel? _channel;
  Timer? _idleTimer;
  bool _stopped = false;
  bool _connected = false;
  int _backoffMs = 1000;
  Duration _totalReconnectElapsed = Duration.zero;
  StreamSubscription? _subscription;

  bool get isConnected => _connected;

  @override
  Future<void> start() async {
    await _connect();
  }

  Future<void> _connect() async {
    if (_stopped) return;
    late final WebSocketChannel ch;
    try {
      ch = WebSocketChannel.connect(uri);
    } catch (_) {
      _onConnectFailed();
      return;
    }
    _channel = ch;
    _connected = false;

    // Handle connection errors from the ready future.
    ch.ready.catchError((_) {
      _onClose(1006);
      return null;
    });

    // Send auth as first frame.
    ch.sink.add(
      FrameCodec.encodeBinary(
        Frame.jsonRpc(
          JsonRpcCodec.encodeRequest(
            id: 0,
            method: 'auth',
            params: {'token': token},
          ),
        ),
      ),
    );

    _subscription = ch.stream.listen(
      (msg) {
        _resetIdle();
        if (!_connected) {
          _handleAuthResponse(msg);
        } else {
          _handleFrame(msg);
        }
      },
      onDone: () => _onClose(ch.closeCode),
      onError: (_) => _onClose(1006),
      cancelOnError: true,
    );
    _resetIdle();
  }

  void _handleAuthResponse(dynamic msg) {
    try {
      final bytes = _toBytes(msg);
      final frame = FrameCodec.decodeBinary(bytes);
      if (frame.kind == FrameKind.jsonRpc) {
        final rpc = JsonRpcCodec.decode(frame.jsonRpcText!);
        if (rpc.id == 0) {
          if (rpc.method.isEmpty) {
            // Auth succeeded (result response with no method).
            _connected = true;
            _backoffMs = 1000;
            _totalReconnectElapsed = Duration.zero;
          }
        }
      }
    } catch (_) {
      // Auth failed or malformed; connection will be closed by server.
    }
  }

  void _resetIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(options.idleTimeout, () {
      _channel?.sink.close(4408, 'idle');
    });
  }

  Future<void> _handleFrame(dynamic msg) async {
    final bytes = _toBytes(msg);
    final frame = FrameCodec.decodeBinary(bytes);
    if (frame.kind != FrameKind.jsonRpc) return;
    final rpc = JsonRpcCodec.decode(frame.jsonRpcText!);
    try {
      final result = await dispatcher.dispatch(
        rpc.method,
        rpc.params ?? const {},
      );
      _send(JsonRpcCodec.encodeResult(id: rpc.id!, result: result));
    } on DispatcherError catch (e) {
      _send(
        JsonRpcCodec.encodeError(
          id: rpc.id!,
          code: -32601,
          message: e.message,
        ),
      );
    }
  }

  void _send(String text) {
    final f = Frame.jsonRpc(text);
    _channel?.sink.add(FrameCodec.encodeBinary(f));
  }

  void sendBinary(List<int> data) {
    _channel?.sink.add(FrameCodec.encodeBinary(Frame.screencast(data)));
  }

  void _onClose(int? code) {
    _idleTimer?.cancel();
    _connected = false;
    if (_stopped) return;
    if (!options.autoReconnect) return;
    if (code != null && _isFinalCode(code)) return;
    if (_totalReconnectElapsed > const Duration(seconds: 30)) return;
    _scheduleReconnect();
  }

  void _onConnectFailed() {
    _connected = false;
    if (_stopped) return;
    if (!options.autoReconnect) return;
    if (_totalReconnectElapsed > const Duration(seconds: 30)) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    Future.delayed(Duration(milliseconds: _backoffMs), () {
      if (_stopped) return;
      _totalReconnectElapsed += Duration(milliseconds: _backoffMs);
      _backoffMs = (_backoffMs * 2).clamp(1000, 16000);
      _connect();
    });
  }

  bool _isFinalCode(int code) =>
      code == 1000 ||
      code == 4408 ||
      code == 4401 ||
      (code >= 4000 && code != 4000);

  List<int> _toBytes(dynamic msg) {
    if (msg is String) return msg.codeUnits;
    if (msg is List<int>) return msg;
    if (msg is List) return msg.cast<int>();
    throw FormatException('unexpected message type: ${msg.runtimeType}');
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    _idleTimer?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
  }
}
