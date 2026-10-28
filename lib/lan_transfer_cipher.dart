import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Bounded binary frames, authenticated in order and terminated explicitly.
/// One worker owns a transfer's crypto; large books never become one Uint8List
/// or base64 string on the UI isolate, and there is no per-chunk isolate spawn.
class LanTransferCipher {
  LanTransferCipher._(
    this._isolate,
    this._port,
    this._messages,
    this._commands,
  );
  static const chunkBytes = 256 * 1024;
  final Isolate _isolate;
  final ReceivePort _port;
  final StreamIterator<dynamic> _messages;
  final SendPort _commands;
  bool _closed = false;

  static Future<LanTransferCipher> start(String key) async {
    final port = ReceivePort();
    final messages = StreamIterator<dynamic>(port);
    final isolate = await Isolate.spawn(_transferWorker, (port.sendPort, key));
    try {
      if (!await messages.moveNext().timeout(const Duration(seconds: 8)) ||
          messages.current is! SendPort) {
        throw const FormatException('未能准备书籍传输');
      }
      return LanTransferCipher._(isolate, port, messages, messages.current);
    } catch (_) {
      isolate.kill(priority: Isolate.immediate);
      await messages.cancel();
      port.close();
      rethrow;
    }
  }

  Future<Uint8List> _run(bool seal, Uint8List bytes, String aad) async {
    if (_closed) throw const FormatException('书籍传输已取消');
    _commands.send((seal, TransferableTypedData.fromList([bytes]), aad));
    if (!await _messages.moveNext().timeout(const Duration(seconds: 8)) ||
        _messages.current is! TransferableTypedData) {
      throw const FormatException('书籍传输校验失败，请重试');
    }
    return (_messages.current as TransferableTypedData)
        .materialize()
        .asUint8List();
  }

  Stream<List<int>> seal(
    Stream<List<int>> source, {
    required String session,
    required int length,
    void Function(int bytes)? onProgress,
  }) async* {
    final buffer = BytesBuilder(copy: false);
    var total = 0, index = 0;
    Future<Uint8List> frame(Uint8List bytes) async {
      final packet = await _run(
        true,
        bytes,
        'wenku-lan-file-v1:$session:${index++}',
      );
      final out = Uint8List(packet.length + 4);
      ByteData.sublistView(out).setUint32(0, packet.length);
      out.setRange(4, out.length, packet);
      return out;
    }

    await for (final bytes in source) {
      if (_closed) throw const FormatException('书籍传输已取消');
      var offset = 0;
      while (offset < bytes.length) {
        final take = (chunkBytes - buffer.length).clamp(
          0,
          bytes.length - offset,
        );
        buffer.add(
          bytes is Uint8List
              ? Uint8List.sublistView(bytes, offset, offset + take)
              : Uint8List.fromList(bytes.sublist(offset, offset + take)),
        );
        offset += take;
        if (buffer.length == chunkBytes) {
          total += buffer.length;
          if (total > length) throw const FormatException('本机书籍在传输期间发生变化，请重试');
          yield await frame(buffer.takeBytes());
          onProgress?.call(total);
        }
      }
    }
    if (buffer.isNotEmpty) {
      total += buffer.length;
      yield await frame(buffer.takeBytes());
      onProgress?.call(total);
    }
    if (total != length) throw const FormatException('本机书籍在传输期间发生变化，请重试');
    yield await frame(Uint8List(0));
  }

  Stream<Uint8List> open(
    Stream<List<int>> source, {
    required String session,
    required int length,
    void Function(int bytes)? onProgress,
  }) async* {
    final input = _TransferFrameReader(source);
    var total = 0, index = 0;
    try {
      while (true) {
        final header = await input.take(4);
        if (header == null) throw const FormatException('书籍传输中断，请重试');
        final count = ByteData.sublistView(header).getUint32(0);
        if (count < 28 || count > chunkBytes + 28) {
          throw const FormatException('书籍传输数据格式有误');
        }
        final packet = await input.take(count);
        if (packet == null) throw const FormatException('书籍传输中断，请重试');
        final bytes = await _run(
          false,
          packet,
          'wenku-lan-file-v1:$session:${index++}',
        );
        if (bytes.isEmpty) {
          if (total != length || await input.take(1) != null) {
            throw const FormatException('书籍传输不完整，请重试');
          }
          return;
        }
        total += bytes.length;
        if (total > length) throw const FormatException('收到的书籍大小有误');
        yield bytes;
        onProgress?.call(total);
      }
    } finally {
      await input.close();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _isolate.kill(priority: Isolate.immediate);
    await _messages.cancel();
    _port.close();
  }
}

class _TransferFrameReader {
  _TransferFrameReader(Stream<List<int>> stream)
    : _input = StreamIterator(stream.timeout(const Duration(seconds: 10)));
  final StreamIterator<List<int>> _input;
  List<int> _chunk = const [];
  int _offset = 0;
  Future<Uint8List?> take(int count) async {
    final out = Uint8List(count);
    var written = 0;
    while (written < count) {
      if (_offset == _chunk.length) {
        if (!await _input.moveNext()) {
          if (written != 0) throw const FormatException('书籍传输中断，请重试');
          return null;
        }
        _chunk = _input.current;
        _offset = 0;
        if (_chunk.isEmpty) continue;
      }
      final take = (count - written).clamp(0, _chunk.length - _offset);
      out.setRange(written, written + take, _chunk, _offset);
      written += take;
      _offset += take;
    }
    return out;
  }

  Future<void> close() => _input.cancel();
}

void _transferWorker((SendPort, String) input) async {
  final commands = ReceivePort();
  final aes = AesGcm.with256bits(), key = SecretKey(base64Url.decode(input.$2));
  input.$1.send(commands.sendPort);
  await for (final message in commands) {
    final job = message as (bool, TransferableTypedData, String);
    final data = job.$2.materialize().asUint8List();
    try {
      final Uint8List out;
      if (job.$1) {
        final box = await aes.encrypt(
          data,
          secretKey: key,
          aad: utf8.encode(job.$3),
        );
        out = Uint8List(28 + box.cipherText.length)
          ..setRange(0, 12, box.nonce)
          ..setRange(12, 28, box.mac.bytes)
          ..setRange(28, 28 + box.cipherText.length, box.cipherText);
      } else {
        out = Uint8List.fromList(
          await aes.decrypt(
            SecretBox(
              Uint8List.sublistView(data, 28),
              nonce: Uint8List.sublistView(data, 0, 12),
              mac: Mac(Uint8List.sublistView(data, 12, 28)),
            ),
            secretKey: key,
            aad: utf8.encode(job.$3),
          ),
        );
      }
      input.$1.send(TransferableTypedData.fromList([out]));
    } catch (_) {
      input.$1.send(false);
    }
  }
}
