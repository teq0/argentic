import CoreGraphics

enum ImageDisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case fitToWindow
    case actualPixels

    var id: String { rawValue }
    var title: String {
        switch self {
        case .fitToWindow: return "Fit to Window"
        case .actualPixels: return "Actual Pixels (100%)"
        }
    }

    static var platformDefault: Self {
        #if os(macOS)
        .actualPixels
        #else
        .fitToWindow
        #endif
    }
}

/// Display-only geometry. Image coordinates remain pixels, while SwiftUI geometry is in points.
struct ImageDisplayLayout {
    let imageSize: CGSize
    let pointsPerPixel: CGFloat
    let displayScale: CGFloat

    init(imageSize: CGSize, availableSize: CGSize, mode: ImageDisplayMode, displayScale: CGFloat) {
        self.imageSize = imageSize
        self.displayScale = displayScale.isFinite && displayScale > 0 ? displayScale : 1
        guard imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0 else {
            pointsPerPixel = 0
            return
        }
        switch mode {
        case .actualPixels:
            pointsPerPixel = 1 / self.displayScale
        case .fitToWindow:
            guard availableSize.width.isFinite, availableSize.height.isFinite else {
                pointsPerPixel = 0
                return
            }
            pointsPerPixel = max(0, min(availableSize.width / imageSize.width, availableSize.height / imageSize.height))
        }
    }

    var displayedSize: CGSize {
        guard pointsPerPixel > 0 else { return .zero }
        return CGSize(width: imageSize.width * pointsPerPixel, height: imageSize.height * pointsPerPixel)
    }

    /// 1.0 means one image pixel per physical display pixel, not one image pixel per UI point.
    var magnification: CGFloat { pointsPerPixel * displayScale }

    func imagePoint(from point: CGPoint) -> CGPoint? {
        guard pointsPerPixel > 0 else { return nil }
        return CGPoint(x: min(max(point.x / pointsPerPixel, 0), imageSize.width),
                       y: min(max(point.y / pointsPerPixel, 0), imageSize.height))
    }

    func displayedRect(from rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * pointsPerPixel, y: rect.minY * pointsPerPixel,
               width: rect.width * pointsPerPixel, height: rect.height * pointsPerPixel)
    }
}
