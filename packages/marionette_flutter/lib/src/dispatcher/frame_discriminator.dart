class Frame {
  Frame.jsonRpc(this.jsonRpcText)
      : binaryPayload = null,
        kind = FrameKind.jsonRpc;

  Frame.screencast(this.binaryPayload)
      : jsonRpcText = null,
        kind = FrameKind.screencast;

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
