import AVFoundation
import Foundation
import PulseLogSignal

/// Owns the capture session and turns frames into `FrameSample`s.
///
/// The important work here is locking the camera down. Auto-exposure, in
/// particular, actively tracks scene brightness — and the pulse *is* a change
/// in scene brightness, so an unlocked camera compensates the signal away.
/// Failing to lock is the most common reason a camera PPG implementation
/// returns plausible-looking numbers that mean nothing.
@MainActor
final class CameraController: NSObject, ObservableObject {

    enum StartupError: LocalizedError {
        case permissionDenied
        case noCamera
        case noTorch
        case configurationFailed(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "PulseLog needs camera access to measure your pulse. "
                     + "You can enable it in Settings."
            case .noCamera:
                return "No rear camera is available on this device."
            case .noTorch:
                return "This device has no camera flash, which is required to "
                     + "light the fingertip."
            case .configurationFailed(let detail):
                return "The camera could not be configured: \(detail)"
            }
        }
    }

    /// Emitted for every usable frame, on the main actor.
    var onSample: ((FrameSample) -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.pulselog.capture", qos: .userInitiated)
    private var device: AVCaptureDevice?
    private var hasLockedExposure = false
    private var firstFrameTime: Double?

    // MARK: - Lifecycle

    func start() async throws {
        guard await requestPermission() else { throw StartupError.permissionDenied }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video, position: .back) else {
            throw StartupError.noCamera
        }
        guard camera.hasTorch else { throw StartupError.noTorch }
        device = camera

        session.beginConfiguration()
        // 640x480 is ample: the measurement averages a large region down to a
        // single number per frame, so extra resolution costs power for nothing.
        session.sessionPreset = .vga640x480

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                throw StartupError.configurationFailed("camera input rejected")
            }
            session.addInput(input)
        } catch let error as StartupError {
            throw error
        } catch {
            session.commitConfiguration()
            throw StartupError.configurationFailed(error.localizedDescription)
        }

        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        // Dropping late frames is correct here: a stale frame carries a
        // misleading timestamp, and the resampler handles gaps cleanly.
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw StartupError.configurationFailed("video output rejected")
        }
        session.addOutput(output)
        session.commitConfiguration()

        try configureDevice(camera)

        await withCheckedContinuation { continuation in
            queue.async { [session] in
                session.startRunning()
                continuation.resume()
            }
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        setTorch(on: false)
        hasLockedExposure = false
        firstFrameTime = nil
    }

    // MARK: - Device configuration

    private func configureDevice(_ camera: AVCaptureDevice) throws {
        do {
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }

            // Pin the frame rate so timestamps are as regular as the hardware
            // allows. The resampler copes with the jitter that remains.
            let frameDuration = CMTime(value: 1, timescale: 30)
            if camera.activeFormat.videoSupportedFrameRateRanges.contains(where: {
                $0.minFrameDuration <= frameDuration && frameDuration <= $0.maxFrameDuration
            }) {
                camera.activeVideoMinFrameDuration = frameDuration
                camera.activeVideoMaxFrameDuration = frameDuration
            }

            // A fingertip pressed to the lens is far closer than the near
            // focus limit, so autofocus would hunt indefinitely.
            if camera.isFocusModeSupported(.locked) { camera.focusMode = .locked }

            // A low torch level is deliberate. Full brightness heats the
            // module within seconds, and thermal drift in the sensor shows up
            // as baseline wander in exactly the band being measured.
            if camera.isTorchModeSupported(.on) {
                try? camera.setTorchModeOn(level: 0.3)
            }

            // Exposure and white balance start in auto so they can settle
            // against the finger, then lock in `lockExposureIfSettled`.
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                camera.whiteBalanceMode = .continuousAutoWhiteBalance
            }
        } catch {
            throw StartupError.configurationFailed(error.localizedDescription)
        }
    }

    /// Lock exposure and white balance once the camera has settled on the finger.
    ///
    /// Locking immediately would freeze whatever the camera happened to be
    /// looking at before the finger arrived, typically leaving the frame
    /// black. Locking never would let auto-exposure track the pulse and
    /// cancel it out. So: wait for the automatic systems to converge, then
    /// freeze them for the rest of the measurement.
    private func lockExposureIfSettled() {
        guard let camera = device, !hasLockedExposure else { return }
        guard !camera.isAdjustingExposure, !camera.isAdjustingWhiteBalance else { return }

        do {
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }
            if camera.isExposureModeSupported(.locked) { camera.exposureMode = .locked }
            if camera.isWhiteBalanceModeSupported(.locked) { camera.whiteBalanceMode = .locked }
            hasLockedExposure = true
        } catch {
            // Leaving the camera in auto degrades the signal but does not make
            // it unusable; the confidence gate is what protects the reading.
        }
    }

    private func setTorch(on: Bool) {
        guard let camera = device, camera.hasTorch else { return }
        try? camera.lockForConfiguration()
        defer { camera.unlockForConfiguration() }
        if on {
            try? camera.setTorchModeOn(level: 0.3)
        } else {
            camera.torchMode = .off
        }
    }

    private func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard seconds.isFinite else { return }
        guard let sample = FrameAnalyzer.meanColor(of: buffer, timestamp: seconds) else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.lockExposureIfSettled()

            // Discard frames captured before the camera settled. They carry a
            // moving exposure and would inject a large artificial trend.
            guard self.hasLockedExposure else { return }
            self.onSample?(sample)
        }
    }
}
