import SwiftUI
import WebKit

struct CardWebView: UIViewRepresentable, Equatable {
    let html: String
    let contentTrust: CardContentTrust
    let isScrollEnabled: Bool
    var snapshotRequestID: UUID? = nil
    var onSnapshot: ((UUID, UIImage?) -> Void)? = nil

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.html == rhs.html
            && lhs.contentTrust == rhs.contentTrust
            && lhs.isScrollEnabled == rhs.isScrollEnabled
            && lhs.snapshotRequestID == rhs.snapshotRequestID
            && (lhs.onSnapshot == nil) == (rhs.onSnapshot == nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(contentTrust: contentTrust, onSnapshot: onSnapshot)
    }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(
            frame: .zero,
            configuration: Self.makeConfiguration(contentTrust: contentTrust)
        )
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.scrollView.isDirectionalLockEnabled = true
        view.scrollView.isScrollEnabled = isScrollEnabled
        view.scrollView.alwaysBounceHorizontal = false
        view.scrollView.showsHorizontalScrollIndicator = false
        load(html, in: view)
        if let snapshotRequestID {
            context.coordinator.requestSnapshot(snapshotRequestID, from: view)
        }
        return view
    }

    static func makeConfiguration(contentTrust: CardContentTrust) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = contentTrust.allowsJavaScript
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        return configuration
    }

    static func canOpenExternally(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto", "tel", "facetime", "facetime-audio", "sms"]
            .contains(scheme)
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        if view.scrollView.isScrollEnabled != isScrollEnabled {
            view.scrollView.isScrollEnabled = isScrollEnabled
        }
        context.coordinator.onSnapshot = onSnapshot
        if context.coordinator.loadedHTML != html {
            load(html, in: view)
        }
        if let snapshotRequestID {
            context.coordinator.requestSnapshot(snapshotRequestID, from: view)
        }
    }

    private func load(_ html: String, in view: WKWebView) {
        let document = CardHTMLDocument.make(from: html, contentTrust: contentTrust)
        (view.navigationDelegate as? Coordinator)?.loadedHTML = html
        view.loadHTMLString(document, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?
        var onSnapshot: ((UUID, UIImage?) -> Void)?
        private let contentTrust: CardContentTrust
        private var completedSnapshotRequestID: UUID?
        private var pendingSnapshotRequestID: UUID?

        init(
            contentTrust: CardContentTrust,
            onSnapshot: ((UUID, UIImage?) -> Void)?
        ) {
            self.contentTrust = contentTrust
            self.onSnapshot = onSnapshot
        }

        func requestSnapshot(_ requestID: UUID, from webView: WKWebView) {
            guard requestID != completedSnapshotRequestID,
                  requestID != pendingSnapshotRequestID
            else { return }

            pendingSnapshotRequestID = requestID
            guard !webView.isLoading else { return }
            takeSnapshot(requestID, from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            guard let requestID = pendingSnapshotRequestID else { return }
            takeSnapshot(requestID, from: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation?,
            withError error: any Error
        ) {
            finishPendingSnapshot(with: nil)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation?,
            withError error: any Error
        ) {
            finishPendingSnapshot(with: nil)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            finishPendingSnapshot(with: nil)
        }

        private func takeSnapshot(_ requestID: UUID, from webView: WKWebView) {
            guard pendingSnapshotRequestID == requestID else { return }

            let configuration = WKSnapshotConfiguration()
            configuration.rect = webView.bounds
            configuration.afterScreenUpdates = true
            webView.takeSnapshot(with: configuration) { [weak self] image, _ in
                guard let self, self.pendingSnapshotRequestID == requestID else { return }
                self.finishPendingSnapshot(with: image)
            }
        }

        private func finishPendingSnapshot(with image: UIImage?) {
            guard let requestID = pendingSnapshotRequestID else { return }
            pendingSnapshotRequestID = nil
            completedSnapshotRequestID = requestID
            onSnapshot?(requestID, image)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url, CardWebView.canOpenExternally(url) {
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }

            if contentTrust == .untrusted {
                let isInitialDocument = navigationAction.request.url?.scheme == "about"
                    && navigationAction.targetFrame?.isMainFrame != false
                decisionHandler(isInitialDocument ? .allow : .cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}

enum CardHTMLDocument {
    private static let restrictedPolicy = "default-src 'none'; img-src https: data: blob:; media-src data: blob:; style-src 'unsafe-inline'; font-src data:; script-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; form-action 'none'; base-uri 'none'"

    static func make(from html: String, contentTrust: CardContentTrust) -> String {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        let isCompleteDocument = trimmed.range(of: "<!doctype", options: .caseInsensitive) != nil
            || trimmed.range(of: "<html", options: .caseInsensitive) != nil
        if contentTrust == .trusted, isCompleteDocument {
            return html
        }

        let securityMeta = contentTrust == .untrusted
            ? "<meta http-equiv=\"Content-Security-Policy\" content=\"\(restrictedPolicy)\">"
            : ""

        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
          \(securityMeta)
          <style>
            :root { color-scheme: light dark; }
            * { box-sizing: border-box; }
            body {
              margin: 0;
              padding: 20px;
              background: transparent;
              color: -apple-system-label;
              font: -apple-system-body;
              line-height: 1.45;
              overflow-wrap: anywhere;
            }
            h1, h2, h3, h4, h5, h6 { line-height: 1.15; margin: 0 0 0.65em; }
            p, ul, ol, blockquote, pre { margin: 0 0 1em; }
            a { color: -apple-system-blue; }
            pre, code { font-family: ui-monospace, Menlo, monospace; }
            pre { white-space: pre-wrap; }
          </style>
        </head>
        <body>\(html)</body>
        </html>
        """
    }
}
