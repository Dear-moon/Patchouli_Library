/// A Legado image locator may end in `,{...}` request options. Validate the
/// address without URI-normalizing the options or losing header/decode rules.
bool validSourceImageLocator(String raw) {
  if (raw.startsWith('source-epub:')) {
    final local = Uri.tryParse(raw);
    if (local == null) return false;
    return RegExp(r'^[a-f0-9]{64}$').hasMatch(local.host) &&
        local.userInfo.isEmpty &&
        !local.hasPort &&
        !local.hasQuery &&
        !local.hasFragment &&
        RegExp(
          r'^/(?:cover|img-[0-9]+)\.(?:png|jpe?g|webp|gif)$',
        ).hasMatch(local.path);
  }
  if (raw.startsWith('data:image/')) {
    return raw.length <= 12 * 1024 * 1024 &&
        RegExp(
          r'^data:image/(?:png|jpe?g|webp|gif|bmp|avif);base64,[a-z0-9+/=\s]+$',
          caseSensitive: false,
        ).hasMatch(raw);
  }
  final address = raw.split(RegExp(r'\s*,\s*(?=\{)')).first.trim();
  final uri = Uri.tryParse(address);
  return uri != null &&
      ['http', 'https'].contains(uri.scheme) &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}

String? sourceImageLocator(int bookId, String raw, {String referrer = ''}) {
  if (bookId <= 0 || !validSourceImageLocator(raw)) return null;
  return Uri(
    scheme: 'source-image',
    host: '$bookId',
    path: '/',
    queryParameters: {'url': raw, 'ref': referrer},
  ).toString();
}
