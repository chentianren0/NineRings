import Foundation

/// The StoreShots screenshots, as `xcrun xcresulttool export attachments` leaves them: the files, and a
/// `manifest.json` that gives each file's attachment name. The tests name each screenshot `<moment>-<appearance>`,
/// such as `01-light`; the export may add a suffix to that name, so the name is found inside it.
public enum Attachments {
    /// The attachment name a store screenshot has, found in a longer name, or nil.
    public static func shotName(in name: String) -> String? {
        guard let range = name.range(of: #"\d\d-(light|dark)"#, options: .regularExpression) else { return nil }
        return String(name[range])
    }

    /// Every pair of exported file name and attachment name in the export's manifest, wherever it lies in it.
    public static func entries(inManifest data: Data) throws -> [(file: String, name: String)] {
        var entries: [(String, String)] = []
        func walk(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                if let file = dictionary["exportedFileName"] as? String {
                    let name = (dictionary["suggestedHumanReadableName"] as? String) ?? (dictionary["name"] as? String) ?? file
                    entries.append((file, name))
                }
                dictionary.values.forEach(walk)
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        walk(try JSONSerialization.jsonObject(with: data))
        return entries
    }

    /// Copies each store screenshot in the export at `from` to `to/<moment>-<appearance>.png`, and returns the names.
    public static func collect(from: URL, to: URL) throws -> [String] {
        let manifest = try Data(contentsOf: from.appending(path: "manifest.json"))
        try FileManager.default.createDirectory(at: to, withIntermediateDirectories: true)
        var names: [String] = []
        for entry in try entries(inManifest: manifest) {
            guard let name = shotName(in: entry.name) else { continue }
            let target = to.appending(path: "\(name).png")
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: from.appending(path: entry.file), to: target)
            names.append(name)
        }
        return names.sorted()
    }
}
