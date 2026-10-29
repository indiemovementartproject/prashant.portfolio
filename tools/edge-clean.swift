// edge-clean: finish a person cut-out so it sits cleanly on a dark page.
//
//   swift tools/edge-clean.swift <original> <full-frame-cutout.png> <out.png>
//        [--floor=Y] [--flip] [--fade=0.3] [--choke=N]
//
// Unlike defringe.swift (one flat background colour), the background here varies across the
// frame, so each soft edge pixel is cleaned against the background right next to it:
//   1. B = average of nearby pixels the mask marks as background in the original photo.
//   2. Colour decontamination: F = (P - (1 - a) * B) / a, so no rim of the old backdrop survives.
//   3. A slight alpha tightening for a crisp but smooth edge.
// --floor=Y  drops everything from row Y down (a floor reflection, for example).
// --flip     mirrors the result horizontally.
// --fade=F   fades the bottom F of the subject's height into transparency.
// --choke=N  pulls the edge in by N pixels first. Avoid on faces: it shaves a profile.
// --bleed=N  instead of decontaminating, the outer N pixels of the edge take the colour of
//            the subject just inside them, so no rim of any colour survives and the outline stays put.
// The output is trimmed to the subject, with a small transparent margin.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
guard a.count >= 4 else { print("usage: edge-clean original cutout out [--floor=Y] [--flip] [--fade=F]"); exit(1) }
func opt(_ k: String) -> Double? { a.first(where: { $0.hasPrefix("--\(k)=") }).flatMap { Double($0.split(separator: "=")[1]) } }
let floorY = opt("floor").map { Int($0) }, fade = opt("fade") ?? 0, flip = a.contains("--flip"), choke = Int(opt("choke") ?? 0), bleed = Int(opt("bleed") ?? 0)

func load(_ p: String) -> ([UInt8], Int, Int) {
  let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil)!, img = CGImageSourceCreateImageAtIndex(s, 0, nil)!
  let w = img.width, h = img.height
  var px = [UInt8](repeating: 0, count: w * h * 4)
  CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
  return (px, w, h)
}
let (op, W, H) = load(a[1])
let (cp, cw, ch) = load(a[2])
guard cw == W && ch == H else { print("cutout must be full frame (\(cw)x\(ch) vs \(W)x\(H)); use cutout.swift --full"); exit(1) }

var alpha = (0..<(W * H)).map { Double(cp[$0 * 4 + 3]) / 255 }
if let fy = floorY { for y in max(0, fy)..<H { for x in 0..<W { alpha[y * W + x] = 0 } } }
func orig(_ i: Int, _ k: Int) -> Double { Double(op[i * 4 + k]) / 255 }
// Choke: each pixel takes the lowest alpha within N pixels (a separable min filter).
if choke > 0 {
  var tmp = alpha
  for y in 0..<H { for x in 0..<W {
    var m = 1.0
    for dx in -choke...choke { let nx = x + dx; if nx >= 0 && nx < W { m = min(m, alpha[y * W + nx]) } else { m = 0 } }
    tmp[y * W + x] = m } }
  for y in 0..<H { for x in 0..<W {
    var m = 1.0
    for dy in -choke...choke { let ny = y + dy; if ny >= 0 && ny < H { m = min(m, tmp[ny * W + x]) } else { m = 0 } }
    alpha[y * W + x] = m } }
  // Soften the new edge by one pixel so it stays smooth.
  tmp = alpha
  for y in 1..<(H - 1) { for x in 1..<(W - 1) {
    var s = 0.0
    for dy in -1...1 { for dx in -1...1 { s += tmp[(y + dy) * W + x + dx] } }
    alpha[y * W + x] = s / 9 } }
}

// Background estimate for edge pixels: mean of clear-background pixels within a growing radius.
var rgb = [Double](repeating: 0, count: W * H * 3)
for y in 0..<H { for x in 0..<W {
  let i = y * W + x, al = alpha[i]
  if al <= 0.004 { continue }
  var P = [orig(i, 0), orig(i, 1), orig(i, 2)]
  if al < 0.995 && bleed == 0 {
    var B = [0.0, 0.0, 0.0], n = 0.0
    var r = 3
    while n < 6 && r <= 24 {
      B = [0, 0, 0]; n = 0
      for dy in stride(from: -r, through: r, by: 1) { for dx in stride(from: -r, through: r, by: 1) {
        let nx = x + dx, ny = y + dy
        if nx < 0 || ny < 0 || nx >= W || ny >= H { continue }
        let j = ny * W + nx
        if Double(cp[j * 4 + 3]) / 255 < 0.02 { for k in 0..<3 { B[k] += orig(j, k) }; n += 1 }
      } }
      r *= 2
    }
    if n > 0 { B = B.map { $0 / n }; P = (0..<3).map { max(0, min(1, (P[$0] - (1 - al) * B[$0]) / al)) } }
  }
  for k in 0..<3 { rgb[i * 3 + k] = P[k] }
  // Tighten the outermost part of the soft edge a little.
  let t = max(0, min(1, (al - 0.12) / 0.8)); alpha[i] = t * t * (3 - 2 * t)
} }

// Bleed: multi-source flood outward from the solid interior, carrying colour to the edge band.
if bleed > 0 {
  var inner = [Bool](repeating: false, count: W * H)
  for i in 0..<(W * H) { inner[i] = alpha[i] >= 0.98 }
  // Erode the solid region by N so its border pixels are free of backdrop light.
  for _ in 0..<bleed {
    var next = inner
    for y in 1..<(H - 1) { for x in 1..<(W - 1) where inner[y * W + x] {
      let i = y * W + x
      if !inner[i - 1] || !inner[i + 1] || !inner[i - W] || !inner[i + W] { next[i] = false } } }
    inner = next
  }
  var queue: [Int] = [], head = 0, done = inner
  for i in 0..<(W * H) where inner[i] { queue.append(i) }
  while head < queue.count {
    let i = queue[head]; head += 1
    let x = i % W, y = i / W
    for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
      if nx < 0 || ny < 0 || nx >= W || ny >= H { continue }
      let j = ny * W + nx
      if done[j] || alpha[j] <= 0.004 { continue }
      done[j] = true
      for k in 0..<3 { rgb[j * 3 + k] = rgb[i * 3 + k] }
      queue.append(j)
    }
  }
}

// Trim to the subject.
var minX = W, minY = H, maxX = -1, maxY = -1
for y in 0..<H { for x in 0..<W where alpha[y * W + x] > 0.004 {
  minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
// Keep a transparent margin so the faintest edge pixels (hair tips) are never sliced by the frame.
let mg = max(8, (maxY - minY) / 40)
minX = max(0, minX - mg); minY = max(0, minY - mg); maxX = min(W - 1, maxX + mg); maxY = min(H - 1, maxY + mg)
let ow = maxX - minX + 1, oh = maxY - minY + 1
var out = [UInt8](repeating: 0, count: ow * oh * 4)
for y in 0..<oh { for x in 0..<ow {
  let sx = flip ? (maxX - x) : (minX + x), i = (minY + y) * W + sx
  var al = alpha[i]
  if fade > 0 {
    let f = Double(y) / Double(oh), start = 1 - fade
    if f > start { let t = 1 - (f - start) / fade; al *= t * t * (3 - 2 * t) }
  }
  let o = (y * ow + x) * 4
  for k in 0..<3 { out[o + k] = UInt8(max(0, min(255, rgb[i * 3 + k] * al * 255))) }
  out[o + 3] = UInt8(al * 255)
} }
let ctx = CGContext(data: &out, width: ow, height: oh, bitsPerComponent: 8, bytesPerRow: ow * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[3]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(d, ctx.makeImage()!, nil)
CGImageDestinationFinalize(d)
print("\(a[3]) \(ow)x\(oh)")
