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
        case noSupportedRecordingFormat

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return L10n.tr("error.recorder.permission_denied")
            case .alreadyRecording:
                return L10n.tr("error.recorder.already_recording")
            case .recorderInitFailed:
                return L10n.tr("error.recorder.init_failed")
            case .recordingStartFailed:
                return L10n.tr("error.recorder.start_failed")
            case .notRecording:
                return L10n.tr("error.recorder.not_recording")
            case .noSupportedRecordingFormat:
                return L10n.tr("error.recorder.no_supported_format")
            }
        }
    }

    var onRMS: ((Float) -> Void)?
    var onMeterSample: ((MeterSample) -> Void)?

    private enum Constants {
        static let meteringIntervalMs = 90
        /// 优先使用较低采样率：OpenAI STT 内部以 16kHz 处理，22.05kHz 足够且文件更小
        static let aacPreferredSampleRate: Double = 22_050
        static let aacFallbackSampleRate: Double = 44_100
        static let pcmSampleRate: Double = 16_000
        static let aacBitRate = 64_000
    }

    private(set) var lastDuration: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var startUptime: TimeInterval?
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

        // Prefer compressed AAC for faster upload; if codec init fails on this Mac,
        // automatically fall back to PCM WAV so recording can still proceed.
        let candidates: [(ext: String, settings: [String: Any])] = [
            (
                "m4a",
                [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: Constants.aacPreferredSampleRate,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: Constants.aacBitRate,
                    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
                ]
            ),
            (
                "m4a",
                [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: Constants.aacFallbackSampleRate,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: Constants.aacBitRate,
                    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
                ]
            ),
            (
                "wav",
                [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: Constants.pcmSampleRate,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsFloatKey: false
                ]
            )
        ]

        var preparedRecorder: AVAudioRecorder?
        var preparedURL: URL?

        for candidate in candidates {
            let targetURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("press-talk-\(UUID().uuidString)")
                .appendingPathExtension(candidate.ext)

            do {
                let recorder = try AVAudioRecorder(url: targetURL, settings: candidate.settings)
                recorder.isMeteringEnabled = true
                recorder.prepareToRecord()
                if recorder.record() {
                    preparedRecorder = recorder
                    preparedURL = targetURL
                    break
                }
            } catch {
                continue
            }
        }

        guard let recorder = preparedRecorder, let outputURL = preparedURL else {
            throw RecorderError.noSupportedRecordingFormat
        }

        self.recorder = recorder
        self.startUptime = ProcessInfo.processInfo.systemUptime
        self.lastDuration = 0
        startMetering()

        return outputURL
    }

    func stopRecording() throws -> URL {
        guard let recorder else { throw RecorderError.notRecording }

        recorder.stop()
        stopMetering()

        let nowUptime = ProcessInfo.processInfo.systemUptime
        let duration = max(0, nowUptime - (startUptime ?? nowUptime))
        lastDuration = duration

        let url = recorder.url
        self.recorder = nil
        self.startUptime = nil

        return url
    }

    private func startMetering() {
        stopMetering()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        // Lower metering frequency to reduce load on busy systems.
        timer.schedule(deadline: .now(), repeating: .milliseconds(Constants.meteringIntervalMs))
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
                frameDurationMs = 90
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
