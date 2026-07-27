import AppKit

extension NSColor {
    func contrastRatio(with other: NSColor, appearance: NSAppearance? = nil) -> CGFloat {
        let l1 = self.relativeLuminance(appearance: appearance)
        let l2 = other.relativeLuminance(appearance: appearance)
        let hi = max(l1, l2)
        let lo = min(l1, l2)
        return (hi + 0.05) / (lo + 0.05)
    }

    func ensuringContrast(on background: NSColor, minRatio: CGFloat, appearance: NSAppearance? = nil) -> NSColor {
        let fg = self.resolvedRGBColor(appearance: appearance)
        let bg = background.resolvedRGBColor(appearance: appearance)

        if fg.contrastRatio(with: bg) >= minRatio {
            return self
        }

        let white = Self.bestMix(foreground: fg, background: bg, target: .white, minRatio: minRatio)
        let black = Self.bestMix(foreground: fg, background: bg, target: .black, minRatio: minRatio)

        if let white, let black {
            return white.mixFraction <= black.mixFraction ? white.color : black.color
        }
        if let white {
            return white.color
        }
        if let black {
            return black.color
        }

        let fallbackWhite = fg.blended(with: .white, fraction: 1.0)
        let fallbackBlack = fg.blended(with: .black, fraction: 1.0)
        return fallbackWhite.contrastRatio(with: bg) >= fallbackBlack.contrastRatio(with: bg)
            ? fallbackWhite
            : fallbackBlack
    }

    private func relativeLuminance(appearance: NSAppearance?) -> CGFloat {
        guard let rgba = self.rgba(appearance: appearance) else { return 0 }

        let r = Self.srgbToLinear(rgba.r)
        let g = Self.srgbToLinear(rgba.g)
        let b = Self.srgbToLinear(rgba.b)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private struct RGBA {
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        let a: CGFloat
    }

    private func rgba(appearance: NSAppearance?) -> RGBA? {
        if let appearance {
            var resolved: RGBA?
            appearance.performAsCurrentDrawingAppearance {
                resolved = self.rgba(appearance: nil)
            }
            return resolved
        }

        let rgb = self.usingColorSpace(.deviceRGB) ?? self.usingColorSpace(.sRGB)
        guard let rgb else { return nil }

        return RGBA(r: rgb.redComponent, g: rgb.greenComponent, b: rgb.blueComponent, a: rgb.alphaComponent)
    }

    private static func srgbToLinear(_ c: CGFloat) -> CGFloat {
        if c <= 0.04045 {
            return c / 12.92
        }
        return pow((c + 0.055) / 1.055, 2.4)
    }

    private func resolvedRGBColor(appearance: NSAppearance?) -> NSColor {
        guard let rgba = self.rgba(appearance: appearance) else { return self }

        return NSColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
    }

    private func blended(with other: NSColor, fraction: CGFloat) -> NSColor {
        let f = max(0, min(1, fraction))
        guard let a = self.rgba(appearance: nil), let b = other.rgba(appearance: nil) else { return self }

        return NSColor(
            srgbRed: a.r + (b.r - a.r) * f,
            green: a.g + (b.g - a.g) * f,
            blue: a.b + (b.b - a.b) * f,
            alpha: a.a + (b.a - a.a) * f
        )
    }

    private struct MixCandidate {
        let mixFraction: CGFloat
        let color: NSColor
    }

    private static func bestMix(
        foreground: NSColor,
        background: NSColor,
        target: NSColor,
        minRatio: CGFloat
    ) -> MixCandidate? {
        for step in 0 ... 20 {
            let fraction = CGFloat(step) / 20
            let candidate = foreground.blended(with: target, fraction: fraction)
            let ratio = candidate.contrastRatio(with: background)
            if ratio >= minRatio {
                return MixCandidate(mixFraction: fraction, color: candidate)
            }
        }
        return nil
    }
}
