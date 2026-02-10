import Foundation
import SwiftUI
import AppKit

@MainActor
final class HUDPresenter {
    private let layout: HUDLayoutConfig
    private let stateMachine: HUDStateMachine
    private let levelMeter: AudioLevelMeter
    private let settings: HUDSettingsStore
    private let window: FloatingHUDWindow

    var onRetry: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    init(layout: HUDLayoutConfig = HUDLayoutConfig()) {
        self.layout = layout
        self.stateMachine = HUDStateMachine()
        self.levelMeter = AudioLevelMeter()
        self.settings = HUDSettingsStore()

        let view = HUDView(
            stateMachine: stateMachine,
            levelMeter: levelMeter,
            settings: settings,
            layout: layout,
            onClose: { [weak stateMachine] in
                stateMachine?.dismiss()
            },
            onRetry: { },
            onOpenSettings: { }
        )

        self.window = FloatingHUDWindow(rootView: view, layout: layout)

        // Rebind with callback closures after self is fully initialized.
        let reboundView = HUDView(
            stateMachine: stateMachine,
            levelMeter: levelMeter,
            settings: settings,
            layout: layout,
            onClose: { [weak stateMachine] in
                stateMachine?.dismiss()
            },
            onRetry: { [weak self] in
                self?.onRetry?()
            },
            onOpenSettings: { [weak self] in
                self?.onOpenSettings?()
            }
        )
        window.setRootView(reboundView)

        stateMachine.onModeChanged = { [weak self] mode in
            self?.handleModeChanged(mode)
        }
    }

    func updateDisplaySettings(autoPasteEnabled: Bool, languageMode: String, modelMode: String) {
        if settings.autoPasteEnabled != autoPasteEnabled {
            settings.autoPasteEnabled = autoPasteEnabled
        }
        if settings.languageMode != languageMode {
            settings.languageMode = languageMode
        }
        if settings.modelMode != modelMode {
            settings.modelMode = modelMode
        }
    }

    func updateHUDAnchor(_ anchor: HUDAnchorPosition) {
        window.setAnchorPosition(anchor)
    }

    func updateRecordingElapsed(_ seconds: Int) {
        stateMachine.updateRecordingElapsed(seconds)
    }

    func updateRMS(_ rms: Float) {
        levelMeter.ingestRMS(rms)
    }

    func showListening() {
        levelMeter.setActive(true)
        stateMachine.showListening()
    }

    func showTranscribing() {
        levelMeter.setActive(false)
        stateMachine.showTranscribing()
    }

    func updateTranscribingPreview(_ text: String) {
        stateMachine.updateTranscribingPreview(text)
    }

    func showSuccess(_ text: String) {
        levelMeter.setActive(false)
        stateMachine.showSuccess(text)
    }

    func showError(_ reason: String) {
        levelMeter.setActive(false)
        stateMachine.showError(reason)
    }

    func dismiss() {
        stateMachine.dismiss()
    }

    func runDemoSequence() {
        Task { @MainActor in
            showListening()
            for _ in 0..<36 {
                updateRMS(Float.random(in: 0.08...0.85))
                try? await Task.sleep(nanoseconds: 55_000_000)
            }

            showTranscribing()
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            showSuccess("这是一个成功转写预览，用于验证两行省略与排版。")
            try? await Task.sleep(nanoseconds: 2_100_000_000)

            showError("环境噪声较大")
        }
    }

    private func handleModeChanged(_ mode: HUDMode) {
        switch mode {
        case .hidden:
            window.hide()
        default:
            let height = preferredHeight(for: mode)
            window.show(height: height)
        }
    }

    private func preferredHeight(for mode: HUDMode) -> CGFloat {
        switch mode {
        case .listening, .transcribing:
            return max(layout.minHeight, min(layout.maxHeight, 112))
        case .success(let text):
            let textHeight = textHeightForSuccess(text)
            let estimated = 96 + textHeight
            return max(layout.minHeight, min(layout.maxHeight, estimated))
        case .error:
            return max(layout.minHeight, min(layout.maxHeight, 138))
        case .hidden:
            return layout.minHeight
        }
    }

    private func textHeightForSuccess(_ text: String) -> CGFloat {
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .regular)]
        )

        let bounds = attributed.boundingRect(
            with: NSSize(width: layout.width - (layout.horizontalInset * 2), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        let twoLineCap: CGFloat = 34
        return min(twoLineCap, ceil(bounds.height))
    }

}
