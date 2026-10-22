part of 'lan_reading_sync.dart';

class LanHandoffReceipt {
  const LanHandoffReceipt(this.book, this.position, this.device);
  final Novel book;
  final ReadingPosition position;
  final String device;
}

class LanBookTransfer {
  const LanBookTransfer({
    required this.title,
    required this.device,
    required this.phase,
    required this.incoming,
    this.bytes = 0,
    this.total = 0,
    this.cancellable = true,
  });
  final String title, device, phase;
  final bool incoming;
  final bool cancellable;
  final int bytes, total;
  double? get progress => total == 0 ? null : (bytes / total).clamp(0.0, 1.0);
}

class _HandoffJob {
  _HandoffJob({
    required this.id,
    required this.manifest,
    required this.files,
    required this.position,
    required this.host,
    required this.sender,
    required this.device,
    required this.cipher,
    required this.staging,
  });
  final String id, host, device;
  final String? sender;
  final LocalBookHandoff manifest;
  final List<LocalHandoffFile> files;
  final ReadingPosition position;
  final LanSyncCipher cipher;
  final Directory staging;
  Timer? expiry;
  LanTransferCipher? worker;
  Future<void>? discarding;
  bool receiving = false, cancelled = false;
}

/// One explicitly selected book at a time, over an already authenticated peer.
/// This controller owns transfers independently of the lightweight periodic
/// position exchange, so progress does not rebuild the reader or the app shell.
class LanBookHandoff extends ChangeNotifier {
  LanBookHandoff(this._sync);
  final LanReadingSync _sync;
  LocalBookStore? get _books => _sync.books;
  LanBookTransfer? transfer;
  LanHandoffReceipt? received;
  String? error;
  final _jobs = <String, _HandoffJob>{};
  HttpClientRequest? _sending;
  LanTransferCipher? _sendingWorker;
  bool _sendingBook = false, _disposed = false;
  bool _incomingFailure = false;
  Future<void>? _storage;
  String? get incomingError => _incomingFailure ? error : null;
  Future<void> initializeStorage() => _storage ??= _cleanAbandoned();
  Future<void> _cleanAbandoned() async {
    final books = _books;
    if (books == null || !await books.directory.exists()) return;
    try {
      await for (final entry in books.directory.list(followLinks: false)) {
        if (entry is Directory &&
            RegExp(r'^\.lan-handoff-[a-f0-9]{32}$').hasMatch(
              entry.uri.pathSegments.where((s) => s.isNotEmpty).last,
            )) {
          await entry.delete(recursive: true);
        }
      }
    } on FileSystemException {
      _incomingFailure = true;
      error = '上次传书的临时文件未能清理，请检查本机存储后重新打开 App';
      _notify();
    }
  }

  void dismissError() {
    error = null;
    _incomingFailure = false;
    _notify();
  }

  int _generation = 0, _lastProgress = 0;
  bool get busy => _sendingBook || _jobs.isNotEmpty;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _progress(int bytes, int total) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (bytes != total && now - _lastProgress < 50) return;
    _lastProgress = now;
    final current = transfer;
    if (current == null) return;
    transfer = LanBookTransfer(
      title: current.title,
      device: current.device,
      phase: current.phase,
      incoming: current.incoming,
      bytes: bytes,
      total: total,
      cancellable: current.cancellable,
    );
    _notify();
  }

  ReadingPosition _positionFor(Novel book, ReadingPosition incoming) {
    if (incoming.chapter < 0 || incoming.chapter >= book.chapters.length) {
      throw const FormatException('两端章节不一致，未更改阅读位置');
    }
    // Identical series may have different stable IDs on the other device.
    // Their ordered original/parse identities establish the chapter space.
    return ReadingPosition.fromJson({
      ...incoming.toJson(),
      'chapterId': book.chapters[incoming.chapter].id,
    });
  }

  Future<LanHandoffReceipt> _ready(
    Novel book,
    ReadingPosition position,
    String device,
  ) async {
    final mapped = _positionFor(book, position);
    await _sync.state.rememberNovel(book);
    await _sync.state.setLocalBookHidden(book.id, false);
    await _sync.state.mergeLanPositions({book: mapped});
    received = LanHandoffReceipt(book, mapped, device);
    error = null;
    _incomingFailure = false;
    _notify();
    return received!;
  }

  void dismissReceipt() {
    received = null;
    _notify();
  }

  Future<HttpClientRequest> _request(LanPeer peer, String path) async {
    final client = _sync._client;
    if (client == null) throw const FormatException('请先开启局域网续读');
    final request = await client.postUrl(
      Uri(scheme: 'http', host: peer.host, port: peer.port, path: path),
    );
    // Abort can complete the response before an upload finishes, so observe it
    // now as well as awaiting close below. Upload failures still reach send().
    request.done.ignore();
    request.followRedirects = false;
    if (peer.deviceId != null) {
      request.headers.set('X-Wenku-Peer', _sync.deviceId!);
    }
    return request;
  }

  Future<Map<String, dynamic>> _control(
    LanPeer peer,
    LanSyncCipher cipher,
    String path,
    Map<String, dynamic> data,
    String kind,
  ) async {
    final request = await _request(peer, path);
    request.headers.contentType = ContentType.json;
    request.write(
      await cipher.seal({
        ...data,
        'at': DateTime.now().millisecondsSinceEpoch,
      }, kind),
    );
    final response = await request.close().timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw const FormatException('另一台设备暂未接受传输，请保持 App 在前台后重试');
    }
    return cipher.open(await _sync._read(response), '$kind-reply');
  }

  Future<void> send({
    required LanPeer peer,
    required int bookId,
    required ReadingPosition position,
  }) async {
    if (busy) throw const FormatException('请等待当前书籍传输完成');
    if (_books == null || !_sync.enabled || _sync._client == null) {
      throw const FormatException('请先开启局域网续读并连接设备');
    }
    final trusted = _sync.peers
        .where(
          (p) =>
              p.key == peer.key &&
              (p.deviceId == peer.deviceId) &&
              p.addressKey == peer.addressKey,
        )
        .firstOrNull;
    if (trusted == null) throw const FormatException('设备连接已变化，请重新选择');
    _sendingBook = true;
    final generation = ++_generation;
    final id = newLanDeviceId(), cipher = LanSyncCipher(peer.key);
    final device = peer.name ?? peer.host;
    error = null;
    _incomingFailure = false;
    transfer = LanBookTransfer(
      title: _books!.book(bookId)?.title ?? '',
      device: device,
      phase: '正在准备续读',
      incoming: false,
    );
    _notify();
    try {
      final manifest = await _books!.prepareHandoff(bookId);
      if (generation != _generation) throw const FormatException('书籍传输已取消');
      final answer = await _control(peer, cipher, '/handoff/offer', {
        'id': id,
        'device': _sync.deviceName,
        'manifest': manifest.toJson(),
        'position': {
          ...position.toJson(),
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        },
      }, 'handoff-offer');
      if (generation != _generation) throw const FormatException('书籍传输已取消');
      if (answer['replyTo'] != id) throw const FormatException('续读回复不匹配');
      if (answer['error'] is String) throw FormatException(answer['error']);
      if (answer['ready'] == true) return;
      final wanted = answer['needed'];
      if (wanted is! List ||
          wanted.any((key) => key is! String) ||
          wanted.length != wanted.toSet().length) {
        throw const FormatException('设备返回的传书信息有误');
      }
      final known = {for (final file in manifest.files) file.key: file};
      if (wanted.any((key) => !known.containsKey(key))) {
        throw const FormatException('设备返回了无效书籍文件');
      }
      final files = wanted.map((key) => known[key]!).toList();
      final total = files.fold(0, (sum, file) => sum + file.length);
      transfer = LanBookTransfer(
        title: manifest.title,
        device: device,
        phase: '正在传送书籍',
        incoming: false,
        total: total,
      );
      _notify();
      final worker = await LanTransferCipher.start(peer.key);
      _sendingWorker = worker;
      if (generation != _generation) throw const FormatException('书籍传输已取消');
      final request = await _request(peer, '/handoff/push/$id');
      _sending = request;
      request.headers.contentType = ContentType.binary;
      Stream<List<int>> source() async* {
        for (final file in files) {
          yield* _books!.openHandoffFile(file);
        }
      }

      // Keep file/crypto cancellation in this owner, not in the HTTP socket's
      // input stream. Flush each bounded frame for backpressure and immediate
      // cancellation without an unobserved socket stream-error future.
      await for (final frame in worker.seal(
        source(),
        session: id,
        length: total,
        onProgress: (bytes) => _progress(bytes, total),
      )) {
        request.add(frame);
        await request.flush();
      }
      transfer = LanBookTransfer(
        title: manifest.title,
        device: device,
        phase: '正在完成续读',
        incoming: false,
        cancellable: false,
        bytes: total,
        total: total,
      );
      _notify();
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      if (response.statusCode != 200) {
        throw const FormatException('书籍未能完整传到对方设备，请重试');
      }
      final result = await cipher.open(
        await _sync._read(response),
        'handoff-result',
      );
      if (result['replyTo'] != id || result['ready'] != true) {
        throw FormatException(
          result['error'] is String ? result['error'] : '对方设备未能完成续读准备',
        );
      }
    } catch (failure) {
      _sending?.abort();
      error = generation != _generation
          ? '书籍传输已取消'
          : failure is FormatException
          ? failure.message.toString()
          : '设备连接或本地空间暂时异常，原书仍保留，请重试';
      rethrow;
    } finally {
      if (generation == _generation) _sending = null;
      await _sendingWorker?.close();
      _sendingWorker = null;
      _sendingBook = false;
      transfer = null;
      _notify();
      // Cancellation and an interrupted sender leave no reserved receiver job.
      if (error != null && _sync._client != null) {
        unawaited(
          _control(peer, cipher, '/handoff/cancel', {
            'id': id,
          }, 'handoff-cancel').catchError((Object _) => <String, dynamic>{}),
        );
      }
    }
  }

  Future<void> _reply(
    HttpRequest request,
    LanSyncCipher cipher,
    Map<String, dynamic> data,
    String kind,
  ) async {
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('Cache-Control', 'no-store');
    request.response.write(
      await cipher.seal({
        ...data,
        'at': DateTime.now().millisecondsSinceEpoch,
      }, kind),
    );
  }

  Future<void> handle(
    HttpRequest request,
    LanSyncCipher cipher,
    String? sender,
  ) async {
    final path = request.uri.path;
    if (_books == null) {
      request.response.statusCode = 404;
      return;
    }
    if (path == '/handoff/cancel') {
      final value = await cipher.open(
        await _sync._read(request, maximum: 4096),
        'handoff-cancel',
      );
      final job = _jobs[value['id']];
      if (job != null &&
          job.sender == sender &&
          job.host == request.connectionInfo!.remoteAddress.address) {
        job.cancelled = true;
        unawaited(job.worker?.close());
        if (!job.receiving) await _discard(job);
      }
      await _reply(request, cipher, {
        'replyTo': value['id'],
      }, 'handoff-cancel-reply');
      return;
    }
    if (path == '/handoff/offer') {
      final value = await cipher.open(
        await _sync._read(request),
        'handoff-offer',
      );
      final id = value['id'];
      if (id is! String ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
          value['position'] is! Map ||
          value['device'] is! String ||
          value['device'].length > 64) {
        throw const FormatException('续读请求格式有误');
      }
      try {
        if (busy) throw const FormatException('另一台设备正在传书，请稍后重试');
        final manifest = LocalBookHandoff.fromJson(value['manifest']);
        final position = ReadingPosition.fromJson(
          Map<String, dynamic>.from(value['position']),
        );
        if (_books!.bookForHandoff(manifest.identity) case final existing?) {
          await _ready(existing, position, value['device']);
          await _reply(request, cipher, {
            'replyTo': id,
            'ready': true,
          }, 'handoff-offer-reply');
          return;
        }
        final files = _books!.neededHandoffFiles(manifest);
        final staging = Directory('${_books!.directory.path}/.lan-handoff-$id');
        if (await staging.exists()) {
          throw const FormatException('该传输尚未清理完成，请重试');
        }
        await staging.create(recursive: true);
        final job = _HandoffJob(
          id: id,
          manifest: manifest,
          files: files,
          position: position,
          host: request.connectionInfo!.remoteAddress.address,
          sender: sender,
          device: value['device'],
          cipher: cipher,
          staging: staging,
        );
        _jobs[id] = job;
        job.expiry = Timer(
          const Duration(minutes: 2),
          () => unawaited(_discard(job)),
        );
        await _reply(request, cipher, {
          'replyTo': id,
          'ready': false,
          'needed': files.map((f) => f.key).toList(),
        }, 'handoff-offer-reply');
      } on FormatException catch (failure) {
        await _reply(request, cipher, {
          'replyTo': id,
          'error': failure.message,
        }, 'handoff-offer-reply');
      }
      return;
    }
    final id = path.startsWith('/handoff/push/')
        ? path.substring('/handoff/push/'.length)
        : '';
    final job = _jobs[id];
    if (job == null ||
        job.receiving ||
        job.cancelled ||
        job.sender != sender ||
        job.host != request.connectionInfo!.remoteAddress.address) {
      request.response.statusCode = 403;
      return;
    }
    job.receiving = true;
    job.expiry?.cancel();
    final total = job.files.fold(0, (sum, file) => sum + file.length);
    transfer = LanBookTransfer(
      title: job.manifest.title,
      device: job.device,
      phase: '正在接收书籍',
      incoming: true,
      total: total,
    );
    error = null;
    _notify();
    try {
      final worker = await LanTransferCipher.start(cipher.encodedKey);
      job.worker = worker;
      if (job.cancelled) throw const FormatException('书籍传输已取消');
      final body = worker.open(
        request,
        session: id,
        length: total,
        onProgress: (bytes) => _progress(bytes, total),
      );
      var index = 0, written = 0;
      RandomAccessFile? output;
      Future<void> nextFile() async {
        await output?.close();
        output = null;
        while (index < job.files.length) {
          final file = File('${job.staging.path}/${job.files[index].key}');
          await file.parent.create(recursive: true);
          output = await file.open(mode: FileMode.write);
          written = 0;
          if (job.files[index].length != 0) return;
          await output!.close();
          output = null;
          index++;
        }
      }

      try {
        await nextFile();
        await for (final chunk in body) {
          if (job.cancelled) throw const FormatException('书籍传输已取消');
          var offset = 0;
          while (offset < chunk.length) {
            if (index >= job.files.length) {
              throw const FormatException('书籍内容超过目录范围');
            }
            final count = (job.files[index].length - written).clamp(
              0,
              chunk.length - offset,
            );
            await output!.writeFrom(chunk, offset, offset + count);
            written += count;
            offset += count;
            if (written == job.files[index].length) {
              index++;
              await nextFile();
            }
          }
        }
      } finally {
        await output?.close();
      }
      if (index != job.files.length || job.cancelled) {
        throw const FormatException('书籍传输未完成，请重试');
      }
      transfer = LanBookTransfer(
        title: job.manifest.title,
        device: job.device,
        phase: '正在准备续读',
        incoming: true,
        cancellable: false,
        bytes: total,
        total: total,
      );
      _notify();
      final book = await _books!.receiveHandoff(job.manifest, job.staging);
      await _ready(book, job.position, job.device);
      await _reply(request, cipher, {
        'replyTo': id,
        'ready': true,
      }, 'handoff-result');
    } catch (failure) {
      _incomingFailure = true;
      error = job.cancelled
          ? '书籍接收已取消'
          : failure is FormatException
          ? failure.message.toString()
          : '书籍未能接收完成，请检查连接和本机空间后重试';
      _notify();
      try {
        await _reply(request, cipher, {
          'replyTo': id,
          'ready': false,
          'error': error,
        }, 'handoff-result');
      } on IOException {
        /* peer has already disconnected */
      }
    } finally {
      await _discard(job);
      transfer = null;
      _notify();
    }
  }

  Future<void> _discard(_HandoffJob job) => job.discarding ??= () async {
    job.expiry?.cancel();
    try {
      await job.worker?.close();
      if (await job.staging.exists()) await job.staging.delete(recursive: true);
    } finally {
      _jobs.remove(job.id);
    }
  }();

  void cancel() {
    _generation++;
    _sending?.abort();
    _sending = null;
    unawaited(_sendingWorker?.close());
    for (final job in _jobs.values.toList()) {
      job.cancelled = true;
      unawaited(job.worker?.close());
      if (!job.receiving) unawaited(_discard(job));
    }
  }

  void stop() => cancel();
  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}
