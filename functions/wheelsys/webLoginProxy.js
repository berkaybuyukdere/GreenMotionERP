/**
 * WheelSys web login proxy — first-party iframe session capture.
 */
/* eslint-disable max-len */

const admin = require("firebase-admin");
const {
  mergeSetCookies,
  readSetCookieHeaders,
  buildFleetAuthCookie,
} = require("./cookieJar");
const {BASE_URL} = require("./client");

const TARGET_HOST = "https://ch.wheelsys.greenmotion.com";
const UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
  "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36";
const SCRATCH_COLLECTION = "wheelsysWebLoginSessions";
const TTL_MS = 15 * 60 * 1000;

/**
 * @param {string} sid
 * @return {FirebaseFirestore.DocumentReference}
 */
function scratchRef(sid) {
  return admin.firestore().collection(SCRATCH_COLLECTION).doc(String(sid));
}

/**
 * @param {string} sid
 * @return {Promise<object|null>}
 */
async function loadScratch(sid) {
  const snap = await scratchRef(sid).get();
  if (!snap.exists) return null;
  const data = snap.data() || {};
  const created = data.createdAt && data.createdAt.toMillis ?
    data.createdAt.toMillis() : 0;
  if (created && Date.now() - created > TTL_MS) return null;
  return data;
}

/**
 * @param {string} sid
 * @param {object} patch
 */
async function patchScratch(sid, patch) {
  await scratchRef(sid).set({
    ...patch,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}

/**
 * @param {object} p
 * @return {Promise<{sid: string, proxyPath: string}>}
 */
async function startWebLoginSession(p) {
  const sid = require("crypto").randomBytes(16).toString("hex");
  await scratchRef(sid).set({
    uid: String(p.uid || ""),
    franchiseId: String(p.franchiseId || "CH").toUpperCase(),
    station: String(p.station || "ZRH").toUpperCase(),
    cookieJar: "",
    status: "pending",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + TTL_MS),
  });
  return {sid, proxyPath: `/wheelsys-login-proxy/ui/?sid=${sid}`};
}

/**
 * @param {string} body
 * @param {string} proxyOrigin
 * @return {string}
 */
function rewriteProxiedBody(body, proxyOrigin) {
  let out = String(body || "");
  const base = `${proxyOrigin}/wheelsys-login-proxy`;
  out = out.split(TARGET_HOST).join(base);
  out = out.replace(/href="\/ui\//g, `href="${base}/ui/`);
  out = out.replace(/src="\/ui\//g, `src="${base}/ui/`);
  out = out.replace(/action="\/ui\//g, `action="${base}/ui/`);
  out = out.replace(/(["'])\/(ui\/)/g, `$1${base}/$2`);
  return out;
}

/**
 * @param {string} location
 * @param {string} proxyOrigin
 * @return {string}
 */
function rewriteLocation(location, proxyOrigin) {
  const loc = String(location || "");
  if (loc.startsWith(TARGET_HOST)) {
    return `${proxyOrigin}/wheelsys-login-proxy${loc.slice(TARGET_HOST.length)}`;
  }
  if (loc.startsWith("/")) {
    return `${proxyOrigin}/wheelsys-login-proxy${loc}`;
  }
  return loc;
}

/**
 * @param {object} req
 * @param {object} res
 * @param {string} proxyOrigin
 */
async function handleProxyRequest(req, res, proxyOrigin) {
  const sid = String(req.query.sid || "").trim();
  if (!sid) {
    res.status(400).send("Missing sid");
    return;
  }
  const scratch = await loadScratch(sid);
  if (!scratch) {
    res.status(410).send("Login session expired. Refresh the page.");
    return;
  }

  const reqUrl = new URL(
      req.url || "/",
      proxyOrigin || "https://vehiclesentinel.com",
  );
  let rawPath = reqUrl.pathname.replace(/^\/wheelsys-login-proxy/, "");
  if (!rawPath || rawPath === "/") rawPath = "/ui/";
  const qs = new URLSearchParams(reqUrl.search);
  qs.delete("sid");
  const qstr = qs.toString();
  const targetUrl = `${TARGET_HOST}${rawPath}${qstr ? `?${qstr}` : ""}`;

  const headers = {
    "User-Agent": UA,
    "Accept": req.headers.accept || "*/*",
    "Accept-Language": "en-US,en;q=0.9",
  };
  if (scratch.cookieJar) headers.Cookie = scratch.cookieJar;
  if (req.headers["content-type"]) {
    headers["Content-Type"] = req.headers["content-type"];
  }

  const init = {
    method: req.method,
    headers,
    redirect: "manual",
  };
  if (req.method !== "GET" && req.method !== "HEAD" && req.rawBody) {
    init.body = req.rawBody;
  }

  const upstream = await fetch(targetUrl, init);
  const setCookies = readSetCookieHeaders(upstream.headers);
  if (setCookies.length) {
    const merged = mergeSetCookies(scratch.cookieJar || "", setCookies);
    await patchScratch(sid, {cookieJar: merged});
    scratch.cookieJar = merged;
  }

  const authCookie = buildFleetAuthCookie(scratch.cookieJar || "");
  if (authCookie) {
    await patchScratch(sid, {authCookie, status: "cookies_ready"});
  }

  if (upstream.status >= 300 && upstream.status < 400) {
    const loc = upstream.headers.get("location");
    res.status(upstream.status);
    if (loc) res.set("Location", rewriteLocation(loc, proxyOrigin));
    res.end();
    return;
  }

  const ctype = String(upstream.headers.get("content-type") || "");
  const buf = Buffer.from(await upstream.arrayBuffer());

  res.status(upstream.status);
  res.set("X-Frame-Options", "SAMEORIGIN");
  res.removeHeader("Content-Security-Policy");

  const isText =
    ctype.includes("text/") ||
    ctype.includes("javascript") ||
    ctype.includes("json") ||
    ctype.includes("xml");

  if (isText) {
    if (ctype) res.set("Content-Type", ctype);
    res.send(rewriteProxiedBody(buf.toString("utf8"), proxyOrigin));
    return;
  }

  if (ctype) res.set("Content-Type", ctype);
  res.send(buf);
}

/**
 * @param {object} p
 * @return {Promise<object>}
 */
async function pollWebLogin(p) {
  const sid = String(p.sid || "").trim();
  const scratch = await loadScratch(sid);
  if (!scratch) {
    return {ready: false, expired: true};
  }
  if (String(scratch.uid) !== String(p.uid)) {
    return {ready: false, forbidden: true};
  }

  const authCookie = scratch.authCookie ||
    buildFleetAuthCookie(scratch.cookieJar || "");
  if (!authCookie) {
    return {ready: false, status: scratch.status || "pending"};
  }

  const probe = await fetch(`${BASE_URL}/ui/manage/master/rentals.aspx`, {
    headers: {"Cookie": authCookie, "User-Agent": UA},
    redirect: "follow",
  });
  const html = String(await probe.text());
  const loggedIn = probe.ok &&
    !( /login|sign.?in/i.test(html) && !html.includes("/ui/manage/") );

  if (!loggedIn) {
    return {ready: false, status: "awaiting_login"};
  }

  const {saveSession} = require("./sessionStore");
  await saveSession({
    db: admin.firestore(),
    franchiseId: scratch.franchiseId,
    station: scratch.station,
    cookiePlain: authCookie,
    encryptionKeyHex: p.encryptionKeyHex,
    createdBy: p.uid,
    ttlHours: 24,
  });

  await patchScratch(sid, {status: "saved", savedAt: Date.now()});

  return {
    ready: true,
    saved: true,
    franchiseId: scratch.franchiseId,
    station: scratch.station,
  };
}

module.exports = {
  startWebLoginSession,
  handleProxyRequest,
  pollWebLogin,
  SCRATCH_COLLECTION,
};
