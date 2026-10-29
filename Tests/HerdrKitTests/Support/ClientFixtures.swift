import Foundation
import Synchronization
@testable import HerdrKit

/// Records every command and answers with scripted outputs; the last script repeats.
final class FakeProcessRunner: ProcessRunner {
    struct Invocation: Sendable, Equatable {
        let executable: String
        let arguments: [String]
        let environment: [String: String]
    }

    private let state: Mutex<(invocations: [Invocation], outputs: [Result<ProcessOutput, HerdrError>])>

    init(_ outputs: Result<ProcessOutput, HerdrError>...) {
        state = Mutex(([], outputs))
    }

    /// A runner whose `herdr status server` reports `socketPath`.
    convenience init(socketPath: String) {
        self.init(.success(.status(socket: socketPath)))
    }

    var invocations: [Invocation] { state.withLock { $0.invocations } }

    func run(_ executable: String, arguments: [String], environment: [String: String]) async throws(HerdrError) -> ProcessOutput {
        let next = state.withLock { state in
            state.invocations.append(Invocation(executable: executable, arguments: arguments, environment: environment))
            return state.outputs.count > 1 ? state.outputs.removeFirst() : state.outputs[0]
        }
        return try next.get()
    }
}

extension ProcessOutput {
    static func status(socket: String) -> ProcessOutput {
        ProcessOutput(status: 0, stdout: Data("status: running\nversion: 0.9.5\nsocket: \(socket)\n".utf8), stderr: Data())
    }
}

extension LiveHerdrClient {
    /// A client wired to fakes only: its home has no herdr, and the one "installed" binary is a
    /// path the fake runner never executes.
    static func testing(runner: FakeProcessRunner, environment: [String: String] = ["HOME": "/Users/test"],
                        requestDeadline: Duration = .seconds(60), replyCap: Int = 1 << 20,
                        refreshInterval: Duration = .seconds(30)) -> LiveHerdrClient {
        LiveHerdrClient(runner: runner, home: "/Users/test", environment: environment,
                        isExecutable: { $0 == "/opt/homebrew/bin/herdr" },
                        settings: Settings(requestDeadline: requestDeadline, replyCap: replyCap, refreshInterval: refreshInterval))
    }
}

/// One agent object in herdr's wire shape; values are synthetic.
func agentJSON(pane: String, status: String = "idle", terminal: String? = nil, workspace: String? = nil,
               agent: String = "claude", session: AgentSessionRef? = nil) -> String {
    let workspace = workspace ?? String(pane.split(separator: ":")[0])
    let sessionJSON = session.map { #"{"agent":"claude","kind":"\#($0.kind.rawValue)","source":"herdr:claude","value":"\#($0.value)"}"# } ?? "null"
    return """
    {"agent":"\(agent)","agent_status":"\(status)","agent_session":\(sessionJSON),"completion_seq":null,"cwd":"/tmp/project",\
    "focused":false,"pane_id":"\(pane)","revision":1,"state_change_seq":3,"tab_id":"\(workspace):t1",\
    "terminal_id":"\(terminal ?? "term-\(pane)")","terminal_title_stripped":"Synthetic task","workspace_id":"\(workspace)"}
    """
}

func agentListResult(_ agents: [String]) -> String {
    #"{"agents":[\#(agents.joined(separator: ","))],"type":"agent_list"}"#
}

func agentInfoResult(_ agent: String) -> String {
    #"{"agent":\#(agent),"type":"agent_info"}"#
}
