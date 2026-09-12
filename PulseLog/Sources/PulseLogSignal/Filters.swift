import Foundation

/// Second-order IIR section, as direct-form I coefficients.
public struct Biquad: Equatable {
    public let b0, b1, b2, a1, a2: Double

    /// Butterworth lowpass via the bilinear transform.
    public static func lowpass(cutoffHz: Double, fs: Double) -> Biquad {
        let (w0, k, denom) = prewarp(cutoffHz, fs)
        let b0 = w0 * w0 / denom
        return Biquad(
            b0: b0, b1: 2.0 * b0, b2: b0,
            a1: 2.0 * (w0 * w0 - 1.0) / denom,
            a2: (1.0 - k * w0 + w0 * w0) / denom
        )
    }

    /// Butterworth highpass via the bilinear transform.
    public static func highpass(cutoffHz: Double, fs: Double) -> Biquad {
        let (w0, k, denom) = prewarp(cutoffHz, fs)
        let b0 = 1.0 / denom
        return Biquad(
            b0: b0, b1: -2.0 * b0, b2: b0,
            a1: 2.0 * (w0 * w0 - 1.0) / denom,
            a2: (1.0 - k * w0 + w0 * w0) / denom
        )
    }

    private static func prewarp(_ cutoffHz: Double, _ fs: Double) -> (w0: Double, k: Double, denom: Double) {
        let nyquist = fs * 0.5
        let fc = min(max(cutoffHz, 1e-6), nyquist * 0.999)
        let w0 = tan(.pi * fc / fs)
        let k = 2.0.squareRoot()
        return (w0, k, 1.0 + k * w0 + w0 * w0)
    }

    /// Single forward pass. Phase is not preserved; use ``filtfilt`` instead
    /// unless you specifically want the causal response.
    public func forward(_ x: [Double]) -> [Double] {
        var y = [Double](repeating: 0, count: x.count)
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for i in 0..<x.count {
            let xi = x[i]
            let yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            y[i] = yi
            x2 = x1; x1 = xi
            y2 = y1; y1 = yi
        }
        return y
    }

    /// Zero-phase filtering: forward, then backward over the reversed signal.
    ///
    /// Phase distortion would shift detected peak positions and so corrupt the
    /// RR intervals that RMSSD is computed from. The filter must be zero-phase.
    public func filtfilt(_ x: [Double]) -> [Double] {
        let forwardPass = forward(x)
        let reversed = Array(forwardPass.reversed())
        return Array(forward(reversed).reversed())
    }
}

public enum Filters {
    /// Subtract a centred moving average to remove DC and slow wander.
    ///
    /// The torch drives the red channel close to saturation, so the DC term
    /// dwarfs the pulsatile component — fingertip AC/DC is typically well
    /// under 1%. Removing it first keeps later stages well-conditioned.
    public static func movingAverageDetrend(_ x: [Double], fs: Double,
                                            windowSeconds: Double = PPGConstants.detrendWindowSeconds) -> [Double] {
        guard !x.isEmpty else { return x }
        var w = max(3, Int((windowSeconds * fs).rounded()))
        if w % 2 == 0 { w += 1 }
        guard w < x.count else {
            let mean = x.reduce(0, +) / Double(x.count)
            return x.map { $0 - mean }
        }

        let half = w / 2
        // Edge padding keeps the baseline defined at the ends, matching the
        // reference implementation.
        var padded = [Double]()
        padded.reserveCapacity(x.count + 2 * half)
        padded.append(contentsOf: repeatElement(x[0], count: half))
        padded.append(contentsOf: x)
        padded.append(contentsOf: repeatElement(x[x.count - 1], count: half))

        // Running sum: the window is wide (1 s at 30 fps = 31 taps) and this
        // runs on every frame, so the naive O(n*w) convolution is worth avoiding.
        var out = [Double](repeating: 0, count: x.count)
        var windowSum = 0.0
        for i in 0..<w { windowSum += padded[i] }
        let inverseWidth = 1.0 / Double(w)
        for i in 0..<x.count {
            if i > 0 {
                windowSum += padded[i + w - 1] - padded[i - 1]
            }
            out[i] = x[i] - windowSum * inverseWidth
        }
        return out
    }

    /// Zero-phase bandpass across the physiological heart-rate band.
    public static func bandpass(_ x: [Double], fs: Double,
                                lowHz: Double = PPGConstants.lowHz,
                                highHz: Double = PPGConstants.highHz) -> [Double] {
        let highpassed = Biquad.highpass(cutoffHz: lowHz, fs: fs).filtfilt(x)
        return Biquad.lowpass(cutoffHz: highHz, fs: fs).filtfilt(highpassed)
    }
}
