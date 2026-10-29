import Foundation
import Testing
@testable import Transcript

@Suite struct TranscriptToolCallTextTests {
    private func calls(_ names: [String]) -> [ToolCall] {
        names.map { ToolCall(name: $0, summary: "", result: nil) }
    }

    @Test(arguments: [
        (["Read"], "read 1 file"),
        (["Read", "Read"], "read 2 files"),
        (["Edit"], "edited 1 file"),
        (["Edit", "Write", "MultiEdit", "NotebookEdit"], "edited 4 files"),
        (["Bash"], "ran 1 shell command"),
        (["Bash", "Bash", "Bash", "Bash"], "ran 4 shell commands"),
        (["Grep"], "searched once"),
        (["Grep", "Glob", "Grep"], "searched 3 times"),
        (["WebFetch"], "used WebFetch"),
        (["WebFetch", "WebFetch"], "used WebFetch 2 times"),
        (["Read", "Bash", "Read", "Agent", "Grep", "Bash", "Bash", "Bash"],
         "read 2 files · ran 4 shell commands · used Agent · searched once"),
        ([], ""),
    ])
    func groupSummaryCountsByKindInOrderOfFirstUse(names: [String], expected: String) {
        #expect(ToolCall.groupSummary(of: calls(names)) == expected)
    }

    @Test(arguments: [
        ("Bash", ["command": "swift test --filter X\necho done", "description": "Run"], "swift test --filter X"),
        ("Read", ["file_path": "/src/a.swift", "offset": 3], "/src/a.swift"),
        ("Edit", ["file_path": "/src/b.swift", "old_string": "x", "new_string": "y"], "/src/b.swift"),
        ("Write", ["file_path": "/src/c.swift", "content": "z"], "/src/c.swift"),
        ("NotebookEdit", ["notebook_path": "/n.ipynb", "new_source": "z"], "/n.ipynb"),
        ("Grep", ["pattern": "TODO", "path": "/src"], "TODO"),
        ("Glob", ["pattern": "**/*.swift"], "**/*.swift"),
        ("Agent", ["description": "Review the diff", "prompt": "long"], "Review the diff"),
        ("WebFetch", ["url": "https://example.com", "prompt": "Summarise"], "https://example.com"),
        ("Mystery", ["count": 3], ""),
    ] as [(String, [String: any Sendable], String)])
    func callSummaryIsTheOneLineThatSaysWhatRan(name: String, input: [String: any Sendable], expected: String) {
        #expect(ToolCall.callSummary(name: name, input: input) == expected)
    }

    @Test func aLongCallSummaryIsCut() {
        let summary = ToolCall.callSummary(name: "Bash", input: ["command": String(repeating: "a", count: 500)])
        #expect(summary == String(repeating: "a", count: 200) + "…")
    }

    @Test func aShortResultIsKeptWhole() {
        #expect(ToolCall.shortenedResult("one\ntwo\nthree") == "one\ntwo\nthree")
    }

    @Test func aResultIsCutToThreeLines() {
        #expect(ToolCall.shortenedResult("one\ntwo\nthree\nfour\nfive") == "one\ntwo\nthree…")
    }

    @Test func windowsLineEndingsCountAsLinesForTheCut() {
        #expect(ToolCall.shortenedResult("one\r\ntwo\r\nthree\r\nfour\r\n") == "one\ntwo\nthree…")
    }

    @Test func aResultIsCutTo300Characters() {
        let long = String(repeating: "x", count: 1_000)
        #expect(ToolCall.shortenedResult(long) == String(repeating: "x", count: 300) + "…")
    }

    @Test func trailingWhitespaceIsDroppedAndAnEmptyResultIsNone() {
        #expect(ToolCall.shortenedResult("done\n\n") == "done")
        #expect(ToolCall.shortenedResult(" \n ") == nil)
    }
}
