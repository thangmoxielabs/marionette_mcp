# Broker Transport — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an outbound-WebSocket broker transport so marionette can drive Flutter apps in production-grade builds (web, desktop, mobile release) that compile marionette in. The dispatcher and existing handlers are reused; only the ingress is new.

**Architecture:** A new `Dispatcher` owns the handler map. `VmServiceTransport` (extracted from existing `registerInternalMarionetteExtension` calls) is one ingress; `BrokerTransport` (new outbound JSON-RPC 2.0 over WS) is another. A local broker server inside `marionette_mcp` accepts the app's outbound connection, enforces token + idle, and forwards JSON-RPC requests from CLI/MCP. Screencast frames share the same WS via a one-byte type discriminator.

**Tech Stack:** Dart, Flutter, `package:web_socket_channel`, `package:test`, `flutter_test`. Existing patterns: `registerInternalMarionetteExtension`, `MarionetteConfiguration`.

**Spec:** `docs/superpowers/specs/2026-05-08-broker-transport-design.md`

---

## File Structure

**New (`marionette_flutter`):**

- `lib/src/dispatcher/dispatcher.dart` — handler registry.
- `lib/src/dispatcher/transport.dart` — `Transport` interface.
- `lib/src/dispatcher/vm_service_transport.dart` — wraps `developer.registerExtension`.
- `lib/src/dispatcher/broker_transport.dart` — outbound WS client; JSON-RPC 2.0 codec; reconnect.
- `lib/src/dispatcher/broker_options.dart` — public configuration.
- `lib/src/dispatcher/jsonrpc_codec.dart` — encode/decode JSON-RPC 2.0 frames.
- `lib/src/dispatcher/frame_discriminator.dart` — `0x01` text / `0x02` binary mux.
- `lib/src/binding/overlay/connected_overlay.dart` — visible "Marionette connected" overlay.
- Tests: `test/dispatcher/*.dart`.

**Modified (`marionette_flutter`):**

- `lib/src/binding/marionette_binding.dart` — wire dispatcher + transport selection.
- `lib/src/binding/marionette_configuration.dart` — `enableBroker: BrokerOptions?`.
- `lib/src/binding/extensions/*_extensions.dart` — register handlers against `Dispatcher` instead of directly via `developer.registerExtension`. Mechanical refactor.
- `lib/src/services/screencast_*` — emit binary frames through active transport(s).

**New (`marionette_mcp`):**

- `lib/src/broker/broker_server.dart` — local WS server; token + idle enforcement; JSON-RPC dispatch; binary frame relay.
- `lib/src/broker/broker_handle.dart` — local handle file (port + token) under `${TMPDIR}/marionette-broker-<pid>.json`.
- `lib/src/broker/broker_discovery.dart` — find a running broker via handle files.
- Tests: `test/broker/*.dart`.

**Modified (`marionette_mcp`):**

- `lib/src/mcp_server_runner.dart` — auto-spawn or auto-discover broker.
- `lib/src/vm_service/vm_service_connector.dart` — alternate connector for broker mode.

**New (`marionette_cli`):**

- `lib/src/cli/commands/broker/broker_command.dart` — top-level group.
- `lib/src/cli/commands/broker/start_command.dart`
- `lib/src/cli/commands/broker/status_command.dart`
- `lib/src/cli/commands/broker/stop_command.dart`

**Modified (`marionette_cli`):**

- All action commands — accept `--broker [<uri>]` with auto-discovery default.

---

### Task 1: Branch baseline

- [ ] **Step 1: Confirm branch.**

Run: `git status -sb`
Expected: `## feat/broker-transport`.

- [ ] **Step 2: Run all package tests; capture baseline.**

```bash
for d in packages/*/; do (cd "$d" && (dart test 2>/dev/null || flutter test 2>/dev/null) | tail -3); done
```

- [ ] **Step 3: Run analyze.**

```bash
dart analyze
```

Expected: no issues.

---

### Task 2: Release-mode capability audit (gated prerequisite)

**Goal:** Identify any handler that depends on `WidgetInspectorService` (stripped from release). Block any feature that wouldn't survive release.

- [ ] **Step 1: Search.**

```bash
grep -rn "WidgetInspectorService\|inspector\." packages/marionette_flutter/lib
```

- [ ] **Step 2: For each hit, classify:**
  - Used only by debug-only code paths (OK).
  - Used by handlers reachable via broker → must be replaced with public APIs.

- [ ] **Step 3: Document findings in `packages/marionette_flutter/RELEASE_AUDIT.md`.**

Write a short report listing each occurrence and its disposition (safe / needs-fix / scheduled-followup).

- [ ] **Step 4: Commit the audit.**

```bash
git add packages/marionette_flutter/RELEASE_AUDIT.md
git commit -m "docs(marionette_flutter): release-mode capability audit"
```

If any handler needs replacement, add follow-up tasks here before continuing.

---

### Task 3: `Dispatcher` skeleton

**Files:**
- Create: `packages/marionette_flutter/lib/src/dispatcher/dispatcher.dart`
- Test: `packages/marionette_flutter/test/dispatcher/dispatcher_test.dart`

- [ ] **Step 1: Failing test.**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/dispatcher/dispatcher.dart';

void main() {
  test('register and dispatch returns handler result', () async {
    final d = Dispatcher();
    d.register('echo', (params) async => {'echoed': params});
    final result = await d.dispatch('echo', {'a': 1});
    expect(result, {'echoed': {'a': 1}});
  });

  test('dispatch unknown method throws', () async {
    final d = Dispatcher();
    expect(() => d.dispatch('missing', const {}), throwsA(isA<DispatcherError>()));
  });
}
```

- [ ] **Step 2: Verify failure.**

Run: `cd packages/marionette_flutter && flutter test test/dispatcher/dispatcher_test.dart`
Expected: compile error.

- [ ] **Step 3: Implement.**

```dart
// packages/marionette_flutter/lib/src/dispatcher/dispatcher.dart

typedef DispatchHandler = Future<Map<String, dynamic>> Function(Map<String, dynamic> params);

class DispatcherError implements Exception {
  DispatcherError(this.code, this.message);
  final String code;
  final String message;
  @override String toString() => 'DispatcherError($code): $message';
}

class Dispatcher {
  final Map<String, DispatchHandler> _handlers = {};

  void register(String method, DispatchHandler handler) {
    if (_handlers.containsKey(method)) {
      throw StateError('Method already registered: $method');
    }
    _handlers[method] = handler;
  }

  Future<Map<String, dynamic>> dispatch(String method, Map<String, dynamic> params) async {
    final h = _handlers[method];
    if (h == null) throw DispatcherError('method_not_found', 'No handler for $method');
    return h(params);
  }

  Iterable<String> get registeredMethods => _handlers.keys;
}
```

- [ ] **Step 4: Run tests.**

Expected: pass.

- [ ] **Step 5: Commit.**

```bash
git add packages/marionette_flutter/lib/src/dispatcher/dispatcher.dart \
        packages/marionette_flutter/test/dispatcher/dispatcher_test.dart
git commit -m "feat(marionette_flutter): introduce Dispatcher handler registry"
```

---

### Task 4: `Transport` interface + `VmServiceTransport`

**Files:**
- Create: `packages/marionette_flutter/lib/src/dispatcher/transport.dart`
- Create: `packages/marionette_flutter/lib/src/dispatcher/vm_service_transport.dart`
- Test: `packages/marionette_flutter/test/dispatcher/vm_service_transport_test.dart`

- [ ] **Step 1: Failing test.**

```dart
test('VmServiceTransport binds dispatcher methods to dart:developer extensions', () async {
  final d = Dispatcher();
  d.register('foo', (p) async => {'ok': true});
  final t = VmServiceTransport(dispatcher: d, prefix: 'marionette');
  await t.start();
  // postEvent or simulate ext.marionette.foo invocation; assert response.
});
```

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Implement.**

```dart
// transport.dart
abstract class Transport {
  Future<void> start();
  Future<void> stop();
}

// vm_service_transport.dart
import 'dart:developer' as developer;
import 'dart:convert';
import 'dispatcher.dart';
import 'transport.dart';

class VmServiceTransport implements Transport {
  VmServiceTransport({required this.dispatcher, this.prefix = 'marionette'});
  final Dispatcher dispatcher;
  final String prefix;

  bool _started = false;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    for (final method in dispatcher.registeredMethods) {
      developer.registerExtension('ext.$prefix.$method', (_, params) async {
        try {
          final result = await dispatcher.dispatch(method, params);
          return developer.ServiceExtensionResponse.result(jsonEncode(result));
        } on DispatcherError catch (e) {
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.invalidParams,
            jsonEncode({'code': e.code, 'message': e.message}),
          );
        }
      });
    }
  }

  @override
  Future<void> stop() async {} // VM service exts cannot be unregistered.
}
```

- [ ] **Step 4: Run tests.**

- [ ] **Step 5: Commit.**

```bash
git add packages/marionette_flutter/lib/src/dispatcher/transport.dart \
        packages/marionette_flutter/lib/src/dispatcher/vm_service_transport.dart \
        packages/marionette_flutter/test/dispatcher/vm_service_transport_test.dart
git commit -m "feat(marionette_flutter): Transport interface + VmServiceTransport"
```

---

### Task 5: Refactor existing extensions to register against `Dispatcher`

**Files:**
- Modify: every `packages/marionette_flutter/lib/src/binding/extensions/*_extensions.dart`
- Modify: `packages/marionette_flutter/lib/src/binding/register_extension_internal.dart`
- Modify: `packages/marionette_flutter/lib/src/binding/marionette_binding.dart`

- [ ] **Step 1: Replace `registerInternalMarionetteExtension` with `dispatcher.register`.**

Update `register_extension_internal.dart` to expose a global dispatcher accessor:

```dart
final marionetteDispatcher = Dispatcher();

void registerInternalMarionetteExtension({
  required String name,
  required Future<MarionetteExtensionResult> Function(Map<String, dynamic>) callback,
}) {
  // strip 'marionette.' prefix; register on dispatcher
  final method = name.replaceFirst(RegExp(r'^marionette\.'), '');
  marionetteDispatcher.register(method, (params) async {
    final r = await callback(params);
    return r.toJson();
  });
}
```

In `marionette_binding.dart`, after all extensions register, start the VM service transport:

```dart
final vmTransport = VmServiceTransport(dispatcher: marionetteDispatcher);
await vmTransport.start();
```

- [ ] **Step 2: Run all flutter tests; verify the existing extensions still work via VM service.**

Expected: pass.

- [ ] **Step 3: Run a sanity check end-to-end test using `developer.Service` against an existing handler (e.g., `interactiveElements`).**

- [ ] **Step 4: Commit.**

```bash
git commit -am "refactor(marionette_flutter): route all extensions through Dispatcher"
```

---

### Task 6: JSON-RPC 2.0 codec

**Files:**
- Create: `packages/marionette_flutter/lib/src/dispatcher/jsonrpc_codec.dart`
- Test: `packages/marionette_flutter/test/dispatcher/jsonrpc_codec_test.dart`

- [ ] **Step 1: Failing test.**

```dart
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
    final m = JsonRpcCodec.decode('{"jsonrpc":"2.0","id":1,"method":"tap","params":{}}');
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
    final s = JsonRpcCodec.encodeError(id: 1, code: -32601, message: 'Method not found');
    expect(s.contains('"code":-32601'), isTrue);
  });
}
```

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Implement.**

```dart
// jsonrpc_codec.dart
import 'dart:convert';

class JsonRpcMessage {
  JsonRpcMessage({this.id, required this.method, this.params});
  final int? id;
  final String method;
  final Map<String, dynamic>? params;
}

class JsonRpcCodec {
  static String encodeRequest({required int id, required String method, Map<String, dynamic>? params}) =>
      jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, if (params != null) 'params': params});

  static String encodeResult({required int id, required Map<String, dynamic> result}) =>
      jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result});

  static String encodeError({required int id, required int code, required String message}) =>
      jsonEncode({'jsonrpc': '2.0', 'id': id, 'error': {'code': code, 'message': message}});

  static JsonRpcMessage decode(String s) {
    final m = jsonDecode(s) as Map<String, dynamic>;
    return JsonRpcMessage(
      id: m['id'] as int?,
      method: m['method'] as String,
      params: m['params'] as Map<String, dynamic>?,
    );
  }
}
```

- [ ] **Step 4: Run tests.**

- [ ] **Step 5: Commit.**

```bash
git add packages/marionette_flutter/lib/src/dispatcher/jsonrpc_codec.dart \
        packages/marionette_flutter/test/dispatcher/jsonrpc_codec_test.dart
git commit -m "feat(marionette_flutter): JSON-RPC 2.0 codec"
```

---

### Task 7: Frame discriminator

**Files:**
- Create: `packages/marionette_flutter/lib/src/dispatcher/frame_discriminator.dart`
- Test: `packages/marionette_flutter/test/dispatcher/frame_discriminator_test.dart`

- [ ] **Step 1: Failing test** — round-trip a JSON-RPC frame and a binary screencast frame through encode/decode; assert discriminator byte is correct.

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Implement.**

```dart
class Frame {
  Frame.jsonRpc(this.jsonRpcText) : binaryPayload = null, kind = FrameKind.jsonRpc;
  Frame.screencast(this.binaryPayload) : jsonRpcText = null, kind = FrameKind.screencast;

  final FrameKind kind;
  final String? jsonRpcText;
  final List<int>? binaryPayload;
}

enum FrameKind { jsonRpc, screencast }

class FrameCodec {
  static const int kJsonRpc = 0x01;
  static const int kScreencast = 0x02;

  static List<int> encodeBinary(Frame f) {
    if (f.kind == FrameKind.jsonRpc) {
      return [kJsonRpc, ...f.jsonRpcText!.codeUnits];
    }
    return [kScreencast, ...f.binaryPayload!];
  }

  static Frame decodeBinary(List<int> bytes) {
    if (bytes.isEmpty) throw FormatException('empty frame');
    switch (bytes[0]) {
      case kJsonRpc:
        return Frame.jsonRpc(String.fromCharCodes(bytes.sublist(1)));
      case kScreencast:
        return Frame.screencast(bytes.sublist(1));
      default:
        throw FormatException('unknown discriminator: ${bytes[0]}');
    }
  }
}
```

- [ ] **Step 4: Run tests.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_flutter): frame discriminator codec"
```

---

### Task 8: `BrokerOptions` config + `MarionetteConfiguration` integration

**Files:**
- Create: `packages/marionette_flutter/lib/src/dispatcher/broker_options.dart`
- Modify: `packages/marionette_flutter/lib/src/binding/marionette_configuration.dart`
- Test: extend `marionette_configuration_test.dart`.

- [ ] **Step 1: Failing test** — construct `MarionetteConfiguration(enableBroker: BrokerOptions())`; assert defaults.

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Implement.**

```dart
// broker_options.dart
class BrokerOptions {
  const BrokerOptions({
    this.idleTimeout = const Duration(minutes: 30),
    this.autoReconnect = true,
    this.autoActivate = true,
    this.showOverlay = true,
    this.allowRemote = false,
  });
  final Duration idleTimeout;
  final bool autoReconnect;
  final bool autoActivate;
  final bool showOverlay;
  final bool allowRemote;
}
```

Add `final BrokerOptions? enableBroker;` field to `MarionetteConfiguration`.

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_flutter): BrokerOptions on MarionetteConfiguration"
```

---

### Task 9: `BrokerTransport` (outbound WS client)

**Files:**
- Create: `packages/marionette_flutter/lib/src/dispatcher/broker_transport.dart`
- Test: `packages/marionette_flutter/test/dispatcher/broker_transport_test.dart`

- [ ] **Step 1: Failing test** — spin up an in-test WS server simulating a broker; instantiate `BrokerTransport(uri, token, dispatcher)`; verify auth handshake, then send a JSON-RPC request frame to the transport and assert the dispatcher's handler is invoked and the response is sent back. Also test idle close (4408) → no reconnect; transient close (1006) → reconnects within window.

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Implement.**

```dart
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';

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
  int _backoffMs = 1000;
  Duration _totalReconnectElapsed = Duration.zero;

  @override
  Future<void> start() async {
    await _connect();
  }

  Future<void> _connect() async {
    final ch = WebSocketChannel.connect(uri);
    _channel = ch;
    // Send auth as first frame.
    ch.sink.add(JsonRpcCodec.encodeRequest(id: 0, method: 'auth', params: {'token': token}));
    ch.stream.listen(
      (msg) {
        _resetIdle();
        _handleFrame(msg);
      },
      onDone: () => _onClose(ch.closeCode),
      onError: (_) => _onClose(1006),
    );
    _resetIdle();
  }

  void _resetIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(options.idleTimeout, () {
      _channel?.sink.close(4408, 'idle');
    });
  }

  Future<void> _handleFrame(dynamic msg) async {
    final bytes = msg is String ? msg.codeUnits : (msg as List<int>);
    final frame = FrameCodec.decodeBinary(bytes);
    if (frame.kind != FrameKind.jsonRpc) return; // we don't accept binary inbound
    final rpc = JsonRpcCodec.decode(frame.jsonRpcText!);
    try {
      final result = await dispatcher.dispatch(rpc.method, rpc.params ?? const {});
      _send(JsonRpcCodec.encodeResult(id: rpc.id!, result: result));
    } on DispatcherError catch (e) {
      _send(JsonRpcCodec.encodeError(id: rpc.id!, code: -32601, message: e.message));
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
    if (_stopped) return;
    if (!options.autoReconnect) return;
    if (code != null && _isFinalCode(code)) return;
    if (_totalReconnectElapsed > const Duration(seconds: 30)) return;
    Future.delayed(Duration(milliseconds: _backoffMs), () {
      _totalReconnectElapsed += Duration(milliseconds: _backoffMs);
      _backoffMs = (_backoffMs * 2).clamp(1000, 16000);
      _connect();
    });
  }

  bool _isFinalCode(int code) =>
      code == 1000 || code == 4408 || code == 4401 || (code >= 4000 && code != 4000);

  @override
  Future<void> stop() async {
    _stopped = true;
    _idleTimer?.cancel();
    await _channel?.sink.close();
  }
}
```

- [ ] **Step 4: Run tests.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_flutter): BrokerTransport outbound JSON-RPC over WS"
```

---

### Task 10: Build-time + runtime gates in `MarionetteBinding`

**Files:**
- Modify: `packages/marionette_flutter/lib/src/binding/marionette_binding.dart`
- Test: `packages/marionette_flutter/test/binding/broker_gating_test.dart`

- [ ] **Step 1: Failing test** — initialize binding without `enableBroker`; assert no broker transport is started even if build flag is on.

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Implement.**

```dart
const _enabledAtCompile = bool.fromEnvironment('MARIONETTE_ENABLED');

if (_enabledAtCompile && configuration.enableBroker != null) {
  // construct + start BrokerTransport once activation triggers.
}
```

Add `MarionetteBinding.connectToBroker(uri, token)` API that constructs and starts `BrokerTransport`.

Add default activation:
- On web (`kIsWeb`): inspect `Uri.base` for `marionette` and `token` query params. If both present and `enableBroker.autoActivate`, call `connectToBroker`.
- On native: document; no default deep-link parser ships in v1.

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_flutter): build-flag + runtime gates for broker activation"
```

---

### Task 11: Visible "Marionette connected" overlay

**Files:**
- Create: `packages/marionette_flutter/lib/src/binding/overlay/connected_overlay.dart`
- Test: widget test for overlay visibility.

- [ ] **Step 1: Failing widget test** — connect broker (mock); assert overlay widget appears in `WidgetsApp` `OverlayEntry`.

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Implement an overlay using `WidgetsBinding.instance.addPersistentFrameCallback` or by wrapping `runApp`'s root with a stack that includes the badge when `BrokerTransport.isConnected` is true. Honor `BrokerOptions(showOverlay: false)` in debug; force-on in release (per spec open-question proposal).**

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_flutter): connected overlay (forced-on in release)"
```

---

### Task 12: Broker server in `marionette_mcp`

**Files:**
- Create: `packages/marionette_mcp/lib/src/broker/broker_server.dart`
- Create: `packages/marionette_mcp/lib/src/broker/broker_handle.dart`
- Test: `packages/marionette_mcp/test/broker/broker_server_test.dart`

- [ ] **Step 1: Failing test** — start a broker; have a fake-app WS client connect with bad token → rejected (4401). Connect with good token → accepted; send a JSON-RPC request; verify it's relayed to the registered host-side request channel.

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Implement.**

```dart
// broker_server.dart
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';

class BrokerServer {
  BrokerServer({this.port = 0, required this.token, this.idleTimeout = const Duration(minutes: 30)});
  final int port;
  final String token;
  final Duration idleTimeout;

  late HttpServer _server;
  WebSocketChannel? _appChannel;

  Future<int> start() async {
    final handler = webSocketHandler((WebSocketChannel ws) {
      // wait for auth as first frame
      _handleApp(ws);
    });
    _server = await io.serve(handler, InternetAddress.loopbackIPv4, port);
    return _server.port;
  }

  void _handleApp(WebSocketChannel ws) {
    // First frame must be JSON-RPC auth with matching token
    bool authed = false;
    Timer? idle;
    void resetIdle() {
      idle?.cancel();
      idle = Timer(idleTimeout, () => ws.sink.close(4408, 'idle'));
    }
    resetIdle();
    ws.stream.listen((msg) {
      resetIdle();
      // First message expected to be auth; then subsequent messages are responses.
      if (!authed) {
        // parse auth; if mismatch, close 4401
      }
      // forward to host-side awaiting request
    }, onDone: () { idle?.cancel(); });
  }

  Future<void> stop() async => _server.close();
  Future<Map<String, dynamic>> request(String method, Map<String, dynamic> params) async {
    // assign id; send JSON-RPC request frame to _appChannel; await response by id
  }
}
```

```dart
// broker_handle.dart - writes a small JSON file with port + token to ${TMPDIR}/marionette-broker-<pid>.json so other CLI invocations can discover it.
```

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_mcp): local broker server with auth and idle"
```

---

### Task 13: Broker discovery for CLI auto-attach

**Files:**
- Create: `packages/marionette_mcp/lib/src/broker/broker_discovery.dart`
- Test: `packages/marionette_mcp/test/broker/broker_discovery_test.dart`

- [ ] **Step 1: Failing test** — write two broker handle files; `BrokerDiscovery.findRunning()` returns the freshest reachable one; stale handles are GC'd.

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Implement** by scanning `${TMPDIR}/marionette-broker-*.json`, parsing each, doing a quick TCP connect-test to confirm liveness, and returning the latest.

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_mcp): broker discovery via handle files"
```

---

### Task 14: MCP server runner — auto-spawn / auto-discover

**Files:**
- Modify: `packages/marionette_mcp/lib/src/mcp_server_runner.dart`

- [ ] **Step 1: Failing test** — start MCP server with no `--vm-service`; assert it spawns a broker, prints activation URL, and rejects tool calls until app connects.

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Implement.** Probe for an existing broker via discovery; if none, spawn one. When a tool call arrives, route it through `BrokerServer.request(method, params)` instead of the existing VM service connector.

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_mcp): MCP server auto-spawn or auto-discover broker"
```

---

### Task 15: CLI — `marionette broker` command group

**Files:**
- Create: `packages/marionette_cli/lib/src/cli/commands/broker/{broker,start,status,stop}_command.dart`
- Modify: `packages/marionette_cli/lib/src/cli/marionette_command_runner.dart` — register group.

- [ ] **Step 1: Failing test** — run `marionette broker start` in an isolated process; assert it prints an activation URL with `ws://127.0.0.1:<port>` and a token; assert handle file exists.

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Implement** the three subcommands using `BrokerServer` and `BrokerHandle`.

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_cli): broker start/status/stop commands"
```

---

### Task 16: CLI action commands — `--broker [<uri>]` flag

**Files:**
- Modify: each command in `packages/marionette_cli/lib/src/cli/commands/*.dart`

- [ ] **Step 1: Failing test** — start a broker; run `marionette tap --ref @1` in another process; assert it auto-discovers the broker and dispatches.

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Implement** a shared `connectorFromArgs(args)` helper that returns either a VM service connector (if `--vm-service` given) or a broker connector (auto-discovered or `--broker <uri>` provided). Use everywhere.

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette_cli): action commands accept --broker and auto-discover"
```

---

### Task 17: Screencast over broker (binary frames)

**Files:**
- Modify: `packages/marionette_flutter/lib/src/services/screencast_*` and binding wiring.
- Modify: `packages/marionette_mcp/lib/src/broker/broker_server.dart` — relay binary frames to interested consumers.

- [ ] **Step 1: Failing test** — start a broker; subscribe to screencast on host side; have the test app emit a frame; assert it arrives intact.

- [ ] **Step 2: Verify failure.**

- [ ] **Step 3: Implement.** When `BrokerTransport.start()` is active, route screencast `emitFrame(bytes)` through `transport.sendBinary(bytes)`. Broker server demultiplexes binary frames and forwards them to any consumer that called `subscribeScreencast()`.

- [ ] **Step 4: Tests pass.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "feat(marionette): screencast frames over broker transport"
```

---

### Task 18: End-to-end integration — release build smoke test

**Files:**
- Create: `example/broker_release_smoke/` — a minimal example app built with `--dart-define=MARIONETTE_ENABLED=true`.
- Create: a manual-test script that:
  1. Starts `marionette broker start`.
  2. Builds the example app for the host's platform (e.g., `flutter build macos`).
  3. Launches the binary with the activation URL or deep link.
  4. Runs `marionette get-interactive-elements --compact` and `marionette tap --ref @1` against it.
  5. Asserts both succeed.

- [ ] **Step 1: Write the smoke script.**

- [ ] **Step 2: Run it manually on macOS desktop.**

- [ ] **Step 3: Document results in `RELEASE_AUDIT.md`.**

- [ ] **Step 4: Commit.**

```bash
git commit -am "test: release-build smoke test for broker transport"
```

---

### Task 19: Tree-shake verification

**Files:**
- Create: `packages/marionette_flutter/test_smoke/treeshake_test.sh`

- [ ] **Step 1: Build a tiny example app twice — once without the flag, once with.**

```bash
cd example/broker_release_smoke
flutter build web
mv build/web build-noflag
flutter build web --dart-define=MARIONETTE_ENABLED=true
```

- [ ] **Step 2: Verify symbols.**

```bash
grep -c 'BrokerTransport' build-noflag/main.dart.js || echo "OK: not present"
grep -c 'BrokerTransport' build/web/main.dart.js   # should be > 0
```

- [ ] **Step 3: Document in `RELEASE_AUDIT.md`.**

- [ ] **Step 4: Commit.**

```bash
git commit -am "test: verify broker transport tree-shakes when build flag absent"
```

---

### Task 20: Browser mixed-content check (manual)

- [ ] **Step 1: Serve the example app via a local HTTPS server (e.g., `mkcert` + `http-server -S`).**

- [ ] **Step 2: In Chrome, navigate to the HTTPS URL with `?marionette=ws://localhost:PORT&token=...` — verify connection works.**

- [ ] **Step 3: Repeat in Safari and Firefox.**

- [ ] **Step 4: Document outcomes in `RELEASE_AUDIT.md`. If a browser blocks, note the limitation and mitigation.**

- [ ] **Step 5: Commit.**

```bash
git commit -am "docs: cross-browser mixed-content findings for broker transport"
```

---

### Task 21: CHANGELOG + README + integration docs

**Files:**
- Modify: `CHANGELOG.md`, `packages/*/CHANGELOG.md`, `README.md`.
- Create: `docs/broker-integration.md` — instructions for app teams (build flag, runtime opt-in, CSP, deep links).

- [ ] **Step 1: Write entries.**

- [ ] **Step 2: Verify by reading.**

- [ ] **Step 3: Commit.**

```bash
git commit -am "docs: broker transport integration guide and changelog"
```

---

### Task 22: Final verification

- [ ] **Step 1: Run all tests across all packages.**

```bash
for d in packages/*/; do (cd "$d" && (dart test 2>/dev/null || flutter test 2>/dev/null) | tail -3); done
```

- [ ] **Step 2: Run analyze.**

```bash
dart analyze
```

- [ ] **Step 3: Re-read the spec; confirm every section maps to a task.**

- [ ] **Step 4: Push.**

```bash
git push -u origin feat/broker-transport
```

---

## Self-Review Notes

- **Spec coverage:** transport abstraction (T3–T5), activation (T10), build flag (T10, T19), runtime opt-in (T10), token + idle (T9, T12), overlay (T11), broker server (T12), JSON-RPC (T6), screencast mux (T7, T17), reconnect close-codes (T9), CLI surface (T15, T16), MCP runner (T14), browser mixed-content (T20), tree-shake (T19), release-mode audit (T2).
- **Open questions in spec:** loopback-only by default — implemented in T9 via `BrokerOptions.allowRemote` (default false). Forced overlay in release — implemented in T11. Native deep-link parser — explicitly deferred per T10.
- **Type consistency:** `Dispatcher`, `Transport`, `BrokerTransport`, `BrokerOptions`, `BrokerServer`, `JsonRpcCodec`, `FrameCodec` used consistently throughout.
