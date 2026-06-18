/**
 * Minimal cookie header merge for WheelSys ASP.NET session chaining.
 * Never log full cookie values.
 */

/**
 * @param {string} header
 * @return {Map<string, string>}
 */
function parseCookieHeader(header) {
  const jar = new Map();
  for (const part of String(header || "").split(";")) {
    const trimmed = part.trim();
    if (!trimmed) continue;
    const eq = trimmed.indexOf("=");
    if (eq <= 0) continue;
    const name = trimmed.slice(0, eq).trim();
    const value = trimmed.slice(eq + 1).trim();
    if (name) jar.set(name, value);
  }
  return jar;
}

/**
 * @param {Map<string, string>} jar
 * @return {string}
 */
function serializeCookieJar(jar) {
  return Array.from(jar.entries())
      .map(([name, value]) => `${name}=${value}`)
      .join("; ");
}

/**
 * Merge Set-Cookie response headers into an existing Cookie request header.
 * @param {string} existingCookie
 * @param {string[]} setCookies
 * @return {string}
 */
function mergeSetCookies(existingCookie, setCookies) {
  const jar = parseCookieHeader(existingCookie);
  for (const raw of setCookies || []) {
    const first = String(raw || "").split(";")[0];
    const eq = first.indexOf("=");
    if (eq <= 0) continue;
    jar.set(first.slice(0, eq).trim(), first.slice(eq + 1).trim());
  }
  return serializeCookieJar(jar);
}

/**
 * @param {Headers} headers
 * @return {string[]}
 */
function readSetCookieHeaders(headers) {
  if (!headers) return [];
  if (typeof headers.getSetCookie === "function") {
    const list = headers.getSetCookie();
    if (Array.isArray(list) && list.length) return list;
  }
  if (typeof headers.raw === "function") {
    const raw = headers.raw()["set-cookie"];
    if (Array.isArray(raw)) return raw;
    if (raw) return [raw];
  }
  const single = headers.get("set-cookie");
  return single ? [single] : [];
}

/**
 * Extract only Fleet Chart auth cookies (.wheelsys + __Secure-SID).
 * Browser order: .wheelsys first, then __Secure-SID.
 * @param {string} header
 * @return {string|null}
 */
function buildFleetAuthCookie(header) {
  const jar = parseCookieHeader(header);
  const ws = jar.get(".wheelsys");
  const sid = jar.get("__Secure-SID");
  if (!ws || !sid) return null;
  return `.wheelsys=${ws}; __Secure-SID=${sid}`;
}

/**
 * Safe cookie presence log — never logs values.
 * @param {string} header
 * @return {object}
 */
function cookiePresenceLog(header) {
  const c = String(header || "");
  return {
    hasWheelsys: c.includes(".wheelsys="),
    hasSID: c.includes("__Secure-SID="),
    cookieLength: c.length,
  };
}

module.exports = {
  parseCookieHeader,
  serializeCookieJar,
  mergeSetCookies,
  readSetCookieHeaders,
  buildFleetAuthCookie,
  cookiePresenceLog,
};
