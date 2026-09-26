// sjev-helper: 画面Jev用の小さなSwiftヘルパー。
// front  -> 最前面アプリ/ウィンドウ情報をJSONで出力
// ocr <png> -> Vision(VNRecognizeTextRequest)でPNG内の文字を上から順のテキストで出力
//
// 意図的な簡略化: 複数ウィンドウを持つアプリの「どのウィンドウが最前面か」は
// CGWindowListCopyWindowInfo の kCGWindowLayer==0 かつ最前(配列先頭)のものを採用する簡易判定。
// 本格的に取りたい場合は Accessibility API (AXUIElement) でフォーカスウィンドウを直接問い合わせるのが入口。
import AppKit
import Vision
import Foundation

func jsonPrint(_ obj: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
       let s = String(data: data, encoding: .utf8) {
        print(s)
    } else {
        print("{}")
    }
}

func cmdFront() {
    let ws = NSWorkspace.shared
    guard let app = ws.frontmostApplication else {
        jsonPrint(["error": "no_frontmost_app"])
        return
    }
    let appName = app.localizedName ?? ""
    let bundleId = app.bundleIdentifier ?? ""
    let pid = app.processIdentifier

    var windowId: Int = -1
    var title = ""
    var x: Double = 0, y: Double = 0, w: Double = 0, h: Double = 0

    let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
    if let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
        for win in list {
            guard let ownerPID = win[kCGWindowOwnerPID as String] as? Int32, ownerPID == pid else { continue }
            guard let layer = win[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            windowId = win[kCGWindowNumber as String] as? Int ?? -1
            title = win[kCGWindowName as String] as? String ?? ""
            if let bounds = win[kCGWindowBounds as String] as? [String: Any] {
                x = bounds["X"] as? Double ?? 0
                y = bounds["Y"] as? Double ?? 0
                w = bounds["Width"] as? Double ?? 0
                h = bounds["Height"] as? Double ?? 0
            }
            break
        }
    }

    jsonPrint([
        "app": appName,
        "bundle": bundleId,
        "pid": Int(pid),
        "window_id": windowId,
        "title": title,
        "x": x, "y": y, "w": w, "h": h
    ])
}

func cmdDisplays() {
    var count: UInt32 = 0
    let result = CGGetActiveDisplayList(0, nil, &count)
    if result != .success {
        jsonPrint(["count": 1])
        return
    }
    jsonPrint(["count": Int(count)])
}

func cmdOcr(_ path: String) {
    guard let img = NSImage(contentsOfFile: path),
          let cgImage = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        jsonPrint(["error": "cannot_load_image", "lines": []])
        return
    }
    var lines: [String] = []
    let request = VNRecognizeTextRequest { req, err in
        guard err == nil, let observations = req.results as? [VNRecognizedTextObservation] else { return }
        // 上から順(Y降順=画面上ほど大きい値)に並べて行として出す
        let sorted = observations.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
        for obs in sorted {
            if let top = obs.topCandidates(1).first {
                lines.append(top.string)
            }
        }
    }
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ja-JP", "en-US"]
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
        try handler.perform([request])
    } catch {
        jsonPrint(["error": "vision_failed", "lines": []])
        return
    }
    jsonPrint(["lines": lines])
}

let args = CommandLine.arguments
if args.count < 2 {
    jsonPrint(["error": "usage: sjev-helper front|ocr <png>|displays"])
    exit(1)
}

switch args[1] {
case "front":
    cmdFront()
case "displays":
    cmdDisplays()
case "ocr":
    if args.count < 3 {
        jsonPrint(["error": "ocr requires a png path"])
        exit(1)
    }
    cmdOcr(args[2])
default:
    jsonPrint(["error": "unknown command"])
    exit(1)
}
