import UIKit
import WebKit
import WidgetKit

/// Shows the Axiom dashboard (the same single HTML file, bundled in the app) full screen,
/// and hands its next duties and water count to the Home Screen widgets.
final class DashboardViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    var webView: WKWebView!   // internal so the in-app tests can read the page
    private var darkTheme = true
    private var downloads: [ObjectIdentifier: URL] = [:]
    private let tick = UISelectionFeedbackGenerator()

    override var preferredStatusBarStyle: UIStatusBarStyle { darkTheme ? .lightContent : .darkContent }

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()                       // keeps the dashboard's saved data between launches
        config.allowsInlineMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let ucc = WKUserContentController()
        ucc.add(WeakHandler(self), name: "axiom")
        ucc.add(WeakHandler(self), name: "axiomAlarm")   // Stop / Snooze on Axiom's own ringing screen
        config.userContentController = ucc

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never   // the page keeps clear of the notch and side column itself
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.allowsBackForwardNavigationGestures = false
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let p = Shared.load() { applyTheme(p.theme) }
        if let index = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web") {
            webView.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        }
        startWatchingAlarms()
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(wentToBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    // MARK: - Dashboard → widgets

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "axiomAlarm" {
            guard let text = message.body as? String, let data = text.data(using: .utf8),
                  let cmd = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let action = cmd["action"] else { return }
            if action == "tick" {   // a light click as the time drums turn, like the iPhone's own picker
                tick.selectionChanged()
                tick.prepare()
                return
            }
            guard let id = cmd["id"].flatMap(UUID.init(uuidString:)) else { return }
            AlarmScheduler.shared.handle(action: action, id: id)
            return
        }
        guard message.name == "axiom",
              let text = message.body as? String,
              let data = text.data(using: .utf8),
              var incoming = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        // glasses added on the widget since the dashboard last saved win over the dashboard's older count
        if let stored = Shared.load(), stored.water.ts > incoming.water.ts {
            incoming.water = stored.water
            sendWaterToPage(stored.water)
        }
        Shared.save(incoming)
        WidgetCenter.shared.reloadAllTimelines()
        applyTheme(incoming.theme)
        if let alarms = incoming.alarms { syncAlarms(alarms) }
        let saved = incoming
        Task { await Reminders.sync(saved, ask: true) }
    }

    // MARK: - Alarm clock: the dashboard's alarms go to iOS, which rings them even with the app closed

    private func syncAlarms(_ set: AlarmSet) {
        AlarmScheduler.shared.sync(set) { [weak self] status in
            self?.sendAlarmStatusToPage(status)
        }
    }

    /// While iOS rings an alarm, Axiom shows its own dot-matrix ringing screen (when you're using the phone or tap the alarm).
    private var ringing: UUID?
    private func startWatchingAlarms() {
        AlarmScheduler.shared.watchRinging { [weak self] id, item in
            guard let self = self else { return }
            self.ringing = id
            self.sendRingingToPage()
        }
    }

    private func sendRingingToPage() {
        guard let id = ringing else {
            webView.evaluateJavaScript("window.axiomAlarmRinging && window.axiomAlarmRinging(null)", completionHandler: nil)
            return
        }
        let item = AlarmScheduler.loadKnown()[id.uuidString]
        var x: [String: Any] = ["id": id.uuidString, "title": item?.title ?? "Alarm", "sub": item?.sub ?? ""]
        if let h = item?.h, let m = item?.m { x["h"] = h; x["m"] = m }
        guard let data = try? JSONSerialization.data(withJSONObject: x), let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.axiomAlarmRinging && window.axiomAlarmRinging(\(json))", completionHandler: nil)
    }

    private func sendAlarmStatusToPage(_ status: AlarmStatus) {
        guard let data = try? JSONEncoder().encode(status), let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.axiomAlarmStatus && window.axiomAlarmStatus(\(json))", completionHandler: nil)
    }

    // MARK: - Widgets → dashboard

    @objc private func becameActive() {
        if let w = Shared.load()?.water { sendWaterToPage(w) }
        sendListTicksToPage()
        // alarms allowed or turned off in Settings since last time
        if let a = Shared.load()?.alarms { syncAlarms(a) }
        Task { await Reminders.sync(Shared.load(), ask: false) }   // a new day: fresh water reminders
    }

    /// Items ticked off on the To-do or Shopping widget: hand them to the dashboard, then forget them once it has them.
    private func sendListTicksToPage() {
        let ops = Shared.loadOps()
        guard !ops.isEmpty, let data = try? JSONEncoder().encode(ops), let json = String(data: data, encoding: .utf8) else { return }
        let newest = ops.map(\.ts).max() ?? 0
        webView.evaluateJavaScript("window.axiomApplyOps ? window.axiomApplyOps(\(json)) : -1") { result, error in
            guard error == nil, let n = result as? Int, n >= 0 else { return }
            Shared.saveOps(Shared.loadOps().filter { $0.ts > newest })
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // the page has loaded: pass on anything the widgets changed while the app was closed
        if let w = Shared.load()?.water { sendWaterToPage(w) }
        sendListTicksToPage()
        sendRingingToPage()   // opened by tapping a ringing alarm
    }

    @objc private func wentToBackground() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func sendWaterToPage(_ w: Water) {
        guard let data = try? JSONEncoder().encode(w), let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.axiomFromWidget && window.axiomFromWidget(\(json))", completionHandler: nil)
    }

    private func applyTheme(_ theme: String?) {
        let dark = theme != "light"
        darkTheme = dark
        let bg: UIColor = dark ? .black : .white
        webView.backgroundColor = bg
        webView.scrollView.backgroundColor = bg
        view.window?.backgroundColor = bg
        overrideUserInterfaceStyle = dark ? .dark : .light
        setNeedsStatusBarAppearanceUpdate()
    }

    // MARK: - Links, downloads and pop-ups

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow); return
        }
        if ["http", "https", "mailto", "tel", "sms", "maps"].contains(scheme) {
            // links the dashboard opens (weather sources, your saved links) go to Safari or the right app
            if navigationAction.navigationType == .linkActivated || navigationAction.targetFrame == nil || navigationAction.targetFrame?.isMainFrame == true {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(suggestedFilename.isEmpty ? "axiom-backup.json" : suggestedFilename)
        try? FileManager.default.removeItem(at: url)
        downloads[ObjectIdentifier(download)] = url
        completionHandler(url)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        // backups: offer Save to Files, AirDrop and so on
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = view
        share.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: 60, width: 1, height: 1)
        present(share, animated: true)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloads.removeValue(forKey: ObjectIdentifier(download))
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { UIApplication.shared.open(url) }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard presentedViewController == nil else { completionHandler(); return }   // never leave WebKit waiting
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard presentedViewController == nil else { completionHandler(false); return }
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        guard presentedViewController == nil else { completionHandler(nil); return }
        let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        a.addTextField { $0.text = defaultText }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { [weak a] _ in completionHandler(a?.textFields?.first?.text) })
        present(a, animated: true)
    }

    // if iOS ever unloads the page in the background, bring it back
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

/// WKUserContentController holds its handlers strongly; this breaks the loop.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
