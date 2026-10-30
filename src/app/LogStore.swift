import Foundation

struct LogLine: Identifiable {
    let id = UUID()
    let time: Date
    let text: String

    var isProblem: Bool {
        let t = text.lowercased()
        return ["error", "failed", "couldn't", "can't", "lost", "never appeared", "permission"].contains { t.contains($0) }
    }
}

/// Activity log shown in the dashboard and mirrored to ~/Library/Logs/Annex/annex.log.
final class LogStore: ObservableObject {
    @Published private(set) var lines: [LogLine] = []
    let fileURL: URL
    private static let timeFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    init() {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Annex", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("annex.log")
        if let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int, size > 1_000_000 {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func add(_ text: String) {
        let line = LogLine(time: Date(), text: text)
        lines.append(line)
        if lines.count > 500 { lines.removeFirst(lines.count - 500) }
        let entry = "\(ISO8601DateFormatter().string(from: line.time)) \(text)\n"
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile(); handle.write(Data(entry.utf8)); try? handle.close()
        } else {
            try? Data(entry.utf8).write(to: fileURL)
        }
    }

    var problemCount: Int { lines.filter(\.isProblem).count }

    func text(last count: Int = 500) -> String {
        lines.suffix(count).map { "\(Self.timeFormat.string(from: $0.time))  \($0.text)" }.joined(separator: "\n")
    }

    static func time(_ date: Date) -> String { timeFormat.string(from: date) }
}
