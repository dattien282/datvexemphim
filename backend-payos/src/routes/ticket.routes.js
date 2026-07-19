const express = require('express');
const crypto = require('crypto');
const { Timestamp, FieldValue } = require('firebase-admin/firestore');
const { firestore } = require('../config/firebase');
const { requireAuth, requireStaffAuth } = require('../middleware/auth.middleware');
const { computeAuthoritativeAmount } = require('../services/pricing.service');
const { signTicket } = require('../services/ticket.service');
const { parseShowDateTime } = require('../services/showtime.service');

const router = express.Router();

// 1c-2. API: Bán vé tại quầy (staff_walkin_sale_screen.dart) - trước đây
// client tự tính tổng tiền bằng công thức giá RIÊNG (_seatPrice, chỉ cộng đơn
// giá ghế, không có phụ thu cuối tuần/khung giờ/dynamic pricing/pricing_rules
// như luồng khách tự đặt online) rồi ghi thẳng vé COMPLETED qua Firestore SDK
// - 2 luồng bán vé cùng 1 rạp có thể ra giá khác nhau cho cùng 1 ghế, và
// không gì chặn được 1 client bị sửa đổi gửi totalAmount tuỳ ý. Giờ dùng lại
// CHÍNH computeAuthoritativeAmount() của luồng online, ký QR luôn tại đây
// (trước đây gọi /sign-ticket riêng SAU KHI tạo vé nhưng quên gắn header
// Authorization -> luôn thất bại âm thầm, vé bán tại quầy chưa từng có
// qrSignature). Cố tình KHÔNG gọi checkAgeRestriction() ở đây - khác luồng
// online (nơi không ai xác minh tuổi thật được) - đây là bán tại quầy, nhân
// viên xác minh tuổi/CCCD trực tiếp bằng mắt trước khi bán, đúng quy trình
// rạp chiếu phim thật.
router.post('/walkin-sale', requireStaffAuth, async (req, res) => {
  if (!firestore) {
    return res.status(503).json({ success: false, message: 'Server chưa cấu hình Firebase Admin SDK' });
  }
  try {
    const { showtimeId, seatIds, customerName, preview } = req.body;
    if (!showtimeId || !Array.isArray(seatIds) || seatIds.length === 0) {
      return res.status(400).json({ success: false, message: 'Thiếu showtimeId hoặc danh sách ghế' });
    }
    const showtimeRef = firestore.collection('showtimes').doc(showtimeId);
    const showtimeDoc = await showtimeRef.get();
    if (!showtimeDoc.exists) {
      return res.status(404).json({ success: false, message: 'Suất chiếu không tồn tại' });
    }
    const st = showtimeDoc.data();
    if (st.status !== 'active') {
      return res.status(409).json({ success: false, message: 'Suất chiếu này đã đóng bán/bị huỷ' });
    }
    // Staff/manager chỉ bán vé cho đúng rạp mình phụ trách - admin không giới hạn.
    if (!req.staffIsAdmin && req.staffTheater && req.staffTheater !== st.theaterName) {
      return res.status(403).json({ success: false, message: 'Bạn không phụ trách rạp này' });
    }

    const uniqueSeatIds = [...new Set(seatIds.map(String))];

    const { finalAmount } = await computeAuthoritativeAmount({
      theaterName: st.theaterName,
      showDate: st.date,
      showTime: st.time,
      movieTitle: st.movieTitle,
      seats: uniqueSeatIds,
      combos: [],
    });
    if (finalAmount <= 0) {
      return res.status(400).json({ success: false, message: 'Số tiền không hợp lệ' });
    }

    // preview=true: chỉ báo giá thật cho staff xem TRƯỚC KHI thu tiền mặt
    // (không tạo vé/giữ ghế) - tránh báo sai giá cho khách khi suất chiếu có
    // phụ thu cuối tuần/khung giờ/dynamic pricing mà công thức cũ ở client
    // (chỉ cộng đơn giá ghế) không tính tới.
    if (preview === true) {
      return res.status(200).json({ success: true, finalAmount });
    }

    const ticketRef = firestore.collection('tickets').doc();
    const seatRefs = uniqueSeatIds.map((id) => showtimeRef.collection('seats').doc(id));

    // Port của areSeatsAvailableDirect/bookSeatsDirect
    // (seat_reservation_service.dart) - staff KHÔNG được bán đè ghế khách
    // đang giữ thật qua app (HOLDING chưa hết hạn).
    const booked = await firestore.runTransaction(async (tx) => {
      const seatDocs = await Promise.all(seatRefs.map((ref) => tx.get(ref)));
      const now = Date.now();
      for (const doc of seatDocs) {
        if (!doc.exists) continue;
        const d = doc.data();
        if (d.status === 'BOOKED' || d.status === 'UNAVAILABLE' || d.status === 'BLOCKED') return false;
        if (d.status === 'HOLDING') {
          const heldUntilMs = d.heldUntil ? d.heldUntil.toMillis() : 0;
          if (heldUntilMs > now) return false;
        }
      }
      seatRefs.forEach((ref) => {
        tx.set(ref, {
          status: 'BOOKED', bookingId: ticketRef.id, holdToken: null, heldBy: null, heldUntil: null,
          version: FieldValue.increment(1),
        }, { merge: true });
      });
      const orderCode = Date.now() % 1000000;
      const qrSignature = signTicket(ticketRef.id, orderCode, 'COMPLETED');
      tx.set(ticketRef, {
        orderCode,
        userId: req.staffUid,
        showtimeId,
        email: (customerName && String(customerName).trim()) || 'quầy vé',
        movieTitle: st.movieTitle,
        posterUrl: '',
        seats: uniqueSeatIds,
        combos: [],
        ticketAmount: finalAmount,
        discountAmount: 0,
        totalAmount: finalAmount,
        voucherCode: null,
        paymentMethod: 'cash_counter',
        paymentStatus: 'COMPLETED',
        theaterName: st.theaterName,
        showDate: st.date,
        showTime: st.time,
        showtime: `${st.theaterName} | ${st.date} | ${st.time}`,
        roomName: st.roomName,
        roomFormat: st.roomFormat,
        language: st.language || 'Phụ đề',
        sessionType: st.sessionType || 'Standard',
        soldByStaffUid: req.staffUid,
        soldByStaffEmail: req.staffEmail,
        qrSignature,
        createdAt: Timestamp.now(),
        paidAt: Timestamp.now(),
      });
      return true;
    });

    if (!booked) {
      return res.status(409).json({ success: false, message: 'Ghế vừa được đặt bởi giao dịch khác, vui lòng chọn lại ghế.' });
    }

    return res.status(200).json({ success: true, ticketId: ticketRef.id, finalAmount });
  } catch (error) {
    if (error && error.status) {
      return res.status(error.status).json({ success: false, message: error.message });
    }
    console.error('Lỗi /walkin-sale:', error.message);
    return res.status(500).json({ success: false, message: 'Lỗi máy chủ' });
  }
});

// 1d. API: Huỷ vé PENDING chưa thanh toán được (rollback khi /pay-wallet hoặc
// /create-payment-link báo lỗi). Trước đây payment_service.dart tự gọi
// ticketRef.delete() từ client, nhưng firestore.rules chỉ cho phép
// isAdmin() xoá vé - rollback luôn bị permission-denied, để lại vé PENDING
// rác và ghế bị giữ vĩnh viễn trong showtime_seat_status. Khác /cancel-ticket
// (dành cho vé đã thanh toán, có hoàn tiền) - vé PENDING ở đây chưa từng được
// thanh toán thành công nên không hoàn tiền, chỉ xoá vé + nhả ghế.
router.post('/discard-pending-ticket', requireAuth, async (req, res) => {
  if (!firestore) {
    return res.status(503).json({ success: false, message: 'Server chưa cấu hình Firebase Admin SDK' });
  }
  const { ticketId } = req.body;
  if (!ticketId) {
    return res.status(400).json({ success: false, message: 'Thiếu ticketId' });
  }
  try {
    const ticketRef = firestore.collection('tickets').doc(ticketId);
    await firestore.runTransaction(async (tx) => {
      const ticketDoc = await tx.get(ticketRef);
      if (!ticketDoc.exists) return;
      const data = ticketDoc.data();
      if (data.userId !== req.userUid) {
        throw { status: 403, message: 'Bạn không có quyền huỷ vé này' };
      }
      if (data.paymentStatus !== 'PENDING') {
        throw { status: 400, message: 'Chỉ có thể huỷ vé đang ở trạng thái PENDING' };
      }
      if (data.showtimeId && Array.isArray(data.seats) && data.seats.length > 0) {
        // Nhả ghế ở cả 2 nơi: showtime_seat_status (mảng gộp cũ, giữ lại để
        // tương thích ngược với suất chiếu chưa có ShowtimeSeat) VÀ từng
        // document showtimes/{id}/seats/{seatId} (Giai đoạn C - nguồn thật
        // cho suất chiếu mới). set+merge vì có thể chưa tồn tại (vé cũ).
        const statusRef = firestore.collection('showtime_seat_status').doc(data.showtimeId);
        tx.set(statusRef, { bookedSeatIds: FieldValue.arrayRemove(...data.seats) }, { merge: true });
        for (const seatId of data.seats) {
          const seatRef = firestore.collection('showtimes').doc(data.showtimeId).collection('seats').doc(String(seatId));
          tx.set(seatRef, { status: 'AVAILABLE', holdToken: null, heldBy: null, heldUntil: null, bookingId: null }, { merge: true });
        }
      }
      tx.delete(ticketRef);
    });
    return res.status(200).json({ success: true });
  } catch (error) {
    if (error && error.status) {
      return res.status(error.status).json({ success: false, message: error.message });
    }
    console.error('Lỗi khi discard-pending-ticket:', error.message);
    return res.status(500).json({ success: false, message: 'Lỗi máy chủ' });
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
router.post('/sign-ticket', requireAuth, async (req, res) => {
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
router.post('/verify-checkin', requireStaffAuth, async (req, res) => {
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
router.post('/manual-checkin', requireStaffAuth, async (req, res) => {
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
router.post('/cancel-ticket', requireAuth, async (req, res) => {
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
      // Nhả ghế đã đặt trước trong showtime_seat_status (xem
      // lib/features/booking_and_payment/services/seat_reservation_service.dart)
      // - nếu không làm bước này, ghế của vé đã hủy sẽ bị kẹt vĩnh viễn trong
      // lớp check atomic mới dù vé đã CANCELLED. Dùng set+merge (không phải
      // update) vì tài liệu showtime_seat_status có thể chưa tồn tại với vé cũ.
      if (data.showtimeId && Array.isArray(data.seats) && data.seats.length > 0) {
        const statusRef = firestore.collection('showtime_seat_status').doc(data.showtimeId);
        tx.set(statusRef, { bookedSeatIds: FieldValue.arrayRemove(...data.seats) }, { merge: true });
        // Giai đoạn C: nhả từng document showtimes/{id}/seats/{seatId} về
        // AVAILABLE - vé đã huỷ thì ghế phải mở lại cho người khác đặt.
        for (const seatId of data.seats) {
          const seatRef = firestore.collection('showtimes').doc(data.showtimeId).collection('seats').doc(String(seatId));
          tx.set(seatRef, { status: 'AVAILABLE', holdToken: null, heldBy: null, heldUntil: null, bookingId: null }, { merge: true });
        }
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

module.exports = router;
