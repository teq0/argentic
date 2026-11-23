import CoreGraphics

/// Conservative first-render defaults; explicitly selected or restored output settings take precedence.
enum StartupSizing {
    static let maximumImagePixels: CGFloat = 4_000_000
    static let maximumImageDimension: CGFloat = 4096
    static let minimumLongEdge: CGFloat = 640

    static func windowSize(availableSize: CGSize) -> CGSize {
        guard availableSize.width.isFinite, availableSize.height.isFinite,
              availableSize.width > 0, availableSize.height > 0 else {
            return CGSize(width: 1024, height: 768)
        }
        return CGSize(
            width: max(min(480, availableSize.width), (availableSize.width * 0.9).rounded(.down)),
            height: max(min(360, availableSize.height), (availableSize.height * 0.9).rounded(.down))
        )
    }

    static func imageSize(availableSize: CGSize, displayScale: CGFloat, aspectRatio: CGFloat) -> CGSize {
        guard availableSize.width.isFinite, availableSize.height.isFinite,
              availableSize.width > 0, availableSize.height > 0 else {
            return CGSize(width: 640, height: 480)
        }
        let scale = displayScale.isFinite && displayScale > 0 ? displayScale : 1
        let aspect = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 4 / 3
        let maxWidth = min(availableSize.width * scale, maximumImageDimension)
        let maxHeight = min(availableSize.height * scale, maximumImageDimension)
        var width = min(maxWidth, maxHeight * aspect)
        var height = width / aspect
        // SwiftUI can briefly propose a tiny non-zero canvas during window creation.
        // Automatic output sizing must not produce a thumbnail, even for a compact viewport.
        let longEdge = max(width, height)
        guard longEdge.isFinite && longEdge > 0 else { return CGSize(width: 640, height: 480) }
        let enlarged = longEdge < minimumLongEdge
        if enlarged {
            let enlargement = minimumLongEdge / longEdge
            width *= enlargement
            height *= enlargement
        }
        let pixels = width * height
        if pixels > maximumImagePixels {
            let reduction = (maximumImagePixels / pixels).squareRoot()
            width *= reduction
            height *= reduction
        }
        // Avoid rounding a minimum-size result such as 639.999999999 down to 639.
        let rounding: FloatingPointRoundingRule = enlarged ? .toNearestOrAwayFromZero : .down
        return CGSize(width: max(16, width.rounded(rounding)), height: max(16, height.rounded(rounding)))
    }
}
