import admin from 'firebase-admin';

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

function monthRange(date) {
  const year = date.getFullYear();
  const month = date.getMonth();
  const start = new Date(year, month, 1, 0, 0, 0, 0);
  const nextMonthStart = new Date(year, month + 1, 1, 0, 0, 0, 0);
  const end = new Date(nextMonthStart.getTime() - 1);
  return { start, end };
}

function prevMonthRange(date) {
  const year = date.getFullYear();
  const month = date.getMonth();
  const prevMonthStart = new Date(year, month - 1, 1, 0, 0, 0, 0);
  const thisMonthStart = new Date(year, month, 1, 0, 0, 0, 0);
  const end = new Date(thisMonthStart.getTime() - 1);
  return { start: prevMonthStart, end };
}

function tsToDate(value) {
  if (!value) return null;
  if (value._seconds !== undefined && value._nanoseconds !== undefined) {
    return new Date(value._seconds * 1000);
  }
  if (value.seconds !== undefined) {
    return new Date(value.seconds * 1000);
  }
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate();
  }
  if (typeof value === 'number') {
    if (value > 1000000000) return new Date(value * 1000);
    const ref = new Date('2001-01-01T00:00:00Z').getTime();
    return new Date(ref + value * 1000);
  }
  return new Date(value);
}

async function main() {
  const now = new Date();
  const { start: curStart, end: curEnd } = monthRange(now);
  const { start: prevStart, end: prevEnd } = prevMonthRange(now);

  console.log('Current month range:', curStart.toISOString(), '→', curEnd.toISOString());
  console.log('Previous month range:', prevStart.toISOString(), '→', prevEnd.toISOString());

  const snapshot = await db
    .collection('araclar')
    .where('franchiseId', '==', 'CH')
    .get();

  let currentCount = 0;
  let prevCount = 0;

  snapshot.forEach((doc) => {
    const data = doc.data();
    if (data.isDeleted) return;
    const damages = Array.isArray(data.hasarKayitlari) ? data.hasarKayitlari : [];
    damages.forEach((hasar, idx) => {
      const d = tsToDate(hasar.tarih);
      if (!d || Number.isNaN(d.getTime())) return;
      if (d >= curStart && d <= curEnd) {
        currentCount += 1;
      } else if (d >= prevStart && d <= prevEnd) {
        prevCount += 1;
      }
    });
  });

  console.log('Damage counts for franchiseId=CH');
  console.log('Current month total :', currentCount);
  console.log('Previous month total:', prevCount);
}

main().catch((err) => {
  console.error('Error counting damages', err);
  process.exitCode = 1;
});

