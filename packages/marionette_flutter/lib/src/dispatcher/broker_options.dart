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
