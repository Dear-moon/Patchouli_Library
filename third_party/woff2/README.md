# WOFF2 decoder

Adapted from `woff2` 0.1.0, Apache-2.0:
https://github.com/denisnadey/flutter_full_svg_support/tree/main/packages/woff2

Only the SFNT decoder is included. Brotli uses the portable Dart decoder so
Android does not require unbundled desktop FFI compression libraries.
