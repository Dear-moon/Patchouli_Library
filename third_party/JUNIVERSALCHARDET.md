# juniversalchardet 2.0.4

- Upstream: <https://github.com/albfernandez/juniversalchardet/tree/v2.0.4>
- Original release source: <https://codeload.github.com/albfernandez/juniversalchardet/tar.gz/refs/tags/v2.0.4>
- Maven dependency: `com.github.albfernandez:juniversalchardet:2.0.4`.
- The unmodified release source, build configuration, tests and original notices
  are retained in `third_party/juniversalchardet-2.0.4/` and included by
  `tools/export_public_source.py`. It has no runtime dependencies.
- Copyright 2016–2017 Alberto Fernández, 2006–2007 Kohei Taketa (Java port),
  2001 Netscape Communications Corporation; individual files retain their notices.
- Upstream offers MPL 1.1, GPL 2.0-or-later or LGPL 2.1-or-later. This distribution
  selects the MPL 1.1 option without removing the upstream alternatives. The
  complete unmodified source and build files remain in the directory above.
  The original notice and MPL text are also supplied in
  `assets/licenses/juniversalchardet.txt`.

Only legacy TXT encoding identification uses this library, after strict UTF-8
decoding fails. The app samples at most 64 KiB rather than asking the detector to
read an entire book. The 2.0 release line is retained for older Android versions.
