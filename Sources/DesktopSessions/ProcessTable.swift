import Darwin

/// What the HUD reads about running processes to tell a live session from a stale file.
public protocol ProcessTable: Sendable {
    /// When the process started, in the form Claude Code records as `procStart`: `ps`'s `lstart`
    /// in UTC, such as `Tue Oct 27 16:58:32 2026`. `nil` when no such process runs.
    func startTime(of pid: Int32) -> String?
    func parent(of pid: Int32) -> Int32?
}

/// The processes running on this Mac, read with `sysctl`.
public struct LiveProcessTable: ProcessTable {
    public init() {}

    public func startTime(of pid: Int32) -> String? {
        guard var started = info(pid)?.kp_proc.p_un.__p_starttime.tv_sec else { return nil }
        var utc = tm()
        gmtime_r(&started, &utc)
        var buffer = [CChar](repeating: 0, count: 64)
        let length = strftime(&buffer, buffer.count, "%a %b %e %T %Y", &utc)
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    public func parent(of pid: Int32) -> Int32? {
        info(pid)?.kp_eproc.e_ppid
    }

    private func info(_ pid: Int32) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        // sysctl succeeds with an empty answer for a pid that does not exist.
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }
}
