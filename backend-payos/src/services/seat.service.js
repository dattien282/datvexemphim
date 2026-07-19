const { firestore } = require('../config/firebase');

function rowLabelsForLayout(layout) {
  const standardRows = Number(layout.standardRows) || 0;
  const vipRows = Number(layout.vipRows) || 0;
  const sweetboxRows = Number(layout.sweetboxRows) || 0;
  const total = standardRows + vipRows;
  const vipRowLabels = [];
  for (let i = standardRows; i < total; i++) vipRowLabels.push(String.fromCharCode(65 + i));
  const sweetboxRowLabels = [];
  for (let i = 0; i < sweetboxRows; i++) sweetboxRowLabels.push(String.fromCharCode(65 + total + i));
  return { vipRowLabels, sweetboxRowLabels };
}

function seatTypeAndPrice(seatId, layout) {
  const row = seatId[0];
  const { vipRowLabels, sweetboxRowLabels } = rowLabelsForLayout(layout);
  const priceStandard = Number(layout.priceStandard) || 90000;
  const priceVip = Number(layout.priceVip) || 120000;
  if (sweetboxRowLabels.includes(row)) return { seatType: 'sweetbox', price: priceVip * 2 };
  if (vipRowLabels.includes(row)) return { seatType: 'vip', price: priceVip };
  return { seatType: 'standard', price: priceStandard };
}

async function resolveLayoutForShowtime(showtimeDoc) {
  if (!firestore) return null;
  const st = showtimeDoc.data();
  let layout = null;
  if (st.seatMapVersionId) {
    const versionDoc = await firestore.collection('seat_map_versions').doc(st.seatMapVersionId).get();
    if (versionDoc.exists) layout = versionDoc.data();
  }
  if (!layout) {
    const roomSnap = await firestore.collection('rooms')
      .where('theaterName', '==', st.theaterName).where('roomName', '==', st.roomName).limit(1).get();
    if (!roomSnap.empty) layout = roomSnap.docs[0].data();
  }
  layout = layout || { standardRows: 8, vipRows: 6, sweetboxRows: 0, seatsPerRow: 10 };
  return { ...layout, priceStandard: st.priceStandard || 90000, priceVip: st.priceVip || 120000 };
}

async function resolveLayoutForCreation(seatMapVersionId, theaterName, roomName) {
  if (!firestore) return null;
  if (seatMapVersionId) {
    const versionDoc = await firestore.collection('seat_map_versions').doc(seatMapVersionId).get();
    if (versionDoc.exists) return versionDoc.data();
  }
  const roomSnap = await firestore.collection('rooms')
    .where('theaterName', '==', theaterName).where('roomName', '==', roomName).limit(1).get();
  if (!roomSnap.empty) return roomSnap.docs[0].data();
  return { standardRows: 3, vipRows: 5, sweetboxRows: 2, seatsPerRow: 10, brokenSeats: [] };
}

function generateSeatIdsForLayout(layout) {
  const standardRows = Number(layout.standardRows) || 0;
  const vipRows = Number(layout.vipRows) || 0;
  const sweetboxRows = Number(layout.sweetboxRows) || 0;
  const seatsPerRow = Number(layout.seatsPerRow) || 10;
  const ids = [];
  const totalSingleRows = standardRows + vipRows;
  for (let i = 0; i < totalSingleRows; i++) {
    const row = String.fromCharCode(65 + i);
    for (let s = 0; s < seatsPerRow; s++) ids.push(`${row}${s + 1}`);
  }
  for (let i = 0; i < sweetboxRows; i++) {
    const row = String.fromCharCode(65 + totalSingleRows + i);
    for (let p = 0; p < Math.floor(seatsPerRow / 2); p++) ids.push(`${row}${p * 2 + 1}-${row}${p * 2 + 2}`);
  }
  return ids;
}

async function generateSeatsForShowtime(showtimeId, layout, priceStandard, priceVip) {
  if (!firestore) return;
  const seatIds = generateSeatIdsForLayout(layout);
  const brokenSeats = new Set((layout.brokenSeats || []).map(String));
  const layoutWithPrice = { ...layout, priceStandard, priceVip };
  const chunkSize = 450;
  for (let i = 0; i < seatIds.length; i += chunkSize) {
    const batch = firestore.batch();
    for (const seatId of seatIds.slice(i, i + chunkSize)) {
       const { seatType, price } = seatTypeAndPrice(seatId, layoutWithPrice);
       const ref = firestore.collection('showtimes').doc(showtimeId).collection('seats').doc(seatId);
       batch.set(ref, {
         seatType, price,
         status: brokenSeats.has(seatId) ? 'UNAVAILABLE' : 'AVAILABLE',
         holdToken: null, heldBy: null, heldUntil: null, bookingId: null, version: 0,
       });
    }
    await batch.commit();
  }
}

function parseReleaseDateJs(releaseDate) {
  if (!releaseDate) return null;
  const m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(String(releaseDate).trim());
  if (!m) return null;
  return new Date(parseInt(m[3], 10), parseInt(m[2], 10) - 1, parseInt(m[1], 10));
}

function detectSessionTypeJs(showAt, movieReleaseDate) {
  if (movieReleaseDate) {
    const showDate = new Date(showAt.getFullYear(), showAt.getMonth(), showAt.getDate());
    const releaseDate = new Date(movieReleaseDate.getFullYear(), movieReleaseDate.getMonth(), movieReleaseDate.getDate());
    if (showDate.getTime() < releaseDate.getTime()) return 'Sneak Show';
    if (showDate.getTime() === releaseDate.getTime()) return 'First Day';
  }
  const hour = showAt.getHours();
  if (hour < 7) return 'Midnight';
  if (hour < 10) return 'Morning';
  if (hour < 12) return 'Late Morning';
  if (hour < 17) return 'Afternoon';
  if (hour < 21) return 'Prime Time';
  return 'Evening';
}

const FALLBACK_SHOWTIME_DURATION_MS = 150 * 60 * 1000;

function roomReleaseAtJs(showAt, movieDurationMs, advertisingMin, exitBufferMin, cleaningMin) {
  return new Date(showAt.getTime() + (advertisingMin || 0) * 60000 + movieDurationMs + ((exitBufferMin ?? 10) + (cleaningMin || 0)) * 60000);
}

function overlapsWindowJs(a, b, movieDurationMs) {
  const aEnd = roomReleaseAtJs(a.showAt, movieDurationMs, a.advertisingMinutes, a.exitBufferMinutes, a.cleaningMinutes);
  const bEnd = roomReleaseAtJs(b.showAt, movieDurationMs, b.advertisingMinutes, b.exitBufferMinutes, b.cleaningMinutes);
  return a.showAt.getTime() < bEnd.getTime() && b.showAt.getTime() < aEnd.getTime();
}

module.exports = {
  rowLabelsForLayout,
  seatTypeAndPrice,
  resolveLayoutForShowtime,
  resolveLayoutForCreation,
  generateSeatIdsForLayout,
  generateSeatsForShowtime,
  parseReleaseDateJs,
  detectSessionTypeJs,
  FALLBACK_SHOWTIME_DURATION_MS,
  roomReleaseAtJs,
  overlapsWindowJs
};
