import Foundation
import HerdrKit

/// Reads Claude Code session transcripts (JSONL) from the given Claude config directories.
public struct ClaudeTranscripts: TranscriptSource {
    public let configDirectories: [URL]
    private let pollInterval: Duration
    /// How much of a transcript's end the first read takes; long sessions run to tens of megabytes.
    private let tailBytes: Int

    public init(configDirectories: [URL]) {
        self.init(configDirectories: configDirectories, pollInterval: .seconds(1), tailBytes: 4 << 20)
    }

    init(configDirectories: [URL], pollInterval: Duration, tailBytes: Int) {
        self.configDirectories = configDirectories
        self.pollInterval = pollInterval
        self.tailBytes = tailBytes
    }

    public func chat(at ref: AgentSessionRef, limit: Int) -> AsyncStream<[ChatBlock]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let watcher = Task {
                if let url = transcriptURL(for: ref) {
                    await follow(url, limit: limit, into: continuation)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in watcher.cancel() }
        }
    }

    /// A path is taken as given; a session id is looked up as `projects/*/<id>.jsonl` in every
    /// config directory, newest first, because a resumed session can exist under several accounts.
    func transcriptURL(for ref: AgentSessionRef) -> URL? {
        switch ref.kind {
        case .path:
            return URL(filePath: ref.value)
        case .id:
            guard !ref.value.contains("/") else { return nil }
            let candidates = configDirectories.flatMap { directory in
                let projects = directory.appending(path: "projects")
                let folders = (try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
                return folders.map { $0.appending(path: "\(ref.value).jsonl") }
            }
            return candidates
                .compactMap { url in
                    (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate.map { (url, $0) }
                }
                .max { $0.1 < $1.1 }?.0
        }
    }

    /// Polls rather than using a file-system event source, so a transcript replaced under the same
    /// path is still followed. Returns when the file can no longer be read or the task is cancelled.
    private func follow(_ url: URL, limit: Int, into continuation: AsyncStream<[ChatBlock]>.Continuation) async {
        var tail = TranscriptTail(url: url, initialBytes: tailBytes)
        var assembler = ChatAssembler()
        var emitted: [ChatBlock]?
        while !Task.isCancelled {
            guard let read = try? tail.read() else { return }
            let lines: [Data]
            switch read {
            case .restarted(let all):
                assembler = ChatAssembler()
                lines = all
            case .appended(let new):
                lines = new
            }
            for line in lines {
                if let parsed = TranscriptLine(line) { assembler.consume(parsed) }
            }
            let latest = Array(assembler.blocks.suffix(max(0, limit)))
            if latest != emitted {
                continuation.yield(latest)
                emitted = latest
            }
            try? await Task.sleep(for: pollInterval)
        }
    }
}
