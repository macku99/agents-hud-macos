import Foundation
import Testing
@testable import Transcript

@Suite struct TranscriptTailTests {
    private let directory: URL
    private let file: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "TranscriptTailTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appending(path: "session.jsonl")
    }

    private func write(_ text: String, to url: URL? = nil) throws {
        try Data(text.utf8).write(to: url ?? file)
    }

    private func append(_ text: String) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    private func lines(_ texts: String...) -> [Data] { texts.map { Data($0.utf8) } }

    private func cleanUp() { try? FileManager.default.removeItem(at: directory) }

    @Test func aSmallFileIsReadWhole() throws {
        defer { cleanUp() }
        try write("one\ntwo\n")
        var tail = TranscriptTail(url: file, initialBytes: 1_024)
        #expect(try tail.read() == .restarted(lines("one", "two")))
    }

    @Test func aLongFileIsReadFromItsTailSkippingThePartialFirstLine() throws {
        defer { cleanUp() }
        try write("first line\nsecond line\nthird\n")
        var tail = TranscriptTail(url: file, initialBytes: 14)
        #expect(try tail.read() == .restarted(lines("third")))
    }

    @Test func aTailStartingExactlyOnALineKeepsThatLine() throws {
        defer { cleanUp() }
        try write("first line\nsecond line\nthird\n")
        var tail = TranscriptTail(url: file, initialBytes: 18)
        #expect(try tail.read() == .restarted(lines("second line", "third")))
    }

    @Test func aTailInsideOneLongLineSkipsThatLineEvenAfterItEnds() throws {
        defer { cleanUp() }
        try write("one\n" + String(repeating: "x", count: 100))
        var tail = TranscriptTail(url: file, initialBytes: 10)
        #expect(try tail.read() == .restarted([]))
        try append("xxx\nnext\n")
        #expect(try tail.read() == .appended(lines("next")))
    }

    @Test func growthReadsOnlyTheAppendedLines() throws {
        defer { cleanUp() }
        try write("one\n")
        var tail = TranscriptTail(url: file, initialBytes: 1_024)
        _ = try tail.read()
        #expect(try tail.read() == .appended([]))
        try append("two\nthree\n")
        #expect(try tail.read() == .appended(lines("two", "three")))
    }

    @Test func anUnfinishedLastLineWaitsForItsNewline() throws {
        defer { cleanUp() }
        try write("one\n{\"half\":")
        var tail = TranscriptTail(url: file, initialBytes: 1_024)
        #expect(try tail.read() == .restarted(lines("one")))
        try append("true}\n")
        #expect(try tail.read() == .appended(lines("{\"half\":true}")))
    }

    @Test func aTruncatedFileIsReadAgainFromTheStart() throws {
        defer { cleanUp() }
        try write("one\ntwo\nthree\n")
        var tail = TranscriptTail(url: file, initialBytes: 1_024)
        _ = try tail.read()
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("fresh\n".utf8))
        try handle.close()
        #expect(try tail.read() == .restarted(lines("fresh")))
    }

    @Test func aFileTruncatedAndRegrownBetweenReadsIsReadAgainFromTheStart() throws {
        defer { cleanUp() }
        try write("one\ntwo\n")
        var tail = TranscriptTail(url: file, initialBytes: 1_024)
        _ = try tail.read()
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("replacement line\n".utf8))
        try handle.close()
        #expect(try tail.read() == .restarted(lines("replacement line")))
    }

    @Test func aReplacedFileIsReadAgainFromTheStart() throws {
        defer { cleanUp() }
        try write("one\n")
        var tail = TranscriptTail(url: file, initialBytes: 1_024)
        _ = try tail.read()
        let replacement = directory.appending(path: "replacement.jsonl")
        try write("other one\nother two\n", to: replacement)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: replacement)
        #expect(try tail.read() == .restarted(lines("other one", "other two")))
    }

    @Test func aMissingFileThrows() {
        defer { cleanUp() }
        var tail = TranscriptTail(url: file, initialBytes: 1_024)
        #expect(throws: (any Error).self) { try tail.read() }
    }
}
