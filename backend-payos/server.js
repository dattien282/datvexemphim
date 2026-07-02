const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const { PayOS } = require('@payos/node');
const { GoogleGenerativeAI } = require('@google/generative-ai');
// firebase-admin v14 dùng API dạng module (không còn admin.credential.cert()/
// admin.firestore()/admin.auth() kiểu namespace cũ của v11 trở xuống).
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore, Timestamp, FieldValue } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
require('dotenv').config();

const app = express();
const port = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// Khởi tạo đối tượng PayOS với các cấu hình từ .env
const payos = new PayOS({
  clientId: process.env.PAYOS_CLIENT_ID,
  apiKey: process.env.PAYOS_API_KEY,
  checksumKey: process.env.PAYOS_CHECKSUM_KEY
});

// Khởi tạo Firebase Admin SDK để cập nhật trạng thái vé trong webhook.
// BƯỚC THỦ CÔNG BẮT BUỘC: tải serviceAccountKey.json từ Firebase Console
// (Project Settings > Service accounts > Generate new private key) và đặt
// vào backend-payos/serviceAccountKey.json (đã thêm vào .gitignore).
let firestore = null;
let auth = null;
try {
  const serviceAccount = require('./serviceAccountKey.json');
  initializeApp({ credential: cert(serviceAccount) });
  firestore = getFirestore();
  auth = getAuth();
  console.log('✅ Firebase Admin SDK initialized.');
} catch (e) {
  console.warn('⚠️  Firebase Admin SDK init failed - webhook will NOT update Firestore ticket status.');
  console.warn('    Lỗi:', e.message);
  console.warn('    Kiểm tra backend-payos/serviceAccountKey.json có tồn tại và hợp lệ không.');
}

// Gemini API key giờ chỉ tồn tại ở server, không còn được gửi xuống app
// Flutter dưới bất kỳ hình thức nào (trước đây app đọc key này từ Firestore
// configs/gemini về máy khách để tự gọi Gemini - key có thể bị trích xuất
// bằng cách bắt gói tin/reverse-engineer app, dùng ké quota của dự án).
// Client giờ chỉ gọi /gemini-chat, server giữ key và gọi Gemini hộ.
//
// Key ưu tiên đọc từ Firestore configs/server_config (admin sửa qua UI
// AdminServerConfigScreen, không cần restart server) - rơi về biến môi
// trường .env nếu Firestore chưa có/chưa cấu hình. Cache 60 giây để không
// phải đọc Firestore trên mỗi tin nhắn chat.
let _geminiConfigCache = { key: null, fetchedAt: 0 };
async function getGeminiApiKey() {
  const now = Date.now();
  if (_geminiConfigCache.key && now - _geminiConfigCache.fetchedAt < 60000) {
    return _geminiConfigCache.key;
  }
  let key = process.env.GEMINI_API_KEY || '';
  if (firestore) {
    try {
      const doc = await firestore.collection('configs').doc('server_config').get();
      const configuredKey = doc.data()?.geminiApiKey;
      if (configuredKey) key = configuredKey;
    } catch (e) {
      console.warn('Không đọc được configs/server_config từ Firestore:', e.message);
    }
  }
  _geminiConfigCache = { key, fetchedAt: now };
  return key;
}
async function getGeminiClient() {
  const key = await getGeminiApiKey();
  return key ? new GoogleGenerativeAI(key) : null;
}
const GEMINI_SYSTEM_INSTRUCTION =
  "Bạn là Trợ lý ảo AI lịch sự và chuyên nghiệp của hệ thống rạp phim Stella Cinema. " +
  "Quy tắc giao tiếp bắt buộc:\n" +
  "1. Luôn xưng hô với khách hàng lịch sự là 'bạn' (ví dụ: 'chào bạn', 'bạn chọn phim gì', 'bạn cần trợ giúp gì'). Tự xưng là 'Stella' hoặc 'tôi'. Tuyệt đối tránh dùng các từ ngữ thân mật quá mức hoặc suồng sã như 'ní'.\n" +
  "2. Phong cách trả lời: Lịch sự, chuyên nghiệp, hỗ trợ tận tình, dùng emoji phù hợp.\n" +
  "3. Trả lời súc tích, ngắn gọn (trong khoảng 2-4 câu), trừ khi được yêu cầu liệt kê bảng giá hoặc địa điểm.\n" +
  "4. Luôn dựa trên dữ liệu thực tế được cung cấp trong prompt để tư vấn, không tự bịa tên phim khác đang chiếu.";

// Secret dùng để ký/verify QR vé (HMAC-SHA256). BẮT BUỘC đặt TICKET_SIGNING_SECRET
// trong backend-payos/.env cho môi trường thật - giá trị mặc định dưới đây chỉ để
// server không crash khi thiếu cấu hình lúc dev, KHÔNG an toàn cho production.
const TICKET_SIGNING_SECRET = process.env.TICKET_SIGNING_SECRET || 'dev-only-insecure-secret-change-me';

function signTicket(ticketId, orderCode, paymentStatus) {
  const payload = `${ticketId}:${orderCode || ''}:${paymentStatus}`;
  return crypto.createHmac('sha256', TICKET_SIGNING_SECRET).update(payload).digest('hex');
}

// Xác thực Firebase ID token gửi qua header Authorization: Bearer <token>,
// gắn req.staffUid + req.staffRole (đọc từ users/{uid}.role) nếu hợp lệ.
async function requireStaffAuth(req, res, next) {
  if (!firestore) {
    return res.status(503).json({ success: false, message: 'Server chưa cấu hình Firebase Admin SDK' });
  }
  const authHeader = req.headers.authorization || '';
  const idToken = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
  if (!idToken) {
    return res.status(401).json({ success: false, message: 'Thiếu token xác thực' });
  }
  try {
    const decoded = await auth.verifyIdToken(idToken);
    const userDoc = await firestore.collection('users').doc(decoded.uid).get();
    const userData = userDoc.data() || {};
    const role = userData.role;
    const hasStaffAccess = role === 'staff' || role === 'theater_manager' || role === 'admin' || userData.isAdmin === true;
    if (!hasStaffAccess) {
      return res.status(403).json({ success: false, message: 'Tài khoản không có quyền soát vé' });
    }
    req.staffUid = decoded.uid;
    req.staffTheater = userData.assignedTheater || null;
    next();
  } catch (e) {
    return res.status(401).json({ success: false, message: 'Token không hợp lệ' });
  }
}

// Xác thực Firebase ID token cho user thường (không yêu cầu role staff trở
// lên) - dùng cho các API mà khách hàng tự gọi, ví dụ hủy vé.
async function requireAuth(req, res, next) {
  if (!firestore) {
    return res.status(503).json({ success: false, message: 'Server chưa cấu hình Firebase Admin SDK' });
  }
  const authHeader = req.headers.authorization || '';
  const idToken = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
  if (!idToken) {
    return res.status(401).json({ success: false, message: 'Thiếu token xác thực' });
  }
  try {
    const decoded = await auth.verifyIdToken(idToken);
    req.userUid = decoded.uid;
    req.userEmail = decoded.email || null;
    next();
  } catch (e) {
    return res.status(401).json({ success: false, message: 'Token không hợp lệ' });
  }
}

app.get('/', (req, res) => {
  res.send('✅ Stella Cinema PayOS Backend is running!');
});

// Bảng giá combo - phải khớp với _combos trong
// lib/features/booking_and_payment/screens/combo_selection_screen.dart.
// Dùng để tính lại tiền combo ở server thay vì tin số client gửi lên.
const COMBO_PRICES = {
  solo: 75000,
  couple: 110000,
  premium: 160000,
  popcorn_sweet: 35000,
  popcorn_cheese: 45000,
  pepsi: 30000,
};

// Layout phòng mặc định - phải khớp với seat_booking_screen.dart khi chưa
// tìm thấy room doc thật (showtime cũ/dự phòng chưa gắn phòng cụ thể).
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

// Cùng công thức +15k cuối tuần / -10k suất sớm / +10k suất khuya như
// seat_booking_screen.dart (_isWeekend/_getTimeSurcharge) - cố tình giữ y hệt
// cách nhận diện cuối tuần hiện tại của client (kể cả phần chỉ khớp chuỗi
// tiếng Việt 'Thứ Bảy'/'Chủ Nhật', không áp dụng cho showtime ISO 'yyyy-MM-dd')
// để không vô tình từ chối thanh toán hợp lệ do lệch công thức hai bên.
function isWeekend(showDate) {
  const s = showDate || '';
  return s.includes('Thứ Bảy') || s.includes('Chủ Nhật') || s.includes('13/06') || s.includes('14/06');
}
function timeSurcharge(showTime) {
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

// Kiểm tra lại giới hạn tuổi (phim T18) ở server - trước đây cổng này chỉ
// nằm ở payment_screen.dart (client), nghĩa là sửa app hoặc gọi thẳng API
// /create-payment-link là bỏ qua được hoàn toàn, kể cả vé PENDING tạo trực
// tiếp qua Firestore SDK. Mirror đúng logic client: cho qua nếu phim không
// phải T18, hoặc user đã có ageVerified (admin duyệt CCCD), hoặc birthDate
// tính ra >=18, hoặc đã cung cấp verifiedCccd (12 số, xác minh mềm như phía
// client vốn cho phép khi khai gian tuổi).
async function checkAgeRestriction(ticketData) {
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
    // Có birthDate và dưới 18 - chỉ qua được nếu đã nhập CCCD xác minh hợp lệ.
    return typeof ticketData.verifiedCccd === 'string' && /^\d{12}$/.test(ticketData.verifiedCccd);
  }

  // Không có birthDate (vd. Google Sign-In) và chưa được admin duyệt CCCD -
  // bắt buộc phải qua luồng age_verification_requests trước, không có "quick
  // path" nào khác ở server để tránh việc bỏ qua hoàn toàn cổng này.
  return false;
}

// Tính lại toàn bộ số tiền phải thanh toán ở server, không tin bất kỳ giá
// nào do client gửi lên - đóng lỗ hổng "client tự tính giá rồi gửi amount
// tùy ý" (seat/combo/voucher/giảm giá tự động đều được xác minh lại từ
// Firestore, không đọc lại field 'ticketAmount'/'totalAmount' của chính vé).
async function computeAuthoritativeAmount(ticketData) {
  const theaterName = ticketData.theaterName || '';
  const showDate = ticketData.showDate || '';
  const showTime = ticketData.showTime || '';
  const movieTitle = ticketData.movieTitle || '';
  const seats = Array.isArray(ticketData.seats) ? ticketData.seats : [];
  const combos = Array.isArray(ticketData.combos) ? ticketData.combos : [];

  // 1. Giá STD/VIP + phòng: tra showtime thật do theater_manager tạo, dùng
  // mặc định nếu không tìm thấy (khớp fallback của showtime_selection_screen.dart).
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
  const weekendSur = isWeekend(showDate) ? 15000 : 0;
  const timeSur = timeSurcharge(showTime);
  let seatSubtotal = 0;
  for (const seatId of seats) {
    seatSubtotal += seatPrice(String(seatId), priceStandard, priceVip, rows, weekendSur, timeSur);
  }

  // 2. Combo: chỉ cộng theo bảng giá server, bỏ qua 'price' client tự gửi.
  let comboSubtotal = 0;
  for (const c of combos) {
    const unitPrice = COMBO_PRICES[c.id];
    if (unitPrice == null) {
      throw { status: 400, message: `Combo không hợp lệ: ${c.id}` };
    }
    comboSubtotal += unitPrice * (Number(c.quantity) || 0);
  }

  const subtotal = seatSubtotal + comboSubtotal;

  // 3. Voucher: xác minh lại từ chính document voucher, không tin
  // 'discountAmount' ghi sẵn trong vé.
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
      // Voucher không còn hợp lệ tại thời điểm thanh toán (vd. bị tắt/hết hạn
      // sau khi khách áp mã) - âm thầm bỏ qua discount thay vì chặn cả giao
      // dịch, vì khách vẫn có quyền thanh toán vé mà không có voucher.
    }
  }

  // 4. Giảm giá tự động (thành viên + Happy Wednesday) - tính lại độc lập
  // theo lịch sử vé COMPLETED thật trong Firestore và ngày giờ SERVER (không
  // tin ngày giờ máy khách), khớp _calculateAutomaticDiscounts() ở
  // payment_screen.dart.
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
    const wednesdayPct = new Date().getDay() === 3 ? 10 : 0; // 0=CN...3=Thứ 4
    const autoPct = memPct + wednesdayPct;
    autoDiscount = Math.round((subtotal * autoPct) / 100);
  }

  const finalAmount = Math.max(0, subtotal - voucherDiscount - autoDiscount);
  return { finalAmount, subtotal, voucherDiscount, autoDiscount };
}

// 1. API: Tạo link thanh toán. Client gửi ticketId (vé PENDING đã tạo sẵn)
// thay vì tự gửi 'amount' - server tính lại toàn bộ số tiền từ dữ liệu gốc
// trong Firestore (seats/combo/voucher/giảm giá tự động), không tin số tiền
// client tính. Đồng thời ghi orderCode PayOS thật vào vé - trước đây webhook
// đối chiếu vé qua field 'orderCode', nhưng client tự sinh 1 số ngẫu nhiên
// hoàn toàn khác với orderCode PayOS thật, nên webhook gần như không bao giờ
// tìm đúng vé để cập nhật COMPLETED.
app.post('/create-payment-link', requireAuth, async (req, res) => {
  if (!firestore) {
    return res.status(503).json({ error: -1, message: 'Server chưa cấu hình Firebase Admin SDK', data: null });
  }
  try {
    const { ticketId, returnUrl, cancelUrl } = req.body;
    if (!ticketId) {
      return res.status(400).json({ error: -1, message: 'Thiếu ticketId', data: null });
    }

    const ticketRef = firestore.collection('tickets').doc(ticketId);
    const ticketDoc = await ticketRef.get();
    if (!ticketDoc.exists) {
      return res.status(404).json({ error: -1, message: 'Vé không tồn tại', data: null });
    }
    const ticketData = ticketDoc.data();
    if (ticketData.userId !== req.userUid) {
      return res.status(403).json({ error: -1, message: 'Bạn không có quyền thanh toán vé này', data: null });
    }
    if (ticketData.paymentStatus !== 'PENDING') {
      return res.status(400).json({ error: -1, message: `Vé đang ở trạng thái không hợp lệ để thanh toán: ${ticketData.paymentStatus}`, data: null });
    }

    const ageOk = await checkAgeRestriction(ticketData);
    if (!ageOk) {
      return res.status(403).json({ error: -1, message: 'Phim này giới hạn 18+. Cần xác minh độ tuổi trước khi thanh toán.', data: null });
    }

    const { finalAmount } = await computeAuthoritativeAmount(ticketData);
    if (finalAmount <= 0) {
      return res.status(400).json({ error: -1, message: 'Số tiền thanh toán không hợp lệ', data: null });
    }

    // orderCode phải là số nguyên dương, duy nhất và nằm trong khoảng PayOS
    // chấp nhận (< 9007199254740991). Dùng đầy đủ timestamp (ms) + phần dư
    // ngẫu nhiên nhỏ để tránh trùng khi nhiều request tới trong cùng 1ms.
    const orderCode = Date.now() * 1000 + Math.floor(Math.random() * 1000);

    const requestData = {
      orderCode: orderCode,
      amount: finalAmount,
      description: `Ve ${orderCode}`.slice(0, 25), // PayOS giới hạn description <= 25 ký tự
      returnUrl: returnUrl || 'http://localhost:3000/success.html',
      cancelUrl: cancelUrl || 'http://localhost:3000/cancel.html',
    };

    const paymentLinkRes = await payos.paymentRequests.create(requestData);

    // Ghi orderCode PayOS thật vào vé để webhook đối chiếu đúng, và ghi lại
    // finalAmount server tính để có dấu vết đối soát sau này.
    await ticketRef.update({ orderCode, totalAmount: finalAmount });

    return res.status(200).json({
      error: 0,
      message: 'Success',
      data: {
        bin: paymentLinkRes.bin,
        checkoutUrl: paymentLinkRes.checkoutUrl,
        accountNumber: paymentLinkRes.accountNumber,
        accountName: paymentLinkRes.accountName,
        amount: paymentLinkRes.amount,
        description: paymentLinkRes.description,
        orderCode: paymentLinkRes.orderCode,
        qrCode: paymentLinkRes.qrCode,
      }
    });
  } catch (error) {
    if (error && error.status) {
      return res.status(error.status).json({ error: -1, message: error.message, data: null });
    }
    console.error('Error creating payment link:', error);
    return res.status(500).json({
      error: -1,
      message: 'Failed to create payment link',
      data: null
    });
  }
});

// 2. API: Nhận Webhook từ PayOS khi thanh toán thành công
app.post('/payos-webhook', async (req, res) => {
  try {
    const webhookData = req.body;

    // Xác thực chữ ký dữ liệu để đảm bảo dữ liệu là từ PayOS gửi
    const paymentData = await payos.webhooks.verify(webhookData);

    console.log('Xác thực Webhook thành công:', paymentData);
    console.log(`Đơn hàng ${paymentData.orderCode} đã thanh toán thành công số tiền ${paymentData.amount}`);

    if (!firestore) {
      console.error('Firestore chưa được khởi tạo (thiếu serviceAccountKey.json) - không thể cập nhật vé.');
      return res.status(200).json({ success: true, message: 'Verified but Firestore not configured' });
    }

    const ticketsRef = firestore.collection('tickets');
    const snap = await ticketsRef.where('orderCode', '==', paymentData.orderCode).limit(1).get();

    if (snap.empty) {
      console.error(`Không tìm thấy vé nào có orderCode ${paymentData.orderCode}`);
      return res.status(200).json({ success: true, message: 'Verified but no matching ticket' });
    }

    const ticketDoc = snap.docs[0];
    // Idempotency guard: PayOS có thể gửi lại webhook, bỏ qua nếu đã cập nhật.
    if (ticketDoc.data().paymentStatus === 'COMPLETED') {
      console.log(`Vé ${ticketDoc.id} đã ở trạng thái COMPLETED, bỏ qua webhook lặp lại.`);
      return res.status(200).json({ success: true, message: 'Already completed' });
    }

    const ticketData = ticketDoc.data();
    const qrSignature = signTicket(ticketDoc.id, ticketData.orderCode, 'COMPLETED');

    await ticketDoc.ref.update({
      paymentStatus: 'COMPLETED',
      paidAt: Timestamp.now(),
      qrSignature,
    });
    console.log(`Đã cập nhật vé ${ticketDoc.id} thành COMPLETED và ký QR.`);

    return res.status(200).json({
      success: true,
      message: 'Ok',
    });

  } catch (error) {
    console.error('Lỗi khi xử lý webhook (Hoặc sai chữ ký):', error.message);
    return res.status(400).json({
      success: false,
      message: 'Invalid webhook',
    });
  }
});

// 3. API: Ký vé đã thanh toán xong (dùng cho luồng ví Stella Wallet, vốn
// hoàn tất trực tiếp trên client không qua webhook PayOS). Client gọi API
// này ngay sau khi tạo vé COMPLETED để lấy chữ ký nhúng vào QR check-in.
// Trước đây endpoint này không yêu cầu xác thực gì cả - bất kỳ ai (không cần
// đăng nhập) gọi đúng ticketId của vé COMPLETED nào cũng lấy được chữ ký QR
// hợp lệ cho vé đó, kể cả vé không phải của họ. Giờ bắt buộc đăng nhập +
// đúng chủ vé (staff bán vé quầy tự đứng tên userId trên vé đó nên vẫn ký
// được vé mình vừa tạo).
app.post('/sign-ticket', requireAuth, async (req, res) => {
  if (!firestore) {
    return res.status(503).json({ success: false, message: 'Server chưa cấu hình Firebase Admin SDK' });
  }
  try {
    const { ticketId } = req.body;
    if (!ticketId) {
      return res.status(400).json({ success: false, message: 'Thiếu ticketId' });
    }
    const ticketRef = firestore.collection('tickets').doc(ticketId);
    const ticketDoc = await ticketRef.get();
    if (!ticketDoc.exists) {
      return res.status(404).json({ success: false, message: 'Vé không tồn tại' });
    }
    const data = ticketDoc.data();
    if (data.userId !== req.userUid) {
      return res.status(403).json({ success: false, message: 'Bạn không có quyền ký vé này' });
    }
    if (data.paymentStatus !== 'COMPLETED') {
      return res.status(400).json({ success: false, message: 'Vé chưa ở trạng thái COMPLETED' });
    }
    const qrSignature = signTicket(ticketId, data.orderCode, 'COMPLETED');
    await ticketRef.update({ qrSignature });
    return res.status(200).json({ success: true, signature: qrSignature });
  } catch (error) {
    console.error('Lỗi khi ký vé:', error.message);
    return res.status(500).json({ success: false, message: 'Lỗi máy chủ' });
  }
});

// 4. API: Xác minh QR check-in do nhân viên quét. Đây là điểm duy nhất được
// phép chuyển vé sang CHECKED_IN - client (staff app) không còn ghi thẳng
// Firestore nữa, tránh giả mạo QR bằng cách chỉ biết ticket ID thô.
app.post('/verify-checkin', requireStaffAuth, async (req, res) => {
  const { ticketId, signature } = req.body;
  const logResult = async (result, reason, theaterName) => {
    try {
      await firestore.collection('checkin_audit_log').add({
        ticketId: ticketId || null,
        staffUid: req.staffUid,
        theaterName: theaterName || req.staffTheater || null,
        result,
        reason,
        timestamp: Timestamp.now(),
      });
    } catch (e) {
      console.error('Không ghi được checkin_audit_log:', e.message);
    }
  };

  if (!ticketId || !signature) {
    await logResult('rejected', 'missing_ticket_id_or_signature');
    return res.status(400).json({ success: false, message: 'Thiếu ticketId hoặc signature' });
  }

  try {
    const ticketRef = firestore.collection('tickets').doc(ticketId);
    const ticketDoc = await ticketRef.get();
    if (!ticketDoc.exists) {
      await logResult('rejected', 'ticket_not_found');
      return res.status(404).json({ success: false, message: 'Vé không tồn tại!' });
    }

    const data = ticketDoc.data();

    if (data.paymentStatus === 'CHECKED_IN') {
      await logResult('rejected', 'already_checked_in', data.theaterName);
      return res.status(409).json({ success: false, message: 'Vé đã được sử dụng!' });
    }
    if (data.paymentStatus !== 'COMPLETED') {
      await logResult('rejected', `invalid_status:${data.paymentStatus}`, data.theaterName);
      return res.status(400).json({ success: false, message: 'Vé chưa thanh toán hoặc đã bị hủy!' });
    }

    const expectedSignature = signTicket(ticketId, data.orderCode, 'COMPLETED');
    const providedBuf = Buffer.from(signature, 'hex');
    const expectedBuf = Buffer.from(expectedSignature, 'hex');
    const signatureValid = providedBuf.length === expectedBuf.length &&
      crypto.timingSafeEqual(providedBuf, expectedBuf);
    if (!signatureValid) {
      await logResult('rejected', 'signature_mismatch', data.theaterName);
      return res.status(403).json({ success: false, message: 'Mã QR không hợp lệ hoặc đã bị giả mạo!' });
    }

    if (req.staffTheater && data.theaterName && data.theaterName !== req.staffTheater) {
      await logResult('rejected', 'wrong_theater', data.theaterName);
      return res.status(403).json({ success: false, message: `Sai rạp! Vé này thuộc về ${data.theaterName}` });
    }

    // Khung giờ hợp lệ: cho phép check-in từ 30 phút trước tới 3 giờ sau giờ chiếu.
    if (data.showDate && data.showTime) {
      const showDateTime = parseShowDateTime(data.showDate, data.showTime);
      if (showDateTime) {
        const now = new Date();
        const minutesDiff = (now - showDateTime) / 60000;
        if (minutesDiff < -30 || minutesDiff > 180) {
          await logResult('rejected', 'outside_checkin_window', data.theaterName);
          return res.status(400).json({ success: false, message: 'Ngoài khung giờ cho phép check-in!' });
        }
      }
    }

    await ticketRef.update({
      paymentStatus: 'CHECKED_IN',
      checkedInAt: Timestamp.now(),
      checkedInBy: req.staffUid,
    });
    await logResult('success', 'ok', data.theaterName);

    return res.status(200).json({ success: true, message: 'Check-in thành công!', movieTitle: data.movieTitle || '' });
  } catch (error) {
    console.error('Lỗi khi verify-checkin:', error.message);
    await logResult('rejected', `server_error:${error.message}`);
    return res.status(500).json({ success: false, message: 'Lỗi máy chủ' });
  }
});

// 5. API: Check-in thủ công khi khách không quét được QR (máy quét lỗi,
// điện thoại hết pin...). Không kiểm tra chữ ký HMAC (khách không đưa được
// QR) nhưng vẫn xác thực staff + đúng rạp + trạng thái vé, và ghi vào
// checkin_audit_log với reason 'manual_override' để admin có thể soát lại -
// tránh lỗ hổng "staff tự ghi log giả" mà việc client ghi thẳng Firestore
// (trước đây) không để lại dấu vết nào.
app.post('/manual-checkin', requireStaffAuth, async (req, res) => {
  const { ticketId } = req.body;
  const logResult = async (result, reason, theaterName) => {
    try {
      await firestore.collection('checkin_audit_log').add({
        ticketId: ticketId || null,
        staffUid: req.staffUid,
        theaterName: theaterName || req.staffTheater || null,
        result,
        reason,
        timestamp: Timestamp.now(),
      });
    } catch (e) {
      console.error('Không ghi được checkin_audit_log:', e.message);
    }
  };

  if (!ticketId) {
    await logResult('rejected', 'missing_ticket_id');
    return res.status(400).json({ success: false, message: 'Thiếu ticketId' });
  }

  try {
    const ticketRef = firestore.collection('tickets').doc(ticketId);
    const ticketDoc = await ticketRef.get();
    if (!ticketDoc.exists) {
      await logResult('rejected', 'ticket_not_found');
      return res.status(404).json({ success: false, message: 'Vé không tồn tại!' });
    }

    const data = ticketDoc.data();

    if (data.paymentStatus === 'CHECKED_IN') {
      await logResult('rejected', 'already_checked_in', data.theaterName);
      return res.status(409).json({ success: false, message: 'Vé đã được sử dụng!' });
    }
    if (data.paymentStatus !== 'COMPLETED') {
      await logResult('rejected', `invalid_status:${data.paymentStatus}`, data.theaterName);
      return res.status(400).json({ success: false, message: 'Vé chưa thanh toán hoặc đã bị hủy!' });
    }

    if (req.staffTheater && data.theaterName && data.theaterName !== req.staffTheater) {
      await logResult('rejected', 'wrong_theater', data.theaterName);
      return res.status(403).json({ success: false, message: `Sai rạp! Vé này thuộc về ${data.theaterName}` });
    }

    await ticketRef.update({
      paymentStatus: 'CHECKED_IN',
      checkedInAt: Timestamp.now(),
      checkedInBy: req.staffUid,
    });
    await logResult('success', 'manual_override', data.theaterName);

    return res.status(200).json({ success: true, message: 'Check-in thủ công thành công!' });
  } catch (error) {
    console.error('Lỗi khi manual-checkin:', error.message);
    await logResult('rejected', `server_error:${error.message}`);
    return res.status(500).json({ success: false, message: 'Lỗi máy chủ' });
  }
});

// 6. API: Hủy vé + hoàn tiền vào ví - thay cho việc client trước đây tự ghi
// thẳng 3 bước rời rạc (thông báo, cộng ví, đổi trạng thái vé) không có giao
// dịch nào bọc lại. Lỗi đó cho phép: cộng tiền vào ví trước, rồi bước đổi
// trạng thái vé bị Firestore rules từ chối (vé COMPLETED không được owner tự
// sửa) - khách vẫn được hoàn tiền dù vé vẫn còn nguyên, và có thể lặp lại vô
// hạn lần. Toàn bộ hoàn tiền + đổi trạng thái giờ nằm trong 1 Firestore
// transaction chạy bằng Admin SDK ở server, không thể xảy ra nửa vời.
app.post('/cancel-ticket', requireAuth, async (req, res) => {
  const { ticketId } = req.body;
  if (!ticketId) {
    return res.status(400).json({ success: false, message: 'Thiếu ticketId' });
  }

  try {
    const ticketRef = firestore.collection('tickets').doc(ticketId);
    const userRef = firestore.collection('users').doc(req.userUid);

    const result = await firestore.runTransaction(async (tx) => {
      const ticketDoc = await tx.get(ticketRef);
      if (!ticketDoc.exists) {
        throw { status: 404, message: 'Vé không tồn tại' };
      }
      const data = ticketDoc.data();

      if (data.userId !== req.userUid) {
        throw { status: 403, message: 'Bạn không có quyền hủy vé này' };
      }
      if (data.paymentStatus === 'CANCELLED') {
        throw { status: 409, message: 'Vé này đã được hủy trước đó' };
      }
      if (data.paymentStatus === 'CHECKED_IN') {
        throw { status: 400, message: 'Vé đã check-in, không thể hủy' };
      }
      if (data.paymentStatus !== 'PENDING' && data.paymentStatus !== 'COMPLETED') {
        throw { status: 400, message: `Vé đang ở trạng thái không hợp lệ để hủy: ${data.paymentStatus}` };
      }

      // Chỉ chặn hủy trễ với vé COMPLETED (vé PENDING coi như chưa thật sự
      // "đi xem" nên luôn cho hủy) - đúng chính sách nêu ở payment_screen.dart
      // "hủy tối đa 30 phút trước giờ chiếu".
      if (data.paymentStatus === 'COMPLETED' && data.showDate && data.showTime) {
        const showDateTime = parseShowDateTime(data.showDate, data.showTime);
        if (showDateTime) {
          const minutesUntilShow = (showDateTime - new Date()) / 60000;
          if (minutesUntilShow < 30) {
            throw { status: 400, message: 'Chỉ có thể hủy vé tối thiểu 30 phút trước giờ chiếu' };
          }
        }
      }

      const refundAmount = (data.totalAmount && Number(data.totalAmount) > 0) ? Number(data.totalAmount) : 0;

      tx.update(ticketRef, {
        paymentStatus: 'CANCELLED',
        cancelledAt: Timestamp.now(),
      });
      if (refundAmount > 0) {
        tx.update(userRef, { wallet_balance: FieldValue.increment(refundAmount) });
      }

      return { refundAmount, movieTitle: data.movieTitle || '' };
    });

    // Ghi thông báo sau khi transaction đã chắc chắn thành công (best-effort,
    // không ảnh hưởng tới kết quả hủy vé nếu ghi thông báo lỗi).
    try {
      await firestore.collection('notifications').add({
        title: 'HỦY VÉ HOÀN TIỀN THÀNH CÔNG 💸',
        body: `Stella Cinema xác nhận yêu cầu hủy vé phim "${result.movieTitle}" đã được phê duyệt. Số tiền hoàn lại đã được gửi về ví của bạn.`,
        userEmail: req.userEmail,
        type: 'system',
        isRead: false,
        createdAt: Timestamp.now(),
      });
    } catch (e) {
      console.error('Không ghi được notification sau khi hủy vé:', e.message);
    }

    return res.status(200).json({ success: true, refundAmount: result.refundAmount });
  } catch (error) {
    if (error && error.status) {
      return res.status(error.status).json({ success: false, message: error.message });
    }
    console.error('Lỗi khi hủy vé:', error.message);
    return res.status(500).json({ success: false, message: 'Lỗi máy chủ' });
  }
});

// 7. API: Chatbot AI Gemini - client gửi tin nhắn + ngữ cảnh phim (dữ liệu
// công khai), server giữ API key và gọi Gemini hộ. Không yêu cầu đăng nhập vì
// chatbot phục vụ cả khách vãng lai chưa có tài khoản.
app.post('/gemini-chat', async (req, res) => {
  const geminiClient = await getGeminiClient();
  if (!geminiClient) {
    return res.status(503).json({ success: false, message: 'Server chưa cấu hình GEMINI_API_KEY' });
  }
  try {
    const { message, movieContext, history } = req.body;
    if (!message || typeof message !== 'string') {
      return res.status(400).json({ success: false, message: 'Thiếu message' });
    }

    const model = geminiClient.getGenerativeModel({
      model: 'gemini-1.5-flash',
      systemInstruction: GEMINI_SYSTEM_INSTRUCTION,
    });

    // history: [{role: 'user'|'model', text: '...'}], tối đa 10 tin nhắn gần
    // nhất - client tự cắt bớt trước khi gửi, server chỉ giới hạn phòng hờ.
    const contents = Array.isArray(history)
      ? history.slice(-10).map((h) => ({
          role: h.role === 'user' ? 'user' : 'model',
          parts: [{ text: String(h.text || '') }],
        }))
      : [];

    const prompt = `Câu hỏi của khách hàng: '${message}'\n${movieContext || ''}\n\nHãy tư vấn lịch sự, xưng hô 'bạn' và 'tôi' nhé.`;
    contents.push({ role: 'user', parts: [{ text: prompt }] });

    const result = await model.generateContent({ contents });
    const text = result.response.text();

    return res.status(200).json({ success: true, text });
  } catch (error) {
    console.error('Lỗi khi gọi Gemini:', error.message);
    return res.status(500).json({ success: false, message: 'Gemini API bị lỗi hoặc quá tải' });
  }
});

// Parse các định dạng ngày đang tồn tại trong app: "yyyy-MM-dd" (từ showtimes
// do theater_manager tạo) hoặc "Hôm nay (dd/MM)" / "Thứ Hai (dd/MM)" (từ
// showtime_selection_screen.dart). Trả về null nếu không parse được -
// verify-checkin sẽ bỏ qua kiểm tra khung giờ trong trường hợp đó.
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

app.listen(port, () => {
  console.log(`Server đang chạy tại http://localhost:${port}`);
  console.log('Hãy sử dụng ngrok để expose port này ra public và cấu hình Webhook trên trang PayOS nhé!');
});
