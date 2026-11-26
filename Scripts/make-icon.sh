#!/bin/bash
# Generates Resources/AppIcon.icns from a rendered 1024px PNG using only system tools
# (swift + sips + iconutil). Run once; the .icns is checked into the repo.
#
# Current design: dark charcoal squircle, white chat bubble with a teal
# counterclockwise rotate arrow inside ("recalled message is being undone").
#
# ICON GEOMETRY (measured against real macOS app icons):
#   Chrome / WeChat / Notes / Photos / Messages all draw their artwork in the
#   centered 80% of the 1024px canvas with 10% transparent margins — that is
#   the Apple guideline, and full-bleed artwork really does render ~25% larger
#   in the Dock. But at exactly 80%, our dark background plus a small white
#   glyph reads as visually smaller/lighter than neighbouring light icons
#   (dark colours contract, light ones expand). So we deliberately use 88%
#   artwork (6% margins) and a larger glyph: the square is only ~10% larger
#   than standard — never "a full size bigger" — while the icon gains the
#   visual weight of the apps around it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SWIFT_SRC="$WORK/render.swift"
cat > "$SWIFT_SRC" <<'SWIFT'
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Clear the whole canvas to transparent; draw the artwork in the centered
// safe area so macOS scales it consistently with other Dock icons.
let canvas = NSRect(x: 0, y: 0, width: size, height: size)
if let cg = NSGraphicsContext.current?.cgContext { cg.clear(canvas) }

let margin = size * 0.06
let artSize = size * 0.88
let artRect = NSRect(x: margin, y: margin, width: artSize, height: artSize)
let cx = size * 0.5
let cy = size * 0.5

// Rounded-rect background with a dark charcoal gradient.
let corner = artSize * 0.2237   // macOS icon superellipse-ish radius
let bgPath = NSBezierPath(roundedRect: artRect, xRadius: corner, yRadius: corner)
bgPath.addClip()
let bgTop = NSColor(calibratedRed: 0.25, green: 0.27, blue: 0.29, alpha: 1)
let bgBottom = NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.15, alpha: 1)
NSGradient(starting: bgTop, ending: bgBottom)?.draw(in: artRect, angle: -90)

// White chat bubble: filled circle + small tail on the right side.
// The tail is kept short enough that the larger glyph still has breathing
// room inside the artwork (1.33r instead of 1.46r).
let r = artSize * 0.33
let bubble = NSBezierPath()
bubble.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: r,
                 startAngle: 0, endAngle: 360, clockwise: false)
let tail = NSBezierPath()
tail.move(to: NSPoint(x: cx + r * 0.90, y: cy + r * 0.34))
tail.line(to: NSPoint(x: cx + r * 1.33, y: cy + r * 0.12))
tail.line(to: NSPoint(x: cx + r * 0.86, y: cy - r * 0.40))
tail.close()
NSColor.white.set()
bubble.fill()
tail.fill()

// Teal counterclockwise rotate arrow inside the bubble.
// Arc spans top -> left -> bottom -> right with a gap at the top-right;
// the arrowhead lands on the right side moving upward (undo motion).
let aR = artSize * 0.18
let stroke = artSize * 0.056
let arc = NSBezierPath()
arc.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: aR,
              startAngle: 80, endAngle: 380, clockwise: false)
arc.lineWidth = stroke
arc.lineCapStyle = .round
let teal = NSColor(calibratedRed: 0.055, green: 0.68, blue: 0.49, alpha: 1)
teal.set()
arc.stroke()

// Arrowhead triangle at the arc end (angle 20 deg), tangent pointing CCW.
let endRad = 20.0 * Double.pi / 180.0
let ex = cx + aR * cos(endRad)
let ey = cy + aR * sin(endRad)
let tx = -sin(endRad), ty = cos(endRad)          // tangent (CCW motion)
let nx = cos(endRad), ny = sin(endRad)           // outward normal
let headLen = artSize * 0.115
let headHalf = artSize * 0.075
let tipX = ex + tx * headLen, tipY = ey + ty * headLen
let baseBack = artSize * 0.02
let head = NSBezierPath()
head.move(to: NSPoint(x: tipX, y: tipY))
head.line(to: NSPoint(x: ex - nx * headHalf - tx * baseBack,
                      y: ey - ny * headHalf - ty * baseBack))
head.line(to: NSPoint(x: ex + nx * headHalf - tx * baseBack,
                      y: ey + ny * headHalf - ty * baseBack))
head.close()
teal.set()
head.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to render icon\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT

PNG="$WORK/icon_1024.png"
swift "$SWIFT_SRC" "$PNG"

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
  px="${spec%% *}"; name="${spec##* }"
  sips -z "$px" "$px" "$PNG" --out "$ICONSET/icon_$name.png" >/dev/null
done

mkdir -p "$ROOT/Resources"
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
echo ">> Wrote $ROOT/Resources/AppIcon.icns"
