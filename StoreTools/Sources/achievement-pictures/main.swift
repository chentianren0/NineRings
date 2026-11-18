import Foundation
import StoreComposer

// Draws the four Game Center achievement pictures into StoreTools/AchievementPictures/, one PNG per achievement, named
// by its identifier. Run it with `swift run --package-path StoreTools achievement-pictures`.
let folder = URL(filePath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "AchievementPictures")
do {
    for picture in AchievementPictures.Picture.allCases {
        let url = folder.appending(path: "\(picture.rawValue).png")
        try AchievementPictures.write(AchievementPictures.draw(picture), to: url)
        print(url.path(percentEncoded: false))
    }
} catch {
    FileHandle.standardError.write(Data("achievement-pictures: \(error)\n".utf8))
    exit(1)
}
