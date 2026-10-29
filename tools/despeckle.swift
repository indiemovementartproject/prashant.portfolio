// despeckle: clean a small, compressed colour logo that has no intended white or grey in it.
// Washed-out pixels (compression specks inside letters, the pale rim left from a white matte)
// take the colour of their strongly coloured neighbours; alpha is left as it is.
//
//   swift tools/despeckle.swift <in.png> <out.png> [--chroma=0.3] [--radius=2]
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
guard a.count >= 3 else { print("usage: despeckle in out [--chroma=] [--radius=]"); exit(1) }
func opt(_ k: String, _ d: Double) -> Double {
  a.first(where: { $0.hasPrefix("--\(k)=") }).flatMap { Double($0.split(separator: "=")[1]) } ?? d
}
let minChroma = opt("chroma", 0.3), R = Int(opt("radius", 2))

let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let W = img.width, H = img.height, cs = CGColorSpaceCreateDeviceRGB()
var px = [UInt8](repeating: 0, count: W * H * 4)
CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: cs,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))

// Straight colour per pixel, and whether it is a "solid" brand colour we can borrow from.
var col = [[Double]](repeating: [0, 0, 0], count: W * H), alpha = [Double](repeating: 0, count: W * H)
var solid = [Bool](repeating: false, count: W * H)
for i in 0..<(W * H) {
  let al = Double(px[i * 4 + 3]) / 255
  alpha[i] = al
  if al > 0 { col[i] = (0..<3).map { Double(px[i * 4 + $0]) / 255 / al } }
  let c = col[i]
  solid[i] = al > 0.85 && (c.max()! - c.min()!) >= minChroma
}

var fixed = 0
var out = px
for y in 0..<H { for x in 0..<W {
  let i = y * W + x
  if alpha[i] == 0 || solid[i] { continue }
  // Search outward ring by ring for solid neighbours; weight nearer ones more.
  var acc = [0.0, 0.0, 0.0], w = 0.0
  for r in 1...max(1, R * 3) {
    for dy in -r...r { for dx in -r...r where max(abs(dx), abs(dy)) == r {
      let nx = x + dx, ny = y + dy
      if nx < 0 || ny < 0 || nx >= W || ny >= H { continue }
      let j = ny * W + nx
      if !solid[j] { continue }
      let k = 1 / Double(dx * dx + dy * dy)
      for c in 0..<3 { acc[c] += col[j][c] * k }; w += k
    } }
    if w > 0 && r >= R { break }
  }
  if w == 0 { continue }
  for c in 0..<3 { out[i * 4 + c] = UInt8(max(0, min(255, acc[c] / w * alpha[i] * 255))) }
  fixed += 1
} }

let ctx = CGContext(data: &out, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(d, ctx.makeImage()!, nil)
CGImageDestinationFinalize(d)
print("\(a[1]) -> \(a[2]): recoloured \(fixed) pixels")
