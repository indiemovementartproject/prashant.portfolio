// logo-soft: cut a logo off a flat background with soft, anti-aliased edges, and write the two
// PNGs the site uses on its dark background.
//
//   swift tools/logo-soft.swift <in> <out-grey.png> <out-hover.png> [--keep-alpha] [--lo=0.08] [--hi=0.25] [--whiten=L] [--dark=tint|white|keep]
//
// Background colour is the average of the four image corners. Each pixel's alpha comes from how far
// its colour sits from that background (between --lo and --hi), and the background share is taken
// back out of edge pixels so no pale rim survives. --keep-alpha skips keying for logos that already
// have a transparent background. --whiten=L turns every colour lighter than luminance L pure white
// in the hover version (cleans the tinted rim a low-res source leaves on white shapes).
// --dark picks what dark coloured ink does on hover: tint (default, a light tint of its hue),
// white (navy wordmarks), or keep (strong reds and the like that already read on black). The result is trimmed tight to the visible pixels.
//
// grey  : a light grey for the default state; neutral dark ink becomes a light grey.
// hover : original colours; neutral dark ink (black, charcoal) turns white, and dark coloured ink
//         (navy, brown) is lifted to a light tint of its own hue so it reads on black.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 4 else { print("usage: logo-soft in grey hover [--keep-alpha] [--lo=] [--hi=]"); exit(1) }
func opt(_ k: String, _ d: Double) -> Double {
  args.first(where: { $0.hasPrefix("--\(k)=") }).flatMap { Double($0.split(separator: "=")[1]) } ?? d
}
let keepAlpha = args.contains("--keep-alpha"), lo = opt("lo", 0.08), hi = opt("hi", 0.25), whiten = opt("whiten", 2)
let darkMode = args.first(where: { $0.hasPrefix("--dark=") }).map { String($0.dropFirst(7)) } ?? "tint"

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { print("cannot read \(args[1])"); exit(1) }
let W = img.width, H = img.height
let cs = CGColorSpaceCreateDeviceRGB()
var px = [UInt8](repeating: 0, count: W * H * 4)
CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: cs,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))

// Straight (unpremultiplied) float RGBA.
var f = [Double](repeating: 0, count: W * H * 4)
for i in 0..<(W * H) {
  let a = Double(px[i * 4 + 3]) / 255
  f[i * 4 + 3] = a
  if a > 0 { for k in 0..<3 { f[i * 4 + k] = Double(px[i * 4 + k]) / 255 / a } }
}

if !keepAlpha {
  var B = [0.0, 0.0, 0.0], n = 0.0
  let c = max(2, min(W, H) / 40)
  for (cx, cy) in [(0, 0), (W - c, 0), (0, H - c), (W - c, H - c)] {
    for y in cy..<(cy + c) { for x in cx..<(cx + c) { for k in 0..<3 { B[k] += f[(y * W + x) * 4 + k] }; n += 1 } }
  }
  B = B.map { $0 / n }
  print(String(format: "background %.2f %.2f %.2f", B[0], B[1], B[2]))
  for i in 0..<(W * H) {
    let o = i * 4
    let d = (0..<3).map { abs(f[o + $0] - B[$0]) }.max()!
    let t = max(0, min(1, (d - lo) / (hi - lo)))
    let a = t * t * (3 - 2 * t)
    if a < 1 && a > 0 {
      // How much background is mixed in, judged on the channel that moves furthest from it.
      for k in 0..<3 { f[o + k] = max(0, min(1, (f[o + k] - (1 - a) * B[k]) / a)) }
    }
    f[o + 3] *= a
  }
}

// Trim to visible pixels, with a hair of margin so anti-aliasing is not clipped.
var minX = W, minY = H, maxX = -1, maxY = -1
for y in 0..<H { for x in 0..<W where f[(y * W + x) * 4 + 3] > 0.04 {
  minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
if maxX < 0 { print("nothing visible in \(args[1])"); exit(2) }
let m = 2
minX = max(0, minX - m); minY = max(0, minY - m); maxX = min(W - 1, maxX + m); maxY = min(H - 1, maxY + m)
let cw = maxX - minX + 1, ch = maxY - minY + 1

func write(_ name: String, _ map: (Double, Double, Double) -> (Double, Double, Double)) {
  var out = [UInt8](repeating: 0, count: cw * ch * 4)
  for y in 0..<ch { for x in 0..<cw {
    let i = ((y + minY) * W + (x + minX)) * 4, o = (y * cw + x) * 4
    let a = f[i + 3]
    if a <= 0.004 { continue }
    let (r, g, b) = map(f[i], f[i + 1], f[i + 2])
    out[o] = UInt8(max(0, min(255, r * a * 255))); out[o + 1] = UInt8(max(0, min(255, g * a * 255)))
    out[o + 2] = UInt8(max(0, min(255, b * a * 255))); out[o + 3] = UInt8(a * 255)
  } }
  let ctx = CGContext(data: &out, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: cw * 4, space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
  CGImageDestinationFinalize(dest)
}

func lum(_ r: Double, _ g: Double, _ b: Double) -> Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
// 0 for light colours, rising to 1 as a colour gets dark enough to vanish on black.
func darkness(_ r: Double, _ g: Double, _ b: Double) -> Double { max(0, min(1, (0.42 - lum(r, g, b)) / 0.18)) }
func chroma(_ r: Double, _ g: Double, _ b: Double) -> Double { max(r, g, b) - min(r, g, b) }

write(args[2]) { r, g, b in
  let v = 0.45 + 0.5 * lum(r, g, b), d = darkness(r, g, b)
  let w = v * (1 - d) + 0.80 * d
  return (w, w, w)
}
write(args[3]) { r, g, b in
  if lum(r, g, b) > whiten { return (1, 1, 1) }
  if darkMode == "white" && lum(r, g, b) < 0.5 { return (1, 1, 1) }
  let d = darkness(r, g, b)
  if d == 0 { return (r, g, b) }
  // Neutral ink goes white; coloured ink keeps its hue as a light tint.
  var neutral = max(0, min(1, (0.26 - chroma(r, g, b)) / 0.08))
  if darkMode == "white" { neutral = 1 } else if darkMode == "keep" && neutral < 1 { return (r, g, b) }
  let mx = max(r, g, b, 0.001)
  let tint = [r, g, b].map { 0.62 + 0.38 * $0 / mx }
  let lift = [0, 1, 2].map { k in tint[k] * (1 - neutral) + 1 * neutral }
  return (r * (1 - d) + lift[0] * d, g * (1 - d) + lift[1] * d, b * (1 - d) + lift[2] * d)
}
print("\(args[1]) -> \(cw)x\(ch)")
