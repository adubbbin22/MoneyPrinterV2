import CoreVideo
import Foundation
import PulseLogSignal

/// Reduces a camera frame to the mean colour of a central region.
///
/// Averaging a large region is not merely convenient: the pulsatile component
/// is well under 1% of the DC level, which is comparable to a single 8-bit
/// quantisation step. Averaging N pixels shrinks quantisation noise by sqrt(N)
/// and is what lifts the pulse clear of the sensor's least significant bit.
enum FrameAnalyzer {

    /// Fraction of the frame's shorter edge used as the sampling region.
    static let regionFraction: CGFloat = 0.5

    /// Sample every other pixel in each direction. A quarter of a 640x480
    /// centre region is still ~19k samples, far more than enough to suppress
    /// quantisation noise, and keeps per-frame work trivial at 30 fps.
    static let stride = 2

    /// Mean red, green and blue of the central region, normalised to 0...1.
    ///
    /// Returns nil if the buffer is not 32BGRA, which is the only format the
    /// capture session is configured to deliver.
    static func meanColor(of pixelBuffer: CVPixelBuffer, timestamp: Double) -> FrameSample? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0 else { return nil }

        let side = Int(CGFloat(min(width, height)) * regionFraction)
        guard side > 0 else { return nil }
        let originX = (width - side) / 2
        let originY = (height - side) / 2

        let pointer = base.assumingMemoryBound(to: UInt8.self)
        var sumB = 0, sumG = 0, sumR = 0, count = 0

        for y in Swift.stride(from: originY, to: originY + side, by: stride) {
            let row = pointer + y * bytesPerRow
            for x in Swift.stride(from: originX, to: originX + side, by: stride) {
                let pixel = row + x * 4      // BGRA
                sumB += Int(pixel[0])
                sumG += Int(pixel[1])
                sumR += Int(pixel[2])
                count += 1
            }
        }
        guard count > 0 else { return nil }

        let scale = 1.0 / (255.0 * Double(count))
        return FrameSample(timestamp: timestamp,
                           red: Double(sumR) * scale,
                           green: Double(sumG) * scale,
                           blue: Double(sumB) * scale)
    }
}
