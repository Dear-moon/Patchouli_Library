import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// A leased native descriptor is already authorized. Reopening /proc/self/fd
/// is not equivalent on Android's scoped-storage FUSE provider, and Darwin
/// does not expose that path. Map the live, read-only descriptor instead; no
/// original or expanded archive is staged.
class LocalDocumentInput {
  const LocalDocumentInput.file(this.path)
    : descriptor = null,
      size = null,
      offset = 0;
  const LocalDocumentInput.descriptor(
    this.descriptor,
    this.size, {
    this.offset = 0,
  }) : path = null;
  final String? path;
  final int? descriptor, size;
  final int offset;
  int get length => size ?? File(path!).lengthSync();

  LocalDocumentBuffer open() {
    if (offset != 0) throw const FormatException('这份输入范围需要使用有界读取');
    return path != null
        ? LocalDocumentBuffer._(InputFileStream(path!), null, 0)
        : LocalDocumentBuffer._mapped(descriptor!, size!);
  }

  /// Uses owned bounded bytes rather than a mapping. External TXT editors can
  /// truncate an open original without exposing a stale mmap page to the VM.
  LocalDocumentReadBuffer openReadBuffer() =>
      LocalDocumentReadBuffer._open(this);

  Stream<List<int>> bytes() async* {
    if (offset != 0) {
      final reader = openReadBuffer();
      try {
        for (var at = 0; at < length;) {
          final count = (length - at).clamp(
            0,
            LocalDocumentReadBuffer.maxReadBytes,
          );
          final chunk = reader.read(at, count);
          at += chunk.length;
          yield chunk;
        }
      } finally {
        reader.close();
      }
      return;
    }
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

/// Both entry points take a 64-bit file offset. Darwin exposes it as `off_t`
/// on mmap; Android needs mmap64's `off64_t`, including on 32-bit devices.
String localDocumentMmapSymbol(String operatingSystem) =>
    operatingSystem == 'ios' || operatingSystem == 'macos' ? 'mmap' : 'mmap64';

/// The raw reader retains a 64-bit offset on 32-bit Android as well.
String localDocumentPreadSymbol(String operatingSystem) =>
    operatingSystem == 'ios' || operatingSystem == 'macos'
    ? 'pread'
    : 'pread64';

/// libc's thread-local errno entry points differ between Darwin, Bionic and
/// the musl libc used by Harmony/Linux. It is used only to retry EINTR.
String localDocumentErrnoSymbol(String operatingSystem) =>
    operatingSystem == 'ios' || operatingSystem == 'macos'
    ? '__error'
    : operatingSystem == 'android'
    ? '__errno'
    : '__errno_location';

typedef _PreadNative = IntPtr Function(Int32, Pointer<Void>, UintPtr, Int64);
typedef _Pread = int Function(int, Pointer<Void>, int, int);
typedef _AllocateNative = Pointer<Void> Function(UintPtr);
typedef _Allocate = Pointer<Void> Function(int);
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _Free = void Function(Pointer<Void>);
typedef _ErrnoNative = Pointer<Int32> Function();
typedef _Errno = Pointer<Int32> Function();

/// A reader owns at most 32 KiB of scratch space and never owns the native
/// descriptor lease. Short reads/early EOF become ordinary source errors.
class LocalDocumentReadBuffer {
  LocalDocumentReadBuffer._(this._input, this.length, this._file, this._memory);
  factory LocalDocumentReadBuffer._open(LocalDocumentInput input) {
    final size = input.length;
    if (size < 0 || input.offset < 0) {
      throw const FormatException('原文件大小无效，请重新选择原文件');
    }
    if (input.path case final path?) {
      return LocalDocumentReadBuffer._(
        input,
        size,
        File(path).openSync(),
        null,
      );
    }
    final memory = _allocate(maxReadBytes).cast<Uint8>();
    if (memory.address == 0) throw OutOfMemoryError();
    return LocalDocumentReadBuffer._(input, size, null, memory);
  }

  static const maxReadBytes = 32 * 1024;
  static final _libc = DynamicLibrary.process();
  static final _allocate = _libc.lookupFunction<_AllocateNative, _Allocate>(
    'malloc',
  );
  static final _free = _libc.lookupFunction<_FreeNative, _Free>('free');
  static final _pread = _libc.lookupFunction<_PreadNative, _Pread>(
    localDocumentPreadSymbol(Platform.operatingSystem),
  );
  static final _errno = _libc.lookupFunction<_ErrnoNative, _Errno>(
    localDocumentErrnoSymbol(Platform.operatingSystem),
  );
  final LocalDocumentInput _input;
  final RandomAccessFile? _file;
  final Pointer<Uint8>? _memory;
  final int length;
  bool _closed = false;

  /// Reads an exact logical range without changing the leased descriptor's
  /// position. The returned bytes no longer depend on the original's lifetime.
  Uint8List read(int offset, int count) {
    if (_closed) throw StateError('原文件读取已结束');
    if (offset < 0 ||
        count < 0 ||
        count > maxReadBytes ||
        offset + count > length) {
      throw RangeError('原文件读取范围无效');
    }
    final file = _file;
    if (file != null) {
      file.setPositionSync(_input.offset + offset);
      final bytes = Uint8List(count);
      var done = 0;
      while (done < count) {
        final read = file.readIntoSync(bytes, done, count);
        if (read == 0) throw const FormatException('原文件已变化，请重新选择');
        done += read;
      }
      return bytes;
    }
    final errno = _errno;
    var done = 0;
    while (done < count) {
      final read = _pread(
        _input.descriptor!,
        (_memory! + done).cast<Void>(),
        count - done,
        _input.offset + offset + done,
      );
      if (read < 0) {
        final code = errno().value;
        if (code == 4) continue; // EINTR never changes a decoder checkpoint.
        throw FileSystemException('无法读取原文件，请重新定位原文件', '', OSError('', code));
      }
      if (read == 0) throw const FormatException('原文件已变化，请重新选择');
      done += read;
    }
    return Uint8List.fromList(_memory!.asTypedList(count));
  }

  /// Releases only owned scratch storage/file handles, never the native lease.
  void close() {
    if (_closed) return;
    _closed = true;
    try {
      _file?.closeSync();
    } finally {
      if (_memory case final memory?) _free(memory.cast<Void>());
    }
  }
}

typedef _MmapNative =
    Pointer<Void> Function(Pointer<Void>, UintPtr, Int32, Int32, Int32, Int64);
typedef _Mmap = Pointer<Void> Function(Pointer<Void>, int, int, int, int, int);
typedef _MunmapNative = Int32 Function(Pointer<Void>, UintPtr);
typedef _Munmap = int Function(Pointer<Void>, int);

class LocalDocumentBuffer {
  LocalDocumentBuffer._(this.stream, this._mapping, this._size);
  factory LocalDocumentBuffer._mapped(int fd, int size) {
    if (size < 0) {
      throw const FormatException('原文件大小无效，请重新选择原文件');
    }
    if (size == 0) {
      return LocalDocumentBuffer._(InputMemoryStream(Uint8List(0)), null, 0);
    }
    // PROT_READ with MAP_PRIVATE: never make the leased original writable.
    final pointer = _mmap(nullptr, size, 1, 2, fd, 0);
    if (pointer.address == -1 ||
        pointer.address == 0xffffffffffffffff ||
        pointer.address == 0xffffffff ||
        pointer.address == 0) {
      throw const FormatException('无法直接读取这份原文件，请选择「复制到应用」');
    }
    try {
      return LocalDocumentBuffer._(
        InputMemoryStream(pointer.cast<Uint8>().asTypedList(size)),
        pointer,
        size,
      );
    } catch (_) {
      _munmap(pointer, size);
      rethrow;
    }
  }
  static final _mmap = DynamicLibrary.process()
      .lookupFunction<_MmapNative, _Mmap>(
        localDocumentMmapSymbol(Platform.operatingSystem),
      );
  static final _munmap = DynamicLibrary.process()
      .lookupFunction<_MunmapNative, _Munmap>('munmap');
  final InputStream stream;
  final Pointer<Void>? _mapping;
  final int _size;
  bool _closed = false;
  void close() {
    if (_closed) return;
    _closed = true;
    try {
      stream.closeSync();
    } finally {
      if (_mapping != null) _munmap(_mapping, _size);
    }
  }
}
