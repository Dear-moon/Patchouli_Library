import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

String newLanDeviceId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class LanPairOffer {
  const LanPairOffer({
    required this.session,
    required this.device,
    required this.name,
    required this.port,
    required this.publicKey,
    required this.nonce,
  });
  final String session, device, name, publicKey, nonce;
  final int port;
  Map<String, dynamic> toJson() => {
    'session': session,
    'device': device,
    'name': name,
    'port': port,
    'public': publicKey,
    'nonce': nonce,
  };
  factory LanPairOffer.fromJson(Object? value) {
    if (value is! Map ||
        value['session'] is! String ||
        value['device'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(value['session']) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(value['device']) ||
        value['name'] is! String ||
        (value['name'] as String).isEmpty ||
        (value['name'] as String).length > 64 ||
        value['port'] is! int ||
        value['port'] < 1024 ||
        value['port'] > 65535 ||
        value['public'] is! String ||
        value['nonce'] is! String ||
        base64Url.decode(value['public']).length != 32 ||
        base64Url.decode(value['nonce']).length != 32) {
      throw const FormatException('设备配对信息无效');
    }
    return LanPairOffer(
      session: value['session'],
      device: value['device'],
      name: value['name'],
      port: value['port'],
      publicKey: value['public'],
      nonce: value['nonce'],
    );
  }
}

class LanPairCommit {
  const LanPairCommit(
    this.session,
    this.device,
    this.name,
    this.port,
    this.commitment,
  );
  final String session, device, name, commitment;
  final int port;
  Map<String, dynamic> toJson() => {
    'session': session,
    'device': device,
    'name': name,
    'port': port,
    'commitment': commitment,
  };
  factory LanPairCommit.fromJson(Object? value) {
    if (value is! Map ||
        value['commitment'] is! String ||
        base64Url.decode(value['commitment']).length != 32) {
      throw const FormatException('设备配对承诺无效');
    }
    // Apply the same identity/length bounds without revealing either public key.
    final bounded = LanPairOffer.fromJson({
      ...value,
      'public': base64Url.encode(List.filled(32, 0)),
      'nonce': base64Url.encode(List.filled(32, 0)),
    });
    return LanPairCommit(
      bounded.session,
      bounded.device,
      bounded.name,
      bounded.port,
      value['commitment'],
    );
  }
  Future<bool> matches(LanPairOffer offer) async =>
      session == offer.session &&
      device == offer.device &&
      name == offer.name &&
      port == offer.port &&
      commitment ==
          base64Url.encode(
            (await Sha256().hash(
              utf8.encode(jsonEncode(offer.toJson())),
            )).bytes,
          );
}

/// Fresh X25519 agreement. Human confirmation authenticates the six-digit SAS;
/// neither a discoverable device name nor its mDNS address is trusted alone.
class LanPairHandshake {
  LanPairHandshake._(this.offer, this._key);
  final LanPairOffer offer;
  final SimpleKeyPair _key;
  static Future<LanPairHandshake> create({
    required String device,
    required String name,
    required int port,
    String? session,
  }) async {
    final key = await X25519().newKeyPair();
    final random = Random.secure();
    final nonce = List.generate(32, (_) => random.nextInt(256));
    return LanPairHandshake._(
      LanPairOffer(
        session: session ?? newLanDeviceId(),
        device: device,
        name: name,
        port: port,
        publicKey: base64Url.encode((await key.extractPublicKey()).bytes),
        nonce: base64Url.encode(nonce),
      ),
      key,
    );
  }

  Future<LanPairCommit> commit() async => LanPairCommit(
    offer.session,
    offer.device,
    offer.name,
    offer.port,
    base64Url.encode(
      (await Sha256().hash(utf8.encode(jsonEncode(offer.toJson())))).bytes,
    ),
  );
  Future<({String key, String digits})> agree(
    LanPairOffer remote, {
    required bool initiator,
  }) async {
    if (offer.session != remote.session || offer.device == remote.device) {
      throw const FormatException('配对请求已改变，请重新连接');
    }
    final shared = await X25519().sharedSecretKey(
      keyPair: _key,
      remotePublicKey: SimplePublicKey(
        base64Url.decode(remote.publicKey),
        type: KeyPairType.x25519,
      ),
    );
    if ((await shared.extractBytes()).every((v) => v == 0)) {
      throw const FormatException('设备配对密钥无效');
    }
    final transcript = utf8.encode(
      jsonEncode(
        initiator
            ? [offer.toJson(), remote.toJson()]
            : [remote.toJson(), offer.toJson()],
      ),
    );
    final salt = await Sha256().hash(transcript);
    final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: shared,
      nonce: salt.bytes,
      info: utf8.encode('wenku-nearby-pair-v1'),
    );
    final mac = await Hmac.sha256().calculateMac([
      ...utf8.encode('verify:'),
      ...transcript,
    ], secretKey: key);
    final number =
        ((mac.bytes[0] & 0x7f) << 24) |
        (mac.bytes[1] << 16) |
        (mac.bytes[2] << 8) |
        mac.bytes[3];
    return (
      key: base64Url.encode(await key.extractBytes()),
      digits: (number % 1000000).toString().padLeft(6, '0'),
    );
  }
}
