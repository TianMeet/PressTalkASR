import XCTest
@testable import PressTalkASR

final class SessionPhaseTests: XCTestCase {
    func testPhaseFlagsAndIconMapping() {
        XCTAssertFalse(SessionPhase.idle.isRecording)
        XCTAssertFalse(SessionPhase.idle.isTranscribing)
        XCTAssertEqual(SessionPhase.idle.menuBarIconName, "mic")

        XCTAssertTrue(SessionPhase.listening.isRecording)
        XCTAssertFalse(SessionPhase.listening.isTranscribing)
        XCTAssertEqual(SessionPhase.listening.menuBarIconName, "mic.fill")

        XCTAssertFalse(SessionPhase.transcribing.isRecording)
        XCTAssertTrue(SessionPhase.transcribing.isTranscribing)
        XCTAssertEqual(SessionPhase.transcribing.menuBarIconName, "waveform.badge.magnifyingglass")
    }

    func testSessionStatusInitFromPhase() {
        XCTAssertEqual(AppViewModel.SessionStatus(phase: .idle).title, L10n.tr("status.idle"))
        XCTAssertEqual(AppViewModel.SessionStatus(phase: .listening).title, L10n.tr("status.listening"))
        XCTAssertEqual(AppViewModel.SessionStatus(phase: .transcribing).title, L10n.tr("status.transcribing"))
    }
}
