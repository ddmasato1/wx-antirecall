#!/bin/bash
# Generates Resources/AppIcon.icns from a rendered 1024px PNG using only system tools
# (swift + sips + iconutil). Run once; the .icns is checked into the repo.
#
# Design: Emerald-jade squircle with subtle top specular glow and soft drop shadow,
# layered translucent secondary chat bubble + crisp white primary chat bubble (both
# single continuous closed Bezier contours with zero seam overlap), and a bold emerald
# counterclockwise recall-shield arc arrow at the center.
#
# ICON GEOMETRY (measured against real macOS app icons):
#   Artwork occupies the centered 80% of the 1024px canvas with 10% transparent margins
#   so macOS scales it consistently with native Dock icons.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d /tmp/antirecall-icon.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

SWIFT_SRC="$WORK/render.swift"
cat > "$SWIFT_SRC" <<'SWIFT'
import AppKit

/// Builds a seamless, single-contour elliptical chat bubble path with no internal overlap.
func makeChatBubble(center: NSPoint, rx: CGFloat, ry: CGFloat, tailOnLeft: Bool) -> NSBezierPath {
    let p = NSBezierPath()
    if tailOnLeft {
        // Arc CCW from 238° around bottom -> right -> top -> left to 568° (208°)
        p.appendArc(withCenter: .zero, radius: 1.0, startAngle: 238, endAngle: 568, clockwise: false)
        p.curve(
            to: NSPoint(x: -1.03, y: -0.95),
            controlPoint1: NSPoint(x: -0.95, y: -0.65),
            controlPoint2: NSPoint(x: -1.02, y: -0.83)
        )
        p.curve(
            to: NSPoint(x: cos(238.0 * .pi / 180.0), y: sin(238.0 * .pi / 180.0)),
            controlPoint1: NSPoint(x: -0.86, y: -0.94),
            controlPoint2: NSPoint(x: -0.68, y: -0.89)
        )
    } else {
        // Arc CCW from 332° around right -> top -> left -> bottom to 662° (302°)
        p.appendArc(withCenter: .zero, radius: 1.0, startAngle: 332, endAngle: 662, clockwise: false)
        p.curve(
            to: NSPoint(x: 1.03, y: -0.95),
            controlPoint1: NSPoint(x: 0.68, y: -0.89),
            controlPoint2: NSPoint(x: 0.86, y: -0.94)
        )
        p.curve(
            to: NSPoint(x: cos(332.0 * .pi / 180.0), y: sin(332.0 * .pi / 180.0)),
            controlPoint1: NSPoint(x: 1.02, y: -0.83),
            controlPoint2: NSPoint(x: 0.95, y: -0.65)
        )
    }
    p.close()

    var xf = AffineTransform.identity
    xf.translate(x: center.x, y: center.y)
    xf.scale(x: rx, y: ry)
    p.transform(using: xf)
    return p
}

let size = 1024.0
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size),
    pixelsHigh: Int(size),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
let cg = ctx.cgContext

let canvas = NSRect(x: 0, y: 0, width: size, height: size)
cg.clear(canvas)

let margin = size * 0.10
let artSize = size * 0.80
let artRect = NSRect(x: margin, y: margin, width: artSize, height: artSize)
let cx = size * 0.5
let cy = size * 0.5
let corner = artSize * 0.2237
let bgPath = NSBezierPath(roundedRect: artRect, xRadius: corner, yRadius: corner)

// 1. Soft exterior drop shadow for macOS native icon depth (stays well inside 10% margin)
NSGraphicsContext.saveGraphicsState()
let outerShadow = NSShadow()
outerShadow.shadowOffset = NSSize(width: 0, height: -14)
outerShadow.shadowBlurRadius = 28
outerShadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.26)
outerShadow.set()
NSColor(calibratedRed: 0.03, green: 0.52, blue: 0.35, alpha: 1.0).setFill()
bgPath.fill()
NSGraphicsContext.restoreGraphicsState()

// 2. Clip to squircle and paint rich multi-stop emerald gradient + top glow
NSGraphicsContext.saveGraphicsState()
bgPath.addClip()

let bgGradient = NSGradient(colorsAndLocations:
    (NSColor(calibratedRed: 0.13, green: 0.84, blue: 0.51, alpha: 1.0), 0.0),
    (NSColor(calibratedRed: 0.04, green: 0.69, blue: 0.43, alpha: 1.0), 0.52),
    (NSColor(calibratedRed: 0.015, green: 0.47, blue: 0.33, alpha: 1.0), 1.0)
)!
bgGradient.draw(in: artRect, angle: -90)

// Ambient top-left highlight glow
let glowGradient = NSGradient(
    starting: NSColor(calibratedRed: 0.62, green: 1.0, blue: 0.82, alpha: 0.30),
    ending: NSColor(calibratedRed: 0.62, green: 1.0, blue: 0.82, alpha: 0.0)
)!
glowGradient.draw(
    fromCenter: NSPoint(x: cx - artSize * 0.16, y: cy + artSize * 0.36),
    radius: 0,
    toCenter: NSPoint(x: cx - artSize * 0.10, y: cy + artSize * 0.28),
    radius: artSize * 0.65,
    options: []
)

// 3. Frosted secondary chat bubble (top-right behind main bubble for depth)
let sCenter = NSPoint(x: cx + artSize * 0.155, y: cy + artSize * 0.135)
let sRx = artSize * 0.185
let sRy = artSize * 0.152
let secondaryBubble = makeChatBubble(center: sCenter, rx: sRx, ry: sRy, tailOnLeft: false)

NSColor(calibratedWhite: 1.0, alpha: 0.23).setFill()
secondaryBubble.fill()
NSColor(calibratedWhite: 1.0, alpha: 0.34).setStroke()
secondaryBubble.lineWidth = 3.0
secondaryBubble.stroke()

for dx in [-0.26, 0.22] {
    let dotR = artSize * 0.022
    let dotRect = NSRect(
        x: sCenter.x + sRx * dx - dotR,
        y: sCenter.y - dotR * 0.5,
        width: dotR * 2,
        height: dotR * 2
    )
    NSColor(calibratedWhite: 1.0, alpha: 0.48).setFill()
    NSBezierPath(ovalIn: dotRect).fill()
}

// 4. Primary crisp white chat bubble (slightly lower-left to balance visual center)
let bCenter = NSPoint(x: cx - artSize * 0.045, y: cy - artSize * 0.038)
let bRx = artSize * 0.285
let bRy = artSize * 0.245
let mainBubble = makeChatBubble(center: bCenter, rx: bRx, ry: bRy, tailOnLeft: true)

NSGraphicsContext.saveGraphicsState()
let bubbleShadow = NSShadow()
bubbleShadow.shadowOffset = NSSize(width: 0, height: -14)
bubbleShadow.shadowBlurRadius = 26
bubbleShadow.shadowColor = NSColor(calibratedRed: 0.0, green: 0.22, blue: 0.14, alpha: 0.30)
bubbleShadow.set()
NSColor.white.setFill()
mainBubble.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
mainBubble.addClip()
let bubbleGrad = NSGradient(
    starting: NSColor(calibratedWhite: 1.0, alpha: 1.0),
    ending: NSColor(calibratedRed: 0.94, green: 0.98, blue: 0.96, alpha: 1.0)
)!
bubbleGrad.draw(
    in: NSRect(x: bCenter.x - bRx * 1.1, y: bCenter.y - bRy * 1.1, width: bRx * 2.2, height: bRy * 2.2),
    angle: -90
)
NSGraphicsContext.restoreGraphicsState()

// 5. Emerald counterclockwise recall-retention arrow inside primary bubble
let aR = artSize * 0.128
let stroke = artSize * 0.048
let arc = NSBezierPath()
arc.appendArc(withCenter: bCenter, radius: aR, startAngle: 72, endAngle: 355, clockwise: false)
arc.lineWidth = stroke
arc.lineCapStyle = .round
let iconGreen = NSColor(calibratedRed: 0.03, green: 0.65, blue: 0.41, alpha: 1.0)
iconGreen.setStroke()
arc.stroke()

let endDeg = 355.0
let endRad = endDeg * Double.pi / 180.0
let ex = bCenter.x + aR * cos(endRad)
let ey = bCenter.y + aR * sin(endRad)
let tx = -sin(endRad), ty = cos(endRad)
let nx = cos(endRad), ny = sin(endRad)
let headLen = artSize * 0.095
let headHalf = artSize * 0.064
let baseBack = artSize * 0.018

let head = NSBezierPath()
head.move(to: NSPoint(x: ex + tx * headLen, y: ey + ty * headLen))
head.line(to: NSPoint(x: ex - nx * headHalf - tx * baseBack,
                      y: ey - ny * headHalf - ty * baseBack))
head.line(to: NSPoint(x: ex + nx * headHalf - tx * baseBack,
                      y: ey + ny * headHalf - ty * baseBack))
head.close()
head.lineJoinStyle = .round
iconGreen.setFill()
head.fill()

let centerDotR = artSize * 0.030
let centerDot = NSBezierPath(ovalIn: NSRect(
    x: bCenter.x - centerDotR,
    y: bCenter.y - centerDotR,
    width: centerDotR * 2,
    height: centerDotR * 2
))
NSColor(calibratedRed: 0.07, green: 0.76, blue: 0.48, alpha: 1.0).setFill()
centerDot.fill()

// 6. Subtle inner rim highlight around the squircle edge
let insetRect = artRect.insetBy(dx: 1.5, dy: 1.5)
let rimPath = NSBezierPath(roundedRect: insetRect, xRadius: corner - 1.5, yRadius: corner - 1.5)
rimPath.lineWidth = 3.0
NSColor(calibratedWhite: 1.0, alpha: 0.24).setStroke()
rimPath.stroke()

NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to render icon\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT

PNG="$WORK/icon_1024.png"
mkdir -p "$WORK/ModuleCache"
swift -module-cache-path "$WORK/ModuleCache" "$SWIFT_SRC" "$PNG"

if [ -n "${PREVIEW_PNG:-}" ]; then
  mkdir -p "$(dirname "$PREVIEW_PNG")"
  cp "$PNG" "$PREVIEW_PNG"
fi

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
  px="${spec%% *}"; name="${spec##* }"
  sips -z "$px" "$px" "$PNG" --out "$ICONSET/icon_$name.png" >/dev/null
done

mkdir -p "$ROOT/Resources"
OUT_ICNS="$ROOT/Resources/AppIcon.icns"
if ! iconutil -c icns "$ICONSET" -o "$OUT_ICNS" 2>/dev/null; then
  python3 - "$ICONSET" "$OUT_ICNS" <<'PY'
import os, struct, sys

iconset, out_path = sys.argv[1], sys.argv[2]
mapping = [
    (b"icp4", "icon_16x16.png"),
    (b"ic11", "icon_16x16@2x.png"),
    (b"icp5", "icon_32x32.png"),
    (b"ic12", "icon_32x32@2x.png"),
    (b"ic07", "icon_128x128.png"),
    (b"ic13", "icon_128x128@2x.png"),
    (b"ic08", "icon_256x256.png"),
    (b"ic14", "icon_256x256@2x.png"),
    (b"ic09", "icon_512x512.png"),
    (b"ic10", "icon_512x512@2x.png"),
]
chunks = bytearray()
for ostype, filename in mapping:
    data = open(os.path.join(iconset, filename), "rb").read()
    chunks += ostype + struct.pack(">I", 8 + len(data)) + data

with open(out_path, "wb") as f:
    f.write(b"icns" + struct.pack(">I", 8 + len(chunks)) + chunks)
PY
fi
echo ">> Wrote $OUT_ICNS"
