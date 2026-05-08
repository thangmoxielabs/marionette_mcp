# Broker Transport — Design

**Date:** 2026-05-08
**Status:** Draft, awaiting review
**Branch:** `feat/broker-transport`

## Summary

Add a new transport that lets marionette drive Flutter apps without a Dart VM service: `marionette_flutter` opens an outbound WebSocket to a broker run locally by the CLI/MCP. The broker speaks JSON-RPC 2.0; binary screencast frames share the same socket via a one-byte type discriminator. The transport is opt-in at compile time, opt-in at runtime, token-authenticated, and idle-timed. This unblocks driving public production builds — web (deployed sites), desktop release, and mobile release — that have intentionally compiled marionette into the bundle.

## Motivation

`marionette_flutter` today registers handlers via `dart:developer.registerExtension`, accessible only via the Dart VM service. The VM service is available in debug and profile builds with the VM running; it is **not** available in:

- Production web builds (compiled to JS, no Dart VM).
- Release builds on any platform when `--enable-vm-service` is not used.

Flutter teams that want their AI agent to drive a deployed staging site or a stock release build cannot today, even though widget-tree introspection and gesture dispatch work fine in those builds (they use only public Flutter APIs). The blocker is purely the transport.

We add a second transport — an outbound-from-app WebSocket to a local broker — that works in every build mode where the app's process is alive. The dispatcher and handlers (snapshot, tap, enter_text, screenshot, screencast, logs, etc.) are unchanged; only the ingress is new.

## Goals

- Drive Flutter apps in production-grade builds (web release, desktop release, mobile release) on any platform where Dart can open an outbound WebSocket.
- Unify desktop / mobile / web behind one transport mechanism.
- Compile-time tree-shaking: zero marionette code in builds that don't opt in.
- Defense-in-depth security: opt-in flag + opt-in API + per-session token + idle timeout + visible overlay.
- Reuse existing handlers (`tap`, `enter_text`, `interactiveElements`, `screenshot`, etc.) verbatim — broker is just another way to reach them.
- CLI usability: a long-lived `marionette broker` process holds the session so chained CLI calls stay cheap.

## Non-Goals

- Driving arbitrary deployed Flutter web apps that did not opt in (impossible without app cooperation).
- Replacing the VM service transport (it stays the default for debug builds).
- Multiplexing multiple app sessions per broker (deferred to v2; v1 is one app per broker invocation).
- Discovering brokers via mDNS / Bonjour.
- A persistent daemon or per-machine broker.

## Design

### Transport abstraction (in `marionette_flutter`)

A new `Dispatcher` owns the handler map. Today's `registerInternalMarionetteExtension` becomes a thin shim that registers the handler with the dispatcher and binds it to the VM service transport. New code:

```dart
abstract class Transport {
  Future<void> start();
  Future<void> stop();
}

class Dispatcher {
  void register(String method, Future<Map<String, dynamic>> Function(Map params) handler);
  Future<Map<String, dynamic>> dispatch(String method, Map params);
}

class VmServiceTransport implements Transport { ... }
class BrokerTransport implements Transport { ... }
```

At binding init:

- `VmServiceTransport` is created if `kDebugMode` (today's behavior).
- `BrokerTransport` is created iff:
  - `MARIONETTE_ENABLED=true` was passed via `--dart-define` (compile-time gate), AND
  - `MarionetteBinding.instance.enableBroker(...)` was called at runtime, AND
  - an activation signal arrived (URL query param, deep link, or `connectToBroker(uri, token)` call).

Both transports decode their input shape and call `dispatcher.dispatch(method, params)`. The handler return shape is the same JSON regardless of how it was reached.

### Activation (Q1=C)

Two activation paths, layered:

1. **Default — query param / deep link.** When `enableBroker()` is called, marionette installs a default activation listener that reads `Uri.base` (web) or the launch deep link (native, via the `app_links`/platform-channel route) and looks for `?marionette=ws://...&token=...`. If present, marionette calls `connectToBroker(uri, token)` automatically.
2. **Programmatic.** App developer can call `MarionetteBinding.instance.connectToBroker(uri, token)` directly — from a hidden dev menu, a launch arg parser, an env var, etc.

The default activation can be disabled via `enableBroker(autoActivate: false)`.

### Build-time gate

```bash
flutter build web --dart-define=MARIONETTE_ENABLED=true
```

Without `MARIONETTE_ENABLED=true`, the entire `BrokerTransport` and supporting code are stripped:

```dart
const _enabled = bool.fromEnvironment('MARIONETTE_ENABLED');

if (_enabled) {
  // BrokerTransport import and instantiation guarded here.
}
```

The `if (_enabled)` constant-folds at compile time; the tree-shaker removes the unused branch and any code reachable only from it. No marionette network code ships in default release builds.

### Runtime gate

Even with the build flag set, the broker is dormant until the app calls:

```dart
MarionetteBinding.ensureInitialized(
  MarionetteConfiguration(
    enableBroker: BrokerOptions(
      idleTimeout: const Duration(minutes: 30),
      autoReconnect: true,
      autoActivate: true,
      showOverlay: true,
    ),
  ),
);
```

`enableBroker` is opt-in. Apps that compile with the flag but forget to enable it at runtime are still safe.

### Per-session token (Q5=D)

The broker generates a fresh UUID on startup. The activation URL includes this token. The app sends the token in the WS handshake (sub-protocol or first JSON-RPC frame `auth`). The broker rejects connections whose token does not match.

Tokens are one-shot in spirit: when the broker exits, the token dies with it.

### Idle timeout

The broker tracks last-message time per connection. After `idleTimeout` (default 30 min) of no traffic, the broker closes the WS with custom close code `4408`. The app receives this and does **not** reconnect (it's a final close). Re-activation requires the user to open a fresh activation URL.

### Visible overlay

While connected, marionette injects a small overlay widget (top-right corner, dismissable) reading "Marionette connected". Implemented as a `WidgetsBinding`-injected overlay, no app cooperation required. Opt-out via `BrokerOptions(showOverlay: false)`.

### Broker topology (Q3=C)

Each `marionette mcp` or `marionette broker start` invocation spins up a fresh broker:

- OS-assigned free port (or `--port N` override).
- Fresh UUID token.
- One app connection per broker (v1).
- Broker dies when its parent process exits.

No persistent daemon. Each invocation is self-contained.

### Wire protocol (Q4=A)

Single WebSocket carries two frame types, distinguished by a one-byte type discriminator at offset 0:

| Byte | Type | Payload |
|------|------|---------|
| `0x01` | JSON-RPC text | UTF-8 JSON-RPC 2.0 message (request / response / notification) |
| `0x02` | Screencast frame | Binary image bytes (existing screencast frame format) |
| `0x03..0xFF` | Reserved | — |

Text frames use the WS text opcode; binary frames use the WS binary opcode. The discriminator byte sits at offset 0 of the frame payload. (We use the discriminator on both opcodes for forward-compat — a future text-mode screencast or binary RPC.)

#### JSON-RPC 2.0

Standard shape:

```json
// Broker → app (request)
{ "jsonrpc": "2.0", "id": 17, "method": "tap", "params": { "ref": "@5" } }

// App → broker (response)
{ "jsonrpc": "2.0", "id": 17, "result": { ... } }

// App → broker (notification, e.g. log message)
{ "jsonrpc": "2.0", "method": "logs/event", "params": { ... } }
```

Methods correspond 1:1 with current VM service extensions (e.g. `marionette.interactiveElements` becomes method `interactiveElements`; the `marionette.` prefix is dropped on the wire).

#### Screencast frames

The existing `screencast_web_server` produces frames over a separate WS today. Under the broker, frames are sent on the same socket with `0x02` discriminator. The broker forwards them to whichever local consumer (CLI screencast viewer, MCP screencast tool) requested the stream. Backpressure handled via a bounded queue per consumer; oldest frame dropped when the queue fills.

### Connection lifecycle (Q6=C-with-twist)

App-side reconnect logic on WS close:

| Close code | Reconnect? | Why |
|------------|-----------|-----|
| 1000 (normal) | No | Server intentionally closed |
| 1001 (going away) | Yes | Browser tab change / network blip |
| 1006 (abnormal) | Yes | Network blip |
| 4408 (idle timeout) | No | Final by design |
| 4401 (auth rejected) | No | Token bad; reconnect would just fail again |
| 4xxx (other custom) | No | Server-defined finals |
| Other | Yes | Conservative default |

Reconnect uses exponential backoff (1s, 2s, 4s, 8s, capped at 16s) for **at most 30 seconds total**, then gives up. Auto-reconnect can be disabled per-app via `BrokerOptions(autoReconnect: false)`.

### CLI surface (Q7=C)

New top-level command group:

```
marionette broker start [--port N] [--idle-timeout 30m] [--no-overlay]
marionette broker status
marionette broker stop
```

`marionette broker start` runs in the foreground:

```
$ marionette broker start
Marionette broker listening on ws://127.0.0.1:54839
Activation URL: https://your-app.example.com/?marionette=ws://127.0.0.1:54839&token=8f3a-...

(or for native deep links: myapp://?marionette=ws://127.0.0.1:54839&token=8f3a-...)

Waiting for app to connect... [press Ctrl-C to exit]
```

Action commands learn a `--broker` selector — when omitted, the CLI auto-discovers a running broker via a local handle file (e.g. `~/.marionette/broker.sock` or a port file in `$TMPDIR`). When present, an explicit `--broker ws://127.0.0.1:54839` overrides:

```
$ marionette broker start &
$ # In another shell, after the app connects:
$ marionette get-interactive-elements --compact --prune
$ marionette tap --ref @5
```

Existing `--vm-service` flag is retained — VM service and broker are sibling transports.

### MCP server surface

`marionette mcp` (the MCP server) at startup either:

1. **Auto-discovers a running broker** via the local handle file. If found, attaches to it and uses that for the session.
2. **Spawns its own broker** if none found. Prints the activation URL via the MCP host's UI mechanism (e.g. an MCP `notification` to the agent, or stderr-with-display).
3. **Speaks VM service** (today's flow) when given a `--vm-service ws://...` URI.

The MCP tool surface is unchanged — agents call `tap`, `interactiveElements`, etc. exactly as today; the transport choice is hidden.

### CSP and mixed-content notes (for app integrators)

Apps shipping with `MARIONETTE_ENABLED=true` and serving over HTTPS need their CSP to allow the broker:

```
Content-Security-Policy: connect-src 'self' ws://localhost:* ws://127.0.0.1:*;
```

Mixed content: HTTPS pages → `ws://localhost` is allowed by Chrome, Edge per the Secure Contexts spec carve-out for localhost. **Safari and Firefox to be verified during implementation.** If a browser blocks the connection, fallback is `wss://` with a locally-trusted certificate (deferred — out of scope for v1; doc the limitation).

### Release-mode capability audit (implementation prerequisite)

Before merging this spec's implementation, audit which marionette internals depend on inspector APIs that are stripped from release. Suspected safe:

- `WidgetsBinding.instance.rootElement` — public, available in release.
- `Element.visitChildren` — public, available in release.
- `RenderBox.localToGlobal`, `RenderBox.size` — public, available in release.
- `GestureBinding.instance.handlePointerEvent` (used by gesture dispatcher) — public, available in release.

Suspected at-risk:

- `WidgetInspectorService` — stripped from release. Audit any handler that touches `WidgetInspectorService`. If any do, route through alternative public APIs or document as "debug-only via VM service transport, not available via broker."

This audit must happen in the first PR of the implementation plan and may surface follow-up work to make specific handlers release-safe.

## Architecture diagram

```
                ┌───────────────────────────────────┐
                │      marionette_flutter (in app)  │
                │                                   │
                │  ┌─────────────────────────────┐  │
                │  │       Dispatcher            │  │
                │  │  tap, interactiveElements,  │  │
                │  │  screenshot, logs, ...      │  │
                │  └────────┬─────────────┬──────┘  │
                │           │             │         │
                │  ┌────────▼─────┐  ┌────▼──────┐ │
                │  │ VmServiceXp  │  │ BrokerXp  │ │
                │  └──────┬───────┘  └─────┬─────┘ │
                └─────────┼───────────────┼────────┘
                          │ (debug only)  │ outbound WS
                          ▼               ▼
                ┌──────────────┐    ┌──────────────────┐
                │  Dart VM     │    │  marionette      │
                │  Service     │    │  broker (local)  │
                └──────┬───────┘    └────────┬─────────┘
                       │                     │
                       ▼                     ▼
              ┌──────────────────────────────────────┐
              │  marionette CLI / MCP                │
              └──────────────────────────────────────┘
```

## Files (rough plan)

**`marionette_flutter`:**

- `lib/src/dispatcher/dispatcher.dart` (new) — handler registry.
- `lib/src/dispatcher/transport.dart` (new) — `Transport` interface.
- `lib/src/dispatcher/vm_service_transport.dart` (new) — wraps existing `registerExtension` calls.
- `lib/src/dispatcher/broker_transport.dart` (new) — outbound WS client; JSON-RPC 2.0 codec; reconnect logic.
- `lib/src/binding/marionette_binding.dart` — wire dispatcher + transport selection at boot; `connectToBroker` API.
- `lib/src/binding/marionette_configuration.dart` — add `BrokerOptions`.
- `lib/src/binding/extensions/*.dart` — refactor each `registerInternalMarionetteExtension(...)` call to register against the dispatcher (mechanical).
- `lib/src/services/screencast_*` — adapt to emit binary frames through whichever transport is active.
- `lib/src/binding/overlay/connected_overlay.dart` (new) — visible "Marionette connected" overlay.

**`marionette_mcp`:**

- `lib/src/broker/broker_server.dart` (new) — local WS server, JSON-RPC 2.0 dispatch, token enforcement, idle timeout, screencast frame relay.
- `lib/src/mcp_server_runner.dart` — broker auto-spawn / auto-discover.

**`marionette_cli`:**

- `lib/src/cli/commands/broker/*` (new) — `start`, `status`, `stop` subcommands.
- `lib/src/cli/commands/<action>_command.dart` — `--broker [<uri>]` flag plumbed through.

## Testing

### Unit tests

- `dispatcher_test.dart` — register, dispatch, error propagation.
- `broker_transport_test.dart` — JSON-RPC encode/decode; reconnect close-code logic; idle timeout client-side; auth handshake.
- `broker_server_test.dart` — token rejection; idle close; concurrent request handling; binary frame routing.
- `screencast_framing_test.dart` — discriminator byte; demultiplex.

### Integration tests

- `broker_handshake_test.dart` — app boots with build flag, calls `enableBroker`, broker starts with token, app connects via activation URL, RPC roundtrip succeeds.
- `broker_release_mode_test.dart` — run a release-mode test app under broker; verify `interactiveElements`, `tap`, `screenshot` work without VM service.
- `broker_idle_timeout_test.dart` — connection auto-closes after configured idle; app does not reconnect.
- `broker_reconnect_test.dart` — kill the broker mid-session, restart it, verify the app reconnects automatically (transient close codes only) and does not (token-rejected close codes).
- `broker_overlay_test.dart` — overlay appears when connected, disappears on close.
- `broker_tree_shake_test.dart` — build without `MARIONETTE_ENABLED=true`; binary should not contain broker-transport symbols (size or symbol-table assertion).

### Manual verification checklist

- HTTPS staging site + `ws://localhost` broker, drive from Chrome (web release).
- Same on Safari and Firefox — document any browser-specific blockers.
- Desktop release build (macOS/Windows/Linux) drives over broker.
- Mobile release build (iOS / Android) drives over broker via Wi-Fi.
- App Store / Play Store binary built without flag — verify no marionette code in symbols.

## Backward Compatibility

- VM service transport is unchanged. Debug-mode users see no behavior change.
- All existing MCP tools and CLI commands work over both transports without callsite changes.
- The dispatcher refactor is internal to `marionette_flutter`; no public API removed. New public APIs (`enableBroker`, `connectToBroker`, `BrokerOptions`) are additive.

## Risks

1. **Browser mixed-content (Safari/Firefox).** HTTPS → `ws://localhost` may be blocked. Mitigation: verify behavior during implementation; document Chrome as the supported browser for v1; consider `wss://` with locally-trusted cert in v2.
2. **CSP misconfiguration.** App teams must allow `connect-src ws://localhost:*`. Mitigation: clear docs + integration test recipe.
3. **Release-mode inspector API gaps.** Some handler might depend on `WidgetInspectorService`. Mitigation: audit in first implementation PR; route around or document gaps.
4. **Token leakage via URL bar.** Activation URL contains the token; visible in browser history. Mitigation: tokens are ephemeral (broker-process-lifetime), one-shot, and have no value once the broker exits. Document the threat model: the token is a session capability, not a long-lived secret.
5. **Surface area for malicious activation.** A user could be tricked into clicking a malicious activation URL pointing at an attacker-controlled broker. Mitigation: visible overlay during connection; idle timeout limits exposure window; document threat model; consider requiring the host portion of the broker URL to be `localhost`/`127.0.0.1` by default (configurable to opt out for remote-driving use cases).

## Open Questions

- Should the broker URL host be restricted to loopback by default, with an explicit `BrokerOptions(allowRemote: true)` for cross-machine driving (e.g. driving a phone from a dev laptop)? Proposal: yes, loopback-only by default. Cross-machine is a v2 feature with extra security thinking required.
- Should the visible overlay be required (no opt-out) for release builds, regardless of `BrokerOptions(showOverlay: false)`? Proposal: yes — the opt-out only applies in debug. Production-shipped marionette must show the overlay when connected.
- Activation deep-link parsing on native: do we ship a default parser for `app_links`-style deep links, or is it always the developer's responsibility? Proposal: web-only default parser in v1; native deep-link integration documented as "call `connectToBroker(uri, token)` from your existing deep-link handler."

## Out of Scope (deferred)

- Multiplexing multiple apps per broker.
- Persistent broker daemon / cross-invocation broker.
- mDNS broker discovery.
- `wss://` with locally-trusted certs.
- Cross-machine driving (e.g. driving phone from laptop over LAN).
- App-declared semantic tools (formerly Spec 2; deferred indefinitely).
