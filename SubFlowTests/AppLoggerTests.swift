import Testing
import Foundation
@testable import SubFlow

// AppLogger tests must run serially since they share a single log file
@Suite(.serialized)
struct AppLoggerTests {
    @Test func pathIsNotEmpty() {
        #expect(!AppLogger.path.isEmpty)
    }

    @Test func pathEndsWithCorrectFilename() {
        #expect(AppLogger.path.hasSuffix("SubFlow.log"))
    }

    @Test func clearAndLogWritesContent() {
        AppLogger.clear()
        AppLogger.log("Test message for unit test")

        let content = try? String(contentsOfFile: AppLogger.path, encoding: .utf8)
        #expect(content != nil)
        #expect(content!.contains("Test message for unit test"))
    }

    @Test func clearEmptiesFile() {
        AppLogger.log("Something to clear")
        AppLogger.clear()

        let content = try? String(contentsOfFile: AppLogger.path, encoding: .utf8)
        #expect(content != nil)
        #expect(content!.isEmpty)
    }

    @Test func multipleMessagesAreAppended() {
        AppLogger.clear()
        AppLogger.log("First line")
        AppLogger.log("Second line")

        let content = try? String(contentsOfFile: AppLogger.path, encoding: .utf8)
        #expect(content != nil)
        #expect(content!.contains("First line"))
        #expect(content!.contains("Second line"))
    }

    @Test func messageIncludesTimestamp() {
        AppLogger.clear()
        AppLogger.log("Timestamped")

        let content = try? String(contentsOfFile: AppLogger.path, encoding: .utf8)
        #expect(content != nil)
        // Log format is [HH:mm:ss.SSS] message
        #expect(content!.contains("["))
        #expect(content!.contains("]"))
        #expect(content!.contains("Timestamped"))
    }

    @Test func multipleArguments() {
        AppLogger.clear()
        AppLogger.log("Context:", "detail1", "detail2")

        let content = try? String(contentsOfFile: AppLogger.path, encoding: .utf8)
        #expect(content != nil)
        #expect(content!.contains("Context: detail1 detail2"))
    }
}
