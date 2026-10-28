// cutout: lift the foreground subject (person plus anything they hold) out of a photo
// with Apple's on-device Vision subject mask, and save a trimmed transparent PNG.
//   swift tools/cutout.swift <in.jpg> <out.png>
import Foundation
import Vision
import CoreImage
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
guard a.count == 3, let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { print("usage: cutout in out"); exit(1) }
let req = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(cgImage: img, options: [:])
try handler.perform([req])
guard let obs = req.results?.first else { print("no subject found"); exit(2) }
let buf = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: true)
let ci = CIImage(cvPixelBuffer: buf)
let cg = CIContext().createCGImage(ci, from: ci.extent)!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, cg, nil)
CGImageDestinationFinalize(dest)
print("\(a[2]) \(cg.width)x\(cg.height), instances \(obs.allInstances.count)")
