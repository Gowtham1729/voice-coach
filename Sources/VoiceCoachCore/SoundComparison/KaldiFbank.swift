#if canImport(Accelerate)
import Accelerate

/// Kaldi-compatible log-mel filterbank, matching lhotse `Fbank(FbankConfig(num_filters: 80,
/// dither: 0, snip_edges: false))`, which is what ZIPA was trained and run with.
///
/// 16 kHz, 25 ms Povey window (Hann^0.85, 400 samples), 10 ms hop, per-frame DC removal,
/// pre-emphasis 0.97 (first sample replicated), zero-pad to a 512-point FFT, power spectrum,
/// 80 triangular mel bins over 20 Hz…7600 Hz (torchaudio/Kaldi banks, Nyquist bin unused),
/// `log(max(energy, Float.ulpOfOne))`. No energy, no CMVN. `snip_edges = false` reflects the
/// signal at both ends and gives `(samples + 80) / 160` frames.
struct KaldiFbank: Sendable {
    static let melBins = 80
    static let frameLength = 400
    static let frameShift = 160
    static let fftLength = 512
    static let spectrumBins = fftLength / 2 + 1

    /// Feature value of a silent (all-zero) frame: `log(torch.finfo(float32).eps)`.
    /// Used to pad the last Core ML window.
    static let silence: Float = log(Float.ulpOfOne)

    private let window: [Float]
    /// `[spectrumBins × melBins]`, row-major, as in lhotse (`_fb`).
    private let melBanks: [Float]

    init() {
        let n = Self.frameLength
        window = (0..<n).map { i in
            let hann = 0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(n - 1))
            return Float(pow(hann, 0.85))
        }
        melBanks = Self.makeMelBanks()
    }

    /// Number of frames for `sampleCount` samples (snip_edges = false).
    static func frameCount(samples sampleCount: Int) -> Int {
        (sampleCount + frameShift / 2) / frameShift
    }

    func compute(_ samples: [Float]) -> FrameMatrix {
        let frames = Self.frameCount(samples: samples.count)
        guard frames > 0 else { return FrameMatrix(rows: 0, columns: Self.melBins) }
        let padded = Self.reflectPadded(samples, frames: frames)
        let n = Self.frameLength
        let half = Self.fftLength / 2
        var power = [Float](repeating: 0, count: frames * Self.spectrumBins)
        var frame = [Float](repeating: 0, count: Self.fftLength)
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        let log2n = vDSP_Length(9)
        guard let fft = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { fatalError("vDSP FFT setup failed") }
        defer { vDSP_destroy_fftsetup(fft) }

        for f in 0..<frames {
            let start = f * Self.frameShift
            // DC removal, pre-emphasis (x[-1] = x[0]), window. Mirrors lhotse Wav2Win in Float.
            var mean: Float = 0
            padded.withUnsafeBufferPointer { vDSP_meanv($0.baseAddress! + start, 1, &mean, vDSP_Length(n)) }
            for i in stride(from: n - 1, through: 0, by: -1) {
                let x = padded[start + i] - mean
                let previous = padded[start + max(i - 1, 0)] - mean
                frame[i] = (x - 0.97 * previous) * window[i]
            }
            for i in n..<Self.fftLength { frame[i] = 0 }

            real.withUnsafeMutableBufferPointer { rp in
                imag.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    frame.withUnsafeBytes {
                        vDSP_ctoz($0.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half))
                    }
                    vDSP_fft_zrip(fft, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                }
            }
            // vDSP's real FFT output is 2× the DFT; DC in real[0], Nyquist in imag[0].
            let row = f * Self.spectrumBins
            power[row] = (real[0] * 0.5) * (real[0] * 0.5)
            power[row + half] = (imag[0] * 0.5) * (imag[0] * 0.5)
            for k in 1..<half {
                let re = real[k] * 0.5, im = imag[k] * 0.5
                power[row + k] = re * re + im * im
            }
        }

        var mel = [Float](repeating: 0, count: frames * Self.melBins)
        vDSP_mmul(power, 1, melBanks, 1, &mel, 1,
                  vDSP_Length(frames), vDSP_Length(Self.melBins), vDSP_Length(Self.spectrumBins))
        var floor = Float.ulpOfOne
        vDSP_vthr(mel, 1, &floor, &mel, 1, vDSP_Length(mel.count))
        var count = Int32(mel.count)
        vvlogf(&mel, mel, &count)
        return FrameMatrix(rows: frames, columns: Self.melBins, values: mel)
    }

    /// `torch.flip(x[:120]) ++ x ++ torch.flip(x[-npad_right:])`, exactly as lhotse pads.
    static func reflectPadded(_ x: [Float], frames: Int) -> [Float] {
        let needed = (frames - 1) * frameShift + frameLength
        let left = (frameLength - frameShift) / 2
        let right = needed - x.count - left
        var out = [Float]()
        out.reserveCapacity(needed + max(right, 0))
        out.append(contentsOf: x[0..<min(left, x.count)].reversed())
        out.append(contentsOf: x)
        if right >= 0 {
            // x[-0:] is the whole signal in Python; only the first `right` samples are read anyway.
            let from = right == 0 ? 0 : max(0, x.count - right)
            out.append(contentsOf: x[from...].reversed())
        }
        while out.count < needed { out.append(0) } // only for clips shorter than 7.5 ms
        return out
    }

    /// torchaudio `get_mel_banks` in Float32 (as torch computes it), transposed to
    /// `[spectrumBins × melBins]` with a zero Nyquist row.
    static func makeMelBanks() -> [Float] {
        func mel(_ hz: Double) -> Double { 1127.0 * log(1.0 + hz / 700.0) }
        func melF(_ hz: Float) -> Float { 1127.0 * log(1.0 + hz / 700.0) }
        let lowMel = mel(20.0)
        let highMel = mel(8000.0 - 400.0)
        let delta = (highMel - lowMel) / Double(melBins + 1)
        let binWidth = Float(16_000) / Float(fftLength)
        var banks = [Float](repeating: 0, count: spectrumBins * melBins)
        for b in 0..<melBins {
            let left = Float(lowMel + Double(Float(b) * Float(delta)))
            let center = Float(lowMel + Double(Float(b + 1) * Float(delta)))
            let right = Float(lowMel + Double(Float(b + 2) * Float(delta)))
            for k in 0..<(fftLength / 2) {
                let m = melF(binWidth * Float(k))
                let up = (m - left) / (center - left)
                let down = (right - m) / (right - center)
                banks[k * melBins + b] = max(0, min(up, down))
            }
        }
        return banks
    }
}
#endif
