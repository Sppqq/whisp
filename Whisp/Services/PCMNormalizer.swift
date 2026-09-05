import AVFoundation
import Foundation

enum PCMNormalizer {
    static func mono16kFloat(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: buffer.format, to: outputFormat) else { return [] }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: max(1, capacity)) else { return [] }
        var supplied = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard conversionError == nil, let channel = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }

    static func pcm16Data(from samples: [Float]) -> Data {
        var values = samples.map { sample -> Int16 in
            let clipped = min(1, max(-1, sample))
            return Int16(clipped * Float(Int16.max))
        }
        return Data(bytes: &values, count: values.count * MemoryLayout<Int16>.size)
    }
}
