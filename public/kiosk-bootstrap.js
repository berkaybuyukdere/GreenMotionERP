/**
 * Front-desk kiosk bootstrap: franchise resolution, TR/DE branch picker, GRT context.
 * Loaded before the React SPA — must finish redirect before paint when possible.
 */
(function kioskBootstrap() {
  if (typeof window === "undefined") return;

  const STORAGE_KEY = "gm_selected_franchise";

  function isKioskPath() {
    const path = (window.location.pathname || "").replace(/\/+$/, "");
    const hash = (window.location.hash || "").replace(/^#/, "").split("?")[0].replace(/^\//, "");
    return (
      /\/front-desk$|\/frontdesk$|\/kiosk$/i.test(path) ||
      hash === "front-desk" ||
      hash === "frontdesk" ||
      hash === "kiosk"
    );
  }

  function readFranchiseParam() {
    const search = new URLSearchParams(window.location.search || "");
    const hashQs = (window.location.hash || "").includes("?")
      ? new URLSearchParams(window.location.hash.split("?")[1] || "")
      : new URLSearchParams();
    return (
      search.get("franchise") ||
      search.get("franchiseId") ||
      hashQs.get("franchise") ||
      hashQs.get("franchiseId") ||
      ""
    ).trim();
  }

  function selectedBranchFromStorage() {
    try {
      const raw = String(localStorage.getItem(STORAGE_KEY) || "").trim();
      if (!raw) return "";
      const upper = raw.toUpperCase();
      if (/^(TR|DE|CH)(_|$)/i.test(upper)) return upper;
      return "";
    } catch (_e) {
      return "";
    }
  }

  function persistBranch(franchiseId) {
    try {
      localStorage.setItem(STORAGE_KEY, String(franchiseId || "").trim().toUpperCase());
    } catch (_e) {
      /* ignore quota / private mode */
    }
  }

  function resolveAlias(id, registry) {
    const key = String(id || "").trim().toUpperCase();
    if (!key) return "";
    const aliases = (registry && registry.aliases) || {};
    return String(aliases[key] || key).trim().toUpperCase();
  }

  function branchByKey(key, registry) {
    const canonical = resolveAlias(key, registry);
    if (!canonical || !registry || !Array.isArray(registry.franchises)) return null;
    return registry.franchises.find((b) => b && b.storageKey === canonical) || null;
  }

  function isCountryCodeOnly(id) {
    const u = String(id || "").trim().toUpperCase();
    return u === "TR" || u === "DE" || u === "CH";
  }

  function redirectToFranchise(franchiseId) {
    const canonical = String(franchiseId || "").trim().toUpperCase();
    if (!canonical) return;
    persistBranch(canonical);
    const url = new URL(window.location.href);
    url.searchParams.set("franchise", canonical);
    if (url.hash && url.hash.includes("?")) {
      const parts = url.hash.split("?");
      const hp = new URLSearchParams(parts[1] || "");
      hp.set("franchise", canonical);
      url.hash = parts[0] + "?" + hp.toString();
    }
    window.location.replace(url.toString());
  }

  function publishGlobals(registry, resolvedFranchise) {
    if (registry) window.__KIOSK_FRANCHISES_CACHE__ = registry;
    const resolved = String(resolvedFranchise || readFranchiseParam() || "").trim().toUpperCase();
    window.__KIOSK_RESOLVED_FRANCHISE = resolved;
    window.__KIOSK_IS_TURKEY = resolved.startsWith("TR");
    window.__KIOSK_IS_GERMANY = resolved.startsWith("DE");
    window.__KIOSK_IS_SWITZERLAND = resolved === "CH" || resolved.startsWith("CH_");

    window.__kioskFranchiseDisplayName = function kioskFranchiseDisplayName(id) {
      const key = resolveAlias(id, registry || window.__KIOSK_FRANCHISES_CACHE__);
      if (!key) return "—";
      const cache = registry || window.__KIOSK_FRANCHISES_CACHE__;
      if (cache && Array.isArray(cache.franchises)) {
        const hit = cache.franchises.find((f) => f.storageKey === key);
        if (hit && hit.displayName) return hit.displayName;
      }
      return key;
    };

    window.__kioskResolveFranchiseId = function kioskResolveFranchiseId(id) {
      return resolveAlias(id, registry || window.__KIOSK_FRANCHISES_CACHE__);
    };
  }

  function overlayBaseStyles() {
    return [
      "position:fixed",
      "inset:0",
      "z-index:99999",
      "background:#0a0a0c",
      "color:#f5f5f7",
      "display:flex",
      "flex-direction:column",
      "align-items:center",
      "justify-content:center",
      "padding:24px",
      "font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif",
    ].join(";");
  }

  function showBranchPicker(branches, countryLabel) {
    const overlay = document.createElement("div");
    overlay.id = "kiosk-branch-picker";
    overlay.setAttribute("style", overlayBaseStyles());
    const title = document.createElement("h1");
    title.textContent = countryLabel + " — şube seçin / select branch";
    title.setAttribute("style", "font-size:22px;font-weight:600;margin:0 0 8px;text-align:center");
    const hint = document.createElement("p");
    hint.textContent = "Kiosk hangi şube için açılsın? / Which branch is this kiosk for?";
    hint.setAttribute("style", "font-size:14px;opacity:.75;margin:0 0 24px;text-align:center;max-width:480px");
    const list = document.createElement("div");
    list.setAttribute(
        "style",
        "display:grid;gap:10px;width:min(480px,100%);max-height:70vh;overflow:auto",
    );
    branches.forEach((b) => {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.textContent = b.displayName || b.storageKey;
      btn.setAttribute(
          "style",
          [
            "padding:14px 18px",
            "border-radius:12px",
            "border:1px solid rgba(255,255,255,.12)",
            "background:#151518",
            "color:#f5f5f7",
            "font-size:16px",
            "font-weight:500",
            "cursor:pointer",
            "text-align:left",
          ].join(";"),
      );
      btn.addEventListener("click", () => redirectToFranchise(b.storageKey));
      list.appendChild(btn);
    });
    overlay.appendChild(title);
    overlay.appendChild(hint);
    overlay.appendChild(list);
    document.documentElement.appendChild(overlay);
  }

  function showInvalidFranchise(franchiseId) {
    const overlay = document.createElement("div");
    overlay.id = "kiosk-invalid-franchise";
    overlay.setAttribute("style", overlayBaseStyles());
    const title = document.createElement("h1");
    title.textContent = "Geçersiz şube / Invalid branch";
    title.setAttribute("style", "font-size:22px;font-weight:600;margin:0 0 12px;text-align:center");
    const body = document.createElement("p");
    body.textContent =
      "Franchise \"" + franchiseId + "\" is not configured for kiosk. " +
      "Use a branch link such as ?franchise=TR_NEVSEHIR or ?franchise=TR for Türkiye.";
    body.setAttribute("style", "font-size:14px;opacity:.8;margin:0 0 20px;text-align:center;max-width:520px;line-height:1.45");
    const link = document.createElement("a");
    link.href = "/front-desk?franchise=TR";
    link.textContent = "Türkiye şube seçici / Turkey branch picker";
    link.setAttribute("style", "color:#0a84ff;font-size:16px;font-weight:600;text-decoration:none");
    overlay.appendChild(title);
    overlay.appendChild(body);
    overlay.appendChild(link);
    document.documentElement.appendChild(overlay);
  }

  function loadRegistry() {
    return fetch("/kiosk-franchises.json?v=2", {cache: "no-store"})
        .then((r) => (r.ok ? r.json() : null))
        .catch(() => null);
  }

  function branchesForCountry(registry, countryCode) {
    const cc = String(countryCode || "").trim().toUpperCase();
    const fromMap = registry && registry.byCountry && registry.byCountry[cc];
    if (Array.isArray(fromMap) && fromMap.length) {
      return fromMap.filter((b) => b && b.storageKey);
    }
    if (!registry || !Array.isArray(registry.franchises)) return [];
    return registry.franchises.filter((b) => b && b.countryCode === cc);
  }

  function runWithRegistry(registry) {
    const rawParam = readFranchiseParam();
    const franchise = rawParam.toUpperCase();
    const branch = selectedBranchFromStorage();

    publishGlobals(registry, franchise);

    if (!franchise) return;

    const canonical = resolveAlias(franchise, registry);
    if (canonical && canonical !== franchise) {
      redirectToFranchise(canonical);
      return;
    }

    if ((franchise === "TR" || franchise === "DE") && branch && branch.startsWith(franchise + "_")) {
      if (!registry || branchByKey(branch, registry)) {
        redirectToFranchise(branch);
        return;
      }
    }

    if (franchise === "TR" || franchise === "DE") {
      const list = branchesForCountry(registry, franchise);
      if (list.length === 1) {
        redirectToFranchise(list[0].storageKey);
        return;
      }
      if (list.length > 1) {
        const label =
          (registry && registry.countryLabels && registry.countryLabels[franchise]) || franchise;
        const mount = () => showBranchPicker(list, label);
        if (document.readyState === "loading") {
          document.addEventListener("DOMContentLoaded", mount);
        } else {
          mount();
        }
        return;
      }
    }

    if (franchise && !isCountryCodeOnly(franchise)) {
      const known = branchByKey(franchise, registry);
      if (known) {
        persistBranch(known.storageKey);
        publishGlobals(registry, known.storageKey);
        return;
      }
      if (registry && Array.isArray(registry.franchises) && registry.franchises.length > 0) {
        const mount = () => showInvalidFranchise(franchise);
        if (document.readyState === "loading") {
          document.addEventListener("DOMContentLoaded", mount);
        } else {
          mount();
        }
      }
    } else if (franchise === "CH") {
      persistBranch("CH");
    }
  }

  if (!isKioskPath()) return;

  loadRegistry().then((registry) => {
    runWithRegistry(registry);
  });
})();
