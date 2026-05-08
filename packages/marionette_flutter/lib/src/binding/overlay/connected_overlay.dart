import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A persistent overlay that shows "Marionette connected" when the broker
/// transport is active.
///
/// In debug mode, [showOverlay] can be set to false to hide the badge.
/// In release mode, the overlay is always shown when connected (security
/// requirement: users must know their app is being driven).
class ConnectedOverlay extends StatelessWidget {
  const ConnectedOverlay({
    super.key,
    required this.connected,
    this.showOverlay = true,
  });

  final bool connected;
  final bool showOverlay;

  bool get _shouldShow {
    if (!connected) return false;
    if (kReleaseMode) return true;
    return showOverlay;
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldShow) return const SizedBox.shrink();

    return Positioned(
      top: 0,
      right: 0,
      child: Material(
        color: Colors.green,
        elevation: 4,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            'Marionette connected',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps an app's root widget with a [Stack] that includes the
/// [ConnectedOverlay] when a broker is active.
///
/// Usage:
/// ```dart
/// runApp(
///   MarionetteOverlayWrapper(
///     isConnected: brokerTransport.isConnected,
///     showOverlay: configuration.enableBroker?.showOverlay ?? true,
///     child: MyApp(),
///   ),
/// );
/// ```
class MarionetteOverlayWrapper extends StatefulWidget {
  const MarionetteOverlayWrapper({
    super.key,
    required this.isConnected,
    this.showOverlay = true,
    required this.child,
  });

  final bool isConnected;
  final bool showOverlay;
  final Widget child;

  @override
  State<MarionetteOverlayWrapper> createState() =>
      _MarionetteOverlayWrapperState();
}

class _MarionetteOverlayWrapperState extends State<MarionetteOverlayWrapper> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        ConnectedOverlay(
          connected: widget.isConnected,
          showOverlay: widget.showOverlay,
        ),
      ],
    );
  }

  @override
  void didUpdateWidget(MarionetteOverlayWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isConnected != oldWidget.isConnected ||
        widget.showOverlay != oldWidget.showOverlay) {
      setState(() {});
    }
  }
}
