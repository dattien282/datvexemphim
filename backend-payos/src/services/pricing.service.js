const { firestore, Timestamp } = require('../config/firebase');

const DEFAULT_ROOM = { standardRows: 3, vipRows: 5, sweetboxRows: 2, seatsPerRow: 10 };

function rowLabelsFor(room) {
  const letters = [];
  const total = room.standardRows + room.vipRows + room.sweetboxRows;
  for (let i = 0; i < total; i++) letters.push(String.fromCharCode('A'.charCodeAt(0) + i));
  return {
    vip: letters.slice(room.standardRows, room.standardRows + room.vipRows),
    sweetbox: letters.slice(room.standardRows + room.vipRows),
  };
}

function isWeekend(showDate) {
  const s = showDate || '';
  return s.includes('Thứ Bảy') || s.includes('Chủ Nhật') || s.includes('13/06') || s.includes('14/06');
}

// Mirror của kSessionTypeSpecs (lib/models/session_type.dart) - CHỈ phần
// priceAdjustment, phải giữ khớp tuyệt đối với bảng Dart vì client hiển thị
// giá theo bảng đó còn server trừ tiền theo bảng này. Suất chiếu có
// sessionType nằm trong bảng dùng đúng mức phụ thu/giảm giá của loại đó thay
// cho công thức giờ cũ - đóng khoảng lệch "khách thấy 1 giá lúc chọn ghế, bị
// trừ giá khác lúc thanh toán" với các suất đặc biệt khi pricing_rules trống.
const SESSION_TYPE_ADJUSTMENTS = {
  'Morning': -10000,
  'Late Morning': -5000,
  'Afternoon': 0,
  'Prime Time': 0,
  'Evening': 10000,
  'Midnight': 15000,
  'Sneak Show': 20000,
  'First Day': 15000,
  'Marathon': -5000,
  'Fan Screening': 10000,
  'Special Event': 30000,
};

function timeSurcharge(showTime, sessionType) {
  if (sessionType != null && Object.prototype.hasOwnProperty.call(SESSION_TYPE_ADJUSTMENTS, sessionType)) {
    return SESSION_TYPE_ADJUSTMENTS[sessionType];
  }
  // Fallback công thức giờ cũ cho suất chiếu chưa có sessionType - khớp nhánh
  // else của ShowtimeSurcharge.fromShowAt phía Dart.
  if (!showTime) return 0;
  const hour = parseInt(showTime.split(':')[0], 10);
  if (Number.isNaN(hour)) return 0;
  if (hour < 12) return -10000;
  if (hour >= 22) return 10000;
  return 0;
}

function seatPrice(seatId, priceStandard, priceVip, rows, weekendSurcharge, timeSur) {
  const row = seatId[0];
  let base;
  if (rows.sweetbox.includes(row)) base = priceVip + 80000;
  else if (rows.vip.includes(row)) base = priceVip;
  else base = priceStandard;
  return base + weekendSurcharge + timeSur;
}

let _pricingRulesCache = null;
let _pricingRulesCacheAt = 0;

async function loadPricingRules() {
  if (!firestore) return null;
  if (_pricingRulesCache !== null && Date.now() - _pricingRulesCacheAt < 5 * 60 * 1000) {
    return _pricingRulesCache.length > 0 ? _pricingRulesCache : null;
  }
  try {
    const snap = await firestore.collection('pricing_rules').where('status', '==', 'active').get();
    _pricingRulesCache = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    _pricingRulesCacheAt = Date.now();
    return _pricingRulesCache.length > 0 ? _pricingRulesCache : null;
  } catch (e) {
    console.error('[pricing] Lỗi đọc pricing_rules:', e.message);
    return null;
  }
}

function pricingRuleMatches(rule, { showAt, sessionType, theaterName }) {
  if (rule.validFrom && showAt < rule.validFrom.toDate()) return false;
  if (rule.validTo && showAt > rule.validTo.toDate()) return false;
  if (rule.sessionType != null && rule.sessionType !== sessionType) return false;
  if (Array.isArray(rule.daysOfWeek)) {
    const dartWeekday = showAt.getDay() === 0 ? 7 : showAt.getDay();
    if (!rule.daysOfWeek.includes(dartWeekday)) return false;
  }
  if (rule.startHour != null && showAt.getHours() < rule.startHour) return false;
  if (rule.endHour != null && showAt.getHours() >= rule.endHour) return false;
  if (rule.theaterName != null && rule.theaterName !== theaterName) return false;
  return true;
}

function resolvePricingSurcharges(rules, context, basePrice) {
  const byGroup = {};
  for (const rule of rules) {
    if (!pricingRuleMatches(rule, context)) continue;
    const current = byGroup[rule.group || 'default'];
    if (!current || (rule.priority || 0) > (current.priority || 0)) {
      byGroup[rule.group || 'default'] = rule;
    }
  }
  let weekendSur = 0;
  let timeSur = 0;
  for (const [group, rule] of Object.entries(byGroup)) {
    const amount = rule.adjustmentType === 'percent'
      ? Math.floor((basePrice * (rule.adjustmentValue || 0)) / 100)
      : (rule.adjustmentValue || 0);
    if (group === 'weekend') weekendSur += amount;
    else timeSur += amount;
  }
  return { weekendSur, timeSur };
}

function parseShowDateTime(showDate, showTime) {
  try {
    const [hh, mm] = showTime.split(':').map((s) => parseInt(s, 10));
    const isoMatch = showDate.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (isoMatch) {
      return new Date(Number(isoMatch[1]), Number(isoMatch[2]) - 1, Number(isoMatch[3]), hh, mm);
    }
    const ddmmMatch = showDate.match(/\((\d{2})\/(\d{2})\)/);
    if (ddmmMatch) {
      const now = new Date();
      return new Date(now.getFullYear(), Number(ddmmMatch[2]) - 1, Number(ddmmMatch[1]), hh, mm);
    }
    return null;
  } catch (e) {
    return null;
  }
}

async function checkAgeRestriction(ticketData) {
  if (!firestore) return false;
  const movieTitle = ticketData.movieTitle || '';
  const moviesSnap = await firestore.collection('movies').where('title', '==', movieTitle).limit(1).get();
  const ageRating = moviesSnap.empty ? '' : String(moviesSnap.docs[0].data().ageRating || '').toUpperCase();
  if (ageRating !== 'T18') return true;

  const userDoc = await firestore.collection('users').doc(ticketData.userId).get();
  const userData = userDoc.data() || {};
  if (userData.ageVerified === true) return true;

  if (userData.birthDate) {
    const birth = userData.birthDate.toDate();
    const now = new Date();
    let age = now.getFullYear() - birth.getFullYear();
    if (now.getMonth() < birth.getMonth() || (now.getMonth() === birth.getMonth() && now.getDate() < birth.getDate())) age--;
    if (age >= 18) return true;
    return typeof ticketData.verifiedCccd === 'string' && /^\d{12}$/.test(ticketData.verifiedCccd);
  }

  return false;
}

async function computeAuthoritativeAmount(ticketData) {
  if (!firestore) throw new Error('Firebase Admin not initialized');
  const theaterName = ticketData.theaterName || '';
  const showDate = ticketData.showDate || '';
  const showTime = ticketData.showTime || '';
  const movieTitle = ticketData.movieTitle || '';
  const seats = Array.isArray(ticketData.seats) ? ticketData.seats : [];
  const combos = Array.isArray(ticketData.combos) ? ticketData.combos : [];

  let priceStandard = 90000;
  let priceVip = 120000;
  let room = DEFAULT_ROOM;
  const showtimeSnap = await firestore.collection('showtimes')
    .where('theaterName', '==', theaterName)
    .where('movieTitle', '==', movieTitle)
    .where('date', '==', showDate)
    .where('time', '==', showTime)
    .limit(1)
    .get();
  if (!showtimeSnap.empty) {
    const st = showtimeSnap.docs[0].data();
    priceStandard = Number(st.priceStandard) || priceStandard;
    priceVip = Number(st.priceVip) || priceVip;
    if (st.roomName) {
      const roomSnap = await firestore.collection('rooms')
        .where('theaterName', '==', theaterName)
        .where('roomName', '==', st.roomName)
        .limit(1)
        .get();
      if (!roomSnap.empty) {
        const rd = roomSnap.docs[0].data();
        room = {
          standardRows: Number(rd.standardRows) || 0,
          vipRows: Number(rd.vipRows) || 0,
          sweetboxRows: Number(rd.sweetboxRows) || 0,
          seatsPerRow: Number(rd.seatsPerRow) || 10,
        };
      }
    }
  }

  const rows = rowLabelsFor(room);

  const sessionType = showtimeSnap.empty ? null : (showtimeSnap.docs[0].data().sessionType || null);
  let weekendSur = isWeekend(showDate) ? 15000 : 0;
  let timeSur = timeSurcharge(showTime, sessionType);
  const pricingRules = await loadPricingRules();
  const showAtParsed = parseShowDateTime(showDate, showTime);
  if (pricingRules && showAtParsed) {
    const resolved = resolvePricingSurcharges(
      pricingRules,
      { showAt: showAtParsed, sessionType, theaterName },
      priceStandard,
    );
    weekendSur = resolved.weekendSur;
    timeSur = resolved.timeSur;
  }

  let seatSubtotal = 0;
  for (const seatId of seats) {
    seatSubtotal += seatPrice(String(seatId), priceStandard, priceVip, rows, weekendSur, timeSur);
  }

  if (!showtimeSnap.empty) {
    const dynPercent = Number(showtimeSnap.docs[0].data().dynamicSurchargePercent) || 0;
    if (dynPercent > 0) {
      seatSubtotal = Math.round(seatSubtotal * (1 + dynPercent / 100));
    }
  }

  let comboSubtotal = 0;
  for (const c of combos) {
    if (!c.id) {
      throw { status: 400, message: 'Combo không hợp lệ: thiếu id' };
    }
    const comboDoc = await firestore.collection('combos').doc(String(c.id)).get();
    if (!comboDoc.exists) {
      throw { status: 400, message: `Combo không hợp lệ: ${c.id}` };
    }
    const comboScope = comboDoc.data().theaterName;
    if (comboScope !== 'ALL' && comboScope !== theaterName) {
      throw { status: 400, message: `Combo không áp dụng cho rạp này: ${c.id}` };
    }
    const unitPrice = Number(comboDoc.data().price) || 0;
    comboSubtotal += unitPrice * (Number(c.quantity) || 0);
  }

  const subtotal = seatSubtotal + comboSubtotal;

  let voucherDiscount = 0;
  if (ticketData.voucherCode) {
    const voucherDoc = await firestore.collection('vouchers').doc(ticketData.voucherCode).get();
    if (voucherDoc.exists) {
      const v = voucherDoc.data();
      const now = new Date();
      const notExpired = !v.expiresAt || v.expiresAt.toDate() > now;
      const usesLeft = !v.maxUses || v.maxUses === 0 || (v.currentUses || 0) < v.maxUses;
      const theaterOk = !v.theaterScope || v.theaterScope === theaterName;
      const minOrderOk = !v.minOrder || subtotal >= v.minOrder;
      if (v.status === 'active' && notExpired && usesLeft && theaterOk && minOrderOk) {
        const pct = Number(v.discountPercent) || 0;
        voucherDiscount = pct > 0 ? Math.round((subtotal * pct) / 100) : (Number(v.discountAmount) || 0);
      }
    }
  }

  let autoDiscount = 0;
  if (ticketData.email) {
    const historySnap = await firestore.collection('tickets').where('email', '==', ticketData.email).get();
    let totalSpent = 0;
    historySnap.forEach((d) => {
      const t = d.data();
      if (t.paymentStatus === 'COMPLETED') totalSpent += Number(t.totalAmount) || 0;
    });
    let memPct = 0;
    if (totalSpent >= 8000000) memPct = 15;
    else if (totalSpent >= 3000000) memPct = 10;
    else if (totalSpent >= 1000000) memPct = 5;
    const wednesdayPct = new Date().getDay() === 3 ? 10 : 0;
    const autoPct = memPct + wednesdayPct;
    autoDiscount = Math.round((subtotal * autoPct) / 100);
  }

  let usedLoyaltyPoints = 0;
  if (ticketData.userId) {
    const requestedPoints = Number(ticketData.usedLoyaltyPoints) || 0;
    if (requestedPoints > 0) {
      const userSnap = await firestore.collection('users').doc(ticketData.userId).get();
      const currentPoints = Number(userSnap.data()?.loyalty_points) || 0;
      usedLoyaltyPoints = Math.min(requestedPoints, currentPoints);
    }
  }
  const loyaltyDiscount = usedLoyaltyPoints * 100;

  const promoDiscount = Math.max(voucherDiscount, autoDiscount);
  const finalAmount = Math.max(0, subtotal - promoDiscount - loyaltyDiscount);
  
  return { finalAmount, subtotal, voucherDiscount, autoDiscount, promoDiscount, loyaltyDiscount, usedLoyaltyPoints };
}

module.exports = {
  DEFAULT_ROOM,
  rowLabelsFor,
  isWeekend,
  timeSurcharge,
  seatPrice,
  loadPricingRules,
  pricingRuleMatches,
  resolvePricingSurcharges,
  checkAgeRestriction,
  computeAuthoritativeAmount,
  parseShowDateTime
};
