import Foundation
import Testing
@testable import Transcript

private typealias F = TranscriptFixture

@Suite struct TranscriptChatAssemblyTests {
    @Test func aUserStringEntryBecomesAPrompt() {
        let blocks = F.blocks([F.prompt("u1", "  Fix the sync  ", at: 5)])
        #expect(blocks == [ChatBlock(id: "u1", kind: .prompt("Fix the sync"), at: F.time(5))])
    }

    @Test func aUserEntryWithTextBlocksBecomesAPromptAndIgnoresImages() {
        let blocks = F.blocks([F.user("u1", content: [F.text("Look at this"), ["type": "image", "source": [:]], F.text("and this")])])
        #expect(blocks.map(\.kind) == [.prompt("Look at this\nand this")])
    }

    @Test func assistantTextBecomesAReply() {
        let blocks = F.blocks([F.assistant("a1", [F.text("Done.")], at: 7)])
        #expect(blocks == [ChatBlock(id: "a1", kind: .reply("Done."), at: F.time(7))])
    }

    @Test func consecutiveTextOfOneTurnMergesIntoOneReplyKeepingTheFirstIDAndTime() {
        let blocks = F.blocks([
            F.assistant("a1", [F.text("First.")], at: 1),
            F.assistant("a2", [F.thinking()], at: 2),
            F.assistant("a3", [F.text("Second.")], at: 3),
        ])
        #expect(blocks == [ChatBlock(id: "a1", kind: .reply("First.\n\nSecond."), at: F.time(1))])
    }

    @Test func thinkingAloneProducesNoBlock() {
        #expect(F.blocks([F.assistant("a1", [F.thinking()])]).isEmpty)
    }

    @Test func everyToolCallOfATurnFoldsIntoOneToolsBlockBeforeItsReply() {
        let blocks = F.blocks([
            F.assistant("a1", [F.toolUse("t1", "Read", ["file_path": "/src/a.swift"])], at: 1),
            F.user("r1", content: [F.toolResult("t1", "line one")], at: 2),
            F.assistant("a2", [F.toolUse("t2", "Bash", ["command": "swift build", "description": "Build"])], at: 3),
            F.user("r2", content: [F.toolResult("t2", "Build complete")], at: 4),
            F.assistant("a3", [F.text("It builds.")], at: 5),
            F.assistant("a4", [F.toolUse("t3", "Grep", ["pattern": "TODO", "path": "/src"])], at: 6),
        ])
        #expect(blocks == [
            ChatBlock(id: "a1", kind: .tools(summary: "read 1 file · ran 1 shell command · searched once", calls: [
                ToolCall(name: "Read", summary: "/src/a.swift", result: "line one"),
                ToolCall(name: "Bash", summary: "swift build", result: "Build complete"),
                ToolCall(name: "Grep", summary: "TODO", result: nil),
            ]), at: F.time(1)),
            ChatBlock(id: "a3", kind: .reply("It builds."), at: F.time(5)),
        ])
    }

    @Test func textBetweenToolCallsJoinsOneReplyAfterTheTurnsToolLine() {
        let blocks = F.blocks([
            F.user("p1", content: "check the build", at: 0),
            F.assistant("a1", [F.text("Let me look.")], at: 1),
            F.assistant("a2", [F.toolUse("t1", "Bash", ["command": "swift build"])], at: 2),
            F.user("r1", content: [F.toolResult("t1", "Build complete")], at: 3),
            F.assistant("a3", [F.text("It builds.")], at: 4),
            F.assistant("a4", [F.toolUse("t2", "Bash", ["command": "swift test"])], at: 5),
            F.user("r2", content: [F.toolResult("t2", "All passed")], at: 6),
            F.assistant("a5", [F.text("Tests pass too.")], at: 7),
        ])
        #expect(blocks == [
            ChatBlock(id: "p1", kind: .prompt("check the build"), at: F.time(0)),
            ChatBlock(id: "a2", kind: .tools(summary: "ran 2 shell commands", calls: [
                ToolCall(name: "Bash", summary: "swift build", result: "Build complete"),
                ToolCall(name: "Bash", summary: "swift test", result: "All passed"),
            ]), at: F.time(2)),
            ChatBlock(id: "a1", kind: .reply("Let me look.\n\nIt builds.\n\nTests pass too."), at: F.time(1)),
        ])
    }

    @Test func eachTurnGetsItsOwnToolLine() {
        let blocks = F.blocks([
            F.user("p1", content: "first", at: 0),
            F.assistant("a1", [F.toolUse("t1", "Read", ["file_path": "/a"])], at: 1),
            F.assistant("a2", [F.text("Done.")], at: 2),
            F.user("p2", content: "second", at: 3),
            F.assistant("a3", [F.toolUse("t2", "Read", ["file_path": "/b"])], at: 4),
        ])
        #expect(blocks.map(\.id) == ["p1", "a1", "a2", "p1#end", "p2", "a3"])
    }

    @Test func aToolResultWithTextBlocksIsJoinedAndImagesAreDropped() {
        let blocks = F.blocks([
            F.assistant("a1", [F.toolUse("t1", "WebFetch", ["url": "https://example.com", "prompt": "Summarise"])]),
            F.user("r1", content: [F.toolResult("t1", [F.text("alpha"), ["type": "image", "source": [:]], F.text("beta")])]),
        ])
        #expect(blocks.map(\.kind) == [.tools(summary: "used WebFetch", calls: [
            ToolCall(name: "WebFetch", summary: "https://example.com", result: "alpha\nbeta"),
        ])])
    }

    @Test func aToolResultWithoutItsCallInViewIsIgnored() {
        #expect(F.blocks([F.user("r1", content: [F.toolResult("missing", "out")])]).isEmpty)
    }

    @Test func oneEntryWithSeveralBlocksGivesDistinctIDs() {
        let blocks = F.blocks([F.assistant("a1", [F.text("Checking."), F.toolUse("t1", "Glob", ["pattern": "*.swift"]), F.text("Found it.")])])
        #expect(blocks.map(\.id) == ["a1#1", "a1"])
        #expect(blocks.last?.kind == .reply("Checking.\n\nFound it."))
    }

    @Test func theTurnDurationMarkerEndsTheTurn() {
        let blocks = F.blocks([
            F.prompt("u1", "Go", at: 0),
            F.assistant("a1", [F.text("Gone.")], at: 4),
            F.turnDuration("s1", milliseconds: 4_250, at: 4.5),
        ])
        #expect(blocks.last == ChatBlock(id: "s1", kind: .turnEnded(duration: .milliseconds(4_250)), at: F.time(4.5)))
    }

    @Test func withoutAMarkerTheTurnEndsAtTheLastAssistantEntryBeforeTheNextPrompt() {
        let blocks = F.blocks([
            F.prompt("u1", "Go", at: 10),
            F.assistant("a1", [F.text("Working.")], at: 12),
            F.assistant("a2", [F.thinking()], at: 16.5),
            F.prompt("u2", "Next", at: 30),
        ])
        #expect(blocks == [
            ChatBlock(id: "u1", kind: .prompt("Go"), at: F.time(10)),
            ChatBlock(id: "a1", kind: .reply("Working."), at: F.time(12)),
            ChatBlock(id: "u1#end", kind: .turnEnded(duration: .milliseconds(6_500)), at: F.time(16.5)),
            ChatBlock(id: "u2", kind: .prompt("Next"), at: F.time(30)),
        ])
    }

    @Test func aTurnInProgressHasNoEnd() {
        let blocks = F.blocks([F.prompt("u1", "Go"), F.assistant("a1", [F.text("Working.")], at: 2)])
        #expect(blocks.map(\.id) == ["u1", "a1"])
    }

    @Test func aMarkedTurnIsNotEndedTwiceWhenTheNextPromptArrives() {
        let blocks = F.blocks([
            F.prompt("u1", "Go"),
            F.assistant("a1", [F.text("Gone.")], at: 1),
            F.turnDuration("s1", milliseconds: 1_000, at: 1),
            F.prompt("u2", "Next", at: 9),
        ])
        #expect(blocks.map(\.id) == ["u1", "a1", "s1", "u2"])
    }

    @Test(arguments: [
        F.prompt("m1", "Injected context", extra: ["isMeta": true]),
        F.prompt("m2", "Subagent prompt", extra: ["isSidechain": true]),
        F.prompt("m3", "Summary of the conversation so far", extra: ["isCompactSummary": true]),
        F.prompt("m4", "<command-name>/clear</command-name>\n<command-message>clear</command-message>"),
        F.prompt("m5", "<local-command-caveat>Caveat: synthetic</local-command-caveat>"),
        F.prompt("m6", "<local-command-stdout>synthetic</local-command-stdout>"),
        F.prompt("m7", "<task-notification>\n<task-id>x</task-id>\n</task-notification>"),
        F.prompt("m8", "Plugin prompt", extra: ["origin": ["kind": "plugin", "name": "synthetic"]]),
        F.user("m9", content: [F.text("[Request interrupted by user]")]),
        F.user("m10", content: [F.toolResult("t1", "out")]),
        F.user("m11", content: "   "),
        F.assistant("m12", [F.text("Subagent reply")], extra: ["isSidechain": true]),
        F.entry(["type": "summary", "summary": "synthetic", "leafUuid": "x"], [:]),
        F.entry(["type": "system", "subtype": "stop_hook_summary", "uuid": "m13"], [:]),
        F.entry(["type": "system", "subtype": "informational", "uuid": "m15", "durationMs": 5], [:]),
        F.entry(["type": "attachment", "uuid": "m14", "attachment": [:]], [:]),
        F.entry(["type": "attachment", "uuid": "m16", "attachment": ["type": "edited_text_file", "commandMode": "prompt", "prompt": "synthetic"]], [:]),
        F.queuedCommand("m17", prompt: "<task-notification>x</task-notification>", mode: "task-notification",
                        origin: ["kind": "task-notification"]),
        F.queuedCommand("m18", prompt: "Background task finished", mode: "task-notification", origin: nil),
        F.queuedCommand("m19", prompt: "Plugin prompt", origin: ["kind": "plugin", "name": "synthetic"]),
        F.queuedCommand("m20", prompt: "Subagent prompt", extra: ["isSidechain": true]),
        F.queuedCommand("m21", prompt: "<local-command-stdout>synthetic</local-command-stdout>"),
        F.prompt("m22", "<bash-stdout>synthetic output</bash-stdout><bash-stderr></bash-stderr>"),
        F.prompt("m23", "<bash-stderr>synthetic error</bash-stderr>"),
        "not json",
        "[1, 2]",
    ])
    func entriesThatAreNotChatProduceNoBlock(line: String) {
        #expect(F.blocks([line]).isEmpty)
    }

    @Test func aHumanOriginPromptIsKept() {
        let blocks = F.blocks([F.prompt("u1", "Typed", extra: ["origin": ["kind": "human"], "promptSource": "typed"])])
        #expect(blocks.map(\.kind) == [.prompt("Typed")])
    }

    @Test func aPromptQueuedWhileClaudeWorkedBecomesAPrompt() {
        let blocks = F.blocks([F.queuedCommand("q1", prompt: "  Also check the tests  ", at: 4)])
        #expect(blocks == [ChatBlock(id: "q1", kind: .prompt("Also check the tests"), at: F.time(4))])
    }

    @Test func aPromptQueuedMidTurnJoinsTheRunningTurnUnderItsPrompt() {
        let blocks = F.blocks([
            F.prompt("p1", "Fix the sync", at: 0),
            F.assistant("a1", [F.toolUse("t1", "Bash", ["command": "swift build"])], at: 1),
            F.user("r1", content: [F.toolResult("t1", "Build complete")], at: 2),
            F.queuedCommand("q1", prompt: "Also check the tests", at: 3),
            F.assistant("a2", [F.toolUse("t2", "Bash", ["command": "swift test"])], at: 4),
            F.user("r2", content: [F.toolResult("t2", "All passed")], at: 5),
            F.assistant("a3", [F.text("Fixed and tested.")], at: 6),
            F.turnDuration("s1", milliseconds: 6_000, at: 6),
        ])
        #expect(blocks == [
            ChatBlock(id: "p1", kind: .prompt("Fix the sync"), at: F.time(0)),
            ChatBlock(id: "q1", kind: .prompt("Also check the tests"), at: F.time(3)),
            ChatBlock(id: "a1", kind: .tools(summary: "ran 2 shell commands", calls: [
                ToolCall(name: "Bash", summary: "swift build", result: "Build complete"),
                ToolCall(name: "Bash", summary: "swift test", result: "All passed"),
            ]), at: F.time(1)),
            ChatBlock(id: "a3", kind: .reply("Fixed and tested."), at: F.time(6)),
            ChatBlock(id: "s1", kind: .turnEnded(duration: .milliseconds(6_000)), at: F.time(6)),
        ])
    }

    @Test func aPromptQueuedAfterATurnEndedStartsTheNextTurn() {
        let blocks = F.blocks([
            F.prompt("p1", "Go", at: 0),
            F.assistant("a1", [F.text("Done.")], at: 1),
            F.turnDuration("s1", milliseconds: 1_000, at: 1),
            F.queuedCommand("q1", prompt: "Next", at: 2),
            F.assistant("a2", [F.text("On it.")], at: 3),
        ])
        #expect(blocks.map(\.id) == ["p1", "a1", "s1", "q1", "a2"])
    }

    @Test func assistantOutputAfterAMarkedEndOpensATurnOfItsOwn() {
        let blocks = F.blocks([
            F.prompt("p1", "Start the build", at: 0),
            F.assistant("a1", [F.text("Started.")], at: 1),
            F.turnDuration("s1", milliseconds: 1_000, at: 1),
            F.assistant("a2", [F.text("The build finished.")], at: 9),
            F.turnDuration("s2", milliseconds: 500, at: 9),
        ])
        #expect(blocks == [
            ChatBlock(id: "p1", kind: .prompt("Start the build"), at: F.time(0)),
            ChatBlock(id: "a1", kind: .reply("Started."), at: F.time(1)),
            ChatBlock(id: "s1", kind: .turnEnded(duration: .milliseconds(1_000)), at: F.time(1)),
            ChatBlock(id: "a2", kind: .reply("The build finished."), at: F.time(9)),
            ChatBlock(id: "s2", kind: .turnEnded(duration: .milliseconds(500)), at: F.time(9)),
        ])
    }

    @Test func aQueuedPromptWithBlocksJoinsItsTextAndIgnoresImages() {
        let blocks = F.blocks([F.queuedCommand("q1", prompt: [F.text("Look at this"), ["type": "image", "source": [:]], F.text("and this")])])
        #expect(blocks.map(\.kind) == [.prompt("Look at this\nand this")])
    }

    @Test func aQueuedPromptWithoutAnOriginIsKept() {
        #expect(F.blocks([F.queuedCommand("q1", prompt: "Typed", origin: nil)]).map(\.kind) == [.prompt("Typed")])
    }

    @Test func aShellCommandTypedAfterABangIsAPromptMarkedWithTheBang() {
        let blocks = F.blocks([F.prompt("b1", "<bash-input>ls -la</bash-input>", at: 2)])
        #expect(blocks == [ChatBlock(id: "b1", kind: .prompt("! ls -la"), at: F.time(2))])
    }

    @Test func idsAreTheSameWhenTheSameLinesAreReadAgain() {
        let lines = [
            F.prompt("u1", "Go"),
            F.assistant("a1", [F.toolUse("t1", "Bash", ["command": "ls"])], at: 1),
            F.user("r1", content: [F.toolResult("t1", "out")], at: 2),
            F.assistant("a2", [F.text("Listed.")], at: 3),
            F.turnDuration("s1", milliseconds: 3_000, at: 3),
        ]
        #expect(F.blocks(lines).map(\.id) == ["u1", "a1", "a2", "s1"])
    }

    @Test func aMissingTimestampLeavesTheBlockUndated() {
        let line = F.entry(["type": "user", "uuid": "u1", "message": ["role": "user", "content": "Hi"]], [:])
        #expect(F.blocks([line]) == [ChatBlock(id: "u1", kind: .prompt("Hi"), at: nil)])
    }
}
