import AchievementPictures
import Foundation

// Draws the four Game Center achievement pictures, one PNG per achievement named by its identifier, into
// StoreTools/AchievementPictures/, or into the folder given:
// `swift run --package-path StoreTools achievement-pictures [folder]`.
let folder =
    CommandLine.arguments.count > 1
    ? URL(filePath: CommandLine.arguments[1])
    : URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "AchievementPictures")
do {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for picture in AchievementPicture.allCases {
        print(try picture.write(into: folder).path(percentEncoded: false))
    }
} catch {
    FileHandle.standardError.write(Data("achievement-pictures: \(error)\n".utf8))
    exit(1)
}
