import 'dart:convert';
import 'dart:typed_data';

class BackendMessChunk {
  final String dstNodeId;
  final String srcNodeId;
  final int msgId;
  final int partIndex;
  final int partCount;
  final int totalLen;
  final int crc32;
  final Uint8List payload;

  const BackendMessChunk({
    required this.dstNodeId,
    required this.srcNodeId,
    required this.msgId,
    required this.partIndex,
    required this.partCount,
    required this.totalLen,
    required this.crc32,
    required this.payload,
  });

  Map<String, dynamic> toJson() {
    return {
      'dstNodeId': dstNodeId,
      'srcNodeId': srcNodeId,
      'msgId': msgId,
      'partIndex': partIndex,
      'partCount': partCount,
      'totalLen': totalLen,
      'crc32': crc32,
      'payloadB64': base64Encode(payload),
    };
  }

  @override
  String toString() {
    return 'BackendMessChunk(dstNodeId=$dstNodeId, srcNodeId=$srcNodeId, '
        'msgId=$msgId, part=${partIndex + 1}/$partCount, '
        'totalLen=$totalLen, crc32=$crc32, payloadLen=${payload.length})';
  }

  Uint8List toBytes() {
    final builder = BytesBuilder(copy: false);

    void putU16(int v) {
      builder.add(Uint8List.fromList([v & 0xFF, (v >> 8) & 0xFF]));
    }

    // chunk format:
    // [partIndex:u16][payloadLen:u16][payload...]
    putU16(partIndex);
    putU16(payload.length);
    builder.add(payload);

    return builder.toBytes();
  }
}

class BackendMessPacket {
  final String dstNodeId;
  final String srcNodeId;
  final int msgId;
  final int totalLen;
  final int crc32;
  final String deliveryMode;
  final int burstCount;
  final int ackWindowMs;
  final List<BackendMessChunk> chunks;

  const BackendMessPacket({
    required this.dstNodeId,
    required this.srcNodeId,
    required this.msgId,
    required this.totalLen,
    required this.crc32,
    required this.deliveryMode,
    required this.burstCount,
    required this.ackWindowMs,
    required this.chunks,
  });

  Map<String, dynamic> toJson() {
    return {
      'dstNodeId': dstNodeId,
      'srcNodeId': srcNodeId,
      'msgId': msgId,
      'totalLen': totalLen,
      'crc32': crc32,
      'deliveryMode': deliveryMode,
      'burstCount': burstCount,
      'ackWindowMs': ackWindowMs,
      'partCount': chunks.length,
      'chunks': chunks.map((c) => c.toJson()).toList(),
    };
  }

  Uint8List toBytes() {
    final builder = BytesBuilder(copy: false);

    void putU8(int v) {
      builder.addByte(v & 0xFF);
    }

    void putU16(int v) {
      builder.add(Uint8List.fromList([v & 0xFF, (v >> 8) & 0xFF]));
    }

    void putU32(int v) {
      builder.add(
        Uint8List.fromList([
          v & 0xFF,
          (v >> 8) & 0xFF,
          (v >> 16) & 0xFF,
          (v >> 24) & 0xFF,
        ]),
      );
    }

    void putStr(String s) {
      final bytes = Uint8List.fromList(utf8.encode(s));
      if (bytes.length > 255) {
        throw ArgumentError.value(s, 'string', 'must be <= 255 bytes in UTF-8');
      }
      putU8(bytes.length);
      builder.add(bytes);
    }

    // Binary protocol:
    // magic[3] = 'B','M','1'
    // version:u8 = 1
    // srcNodeId:str
    // dstNodeId:str
    // msgId:u32
    // totalLen:u32
    // crc32:u32
    // partCount:u16
    // burstCount:u8
    // ackWindowMs:u16
    // repeated chunks:
    //   partIndex:u16
    //   payloadLen:u16
    //   payload bytes
    builder.add([0x42, 0x4D, 0x31, 0x01]);
    putStr(srcNodeId);
    putStr(dstNodeId);
    putU32(msgId);
    putU32(totalLen);
    putU32(crc32);
    putU16(chunks.length);
    putU8(burstCount);
    putU16(ackWindowMs);

    for (final chunk in chunks) {
      builder.add(chunk.toBytes());
    }

    return builder.toBytes();
  }
}

class BackendMessBuilder {
  static const int defaultChunkSize = 8;
  static const int defaultBurstCount = 10;
  static const int defaultAckWindowMs = 5000;
  static const String defaultDeliveryMode = 'burst_window';

  // Стартуем не с 1, чтобы после перезапуска приложения не плодить совпадения
  // с уже сохранёнными сообщениями.
  int _msgCounter = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;

  int nextMsgId() {
    _msgCounter = (_msgCounter + 1) & 0x7fffffff;
    if (_msgCounter == 0) {
      _msgCounter = 1;
    }
    return _msgCounter;
  }

  Uint8List encodeUtf8(String text) {
    return Uint8List.fromList(utf8.encode(text));
  }

  String decodeUtf8(Uint8List bytes) {
    return utf8.decode(bytes);
  }

  List<String> _splitTextByChars(String text, int chunkSize) {
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'must be > 0');
    }

    final runes = text.runes.toList();
    if (runes.isEmpty) {
      return <String>[''];
    }

    final parts = <String>[];

    for (int i = 0; i < runes.length; i += chunkSize) {
      final end = (i + chunkSize < runes.length) ? i + chunkSize : runes.length;
      parts.add(String.fromCharCodes(runes.sublist(i, end)));
    }

    return parts;
  }

  int crc32(Uint8List data) {
    const int polynomial = 0xEDB88320;
    int crc = 0xFFFFFFFF;

    for (final byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        final mask = -(crc & 1);
        crc = (crc >> 1) ^ (polynomial & mask);
      }
    }

    return (~crc) & 0xFFFFFFFF;
  }

  BackendMessPacket buildPacket({
    required String srcNodeId,
    required String dstNodeId,
    required String text,
    int? msgId,
    int chunkSize = defaultChunkSize,
    String deliveryMode = defaultDeliveryMode,
    int burstCount = defaultBurstCount,
    int ackWindowMs = defaultAckWindowMs,
  }) {
    final resolvedMsgId = msgId ?? nextMsgId();

    // Полный текст сначала кодируем в байты для CRC и totalLen,
    // но сами части режем по символам.
    final fullBytes = encodeUtf8(text);
    final totalLen = fullBytes.length;
    final crc = crc32(fullBytes);

    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'must be > 0');
    }

    final parts = _splitTextByChars(text, chunkSize);
    final partCount = parts.length;

    final chunks = <BackendMessChunk>[];
    for (int partIndex = 0; partIndex < partCount; partIndex++) {
      final partText = parts[partIndex];
      final payload = Uint8List.fromList(utf8.encode(partText));

      chunks.add(
        BackendMessChunk(
          dstNodeId: dstNodeId,
          srcNodeId: srcNodeId,
          msgId: resolvedMsgId,
          partIndex: partIndex,
          partCount: partCount,
          totalLen: totalLen,
          crc32: crc,
          payload: payload,
        ),
      );
    }

    return BackendMessPacket(
      dstNodeId: dstNodeId,
      srcNodeId: srcNodeId,
      msgId: resolvedMsgId,
      totalLen: totalLen,
      crc32: crc,
      deliveryMode: deliveryMode,
      burstCount: burstCount,
      ackWindowMs: ackWindowMs,
      chunks: chunks,
    );
  }

  List<BackendMessChunk> splitText({
    required String srcNodeId,
    required String dstNodeId,
    required String text,
    int? msgId,
    int chunkSize = defaultChunkSize,
    String deliveryMode = defaultDeliveryMode,
    int burstCount = defaultBurstCount,
    int ackWindowMs = defaultAckWindowMs,
  }) {
    return buildPacket(
      srcNodeId: srcNodeId,
      dstNodeId: dstNodeId,
      text: text,
      msgId: msgId,
      chunkSize: chunkSize,
      deliveryMode: deliveryMode,
      burstCount: burstCount,
      ackWindowMs: ackWindowMs,
    ).chunks;
  }
}
