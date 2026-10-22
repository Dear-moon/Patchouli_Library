import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'catalog.dart';
import 'library_state.dart';
import 'local_books.dart';
import 'lan_discovery.dart';
import 'lan_pairing.dart';
import 'lan_transfer_cipher.dart';
import 'library_incremental_sync.dart';
export 'lan_discovery.dart' show LanDiscovery, LanNearbyDevice;

part 'lan_book_handoff.dart';

bool isPrivateLanAddress(InternetAddress address) {
  final bytes = address.rawAddress;
  return address.isLoopback ||
      bytes.length == 4 &&
          (bytes[0] == 10 ||
              bytes[0] == 192 && bytes[1] == 168 ||
              bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31 ||
              bytes[0] == 169 && bytes[1] == 254);
}

String _newLanKey() {
  final random = Random.secure();
  return base64Url.encode(List.generate(32, (_) => random.nextInt(256)));
}

class LanPairingStore {
  const LanPairingStore();
  static const channel = MethodChannel('org.mewx.wenku8/lan_reading_config');
  Future<Map<String, dynamic>> read() async {
    final text = await channel.invokeMethod<String>('read');
    return text == null ? {} : Map<String, dynamic>.from(jsonDecode(text));
  }

  Future<void> write(Map<String, dynamic> value) =>
      channel.invokeMethod<void>('write', jsonEncode(value));
}

class LanPeer {
  const LanPeer(this.host, this.port, this.key, {this.deviceId, this.name});
  final String host, key;
  final int port;
  final String? deviceId, name;
  String get addressKey => '$host:$port';
  factory LanPeer.parse(String value) {
    final uri = Uri.parse(value.trim());
    final address = InternetAddress.tryParse(uri.host);
    final key = uri.queryParameters['key'];
    if (uri.scheme != 'wenku-sync' ||
        address == null ||
        !isPrivateLanAddress(address) ||
        uri.port < 1024 ||
        uri.port > 65535 ||
        key == null ||
        base64Url.decode(key).length != 32) {
      throw const FormatException('连接码无效，请复制同一局域网设备的完整连接码');
    }
    return LanPeer(address.address, uri.port, key);
  }
  String get code => Uri(
    scheme: 'wenku-sync',
    host: host,
    port: port,
    queryParameters: {'key': key},
  ).toString();
  Object toRecord() =>
      deviceId == null ? code : {'id': deviceId, 'name': name, 'code': code};
  factory LanPeer.fromRecord(Object? value) {
    if (value is String) return LanPeer.parse(value);
    if (value is! Map ||
        value['id'] is! String ||
        value['name'] is! String ||
        value['code'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(value['id']) ||
        (value['name'] as String).length > 64) {
      throw const FormatException('配对记录无效');
    }
    final peer = LanPeer.parse(value['code']);
    return LanPeer(
      peer.host,
      peer.port,
      peer.key,
      deviceId: value['id'],
      name: value['name'],
    );
  }
}

class _NearbyPairing {
  _NearbyPairing(this.offer, this.peer, this.digits);
  final LanPairOffer offer;
  final LanPeer peer;
  final String digits;
  late final cipher = LanSyncCipher(peer.key);
  bool accepted = false,
      remoteAccepted = false,
      completed = false,
      cancelled = false,
      polling = false;
  Future<void>? saving;
  Timer? poll, expiry;
}

class _NearbyReservation {
  _NearbyReservation(this.handshake, this.remote, this.host);
  final LanPairHandshake handshake;
  final LanPairCommit remote;
  final String host;
  Timer? expiry;
}

/// Authenticated encryption keeps progress and book identities private on Wi-Fi.
/// A key is shared only by explicit pairing, never exported with library backups.
class LanSyncCipher {
  LanSyncCipher(this.encodedKey)
    : key = SecretKey(base64Url.decode(encodedKey));
  final String encodedKey;
  final SecretKey key;
  final _aes = AesGcm.with256bits();
  final _seen = <String>{};
  Future<String> seal(Map<String, dynamic> value, String kind) async {
    if (value['library'] is Map ||
        value.values.any(
          (v) =>
              v is Map && v.length > 32 ||
              v is List && v.length > 64 ||
              v is String && v.length > 32768,
        )) {
      return compute(_sealLargeLanPacket, (
        key: encodedKey,
        value: value,
        kind: kind,
      ));
    }
    final text = jsonEncode(value);
    final box = await _aes.encrypt(
      utf8.encode(text),
      secretKey: key,
      aad: utf8.encode('wenku-lan-v1:$kind'),
    );
    return jsonEncode({
      'nonce': base64Url.encode(box.nonce),
      'body': base64Url.encode(box.cipherText),
      'tag': base64Url.encode(box.mac.bytes),
    });
  }

  Future<Map<String, dynamic>> open(String text, String kind) async {
    Map<String, dynamic> value;
    String nonce;
    if (text.length > 32768) {
      final packet = await compute(_openLargeLanPacket, (
        key: encodedKey,
        text: text,
        kind: kind,
      ));
      value = packet.value;
      nonce = packet.nonce;
    } else {
      final raw = jsonDecode(text);
      if (raw is! Map ||
          raw['nonce'] is! String ||
          raw['body'] is! String ||
          raw['tag'] is! String) {
        throw const FormatException('同步数据格式有误');
      }
      if (_seen.contains(raw['nonce'])) throw const FormatException('重复的同步请求');
      final decoded = jsonDecode(
        utf8.decode(
          await _aes.decrypt(
            SecretBox(
              base64Url.decode(raw['body']),
              nonce: base64Url.decode(raw['nonce']),
              mac: Mac(base64Url.decode(raw['tag'])),
            ),
            secretKey: key,
            aad: utf8.encode('wenku-lan-v1:$kind'),
          ),
        ),
      );
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('同步内容格式有误');
      }
      value = decoded;
      nonce = raw['nonce'];
    }
    if (_seen.contains(nonce)) throw const FormatException('重复的同步请求');
    if (value['at'] is! int ||
        (DateTime.now().millisecondsSinceEpoch - (value['at'] as int)).abs() >
            300000) {
      throw const FormatException('设备时间相差过大，请校准系统时间');
    }
    if (_seen.length >= 256) _seen.remove(_seen.first);
    _seen.add(nonce);
    return value;
  }
}

Future<String> _sealLargeLanPacket(
  ({String key, Map<String, dynamic> value, String kind}) input,
) async {
  final aes = AesGcm.with256bits();
  final box = await aes.encrypt(
    utf8.encode(jsonEncode(input.value)),
    secretKey: SecretKey(base64Url.decode(input.key)),
    aad: utf8.encode('wenku-lan-v1:${input.kind}'),
  );
  return jsonEncode({
    'nonce': base64Url.encode(box.nonce),
    'body': base64Url.encode(box.cipherText),
    'tag': base64Url.encode(box.mac.bytes),
  });
}

Future<({String nonce, Map<String, dynamic> value})> _openLargeLanPacket(
  ({String key, String text, String kind}) input,
) async {
  final raw = jsonDecode(input.text);
  if (raw is! Map ||
      raw['nonce'] is! String ||
      raw['body'] is! String ||
      raw['tag'] is! String) {
    throw const FormatException('同步数据格式有误');
  }
  final clear = await AesGcm.with256bits().decrypt(
    SecretBox(
      base64Url.decode(raw['body']),
      nonce: base64Url.decode(raw['nonce']),
      mac: Mac(base64Url.decode(raw['tag'])),
    ),
    secretKey: SecretKey(base64Url.decode(input.key)),
    aad: utf8.encode('wenku-lan-v1:${input.kind}'),
  );
  return (
    nonce: raw['nonce'] as String,
    value: Map<String, dynamic>.from(jsonDecode(utf8.decode(clear))),
  );
}

class LanReadingSync extends ChangeNotifier with WidgetsBindingObserver {
  LanReadingSync({
    required this.state,
    required this.preferences,
    this.books,
    this.port = 38762,
    this.address,
    this.pairings = const LanPairingStore(),
    LanDiscovery? discovery,
  }) : discovery = discovery ?? LanDiscovery();
  final LibraryState state;
  final SharedPreferences preferences;
  final LocalBookStore? books;
  final int port;
  final InternetAddress? address;
  final LanPairingStore pairings;
  final LanDiscovery discovery;
  LibraryIncrementalSync? librarySync;
  Timer? _libraryDebounce;
  final _libraryVersions = <String, Object?>{};
  void _libraryChanged() {
    if (_closed || !_foreground || !enabled || _server == null) return;
    _libraryDebounce?.cancel();
    _libraryDebounce = Timer(
      const Duration(milliseconds: 700),
      () => unawaited(sync()),
    );
  }

  late final handoff = LanBookHandoff(this);
  Map<String, dynamic>? _pairings;
  Future<void> _configurationWrites = Future.value();
  StreamSubscription<List<LanNearbyDevice>>? _discoveryChanges;
  List<LanNearbyDevice> nearby = const [];
  String get deviceName => discovery.name;
  String? get deviceId => _pairings?['device'] as String?;
  bool get automaticDiscovery => discovery.available;
  int _pairingScreens = 0;
  final _sessions = <String, _NearbyPairing>{};
  final _offers = <String, _NearbyReservation>{};
  _NearbyPairing? _pendingPair;
  ({String name, String digits, bool accepted})? get pendingPairing {
    final pair = _pendingPair;
    return pair == null || pair.completed || pair.cancelled
        ? null
        : (name: pair.peer.name!, digits: pair.digits, accepted: pair.accepted);
  }

  final _incomingCiphers = <String, LanSyncCipher>{};
  int _lastOffer = 0;
  void openPairing() {
    _pairingScreens++;
  }

  void closePairing() {
    _pairingScreens = (_pairingScreens - 1).clamp(0, 100);
    if (_pairingScreens == 0) cancelPairing();
  }

  bool get enabled => preferences.getBool('lanReading.enabled.v1') ?? false;
  HttpServer? _server;
  int _requests = 0;
  HttpClient? _client;
  Future<void>? _starting;
  Timer? _poll;
  LanSyncCipher? _cipher;
  bool _busy = false, _closed = false, _observing = false, _foreground = true;
  int _epoch = 0;
  int? lastSync;
  String? error;
  List<String> hosts = const [];
  List<LanPeer> get peers => [
    for (final value in _pairings?['peers'] as List? ?? const [])
      ?_validPeer(value),
  ];
  LanPeer? _validPeer(Object? text) {
    try {
      return LanPeer.fromRecord(text);
    } catch (_) {
      return null;
    }
  }

  String? codeFor(String host) => _server == null || _serverKey == null
      ? null
      : LanPeer(host, _server!.port, _serverKey!).code;
  String? _serverKey;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> initialize() async {
    _observe();
    await handoff.initializeStorage();
    if (enabled) await start();
  }

  void _observe() {
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      state.bookmarkChanges.addListener(_libraryChanged);
      state.organization.addListener(_libraryChanged);
      _observing = true;
    }
  }

  Future<void> setEnabled(bool value) async {
    if (!await preferences.setBool('lanReading.enabled.v1', value)) {
      throw const FormatException('同步设置未保存');
    }
    if (value) {
      await start();
    } else {
      await stop();
    }
    _notify();
  }

  Future<void> start() async {
    if (_starting case final pending?) {
      await pending;
      if (_foreground && enabled && !_closed && _server == null) await start();
      return;
    }
    final task = _start();
    _starting = task;
    try {
      await task;
    } finally {
      if (identical(_starting, task)) _starting = null;
    }
  }

  Future<void> _start() async {
    if (_closed || !_foreground || !enabled || _server != null) return;
    _observe();
    final epoch = ++_epoch;
    try {
      await handoff.initializeStorage();
      _pairings ??= await pairings.read();
      if (_closed || epoch != _epoch) return;
      var key = _pairings!['key'] as String?;
      key ??= _newLanKey();
      await _saveConfiguration(
        (value) => {
          ...value,
          'key': key,
          'device': value['device'] ?? newLanDeviceId(),
        },
      );
      if (_closed || epoch != _epoch) return;
      _pairings!['key'] = key;
      librarySync ??= LibraryIncrementalSync(
        actor: deviceId!,
        state: state,
        preferences: preferences,
        books: books,
      )..addListener(_notify);
      await librarySync!.initialize();
      if (_closed || epoch != _epoch) return;
      final server = await HttpServer.bind(
        address ?? InternetAddress.anyIPv4,
        port,
        shared: false,
      );
      if (_closed || epoch != _epoch) {
        await server.close(force: true);
        return;
      }
      _server = server;
      _serverKey = key;
      _cipher = LanSyncCipher(key);
      hosts = address?.isLoopback == true
          ? [address!.address]
          : [
              for (final interface in await NetworkInterface.list(
                type: InternetAddressType.IPv4,
              ))
                for (final a in interface.addresses)
                  if (isPrivateLanAddress(a) && !a.isLoopback) a.address,
            ];
      if (_closed || epoch != _epoch) return;
      server.listen((request) => unawaited(_handle(request)), onError: (_) {});
      _client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4)
        ..findProxy = (_) => 'DIRECT';
      _poll = Timer.periodic(
        const Duration(seconds: 15),
        (_) => unawaited(sync()),
      );
      _discoveryChanges ??= discovery.changes.listen(
        (devices) => unawaited(_discovered(devices)),
      );
      await discovery.start(deviceId!, server.port);
      if (_closed || epoch != _epoch) return;
      error = null;
      _notify();
      unawaited(sync());
    } catch (_) {
      if (_closed || epoch != _epoch) return;
      await stop();
      error = '局域网同步未启动，请检查 Wi-Fi 和本机网络权限后重试';
      _notify();
    }
  }

  Future<void> stop() async {
    _epoch++;
    handoff.stop();
    _poll?.cancel();
    _poll = null;
    _libraryDebounce?.cancel();
    _libraryDebounce = null;
    _client?.close(force: true);
    _client = null;
    final server = _server;
    _server = null;
    _cipher = null;
    _incomingCiphers.clear();
    for (final pair in _sessions.values) {
      pair.poll?.cancel();
      pair.expiry?.cancel();
    }
    _sessions.clear();
    _pendingPair = null;
    nearby = const [];
    for (final offer in _offers.values) {
      offer.expiry?.cancel();
    }
    _offers.clear();
    await discovery.stop();
    await server?.close(force: true);
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      unawaited(start());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      unawaited(stop());
    }
  }

  String? _identity(int id) =>
      isLocalBook(id) ? books?.readingIdentity(id) : 'wenku8:$id';
  Novel? _book(int id) => books?.book(id) ?? state.cachedNovel(id);
  Map<String, dynamic> _records() => {
    for (final e in state.readingPositions.entries)
      ?_identity(e.key): e.value.toJson(),
  };
  Map<String, Novel> _knownBooks() => {
    for (final id in {
      ...state.readingPositions.keys,
      ...state.shelf,
      ...?books?.books.map((b) => b.id),
    })
      ?_identity(id): ?_book(id),
  };
  Future<int> _merge(Object? raw) async {
    if (raw is! Map || raw.length > 10000) {
      throw const FormatException('同步记录数量有误');
    }
    final known = _knownBooks();
    final updates = <Novel, ReadingPosition>{};
    for (final e in raw.entries) {
      final book = known[e.key];
      if (book == null || e.value is! Map) continue;
      final position = ReadingPosition.fromJson(
        Map<String, dynamic>.from(e.value),
      );
      if (position.updatedAt > DateTime.now().millisecondsSinceEpoch + 300000) {
        continue;
      }
      updates[book] = position;
    }
    return state.mergeLanPositions(updates);
  }

  Future<String> _read(
    Stream<List<int>> stream, {
    int maximum = 4 * 1024 * 1024,
  }) async {
    final bytes = <int>[];
    await for (final chunk in stream.timeout(const Duration(seconds: 8))) {
      if (bytes.length + chunk.length > maximum) {
        throw const FormatException('同步数据过大');
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  Future<void> _saveConfiguration(
    Map<String, dynamic> Function(Map<String, dynamic>) change,
  ) {
    final work = _configurationWrites.catchError((Object _) {}).then((_) async {
      final current = _pairings ?? await pairings.read();
      final next = change(current);
      await pairings.write(next);
      _pairings = next;
    });
    _configurationWrites = work;
    return work;
  }

  Future<void> _rememberPeer(LanPeer peer) async {
    await _saveConfiguration((current) {
      final values =
          [
            for (final raw in current['peers'] as List? ?? const [])
              ?_validPeer(raw),
          ]..removeWhere(
            (p) => peer.deviceId != null
                ? p.deviceId == peer.deviceId
                : p.addressKey == peer.addressKey,
          );
      if (values.length >= 8) throw const FormatException('最多配对 8 台设备，请先解除旧配对');
      return {
        ...current,
        'peers': [...values.map((p) => p.toRecord()), peer.toRecord()],
      };
    });
    _incomingCiphers.remove(peer.deviceId);
  }

  bool _validDevice(LanNearbyDevice device) {
    final address = InternetAddress.tryParse(device.host);
    return device.id != deviceId &&
        RegExp(r'^[a-f0-9]{32}$').hasMatch(device.id) &&
        device.name.isNotEmpty &&
        device.name.length <= 64 &&
        device.port >= 1024 &&
        device.port <= 65535 &&
        address != null &&
        isPrivateLanAddress(address);
  }

  Future<void> _discovered(List<LanNearbyDevice> values) async {
    if (_closed || _server == null || !_foreground) return;
    final epoch = _epoch;
    nearby = [
      for (final device in values.take(64))
        if (_validDevice(device)) device,
    ];
    _notify();
    for (final device in nearby) {
      final peer = peers.where((p) => p.deviceId == device.id).firstOrNull;
      if (peer == null ||
          peer.host == device.host && peer.port == device.port) {
        continue;
      }
      try {
        await _rememberPeer(
          LanPeer(
            device.host,
            device.port,
            peer.key,
            deviceId: peer.deviceId,
            name: peer.name,
          ),
        );
        if (_closed || epoch != _epoch) return;
        _sent.clear();
        _peerKnown.clear();
      } catch (_) {
        error = '设备地址已变化，但连接信息未能保存，请重试';
        _notify();
        return;
      }
    }
    if (!_closed && epoch == _epoch) unawaited(sync());
  }

  Future<void> refreshDiscovery() async {
    await start();
    if (_server case final server?) {
      await discovery.stop();
      if (_server != null && !_closed) {
        await discovery.start(deviceId!, server.port);
      }
      _notify();
    }
  }

  Future<Map<String, dynamic>> _postPair(
    LanPeer peer,
    String path,
    String body, {
    String? session,
  }) async {
    final client = _client;
    if (client == null || _server == null || _closed) {
      throw const FormatException('请先开启局域网续读');
    }
    final request = await client.postUrl(
      Uri(scheme: 'http', host: peer.host, port: peer.port, path: path),
    );
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    if (session != null) request.headers.set('X-Wenku-Pair', session);
    request.write(body);
    final response = await request.close().timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw const FormatException('未能连接，请让另一台设备打开局域网续读页后重试');
    }
    final value = jsonDecode(await _read(response, maximum: 8192));
    if (value is! Map<String, dynamic>) throw const FormatException('设备配对回复无效');
    return value;
  }

  void _registerPairing(_NearbyPairing pair) {
    if (_pendingPair != null &&
        !_pendingPair!.completed &&
        !_pendingPair!.cancelled) {
      throw const FormatException('请先完成或取消当前配对');
    }
    _pendingPair = pair;
    _sessions[pair.offer.session] = pair;
    pair.expiry = Timer(const Duration(seconds: 90), () {
      _sessions.remove(pair.offer.session);
      pair.poll?.cancel();
      if (identical(_pendingPair, pair)) {
        _pendingPair = null;
        if (!pair.completed && !pair.cancelled) error = '配对已超时，请重新连接';
        _notify();
      }
    });
    error = null;
    _notify();
  }

  Future<void> pairNearby(LanNearbyDevice device) async {
    if (!_validDevice(device) ||
        _pairingScreens == 0 ||
        _server == null ||
        pendingPairing != null) {
      throw const FormatException('请在局域网续读页选择另一台设备');
    }
    final epoch = _epoch;
    final handshake = await LanPairHandshake.create(
      device: deviceId!,
      name: deviceName,
      port: _server!.port,
    );
    final endpoint = LanPeer(device.host, device.port, '');
    final commit = LanPairCommit.fromJson(
      await _postPair(
        endpoint,
        '/pair/offer',
        jsonEncode((await handshake.commit()).toJson()),
      ),
    );
    if (commit.device != device.id ||
        commit.session != handshake.offer.session) {
      throw const FormatException('设备身份已改变，请重新发现');
    }
    final remote = LanPairOffer.fromJson(
      await _postPair(
        endpoint,
        '/pair/reveal',
        jsonEncode(handshake.offer.toJson()),
      ),
    );
    if (!await commit.matches(remote)) {
      throw const FormatException('配对信息不一致，请重新连接');
    }
    final agreed = await handshake.agree(remote, initiator: true);
    if (_closed || epoch != _epoch || _pairingScreens == 0) return;
    _registerPairing(
      _NearbyPairing(
        handshake.offer,
        LanPeer(
          device.host,
          remote.port,
          agreed.key,
          deviceId: remote.device,
          name: remote.name,
        ),
        agreed.digits,
      ),
    );
  }

  Future<void> _handlePairing(HttpRequest request) async {
    final epoch = _epoch, host = request.connectionInfo!.remoteAddress.address;
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('Cache-Control', 'no-store');
    if (request.uri.path == '/pair/offer') {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_pairingScreens == 0 ||
          pendingPairing != null ||
          _offers.length >= 2 ||
          now - _lastOffer < 1500) {
        request.response.statusCode = 409;
        return;
      }
      _lastOffer = now;
      final remote = LanPairCommit.fromJson(
        jsonDecode(await _read(request, maximum: 4096)),
      );
      if (remote.device == deviceId) throw const FormatException('不能连接本机');
      final handshake = await LanPairHandshake.create(
        device: deviceId!,
        name: deviceName,
        port: _server!.port,
        session: remote.session,
      );
      if (_closed || epoch != _epoch || _pairingScreens == 0) return;
      if (_offers.containsKey(remote.session)) {
        throw const FormatException('重复的配对请求');
      }
      final reservation = _NearbyReservation(handshake, remote, host);
      _offers[remote.session] = reservation;
      reservation.expiry = Timer(
        const Duration(seconds: 10),
        () => _offers.remove(remote.session),
      );
      request.response.write(jsonEncode((await handshake.commit()).toJson()));
      return;
    }
    if (request.uri.path == '/pair/reveal') {
      final remote = LanPairOffer.fromJson(
        jsonDecode(await _read(request, maximum: 4096)),
      );
      final offer = _offers.remove(remote.session);
      offer?.expiry?.cancel();
      if (offer == null ||
          offer.host != host ||
          _pairingScreens == 0 ||
          !await offer.remote.matches(remote)) {
        throw const FormatException('配对承诺不匹配');
      }
      final agreed = await offer.handshake.agree(remote, initiator: false);
      if (_closed || epoch != _epoch || _pairingScreens == 0) return;
      _registerPairing(
        _NearbyPairing(
          offer.handshake.offer,
          LanPeer(
            host,
            remote.port,
            agreed.key,
            deviceId: remote.device,
            name: remote.name,
          ),
          agreed.digits,
        ),
      );
      request.response.write(jsonEncode(offer.handshake.offer.toJson()));
      return;
    }
    final pair = _sessions[request.headers.value('X-Wenku-Pair')];
    if (pair == null || pair.peer.host != host) {
      throw const FormatException('配对请求已过期');
    }
    final incoming = await pair.cipher.open(
      await _read(request, maximum: 8192),
      'pair-confirm',
    );
    if (incoming['session'] != pair.offer.session ||
        incoming['device'] != pair.peer.deviceId ||
        incoming['accepted'] != true) {
      throw const FormatException('配对确认无效');
    }
    if (_closed || epoch != _epoch) return;
    pair.remoteAccepted = true;
    if (pair.accepted && !pair.cancelled) await _completePairing(pair);
    request.response.write(
      await pair.cipher.seal({
        'at': DateTime.now().millisecondsSinceEpoch,
        'session': pair.offer.session,
        'device': deviceId,
        'accepted': pair.accepted && !pair.cancelled,
        'cancelled': pair.cancelled,
      }, 'pair-confirm-response'),
    );
  }

  Future<void> _completePairing(_NearbyPairing pair) async {
    if (pair.completed || pair.cancelled) return;
    final save = pair.saving ??= _rememberPeer(pair.peer);
    try {
      await save;
    } catch (_) {
      pair.saving = null;
      rethrow;
    }
    pair.completed = true;
    pair.poll?.cancel();
    if (identical(_pendingPair, pair)) _pendingPair = null;
    _sent.clear();
    _peerKnown.clear();
    error = null;
    _notify();
    unawaited(sync());
  }

  Future<void> confirmPairing() async {
    final pair = _pendingPair;
    if (pair == null || pair.cancelled || pair.completed) return;
    pair.accepted = true;
    _notify();
    await _confirmPairing(pair);
    if (!pair.completed && !pair.cancelled) {
      pair.poll ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_confirmPairing(pair)),
      );
    }
  }

  Future<void> _confirmPairing(_NearbyPairing pair) async {
    if (pair.polling ||
        pair.completed ||
        pair.cancelled ||
        _server == null ||
        _closed) {
      return;
    }
    pair.polling = true;
    final epoch = _epoch;
    try {
      final raw = await _postPair(
        pair.peer,
        '/pair/confirm',
        await pair.cipher.seal({
          'at': DateTime.now().millisecondsSinceEpoch,
          'session': pair.offer.session,
          'device': deviceId,
          'accepted': true,
        }, 'pair-confirm'),
        session: pair.offer.session,
      );
      final reply = await pair.cipher.open(
        jsonEncode(raw),
        'pair-confirm-response',
      );
      if (_closed || epoch != _epoch || pair.cancelled) return;
      if (reply['session'] != pair.offer.session ||
          reply['device'] != pair.peer.deviceId) {
        throw const FormatException('配对确认不匹配');
      }
      if (reply['cancelled'] == true) {
        cancelPairing();
        error = '另一台设备取消了连接';
        _notify();
        return;
      }
      if (reply['accepted'] == true) {
        pair.remoteAccepted = true;
        await _completePairing(pair);
      }
    } catch (_) {
      if (!_closed && epoch == _epoch && !pair.cancelled) {
        error = '等待另一台设备确认，连接中断时可取消后重试';
        _notify();
      }
    } finally {
      pair.polling = false;
    }
  }

  void cancelPairing() {
    final pair = _pendingPair;
    if (pair == null) return;
    pair.cancelled = true;
    pair.poll?.cancel();
    _pendingPair = null;
    _notify();
  }

  Future<void> _handle(HttpRequest request) async {
    final epoch = _epoch;
    if (_requests >= 3) {
      request.response.statusCode = 429;
      try {
        await request.response.close();
      } on IOException {
        /* cancelled peer */
      }
      return;
    }
    _requests++;
    try {
      if (request.method != 'POST' ||
          request.connectionInfo?.remoteAddress == null ||
          !isPrivateLanAddress(request.connectionInfo!.remoteAddress) ||
          _cipher == null) {
        request.response.statusCode = 404;
        return;
      }
      if (const [
        '/pair/offer',
        '/pair/reveal',
        '/pair/confirm',
      ].contains(request.uri.path)) {
        await _handlePairing(request);
        return;
      }
      final sender = request.headers.value('X-Wenku-Peer');
      LanSyncCipher? cipher = _cipher;
      if (sender != null) {
        final peer = peers.where((p) => p.deviceId == sender).firstOrNull;
        if (peer == null) {
          request.response.statusCode = 403;
          return;
        }
        cipher = _incomingCiphers[sender];
        if (cipher?.encodedKey != peer.key) {
          cipher = LanSyncCipher(peer.key);
          _incomingCiphers[sender] = cipher;
        }
      }
      if (cipher == null) {
        request.response.statusCode = 403;
        return;
      }
      if (request.uri.path.startsWith('/handoff/')) {
        await handoff.handle(request, cipher, sender);
        return;
      }
      if (request.uri.path != '/sync') {
        request.response.statusCode = 404;
        return;
      }
      final incoming = await cipher.open(await _read(request), 'request');
      if (_closed || epoch != _epoch) return;
      await _merge(incoming['records']);
      await librarySync?.receive(incoming['library']);
      final versions = incoming['versions'] is Map
          ? incoming['versions'] as Map
          : const {};
      final records = _records()
        ..removeWhere(
          (key, value) =>
              versions[key] is int && versions[key] >= value['updatedAt'],
        );
      final response = await cipher.seal({
        'at': DateTime.now().millisecondsSinceEpoch,
        'replyTo': incoming['id'],
        'records': records,
        'known': _knownBooks().keys.toList(),
        'versions': {
          for (final e in _records().entries) e.key: e.value['updatedAt'],
        },
        if (incoming['library'] is Map)
          'library': await librarySync!.packet(
            (incoming['library'] as Map)['versions'],
          ),
      }, 'response');
      request.response.headers.contentType = ContentType.json;
      request.response.headers.set('Cache-Control', 'no-store');
      request.response.write(response);
      lastSync = DateTime.now().millisecondsSinceEpoch;
      error = null;
      _notify();
    } catch (_) {
      request.response.statusCode = 403;
    } finally {
      _requests--;
      try {
        await request.response.close();
      } on IOException {
        // The peer or foreground lifecycle may have closed the socket first.
      }
    }
  }

  final _sent = <String, Map<String, int>>{};
  final _peerKnown = <String, Set<String>>{};
  Future<void> sync() async {
    final client = _client;
    if (_closed || _busy || client == null) return;
    _busy = true;
    final epoch = _epoch;
    try {
      var failed = 0;
      for (final peer in peers) {
        if (_closed || epoch != _epoch) return;
        try {
          final records = _records(),
              previous = _sent[peer.addressKey] ?? const {};
          final versions = {
            for (final e in records.entries)
              e.key: (e.value as Map)['updatedAt'],
          };
          final delta = {...records}
            ..removeWhere((key, value) => previous[key] == value['updatedAt']);
          if (_peerKnown[peer.addressKey] case final known?) {
            delta.removeWhere((key, _) => !known.contains(key));
          }
          final cipher = LanSyncCipher(peer.key), id = _newLanKey();
          final library = await librarySync!.packet(
            _libraryVersions[peer.addressKey],
          );
          final request = await client.postUrl(
            Uri(
              scheme: 'http',
              host: peer.host,
              port: peer.port,
              path: '/sync',
            ),
          );
          request.followRedirects = false;
          if (peer.deviceId != null) {
            request.headers.set('X-Wenku-Peer', deviceId!);
          }
          request.headers.contentType = ContentType.json;
          request.write(
            await cipher.seal({
              'at': DateTime.now().millisecondsSinceEpoch,
              'id': id,
              'records': delta,
              'versions': versions,
              'library': library,
            }, 'request'),
          );
          final response = await request.close().timeout(
            const Duration(seconds: 10),
          );
          if (response.statusCode != 200) {
            throw const FormatException('设备未接受配对');
          }
          final incoming = await cipher.open(await _read(response), 'response');
          if (_closed || epoch != _epoch) return;
          if (incoming['replyTo'] != id) throw const FormatException('同步回复不匹配');
          await _merge(incoming['records']);
          await librarySync?.receive(incoming['library']);
          if (incoming['library'] case final Map libraryReply) {
            _libraryVersions[peer.addressKey] = libraryReply['versions'];
            // Finish bounded pages (including the byte-size limit), then send
            // one empty acknowledgment. Steady-state polling stays unchanged.
            if ((libraryReply['records'] as Map).isNotEmpty ||
                (library['records'] as Map).isNotEmpty) {
              _libraryChanged();
            }
          }
          final known = incoming['known'];
          if (known is List && known.every((k) => k is String)) {
            _peerKnown[peer.addressKey] = known.cast<String>().toSet();
          }
          final acknowledged = incoming['versions'];
          _sent[peer.addressKey] = {
            for (final e in versions.entries)
              if (acknowledged is Map &&
                  acknowledged[e.key] is int &&
                  acknowledged[e.key] >= e.value)
                e.key: e.value as int,
          };
          lastSync = DateTime.now().millisecondsSinceEpoch;
        } catch (_) {
          if (_closed || epoch != _epoch) return;
          failed++;
        }
      }
      error = failed == 0
          ? null
          : '$failed 台设备暂未连接；其他设备仍正常同步，请确认双方同一 Wi-Fi 且 App 位于前台';
    } catch (_) {
      if (!_closed && epoch == _epoch) {
        error = '暂未连上已配对设备，请确认双方在同一 Wi-Fi 且 App 位于前台';
      }
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> pair(String code) async {
    final peer = LanPeer.parse(code);
    await _rememberPeer(peer);
    _sent.clear();
    _peerKnown.clear();
    _libraryVersions.clear();
    _notify();
    await sync();
  }

  Future<void> forget() async {
    await stop();
    await _saveConfiguration(
      (value) => {
        'peers': <String>[],
        'key': _newLanKey(),
        'device': value['device'] ?? newLanDeviceId(),
      },
    );
    _sent.clear();
    _peerKnown.clear();
    _libraryVersions.clear();
    if (enabled) await start();
    _notify();
  }

  @override
  void dispose() {
    _closed = true;
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    state.bookmarkChanges.removeListener(_libraryChanged);
    state.organization.removeListener(_libraryChanged);
    librarySync?.removeListener(_notify);
    librarySync?.dispose();
    unawaited(stop());
    unawaited(_discoveryChanges?.cancel());
    handoff.dispose();
    discovery.dispose();
    super.dispose();
  }
}

class LanSyncScope extends InheritedWidget {
  const LanSyncScope({super.key, required this.sync, required super.child});
  final LanReadingSync? sync;
  static LanReadingSync? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LanSyncScope>()?.sync;
  @override
  bool updateShouldNotify(LanSyncScope oldWidget) => oldWidget.sync != sync;
}
