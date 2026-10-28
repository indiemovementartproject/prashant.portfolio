// logo-variants: turn a logo into the two PNGs the site uses on its dark background.
//
//   swift tools/logo-variants.swift <in> <out-grey.png> <out-hover.png> [--key-white] [--key-hue=H,TOL]
//
// --key-white      knock out a flat white/near-white background reachable from the edges
// --key-hue=H,TOL  knock out a coloured background reachable from the edges (hue in degrees)
//
// grey  : light-grey version for the default state. Dark, unsaturated "ink" becomes a light grey;
//         everything else becomes a grey lifted into the light range, so tonal detail survives.
// hover : the original colours, except dark unsaturated ink (black, charcoal, navy-ish) turns
//         white so it stays visible on black.
// Both are trimmed to their visible pixels with a small margin.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 4 else { print("usage: logo-variants in grey hover [--key-white] [--key-hue=H,TOL]"); exit(1) }
let keyWhite = args.contains("--key-white")
var keyHue: (Double, Double)? = nil
if let k = args.first(where: { $0.hasPrefix("--key-hue=") }) {
  let p = k.dropFirst(10).split(separator: ",").compactMap { Double($0) }
  if p.count == 2 { keyHue = (p[0], p[1]) }
}

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { print("cannot read \(args[1])"); exit(1) }
let W = img.width, H = img.height
var px = [UInt8](repeating: 0, count: W * H * 4)
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))

func rgb(_ i: Int) -> (Double, Double, Double, Double) {
  let a = Double(px[i + 3]) / 255
  if a == 0 { return (0, 0, 0, 0) }
  return (Double(px[i]) / 255 / a, Double(px[i + 1]) / 255 / a, Double(px[i + 2]) / 255 / a, a)
}
func hue(_ r: Double, _ g: Double, _ b: Double) -> Double {
  let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
  if d < 1e-6 { return 0 }
  var h: Double
  if mx == r { h = (g - b) / d } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
  h *= 60; if h < 0 { h += 360 }
  return h
}

// Background knock-out: flood fill from the edges over background-coloured pixels.
if keyWhite || keyHue != nil {
  func isBg(_ i: Int) -> Bool {
    let (r, g, b, a) = rgb(i)
    if a < 0.05 { return true }
    let mx = max(r, g, b), mn = min(r, g, b)
    if keyWhite && mn > 0.9 && mx - mn < 0.08 { return true }
    if let (h, tol) = keyHue {
      let s = mx > 0 ? (mx - mn) / mx : 0
      var dh = abs(hue(r, g, b) - h); if dh > 180 { dh = 360 - dh }
      if s > 0.35 && mx > 0.55 && dh < tol { return true }
    }
    return false
  }
  var seen = [Bool](repeating: false, count: W * H)
  var stack: [Int] = []
  for x in 0..<W { stack.append(x); stack.append((H - 1) * W + x) }
  for y in 0..<H { stack.append(y * W); stack.append(y * W + W - 1) }
  while let p = stack.popLast() {
    if seen[p] { continue }
    seen[p] = true
    if !isBg(p * 4) { continue }
    px[p * 4] = 0; px[p * 4 + 1] = 0; px[p * 4 + 2] = 0; px[p * 4 + 3] = 0
    let x = p % W, y = p / W
    if x > 0 { stack.append(p - 1) }; if x < W - 1 { stack.append(p + 1) }
    if y > 0 { stack.append(p - W) }; if y < H - 1 { stack.append(p + W) }
  }
}

// Trim to visible pixels, 4% margin.
var minX = W, minY = H, maxX = -1, maxY = -1
for y in 0..<H { for x in 0..<W where px[(y * W + x) * 4 + 3] > 8 {
  minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
if maxX < 0 { print("nothing visible in \(args[1])"); exit(2) }
let m = Int(Double(max(maxX - minX, maxY - minY)) * 0.04)
minX = max(0, minX - m); minY = max(0, minY - m); maxX = min(W - 1, maxX + m); maxY = min(H - 1, maxY + m)
let cw = maxX - minX + 1, ch = maxY - minY + 1

func write(_ name: String, _ f: (Double, Double, Double, Double) -> (Double, Double, Double)) {
  var out = [UInt8](repeating: 0, count: cw * ch * 4)
  for y in 0..<ch { for x in 0..<cw {
    let i = ((y + minY) * W + (x + minX)) * 4, o = (y * cw + x) * 4
    let (r, g, b, a) = rgb(i)
    if a == 0 { continue }
    let (nr, ng, nb) = f(r, g, b, a)
    out[o] = UInt8(max(0, min(255, nr * a * 255))); out[o + 1] = UInt8(max(0, min(255, ng * a * 255)))
    out[o + 2] = UInt8(max(0, min(255, nb * a * 255))); out[o + 3] = UInt8(a * 255)
  } }
  let octx = CGContext(data: &out, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: cw * 4, space: cs,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(dest, octx.makeImage()!, nil)
  CGImageDestinationFinalize(dest)
}

func isInk(_ r: Double, _ g: Double, _ b: Double) -> Bool {
  let L = 0.2126 * r + 0.7152 * g + 0.0722 * b
  return L < 0.3 && (max(r, g, b) - min(r, g, b)) < 0.45
}
write(args[2]) { r, g, b, _ in
  if isInk(r, g, b) { return (0.80, 0.80, 0.80) }
  let L = 0.2126 * r + 0.7152 * g + 0.0722 * b
  let v = 0.45 + 0.5 * L
  return (v, v, v)
}
write(args[3]) { r, g, b, _ in isInk(r, g, b) ? (1, 1, 1) : (r, g, b) }
print("\(args[1]) -> \(cw)x\(ch)")
