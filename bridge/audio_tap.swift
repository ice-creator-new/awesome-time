import Accelerate
import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Captures system audio (ScreenCaptureKit) and prints 32 log-spaced FFT bands.
/// Requires Screen Recording permission for the hosting process (Terminal).
@main
struct AudioTap {
    static func main() async {
        do {
            try await Tap().run()
        } catch {
            fputs("err \(error.localizedDescription)\n", stderr)
            fflush(stderr)
            exit(1)
        }
    }
}

final class Tap: NSObject, SCStreamOutput, SCStreamDelegate {
    private let n = 2048
    private var setup: FFTSetup
    private var window: [Float]
    private var ring: [Float]
    private var ringWrite = 0
    private var filled = 0
    private var realp: [Float]
    private var imagp: [Float]
    private var mag: [Float]
    private var smooth: [Float]
    private let bands = 32
    private var lastEmit = CFAbsoluteTimeGetCurrent()
    private var lastTick = CFAbsoluteTimeGetCurrent()
    private var samplesSinceAnalyze = 0
    /// 48kHz / 40Hz — emit FFT on the sample clock, not wall sleep.
    private var hopSamples = 1200
    private var agcMax: Float = 1e-6
    private let lock = NSLock()
    private var stream: SCStream?

    override init() {
        let log2n = vDSP_Length(11) // 2048
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        ring = [Float](repeating: 0, count: n)
        realp = [Float](repeating: 0, count: n / 2)
        imagp = [Float](repeating: 0, count: n / 2)
        mag = [Float](repeating: 0, count: n / 2)
        smooth = [Float](repeating: 0, count: 32)
        super.init()
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    func run() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first else {
            throw NSError(
                domain: "audio_tap",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "no display"]
            )
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 1
        config.width = 8
        config.height = 8
        config.minimumFrameInterval = CMTime(value: 1, timescale: 2)
        config.showsCursor = false

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = stream
        let queue = DispatchQueue(label: "audio.tap", qos: .userInteractive)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await stream.startCapture()
        fputs("ok capturing system audio\n", stderr)
        fflush(stderr)
        while true {
            try await Task.sleep(nanoseconds: 10_000_000_000)
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio else { return }
        ingest(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        fputs("err stream \(error.localizedDescription)\n", stderr)
        fflush(stderr)
    }

    private func ingest(_ sampleBuffer: CMSampleBuffer) {
        var count: Int = 0
        var sizeNeeded = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &sizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: nil
        )
        guard sizeNeeded > 0 else { return }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: sizeNeeded, alignment: 16)
        defer { raw.deallocate() }
        let abl = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        var block: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: abl,
            bufferListSize: sizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &block
        )
        guard status == noErr else { return }
        let buf = UnsafeMutableAudioBufferListPointer(abl)
        guard let first = buf.first, let data = first.mData else { return }
        let frames = Int(first.mDataByteSize / 4)
        let ptr = data.bindMemory(to: Float.self, capacity: frames)
        lock.lock()
        for i in 0..<frames {
            ring[ringWrite] = ptr[i]
            ringWrite = (ringWrite + 1) % n
            if filled < n { filled += 1 }
        }
        count = filled
        lock.unlock()
        // Sample-clock hop (1200 @ 48kHz = 40Hz) — wall-clock throttling
        // was the source of irregular stdout / spectrum timing.
        samplesSinceAnalyze += frames
        if count >= n && samplesSinceAnalyze >= hopSamples {
            samplesSinceAnalyze = 0
            maybeAnalyze()
        }
        _ = block
    }

    private func maybeAnalyze() {
        let now = CFAbsoluteTimeGetCurrent()
        // Safety only: real cadence comes from hopSamples.
        if now - lastEmit < 0.012 { return }
        let dt = Float(max(0.001, now - lastTick))
        lastTick = now
        lastEmit = now

        var frame = [Float](repeating: 0, count: n)
        lock.lock()
        let start = ringWrite
        for i in 0..<n {
            frame[i] = ring[(start + i) % n] * window[i]
        }
        lock.unlock()

        realp.withUnsafeMutableBufferPointer { realBuf in
            imagp.withUnsafeMutableBufferPointer { imagBuf in
                var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                frame.withUnsafeBufferPointer { src in
                    src.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, vDSP_Length(11), FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &mag, 1, vDSP_Length(n / 2))
            }
        }

        let sampleRate: Float = 48_000
        let binHz = sampleRate / Float(n)
        var out = [Float](repeating: 0, count: bands)
        for b in 0..<bands {
            let lo = logFreq(b)
            let hi = logFreq(b + 1)
            let i0 = max(1, Int(lo / binHz))
            let i1 = min(n / 2 - 1, max(i0 + 1, Int(hi / binHz)))
            // Band TOTAL energy (sum), not per-bin average.
            // Log HF bands span dozens of bins — averaging crushed highs by
            // ~10–20dB versus narrow bass bands, so the right side went flat.
            var sum: Float = 0
            var peak: Float = 0
            for i in i0...i1 {
                let m = mag[i]
                sum += m
                if m > peak { peak = m }
            }
            // Sum carries the spectrum shape; a little peak keeps attacks alive.
            // HF gets slightly more peak weight (transients are sparse up there).
            let hf = Float(b) / Float(bands - 1)
            let energy = sum * (1.0 - 0.25 * hf) + peak * (0.35 + 0.45 * hf)
            out[b] = sqrtf(max(energy, 0))
        }

        // Slow-decay AGC on the raw magnitude — fine for overall level.
        var mx: Float = 0
        vDSP_maxv(out, 1, &mx, vDSP_Length(bands))
        if mx > agcMax {
            agcMax = mx
        } else {
            agcMax = max(mx, agcMax * expf(-dt * 0.85), 1e-6)
        }
        var scale = 1.0 / agcMax
        vDSP_vsmul(out, 1, &scale, &out, 1, vDSP_Length(bands))

        // Fast attack / medium release — beats should hit, not melt.
        let attack: Float = 1 - expf(-dt * 28)
        let release: Float = 1 - expf(-dt * 7)
        // Rebuild per-band envelopes with a high shelf so mids/highs dance
        // even when the kick owns the global AGC peak.
        var frameMax: Float = 1e-6
        var shelved = [Float](repeating: 0, count: bands)
        for b in 0..<bands {
            let u = Float(b) / Float(bands - 1)
            // Strong shelf: 0.55× lows → ~2.1× highs after AGC.
            let shelf = 0.55 + 1.55 * u * u
            // Soft knee instead of a hard gate (0.04 zeroed quiet highs).
            let raw = out[b] * shelf
            shelved[b] = raw
            if raw > frameMax { frameMax = raw }
        }
        // Normalize to the shelved frame max so the right side can actually
        // reach the ceiling when bass is momentarily dominant.
        let inv = 1.0 / max(frameMax, 1e-6)
        for b in 0..<bands {
            var v = min(1, shelved[b] * inv)
            // Mild lift only — phone-side used to over-compress and go mushy.
            v = powf(v, 0.68)
            // Noise floor relative to frame, not absolute 0.04.
            if v < 0.06 { v = 0 }
            let k = v > smooth[b] ? attack : release
            smooth[b] += (v - smooth[b]) * k
            if smooth[b] < 0.001 { smooth[b] = 0 }
        }

        var line = "s"
        for b in 0..<bands {
            line += String(format: " %.3f", smooth[b])
        }
        line += "\n"
        fputs(line, stdout)
        // Line-buffered flush keeps Python's reader in lockstep without
        // waiting on a full 4K stdio block.
        fflush(stdout)
    }

    private func logFreq(_ band: Int) -> Float {
        let f0: Float = 40
        let f1: Float = 16_000
        let t = Float(band) / Float(bands)
        return f0 * powf(f1 / f0, t)
    }
}
