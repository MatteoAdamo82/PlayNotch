import AppKit

extension NSImage {
    /// A vibrant, representative colour for the image — used to theme the notch
    /// from the current artwork. Returns nil if no usable colour is found.
    ///
    /// The image is downscaled to a small bitmap; pixels are bucketed by hue and
    /// weighted by saturation × brightness, so a colourful accent wins over a
    /// muddy average. Greys and near-black/white pixels are ignored. The result
    /// is normalised to stay bright and saturated enough to read on black.
    func vibrantColor() -> NSColor? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let size = 36
        let bytesPerRow = size * 4
        var data = [UInt8](repeating: 0, count: size * size * 4)
        guard let ctx = CGContext(
            data: &data,
            width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))

        let buckets = 12
        var weight = [Double](repeating: 0, count: buckets)
        var sumR = [Double](repeating: 0, count: buckets)
        var sumG = [Double](repeating: 0, count: buckets)
        var sumB = [Double](repeating: 0, count: buckets)
        var avg = (r: 0.0, g: 0.0, b: 0.0, n: 0.0)

        var i = 0
        while i < data.count {
            defer { i += 4 }
            let alpha = Double(data[i + 3]) / 255
            if alpha < 0.5 { continue }
            let r = Double(data[i]) / 255
            let g = Double(data[i + 1]) / 255
            let b = Double(data[i + 2]) / 255
            avg = (avg.r + r, avg.g + g, avg.b + b, avg.n + 1)

            let (h, s, v) = Self.hsb(r, g, b)
            if s < 0.25 || v < 0.2 || v > 0.95 { continue }   // skip grey / extremes
            let w = s * v
            let idx = min(buckets - 1, Int(h * Double(buckets)))
            weight[idx] += w
            sumR[idx] += r * w
            sumG[idx] += g * w
            sumB[idx] += b * w
        }

        if let top = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[top] > 0 {
            let w = weight[top]
            return Self.normalised(r: sumR[top] / w, g: sumG[top] / w, b: sumB[top] / w)
        }
        guard avg.n > 0 else { return nil }
        return Self.normalised(r: avg.r / avg.n, g: avg.g / avg.n, b: avg.b / avg.n)
    }

    private static func hsb(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d != 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    /// Clamp saturation/brightness so the accent reads well on a black surface.
    private static func normalised(r: Double, g: Double, b: Double) -> NSColor {
        let (h, s, v) = hsb(r, g, b)
        return NSColor(
            hue: CGFloat(h),
            saturation: CGFloat(max(s, 0.55)),
            brightness: CGFloat(min(max(v, 0.62), 0.92)),
            alpha: 1
        )
    }
}
