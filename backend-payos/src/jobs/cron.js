const { Timestamp, FieldValue } = require('firebase-admin/firestore');
const { firestore } = require('../config/firebase');
const { sendPromoPushToAllUsers } = require('../services/notification.service');

// Cron dọn vé PENDING treo quá lâu (Giai đoạn C) - trước đây KHÔNG có cơ chế
// nào tự dọn nếu khách bỏ ngang giữa chừng (thoát app/mất mạng ngay sau khi
// tạo vé PENDING mà /discard-pending-ticket chưa kịp gọi) - ghế bị giữ
// HOLDING/BOOKED vĩnh viễn dù không ai thật sự mua. Không cần quét
// collectionGroup 'seats' tìm hold hết hạn riêng: /seats/hold đã tự coi
// HOLDING hết hạn là "trống" cho lượt giữ mới (lazy reclaim) - cron này chỉ
// cần dọn phần TICKET treo (không tự lazy-reclaim được vì không ai chủ động
// tạo vé mới đúng đúng lúc để kích hoạt).
const STALE_PENDING_TICKET_MINUTES = 15;

async function cleanupStalePendingTickets() {
  if (!firestore) return;
  const cutoff = Timestamp.fromMillis(Date.now() - STALE_PENDING_TICKET_MINUTES * 60 * 1000);
  const snap = await firestore
    .collection('tickets')
    .where('paymentStatus', '==', 'PENDING')
    .where('createdAt', '<', cutoff)
    .limit(100)
    .get();
  if (snap.empty) return;

  let cleaned = 0;
  for (const doc of snap.docs) {
    try {
      await firestore.runTransaction(async (tx) => {
        const ticketDoc = await tx.get(doc.ref);
        if (!ticketDoc.exists) return;
        const data = ticketDoc.data();
        if (data.paymentStatus !== 'PENDING') return; // vừa được thanh toán/huỷ đúng lúc cron chạy
        if (data.showtimeId && Array.isArray(data.seats) && data.seats.length > 0) {
          const statusRef = firestore.collection('showtime_seat_status').doc(data.showtimeId);
          tx.set(statusRef, { bookedSeatIds: FieldValue.arrayRemove(...data.seats) }, { merge: true });
          for (const seatId of data.seats) {
            const seatRef = firestore.collection('showtimes').doc(data.showtimeId).collection('seats').doc(String(seatId));
            tx.set(seatRef, { status: 'AVAILABLE', holdToken: null, heldBy: null, heldUntil: null, bookingId: null }, { merge: true });
          }
        }
        tx.delete(doc.ref);
      });
      cleaned++;
    } catch (e) {
      console.error(`[cleanup] Lỗi dọn vé PENDING treo ${doc.id}:`, e.message);
    }
  }
  console.log(`[cleanup] Đã dọn ${cleaned}/${snap.size} vé PENDING treo quá ${STALE_PENDING_TICKET_MINUTES} phút.`);
}

// ── Dynamic pricing có giới hạn (F.5) ───────────────────────────────────────
// Suất chiếu sắp diễn ra bán càng chạy thì phụ thu nhẹ theo tỷ lệ lấp đầy:
// >70% ghế đã bán -> +5%, >90% -> +10% (chỉ 2 bậc, có trần - không phải giá
// thả nổi tự do). Ghi 1 field `dynamicSurchargePercent` lên document SUẤT
// CHIẾU (không sửa giá từng ghế): app đọc để hiển thị đúng giá trước khi
// khách chọn, computeAuthoritativeAmount đọc để trừ tiền - 2 bên luôn khớp.
// CHỈ TĂNG, không hạ (tránh khách vừa thấy giá cao tải lại thấy rẻ hơn ngay
// trong cùng ngày - nhất quán trải nghiệm); suất chiếu mới luôn bắt đầu từ 0.
const DYNAMIC_PRICING_ENABLED = process.env.DYNAMIC_PRICING_ENABLED !== 'false';

async function updateDynamicPricing() {
  if (!firestore) return;
  const now = Timestamp.now();
  const weekAhead = Timestamp.fromMillis(Date.now() + 7 * 24 * 60 * 60 * 1000);
  const snap = await firestore
    .collection('showtimes')
    .where('status', '==', 'active')
    .where('showAt', '>', now)
    .where('showAt', '<', weekAhead)
    .limit(300)
    .get();

  let updated = 0;
  for (const doc of snap.docs) {
    try {
      const seatsCol = doc.ref.collection('seats');
      // count() aggregate: không phải tải toàn bộ document ghế về chỉ để đếm.
      const [totalAgg, bookedAgg] = await Promise.all([
        seatsCol.count().get(),
        seatsCol.where('status', '==', 'BOOKED').count().get(),
      ]);
      const total = totalAgg.data().count;
      if (total === 0) continue; // suất cũ chưa có ShowtimeSeat - bỏ qua
      const occupancy = bookedAgg.data().count / total;

      const targetPercent = occupancy > 0.9 ? 10 : occupancy > 0.7 ? 5 : 0;
      const currentPercent = Number(doc.data().dynamicSurchargePercent) || 0;
      if (targetPercent > currentPercent) {
        await doc.ref.update({ dynamicSurchargePercent: targetPercent });
        updated++;
      }
    } catch (e) {
      console.error(`[dynamic-pricing] Lỗi suất ${doc.id}:`, e.message);
    }
  }
  if (updated > 0) console.log(`[dynamic-pricing] Đã nâng phụ thu cho ${updated} suất chiếu bán chạy.`);
}

const PROMO_PUSH_ENABLED = (process.env.PROMO_PUSH_ENABLED ?? 'true') === 'true';
const PROMO_PUSH_INTERVAL_HOURS = Number(process.env.PROMO_PUSH_INTERVAL_HOURS || 6);

// Điểm khởi động DUY NHẤT cho mọi cron job của backend - gọi 1 lần từ
// src/app.js sau khi mount xong route, tránh setInterval bị đăng ký lặp lại
// nếu module này lỡ bị require nhiều lần.
function startCronJobs() {
  if (firestore && PROMO_PUSH_ENABLED) {
    setInterval(sendPromoPushToAllUsers, PROMO_PUSH_INTERVAL_HOURS * 60 * 60 * 1000);
    console.log(`✅ Promo push tự động: bật, mỗi ${PROMO_PUSH_INTERVAL_HOURS} giờ.`);
  } else if (!PROMO_PUSH_ENABLED) {
    console.log('ℹ️  Promo push tự động: đã tắt (PROMO_PUSH_ENABLED=false).');
  }

  if (firestore) {
    setInterval(cleanupStalePendingTickets, 5 * 60 * 1000);
    console.log('✅ Cron dọn vé PENDING treo: bật, quét mỗi 5 phút.');
  }

  if (firestore && DYNAMIC_PRICING_ENABLED) {
    setInterval(updateDynamicPricing, 30 * 60 * 1000);
    console.log('✅ Dynamic pricing: bật, quét mỗi 30 phút (tắt bằng DYNAMIC_PRICING_ENABLED=false).');
  }
}

module.exports = { startCronJobs, cleanupStalePendingTickets, updateDynamicPricing };
