import Foundation
import Session

/// The person's toy and finished plays, kept as two JSON files in a folder it is given.
///
/// It knows nothing of where the folder comes from: the app gives it the folder that syncs, a test a temporary one. It
/// reads and writes at once, on the caller's thread, as the files are a few kilobytes. The rules it keeps:
/// - The toy is `Toy.json`: `{"format":1,"toy":{…}}`, a ``ToySnapshot`` with its ``ToySnapshot/format``. A file that
///   is missing, cannot be read, or holds a format this build does not know gives no toy, and the next toy kept
///   replaces it.
/// - The history is `History.json`: `{"plays":[…]}`, each play a ``PlayRecord`` with its ``PlayRecord/rules``, newest
///   first. No file is an empty history. A play this build cannot read is counted in ``PlayHistory/unreadable``, and
///   written back as it was read whenever this build writes the file, so that it is not lost.
/// - A history file that is there but cannot be read as a history, as when it is not JSON, is left as it is: reading
///   the history and recording a play throw, and only clearing the history replaces it.
/// - Each file is written whole and atomically, with its keys sorted and its dates as seconds since Foundation's
///   reference date, as ``ToySnapshot/encoded()`` writes them: the same toy or the same plays give the same bytes.
public struct RecordFolder: Sendable {
    /// The folder the two files are in. It is not made: it is there already.
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    var toyFile: URL { url.appending(path: "Toy.json", directoryHint: .notDirectory) }
    var historyFile: URL { url.appending(path: "History.json", directoryHint: .notDirectory) }

    // MARK: The toy

    /// The toy kept, or nil when none is kept that this build can read.
    public func keptToy() -> ToySnapshot? {
        guard let data = try? Data(contentsOf: toyFile), let file = try? Self.decode(ToyFile.self, from: data),
            file.format == ToySnapshot.format
        else { return nil }
        return file.toy
    }

    /// Keeps `snapshot` as the toy. Returns whether the file was written: it is not when it holds exactly this snapshot
    /// already.
    @discardableResult
    public func keep(_ snapshot: ToySnapshot) throws -> Bool {
        let data = try Self.encode(ToyFile(format: ToySnapshot.format, toy: snapshot))
        guard (try? Data(contentsOf: toyFile)) != data else { return false }
        try data.write(to: toyFile, options: .atomic)
        return true
    }

    // MARK: The history

    /// The finished plays kept: the ones this build can read, newest first, one for each play, and how many it cannot.
    /// Throws when the file is there but cannot be read as a history.
    public func history() throws -> PlayHistory {
        try readHistory().history
    }

    /// Records `play` among the plays kept (``PlayHistory/record(_:)``). Returns whether the file was written: it is
    /// not when a play with its id is kept already. Throws, and leaves the file as it is, when the file is there but
    /// cannot be read as a history.
    @discardableResult
    public func record(_ play: PlayRecord) throws -> Bool {
        var (history, unread) = try readHistory()
        guard history.record(play) else { return false }
        try write(HistoryFile(plays: history.plays.map(HistoryFile.Entry.play) + unread.map(HistoryFile.Entry.unread)))
        return true
    }

    /// Deletes every finished play, the ones this build cannot read too: the file is left with no play.
    public func clearHistory() throws {
        try write(HistoryFile(plays: []))
    }

    /// The plays kept, and those this build cannot read as they were read.
    private func readHistory() throws -> (history: PlayHistory, unread: [JSONValue]) {
        let data: Data
        do {
            data = try Data(contentsOf: historyFile)
        } catch CocoaError.fileReadNoSuchFile {
            return (.empty, [])
        }
        var history = PlayHistory.empty
        var unread: [JSONValue] = []
        for entry in try Self.decode(HistoryFile.self, from: data).plays {
            switch entry {
            case .play(let play): history.record(play)
            case .unread(let value): unread.append(value)
            }
        }
        history.unreadable = unread.count
        return (history, unread)
    }

    private func write(_ file: HistoryFile) throws {
        try Self.encode(file).write(to: historyFile, options: .atomic)
    }

    // MARK: The files

    /// What `Toy.json` holds.
    private struct ToyFile: Codable {
        var format: Int
        var toy: ToySnapshot
    }

    /// What `History.json` holds.
    private struct HistoryFile: Codable {
        /// A play as the file keeps it: one this build can read, or one it cannot, kept as it was read.
        enum Entry: Codable {
            case play(PlayRecord)
            case unread(JSONValue)

            init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let play = try? container.decode(PlayRecord.self) {
                    self = .play(play)
                } else {
                    self = .unread(try container.decode(JSONValue.self))
                }
            }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .play(let play): try container.encode(play)
                case .unread(let value): try container.encode(value)
                }
            }
        }

        var plays: [Entry]
    }

    private static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return try decoder.decode(type, from: data)
    }
}

/// Any JSON value, read and written back as it was: how a play this build cannot read stays in the history file.
enum JSONValue: Codable {
    case null
    case bool(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
