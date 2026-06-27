/**
 * Canonical plate normalization (NFKC; matches fleet-inventory / iOS).
 * @param {string} raw
 * @return {string}
 */
function canonicalPlate(raw) {
  return String(raw || "")
      .normalize("NFKC")
      .toUpperCase()
      .replace(/[^A-Z0-9]/g, "");
}

module.exports = {
  canonicalPlate,
};
