import AVFoundation
import Darwin
import Flutter

struct SpeechHostFailure: LocalizedError {
  let code: String
  let message: String
  var errorDescription: String? { message }
}

/// Match the publication's language, allowing regional voices of that language.
/// ISO aliases mirror the Dart/Android routing policy without substituting a
/// voice from another language when an installed model is missing.
enum SystemSpeechLocale {
  static func normalized(_ tag: String) -> String? {
    guard tag.range(of: "\\A[a-zA-Z]{2,3}(?:-[a-zA-Z0-9]{2,8}){0,4}\\z", options: .regularExpression) != nil else { return nil }
    let parts = tag.split(separator: "-").map(String.init)
    let language: String
    switch parts[0].lowercased() {
    case "chi", "zho": language = "zh"
    case "jpn": language = "ja"
    case "eng": language = "en"
    case "kor": language = "ko"
    case "und": return nil
    case let value: language = value
    }
    return ([language] + Array(parts.dropFirst())).joined(separator: "-")
  }

  static func matches(_ requested: String, _ actual: String) -> Bool {
    guard let requested = normalized(requested), let actual = normalized(actual) else { return false }
    return requested.split(separator: "-").first == actual.split(separator: "-").first
  }
}

struct SystemSpeechRequest {
  let id: String
  let text: String
  let voice: String
  let locale: String?
  let output: URL

  init(_ args: [String: Any], root: URL) throws {
    guard let id = args["requestId"] as? String, id.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil,
          let text = args["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          text.utf16.count <= 1000, let voice = args["voice"] as? String, !voice.isEmpty, voice.utf8.count <= 2048,
          let path = args["path"] as? String else {
      throw SpeechHostFailure(code: "TTS_INPUT", message: "语音文本或缓存位置无效")
    }
    guard [NativeSystemSpeechPlugin.engineID, "@default"].contains(args["engine"] as? String ?? "") else {
      throw SpeechHostFailure(code: "TTS_ENGINE", message: "请选择 iOS 系统朗读引擎")
    }
    guard text.rangeOfCharacter(from: .letters.union(.decimalDigits)) != nil else {
      throw SpeechHostFailure(code: "TTS_CONTENT", message: "这一段没有可朗读的文本")
    }
    self.id = id
    self.text = text
    self.voice = voice
    if let raw = args["locale"], !(raw is NSNull) {
      guard let tag = raw as? String, let normalized = SystemSpeechLocale.normalized(tag) else {
        throw SpeechHostFailure(code: "TTS_INPUT", message: "朗读语言无效")
      }
      locale = normalized
    } else { locale = nil }
    output = try Self.outputURL(path, root: root)
  }

  static func outputURL(_ path: String, root: URL) throws -> URL {
    let candidate = URL(fileURLWithPath: path).standardizedFileURL
    let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
    guard path.hasPrefix("/"), candidate.lastPathComponent.range(of: "^[a-f0-9]{64}\\.wav\\.part$", options: .regularExpression) != nil,
          candidate.deletingLastPathComponent().resolvingSymlinksInPath().path == canonicalRoot.path,
          candidate.resolvingSymlinksInPath().path == canonicalRoot.appendingPathComponent(candidate.lastPathComponent).path else {
      throw SpeechHostFailure(code: "TTS_INPUT", message: "语音缓存位置无效")
    }
    return canonicalRoot.appendingPathComponent(candidate.lastPathComponent)
  }
}

/// A single bounded WAV writer. The synthesizer's buffer callback synchronizes
/// onto this I/O queue: no retained buffer backlog or full-utterance PCM copy.
/// The .part requested by Dart is published only after a readable WAV is closed.
final class SystemSpeechFile {
  private let queue = DispatchQueue(label: "org.mewx.wenku8.speech-file", qos: .userInitiated)
  private let root: URL
  private let output: URL
  private let work: URL
  private var audio: AVAudioFile?
  private var byteCount = 0
  private var duration = 0.0
  private var terminal = false
  private var published = false
  private let maximumBytes: Int

  init(output: URL, root: URL, maximumBytes: Int = 16 * 1024 * 1024) {
    self.root = root
    self.output = output
    self.maximumBytes = maximumBytes
    work = root.appendingPathComponent(".speech-\(UUID().uuidString).wav")
  }

  func consume(_ buffer: AVAudioPCMBuffer) throws -> String? {
    try queue.sync {
      if terminal { return nil }
      if buffer.frameLength == 0 {
        guard audio != nil, byteCount > 100 else {
          throw SpeechHostFailure(code: "TTS_CONTENT", message: "系统音色没有生成有效语音，请重新检测音色")
        }
        audio = nil // Close and finalize the WAV header before publishing.
        let check = try AVAudioFile(forReading: work)
        guard check.length > 0 else {
          throw SpeechHostFailure(code: "TTS_CONTENT", message: "系统音色没有生成有效语音")
        }
        _ = try SystemSpeechRequest.outputURL(output.path, root: root)
        guard Darwin.rename(work.path, output.path) == 0 else {
          throw SpeechHostFailure(code: "TTS_SYNTH", message: "语音缓存无法保存，请检查本机存储空间")
        }
        published = true
        terminal = true
        return output.path
      }
      let format = buffer.format
      guard format.sampleRate.isFinite, format.sampleRate > 0, format.sampleRate <= 192_000,
            format.channelCount > 0, format.channelCount <= 2 else {
        throw SpeechHostFailure(code: "TTS_CONTENT", message: "系统音色返回了不支持的音频格式")
      }
      let bytes = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        .reduce(0) { $0 + Int($1.mDataByteSize) }
      byteCount += bytes
      duration += Double(buffer.frameLength) / format.sampleRate
      guard byteCount <= maximumBytes, duration <= 120 else {
        throw SpeechHostFailure(code: "TTS_CONTENT", message: "这一段语音过长，请重试较短的段落")
      }
      if audio == nil {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        audio = try AVAudioFile(forWriting: work, settings: format.settings,
          commonFormat: format.commonFormat, interleaved: format.isInterleaved)
      }
      guard audio?.processingFormat == format else {
        throw SpeechHostFailure(code: "TTS_CONTENT", message: "系统音色的音频格式发生变化，请重新检测音色")
      }
      try audio!.write(from: buffer)
      return nil
    }
  }

  func close(keepingOutput: Bool, completion: @escaping () -> Void) {
    queue.async {
      self.terminal = true
      self.audio = nil
      try? FileManager.default.removeItem(at: self.work)
      if self.published && !keepingOutput { try? FileManager.default.removeItem(at: self.output) }
      completion()
    }
  }
}

/// Public iOS synthesis writes files only; AudioService/just_audio own playback,
/// pause, seek and 0.5–3x speed. No speak(), microphone or personal-voice prompt.
final class NativeSystemSpeechPlugin: NSObject, FlutterPlugin, AVSpeechSynthesizerDelegate {
  static let engineID = "com.apple.avspeech"
  private let root: URL
  private var current: Job?

  private final class Job {
    let request: SystemSpeechRequest
    let writer: SystemSpeechFile
    let synthesizer = AVSpeechSynthesizer()
    let result: FlutterResult
    var timeout: DispatchWorkItem?
    var finishing = false
    init(request: SystemSpeechRequest, root: URL, result: @escaping FlutterResult) {
      self.request = request
      writer = SystemSpeechFile(output: request.output, root: root)
      self.result = result
    }
  }

  init(cacheDirectory: URL) {
    root = cacheDirectory.appendingPathComponent("listening-audio-v1", isDirectory: true)
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    let plugin = NativeSystemSpeechPlugin(cacheDirectory: cache)
    let channel = FlutterMethodChannel(name: "org.mewx.wenku8/system_speech", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.publish(plugin)
  }

  static func installedVoices() -> [AVSpeechSynthesisVoice] {
    AVSpeechSynthesisVoice.speechVoices().filter { voice in
      if #available(iOS 17.0, *), voice.voiceTraits.contains(.isPersonalVoice) { return false }
      return true
    }.sorted { lhs, rhs in
      let lhsChinese = lhs.language.hasPrefix("zh-")
      let rhsChinese = rhs.language.hasPrefix("zh-")
      if lhsChinese != rhsChinese { return lhsChinese }
      if lhs.language != rhs.language { return lhs.language < rhs.language }
      if lhs.quality != rhs.quality { return lhs.quality.rawValue > rhs.quality.rawValue }
      return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "engines": result([["id": Self.engineID, "name": "iOS 系统朗读"]])
    case "voices":
      guard [Self.engineID, "@default"].contains(args["engine"] as? String ?? "") else {
        result(flutterError(SpeechHostFailure(code: "TTS_ENGINE", message: "请选择 iOS 系统朗读引擎"))); return
      }
      result(Self.installedVoices().map { voice -> [String: Any] in
        // Public provider extensions expose no offline metadata. Only Apple's
        // installed voices are advertised as offline; other providers stay usable.
        ["id": voice.identifier, "name": voice.name, "locale": voice.language,
         "quality": voice.quality.rawValue * 100, "latency": 0,
         "networkRequired": !voice.identifier.hasPrefix("com.apple."), "features": []]
      })
    case "settings":
      result(flutterError(SpeechHostFailure(code: "TTS_SETTINGS", message: "请在系统设置的辅助功能中添加朗读声音，返回后重新检测")))
    case "synthesize":
      do { try synthesize(args, result) }
      catch { result(flutterError(error)) }
    case "cancel":
      if let job = current, args["requestId"] as? String == job.request.id {
        finish(job, .failure(SpeechHostFailure(code: "TTS_CANCELLED", message: "合成已取消")))
      }
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func synthesize(_ args: [String: Any], _ result: @escaping FlutterResult) throws {
    let request = try SystemSpeechRequest(args, root: root)
    guard current == nil else { throw SpeechHostFailure(code: "TTS_BUSY", message: "系统语音正在准备上一段") }
    let voice = try Self.selectVoice(for: request, from: Self.installedVoices())
    let job = Job(request: request, root: root, result: result)
    current = job
    job.synthesizer.delegate = self
    job.synthesizer.usesApplicationAudioSession = false
    let utterance = AVSpeechUtterance(string: request.text)
    utterance.voice = voice
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    let deadline = DispatchWorkItem { [weak self, weak job] in
      guard let self, let job else { return }
      self.finish(job, .failure(SpeechHostFailure(code: "TTS_TIMEOUT", message: "系统语音准备超时，请重新检测音色")))
    }
    job.timeout = deadline
    DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: deadline)
    job.synthesizer.write(utterance) { [weak self, weak job] buffer in
      guard let self, let job else { return }
      do {
        guard let pcm = buffer as? AVAudioPCMBuffer else {
          throw SpeechHostFailure(code: "TTS_CONTENT", message: "系统音色返回了无效的语音数据")
        }
        if let path = try job.writer.consume(pcm) {
          DispatchQueue.main.async { self.finish(job, .success(path)) }
        }
      } catch {
        DispatchQueue.main.async { self.finish(job, .failure(error)) }
      }
    }
  }

  static func selectVoice(for request: SystemSpeechRequest, from voices: [AVSpeechSynthesisVoice]) throws -> AVSpeechSynthesisVoice {
    let voice: AVSpeechSynthesisVoice?
    if request.voice == "@default" {
      let locale = request.locale ?? "zh-CN"
      let available = voices.filter { SystemSpeechLocale.matches(locale, $0.language) }
      let preferred = AVSpeechSynthesisVoice(language: locale)
      voice = available.first { $0.identifier == preferred?.identifier } ?? available.first
    } else { voice = voices.first { $0.identifier == request.voice } }
    guard let voice else {
      throw SpeechHostFailure(code: request.locale == nil ? "TTS_VOICE" : "TTS_LANGUAGE_UNAVAILABLE",
        message: "该系统音色尚未安装，请在系统设置中添加声音后重新检测")
    }
    if let locale = request.locale, !SystemSpeechLocale.matches(locale, voice.language) {
      throw SpeechHostFailure(code: "TTS_LANGUAGE_UNAVAILABLE", message: "没有对应语言的语音模型，已跳过该语言")
    }
    return voice
  }

  private func finish(_ job: Job, _ outcome: Result<String, Error>) {
    guard current === job, !job.finishing else { return }
    job.finishing = true
    job.timeout?.cancel()
    job.synthesizer.delegate = nil
    let success: Bool
    switch outcome {
    case .success: success = true
    case .failure:
      success = false
      job.synthesizer.stopSpeaking(at: .immediate)
    }
    job.writer.close(keepingOutput: success) {
      DispatchQueue.main.async {
        guard self.current === job else { return }
        self.current = nil
        switch outcome {
        case .success(let path): job.result(path)
        case .failure(let error): job.result(self.flutterError(error))
        }
      }
    }
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    DispatchQueue.main.async {
      if let job = self.current, job.synthesizer === synthesizer {
        self.finish(job, .failure(SpeechHostFailure(code: "TTS_CANCELLED", message: "系统语音准备已取消，请重试")))
      }
    }
  }

  func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    if let job = current { finish(job, .failure(SpeechHostFailure(code: "TTS_CANCELLED", message: "语音引擎已关闭"))) }
  }

  private func flutterError(_ error: Error) -> FlutterError {
    let failure = error as? SpeechHostFailure
    return FlutterError(code: failure?.code ?? "TTS_SYNTH",
      message: failure?.message ?? "系统语音缓存写入失败，请检查本机存储空间",
      details: ["stage": "ios_system_speech", "domain": (error as NSError).domain, "code": (error as NSError).code])
  }
}
