import Foundation
import AVFoundation

@MainActor
final class AudioRecorder {
    struct MeterSample: Sendable {
        let rms: Float
        let dbInstant: Float
        let frameDurationMs: Double
    }

    enum RecorderError: LocalizedError {
        case permissionDenied
        case alreadyRecording
        case recorderInitFailed
        case recordingStartFailed
        case notRecording

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Microphone permission is not granted."
            case .alreadyRecording:
                return "Recorder is already running."
            case .recorderInitFailed:
                return "Unable to initialize audio recorder."
            case .recordingStartFailed:
                return "Unable to start recording."
            case .notRecording:
                return "No active recording session."
            }
        }
    }

    var onRMS: ((Float) -> Void)?
    var onMeterSample: ((MeterSample) -> Void)?

    private(set) var lastDuration: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var startDate: Date?
    private var meterTimer: DispatchSourceTimer?
    private var lastMeterTimestamp: DispatchTime?
    private var requestedMicPermissionInSession = false

    func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            if requestedMicPermissionInSession {
                return false
            }
            requestedMicPermissionInSession = true
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func startRecording() throws -> URL {
        guard recorder == nil else { throw RecorderError.alreadyRecording }

        let targetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("press-talk-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        let recorder = try AVAudioRecorder(url: targetURL, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw RecorderError.recordingStartFailed
        }

        self.recorder = recorder
        self.startDate = Date()
        self.lastDuration = 0
        startMetering()

        return targetURL
    }

    func stopRecording() throws -> URL {
        guard let recorder else { throw RecorderError.notRecording }

        recorder.stop()
        stopMetering()

        let duration = max(0, Date().timeIntervalSince(startDate ?? Date()))
        lastDuration = duration

        let url = recorder.url
        self.recorder = nil
        self.startDate = nil

        return url
    }

    private func startMetering() {
        stopMetering()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(60))
        timer.setEventHandler { [weak self] in
            guard let self, let recorder = self.recorder else { return }
            recorder.updateMeters()
            let averagePower = recorder.averagePower(forChannel: 0)
            let rms = pow(10, averagePower / 20)
            let clampedRMS = max(0, min(1, rms))

            let now = DispatchTime.now()
            let frameDurationMs: Double
            if let last = self.lastMeterTimestamp {
                frameDurationMs = Double(now.uptimeNanoseconds - last.uptimeNanoseconds) / 1_000_000
            } else {
                frameDurationMs = 60
            }
            self.lastMeterTimestamp = now

            self.onRMS?(clampedRMS)
            self.onMeterSample?(
                MeterSample(
                    rms: clampedRMS,
                    dbInstant: averagePower,
                    frameDurationMs: frameDurationMs
                )
            )
        }
        timer.resume()
        meterTimer = timer
    }

    private func stopMetering() {
        meterTimer?.cancel()
        meterTimer = nil
        lastMeterTimestamp = nil
    }
}
