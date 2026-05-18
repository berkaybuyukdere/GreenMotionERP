import UIKit

/// Normalizes Turkey serial-capture photos for storage and PDF (landscape stays landscape).
enum TurkeyCaptureImageOrientation {

  /// Logical size in points using pixel buffer dimensions (ignores stale EXIF on `UIImage.size`).
  static func logicalPixelSize(of image: UIImage) -> CGSize {
    guard let cg = image.cgImage else { return image.size }
    return CGSize(width: CGFloat(cg.width) / image.scale, height: CGFloat(cg.height) / image.scale)
  }

  /// Prepare image for PDF drawing / upload (EXIF baked to `.up` pixels).
  static func preparedForStorage(deviceOrientation: UIDeviceOrientation, image: UIImage) -> UIImage {
    bakedForCapture(deviceOrientation: deviceOrientation, image: image)
  }

  static func preparedForPdf(_ image: UIImage) -> UIImage {
    fixedOrientationToUpPixels(image)
  }

  static func bakedForCapture(deviceOrientation: UIDeviceOrientation, image: UIImage) -> UIImage {
    let upright = fixedOrientationToUpPixels(image)
    guard let cg = upright.cgImage else { return upright }
    let w = CGFloat(cg.width)
    let h = CGFloat(cg.height)
    let heldLandscape = deviceOrientation.isLandscape

    if heldLandscape, w < h {
      return upright.rotated90(clockwise: deviceOrientation == .landscapeLeft)
    }
    if !heldLandscape, w > h, h / w < 0.85 {
      return upright.rotated90(clockwise: true)
    }
    return upright
  }

  /// Bakes rotation to `.up` only — never applies horizontal/vertical mirror from EXIF.
  static func fixedOrientationToUpPixels(_ image: UIImage) -> UIImage {
    let orientation = nonMirroredOrientation(image.imageOrientation)
    guard orientation != .up else {
      guard let cg = image.cgImage else { return image }
      return UIImage(cgImage: cg, scale: image.scale, orientation: .up)
    }
    guard let cg = image.cgImage else { return image }

    let width = CGFloat(cg.width)
    let height = CGFloat(cg.height)
    var transform = CGAffineTransform.identity

    switch orientation {
    case .down:
      transform = transform.translatedBy(x: width, y: height).rotated(by: .pi)
    case .left:
      transform = transform.translatedBy(x: width, y: 0).rotated(by: .pi / 2)
    case .right:
      transform = transform.translatedBy(x: 0, y: height).rotated(by: -.pi / 2)
    default:
      break
    }

    let contextSize: CGSize
    switch orientation {
    case .left, .right:
      contextSize = CGSize(width: height, height: width)
    default:
      contextSize = CGSize(width: width, height: height)
    }

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: contextSize, format: format).image { rendererContext in
      let ctx = rendererContext.cgContext
      ctx.concatenate(transform)
      switch orientation {
      case .right:
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: height, height: width))
      case .left:
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: height, height: width))
      default:
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
      }
    }
  }

  /// Strips mirror flag from EXIF orientation (rotation only).
  private static func nonMirroredOrientation(_ o: UIImage.Orientation) -> UIImage.Orientation {
    switch o {
    case .upMirrored: return .up
    case .downMirrored: return .down
    case .leftMirrored: return .left
    case .rightMirrored: return .right
    default: return o
    }
  }
}

private extension UIDeviceOrientation {
  var isLandscape: Bool {
    self == .landscapeLeft || self == .landscapeRight
  }
}

private extension UIImage {
  func rotated90(clockwise: Bool) -> UIImage {
    guard let cg = cgImage else { return self }
    let w = CGFloat(cg.width)
    let h = CGFloat(cg.height)
    let outSize = CGSize(width: h, height: w)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: outSize, format: format).image { rendererContext in
      let ctx = rendererContext.cgContext
      ctx.translateBy(x: outSize.width / 2, y: outSize.height / 2)
      ctx.rotate(by: clockwise ? .pi / 2 : -.pi / 2)
      ctx.draw(cg, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
    }
  }
}
