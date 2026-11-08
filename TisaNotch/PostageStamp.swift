import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum StampLayout: Int, CaseIterable, Hashable, Identifiable {
    case three = 3
    case four = 4

    var id: Int { rawValue }
}

enum PostageStamp {
    enum Failure: LocalizedError {
        case render, encode

        var errorDescription: String? {
            switch self {
            case .render: return "The postage stamp could not be drawn."
            case .encode: return "The postage stamp could not be encoded as PNG."
            }
        }
    }

    private static let paper = CGColor(red: 0.96, green: 0.90, blue: 0.76, alpha: 1)
    private static let jade = CGColor(red: 0.10, green: 0.27, blue: 0.22, alpha: 1)
    private static let bronze = CGColor(red: 0.65, green: 0.38, blue: 0.22, alpha: 1)

    static func render(_ layout: StampLayout, photos: [CGImage]) -> CGImage? {
        guard photos.count == layout.rawValue else { return nil }
        let width = 1080
        let photoHeight = 548
        let pitch = 599
        let firstPhotoTop = 312
        let footerTop = firstPhotoTop + photos.count * pitch
        let height = footerTop + 150
        let center = CGFloat(width) / 2

        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let canvas = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        context.clear(canvas)
        context.interpolationQuality = .high

        drawPaper(in: canvas.insetBy(dx: 26, dy: 26), context: context)
        let top = CGFloat(height)

        label("កម្ពុជា", x: center, y: top - 125, size: 52, font: "Khmer Sangam MN", in: context)
        label("Postcards from Cambodia", x: center, y: top - 192, size: 66,
              font: "Baskerville-SemiBold", in: context)
        label("K H M E R   H E R I T A G E", x: center, y: top - 244, size: 21,
              font: "HelveticaNeue-Medium", in: context)

        diamondBand(at: top - 274, in: context)
        for (index, photo) in photos.enumerated() {
            let y = top - CGFloat(firstPhotoTop + index * pitch + photoHeight)
            let frame = CGRect(x: 112, y: y, width: 856, height: CGFloat(photoHeight))
            drawPhoto(photo, in: frame, context: context)
            label(String(format: "%02d", index + 1), x: center, y: y - 28,
                  size: 16, font: "Menlo", in: context)
        }

        let footer = top - CGFloat(footerTop)
        diamondBand(at: footer + 4, in: context)
        label("អនុស្សាវរីយ៍", x: 360, y: footer - 47, size: 35, font: "Khmer Sangam MN", in: context)
        label("TISA NOTCH   /   PHOTO BOOTH", x: 360, y: footer - 80,
              size: 16, font: "HelveticaNeue-Medium", in: context)
        drawPostmark(at: CGPoint(x: 770, y: footer - 57), count: photos.count, in: context)
        return context.makeImage()
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        let bytes = NSMutableData()
        guard let writer = CGImageDestinationCreateWithData(
            bytes as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ) else { throw Failure.encode }
        CGImageDestinationAddImage(writer, image, nil)
        guard CGImageDestinationFinalize(writer) else { throw Failure.encode }
        try (bytes as Data).write(to: url, options: .atomic)
    }

    private static func drawPaper(in sheet: CGRect, context: CGContext) {
        let cutouts = CGMutablePath()
        cutouts.addRect(sheet)
        let pitch: CGFloat = 34
        let radius: CGFloat = 10
        for x in stride(from: sheet.minX + pitch, to: sheet.maxX - radius, by: pitch) {
            for y in [sheet.minY, sheet.maxY] {
                cutouts.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: 20, height: 20))
            }
        }
        for y in stride(from: sheet.minY + pitch, to: sheet.maxY - radius, by: pitch) {
            for x in [sheet.minX, sheet.maxX] {
                cutouts.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: 20, height: 20))
            }
        }

        context.saveGState()
        context.clip(to: sheet)
        context.addPath(cutouts)
        context.clip(using: .evenOdd)
        context.setFillColor(paper)
        context.fill(sheet)

        context.setFillColor(CGColor(gray: 0.31, alpha: 0.065))
        for y in stride(from: Int(sheet.minY) + 3, to: Int(sheet.maxY), by: 7) {
            for x in stride(from: Int(sheet.minX) + y % 11, to: Int(sheet.maxX), by: 11) {
                let size = CGFloat(1 + (x * 11 + y * 7) % 3)
                context.fill(CGRect(x: CGFloat(x), y: CGFloat(y), width: size, height: 1))
            }
        }

        context.setStrokeColor(jade)
        context.setLineWidth(3)
        context.stroke(sheet.insetBy(dx: 23, dy: 23))
        context.setStrokeColor(bronze)
        context.setLineWidth(1)
        context.stroke(sheet.insetBy(dx: 34, dy: 34))
        context.restoreGState()
    }

    private static func drawPhoto(_ photo: CGImage, in frame: CGRect, context: CGContext) {
        context.setFillColor(jade)
        context.fill(frame.insetBy(dx: -8, dy: -8))
        context.setFillColor(paper)
        context.fill(frame.insetBy(dx: -4, dy: -4))

        let scale = max(frame.width / CGFloat(photo.width), frame.height / CGFloat(photo.height))
        let width = CGFloat(photo.width) * scale
        let height = CGFloat(photo.height) * scale
        context.saveGState()
        context.clip(to: frame)
        context.draw(photo, in: CGRect(x: frame.midX - width / 2, y: frame.midY - height / 2,
                                       width: width, height: height))
        context.restoreGState()
    }

    private static func diamondBand(at y: CGFloat, in context: CGContext) {
        context.setStrokeColor(bronze)
        context.setLineWidth(2)
        context.move(to: CGPoint(x: 112, y: y))
        context.addLine(to: CGPoint(x: 968, y: y))
        context.strokePath()

        context.setFillColor(jade)
        for index in -12...12 {
            let x = 540 + CGFloat(index) * 33
            let size: CGFloat = index.isMultiple(of: 3) ? 9 : 5
            context.move(to: CGPoint(x: x, y: y + size))
            context.addLine(to: CGPoint(x: x + size, y: y))
            context.addLine(to: CGPoint(x: x, y: y - size))
            context.addLine(to: CGPoint(x: x - size, y: y))
            context.closePath()
        }
        context.fillPath()
    }

    private static func drawPostmark(at center: CGPoint, count: Int, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: -.pi / 14)
        context.setStrokeColor(bronze)
        context.setLineWidth(2.5)
        context.strokeEllipse(in: CGRect(x: -37, y: -37, width: 74, height: 74))
        context.strokeEllipse(in: CGRect(x: -32, y: -32, width: 64, height: 64))
        label("\(count)", x: 0, y: -10, size: 29, font: "Baskerville-SemiBold", in: context)
        for y in [-14.0, 0, 14] as [CGFloat] {
            context.move(to: CGPoint(x: 47, y: y))
            context.addQuadCurve(to: CGPoint(x: 100, y: y), control: CGPoint(x: 72, y: y + 15))
            context.addQuadCurve(to: CGPoint(x: 150, y: y), control: CGPoint(x: 125, y: y - 15))
        }
        context.strokePath()
        context.restoreGState()
    }

    private static func label(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat,
                              font: String, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(font as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): jade
        ]
        let text = NSAttributedString(string: string, attributes: attributes)
        let line = CTLineCreateWithAttributedString(text as CFAttributedString)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: x - width / 2, y: y)
        CTLineDraw(line, context)
    }
}
