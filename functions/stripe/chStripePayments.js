/**
 * CH Stripe: mail-order payment links + chargeback (dispute) sync.
 * Secret: Firebase secret STRIPE_CH_SECRET_KEY.
 * Publishable key: franchises/CH/stripeConfig/public.
 */

const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const {defineSecret} = require("firebase-functions/params");
const {onCall, onRequest, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");

const stripeCHSecretKey = defineSecret("STRIPE_CH_SECRET_KEY");
const stripeCHWebhookSecret = defineSecret("STRIPE_CH_WEBHOOK_SECRET");

const REGION = "europe-west6";
const DEFAULT_FRANCHISE = "CH";

/** @return {object} Stripe SDK client */
function getStripeClient() {
  const Stripe = require("stripe");
  const key = String(stripeCHSecretKey.value() || "").trim();
  if (!key) {
    throw new HttpsError(
        "failed-precondition",
        "STRIPE_CH_SECRET_KEY is not configured",
    );
  }
  return new Stripe(key, {apiVersion: "2024-11-20.acacia"});
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} franchiseId
 * @return {FirebaseFirestore.DocumentReference}
 */
function publicConfigRef(db, franchiseId) {
  return db.collection("franchises").doc(franchiseId)
      .collection("stripeConfig").doc("public");
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} franchiseId
 * @return {FirebaseFirestore.CollectionReference}
 */
function mailOrdersCol(db, franchiseId) {
  return db.collection("franchises").doc(franchiseId)
      .collection("stripeMailOrders");
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} franchiseId
 * @return {FirebaseFirestore.CollectionReference}
 */
function disputesCol(db, franchiseId) {
  return db.collection("franchises").doc(franchiseId)
      .collection("stripeDisputes");
}

/**
 * @param {string} raw
 * @return {string}
 */
function canonicalResNo(raw) {
  let s = String(raw || "").trim().toUpperCase();
  if (s.startsWith("RES-")) {
    s = s.slice(4);
  } else if (s.startsWith("RES")) {
    s = s.slice(3).replace(/^[-_\s]+/, "");
  }
  const digits = s.replace(/\D/g, "");
  return digits ? `RES-${digits}` : "";
}

/**
 * @param {string} email
 * @return {boolean}
 */
function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(email || "").trim());
}

/**
 * @param {string} category
 * @return {boolean}
 */
function isValidMailOrderCategory(category) {
  return category === "traffic_fine" || category === "damage";
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} franchiseId
 * @param {object} payload
 * @return {Promise<void>}
 */
async function upsertDisputeDoc(db, franchiseId, payload) {
  const id = payload.id;
  if (!id) return;
  await disputesCol(db, franchiseId).doc(id).set({
    ...payload,
    franchiseId,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}

/**
 * @param {object} db Firestore
 * @param {string} franchiseId
 * @param {object} stripe Stripe client
 * @param {number} daysBack
 * @return {Promise<number>}
 */
async function syncDisputesForFranchise(
    db, franchiseId, stripe, daysBack = 180,
) {
  const since = Math.floor(Date.now() / 1000) - daysBack * 24 * 60 * 60;
  let synced = 0;
  const disputes = await stripe.disputes.list({
    limit: 100,
    created: {gte: since},
  });

  for (const dispute of disputes.data) {
    let charge = null;
    try {
      if (typeof dispute.charge === "string") {
        charge = await stripe.charges.retrieve(dispute.charge);
      }
    } catch (e) {
      console.warn("dispute charge retrieve", dispute.id, e.message);
    }

    const card = charge &&
      charge.payment_method_details &&
      charge.payment_method_details.card ?
      charge.payment_method_details.card :
      null;

    await upsertDisputeDoc(db, franchiseId, {
      id: dispute.id,
      stripeDisputeId: dispute.id,
      stripeChargeId: typeof dispute.charge === "string" ?
        dispute.charge :
        null,
      amount: dispute.amount,
      currency: dispute.currency,
      status: dispute.status,
      reason: dispute.reason || "",
      paymentMethod: card ? "card" : "unknown",
      cardBrand: card ? card.brand : null,
      cardLast4: card ? card.last4 : null,
      customerReference: (charge && charge.metadata &&
        charge.metadata.customerReference) || "",
      plate: (charge && charge.metadata && charge.metadata.plate) || "",
      evidenceDueBy: dispute.evidence_details &&
        dispute.evidence_details.due_by ?
        admin.firestore.Timestamp.fromMillis(
            dispute.evidence_details.due_by * 1000,
        ) :
        null,
      createdAt: admin.firestore.Timestamp.fromMillis(dispute.created * 1000),
    });
    synced += 1;
  }
  return synced;
}

/**
 * @param {string} franchiseId
 * @return {Promise<object>}
 */
async function readSmtpConfig(franchiseId) {
  const db = admin.firestore();
  const docId = String(franchiseId || "CH").toUpperCase();
  const snap = await db.collection("smtpConfigurations").doc(docId).get();
  if (!snap.exists) return null;
  return snap.data();
}

/**
 * @param {object} smtp
 * @param {string} franchiseId
 * @return {string}
 */
function resolveSmtpPassword(smtp, franchiseId) {
  const normalized = String(franchiseId || "CH").toUpperCase();
  const candidates = [
    `SMTP_PASSWORD_${normalized}`,
    "SMTP_PASSWORD_CH",
  ];
  for (const name of candidates) {
    const val = process.env[name];
    if (val && String(val).trim()) return String(val).trim();
  }
  return String(smtp.password || "").trim();
}

/**
 * @param {object} params
 * @return {Promise<void>}
 */
async function sendMailOrderEmail(params) {
  const {
    franchiseId,
    to,
    customerName,
    amountChf,
    paymentUrl,
    resNo,
    category,
    note,
  } = params;
  const smtp = await readSmtpConfig(franchiseId);
  if (!smtp || !String(smtp.host || "").trim()) {
    throw new HttpsError("failed-precondition", "SMTP not configured for CH");
  }
  const password = resolveSmtpPassword(smtp, franchiseId);
  const transport = nodemailer.createTransport({
    host: smtp.host,
    port: smtp.port || 587,
    secure: smtp.useTLS === true && smtp.port === 465,
    auth: {user: smtp.username, pass: password},
  });

  const amountText = (amountChf / 100).toFixed(2);
  const greeting = customerName ? `Dear ${customerName},` : "Dear Customer,";
  const categoryLine = category ?
    `\nCategory: ${category === "traffic_fine" ? "Traffic fine" : "Damage"}` :
    "";
  const resLine = resNo ? `\nRES: ${resNo}` : "";
  const noteLine = note ? `\n${note}` : "";
  const textBody = `${greeting}

Please complete your payment of CHF ${amountText} using the secure link below:
${paymentUrl}
${categoryLine}${resLine}${noteLine}

This link is hosted by Stripe. If you have questions, contact our office.

Green Motion Switzerland`;

  const wrapperStyle = [
    "font-family:Arial,Helvetica,sans-serif",
    "font-size:14px",
    "line-height:1.55",
    "color:#111",
  ].join(";");
  const categoryLabel = category === "traffic_fine" ?
    "Traffic fine" :
    (category === "damage" ? "Damage" : "");
  const htmlBody = `
    <div style="${wrapperStyle}">
      <p>${greeting}</p>
      <p>Please complete your payment of <strong>CHF ${amountText}</strong>
      using the secure link below:</p>
      <p><a href="${paymentUrl}">${paymentUrl}</a></p>
      ${categoryLabel ? `<p>Category: ${categoryLabel}</p>` : ""}
      ${resNo ? `<p>RES: ${resNo}</p>` : ""}
      ${note ? `<p>${note}</p>` : ""}
      <p style="color:#6b7280;font-size:12px;margin-top:16px">
        This link is hosted by Stripe. Please do not reply to this email.
      </p>
    </div>`;

  const senderName = String(smtp.senderName || "Green Motion").trim();
  await transport.sendMail({
    from: `"${senderName}" <${smtp.senderEmail}>`,
    to,
    subject: `Payment request — CHF ${amountText}${resNo ? ` (${resNo})` : ""}`,
    text: textBody,
    html: htmlBody,
  });
}

/**
 * @param {object} event Stripe webhook event
 * @param {object} db Firestore
 * @param {string} franchiseId
 * @return {Promise<void>}
 */
async function handleWebhookEvent(event, db, franchiseId) {
  const type = event.type;
  const obj = event.data && event.data.object ? event.data.object : null;
  if (!obj) return;

  if (type.startsWith("charge.dispute.")) {
    const stripe = getStripeClient();
    await syncDisputesForFranchise(db, franchiseId, stripe, 365);
    return;
  }

  if (type === "checkout.session.completed") {
    const session = obj;
    const mailOrderId = session.metadata && session.metadata.mailOrderId;
    if (mailOrderId) {
      await mailOrdersCol(db, franchiseId).doc(mailOrderId).set({
        status: "paid",
        stripeSessionId: session.id,
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
        paymentMethod: "link",
      }, {merge: true});
    }
  }
}

const stripeOpts = {
  region: REGION,
  secrets: [stripeCHSecretKey],
};

const webhookOpts = {
  region: REGION,
  secrets: [stripeCHSecretKey, stripeCHWebhookSecret],
};

/**
 * Returns publishable key + mode from Firestore (no secret).
 */
const getCHStripePublicConfig = onCall(stripeOpts, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }
  const franchiseId = String(
      (request.data && request.data.franchiseId) || DEFAULT_FRANCHISE,
  ).toUpperCase();
  const snap = await publicConfigRef(admin.firestore(), franchiseId).get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Stripe public config missing");
  }
  const data = snap.data();
  return {
    franchiseId,
    publishableKey: data.publishableKey || "",
    mode: data.mode || "live",
  };
});

/** Creates Stripe Checkout Session (mail order); optional email. */
const createCHMailOrderPaymentLink = onCall(stripeOpts, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }
  const data = request.data || {};
  const franchiseId = String(
      data.franchiseId || DEFAULT_FRANCHISE,
  ).toUpperCase();
  const amountChf = Math.round(Number(data.amountChf || 0) * 100);
  const customerEmail = String(data.customerEmail || "").trim();
  const customerName = String(data.customerName || "").trim();
  const category = String(data.category || "").trim();
  const resNo = canonicalResNo(data.resNo || data.customerReference || "");
  const note = String(data.note || data.description || "").trim();
  const sendEmail = data.sendEmail === true;

  if (amountChf < 50) {
    throw new HttpsError(
        "invalid-argument",
        "Minimum amount is CHF 0.50",
    );
  }
  if (!isValidMailOrderCategory(category)) {
    throw new HttpsError(
        "invalid-argument",
        "Payment category is required (traffic_fine or damage)",
    );
  }
  if (!resNo) {
    throw new HttpsError(
        "invalid-argument",
        "RES code is required (RES-xxxx format)",
    );
  }
  if (!customerName) {
    throw new HttpsError("invalid-argument", "Customer name is required");
  }
  if (!customerEmail) {
    throw new HttpsError("invalid-argument", "Customer email is required");
  }
  if (!isValidEmail(customerEmail)) {
    throw new HttpsError("invalid-argument", "Invalid customer email");
  }
  if (sendEmail && !customerEmail) {
    throw new HttpsError(
        "invalid-argument",
        "Customer email required to send payment link",
    );
  }

  const categoryLabel = category === "traffic_fine" ?
    "Traffic fine" :
    "Damage";
  const productName = `${categoryLabel} — ${resNo}`;

  const db = admin.firestore();
  const stripe = getStripeClient();
  const mailOrderRef = mailOrdersCol(db, franchiseId).doc();
  const mailOrderId = mailOrderRef.id;

  const session = await stripe.checkout.sessions.create({
    mode: "payment",
    currency: "chf",
    line_items: [{
      quantity: 1,
      price_data: {
        currency: "chf",
        unit_amount: amountChf,
        product_data: {
          name: productName,
          description: note || categoryLabel,
        },
      },
    }],
    customer_email: customerEmail,
    metadata: {
      franchiseId,
      mailOrderId,
      category,
      resNo,
      customerReference: resNo,
      customerName,
      customerEmail,
      note,
      createdBy: request.auth.uid,
    },
    payment_intent_data: {
      metadata: {
        franchiseId,
        mailOrderId,
        category,
        resNo,
        customerReference: resNo,
        customerName,
        customerEmail,
        note,
        flow: "mail_order",
        mailOrder: "true",
      },
    },
    success_url: "https://greenmotion.ch/payment-success",
    cancel_url: "https://greenmotion.ch/payment-cancelled",
  });

  const paymentUrl = session.url;
  if (!paymentUrl) {
    throw new HttpsError("internal", "Stripe did not return a payment URL");
  }

  await mailOrderRef.set({
    franchiseId,
    mailOrderId,
    amount: amountChf,
    currency: "chf",
    status: "pending",
    paymentUrl,
    stripeSessionId: session.id,
    category,
    resNo,
    customerReference: resNo,
    customerEmail,
    customerName,
    note,
    description: note,
    paymentMethod: "link",
    createdBy: request.auth.uid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  let emailSent = false;
  if (sendEmail) {
    await sendMailOrderEmail({
      franchiseId,
      to: customerEmail,
      customerName,
      amountChf,
      paymentUrl,
      resNo,
      category,
      note,
    });
    emailSent = true;
    await mailOrderRef.update({
      emailSent: true,
      emailSentAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  return {
    franchiseId,
    mailOrderId,
    paymentUrl,
    emailSent,
    stripeSessionId: session.id,
  };
});

/**
 * Sync chargebacks / disputes from Stripe.
 */
const syncCHStripeDisputes = onCall(stripeOpts, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }
  const franchiseId = String(
      (request.data && request.data.franchiseId) || DEFAULT_FRANCHISE,
  ).toUpperCase();
  const db = admin.firestore();
  const stripe = getStripeClient();
  const synced = await syncDisputesForFranchise(db, franchiseId, stripe);
  return {franchiseId, synced};
});

const stripeCHWebhook = onRequest(
    {...webhookOpts, cors: false},
    async (req, res) => {
      if (req.method !== "POST") {
        res.status(405).send("Method Not Allowed");
        return;
      }
      const stripe = getStripeClient();
      const sig = req.headers["stripe-signature"];
      const webhookSecret = String(stripeCHWebhookSecret.value() || "").trim();
      let event;
      try {
        if (!webhookSecret) {
          throw new Error("STRIPE_CH_WEBHOOK_SECRET not configured");
        }
        event = stripe.webhooks.constructEvent(req.rawBody, sig, webhookSecret);
      } catch (err) {
        console.error("stripe webhook verify", err.message);
        res.status(400).send(`Webhook Error: ${err.message}`);
        return;
      }
      try {
        await handleWebhookEvent(event, admin.firestore(), DEFAULT_FRANCHISE);
        res.json({received: true});
      } catch (err) {
        console.error("stripe webhook handler", err);
        res.status(500).send("Webhook handler failed");
      }
    },
);

const scheduledCHStripeDisputeSync = onSchedule(
    {
      schedule: "every 6 hours",
      region: REGION,
      secrets: [stripeCHSecretKey],
    },
    async () => {
      const db = admin.firestore();
      const stripe = getStripeClient();
      const synced = await syncDisputesForFranchise(
          db, DEFAULT_FRANCHISE, stripe,
      );
      console.log("scheduledCHStripeDisputeSync", {synced});
    },
);

const {listStripePaymentsForDay, localDayKeyInTimezone} =
  require("./chStripePaymentListing");
const {aggregateStripeDailyReports} = require("./chStripeDailyReports");

/** Daily reports — KPIs + daily series for a date range (CH). */
const getCHStripeDailyReports = onCall(stripeOpts, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }
  const data = request.data || {};
  const franchiseId = String(
      data.franchiseId || DEFAULT_FRANCHISE,
  ).toUpperCase();
  const period = String(data.period || "7d").trim();
  const stripe = getStripeClient();
  const db = admin.firestore();
  return aggregateStripeDailyReports(stripe, franchiseId, period, db);
});

/** Daily closing — Stripe payments for one local day (CH). */
const listCHStripeDailyClosing = onCall(stripeOpts, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }
  const data = request.data || {};
  const franchiseId = String(
      data.franchiseId || DEFAULT_FRANCHISE,
  ).toUpperCase();
  const dayKey = String(
      data.dayKey || localDayKeyInTimezone("Europe/Zurich"),
  ).trim();
  const stripe = getStripeClient();
  const db = admin.firestore();
  return listStripePaymentsForDay(stripe, franchiseId, dayKey, db);
});

/**
 * Capture or increment-capture an authorised deposit (terminal hold).
 * Uses saved customer + payment_method from the original PaymentIntent.
 */
const increaseCHStripeDepositHold = onCall(stripeOpts, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }
  const data = request.data || {};
  const franchiseId = String(
      data.franchiseId || DEFAULT_FRANCHISE,
  ).toUpperCase();
  const paymentIntentId = String(data.paymentIntentId || "").trim();
  const captureAmountMinor = Math.round(Number(data.amountChf || 0) * 100);

  if (!paymentIntentId.startsWith("pi_")) {
    throw new HttpsError("invalid-argument", "paymentIntentId is required");
  }
  if (captureAmountMinor < 50) {
    throw new HttpsError(
        "invalid-argument",
        "Minimum capture amount is CHF 0.50",
    );
  }

  const stripe = getStripeClient();
  let pi = await stripe.paymentIntents.retrieve(paymentIntentId, {
    expand: ["payment_method", "customer"],
  });

  const meta = pi.metadata || {};
  if (meta.franchiseId &&
    String(meta.franchiseId).toUpperCase() !== franchiseId) {
    throw new HttpsError("permission-denied", "Franchise mismatch");
  }

  if (pi.status !== "requires_capture") {
    throw new HttpsError(
        "failed-precondition",
        `PaymentIntent is not capturable (status: ${pi.status})`,
    );
  }

  const capturable = Number(pi.amount_capturable) || 0;
  if (captureAmountMinor > capturable) {
    try {
      pi = await stripe.paymentIntents.incrementAuthorization(
          paymentIntentId,
          {amount: captureAmountMinor},
      );
    } catch (incErr) {
      const customerId = typeof pi.customer === "string" ?
        pi.customer :
        (pi.customer && pi.customer.id ? pi.customer.id : null);
      const paymentMethodId = typeof pi.payment_method === "string" ?
        pi.payment_method :
        (pi.payment_method && pi.payment_method.id ?
          pi.payment_method.id :
          null);

      if (!customerId || !paymentMethodId) {
        throw new HttpsError(
            "failed-precondition",
            `Cannot increase hold: ${incErr.message}`,
        );
      }

      const additionalMinor = captureAmountMinor - capturable;
      const offSession = await stripe.paymentIntents.create({
        amount: additionalMinor,
        currency: pi.currency || "chf",
        customer: customerId,
        payment_method: paymentMethodId,
        off_session: true,
        confirm: true,
        capture_method: "automatic",
        metadata: {
          ...meta,
          franchiseId,
          parentPaymentIntentId: paymentIntentId,
          flow: "deposit_increase",
        },
      });

      if (capturable > 0) {
        await stripe.paymentIntents.capture(paymentIntentId, {
          amount_to_capture: capturable,
        });
      }

      return {
        franchiseId,
        paymentIntentId,
        additionalPaymentIntentId: offSession.id,
        capturedAmount: capturable + additionalMinor,
        currency: pi.currency || "chf",
        status: offSession.status,
        method: "off_session_charge",
      };
    }
  }

  const captured = await stripe.paymentIntents.capture(paymentIntentId, {
    amount_to_capture: captureAmountMinor,
  });

  return {
    franchiseId,
    paymentIntentId: captured.id,
    capturedAmount: captured.amount_received || captureAmountMinor,
    currency: captured.currency,
    status: captured.status,
    method: captureAmountMinor > capturable ? "increment_capture" : "capture",
  };
});

module.exports = {
  getCHStripePublicConfig,
  createCHMailOrderPaymentLink,
  increaseCHStripeDepositHold,
  syncCHStripeDisputes,
  stripeCHWebhook,
  scheduledCHStripeDisputeSync,
  getCHStripeDailyReports,
  listCHStripeDailyClosing,
};
