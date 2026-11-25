#if canImport(CoreML) && canImport(Accelerate)
import CoreML
import Foundation

/// ZIPA small (Zipformer CTC, 127 IPA tokens) through the masked fixed-window Core ML package:
/// `fbank (1, 1000, 80)` (10 s) and `length` (real fbank frames) in, raw fp16 `logits` and the
/// encoder output `hidden` (512 values, for the word DTW) out, one output frame per 2 fbank frames
/// (20 ms). Longer takes run in windows of 1000 frames
/// stepping 800, the last one ending at the last frame; each output frame comes from the window
/// where it is furthest from an edge.
final class ZipaPhoneModel: PhoneLogitModel {
  let modelID = "zipa"
  let vocabulary: PhoneVocabulary
  private let model: MLModel
  private let windowFrames: Int
  private let overlapFrames = 200
  private let fbank = KaldiFbank()

  init(compiledModel: URL, vocabulary: PhoneVocabulary, computeUnits: MLComputeUnits) throws {
    let config = MLModelConfiguration()
    config.computeUnits = computeUnits
    model = try MLModel(contentsOf: compiledModel, configuration: config)
    let inputs = model.modelDescription.inputDescriptionsByName
    guard let shape = inputs["fbank"]?.multiArrayConstraint?.shape, shape.count == 3,
      inputs["length"] != nil
    else { throw SoundComparisonError.unexpectedModel("zipa") }
    windowFrames = shape[1].intValue
    self.vocabulary = vocabulary
  }

  /// Output frames for `fbankFrames` input frames (Conv2dSubsampling, then ÷2).
  static func outputFrames(fbankFrames: Int) -> Int { max(0, (fbankFrames - 7) / 2) }

  func rawLogits(samples: [Float]) throws -> FrameMatrix {
    try rawOutputs(samples: samples).logits
  }

  func rawOutputs(samples: [Float]) throws -> (logits: FrameMatrix, hidden: FrameMatrix?) {
    let features = fbank.compute(samples)
    let total = Self.outputFrames(fbankFrames: features.rows)
    let width = vocabulary.tokens.count
    var logits = FrameMatrix(rows: total, columns: width)
    var hidden: FrameMatrix?
    var starts = [0]
    if features.rows > windowFrames {
      starts =
        Array(stride(from: 0, to: features.rows - windowFrames, by: windowFrames - overlapFrames))
        + [features.rows - windowFrames]
    }
    var owner = [Int](repeating: 0, count: total)
    var bestMargin = [Int](repeating: Int.min, count: total)
    for (k, start) in starts.enumerated() {
      let valid = Self.outputFrames(fbankFrames: min(windowFrames, features.rows - start))
      for local in 0..<valid where start / 2 + local < total {
        let margin = min(local, valid - 1 - local)
        if margin > bestMargin[start / 2 + local] {
          bestMargin[start / 2 + local] = margin
          owner[start / 2 + local] = k
        }
      }
    }
    for (k, start) in starts.enumerated() {
      let owned = (0..<total).filter { owner[$0] == k }
      guard let first = owned.first, let last = owned.last else { continue }
      let window = try predict(features, from: start)
      if hidden == nil { hidden = FrameMatrix(rows: total, columns: window.hidden.columns) }
      let depth = window.hidden.columns
      for g in first...last {
        let local = min(max(g - start / 2, 0), window.logits.rows - 1)
        logits.values.replaceSubrange(
          g * width..<(g + 1) * width, with: window.logits.row(local))
        hidden!.values.replaceSubrange(
          g * depth..<(g + 1) * depth, with: window.hidden.row(local))
      }
    }
    return (logits, hidden)
  }

  private func predict(_ features: FrameMatrix, from start: Int) throws
    -> (logits: FrameMatrix, hidden: FrameMatrix)
  {
    let input = try MLMultiArray(shape: [1, NSNumber(value: windowFrames), 80], dataType: .float32)
    let available = min(windowFrames, features.rows - start)
    input.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, strides in
      for r in 0..<windowFrames {
        for c in 0..<80 {
          buffer[r * strides[1] + c * strides[2]] =
            r < available ? features[start + r, c] : KaldiFbank.silence
        }
      }
    }
    let length = try MLMultiArray(shape: [1], dataType: .int32)
    length[0] = NSNumber(value: available)
    let result = try model.prediction(
      from: MLDictionaryFeatureProvider(dictionary: [
        "fbank": MLFeatureValue(multiArray: input), "length": MLFeatureValue(multiArray: length),
      ]))
    guard let logits = result.featureValue(for: "logits")?.multiArrayValue,
      let hidden = result.featureValue(for: "hidden")?.multiArrayValue
    else { throw SoundComparisonError.unexpectedModel("zipa logits") }
    return (logits.frameMatrix(), hidden.frameMatrix())
  }
}

/// HuBERT / wav2vec2 CTC through an exact-length export: `audio (1, N)`, N from 1 s to 30 s.
/// Never zero-pad these models (the first conv's GroupNorm sees the padding). Input is
/// normalised over the real samples; clips under 1 s are zero-padded to 1 s first, as the lab
/// does. Takes over `maxWindowSeconds` run in overlapping windows (normalised once over the take).
final class Wav2Vec2PhoneModel: PhoneLogitModel {
  static let samplesPerFrame = 320
  /// 15 s, not the package's 30 s: attention over 30 s windows peaks at ~1.7 GB (G-11 ≤ 1 GB).
  /// Golden pairs are all under 10 s, so this does not change parity.
  static let maxWindowSeconds = 15

  let modelID: String
  let vocabulary: PhoneVocabulary
  private let model: MLModel
  private let minSamples: Int
  private let maxSamples: Int
  private let overlapSamples = 2 * 16_000

  init(
    modelID: String, compiledModel: URL, vocabulary: PhoneVocabulary, computeUnits: MLComputeUnits
  ) throws {
    let config = MLModelConfiguration()
    config.computeUnits = computeUnits
    model = try MLModel(contentsOf: compiledModel, configuration: config)
    guard let audio = model.modelDescription.inputDescriptionsByName["audio"]?.multiArrayConstraint,
      audio.shapeConstraint.sizeRangeForDimension.count == 2
    else { throw SoundComparisonError.unexpectedModel(modelID) }
    let range = audio.shapeConstraint.sizeRangeForDimension[1].rangeValue
    minSamples = range.location
    maxSamples = min(range.location + range.length, Self.maxWindowSeconds * 16_000)
    self.modelID = modelID
    self.vocabulary = vocabulary
  }

  /// Output frames of the conv feature encoder (kernels 10,3,3,3,3,2,2; strides 5,2,2,2,2,2,2).
  static func outputFrames(samples n: Int) -> Int {
    var length = n
    for (k, s) in zip([10, 3, 3, 3, 3, 2, 2], [5, 2, 2, 2, 2, 2, 2]) {
      length = length < k ? 0 : (length - k) / s + 1
    }
    return length
  }

  func rawLogits(samples: [Float]) throws -> FrameMatrix {
    var audio = samples
    if audio.count < minSamples { audio += [Float](repeating: 0, count: minSamples - audio.count) }
    let x = Self.normalized(audio)
    if x.count <= maxSamples { return try predict(x[...]) }

    let window = maxSamples / Self.samplesPerFrame * Self.samplesPerFrame
    let starts =
      Array(stride(from: 0, to: x.count - window, by: window - overlapSamples))
      + [(x.count - window) / Self.samplesPerFrame * Self.samplesPerFrame]
    let total = Self.outputFrames(samples: x.count)
    var out: FrameMatrix?
    var bestMargin = [Int](repeating: Int.min, count: total)
    for start in starts {
      let logits = try predict(x[start..<min(x.count, start + window)])
      if out == nil { out = FrameMatrix(rows: total, columns: logits.columns) }
      let offset = start / Self.samplesPerFrame
      for local in 0..<logits.rows where offset + local < total {
        let margin = min(local, logits.rows - 1 - local)
        guard margin > bestMargin[offset + local] else { continue }
        bestMargin[offset + local] = margin
        let g = offset + local
        out!.values.replaceSubrange(
          g * logits.columns..<(g + 1) * logits.columns, with: logits.row(local))
      }
    }
    return out!
  }

  /// HF `Wav2Vec2FeatureExtractor(do_normalize: true)`: zero mean, unit variance (Double sums).
  static func normalized(_ samples: [Float]) -> [Float] {
    var mean = 0.0
    for s in samples { mean += Double(s) }
    mean /= Double(samples.count)
    var variance = 0.0
    for s in samples { variance += (Double(s) - mean) * (Double(s) - mean) }
    variance /= Double(samples.count)
    let scale = 1 / (variance + 1e-7).squareRoot()
    return samples.map { Float((Double($0) - mean) * scale) }
  }

  private func predict(_ x: ArraySlice<Float>) throws -> FrameMatrix {
    let input = try MLMultiArray(shape: [1, NSNumber(value: x.count)], dataType: .float32)
    input.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, strides in
      for (i, v) in x.enumerated() { buffer[i * strides[1]] = v }
    }
    let result = try model.prediction(
      from: MLDictionaryFeatureProvider(dictionary: ["audio": MLFeatureValue(multiArray: input)]))
    guard let logits = result.featureValue(for: "logits")?.multiArrayValue else {
      throw SoundComparisonError.unexpectedModel("\(modelID) logits")
    }
    return logits.frameMatrix()
  }
}

extension MLMultiArray {
  /// `(1, T, D)` fp16 or fp32 array → `[T × D]` Float, honouring strides.
  fileprivate func frameMatrix() -> FrameMatrix {
    let rows = shape[1].intValue
    let cols = shape[2].intValue
    var out = FrameMatrix(rows: rows, columns: cols)
    func copy<T: MLShapedArrayScalar>(_ type: T.Type, _ convert: (T) -> Float) {
      withUnsafeBufferPointer(ofType: type) { buffer in
        let rs = strides[1].intValue
        let cs = strides[2].intValue
        for r in 0..<rows {
          for c in 0..<cols { out.values[r * cols + c] = convert(buffer[r * rs + c * cs]) }
        }
      }
    }
    switch dataType {
    case .float16: copy(Float16.self) { Float($0) }
    case .float32: copy(Float.self) { $0 }
    default: copy(Double.self) { Float($0) }
    }
    return out
  }
}

extension PhoneModelSoundComparisonEngine {
  /// Loads an engine installed by `scripts/setup-sound-comparison.sh`: `manifest.json`, one
  /// `.mlpackage` and vocabulary per model, and a substitution table per model for `full`. Packages are compiled once into `compiled/` beside
  /// them. Always `.cpuAndGPU`: the thresholds were set on GPU logits, and CPU-only is a
  /// different engine for `full`.
  public static func load(installedAt directory: URL) async throws
    -> PhoneModelSoundComparisonEngine
  {
    let manifest = try JSONDecoder().decode(
      SoundEngineManifest.self,
      from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
    guard manifest.isCurrent, let configuration = SoundComparisonConfiguration.named(manifest.engineID)
    else { throw SoundComparisonError.engineNotInstalled(manifest.engineID) }
    var models: [any PhoneLogitModel] = []
    var substitutions: [SubstitutionTable?] = []
    for entry in manifest.models {
      let vocabulary = try PhoneVocabulary(
        contentsOf: directory.appendingPathComponent(entry.vocabulary))
      substitutions.append(
        try entry.substitutions.map {
          try SubstitutionTable(
            contentsOf: directory.appendingPathComponent($0), vocabulary: vocabulary)
        })
      let compiled = try await compile(
        directory.appendingPathComponent(entry.package),
        cacheDirectory: directory.appendingPathComponent("compiled", isDirectory: true))
      if entry.id == "zipa" {
        models.append(
          try ZipaPhoneModel(
            compiledModel: compiled, vocabulary: vocabulary, computeUnits: .cpuAndGPU))
      } else {
        models.append(
          try Wav2Vec2PhoneModel(
            modelID: entry.id, compiledModel: compiled, vocabulary: vocabulary,
            computeUnits: .cpuAndGPU))
      }
    }
    return try PhoneModelSoundComparisonEngine(
      configuration: configuration, models: models, substitutions: substitutions)
  }

  /// Compiles an `.mlpackage` once and keeps the `.mlmodelc`; recompiles when the package is
  /// newer than the cache.
  static func compile(_ package: URL, cacheDirectory: URL) async throws -> URL {
    let fm = FileManager.default
    let cached = cacheDirectory.appendingPathComponent(
      package.deletingPathExtension().lastPathComponent + ".mlmodelc")
    func modified(_ url: URL) -> Date {
      (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        ?? .distantPast
    }
    if fm.fileExists(atPath: cached.path), modified(cached) >= modified(package) { return cached }
    let compiled = try await MLModel.compileModel(at: package)
    try fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    if fm.fileExists(atPath: cached.path) { try fm.removeItem(at: cached) }
    try fm.moveItem(at: compiled, to: cached)
    return cached
  }
}
#endif

#if canImport(AVFoundation)
import AVFoundation

public enum SoundComparisonAudio {
  public static let sampleRate = 16_000.0

  /// The first channel of an audio file at 16 kHz (as the lab's `load_audio`).
  public static func load(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let source = file.processingFormat
    guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(file.length)),
      let mono = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: source.sampleRate, channels: 1,
        interleaved: false)
    else { throw AnalysisError.unreadableAudio }
    try file.read(into: input)
    guard let channel = input.floatChannelData?[0] else { throw AnalysisError.unreadableAudio }
    let samples = Array(UnsafeBufferPointer(start: channel, count: Int(input.frameLength)))
    if source.sampleRate == sampleRate { return samples }

    guard
      let target = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
      let converter = AVAudioConverter(from: mono, to: target),
      let monoBuffer = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: input.frameLength),
      let output = AVAudioPCMBuffer(
        pcmFormat: target,
        frameCapacity: AVAudioFrameCount(Double(samples.count) * sampleRate / source.sampleRate)
          + 1024)
    else { throw AnalysisError.unreadableAudio }
    monoBuffer.frameLength = input.frameLength
    monoBuffer.floatChannelData![0].update(from: channel, count: samples.count)
    converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
    nonisolated(unsafe) var supplied = false
    var conversionError: NSError?
    _ = converter.convert(to: output, error: &conversionError) { _, status in
      if supplied {
        status.pointee = .endOfStream
        return nil
      }
      supplied = true
      status.pointee = .haveData
      return monoBuffer
    }
    if let conversionError { throw conversionError }
    return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
  }
}
#endif
