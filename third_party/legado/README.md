# Legado rule engine adaptation

Upstream: [LegadoTeam/legado](https://github.com/LegadoTeam/legado), tag
`3.26082823`, commit `3046111c1718e7b67c2ad468e54edf295ec05820`.
Authors: gedoor and the Legado contributors. License: GPL-3.0; the complete
upstream license is retained alongside this file.

`android/app/src/main/kotlin/org/mewx/wenku8_flutter/legado/` contains the
upstream `RuleAnalyzer`, `AnalyzeByJSoup`, `AnalyzeByJSonPath`,
`AnalyzeByXPath`, `AnalyzeByRegex`, and the extraction/`SourceRule` parts of
`AnalyzeRule`. This is adapted source, not an independent compatible parser.

`legado/login/LoginUiV2.kt` and `RowUi.kt` reuse the upstream login protocol,
including validation, command parsing and value precedence. `legado/js/`
reuses `JsSourceMarshaller` for script-returned search results, book details
and chapters. The native engine connects the upstream JS entry-point contract
to its existing isolated Rhino runtime. The upstream LoginUiV2 tests are
retained under the matching native test package.

`legado/book/BookInfo.kt` adapts the upstream text-book detail operation: init,
name/author rename rules, optional-field failure handling, field order, intro
and word-count formatting. Android entities/coroutines/logging are replaced by
maps, SourceRun checks and safe field warnings; source scripts are not edited.
Its small formatting helpers originate in BookHelp, HtmlFormatter and StringUtils.
`legado/js/SourceGson.kt` retains INITIAL_GSON's string/integer/map adapters and
number/escaping configuration from upstream GsonExtensions.kt; Android rule-entity
adapters are omitted because this host keeps declarative rules as original maps.

Changes made on 2026-10-18:

- Relocated the package and replaced app-specific Android entities, logging,
  coroutine state and script bindings with `RuleHost`.
- Kept selector splitting, default/JSoup indexing, combination/interleaving,
  JSONPath/XPath, capture groups, variable templates and regex replacement.
- Replaced `TextUtils` with the equivalent Kotlin string operations, and
  the Kotlin `when` guard with an equivalent ordinary branch.
- Added cancellation/budget checks at parsing entry points. No source URLs,
  credentials, response bodies or script contents are written to app logs.
- Login protocol changes are limited to package/Gson helpers and a Flutter row
  model; Android view styling is rendered by the shared Flutter components.
- JS marshaller changes replace Room entities, app logging and URL helpers with
  app-independent adapters. Existing book/chapter IDs are owned by SourceStore.
- The Rhino host supplies isolated execution bindings, bounded compiled-script
  reuse and native persistence instead of App/Room. Shared definitions and
  source-isolated explicit globals follow the pinned ScriptBindings model.

The unmodified upstream `cryptojs.min.js` and its MIT license are bundled under
`android/app/src/main/resources/legado/`; the same license is included in the
Flutter license registry. This is a scripting dependency, not a content source.

The native host, network, persistence, source management and Flutter adapter
are maintained by this project. Reusing this parser does not, by itself,
establish compatibility of those host services; conformance tests and the
current implementation status are in `docs/CUSTOM_SOURCES.md`.

The runtime now uses the same pinned `htmlunit-core-js:5.3.0-legado.4` as
this upstream revision, rather than Mozilla Rhino 1.7.15.1. The JAR, POM,
source identity and complete source archives are under `third_party/maven/`
and `third_party/htmlunit-core-js/`. The E4X Java files originate in
`modules/rhino/`; their original notices are retained. Modified on 2026-10-18:
XmlProcessor supports Android JAXP implementations without the optional secure
processing flag, while mandatorily rejecting declarations before parsing,
blocking external entity/URI resolution and using supported security features.
`legado/runtime/RhinoContext.kt` preserves upstream legacy let/const
normalization and XML loading, replacing coroutine cancellation with
SourceRun checks and also loading XML into the safe standard scope.
The host preserves upstream E4X, Java map access, dynamic-default-this and
dynamic-eval-realm feature flags.

The subsequent novel-host pass also adapts `HtmlFormatter.kt` and `JsURL.kt`
directly. `SourceTextHelpers.kt` implements the Base64/EncoderUtils flags without
depending on Android classes in JVM tests. `SourceEntity.kt` adapts the public
BaseBook/BookChapter/RuleDataInterface variable and metadata operations; encrypted
source state and script objects replace Room entities and RuleBigDataHelp.
`SourceResponse.kt` separates StrResponse from Jsoup Connection.Response and
exposes controlled response/header wrappers rather than an HTTP client or live
socket. The JsExtensions/BaseSource/CacheManager host adapter preserves ordered
batch requests, call timeouts, source-context evaluation, remote script text and
cache semantics within the documented execution and storage limits. TOC/content
operation ordering follows BookChapterList/BookContent;
the existing reader image markers and volume-aware chapter identity are retained
at the application boundary.

`android/app/src/main/java/org/mewx/wenku8_flutter/legado/QueryTTF.java` adapts
the same revision's `model/analyzeRule/QueryTTF.java`. It retains public glyph
maps, cmap 0/4/6 parsing and glyph signatures; changes add input/offset/allocation
bounds, cancellation, memoized signatures and safe missing-glyph indices.
`SourceFonts.kt` supplies JsExtensions query/replace semantics, code-point
iteration and a source-isolated four-entry/32 MiB estimated LRU. WOFF/CFF and
cmap format 12 remain outside this pinned decoder's coverage.

`legado/SourceResources.kt` implements relative resources and bounded archive I/O
with a controlled File-shaped facade. Its cache is per source, not the upstream
shared externalCache; it cannot access user books or other sources. RAR4/RAR5/7z
use the same libarchive-android 1.1.6. The pinned ICU detector is relocated, with
IBM/Unicode notices retained; dependency provenance is in `third_party/source-host`.
`SourceWebCapture.kt` and the renderer follow BackstageWebView's full-URL regex
matching and URL-valued sniff result, cache-first and delayed trigger semantics.
`SourceVerification`, locks, shared script bindings, encrypted large variables,
source/entity accessors and the Flutter host bridge adapt the novel host APIs.
File/network access remains controlled rather than exposing arbitrary JVM I/O.
Native-application differences are documented in `docs/CUSTOM_SOURCES.md`.
Test-only original selectors are separately compiled under `io.legado.app` for
same-rule differential checks; the JVM harness replaces only TextUtils.join and
debug logging, without using the adapted parser as its oracle.
