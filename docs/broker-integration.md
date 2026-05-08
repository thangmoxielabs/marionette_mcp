# Broker Transport Integration Guide

## Overview

The broker transport enables marionette to drive Flutter apps in **production-grade builds** (web, desktop, mobile release) that compile marionette in. Instead of relying on the VM service (debug-only), the app connects outbound to a local WebSocket broker server.

## Quick Start

### 1. Add marionette_flutter to your app

```yaml
dependencies:
  marionette_flutter: ^0.5.0
```

### 2. Initialize with broker enabled

```dart
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  MarionetteBinding.ensureInitialized(
    MarionetteConfiguration(
      enableBroker: const BrokerOptions(),
    ),
  );
  runApp(MyApp());
}
```

### 3. Build with the flag

```bash
flutter build web --dart-define=MARIONETTE_ENABLED=true
flutter build macos --dart-define=MARIONETTE_ENABLED=true
```

### 4. Start the broker and connect

```bash
# Start broker server
marionette broker start
# Output: Broker started on port 12345
#         Activation URL: ws://127.0.0.1:12345?token=abc123...

# Launch your app with the activation URL
# For web: open http://localhost:8080/?marionette=ws://127.0.0.1:12345&token=abc123...

# Use marionette CLI with broker
marionette --broker ws://127.0.0.1:12345?token=abc123... get-interactive-elements
# Or auto-discover
marionette --broker get-interactive-elements
```

## Configuration

### BrokerOptions

| Option | Default | Description |
|--------|---------|-------------|
| `idleTimeout` | 30 minutes | Close connection after inactivity |
| `autoReconnect` | true | Reconnect on transient failures |
| `autoActivate` | true | Auto-connect from URL params on web |
| `showOverlay` | true | Show "Marionette connected" badge |
| `allowRemote` | false | Allow non-loopback connections |

### Build Flag

The `MARIONETTE_ENABLED` dart-define controls whether broker transport code is included in the build. When absent, all broker code tree-shakes away.

```bash
# Include broker transport
flutter build web --dart-define=MARIONETTE_ENABLED=true

# Exclude broker transport (default)
flutter build web
```

## Web Activation

On web, the app auto-activates broker mode when the URL contains `marionette` and `token` query parameters:

```
https://myapp.com/?marionette=ws://127.0.0.1:12345&token=abc123...
```

### CSP Requirements

For web apps with Content Security Policy, ensure `connect-src` allows the broker WebSocket:

```html
<meta http-equiv="Content-Security-Policy"
      content="connect-src 'self' ws://127.0.0.1:*;">
```

## CLI Commands

### Broker Management

```bash
marionette broker start     # Start broker server
marionette broker status    # Show running brokers
marionette broker stop      # Stop most recent broker
```

### Action Commands with Broker

```bash
# Auto-discover broker
marionette --broker get-interactive-elements
marionette --broker tap --key submit_button

# Explicit broker URI
marionette --broker ws://127.0.0.1:12345?token=abc123... tap --key submit_button
```

## Architecture

```
┌─────────────┐     WebSocket (JSON-RPC + binary)     ┌──────────────┐
│ Flutter App │ ──────────────────────────────────────► │ Broker Server│
│             │  0x01: JSON-RPC frames                  │ (marionette  │
│ BrokerTrans │  0x02: Screencast frames               │  CLI/MCP)    │
└──────┬──────┘                                       └──────┬───────┘
       │                                                     │
       ▼                                                     ▼
┌─────────────┐                                       ┌──────────────┐
│ Dispatcher  │                                       │ MCP Tools    │
│ + Handlers  │                                       │ (tap, scroll,│
└─────────────┘                                       │  etc.)       │
                                                      └──────────────┘
```

## Troubleshooting

### "No broker found"
Run `marionette broker start` first.

### Connection refused
Ensure the broker is running: `marionette broker status`

### Token mismatch
The token in the activation URL must match the broker's token.

### Mixed content blocked (web)
Browsers block `ws://` from `https://` pages. Use a local HTTPS dev server or serve the app over HTTP for testing.
