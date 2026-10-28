# Pinned Legado JavaScript runtime

The unmodified `org.htmlunit:htmlunit-core-js:5.3.0-legado.4` binary and POM
are copied from LegadoTeam/legado commit
`3046111c1718e7b67c2ad468e54edf295ec05820`, under `third_party/maven/`.
Android resolves only this module from that local repository.

The upstream `SOURCE.md` alongside the JAR identifies its complete sources:

- Packaging: mgz0227/htmlunit-core-js,
  `3eb5071cdca4a357119d1063a53d5f2d47984ed2`.
- Rhino fork: mgz0227/htmlunit-rhino-fork,
  `76460c0312bfd351df6f2bb11168102cdb54170a`.

Their corresponding unmodified source archives are in `sources/`. Build with
the command recorded in that `SOURCE.md`. Original licenses, notices, patch
descriptions and source identity are retained in
`assets/licenses/htmlunit-core-js/` and concatenated into the app's license
registry entry `assets/licenses/htmlunit-core-js.txt`.

The same pinned Legado revision supplies the E4X implementation under
`android/app/src/main/java/org/htmlunit/corejs/javascript/xmlimpl/`.
`legado/runtime/RhinoContext.kt` adapts its legacy let/const normalization and
XML loader; only the package and cancellation/presentation integration differ.
See `third_party/legado/README.md` for the GPL-3.0 integration notice.
