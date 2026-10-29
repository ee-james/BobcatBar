/**
 * @file    MenuIcon.swift
 * @author  James Zeman
 * @date    28 OCT 2026
 * @brief   The menu-bar icon: the Supercat, a drawn paw print, or your own image.
 *          Template icons follow the menu bar's light or dark look; a custom image
 *          can instead keep its own colors.
 */
import AppKit

enum MenuIcon {
    /**
     * @brief   Where an imported image is kept (~/.config/bobcatbar/menubar-icon.png).
     */
    static var customURL: URL { ConfigStore.dir.appendingPathComponent("menubar-icon.png") }

    /**
     * @brief   The icon the config asks for, 18 points tall.
     *
     * @param   config  the config (icon and iconColor).
     * @return  the image; the Supercat if a custom image is missing.
     */
    static func image(for config: Config) -> NSImage {
        switch config.icon {
        case "paw":
            return paw()
        case "custom":
            if let img = custom(color: config.iconColor) { return img }
            return supercat()
        default:
            return supercat()
        }
    }

    /**
     * @brief   Copies an image into the config folder as the custom icon, scaled to
     *          36 pixels tall (18 points on a Retina menu bar), at most twice as wide.
     *
     * @param   url     the image file the user picked.
     * @throws  when it isn't an image macOS can read, or can't be saved.
     */
    static func importImage(from url: URL) throws {
        guard let src = NSImage(contentsOf: url),
              let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ConfigStore.Failure(message: "That file isn't an image BobcatBar can read.")
        }
        let h = 36, w = min(72, max(1, Int((Double(cg.width) / Double(cg.height) * 36).rounded())))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ConfigStore.Failure(message: "Couldn't resize the image.")
        }
        ctx.interpolationQuality = .high
        // aspect-fit inside w×h
        let scale = min(Double(w) / Double(cg.width), Double(h) / Double(cg.height))
        let dw = Double(cg.width) * scale, dh = Double(cg.height) * scale
        ctx.draw(cg, in: CGRect(x: (Double(w) - dw) / 2, y: (Double(h) - dh) / 2, width: dw, height: dh))
        guard let out = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:]) else {
            throw ConfigStore.Failure(message: "Couldn't convert the image.")
        }
        do {
            try FileManager.default.createDirectory(at: ConfigStore.dir, withIntermediateDirectories: true)
            try png.write(to: customURL, options: .atomic)
        } catch {
            throw ConfigStore.Failure(message: "Couldn't save the image: \(error.localizedDescription)")
        }
    }

    /**
     * @brief   The custom icon, as a template or in its own colors.
     *
     * @param   color   keep its colors (doesn't follow light and dark menu bars).
     * @return  the image, or nil if there isn't a readable one.
     */
    static func custom(color: Bool) -> NSImage? {
        guard let img = NSImage(contentsOf: customURL),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let size = NSSize(width: Double(cg.width) / 2, height: Double(cg.height) / 2)
        if color {
            let out = NSImage(cgImage: cg, size: size)
            out.isTemplate = false
            return out
        }
        let out = NSImage(cgImage: templateMask(cg) ?? cg, size: size)
        out.isTemplate = true
        return out
    }

    /**
     * @brief   Makes an image usable as a template. macOS draws a template from its
     *          alpha alone, so an opaque picture (a JPEG, a logo on white) would show
     *          as a solid block. For those, darker pixels become solid and lighter
     *          ones clear, which suits a dark logo on a light background; a light logo
     *          on dark is inverted to match.
     *
     * @param   cg  the image.
     * @return  a black image with the derived alpha, or nil to use the image as is
     *          (it already has transparency).
     */
    static func templateMask(_ cg: CGImage) -> CGImage? {
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        let n = w * h
        let clear = (0..<n).filter { px[$0 * 4 + 3] < 128 }.count
        if clear > n / 20 { return nil }   // has real transparency: already a template shape

        // luminance of each pixel; the border's average says which side is background
        var lum = [Double](repeating: 0, count: n)
        for i in 0..<n {
            lum[i] = (0.2126 * Double(px[i * 4]) + 0.7152 * Double(px[i * 4 + 1]) + 0.0722 * Double(px[i * 4 + 2])) / 255
        }
        var border: [Double] = []
        for x in 0..<w { border += [lum[x], lum[(h - 1) * w + x]] }
        for y in 0..<h { border += [lum[y * w], lum[y * w + w - 1]] }
        let bg = border.reduce(0, +) / Double(border.count)
        let lo = lum.min() ?? 0, hi = lum.max() ?? 1
        let span = max(hi - lo, 0.01)

        var out = [UInt8](repeating: 0, count: n * 4)
        for i in 0..<n {
            let t = (lum[i] - lo) / span                // 0 = darkest, 1 = lightest
            let a = bg > 0.5 ? 1 - t : t                // the side unlike the background is solid
            out[i * 4 + 3] = UInt8(max(0, min(255, a * 255)))   // black, premultiplied
        }
        guard let octx = CGContext(data: &out, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        return octx.makeImage()
    }

    /**
     * @brief   The Supercat template from the app bundle, or the paw if it's missing
     *          (a debug run outside the .app).
     */
    static func supercat() -> NSImage {
        if let url = Bundle.main.url(forResource: "BobcatTemplate@2x", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            return img
        }
        return paw()
    }

    /**
     * @brief   A simple drawn paw print.
     */
    static func paw() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 5, y: 3, width: 8, height: 7)).fill()   // pad
            for cx in [4.0, 7.5, 11.0, 14.0] {
                let y = cx == 7.5 || cx == 11.0 ? 11.0 : 9.0
                NSBezierPath(ovalIn: NSRect(x: cx - 1.6, y: y, width: 3.2, height: 4)).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
