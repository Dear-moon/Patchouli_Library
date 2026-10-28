import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart';
import 'local_document_input.dart';

/// Only an opaque native grant and content identity are durable. A descriptor
/// path is valid within one operation and must never enter book metadata.
class LocalDocumentSource {
  const LocalDocumentSource({
    required this.reference,
    required this.size,
    required this.modified,
    required this.digest,
  });
  final String reference, digest;
  final int size, modified;
  Map<String, Object> toJson() => {
    'reference': reference,
    'size': size,
    'modified': modified,
    'digest': digest,
  };
  factory LocalDocumentSource.fromJson(Object? raw) {
    if (raw is! Map ||
        raw['reference'] is! String ||
        (raw['reference'] as String).isEmpty ||
        raw['size'] is! int ||
        raw['size'] <= 0 ||
        raw['size'] > 512 * 1024 * 1024 ||
        raw['modified'] is! int ||
        raw['digest'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['digest'])) {
      throw const FormatException('原文件关联记录有误，请重新定位原文件');
    }
    return LocalDocumentSource(
      reference: raw['reference'],
      size: raw['size'],
      modified: raw['modified'],
      digest: raw['digest'],
    );
  }
}

abstract class LocalDocumentAccess {
  Future<LocalDocumentSource> inspect(String reference);
  Future<T> withInput<T>(
    LocalDocumentSource source,
    Future<T> Function(LocalDocumentInput input) read,
  );
  Stream<List<int>> bytes(LocalDocumentSource source);
}

/// Metadata captured while the read-only input is already open. The import
/// worker adds its exact content digest before this becomes durable metadata.
typedef LocalDocumentHeader = ({String reference, int size, int modified});

/// Optional import capability. Existing access implementations keep their
/// inspect/validated-read contract; platform imports avoid closing and reopening
/// the original between identifying and parsing it.
abstract interface class LocalDocumentImportAccess {
  Future<T> withFreshInput<T>(
    String reference,
    Future<T> Function(LocalDocumentInput input, LocalDocumentHeader header)
    read,
  );
}

Future<String> _documentDigest(LocalDocumentInput input) async =>
    (await sha256.bind(input.bytes()).first).toString();

class PlatformLocalDocumentAccess
    implements LocalDocumentAccess, LocalDocumentImportAccess {
  static const _channel = MethodChannel('org.mewx.wenku8/book_documents');
  Future<Map<String, dynamic>> _open(
    String reference, [
    LocalDocumentSource? expected,
  ]) async => (await _channel.invokeMapMethod<String, dynamic>(
    'openLinkedDocument',
    {'reference': reference, if (expected != null) ...expected.toJson()},
  ))!;
  Future<void> _close(Map lease) => _channel.invokeMethod<void>(
    'closeLinkedDocument',
    {'lease': lease['lease']},
  );

  @override
  Future<LocalDocumentSource> inspect(String reference) async {
    final lease = await _open(reference);
    try {
      final digest = await compute(
        _documentDigest,
        _input(lease),
        debugLabel: 'local-original-identity',
      );
      return LocalDocumentSource.fromJson({
        ...lease,
        'reference': reference,
        'digest': digest,
      });
    } finally {
      await _close(lease);
    }
  }

  LocalDocumentInput _input(Map lease) => lease['descriptor'] is int
      ? LocalDocumentInput.descriptor(lease['descriptor'], lease['size'])
      : LocalDocumentInput.file(lease['path'] as String);

  @override
  Future<T> withFreshInput<T>(
    String reference,
    Future<T> Function(LocalDocumentInput input, LocalDocumentHeader header)
    read,
  ) async {
    final lease = await _open(reference);
    try {
      return await read(_input(lease), (
        reference: reference,
        size: lease['size'] as int,
        modified: lease['modified'] as int,
      ));
    } on FileSystemException {
      throw const FormatException('无法原位读取这份原文件，请重新定位，或选择「复制到应用」');
    } finally {
      await _close(lease);
    }
  }

  @override
  Future<T> withInput<T>(
    LocalDocumentSource source,
    Future<T> Function(LocalDocumentInput input) read,
  ) async {
    final lease = await _open(source.reference, source);
    try {
      return await read(_input(lease));
    } on FileSystemException {
      throw const FormatException('无法原位读取这份原文件，请重新定位，或选择「复制到应用」');
    } finally {
      await _close(lease);
    }
  }

  @override
  Stream<List<int>> bytes(LocalDocumentSource source) async* {
    final lease = await _open(source.reference, source);
    try {
      yield* _input(lease).bytes();
    } finally {
      await _close(lease);
    }
  }
}
