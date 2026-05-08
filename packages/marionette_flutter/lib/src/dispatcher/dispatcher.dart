typedef DispatchHandler = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> params,
);

class DispatcherError implements Exception {
  DispatcherError(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'DispatcherError($code): $message';
}

class Dispatcher {
  final Map<String, DispatchHandler> _handlers = {};

  void register(String method, DispatchHandler handler) {
    if (_handlers.containsKey(method)) {
      throw StateError('Method already registered: $method');
    }
    _handlers[method] = handler;
  }

  Future<Map<String, dynamic>> dispatch(
    String method,
    Map<String, dynamic> params,
  ) async {
    final h = _handlers[method];
    if (h == null) {
      throw DispatcherError('method_not_found', 'No handler for $method');
    }
    return h(params);
  }

  Iterable<String> get registeredMethods => _handlers.keys;
}
