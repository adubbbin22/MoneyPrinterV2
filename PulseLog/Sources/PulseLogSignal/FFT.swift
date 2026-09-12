import Foundation

/// Minimal radix-2 FFT.
///
/// Accelerate would be faster, but keeping this in pure Swift is what lets the
/// estimator be unit-tested on any machine, and a 4096-point transform once per
/// measurement is nowhere near the performance budget.
public enum FFT {
    /// Smallest power of two greater than or equal to `n`.
    public static func nextPowerOfTwo(_ n: Int) -> Int {
        guard n > 1 else { return 1 }
        return 1 << (Int.bitWidth - (n - 1).leadingZeroBitCount)
    }

    /// Smallest power of two strictly greater than `v`.
    ///
    /// This is the zero-padding rule the reference implementation uses
    /// (`1 << v.bit_length()` in Python), which differs from
    /// ``nextPowerOfTwo`` when `v` is itself a power of two. Matching it
    /// exactly matters: a different transform length shifts bin centres and
    /// the ported estimator then disagrees with its own test vectors.
    public static func strictlyGreaterPowerOfTwo(_ v: Int) -> Int {
        guard v >= 1 else { return 1 }
        return 1 << (Int.bitWidth - v.leadingZeroBitCount)
    }

    /// In-place iterative Cooley-Tukey over split real/imaginary storage.
    public static func transform(real: inout [Double], imaginary: inout [Double]) {
        let n = real.count
        precondition(n == imaginary.count, "mismatched real/imaginary lengths")
        precondition(n > 0 && (n & (n - 1)) == 0, "FFT length must be a power of two")
        guard n > 1 else { return }

        // Bit-reversal permutation.
        var j = 0
        for i in 0..<(n - 1) {
            if i < j {
                real.swapAt(i, j)
                imaginary.swapAt(i, j)
            }
            var mask = n >> 1
            while j & mask != 0 {
                j &= ~mask
                mask >>= 1
            }
            j |= mask
        }

        var span = 1
        while span < n {
            let step = span << 1
            let angle = -Double.pi / Double(span)
            for group in stride(from: 0, to: n, by: step) {
                for k in 0..<span {
                    let theta = angle * Double(k)
                    let wr = cos(theta), wi = sin(theta)
                    let i0 = group + k
                    let i1 = i0 + span
                    let tr = real[i1] * wr - imaginary[i1] * wi
                    let ti = real[i1] * wi + imaginary[i1] * wr
                    real[i1] = real[i0] - tr
                    imaginary[i1] = imaginary[i0] - ti
                    real[i0] += tr
                    imaginary[i0] += ti
                }
            }
            span = step
        }
    }

    /// Magnitude-squared spectrum of a real signal, zero-padded to `nfft`.
    ///
    /// Returns the non-redundant half, matching `numpy.fft.rfft` bin layout so
    /// bin `i` corresponds to frequency `i * fs / nfft`.
    public static func powerSpectrum(_ x: [Double], nfft: Int) -> [Double] {
        var real = [Double](repeating: 0, count: nfft)
        var imaginary = [Double](repeating: 0, count: nfft)
        for i in 0..<min(x.count, nfft) { real[i] = x[i] }
        transform(real: &real, imaginary: &imaginary)

        let bins = nfft / 2 + 1
        var power = [Double](repeating: 0, count: bins)
        for i in 0..<bins {
            power[i] = real[i] * real[i] + imaginary[i] * imaginary[i]
        }
        return power
    }

    /// Symmetric Hann window, matching `numpy.hanning` (denominator `n - 1`).
    ///
    /// The half-sample difference from the periodic convention shifts spectral
    /// peaks slightly, which is enough to break agreement with the reference
    /// vectors, so the convention has to match exactly.
    public static func hann(_ n: Int) -> [Double] {
        guard n > 1 else { return [Double](repeating: 1.0, count: max(n, 0)) }
        return (0..<n).map { 0.5 - 0.5 * cos(2.0 * .pi * Double($0) / Double(n - 1)) }
    }
}
