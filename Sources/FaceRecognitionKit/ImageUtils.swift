import CoreGraphics
import Foundation
import UIKit

/// Decoding, cropping and JPEG helpers shared by the gallery and the screens.
public enum ImageUtils {

    /// The same cap the engine uses internally, so face boxes come back in this image's coordinates.
    public static let engineMaxSide: CGFloat = 1280

    /// Loads a picked photo upright, with its long side at most `maxSide`.
    public static func load(contentsOf url: URL, maxSide: CGFloat = engineMaxSide) -> UIImage? {
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        return scaleDown(upright(image), maxSide: maxSide)
    }

    /// Redraws the image so its pixels are upright and `imageOrientation` is `.up`.
    /// The engine reads raw pixels, so a rotated original would be detected sideways.
    public static func upright(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    public static func scaleDown(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longSide = max(image.size.width, image.size.height)
        if longSide <= maxSide { return image }
        let scale = maxSide / longSide
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// The face box plus 12% padding of the shorter side (at least 4 pt), clamped to the image.
    public static func cropFace(_ image: UIImage, box: CGRect, paddingFraction: CGFloat = 0.12) -> UIImage? {
        guard box.width > 1, box.height > 1, let cgImage = upright(image).cgImage else { return nil }
        let scale = CGFloat(cgImage.width) / image.size.width
        let padding = max(4, min(box.width, box.height) * paddingFraction)
        let padded = box.insetBy(dx: -padding, dy: -padding)
        let pixels = CGRect(
            x: padded.minX * scale, y: padded.minY * scale,
            width: padded.width * scale, height: padded.height * scale
        ).integral
        let bounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let clamped = pixels.intersection(bounds)
        guard clamped.width > 1, clamped.height > 1, let cropped = cgImage.cropping(to: clamped) else { return nil }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }

    /// A square crop centred on the face, for the probe tile.
    public static func squareAround(_ image: UIImage, box: CGRect, scale factor: CGFloat = 1.8) -> UIImage {
        guard let cgImage = upright(image).cgImage else { return image }
        let scale = CGFloat(cgImage.width) / image.size.width
        let side = min(max(box.width, box.height) * factor * scale, CGFloat(min(cgImage.width, cgImage.height)))
        guard side > 1 else { return image }
        let centre = CGPoint(x: box.midX * scale, y: box.midY * scale)
        let x = min(max(0, centre.x - side / 2), CGFloat(cgImage.width) - side)
        let y = min(max(0, centre.y - side / 2), CGFloat(cgImage.height) - side)
        guard let cropped = cgImage.cropping(to: CGRect(x: x, y: y, width: side, height: side).integral) else {
            return image
        }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }

    public static func jpeg(_ image: UIImage, quality: CGFloat = 0.92) -> Data? {
        image.jpegData(compressionQuality: quality)
    }

    /// The file name without its extension, used as the person's name when importing a folder.
    public static func stripExtension(_ name: String) -> String {
        (name as NSString).deletingPathExtension
    }
}
