import AppKit
import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

guard CommandLine.arguments.count == 3 else {
  fatalError("Usage: swift generate_chat_demo_video.swift <image> <output.mp4>")
}

let imageURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let image = NSImage(contentsOf: imageURL),
      let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
  fatalError("Unable to decode source image")
}

try? FileManager.default.removeItem(at: outputURL)
let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
let width = 640
let height = 360
let settings: [String: Any] = [
  AVVideoCodecKey: AVVideoCodecType.h264,
  AVVideoWidthKey: width,
  AVVideoHeightKey: height,
  AVVideoCompressionPropertiesKey: [
    AVVideoAverageBitRateKey: 1_200_000,
    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
  ],
]
let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
  assetWriterInput: input,
  sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
  ]
)
guard writer.canAdd(input) else { fatalError("Unable to add video input") }
writer.add(input)
guard writer.startWriting() else { fatalError(writer.error?.localizedDescription ?? "Unable to start writer") }
writer.startSession(atSourceTime: .zero)

let frameRate: Int32 = 30
let frameCount = Int(frameRate) * 8
for frame in 0..<frameCount {
  while !input.isReadyForMoreMediaData {
    Thread.sleep(forTimeInterval: 0.003)
  }
  var buffer: CVPixelBuffer?
  guard let pool = adaptor.pixelBufferPool,
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
        let pixelBuffer = buffer
  else { fatalError("Unable to allocate video frame") }

  CVPixelBufferLockBaseAddress(pixelBuffer, [])
  defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
  guard let base = CVPixelBufferGetBaseAddress(pixelBuffer),
        let context = CGContext(
          data: base,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        )
  else { fatalError("Unable to create video frame context") }

  context.setFillColor(CGColor(gray: 0.08, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  let progress = CGFloat(frame) / CGFloat(max(frameCount - 1, 1))
  let zoom = 1.02 + progress * 0.05
  let sourceRatio = CGFloat(source.width) / CGFloat(source.height)
  let targetRatio = CGFloat(width) / CGFloat(height)
  var drawWidth: CGFloat
  var drawHeight: CGFloat
  if sourceRatio > targetRatio {
    drawHeight = CGFloat(height) * zoom
    drawWidth = drawHeight * sourceRatio
  } else {
    drawWidth = CGFloat(width) * zoom
    drawHeight = drawWidth / sourceRatio
  }
  let pan = (progress - 0.5) * 24
  context.draw(
    source,
    in: CGRect(
      x: (CGFloat(width) - drawWidth) / 2 - pan,
      y: (CGFloat(height) - drawHeight) / 2,
      width: drawWidth,
      height: drawHeight
    )
  )
  let time = CMTime(value: CMTimeValue(frame), timescale: frameRate)
  guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
    fatalError(writer.error?.localizedDescription ?? "Unable to append video frame")
  }
}

input.markAsFinished()
await writer.finishWriting()
guard writer.status == .completed else {
  fatalError(writer.error?.localizedDescription ?? "Unable to finish video")
}
