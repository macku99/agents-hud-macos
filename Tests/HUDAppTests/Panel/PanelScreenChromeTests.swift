import Testing
@testable import HUDApp

@Suite struct PanelScreenChromeTests {
    private typealias Chrome = PanelController.ScreenChrome

    private static let rule = String(repeating: "─", count: 40)
    private static let screen = """
    ❯ fix the retry backoff

    ⏺ Resetting the backoff after a success.
      Edited WorkoutSync.swift (+6 -2)

    ✻ Worked for 1m 12s


    \(rule)
    \(rule)
    \(String(repeating: "─", count: 12))
    ❯\u{00A0}
    \(rule)
    \(rule)
      Opus 5.5 (1M context) | tmp | effort: high | 5h 2%
      ⏵⏵ auto mode on · ← 1 agent
    [ Handoff ] [ Reset ] [ View ] [ ⚙ ]
    """

    @Test func claudesInputBoxAndEverythingBelowItAreCut() {
        #expect(Chrome.strip(Self.screen, agent: "claude") == """
        ❯ fix the retry backoff

        ⏺ Resetting the backoff after a success.
          Edited WorkoutSync.swift (+6 -2)

        ✻ Worked for 1m 12s
        """)
    }

    @Test func aDraftTypedIntoTheInputBoxIsCutWithIt() {
        let screen = "⏺ Done.\n\(Self.rule)\n❯ gitignore the hook\n\(Self.rule)\n  status line"
        #expect(Chrome.strip(screen, agent: "claude") == "⏺ Done.")
    }

    @Test func earlierPromptsWithoutARuleAboveThemStay() {
        let screen = "❯ first prompt\n⏺ reply\n❯ second prompt\n⏺ another reply"
        #expect(Chrome.strip(screen, agent: "claude") == screen)
    }

    @Test func aScreenWithoutAnInputBoxIsLeftAlone() {
        let screen = "Which overlay situations do you hit?\n  1. Fullscreen Spaces\n  2. Multiple displays"
        #expect(Chrome.strip(screen, agent: "claude") == screen)
    }

    @Test func otherAgentsAreLeftAlone() {
        #expect(Chrome.strip(Self.screen, agent: "codex") == Self.screen)
    }

    /// A terminal 80 columns wide: the input box's rules span it, and right-aligned notices end at it.
    private static let wideRule = String(repeating: "─", count: 80)

    @Test func aRightAlignedNoticeAboveTheInputBoxIsCut() {
        let notice = "✔ Update installed · Restart to update"
        let screen = """
        ✻ Sautéed for 35s · done 1:27 PM

        \(String(repeating: " ", count: 80 - notice.count))\(notice)
        \(Self.wideRule)
        ❯ _
        \(Self.wideRule)
          Opus 5.5 (1M context) | herdr-hud-macos
        """
        #expect(Chrome.strip(screen, agent: "claude") == "✻ Sautéed for 35s · done 1:27 PM")
    }

    @Test func deeplyIndentedOutputEndingShortOfTheEdgeStays() {
        let kept = """
        ⏺ Ran the build
          ⎿  Build complete
        \(String(repeating: " ", count: 40))wrapped tail of the output
        """
        let screen = "\(kept)\n\n\(Self.wideRule)\n❯\n\(Self.wideRule)"
        #expect(Chrome.strip(screen, agent: "claude") == kept)
    }

    @Test func codeIndentedTwentyColumnsAboveTheInputBoxStays() {
        let kept = """
        ⏺ Change the guard to:
                              guard let x else {
                                  return
                              }
        """
        let screen = "\(kept)\n\(Self.rule)\n❯\n\(Self.rule)"
        #expect(Chrome.strip(screen, agent: "claude") == kept)
    }

    @Test func aModPaneAboveTheInputBoxIsCut() {
        let screen = """
        ⏺ Done.

        ╭──────────────────────────────╮
        │ Save this correction as a lesson? │
        │ [ Save ] [ Skip ]            │
        ╰──────────────────────────────╯
        \(Self.rule)
        ❯
        \(Self.rule)
        """
        #expect(Chrome.strip(screen, agent: "claude") == "⏺ Done.")
    }

    @Test func aModPaneThatReplacesTheInputBoxIsCutWithTheStatusLinesBelowIt() {
        let screen = """
        ⏺ Done.
        ╭──────────────────────────────╮
        │ Settings                     │
        ╰──────────────────────────────╯
          Opus 5.5 (1M context) | herdr-hud-macos
          ⏵⏵ bypass permissions on
        [ Handoff ] [ Reset ]
        """
        #expect(Chrome.strip(screen, agent: "claude") == "⏺ Done.")
    }

    @Test func theWelcomeBannerAndAShortExchangeAfterItStay() {
        let kept = """
        ╭─── Claude Code ───────────────╮
        │ Welcome back                  │
        ╰───────────────────────────────╯

        ❯ hi

        ⏺ Hello! What should I work on?
        """
        let screen = "\(kept)\n\n\(Self.rule)\n❯\n\(Self.rule)\n  status line"
        #expect(Chrome.strip(screen, agent: "claude") == kept)
    }

    @Test(arguments: ["※ recap: fixing the retry backoff", "! ls\n  ⎿  Package.swift", "● Hello from a Linux pane", "· Working… (2s)"])
    func theWelcomeBannerAndTheEntryAfterItStay(entry: String) {
        let kept = """
        ╭─── Claude Code ───────────────╮
        │ Welcome back                  │
        ╰───────────────────────────────╯

        \(entry)
        """
        let screen = "\(kept)\n\n\(Self.rule)\n❯\n\(Self.rule)"
        #expect(Chrome.strip(screen, agent: "claude") == kept)
    }

    @Test func aPaneAboveTheSpinnerStaysOnEveryFrame() {
        for frame in ["·", "✢", "✳", "✶", "✻", "✽", "*"] {
            let screen = """
            ⏺ Done.
            ╭──────────────────────────────╮
            │ Save this correction?        │
            ╰──────────────────────────────╯
            \(frame) Working… (4s)
            """
            #expect(Chrome.strip(screen, agent: "claude") == screen, "frame \(frame)")
        }
    }

    @Test func aLineRunningPastTheInputBoxsEdgeIsNotANotice() {
        let kept = "⏺ Output:\n\(String(repeating: " ", count: 24))\(String(repeating: "x", count: 70))"
        let screen = "\(kept)\n\(Self.wideRule)\n❯\n\(Self.wideRule)"
        #expect(Chrome.strip(screen, agent: "claude") == kept)
    }

    @Test func anIndentedRuleEndingAReplyStays() {
        let kept = "⏺ Summary\n  ──────────"
        let screen = "\(kept)\n\(Self.rule)\n❯\n\(Self.rule)"
        #expect(Chrome.strip(screen, agent: "claude") == kept)
    }

    @Test func anIndentedChoiceUnderARuleAtColumnZeroIsNotTheInputBox() {
        let screen = "⏺ Which one?\n──────────\n ❯ 1. Fullscreen\n   2. Multiple displays"
        #expect(Chrome.strip(screen, agent: "claude") == screen)
    }

    @Test func theInputBoxInShellModeIsCut() {
        let screen = "⏺ Done.\n\(Self.rule)\n! ls -la\n\(Self.rule)\n  ! for bash mode"
        #expect(Chrome.strip(screen, agent: "claude") == "⏺ Done.")
    }

    @Test func anIndentedChoiceUnderARuleIsNotTheInputBox() {
        let screen = "⏺ Which one?\n  ──────────\n ❯ 1. Fullscreen\n   2. Multiple displays"
        #expect(Chrome.strip(screen, agent: "claude") == screen)
    }

    @Test func aRoundedDiagramEndingAReplyStays() {
        let kept = """
        ⏺ The flow is:
          ╭────────╮
          │ client │
          ╰────────╯
        """
        let screen = "\(kept)\n\(Self.rule)\n❯\n\(Self.rule)"
        #expect(Chrome.strip(screen, agent: "claude") == kept)
    }

    @Test func anOldInputBoxAboveTheNewestReplyLeavesTheReplyInPlace() {
        let screen = """
        ⏺ older reply
        \(Self.rule)
        ❯ an old draft
        \(Self.rule)

        ⏺ newest reply the user wants to read
        ╭──────────────────────────────╮
        │ Settings                     │
        ╰──────────────────────────────╯
          Opus 5.5 (1M context) | herdr-hud-macos
        """
        #expect(Chrome.strip(screen, agent: "claude") == """
        ⏺ older reply
        \(Self.rule)
        ❯ an old draft
        \(Self.rule)

        ⏺ newest reply the user wants to read
        """)
    }

    @Test func aBoxHigherUpInTheConversationStays() {
        var lines = ["╭────╮", "│ Claude Code │", "╰────╯"]
        lines += Array(repeating: "⏺ some output", count: 12)
        let screen = lines.joined(separator: "\n")
        #expect(Chrome.strip(screen, agent: "claude") == screen)
    }

    @Test func indentedToolOutputAtTheEndStays() {
        let screen = "⏺ Ran the tests\n  ⎿  All 12 passed\n     no warnings"
        #expect(Chrome.strip(screen, agent: "claude") == screen)
    }
}
