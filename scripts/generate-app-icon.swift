#!/usr/bin/env swift
import AppKit
import WebKit

// Run from the project root: swift scripts/generate-app-icon.swift
// WebKit renders the canonical SVG. AppKit creates each icon representation.
final class IconGenerator: NSObject, WKNavigationDelegate {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let webView: WKWebView
    let window: NSWindow

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 1024),
                            configuration: configuration)
        window = NSWindow(contentRect: webView.frame, styleMask: .borderless,
                          backing: .buffered, defer: false)
        super.init()
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = webView
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
    }

    func start() throws {
        let source = root.appendingPathComponent("assets/brand/agent-monitor.svg")
        let svg = try String(contentsOf: source, encoding: .utf8)
        webView.loadHTMLString("""
        <!doctype html><html><head><meta name="viewport" content="width=1024">
        <style>html,body{margin:0;width:1024px;height:1024px;background:transparent;overflow:hidden}
        svg{display:block;width:1024px;height:1024px}</style></head><body>\(svg)</body></html>
        """, baseURL: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            self.fail(NSError(domain: "IconGenerator", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "SVG rendering exceeds 30 seconds."]))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = NSRect(x: 0, y: 0, width: 1024, height: 1024)
        configuration.snapshotWidth = 1024
        webView.takeSnapshot(with: configuration) { image, error in
            do {
                if let error { throw error }
                guard let image else { throw CocoaError(.fileReadCorruptFile) }
                try self.write(image)
                NSApp.terminate(nil)
            } catch { self.fail(error) }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        fail(error)
    }

    func write(_ source: NSImage) throws {
        let manager = FileManager.default
        let temporary = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let iconset = temporary.appendingPathComponent("AppIcon.iconset")
        try manager.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: temporary) }

        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let size = points * scale
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size,
                    pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                bitmap.size = NSSize(width: size, height: size)
                NSGraphicsContext.saveGraphicsState()
                let context = NSGraphicsContext(bitmapImageRep: bitmap)!
                NSGraphicsContext.current = context
                context.imageInterpolation = .high
                source.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                            from: .zero, operation: .copy, fraction: 1)
                context.flushGraphics()
                NSGraphicsContext.restoreGraphicsState()
                guard bitmap.colorAt(x: 0, y: 0)!.alphaComponent == 0,
                      bitmap.colorAt(x: size - 1, y: size - 1)!.alphaComponent == 0,
                      bitmap.colorAt(x: size / 2, y: size / 2)!.alphaComponent > 0.99 else {
                    throw NSError(domain: "IconGenerator", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Icon transparency validation fails."])
                }
                guard let data = bitmap.representation(using: .png, properties: [:]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let suffix = scale == 2 ? "@2x" : ""
                try data.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
                if size == 1024 {
                    try data.write(to: root.appendingPathComponent("assets/brand/agent-monitor-preview.png"))
                }
                print("Rendered \(points) pt @\(scale)x: \(size) × \(size), RGBA")
            }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", "-o",
            root.appendingPathComponent("assets/AppIcon.icns").path, iconset.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        print("Created assets/AppIcon.icns from assets/brand/agent-monitor.svg")
    }

    func fail(_ error: Error) -> Never {
        FileHandle.standardError.write(Data("Icon generation failed: \(error)\n".utf8))
        exit(1)
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
let generator = IconGenerator()
do { try generator.start() } catch { generator.fail(error) }
application.run()
