/**
 * Stripe payment listing for CH daily closing (Terminal + mail order + online).
 */
/* eslint-disable require-jsdoc */

const CH_TIMEZONE = "Europe/Zurich";

function localDayKeyInTimezone(timeZone) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

function isUnixOnLocalDay(unixSec, timeZone, dayKey) {
  if (!unixSec) return false;
  const key = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(Number(unixSec) * 1000));
  return key === dayKey;
}

function paymentBucketFromCharge(ch) {
  if (ch.status === "failed") return "cancelled";
  if (ch.status === "succeeded" && ch.captured === false) return "hold";
  if (ch.status === "succeeded") return "successful";
  return "pending";
}

function paymentBucketFromIntent(pi) {
  if (pi.status === "canceled") return "cancelled";
  if (pi.status === "requires_capture") return "hold";
  if (Number(pi.amount_capturable) > 0 && pi.status !== "succeeded") {
    return "hold";
  }
  if (pi.status === "succeeded") return "successful";
  return "pending";
}

function statusLabelForBucket(bucket) {
  if (bucket === "hold") return "Hold";
  if (bucket === "successful") return "Succeeded";
  if (bucket === "cancelled") return "Canceled";
  return "Pending";
}

function extractCardInfo(pmd) {
  if (!pmd) {
    return {cardBrand: null, cardLast4: null, paymentMethod: "card"};
  }
  const card = pmd.card || pmd.card_present || null;
  if (card) {
    return {
      cardBrand: card.brand || "card",
      cardLast4: card.last4 || "",
      paymentMethod: pmd.card_present ? "card_present" : (card.brand || "card"),
    };
  }
  if (pmd.type === "link") {
    return {cardBrand: "link", cardLast4: "", paymentMethod: "link"};
  }
  return {
    cardBrand: pmd.type || "card",
    cardLast4: "",
    paymentMethod: pmd.type || "card",
  };
}

function holdAmountForCharge(ch) {
  if (ch.status === "succeeded" && ch.captured === false) {
    return Number(ch.amount) || 0;
  }
  return 0;
}

function holdAmountForIntent(pi) {
  if (pi.status === "requires_capture" || Number(pi.amount_capturable) > 0) {
    return Number(pi.amount_capturable) || Number(pi.amount) || 0;
  }
  return 0;
}

function metaFields(meta) {
  const m = meta || {};
  const resNo = m.resNo || m.customerReference || "";
  return {
    resNo,
    reference: resNo || m.customerReference || m.productId || "",
    customerName: m.customerName || "",
    customerEmail: m.customerEmail || "",
    note: m.note || "",
    category: m.category || null,
    plate: m.plate || "",
  };
}

function detectChannel(chargeDetails, metadata) {
  const meta = metadata || {};
  if (chargeDetails && chargeDetails.card_present) return "terminal";
  if (meta.mailOrder === "true" || meta.flow === "mail_order" ||
    meta.mailOrderId) {
    return "mail_order";
  }
  return "online";
}

function buildSummary(transactions) {
  const summary = {
    successful: {count: 0, amount: 0},
    hold: {count: 0, amount: 0},
    pending: {count: 0, amount: 0},
    cancelled: {count: 0, amount: 0},
  };
  for (const tx of transactions) {
    const bucket = summary[tx.bucket];
    if (!bucket) continue;
    bucket.count += 1;
    if (tx.bucket === "successful") {
      bucket.amount += Number(tx.amountReceived || tx.amount || 0);
    } else if (tx.bucket === "hold") {
      bucket.amount += Number(tx.holdAmount || tx.amount || 0);
    } else {
      bucket.amount += Number(tx.amount || 0);
    }
  }
  return summary;
}

/**
 * @param {object} stripe Stripe client
 * @param {string} franchiseId
 * @param {string} dayKey YYYY-MM-DD
 * @param {FirebaseFirestore.Firestore} db
 * @return {Promise<object>}
 */
async function listStripePaymentsForDay(stripe, franchiseId, dayKey, db) {
  const timeZone = CH_TIMEZONE;
  const lookbackSec = 21 * 86400;
  const createdGte = Math.floor(Date.now() / 1000) - lookbackSec;

  const [chargesRes, intentsRes] = await Promise.all([
    stripe.charges.list({limit: 100, created: {gte: createdGte}}),
    stripe.paymentIntents.list({limit: 100, created: {gte: createdGte}}),
  ]);

  const byKey = new Map();

  for (const ch of chargesRes.data || []) {
    if (!isUnixOnLocalDay(ch.created, timeZone, dayKey)) continue;
    const meta = ch.metadata || {};
    const fields = metaFields(meta);
    if (meta.franchiseId &&
      String(meta.franchiseId).toUpperCase() !== franchiseId) {
      continue;
    }
    const bucket = paymentBucketFromCharge(ch);
    const cardInfo = extractCardInfo(ch.payment_method_details);
    const key = ch.payment_intent || ch.id;
    byKey.set(key, {
      id: ch.id,
      paymentIntentId: ch.payment_intent || null,
      chargeId: ch.id,
      bucket,
      status: ch.status,
      statusLabel: statusLabelForBucket(bucket),
      amount: ch.amount,
      amountReceived: ch.amount_captured || ch.amount,
      holdAmount: holdAmountForCharge(ch),
      currency: ch.currency,
      channel: detectChannel(ch.payment_method_details, meta),
      paymentMethod: cardInfo.paymentMethod,
      cardBrand: cardInfo.cardBrand,
      cardLast4: cardInfo.cardLast4,
      description: ch.description || fields.resNo || fields.plate || "",
      customerEmail: (ch.billing_details && ch.billing_details.email) ||
        fields.customerEmail,
      customerName: fields.customerName,
      resNo: fields.resNo,
      note: fields.note,
      category: fields.category,
      plate: fields.plate,
      reference: fields.reference,
      created: ch.created,
      createdAt: new Date(ch.created * 1000).toISOString(),
    });
  }

  for (const pi of intentsRes.data || []) {
    if (!isUnixOnLocalDay(pi.created, timeZone, dayKey)) continue;
    const meta = pi.metadata || {};
    const fields = metaFields(meta);
    if (meta.franchiseId &&
      String(meta.franchiseId).toUpperCase() !== franchiseId) {
      continue;
    }
    const bucket = paymentBucketFromIntent(pi);
    const existing = byKey.get(pi.id);
    if (existing) {
      existing.bucket = bucket;
      existing.status = pi.status;
      existing.statusLabel = statusLabelForBucket(bucket);
      existing.amountReceived = pi.amount_received || existing.amountReceived;
      existing.holdAmount = holdAmountForIntent(pi) || existing.holdAmount;
      existing.paymentIntentId = pi.id;
      continue;
    }
    byKey.set(pi.id, {
      id: pi.id,
      paymentIntentId: pi.id,
      chargeId: typeof pi.latest_charge === "string" ? pi.latest_charge : null,
      bucket,
      status: pi.status,
      statusLabel: statusLabelForBucket(bucket),
      amount: pi.amount,
      amountReceived: pi.amount_received || 0,
      holdAmount: holdAmountForIntent(pi),
      currency: pi.currency,
      channel: detectChannel(null, meta),
      paymentMethod: Array.isArray(pi.payment_method_types) ?
        pi.payment_method_types[0] :
        "card",
      cardBrand: null,
      cardLast4: null,
      description: pi.description || fields.resNo || fields.plate || "",
      customerEmail: fields.customerEmail,
      customerName: fields.customerName,
      resNo: fields.resNo,
      note: fields.note,
      category: fields.category,
      plate: fields.plate,
      reference: fields.reference || meta.mailOrderId || "",
      created: pi.created,
      createdAt: new Date(pi.created * 1000).toISOString(),
    });
  }

  const mailCol = db.collection("franchises").doc(franchiseId)
      .collection("stripeMailOrders");
  const mailSnap = await mailCol.orderBy("createdAt", "desc").limit(100).get();

  for (const docSnap of mailSnap.docs) {
    const row = docSnap.data() || {};
    const createdAt = row.createdAt && row.createdAt.toDate ?
      row.createdAt.toDate() :
      null;
    if (!createdAt) continue;
    const rowDayKey = new Intl.DateTimeFormat("en-CA", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(createdAt);
    if (rowDayKey !== dayKey) continue;

    const sessionId = row.stripeSessionId || row.checkoutSessionId;
    const key = sessionId || `mail_${docSnap.id}`;
    if (byKey.has(key)) continue;

    let paid = row.status === "paid";
    if (!paid && sessionId) {
      try {
        const session = await stripe.checkout.sessions.retrieve(sessionId);
        paid = session.payment_status === "paid";
        if (paid) {
          await docSnap.ref.set({status: "paid"}, {merge: true});
        }
      } catch (_) {
        /* ignore */
      }
    }

    byKey.set(key, {
      id: docSnap.id,
      paymentIntentId: null,
      chargeId: null,
      checkoutSessionId: sessionId,
      bucket: paid ? "successful" : "pending",
      status: paid ? "paid" : (row.status || "pending"),
      statusLabel: paid ? "Succeeded" : "Pending",
      amount: row.amount,
      amountReceived: paid ? row.amount : 0,
      holdAmount: 0,
      currency: row.currency || "chf",
      channel: "mail_order",
      paymentMethod: "link",
      cardBrand: "link",
      cardLast4: "",
      description: row.productName || row.note || row.description || "",
      customerEmail: row.customerEmail || "",
      customerName: row.customerName || "",
      resNo: row.resNo || row.customerReference || "",
      note: row.note || row.description || "",
      category: row.category || null,
      plate: row.plate || "",
      reference: row.resNo || row.customerReference ||
        row.productId || docSnap.id,
      created: Math.floor(createdAt.getTime() / 1000),
      createdAt: createdAt.toISOString(),
    });
  }

  const transactions = [...byKey.values()]
      .sort((a, b) => b.created - a.created);
  return {
    dayKey,
    timeZone,
    transactions,
    summary: buildSummary(transactions),
    syncedAt: new Date().toISOString(),
  };
}

module.exports = {
  localDayKeyInTimezone,
  listStripePaymentsForDay,
  CH_TIMEZONE,
  paymentBucketFromCharge,
  paymentBucketFromIntent,
  detectChannel,
};
