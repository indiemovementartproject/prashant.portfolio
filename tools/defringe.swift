// defringe: clean the edges of a cut-out so no trace of the old background shows on a dark page.
//   swift tools/defringe.swift <cutout.png> <original-photo> <out.png>
// 1. Samples the original background colour from the photo's corners.
// 2. Colour decontamination: for every partly transparent edge pixel, removes the share of
//    background colour mixed into it (F = (P - (1 - a) * B) / a).
// 3. Tightens the alpha edge slightly, so the soft halo of background goes.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
guard a.count == 4 else { print("usage: defringe cutout original out"); exit(1) }
func load(_ p: String) -> CGImage {
  let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil)!
  return CGImageSourceCreateImageAtIndex(s, 0, nil)!
}
func pixels(_ img: CGImage) -> ([UInt8], Int, Int) {
  let w = img.width, h = img.height
  var px = [UInt8](repeating: 0, count: w * h * 4)
  let c = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
  return (px, w, h)
}

// Background colour: average of the four 24x24 corners of the original photo.
let (op, ow, oh) = pixels(load(a[2]))
var bs = [0.0, 0.0, 0.0], n = 0.0
for (cx, cy) in [(0, 0), (ow - 24, 0), (0, oh - 24), (ow - 24, oh - 24)] {
  for y in cy..<(cy + 24) { for x in cx..<(cx + 24) {
    let i = (y * ow + x) * 4
    bs[0] += Double(op[i]); bs[1] += Double(op[i + 1]); bs[2] += Double(op[i + 2]); n += 1 } }
}
let B = bs.map { $0 / n / 255 }

var (px, w, h) = pixels(load(a[1]))
for i in stride(from: 0, to: px.count, by: 4) {
  let al = Double(px[i + 3]) / 255
  if al == 0 { continue }
  var c = (0..<3).map { Double(px[i + $0]) / 255 / al }          // unpremultiply: the photo's pixel
  if al < 0.98 { c = (0..<3).map { max(0, min(1, (c[$0] - (1 - al) * B[$0]) / al)) } }
  // Tighten: fade the outer ~third of the soft edge.
  let t = max(0, min(1, (al - 0.32) / 0.6)); let na = t * t * (3 - 2 * t)
  for k in 0..<3 { px[i + k] = UInt8(max(0, min(255, c[k] * na * 255))) }
  px[i + 3] = UInt8(na * 255)
}
let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[3]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(d, ctx.makeImage()!, nil)
CGImageDestinationFinalize(d)
print(String(format: "background %.2f %.2f %.2f -> %@", B[0], B[1], B[2], a[3]))
