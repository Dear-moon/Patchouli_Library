# Novel script host dependencies

The host targets Legado `3.26082823`, commit
`3046111c1718e7b67c2ad468e54edf295ec05820` (GPL-3.0).

- `SourceLocks`, shared script bindings and `ConcurrentNativeObject` adapt its
  SourceLock / ScriptBindings / SharedJsScope. No Android or JVM package loader
  is exposed to source scripts. Library definitions are shared by definition;
  explicit global state is isolated by source. Execution bindings are not retained
  in shared roots. `this.java` / indirect eval use the current entry's bindings,
  as in that runtime; lexical free variables in library functions are not rewritten.
- `SourceChinese` adapts ChineseUtils and its dictionary corrections. The
  unmodified `quick-transfer-core:0.2.17` dependency comes from
  [liuyueyi/quick-chinese-transfer](https://github.com/liuyueyi/quick-chinese-transfer/tree/810e881ce722e7919ad00f283551e897bf7aad77).
  Its pinned POM declares Apache-2.0; a copy is retained here. Author: YiHui.
- The eight ICU charset detector Java files originate in that Legado revision's
  `lib/icu4j`. Only their package was relocated to `sourceinternal/icu4j`.
  IBM/Unicode notices remain in the files; the complete ICU 58 license and
  legacy ICU notice are included in `licenses/icu.txt` and the app license asset.
- `me.zhanghai.android.libarchive:library:1.1.6` is unmodified and is the same
  JNI decoder version used by the target. Wrapper: Apache-2.0, zhanghai / Google.
  [Source](https://github.com/zhanghai/libarchive-android/tree/v1.1.6).
  Native components are pinned by that tag's git submodules:

| Component | Commit | License |
| --- | --- | --- |
| libarchive | 9525f90ca4bd14c7b335e2f8c84a4607b0af6bdf | BSD-2-Clause and file notices |
| bzip2 | 6a8690fc8d26c815e798c588f796eabe9d684cf0 | bzip2 license |
| liblzma | a522a226545730551f7e7c2685fab27cf567746c | 0BSD |
| lz4 | ebb370ca83af193212df4dcbadcc5d87bc0de2f0 | BSD-2-Clause |
| zstd | f8745da6ff1ad1e7bab384bd1f9d742439278e99 | BSD-3-Clause option |
| mbedcrypto | 2fc8413bfcb51354c8e679141b17b3f1a5942561 | Apache-2.0 |

Platform zlib uses the Android NDK static library. Source and notices:
<https://android.googlesource.com/platform/external/zlib/>.
`licenses/` retains the dependency notices and full license texts.

Material Components `1.14.0` (Google, Apache-2.0) provides the optional script
browser's Android bottom-sheet behavior. It does not replace app widgets or
change their animation. [Source](https://github.com/material-components/material-components-android/tree/1.14.0).

The self-authored ZIP/7z and captcha fixtures and the separately compiled original
selector comparison classes are test-only. RAR4/RAR5 fixture archives originate
in libarchive `v3.8.1`'s `libarchive/test/test_read_format_rar.rar.uu` and
`test_read_format_rar5_stored.rar.uu`, under the libarchive BSD notice. They are
included only when `wenkuSourceProbe=true`, never in the normal preview/package.
