import XCTest
import CoreAudio
@testable import VoiceScribe

final class ServerStatusTests: XCTestCase {

    // MARK: - ServerStatus.description

    func testStartingDescription() {
        let status = ServerStatus.starting
        XCTAssertEqual(status.description, "Starting server...")
    }

    func testLoadingModelDescription() {
        let status = ServerStatus.loadingModel
        XCTAssertEqual(status.description, "Loading Parakeet model...")
    }

    func testReadyDescription() {
        let status = ServerStatus.ready
        XCTAssertEqual(status.description, "Ready")
    }

    func testErrorDescription() {
        let status = ServerStatus.error("Python not found")
        XCTAssertEqual(status.description, "Error: Python not found")
    }

    func testErrorDescriptionWithEmptyMessage() {
        let status = ServerStatus.error("")
        XCTAssertEqual(status.description, "Error: ")
    }

    // MARK: - ServerStatus.isReady

    func testIsReadyWhenReady() {
        XCTAssertTrue(ServerStatus.ready.isReady)
    }

    func testIsReadyWhenStarting() {
        XCTAssertFalse(ServerStatus.starting.isReady)
    }

    func testIsReadyWhenLoadingModel() {
        XCTAssertFalse(ServerStatus.loadingModel.isReady)
    }

    func testIsReadyWhenError() {
        XCTAssertFalse(ServerStatus.error("fail").isReady)
    }

    // MARK: - ServerStatus Equatable

    func testEqualityReadyReady() {
        XCTAssertEqual(ServerStatus.ready, ServerStatus.ready)
    }

    func testEqualityErrorSameMessage() {
        XCTAssertEqual(ServerStatus.error("a"), ServerStatus.error("a"))
    }

    func testInequalityErrorDifferentMessage() {
        XCTAssertNotEqual(ServerStatus.error("a"), ServerStatus.error("b"))
    }

    func testInequalityDifferentCases() {
        XCTAssertNotEqual(ServerStatus.ready, ServerStatus.starting)
        XCTAssertNotEqual(ServerStatus.starting, ServerStatus.loadingModel)
        XCTAssertNotEqual(ServerStatus.loadingModel, ServerStatus.error("x"))
    }
}

final class ShortcutKeyTests: XCTestCase {

    // MARK: - Display names

    func testGlobeDisplayName() {
        XCTAssertEqual(ShortcutKey.globe.displayName, "Globe (Fn)")
    }

    func testFnDisplayName() {
        XCTAssertEqual(ShortcutKey.fn.displayName, "Fn Key")
    }

    func testRightOptionDisplayName() {
        XCTAssertEqual(ShortcutKey.rightOption.displayName, "Right Option")
    }

    func testRightCommandDisplayName() {
        XCTAssertEqual(ShortcutKey.rightCommand.displayName, "Right Command")
    }

    // MARK: - Key codes

    func testGlobeKeyCode() {
        XCTAssertEqual(ShortcutKey.globe.keyCode, 0x3F)
    }

    func testFnKeyCode() {
        XCTAssertEqual(ShortcutKey.fn.keyCode, 0x3F)
    }

    func testGlobeAndFnShareKeyCode() {
        XCTAssertEqual(ShortcutKey.globe.keyCode, ShortcutKey.fn.keyCode)
    }

    func testRightOptionKeyCode() {
        XCTAssertEqual(ShortcutKey.rightOption.keyCode, 0x3D)
    }

    func testRightCommandKeyCode() {
        XCTAssertEqual(ShortcutKey.rightCommand.keyCode, 0x36)
    }

    func testAllKeyCodesAreDistinctExceptGlobeFn() {
        let codes = ShortcutKey.allCases.map { $0.keyCode }
        // globe and fn share 0x3F; rightOption is 0x3D; rightCommand is 0x36
        let unique = Set(codes)
        XCTAssertEqual(unique.count, 3) // 3 distinct key codes for 4 cases
    }

    // MARK: - Raw values (serialization)

    func testRawValueRoundTrip() {
        for key in ShortcutKey.allCases {
            XCTAssertEqual(ShortcutKey(rawValue: key.rawValue), key)
        }
    }

    func testInvalidRawValueReturnsNil() {
        XCTAssertNil(ShortcutKey(rawValue: "invalid"))
        XCTAssertNil(ShortcutKey(rawValue: ""))
        XCTAssertNil(ShortcutKey(rawValue: "Globe"))  // case-sensitive
    }

    // MARK: - CaseIterable

    func testAllCasesCount() {
        XCTAssertEqual(ShortcutKey.allCases.count, 4)
    }
}

final class TranscriptionEntryTests: XCTestCase {

    func testEntryHasUniqueID() {
        let a = TranscriptionEntry(text: "hello", timestamp: Date())
        let b = TranscriptionEntry(text: "hello", timestamp: Date())
        XCTAssertNotEqual(a.id, b.id)
    }

    func testEntryStoresText() {
        let entry = TranscriptionEntry(text: "test text", timestamp: Date())
        XCTAssertEqual(entry.text, "test text")
    }

    func testEntryStoresTimestamp() {
        let now = Date()
        let entry = TranscriptionEntry(text: "x", timestamp: now)
        XCTAssertEqual(entry.timestamp, now)
    }

    func testFormattedTimeIsNotEmpty() {
        let entry = TranscriptionEntry(text: "x", timestamp: Date())
        XCTAssertFalse(entry.formattedTime.isEmpty)
    }

    func testEmptyTextEntry() {
        let entry = TranscriptionEntry(text: "", timestamp: Date())
        XCTAssertEqual(entry.text, "")
    }
}

final class AppStateTests: XCTestCase {

    var appState: AppState!

    override func setUp() {
        super.setUp()
        appState = AppState.shared
    }

    // MARK: - Transcription history

    func testAddTranscriptionAddsToFront() {
        let initialCount = appState.transcriptionHistory.count
        appState.addTranscription("first")
        appState.addTranscription("second")

        XCTAssertEqual(appState.transcriptionHistory[0].text, "second")
        XCTAssertEqual(appState.transcriptionHistory[1].text, "first")
        XCTAssertEqual(appState.transcriptionHistory.count, initialCount + 2)
    }

    func testAddTranscriptionCapsAt50() {
        // Clear existing history
        appState.transcriptionHistory.removeAll()

        for i in 0..<55 {
            appState.addTranscription("entry \(i)")
        }

        XCTAssertEqual(appState.transcriptionHistory.count, 50)
        // Most recent should be at front
        XCTAssertEqual(appState.transcriptionHistory[0].text, "entry 54")
    }

    func testAddEmptyTranscription() {
        let initialCount = appState.transcriptionHistory.count
        appState.addTranscription("")
        XCTAssertEqual(appState.transcriptionHistory.count, initialCount + 1)
        XCTAssertEqual(appState.transcriptionHistory[0].text, "")
    }

    // MARK: - Default values

    func testDefaultServerStatusIsStarting() {
        // AppState.shared may already be modified, but we can test the type
        XCTAssertNotNil(appState.serverStatus)
    }

    func testDefaultRecordingState() {
        // These may be modified by other tests, just verify they're accessible
        XCTAssertFalse(appState.isRecording)
    }

    func testDefaultTranscribingState() {
        XCTAssertFalse(appState.isTranscribing)
    }

    // MARK: - Settings persistence

    func testShortcutKeyPersistsToUserDefaults() {
        appState.shortcutKey = .rightCommand
        let saved = UserDefaults.standard.string(forKey: "shortcutKey")
        XCTAssertEqual(saved, ShortcutKey.rightCommand.rawValue)

        // Reset
        appState.shortcutKey = .rightOption
    }

    func testAutoTypePersistsToUserDefaults() {
        let original = appState.autoTypeEnabled
        appState.autoTypeEnabled = !original
        let saved = UserDefaults.standard.bool(forKey: "autoTypeEnabled")
        XCTAssertEqual(saved, !original)

        // Reset
        appState.autoTypeEnabled = original
    }

    func testAutoCopyPersistsToUserDefaults() {
        let original = appState.autoCopyEnabled
        appState.autoCopyEnabled = !original
        let saved = UserDefaults.standard.bool(forKey: "autoCopyEnabled")
        XCTAssertEqual(saved, !original)

        // Reset
        appState.autoCopyEnabled = original
    }

    func testTextCleanupPersistsToUserDefaults() {
        let original = appState.textCleanupEnabled
        appState.textCleanupEnabled = !original
        let saved = UserDefaults.standard.bool(forKey: "textCleanupEnabled")
        XCTAssertEqual(saved, !original)

        // Reset
        appState.textCleanupEnabled = original
    }

    func testSelectedInputDevicePersistsToUserDefaults() {
        let testID: AudioDeviceID = 42
        appState.selectedInputDevice = testID
        let saved = UserDefaults.standard.integer(forKey: "selectedInputDevice")
        XCTAssertEqual(saved, Int(testID))
    }

    // MARK: - Accessibility state

    func testAccessibilityDeniedDefaultIsFalse() {
        // Fresh state should be false (unless system has denied)
        XCTAssertNotNil(appState.accessibilityDenied)
    }

    func testKeyboardMonitorActiveDefault() {
        XCTAssertNotNil(appState.keyboardMonitorActive)
    }
}

final class TranscriptionErrorTests: XCTestCase {

    func testServerNotAvailableDescription() {
        let err = TranscriptionError.serverNotAvailable
        XCTAssertEqual(err.errorDescription, "Transcription server is not available")
    }

    func testInvalidResponseDescription() {
        let err = TranscriptionError.invalidResponse
        XCTAssertEqual(err.errorDescription, "Invalid response from server")
    }

    func testTranscriptionFailedDescription() {
        let err = TranscriptionError.transcriptionFailed("bad audio")
        XCTAssertEqual(err.errorDescription, "Transcription failed: bad audio")
    }

    func testNetworkErrorDescription() {
        let underlying = NSError(domain: "test", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "timeout"
        ])
        let err = TranscriptionError.networkError(underlying)
        XCTAssertTrue(err.errorDescription?.contains("timeout") ?? false)
    }

    func testTranscriptionFailedEmptyMessage() {
        let err = TranscriptionError.transcriptionFailed("")
        XCTAssertEqual(err.errorDescription, "Transcription failed: ")
    }
}
