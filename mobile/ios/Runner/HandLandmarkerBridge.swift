import Flutter
import Foundation
import Vision

/// Native bridge exposing on-device hand landmarks to Flutter over a
/// MethodChannel. The `hand_landmarker` pub package is Android-only, so on iOS
/// the Dart finger-guidance controller feeds camera frames here and receives
/// back the 21 hand landmarks (same data the Android MediaPipe plugin returns).
///
/// iOS uses Apple's built-in Vision framework (`VNDetectHumanHandPoseRequest`)
/// rather than MediaPipe: it ships the model in the OS (no pod, no bundled
/// `.task` asset), is hardware-optimized, and uses a live-stream tracker under
/// the hood. Vision's 21 joints map 1:1 onto MediaPipe's landmark order, so the
/// wire contract below is unchanged and the shared Dart gating + overlay math
/// (and the Android path) work untouched.
///
/// Channel: `bih/hand_landmarker`
///   detect(bytes, width, height, bytesPerRow) -> [Double]
///     A flat list of 42 doubles (x0,y0, x1,y1, … x20,y20), each normalized
///     0–1 in the *unrotated sensor frame*, top-left origin — matching the
///     Android plugin so the shared Dart gating + overlay math works unchanged.
///     Empty list = no hand (or Vision unavailable on iOS 13).
final class HandLandmarkerBridge {
  static let channelName = "bih/hand_landmarker"

  // Detection runs off the platform thread; Dart back-pressures (it awaits each
  // call before sending the next frame), so a serial queue never queues up.
  private let workQueue = DispatchQueue(label: "bih.hand_landmarker.detect")

  // Lazily built so it lives on iOS 14+ only; nil on iOS 13 → Dart falls back
  // to the sharpness-only capture gate.
  private var _request: Any?

  @available(iOS 14.0, *)
  private func request() -> VNDetectHumanHandPoseRequest {
    if let existing = _request as? VNDetectHumanHandPoseRequest { return existing }
    let req = VNDetectHumanHandPoseRequest()
    req.maximumHandCount = 1
    _request = req
    return req
  }

  /// MediaPipe's 21-landmark order, expressed as Vision joint names. Feeding the
  /// joints back in this exact order is what preserves the Android contract.
  @available(iOS 14.0, *)
  private static var jointOrder: [VNHumanHandPoseObservation.JointName] {
    [
      .wrist,
      .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
      .indexMCP, .indexPIP, .indexDIP, .indexTip,
      .middleMCP, .middlePIP, .middleDIP, .middleTip,
      .ringMCP, .ringPIP, .ringDIP, .ringTip,
      .littleMCP, .littlePIP, .littleDIP, .littleTip,
    ]
  }

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    let bridge = HandLandmarkerBridge()
    channel.setMethodCallHandler { call, result in
      bridge.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "detect":
      handleDetect(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleDetect(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let data = args["bytes"] as? FlutterStandardTypedData,
      let width = args["width"] as? Int,
      let height = args["height"] as? Int,
      let bytesPerRow = args["bytesPerRow"] as? Int
    else {
      result(FlutterError(code: "bad_args", message: "detect requires bytes/width/height/bytesPerRow", details: nil))
      return
    }

    guard #available(iOS 14.0, *) else {
      // Vision hand pose is iOS 14+. Tell Dart once so it drops to the
      // sharpness-only gate instead of hammering the channel.
      result(FlutterError(code: "init_failed", message: "VNDetectHumanHandPoseRequest requires iOS 14", details: nil))
      return
    }

    let bytes = data.data
    workQueue.async { [weak self] in
      guard let self = self else { return }
      let landmarks = self.detect(
        bgra: bytes,
        width: width,
        height: height,
        bytesPerRow: bytesPerRow
      )
      DispatchQueue.main.async { result(landmarks) }
    }
  }

  /// Wrap the BGRA bytes in a CVPixelBuffer, run Vision hand-pose detection, and
  /// flatten the first hand's 21 joints to [x0,y0,…] in MediaPipe order. Returns
  /// [] on any failure or if the full 21-point skeleton isn't recovered.
  @available(iOS 14.0, *)
  private func detect(bgra: Data, width: Int, height: Int, bytesPerRow: Int) -> [Double] {
    guard let pixelBuffer = makePixelBuffer(bgra: bgra, width: width, height: height, srcBytesPerRow: bytesPerRow) else {
      return []
    }

    // `.up` keeps results in the raw (unrotated) sensor frame; the Dart overlay
    // applies the sensorOrientation rotation, exactly as with the Android path.
    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
    let req = request()
    do {
      try handler.perform([req])
      guard let hand = req.results?.first else { return [] }
      let points = try hand.recognizedPoints(.all)

      var flat = [Double]()
      flat.reserveCapacity(42)
      for joint in Self.jointOrder {
        guard let p = points[joint] else { return [] } // incomplete skeleton → no hand
        // Vision: normalized, bottom-left origin. Contract wants top-left → flip y.
        flat.append(Double(p.location.x))
        flat.append(Double(1.0 - p.location.y))
      }
      return flat
    } catch {
      return []
    }
  }

  private func makePixelBuffer(bgra: Data, width: Int, height: Int, srcBytesPerRow: Int) -> CVPixelBuffer? {
    var pixelBuffer: CVPixelBuffer?
    let attrs: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
      attrs as CFDictionary, &pixelBuffer
    )
    guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

    guard let dest = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let dstBytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    let copyBytesPerRow = min(srcBytesPerRow, dstBytesPerRow)

    bgra.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
      guard let srcBase = src.baseAddress else { return }
      for row in 0..<height {
        let srcRow = srcBase.advanced(by: row * srcBytesPerRow)
        let dstRow = dest.advanced(by: row * dstBytesPerRow)
        memcpy(dstRow, srcRow, copyBytesPerRow)
      }
    }
    return buffer
  }
}
