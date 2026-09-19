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
        if count >= n {
            maybeAnalyze()
        }
        _ = block
    }

    private func maybeAnalyze() {
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastEmit < 0.033 { return }
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
            var peak: Float = 0
            for i in i0...i1 {
                if mag[i] > peak { peak = mag[i] }
            }
            // Magnitude is power; sqrt then gentle compression.
            out[b] = sqrtf(max(peak, 0))
        }
        var mx: Float = 0
        vDSP_maxv(out, 1, &mx, vDSP_Length(bands))
        if mx > 1e-6 {
            var scale = 1 / mx
            vDSP_vsmul(out, 1, &scale, &out, 1, vDSP_Length(bands))
        }
        for b in 0..<bands {
            // Perceptual: boost highs a bit, floor noise.
            let tilt = 0.65 + 0.55 * Float(b) / Float(bands - 1)
            var v = min(1, out[b] * tilt)
            v = powf(v, 0.55)
            smooth[b] = smooth[b] * 0.45 + v * 0.55
        }

        var line = "s"
        for b in 0..<bands {
            line += String(format: " %.3f", smooth[b])
        }
        line += "\n"
        fputs(line, stdout)
        fflush(stdout)
    }

    private func logFreq(_ band: Int) -> Float {
        let f0: Float = 40
        let f1: Float = 16_000
        let t = Float(band) / Float(bands)
        return f0 * powf(f1 / f0, t)
    }
}
