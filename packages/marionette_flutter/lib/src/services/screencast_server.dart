import 'dart:typed_data';
import 'dart:ui';

import 'package:marionette_flutter/src/services/screencast_service.dart';

/// Factory for creating ScreencastService instances.
typedef ScreencastServiceFactory = ScreencastService Function({
  Size? maxSize,
});

/// Provider for the current viewport size.
typedef ViewportSizeProvider = Size Function();

/// Callback for emitting binary screencast frames to an external transport
/// (e.g., broker WebSocket).
typedef BinaryFrameEmitter = void Function(Uint8List frame);

/// Abstract interface for screencast server implementations.
///
/// Implementations manage the screencast lifecycle and push frames to a
/// consumer over a transport-specific channel (TCP, WebSocket, etc.).
abstract class ScreencastServer {
  /// Whether the screencast is currently active.
  bool get isActive;

  /// Starts the screencast and returns transport-specific connection info.
  ///
  /// The returned map always includes `viewportWidth`, `viewportHeight`,
  /// and `transport`. Additional fields depend on the transport type.
  ///
  /// [wsPort] is used by WebSocket-based implementations (web and native
  /// reverse-WS) — the MCP side passes its WebSocket server port so the
  /// Flutter app can connect back to it.
  ///
  /// [binaryEmitter] is an optional callback that receives raw RGBA frames
  /// for forwarding through an external transport (e.g., broker WebSocket).
  Future<Map<String, dynamic>> startScreencast({
    int? maxWidth,
    int? maxHeight,
    int? wsPort,
    BinaryFrameEmitter? binaryEmitter,
  });

  /// Stops the screencast and cleans up resources.
  Future<void> stopScreencast();
}
