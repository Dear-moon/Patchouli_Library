import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// A leased SAF descriptor is already authorized. Reopening /proc/self/fd is
/// not equivalent on Android's scoped-storage FUSE provider. Map that live,
/// read-only descriptor instead; no original or expanded archive is staged.
class LocalDocumentInput {
  const LocalDocumentInput.file(this.path) : descriptor = null, size = null;
  const LocalDocumentInput.descriptor(this.descriptor, this.size) : path = null;
  final String? path;
  final int? descriptor, size;
  int get length => size ?? File(path!).lengthSync();

  LocalDocumentBuffer open() => path != null
      ? LocalDocumentBuffer._(InputFileStream(path!), null, 0)
      : LocalDocumentBuffer._mapped(descriptor!, size!);

  Stream<List<int>> bytes() async* {
    if (path != null) {
      yield* File(path!).openRead();
      return;
    }
    final buffer = open();
    try {
      while (!buffer.stream.isEOS) {
        // Owned chunks outlive the mapping when stream consumers retain them.
        yield Uint8List.fromList(
          buffer.stream.readBytes(64 * 1024).toUint8List(),
        );
      }
    } finally {
      buffer.close();
    }
  }
}

typedef _MmapNative =
    Pointer<Void> Function(Pointer<Void>, IntPtr, Int32, Int32, Int32, Int64);
typedef _Mmap = Pointer<Void> Function(Pointer<Void>, int, int, int, int, int);
typedef _MunmapNative = Int32 Function(Pointer<Void>, IntPtr);
typedef _Munmap = int Function(Pointer<Void>, int);

class LocalDocumentBuffer {
  LocalDocumentBuffer._(this.stream, this._mapping, this._size);
  factory LocalDocumentBuffer._mapped(int fd, int size) {
    final pointer = _mmap(nullptr, size, 1, 2, fd, 0);
    if (pointer.address == -1 ||
        pointer.address == 0xffffffffffffffff ||
        pointer.address == 0xffffffff ||
        pointer.address == 0) {
      throw const FormatException('无法直接读取这份原文件，请选择「复制到应用」');
    }
    return LocalDocumentBuffer._(
      InputMemoryStream(pointer.cast<Uint8>().asTypedList(size)),
      pointer,
      size,
    );
  }
  static final _mmap = DynamicLibrary.process()
      .lookupFunction<_MmapNative, _Mmap>('mmap64');
  static final _munmap = DynamicLibrary.process()
      .lookupFunction<_MunmapNative, _Munmap>('munmap');
  final InputStream stream;
  final Pointer<Void>? _mapping;
  final int _size;
  void close() {
    stream.closeSync();
    if (_mapping != null) _munmap(_mapping, _size);
  }
}
