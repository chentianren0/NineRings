import CoreGraphics
import Foundation
import StoreComposer

// The store pictures' composer and checker. scripts/store-assets.sh runs it; it can be run by hand too:
//
//   store-compose plan --manifest Shots.json --device mac [--appearance plan|light|dark]
//       One line per moment, tab-separated: its id, its appearance, then the app's launch arguments for it.
//   store-compose header-arguments --manifest Shots.json --appearance light --dir DIR
//       The offscreen renderer's launch arguments for the product page header, one per line.
//   store-compose compose --manifest Shots.json --captions Captions.xcstrings --device mac --language en
//                         --captures DIR --out DIR [--caption on|off] [--bezel bezel.json] [--appearance plan|light|dark]
//       Each moment's picture, from DIR/<id>-<appearance>.png to OUT/<id>.png, checked.
//   store-compose finish-header --manifest Shots.json --in FILE --out FILE --appearance light
//       The header from the renderer's picture: no transparency, checked, the toy inside the safe area.
//   store-compose check --class mac FILE...
//       What App Store Connect would refuse in each file.
//   store-compose captions --captions Captions.xcstrings --languages en,fr,ja
//       Which captions each language still lacks.

struct Failure: Error, CustomStringConvertible {
    var description: String
}

struct Options {
    private var values: [String: String] = [:]
    private(set) var rest: [String] = []

    init(_ arguments: ArraySlice<String>) {
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            if argument.hasPrefix("--"), let value = iterator.next() {
                values[String(argument.dropFirst(2))] = value
            } else {
                rest.append(argument)
            }
        }
    }

    func value(_ name: String) throws -> String {
        guard let value = values[name] else { throw Failure(description: "--\(name) is needed") }
        return value
    }

    func optional(_ name: String) -> String? { values[name] }

    func url(_ name: String) throws -> URL { URL(filePath: try value(name)) }
}

/// The appearance a moment is taken in: the series' own (`plan`), or one for all.
func appearance(of moment: Manifest.Moment, _ choice: String) throws -> Manifest.Appearance {
    if choice == "plan" { return moment.appearance }
    guard let appearance = Manifest.Appearance(rawValue: choice) else { throw Failure(description: "--appearance is plan, light or dark") }
    return appearance
}

func backdrop(_ appearance: Manifest.Appearance) -> CGColor {
    // The app's own backdrop behind the toy (Backdrop.swift).
    switch appearance {
    case .light: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    case .dark: CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    }
}

func report(_ url: URL, _ report: Check.Report) -> Bool {
    if report.problems.isEmpty {
        print("ok \(url.lastPathComponent) \(report.size)" + (report.content.map { " content \(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? ""))
        return true
    }
    for problem in report.problems { print("refused \(url.lastPathComponent): \(problem)") }
    return false
}

func run() throws -> Bool {
    let arguments = CommandLine.arguments
    guard arguments.count > 1 else { throw Failure(description: "say plan, header-arguments, compose, finish-header, check or captions") }
    let options = Options(arguments.dropFirst(2))

    switch arguments[1] {
    case "plan":
        let manifest = try Manifest(contentsOf: try options.url("manifest"))
        _ = try manifest.device(try options.value("device"))
        let choice = options.optional("appearance") ?? "plan"
        for moment in manifest.moments {
            print(([moment.id, try appearance(of: moment, choice).rawValue] + moment.arguments).joined(separator: "\t"))
        }
        return true

    case "header-arguments":
        let header = try Manifest(contentsOf: try options.url("manifest")).header
        let lines = [
            "-capture-move", "\(header.move)", "-capture-progress", "\(header.progress)", "-capture-views", header.view,
            "-capture-size", "\(header.size)", "-capture-safe-area", header.safeArea.map { String(Int($0)) }.joined(separator: ","),
            "-capture-appearance", try options.value("appearance"), "-capture-dir", try options.value("dir"),
        ]
        print(lines.joined(separator: "\n"))
        return true

    case "compose":
        let manifest = try Manifest(contentsOf: try options.url("manifest"))
        let catalog = try CaptionCatalog(contentsOf: try options.url("captions"))
        let device = try manifest.device(try options.value("device"))
        let language = try options.value("language")
        let captures = try options.url("captures"), out = try options.url("out")
        let withCaption = (options.optional("caption") ?? "on") == "on"
        let bezel = try options.optional("bezel").map { try Bezel.load(URL(filePath: $0)) }
        let choice = options.optional("appearance") ?? "plan"
        var allGood = true
        for moment in manifest.moments {
            let shade = try appearance(of: moment, choice)
            let input = captures.appending(path: "\(moment.id)-\(shade.rawValue).png")
            let capture = try PNG.read(input)
            let size = PixelSize(capture.width, capture.height)
            // A capture of the wrong size would be stretched or blurred: refuse it.
            switch device.capture {
            case .macWindow:
                if let window = device.window, size != window * 2 {
                    throw ComposerError.wrongCaptureSize(input, size, expected: "\(window * 2), the window at the Mac's 2x scale")
                }
            case .simulator:
                if size != device.size, size != device.size.rotated {
                    throw ComposerError.wrongCaptureSize(input, size, expected: "\(device.size), the simulator's screen")
                }
            }
            var caption: String?
            if withCaption {
                let key = moment.captionKey(on: device.id)
                guard let text = catalog.text(key, language: language) else { throw ComposerError.missingCaption(key) }
                caption = text
            }
            let picture = try Composer.compose(
                capture: capture, canvas: device.size, caption: caption, language: language,
                appearance: shade, bezel: bezel, cornerRadius: device.cornerRadius ?? 0
            )
            let output = out.appending(path: "\(moment.id).png")
            try PNG.write(picture, to: output)
            allGood = report(output, try Check.check(output, as: device.class)) && allGood
        }
        return allGood

    case "finish-header":
        let header = try Manifest(contentsOf: try options.url("manifest")).header
        guard let shade = Manifest.Appearance(rawValue: try options.value("appearance")) else { throw Failure(description: "--appearance is light or dark") }
        let input = try options.url("in"), output = try options.url("out")
        let image = try PNG.read(input)
        guard PixelSize(image.width, image.height) == header.size else {
            throw ComposerError.wrongCaptureSize(input, PixelSize(image.width, image.height), expected: "\(header.size)")
        }
        try PNG.write(try Composer.flatten(image, background: backdrop(shade)), to: output)
        return report(output, try Check.check(output, as: .header))

    case "check":
        guard let deviceClass = DeviceClass(rawValue: try options.value("class")) else {
            throw Failure(description: "--class is one of \(DeviceClass.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        var allGood = true
        for path in options.rest {
            let url = URL(filePath: path)
            allGood = report(url, try Check.check(url, as: deviceClass)) && allGood
        }
        return allGood

    case "captions":
        let catalog = try CaptionCatalog(contentsOf: try options.url("captions"))
        for language in try options.value("languages").split(separator: ",").map(String.init) {
            let missing = catalog.keys.filter { !catalog.isTranslated($0, into: language) }
            print(missing.isEmpty ? "\(language): every caption" : "\(language): lacks \(missing.joined(separator: ", ")) (falls back to \(catalog.sourceLanguage))")
        }
        return true

    default:
        throw Failure(description: "unknown command \(arguments[1])")
    }
}

do {
    exit(try run() ? 0 : 1)
} catch {
    FileHandle.standardError.write(Data("store-compose: \(error)\n".utf8))
    exit(2)
}
