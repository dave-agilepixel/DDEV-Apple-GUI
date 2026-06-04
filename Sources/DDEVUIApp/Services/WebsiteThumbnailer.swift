import Foundation
#if canImport(WebKit)
import WebKit
import AppKit
#endif

public protocol WebsiteThumbnailing: Sendable {
    /// Renders `url` off-screen and returns a downscaled PNG, or nil on failure/timeout.
    func capture(url: URL) async -> Data?
}

/// Test/preview double. Returns a queued response per absolute URL (absent → nil) and records calls.
public final class StubWebsiteThumbnailer: WebsiteThumbnailing, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: Data]
    private var recorded: [URL] = []

    public init(responses: [String: Data] = [:]) { self.responses = responses }

    public var capturedURLs: [URL] { lock.withLock { recorded } }

    public func capture(url: URL) async -> Data? {
        lock.withLock {
            recorded.append(url)
            return responses[url.absoluteString]
        }
    }
}

#if canImport(WebKit)
/// Captures a homepage screenshot via an off-screen `WKWebView`.
@MainActor
public final class WebKitWebsiteThumbnailer: NSObject, WebsiteThumbnailing {
    private let viewport: CGSize
    private let targetWidth: CGFloat
    private let settle: Duration
    private let timeout: Duration

    public init(
        viewport: CGSize = CGSize(width: 1200, height: 900),
        targetWidth: CGFloat = 640,
        settle: Duration = .milliseconds(750),
        timeout: Duration = .seconds(12)
    ) {
        self.viewport = viewport
        self.targetWidth = targetWidth
        self.settle = settle
        self.timeout = timeout
    }

    public func capture(url: URL) async -> Data? {
        let webView = WKWebView(frame: CGRect(origin: .zero, size: viewport))
        let coordinator = LoadCoordinator(host: url.host(percentEncoded: false))
        webView.navigationDelegate = coordinator

        // The window is never shown on-screen; it exists only to give the web view a backing
        // layer tree so the page actually lays out and paints for the snapshot.
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: viewport),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.contentView?.addSubview(webView)

        defer {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.removeFromSuperview()
            window.close()
        }

        webView.load(URLRequest(url: url))

        let loaded = await coordinator.waitForLoad(timeout: timeout)
        guard loaded else { return nil }

        try? await Task.sleep(for: settle)

        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: viewport)   // top viewport only
        let image: NSImage? = await withCheckedContinuation { continuation in
            webView.takeSnapshot(with: config) { image, _ in
                continuation.resume(returning: image)
            }
        }
        guard let image else { return nil }
        return Self.downscaledPNG(image, targetWidth: targetWidth)
    }

    /// Downscale to `targetWidth` (keeping aspect) and encode PNG.
    private static func downscaledPNG(_ image: NSImage, targetWidth: CGFloat) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let source = NSBitmapImageRep(data: tiff),
              source.pixelsWide > 0 else { return nil }

        // targetWidth is measured in physical pixels of the snapshot bitmap. On a Retina display
        // that is ~2× the logical point width — intentional and fine for a thumbnail indicator.
        let scale = targetWidth / CGFloat(source.pixelsWide)
        let size = NSSize(width: targetWidth, height: CGFloat(source.pixelsHigh) * scale)

        let target = NSImage(size: size)
        target.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        target.unlockFocus()

        guard let outTiff = target.tiffRepresentation,
              let rep = NSBitmapImageRep(data: outTiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// Bridges `WKNavigationDelegate` callbacks to a single awaitable `waitForLoad`.
@MainActor
private final class LoadCoordinator: NSObject, WKNavigationDelegate {
    private let host: String?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var settled = false
    private var timeoutTask: Task<Void, Never>?

    init(host: String?) { self.host = host }

    func waitForLoad(timeout: Duration) async -> Bool {
        // Race the delegate continuation against a timeout task.
        // The timeout task calls finish(false) after sleeping; the delegate callbacks call
        // finish(true/false) on navigation events. finish() is guarded by `settled` so
        // the continuation is resumed exactly once regardless of ordering.
        let result = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            self.continuation = c
            self.timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finish(false)
            }
        }
        timeoutTask?.cancel()
        timeoutTask = nil
        return result
    }

    private func finish(_ success: Bool) {
        guard !settled else { return }
        settled = true
        continuation?.resume(returning: success)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(true) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(false) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(false) }

    /// Trust the server cert ONLY for the exact host being captured, and ONLY when it is a
    /// `.ddev.site` host (mkcert-signed local CA). Everything else gets default handling.
    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let host,
              challenge.protectionSpace.host == host,
              host.hasSuffix(".ddev.site") else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
#else
public typealias WebKitWebsiteThumbnailer = StubWebsiteThumbnailer
#endif
