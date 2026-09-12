import XCTest
@testable import PulseLogSignal

/// Component tests that stand on their own, independent of the generated
/// vectors. If the vectors were ever regenerated from a broken reference,
/// these would still catch it.
final class SignalUnitTests: XCTestCase {

    // MARK: - FFT

    func testFFTMatchesNaiveDFT() {
        let n = 64
        let input = (0..<n).map { i -> Double in
            let t = Double(i) / Double(n)
            return sin(2 * .pi * 5 * t) + 0.4 * cos(2 * .pi * 13 * t)
        }

        var real = input
        var imaginary = [Double](repeating: 0, count: n)
        FFT.transform(real: &real, imaginary: &imaginary)

        for k in 0..<n {
            var dftReal = 0.0, dftImaginary = 0.0
            for t in 0..<n {
                let angle = -2.0 * .pi * Double(k) * Double(t) / Double(n)
                dftReal += input[t] * cos(angle)
                dftImaginary += input[t] * sin(angle)
            }
            XCTAssertEqual(real[k], dftReal, accuracy: 1e-9, "bin \(k) real")
            XCTAssertEqual(imaginary[k], dftImaginary, accuracy: 1e-9, "bin \(k) imaginary")
        }
    }

    func testFFTFindsKnownFrequency() {
        let fs = 30.0, n = 256, frequency = 1.2   // 72 BPM
        let signal = (0..<n).map { sin(2 * .pi * frequency * Double($0) / fs) }
        let nfft = FFT.nextPowerOfTwo(n)
        let power = FFT.powerSpectrum(signal, nfft: nfft)

        var peak = 0
        for i in 1..<power.count where power[i] > power[peak] { peak = i }
        XCTAssertEqual(Double(peak) * fs / Double(nfft), frequency, accuracy: 0.1)
    }

    func testPowerOfTwoHelpersDifferAsIntended() {
        // nextPowerOfTwo is inclusive; strictlyGreaterPowerOfTwo is not. The
        // reference's zero-padding rule needs the strict form, and conflating
        // them silently changes every spectral estimate.
        XCTAssertEqual(FFT.nextPowerOfTwo(1024), 1024)
        XCTAssertEqual(FFT.strictlyGreaterPowerOfTwo(1024), 2048)
        XCTAssertEqual(FFT.nextPowerOfTwo(1000), 1024)
        XCTAssertEqual(FFT.strictlyGreaterPowerOfTwo(1000), 1024)
        XCTAssertEqual(FFT.strictlyGreaterPowerOfTwo(2399), 4096)
    }

    func testHannWindowIsSymmetric() {
        let w = FFT.hann(9)
        XCTAssertEqual(w.first ?? .nan, 0.0, accuracy: 1e-12)
        XCTAssertEqual(w.last ?? .nan, 0.0, accuracy: 1e-12)
        XCTAssertEqual(w[4], 1.0, accuracy: 1e-12)
        for i in 0..<w.count {
            XCTAssertEqual(w[i], w[w.count - 1 - i], accuracy: 1e-12, "symmetry at \(i)")
        }
    }

    // MARK: - Filters

    func testFiltfiltIsZeroPhase() {
        // A symmetric input must produce a symmetric output under zero-phase
        // filtering. A single forward pass would skew it.
        let n = 200
        let input = (0..<n).map { i -> Double in
            let d = Double(i) - Double(n - 1) / 2.0
            return exp(-d * d / 200.0)
        }
        let output = Biquad.lowpass(cutoffHz: 3.0, fs: 30.0).filtfilt(input)
        for i in 0..<n {
            XCTAssertEqual(output[i], output[n - 1 - i], accuracy: 1e-6, "symmetry at \(i)")
        }
    }

    func testBandpassRejectsOutOfBandContent() {
        let fs = 30.0, n = 600
        let inBand = (0..<n).map { sin(2 * .pi * 1.2 * Double($0) / fs) }          // 72 BPM
        let breathing = (0..<n).map { 5.0 * sin(2 * .pi * 0.2 * Double($0) / fs) } // 12/min
        let combined = zip(inBand, breathing).map(+)

        let filtered = Filters.bandpass(combined, fs: fs)
        // Ignore filter start-up transients at the edges.
        let core = Array(filtered[100..<(n - 100)])
        let reference = Array(inBand[100..<(n - 100)])

        var error = 0.0
        for i in 0..<core.count { error = max(error, abs(core[i] - reference[i])) }
        XCTAssertLessThan(error, 0.15,
                          "breathing wander five times the pulse amplitude was not rejected")
    }

    func testDetrendRemovesLargeDCPedestal() {
        let fs = 30.0, n = 300
        let pulse = (0..<n).map { 0.005 * sin(2 * .pi * 1.2 * Double($0) / fs) }
        let withPedestal = pulse.map { $0 + 0.85 }   // torch-lit fingertip

        let detrended = Filters.movingAverageDetrend(withPedestal, fs: fs)
        let mean = detrended.reduce(0, +) / Double(n)
        XCTAssertEqual(mean, 0.0, accuracy: 1e-3, "DC pedestal survived detrending")
        XCTAssertLessThan(detrended.map { abs($0) }.max() ?? 1, 0.02)
    }

    // MARK: - Resampler

    func testResamplerInfersRateAndHandlesJitter() {
        var timestamps = [Double](), values = [Double]()
        for i in 0..<300 {
            let jitter = (i % 7 == 0) ? 0.004 : -0.002
            timestamps.append(Double(i) / 30.0 + jitter)
            values.append(Double(i))
        }
        let (fs, samples) = Resampler.uniform(timestamps: timestamps, values: values)
        XCTAssertEqual(fs, 30.0, accuracy: 1.0)
        XCTAssertGreaterThan(samples.count, 250)
        // The source ramps linearly, so the resampled series must too.
        for i in 1..<samples.count {
            XCTAssertGreaterThanOrEqual(samples[i] + 1e-9, samples[i - 1])
        }
    }

    func testResamplerRejectsDegenerateInput() {
        XCTAssertEqual(Resampler.uniform(timestamps: [], values: []).fs, 0)
        XCTAssertEqual(Resampler.uniform(timestamps: [1.0], values: [2.0]).fs, 0)
        XCTAssertEqual(Resampler.uniform(timestamps: [1.0, 1.0, 1.0],
                                         values: [1.0, 2.0, 3.0]).fs, 0)
    }

    // MARK: - Estimator, on signals synthesised here

    /// Sweep clean synthetic pulses and confirm the estimator recovers them.
    /// Harmonics are included because their absence would hide octave errors,
    /// which are the pipeline's dominant failure mode.
    func testEstimatorRecoversKnownRatesAcrossTheBand() {
        let fs = 30.0
        for trueBPM in stride(from: 45.0, through: 200.0, by: 5.0) {
            let f0 = trueBPM / 60.0
            let n = Int(30.0 * fs)
            let raw = (0..<n).map { i -> Double in
                let t = Double(i) / fs
                let phase = 2 * .pi * f0 * t
                // Fundamental plus a strong second harmonic (dicrotic notch).
                return 0.85 + 0.006 * (sin(phase) + 0.55 * sin(2 * phase + 1.1))
            }
            let timestamps = (0..<n).map { Double($0) / fs }
            let result = PPGAnalyzer.analyze(timestamps: timestamps, values: raw)

            guard let bpm = result.bpm else {
                XCTFail("no estimate at \(trueBPM) BPM"); continue
            }
            XCTAssertEqual(bpm, trueBPM, accuracy: 3.0,
                           "estimated \(bpm) for a true rate of \(trueBPM)")
            XCTAssertTrue(result.isReportable, "clean signal at \(trueBPM) BPM was not reportable")
        }
    }

    func testFlatSignalProducesNoReportableReading() {
        let fs = 30.0, n = 900
        let timestamps = (0..<n).map { Double($0) / fs }
        let flat = [Double](repeating: 0.85, count: n)
        XCTAssertFalse(PPGAnalyzer.analyze(timestamps: timestamps, values: flat).isReportable)
    }

    func testPureNoiseIsNotReportable() {
        let fs = 30.0, n = 900
        var generator = SystemRandomNumberGenerator()
        let timestamps = (0..<n).map { Double($0) / fs }
        let noise = (0..<n).map { _ in 0.85 + Double.random(in: -0.01...0.01, using: &generator) }
        let result = PPGAnalyzer.analyze(timestamps: timestamps, values: noise)
        XCTAssertFalse(result.isReportable,
                       "white noise was reported as \(result.bpm ?? -1) BPM")
    }

    // MARK: - Contact monitor

    func testContactMonitorAcceptsAGoodFingertip() {
        var monitor = ContactMonitor()
        // Prime the motion check, then submit a plausible frame.
        _ = monitor.evaluate(FrameSample(timestamp: 0, red: 0.88, green: 0.12, blue: 0.09))
        let issue = monitor.evaluate(FrameSample(timestamp: 0.03, red: 0.881, green: 0.12, blue: 0.09))
        XCTAssertNil(issue)
    }

    func testContactMonitorRejectsEachFailureMode() {
        var monitor = ContactMonitor()
        monitor.reset()
        XCTAssertEqual(monitor.evaluate(FrameSample(timestamp: 0, red: 0.2, green: 0.2, blue: 0.2)),
                       .noFinger)

        monitor.reset()
        XCTAssertEqual(monitor.evaluate(FrameSample(timestamp: 0, red: 0.999, green: 0.5, blue: 0.5)),
                       .saturated)

        monitor.reset()
        XCTAssertEqual(monitor.evaluate(FrameSample(timestamp: 0, red: 0.9, green: 0.85, blue: 0.8)),
                       .tooLight)

        monitor.reset()
        _ = monitor.evaluate(FrameSample(timestamp: 0, red: 0.88, green: 0.1, blue: 0.1))
        XCTAssertEqual(monitor.evaluate(FrameSample(timestamp: 0.03, red: 0.70, green: 0.1, blue: 0.1)),
                       .moving)
    }

    func testContactIssuesAreActionable() {
        // Each message must tell the user what to do differently, not merely
        // report that something is wrong.
        for issue in [ContactIssue.noFinger, .tooLight, .saturated, .moving] {
            XCTAssertFalse(issue.guidance.isEmpty)
        }
    }
}

/// Tests for the capture state machine. These matter as much as the DSP: a
/// session that counts down while the finger is off the lens produces a
/// confident reading from nothing.
final class MeasurementSessionTests: XCTestCase {

    private func fingertipFrame(at t: Double, bpm: Double) -> FrameSample {
        let phase = 2 * .pi * (bpm / 60.0) * t
        let red = 0.85 + 0.006 * (sin(phase) + 0.55 * sin(2 * phase + 1.1))
        return FrameSample(timestamp: t, red: red, green: 0.11, blue: 0.08)
    }

    private func emptyFrame(at t: Double) -> FrameSample {
        FrameSample(timestamp: t, red: 0.15, green: 0.14, blue: 0.16)
    }

    func testCompletesAndRecoversRateFromAGoodCapture() {
        let session = MeasurementSession(duration: 30.0)
        var final: PPGResult?
        // 32 s of frames: 1 s settling plus the 30 s record.
        for i in 0..<Int(32.0 * 30.0) {
            let phase = session.ingest(fingertipFrame(at: Double(i) / 30.0, bpm: 72))
            if case .finished(let result) = phase { final = result; break }
        }
        guard let result = final, let bpm = result.bpm else {
            return XCTFail("session did not finish")
        }
        XCTAssertEqual(bpm, 72, accuracy: 3.0)
        XCTAssertTrue(result.isReportable)
    }

    func testCountdownDoesNotAdvanceWithoutContact() {
        let session = MeasurementSession(duration: 30.0)
        for i in 0..<300 {
            session.ingest(emptyFrame(at: Double(i) / 30.0))
        }
        guard case .awaitingContact = session.phase else {
            return XCTFail("session advanced with no finger present: \(session.phase)")
        }
        XCTAssertEqual(session.elapsed, 0)
    }

    func testLosingContactDiscardsThePartialRecord() {
        let session = MeasurementSession(duration: 30.0)
        for i in 0..<450 {   // 15 s of good contact
            session.ingest(fingertipFrame(at: Double(i) / 30.0, bpm: 72))
        }
        XCTAssertGreaterThan(session.elapsed, 10.0)

        // Finger lifts.
        session.ingest(emptyFrame(at: 15.0))
        XCTAssertEqual(session.elapsed, 0, "a partial record survived a contact break")
        guard case .awaitingContact = session.phase else {
            return XCTFail("expected to await contact again")
        }
    }

    func testSettlingPeriodIsExcluded() {
        let session = MeasurementSession(duration: 30.0)
        // Half a second of contact: inside the settling window, so nothing counts.
        for i in 0..<15 {
            session.ingest(fingertipFrame(at: Double(i) / 30.0, bpm: 72))
        }
        XCTAssertEqual(session.elapsed, 0)
    }

    func testUnreadableCaptureAsksForARetakeRatherThanReporting() {
        let session = MeasurementSession(duration: 20.0)
        var generator = SystemRandomNumberGenerator()
        var phase: MeasurementSession.Phase = .awaitingContact(.noFinger)
        for i in 0..<Int(24.0 * 30.0) {
            // Contact is good, but there is no pulse in the trace.
            let sample = FrameSample(timestamp: Double(i) / 30.0,
                                     red: 0.85 + Double.random(in: -0.004...0.004, using: &generator),
                                     green: 0.11, blue: 0.08)
            phase = session.ingest(sample)
            if case .needsRetake = phase { break }
            if case .finished = phase { break }
        }
        if case .finished(let result) = phase {
            XCTFail("noise was reported as \(result.bpm ?? -1) BPM at confidence \(result.confidence)")
        }
    }

    func testProvisionalRateAppearsOnlyAfterEnoughSignal() {
        let session = MeasurementSession(duration: 30.0)
        var sawProvisionalBefore = false
        for i in 0..<Int(8.0 * 30.0) {   // through the provisional threshold
            if case .measuring(_, let provisional) = session.ingest(
                fingertipFrame(at: Double(i) / 30.0, bpm: 72)
            ), provisional != nil, session.elapsed < PPGConstants.provisionalAfterSeconds {
                sawProvisionalBefore = true
            }
        }
        XCTAssertFalse(sawProvisionalBefore,
                       "a provisional rate was shown before enough signal had accumulated")
    }
}
