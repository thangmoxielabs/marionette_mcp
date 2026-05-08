import 'dart:convert';

class JsonRpcMessage {
  JsonRpcMessage({
    this.id,
    required this.method,
    this.params,
  });
  final int? id;
  final String method;
  final Map<String, dynamic>? params;
}

class JsonRpcCodec {
  static String encodeRequest({
    required int id,
    required String method,
    Map<String, dynamic>? params,
  }) =>
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        if (params != null) 'params': params,
      });

  static String encodeResult({
    required int id,
    required Map<String, dynamic> result,
  }) =>
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'result': result,
      });

  static String encodeError({
    required int id,
    required int code,
    required String message,
  }) =>
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      });

  static JsonRpcMessage decode(String s) {
    final m = jsonDecode(s) as Map<String, dynamic>;
    return JsonRpcMessage(
      id: m['id'] as int?,
      method: (m['method'] as String?) ?? '',
      params: m['params'] as Map<String, dynamic>?,
    );
  }
}
