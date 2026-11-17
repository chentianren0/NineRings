import CoreGraphics
import Foundation
import ImageIO
@testable import StoreComposer
import Testing

@Suite struct StoreSizeTests {
    @Test func theRequiredSizesAreAccepted() {
        #expect(DeviceClass.mac.accepts(PixelSize(2880, 1800)))
        #expect(DeviceClass.iPhone63.accepts(PixelSize(1206, 2622)))
        #expect(DeviceClass.iPad13.accepts(PixelSize(2752, 2064)))
        #expect(DeviceClass.duoOuter.accepts(PixelSize(1398, 2034)))
        #expect(DeviceClass.duoInner.accepts(PixelSize(2853, 2007)))
        #expect(DeviceClass.header.accepts(PixelSize(3840, 1646)))
    }

    @Test func theMacIsLandscapeOnlyAndOtherSizesAreRefused() {
        #expect(!DeviceClass.mac.accepts(PixelSize(1800, 2880)))
        #expect(!DeviceClass.iPhone63.accepts(PixelSize(1320, 2868)))
        #expect(!DeviceClass.header.accepts(PixelSize(1646, 3840)))
    }

    @Test func theHeadersSafeAreaIsCentred() throws {
        let safe = try #require(DeviceClass.header.safeArea)
        #expect(safe.midX == 1920, "\(safe)")
        #expect(abs(safe.midY - 1646 / 2) <= 1)
    }
}

@Suite struct LayoutTests {
    @Test func aCaptureTheSizeOfThePictureIsThePicture() {
        let layout = Layout(canvas: PixelSize(1206, 2622), capture: PixelSize(1206, 2622), caption: false, bezel: nil, cornerRadius: 165)
        #expect(layout.capture == CGRect(x: 0, y: 0, width: 1206, height: 2622))
        #expect(layout.captureCornerRadius == 0)
        #expect(layout.captionBand == nil)
    }

    @Test func theMacWindowIsNeverEnlarged() {
        let layout = Layout(canvas: PixelSize(2880, 1800), capture: PixelSize(2560, 1600), caption: false, bezel: nil)
        #expect(layout.capture == CGRect(x: 160, y: 100, width: 2560, height: 1600))
    }

    @Test func aCaptionTakesABandAboveTheCapture() throws {
        for (canvas, capture) in [(PixelSize(2880, 1800), PixelSize(2560, 1600)), (PixelSize(1206, 2622), PixelSize(1206, 2622)), (PixelSize(2752, 2064), PixelSize(2752, 2064))] {
            let layout = Layout(canvas: canvas, capture: capture, caption: true, bezel: nil, cornerRadius: 100)
            let band = try #require(layout.captionBand)
            let whole = CGRect(origin: .zero, size: canvas.cgSize)
            #expect(whole.contains(band) && whole.contains(layout.capture))
            #expect(layout.capture.minY >= band.maxY, "the caption must not cover the app")
            // The capture keeps its shape.
            #expect(abs(layout.capture.width / layout.capture.height - Double(capture.width) / Double(capture.height)) < 0.002)
            #expect(abs(layout.capture.midX - Double(canvas.width) / 2) <= 1)
            #expect(layout.captureCornerRadius > 0 && layout.captureCornerRadius < 100)
        }
    }

    @Test func aBezelHoldsTheCaptureInItsScreen() throws {
        let bezel = BezelGeometry(size: PixelSize(1400, 2800), screen: CGRect(x: 100, y: 100, width: 1200, height: 2600), screenCornerRadius: 120)
        let layout = Layout(canvas: PixelSize(1206, 2622), capture: PixelSize(1206, 2622), caption: true, bezel: bezel)
        let frame = try #require(layout.bezel)
        let scale = frame.width / 1400
        #expect(abs(frame.height / 2800 - scale) < 0.001)
        #expect(abs(layout.capture.minX - (frame.minX + 100 * scale)) < 0.001)
        #expect(abs(layout.capture.width - 1200 * scale) < 0.001)
        #expect(abs(layout.captureCornerRadius - 120 * scale) < 0.001)
        let band = try #require(layout.captionBand)
        #expect(frame.minY >= band.maxY)
    }
}

@Suite struct CaptionTests {
    let catalog = try! CaptionCatalog(data: Data("""
    {
      "sourceLanguage": "en",
      "strings": {
        "caption.move": {
          "localizations": {
            "en": { "stringUnit": { "state": "translated", "value": "Watch every ring come off" } },
            "fr": { "stringUnit": { "state": "translated", "value": "Regardez chaque anneau sortir" } },
            "zh-Hans": { "stringUnit": { "state": "translated", "value": "看每个环取下" } }
          }
        },
        "caption.rest": {
          "localizations": { "en": { "stringUnit": { "state": "translated", "value": "Nine rings. One rule." } } }
        }
      },
      "version": "1.0"
    }
    """.utf8))

    @Test func fallsBackAsTheStoreDoes() {
        #expect(catalog.text("caption.move", language: "fr") == "Regardez chaque anneau sortir")
        #expect(catalog.text("caption.move", language: "fr-CA") == "Regardez chaque anneau sortir")
        #expect(catalog.text("caption.rest", language: "fr") == "Nine rings. One rule.")
        #expect(catalog.text("caption.missing", language: "en") == nil)
    }

    @Test func chineseKeepsItsScript() {
        #expect(catalog.text("caption.move", language: "zh-Hant") == "Watch every ring come off")
        #expect(catalog.isTranslated("caption.move", into: "zh-Hans"))
        #expect(!catalog.isTranslated("caption.move", into: "zh-Hant"))
    }

    @Test func theRealCatalogReads() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "Captions.xcstrings")
        let real = try CaptionCatalog(contentsOf: url)
        #expect(real.sourceLanguage == "en")
        #expect(real.keys.count >= 6)
    }

    @Test func aLongCaptionFitsItsBand() {
        let text = "Regardez chaque anneau sortir de l’épée, un par un"
        let set = CaptionText.fit(text, language: "fr", maxFontSize: 75, width: 1062, height: 290)
        #expect(set.width <= 1062)
        #expect(set.height <= 290)
        #expect(set.lines.count <= 2)
    }

    @Test func aShortCaptionKeepsItsFullSize() {
        let set = CaptionText.fit("Nine rings. One rule.", language: "en", maxFontSize: 111, width: 2664, height: 230)
        #expect(set.fontSize == 111 && set.lines.count == 1)
    }
}

@Suite struct ComposeTests {
    func image(_ size: PixelSize, alpha: Bool = true, color: CGColor = CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1)) -> CGImage {
        let context = CGContext(
            data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue
        )!
        context.setFillColor(color)
        context.fill(CGRect(origin: .zero, size: size.cgSize))
        return context.makeImage()!
    }

    func temporary(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "store-compose-tests-\(UUID().uuidString)").appending(path: name)
    }

    @Test(arguments: [Manifest.Appearance.light, .dark], [true, false])
    func aComposedPictureIsAcceptedAsIs(appearance: Manifest.Appearance, caption: Bool) throws {
        let picture = try Composer.compose(
            capture: image(PixelSize(2560, 1600)), canvas: PixelSize(2880, 1800), caption: caption ? "Watch every ring come off" : nil,
            language: "en", appearance: appearance, bezel: nil, cornerRadius: 0
        )
        let url = temporary("01.png")
        try PNG.write(picture, to: url)
        let report = try Check.check(url, as: .mac)
        #expect(report.problems.isEmpty, "\(report.problems)")
        #expect(report.size == PixelSize(2880, 1800))
    }

    @Test func aWrongSizeAndTransparencyAreRefused() throws {
        let url = temporary("bad.png")
        try PNG.write(image(PixelSize(2000, 1250)), to: url)
        let problems = try Check.check(url, as: .mac).problems
        #expect(problems.contains { $0.contains("2000x1250") })
        #expect(problems.contains { $0.contains("alpha") })
    }

    @Test func flatteningRemovesTransparency() throws {
        let url = temporary("flat.png")
        try PNG.write(try Composer.flatten(image(PixelSize(3840, 1646)), background: CGColor(gray: 1, alpha: 1)), to: url)
        #expect(!(try Check.check(url, as: .header).problems.contains { $0.contains("alpha") }))
    }

    @Test func theContentBoundsFindTheToy() throws {
        let context = CGContext(
            data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        // Core Graphics counts y from the bottom: this is 30 to 70 from the top.
        context.fill(CGRect(x: 100, y: 130, width: 50, height: 40))
        let bounds = try #require(Check.contentBounds(context.makeImage()!))
        #expect(bounds == CGRect(x: 100, y: 30, width: 50, height: 40))
    }
}
