/**
 * CH Stripe daily reports — KPI aggregation by date range with daily series.
 */
/* eslint-disable require-jsdoc */

const {
  CH_TIMEZONE,
  localDayKeyInTimezone,
  paymentBucketFromCharge,
  paymentBucketFromIntent,
  detectChannel,
} = require("./chStripePaymentListing");

const PERIOD_DAYS = {
  "1d": 1,
  "7d": 7,
  "30d": 30,
  "180d": 180,
  "1y": 365,
};

const MAIL_ORDER_CATEGORIES = ["traffic_fine", "damage", "other"];

function emptyMetric() {
  return {count: 0, volume: 0};
}

function emptyMailOrderByCategory() {
  return {
    traffic_fine: emptyMetric(),
    damage: emptyMetric(),
    other: emptyMetric(),
  };
}

function emptyDayBucket(dayKey) {
  return {
    dayKey,
    payments: emptyMetric(),
    chargebacks: emptyMetric(),
    mailOrder: {
      ...emptyMetric(),
      byCategory: emptyMailOrderByCategory(),
    },
  };
}

function normalizePeriod(raw) {
  const key = String(raw || "7d").toLowerCase().trim();
  return PERIOD_DAYS[key] ? key : "7d";
}

function normalizeMailOrderCategory(raw) {
  const c = String(raw || "").toLowerCase().trim().replace(/-/g, "_");
  if (c === "traffic_fine" || c === "trafficfine") return "traffic_fine";
  if (c === "damage") return "damage";
  return "other";
}

function addMetric(target, count, volume) {
  target.count += count;
  target.volume += Number(volume) || 0;
}

function dayKeyFromDate(date, timeZone) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

function parseDayKey(dayKey) {
  const [y, m, d] = String(dayKey).split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d, 12, 0, 0));
}

function addDaysToDayKey(dayKey, delta, timeZone) {
  const base = parseDayKey(dayKey);
  base.setUTCDate(base.getUTCDate() + delta);
  return dayKeyFromDate(base, timeZone);
}

function buildDayKeys(endDayKey, dayCount, timeZone) {
  const keys = [];
  for (let i = dayCount - 1; i >= 0; i -= 1) {
    keys.push(addDaysToDayKey(endDayKey, -i, timeZone));
  }
  return keys;
}

function unixForDayKeyStart(dayKey, timeZone) {
  const [y, m, d] = String(dayKey).split("-").map(Number);
  const dayPart =
    `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
  const guess = new Date(`${dayPart}T00:00:00`);
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone,
    hour: "numeric",
    hour12: false,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  const parts = formatter.formatToParts(guess);
  const hour = Number(parts.find((p) => p.type === "hour").value);
  return Math.floor(guess.getTime() / 1000) - hour * 3600;
}

function isUnixOnOrAfterDay(unixSec, startDayKey, timeZone) {
  if (!unixSec) return false;
  const key = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(Number(unixSec) * 1000));
  return key >= startDayKey;
}

function isUnixOnOrBeforeDay(unixSec, endDayKey, timeZone) {
  if (!unixSec) return false;
  const key = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(Number(unixSec) * 1000));
  return key <= endDayKey;
}

function isDayKeyInRange(dayKey, startDayKey, endDayKey) {
  return dayKey >= startDayKey && dayKey <= endDayKey;
}

function dayKeyFromUnix(unixSec, timeZone) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(Number(unixSec) * 1000));
}

function dayKeyFromFirestoreTimestamp(ts, timeZone) {
  if (!ts) return null;
  const date = ts.toDate ? ts.toDate() : new Date(ts);
  return dayKeyFromDate(date, timeZone);
}

async function listStripeChargesSince(stripe, createdGte) {
  const all = [];
  let startingAfter = null;
  for (let page = 0; page < 20; page += 1) {
    const params = {limit: 100, created: {gte: createdGte}};
    if (startingAfter) params.starting_after = startingAfter;
    const res = await stripe.charges.list(params);
    all.push(...(res.data || []));
    if (!res.has_more || !res.data.length) break;
    startingAfter = res.data[res.data.length - 1].id;
  }
  return all;
}

async function listStripePaymentIntentsSince(stripe, createdGte) {
  const all = [];
  let startingAfter = null;
  for (let page = 0; page < 20; page += 1) {
    const params = {limit: 100, created: {gte: createdGte}};
    if (startingAfter) params.starting_after = startingAfter;
    const res = await stripe.paymentIntents.list(params);
    all.push(...(res.data || []));
    if (!res.has_more || !res.data.length) break;
    startingAfter = res.data[res.data.length - 1].id;
  }
  return all;
}

function rollupKpis(dailySeries) {
  const kpis = {
    payments: emptyMetric(),
    chargebacks: emptyMetric(),
    mailOrder: {
      ...emptyMetric(),
      byCategory: emptyMailOrderByCategory(),
    },
  };
  for (const day of dailySeries) {
    addMetric(kpis.payments, day.payments.count, day.payments.volume);
    addMetric(kpis.chargebacks, day.chargebacks.count, day.chargebacks.volume);
    addMetric(kpis.mailOrder, day.mailOrder.count, day.mailOrder.volume);
    for (const cat of MAIL_ORDER_CATEGORIES) {
      const block = day.mailOrder.byCategory[cat];
      addMetric(kpis.mailOrder.byCategory[cat], block.count, block.volume);
    }
  }
  return kpis;
}

/**
 * @param {object} stripe Stripe client
 * @param {string} franchiseId
 * @param {string} period 1d|7d|30d|180d|1y
 * @param {FirebaseFirestore.Firestore} db
 * @return {Promise<object>}
 */
async function aggregateStripeDailyReports(stripe, franchiseId, period, db) {
  const timeZone = CH_TIMEZONE;
  const normalizedPeriod = normalizePeriod(period);
  const dayCount = PERIOD_DAYS[normalizedPeriod];
  const endDayKey = localDayKeyInTimezone(timeZone);
  const startDayKey = addDaysToDayKey(endDayKey, -(dayCount - 1), timeZone);
  const dayKeys = buildDayKeys(endDayKey, dayCount, timeZone);
  const buckets = new Map(dayKeys.map((k) => [k, emptyDayBucket(k)]));

  const createdGte = unixForDayKeyStart(startDayKey, timeZone) - 86400;

  const [charges, intents, disputesSnap, mailSnap] = await Promise.all([
    listStripeChargesSince(stripe, createdGte),
    listStripePaymentIntentsSince(stripe, createdGte),
    db.collection("franchises").doc(franchiseId)
        .collection("stripeDisputes")
        .where("createdAt", ">=", new Date(createdGte * 1000))
        .get(),
    db.collection("franchises").doc(franchiseId)
        .collection("stripeMailOrders")
        .where("createdAt", ">=", new Date(createdGte * 1000))
        .get(),
  ]);

  const countedPaymentKeys = new Set();

  for (const ch of charges) {
    if (!isUnixOnOrAfterDay(ch.created, startDayKey, timeZone) ||
      !isUnixOnOrBeforeDay(ch.created, endDayKey, timeZone)) {
      continue;
    }
    const meta = ch.metadata || {};
    if (meta.franchiseId &&
      String(meta.franchiseId).toUpperCase() !== franchiseId) {
      continue;
    }
    const bucketName = paymentBucketFromCharge(ch);
    if (bucketName !== "successful") continue;

    const dayKey = dayKeyFromUnix(ch.created, timeZone);
    const bucket = buckets.get(dayKey);
    if (!bucket) continue;

    const payKey = ch.payment_intent || ch.id;
    if (countedPaymentKeys.has(payKey)) continue;
    countedPaymentKeys.add(payKey);

    const volume = Number(ch.amount_captured || ch.amount || 0);
    addMetric(bucket.payments, 1, volume);
  }

  for (const pi of intents) {
    if (!isUnixOnOrAfterDay(pi.created, startDayKey, timeZone) ||
      !isUnixOnOrBeforeDay(pi.created, endDayKey, timeZone)) {
      continue;
    }
    const meta = pi.metadata || {};
    if (meta.franchiseId &&
      String(meta.franchiseId).toUpperCase() !== franchiseId) {
      continue;
    }
    const bucketName = paymentBucketFromIntent(pi);
    if (bucketName !== "successful") continue;
    if (countedPaymentKeys.has(pi.id)) continue;
    countedPaymentKeys.add(pi.id);

    const dayKey = dayKeyFromUnix(pi.created, timeZone);
    const bucket = buckets.get(dayKey);
    if (!bucket) continue;

    const volume = Number(pi.amount_received || pi.amount || 0);
    addMetric(bucket.payments, 1, volume);
  }

  for (const docSnap of disputesSnap.docs) {
    const row = docSnap.data() || {};
    const createdAt = row.createdAt;
    const dayKey = dayKeyFromFirestoreTimestamp(createdAt, timeZone);
    if (!dayKey || !isDayKeyInRange(dayKey, startDayKey, endDayKey)) continue;
    const bucket = buckets.get(dayKey);
    if (!bucket) continue;
    addMetric(bucket.chargebacks, 1, Number(row.amount || 0));
  }

  const countedMailOrders = new Set();

  for (const docSnap of mailSnap.docs) {
    const row = docSnap.data() || {};
    const paid = row.status === "paid";
    if (!paid) continue;

    const paidAt = row.paidAt || row.createdAt;
    const dayKey = dayKeyFromFirestoreTimestamp(paidAt, timeZone) ||
      dayKeyFromFirestoreTimestamp(row.createdAt, timeZone);
    if (!dayKey || !isDayKeyInRange(dayKey, startDayKey, endDayKey)) continue;
    if (countedMailOrders.has(docSnap.id)) continue;
    countedMailOrders.add(docSnap.id);

    const bucket = buckets.get(dayKey);
    if (!bucket) continue;

    const volume = Number(row.amount || 0);
    const category = normalizeMailOrderCategory(row.category);
    addMetric(bucket.mailOrder, 1, volume);
    addMetric(bucket.mailOrder.byCategory[category], 1, volume);
  }

  for (const ch of charges) {
    const meta = ch.metadata || {};
    const channel = detectChannel(ch.payment_method_details, meta);
    if (channel !== "mail_order") continue;
    if (paymentBucketFromCharge(ch) !== "successful") continue;
    if (!isUnixOnOrAfterDay(ch.created, startDayKey, timeZone) ||
      !isUnixOnOrBeforeDay(ch.created, endDayKey, timeZone)) {
      continue;
    }
    if (meta.franchiseId &&
      String(meta.franchiseId).toUpperCase() !== franchiseId) {
      continue;
    }

    const mailOrderId = meta.mailOrderId;
    if (mailOrderId && countedMailOrders.has(mailOrderId)) continue;

    const dayKey = dayKeyFromUnix(ch.created, timeZone);
    const bucket = buckets.get(dayKey);
    if (!bucket) continue;

    const category = normalizeMailOrderCategory(meta.category);
    const volume = Number(ch.amount_captured || ch.amount || 0);
    addMetric(bucket.mailOrder, 1, volume);
    addMetric(bucket.mailOrder.byCategory[category], 1, volume);
    if (mailOrderId) countedMailOrders.add(mailOrderId);
  }

  const dailySeries = dayKeys.map((k) => buckets.get(k));
  const kpis = rollupKpis(dailySeries);

  return {
    period: normalizedPeriod,
    startDayKey,
    endDayKey,
    timeZone,
    kpis,
    dailySeries,
    syncedAt: new Date().toISOString(),
  };
}

module.exports = {
  aggregateStripeDailyReports,
  PERIOD_DAYS,
  normalizeMailOrderCategory,
};
