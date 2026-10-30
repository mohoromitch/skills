// Rasterize each PDF page at a tablet screen size and report the leftmost and
// rightmost non-white pixel columns, i.e. the real side margins in device pixels.
//
// Usage: swift check-margins.swift <file.pdf> [min-px] [width height ppi]
//   min-px  exit 1 if any page has less ink-free space than this on either side
//           (default 130: the reMarkable toolbar is about 120 px wide)
//   width height ppi  screen size (default 1620 2160 229, the reMarkable Paper Pro)
import Foundation
import PDFKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 2, let doc = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
  print("usage: swift check-margins.swift <file.pdf> [min-px] [width height ppi]"); exit(2)
}
let minPx = args.count > 2 ? Int(args[2])! : 130
let W = args.count > 5 ? Int(args[3])! : 1620
let H = args.count > 5 ? Int(args[4])! : 2160
let ppi = args.count > 5 ? Double(args[5])! : 229
var minL = W, minR = W, bad = 0
for i in 0..<doc.pageCount {
  guard let page = doc.page(at: i) else { continue }
  let box = page.bounds(for: .mediaBox)
  let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
  ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
  ctx.scaleBy(x: CGFloat(W) / box.width, y: CGFloat(H) / box.height)
  page.draw(with: .mediaBox, to: ctx)
  let p = ctx.data!.bindMemory(to: UInt8.self, capacity: W * H * 4)
  var left = W, right = -1
  for y in 0..<H { for x in 0..<W {
    let o = (y * W + x) * 4
    if Int(p[o]) + Int(p[o+1]) + Int(p[o+2]) < 3 * 245 { left = min(left, x); right = max(right, x) }
  }}
  if right < 0 { continue }
  let r = W - 1 - right
  minL = min(minL, left); minR = min(minR, r)
  let flag = left < minPx || r < minPx
  if flag { bad += 1 }
  print(String(format: "page %3d  left %4d px  right %4d px%@", i + 1, left, r, flag ? "  TOO CLOSE" : ""))
}
print(String(format: "tightest: left %d px (%.1f mm), right %d px (%.1f mm); %d page(s) under %d px",
  minL, Double(minL) / ppi * 25.4, minR, Double(minR) / ppi * 25.4, bad, minPx))
exit(bad > 0 ? 1 : 0)
