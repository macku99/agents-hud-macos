import Foundation

/// Reads a growing JSONL file from its end: first the last `initialBytes`, then whatever was
/// appended since the previous read. Only complete lines are returned.
struct TranscriptTail {
    enum Read: Equatable {
        /// Lines from a fresh read of the file's tail; anything read before no longer applies.
        case restarted([Data])
        /// Lines appended since the previous read.
        case appended([Data])
    }

    private struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private static let newline = UInt8(ascii: "\n")

    let url: URL
    let initialBytes: Int
    private var identity: FileIdentity?
    private var offset: UInt64 = 0
    /// The byte just before `offset`, which must still be there for the file to have only grown.
    private var lastByteRead: UInt8?
    private var unfinishedLine = Data()
    /// The tail started mid-line, so bytes up to the next newline belong to a line we never saw whole.
    private var skipsToNextLine = false

    init(url: URL, initialBytes: Int) {
        self.url = url
        self.initialBytes = initialBytes
    }

    mutating func read() throws -> Read {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(handle.fileDescriptor, &info) == 0 else { throw CocoaError(.fileReadUnknown) }
        let current = FileIdentity(device: info.st_dev, inode: info.st_ino)
        let size = UInt64(info.st_size)

        if current == identity, size >= offset, try precedesOffsetUnchanged(in: handle) {
            return .appended(try lines(from: handle, at: offset))
        }

        identity = current
        unfinishedLine = Data()
        lastByteRead = nil
        let start = size > UInt64(initialBytes) ? size - UInt64(initialBytes) : 0
        // Reading from one byte early shows whether `start` falls right after a newline.
        skipsToNextLine = start > 0
        return .restarted(try lines(from: handle, at: start > 0 ? start - 1 : 0))
    }

    /// A file truncated and rewritten past the old offset between two reads keeps its identity and
    /// a size beyond the offset; the byte before the offset is what gives it away.
    private func precedesOffsetUnchanged(in handle: FileHandle) throws -> Bool {
        guard offset > 0 else { return true }
        try handle.seek(toOffset: offset - 1)
        return try handle.read(upToCount: 1)?.first == lastByteRead
    }

    private mutating func lines(from handle: FileHandle, at position: UInt64) throws -> [Data] {
        try handle.seek(toOffset: position)
        var data = try handle.readToEnd() ?? Data()
        offset = position + UInt64(data.count)
        if let last = data.last { lastByteRead = last }

        if skipsToNextLine {
            guard let newline = data.firstIndex(of: Self.newline) else { return [] }
            data = Data(data[(newline + 1)...])
            skipsToNextLine = false
        }
        data = unfinishedLine + data
        guard let lastNewline = data.lastIndex(of: Self.newline) else {
            unfinishedLine = data
            return []
        }
        unfinishedLine = Data(data[(lastNewline + 1)...])
        return data[..<lastNewline].split(separator: Self.newline).map { Data($0) }
    }
}
