import Foundation
import WebKit

/// Detect the WheelSys operator from an authenticated WKWebView page.
enum WheelSysLoggedInUserDetection {
    static let js = """
    (function() {
      function clean(v) { return v == null ? "" : String(v).trim(); }
      function bySelectorValue(selector) {
        const el = document.querySelector(selector);
        return el ? clean(el.value) : "";
      }
      function fromCombo(id) {
        const combo = document.querySelector("#" + id + "_combo");
        if (!combo || !clean(combo.value)) return null;
        const opt = combo.options[combo.selectedIndex];
        return { id: clean(combo.value), name: clean(opt && opt.textContent) };
      }
      function fromNfo() {
        const html = document.documentElement.innerHTML || "";
        const nfoMatch = html.match(/nfo=([^&"'\\\\s]+)/);
        if (!nfoMatch) return null;
        try {
          const decoded = decodeURIComponent(nfoMatch[1]);
          const json = JSON.parse(atob(decoded));
          const id = clean(json.userId || json.UserId || json.uid);
          if (!id) return null;
          const opt =
            document.querySelector('#rdUserFrom_combo option[value="' + id + '"]') ||
            document.querySelector('#rdUserTo_combo option[value="' + id + '"]');
          return { id, name: clean(opt && opt.textContent) || clean(json.userName || json.name) };
        } catch (e) {
          return null;
        }
      }
      const nfoUser = fromNfo();
      if (nfoUser && nfoUser.id) return JSON.stringify(nfoUser);
      const fromUser = fromCombo("rdUserFrom") || fromCombo("rdUserTo");
      if (fromUser && fromUser.id) return JSON.stringify(fromUser);
      const drivenId = bySelectorValue("#DrivenByUser_value");
      const drivenName = bySelectorValue("#DrivenByUser_text");
      if (drivenId) return JSON.stringify({ id: drivenId, name: drivenName });
      const globals = [window.wheels, window.WheelSys, window.pageUser];
      for (const g of globals) {
        if (g && g.userId) {
          const id = clean(g.userId);
          const name = clean(g.userName || g.name || "");
          if (id) return JSON.stringify({ id, name });
        }
      }
      return JSON.stringify({ error: "Could not detect logged-in Wheelsys user." });
    })();
    """

    @MainActor
    static func detect(in webView: WKWebView) async -> WheelSysLoggedInUser? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(js) { result, _ in
                guard let raw = result as? String,
                      let data = raw.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["error"] == nil,
                      let id = (json["id"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                      !id.isEmpty
                else {
                    continuation.resume(returning: nil)
                    return
                }
                let name = (json["name"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: WheelSysLoggedInUser(id: id, name: name))
            }
        }
    }
}
