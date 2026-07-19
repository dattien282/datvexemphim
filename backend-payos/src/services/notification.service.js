const { firestore, messaging, Timestamp } = require('../config/firebase');

const APP_LOGO_URL = 'https://res.cloudinary.com/g9u2mtmv/image/upload/v1784009790/app_assets/logo.png';

async function getAllUserFcmTokens(segment = 'all') {
  if (!firestore) return [];
  let query = firestore.collection('users');
  if (segment === 'diamond') {
    query = query.where('loyalty_points', '>=', 1000);
  } else if (segment === 'gold') {
    query = query.where('loyalty_points', '>=', 500);
  } else if (segment === 'silver') {
    query = query.where('loyalty_points', '>=', 200);
  } else if (segment === 'staff') {
    query = query.where('role', '==', 'staff');
  } else if (segment === 'manager') {
    query = query.where('role', '==', 'theater_manager');
  }
  const usersSnap = await query.get();
  return usersSnap.docs.map((d) => d.data().fcmToken).filter((t) => typeof t === 'string' && t.length > 0);
}

async function sendFcmToAllTokens({ title, body, data = {}, imageUrl, segment = 'all' }) {
  const tokens = await getAllUserFcmTokens(segment);
  if (tokens.length === 0) return { successCount: 0, failureCount: 0, totalTokens: 0 };
  let successCount = 0, failureCount = 0;
  for (let i = 0; i < tokens.length; i += 500) {
    const chunk = tokens.slice(i, i + 500);
    try {
      const res = await messaging.sendEachForMulticast({
        tokens: chunk,
        notification: { title, body, imageUrl },
        data,
      });
      successCount += res.successCount;
      failureCount += res.failureCount;
    } catch (e) {
      console.error('[fcm] Lỗi gửi multicast chunk:', e.message);
      failureCount += chunk.length;
    }
  }
  return { successCount, failureCount, totalTokens: tokens.length };
}

async function buildVoucherPromo() {
  if (!firestore) return null;
  const snap = await firestore
    .collection('vouchers')
    .where('status', '==', 'active')
    .where('expiresAt', '>', Timestamp.now())
    .limit(20)
    .get();
  if (snap.empty) return null;
  const docs = snap.docs.filter((d) => {
    const v = d.data();
    return !(v.maxUses > 0 && (v.currentUses || 0) >= v.maxUses);
  });
  if (docs.length === 0) return null;
  const v = docs[Math.floor(Math.random() * docs.length)].data();
  const discount = v.discountPercent > 0 ? `${v.discountPercent}%` : `${(v.discountAmount || 0).toLocaleString('vi-VN')}đ`;
  return {
    title: '🎟️ Ưu đãi đang chờ bạn!',
    body: `Nhập mã ${v.code} để giảm ${discount} cho vé xem phim. Nhanh tay kẻo hết lượt!`,
    data: { type: 'voucher', voucherCode: v.code },
  };
}

async function buildMoviePromo() {
  if (!firestore) return null;
  const snap = await firestore.collection('movies').where('isShowingNow', '==', true).limit(30).get();
  const docs = snap.docs.filter((d) => !d.data().isDeleted);
  if (docs.length === 0) return null;
  const doc = docs[Math.floor(Math.random() * docs.length)];
  return {
    title: '🔥 Phim hot đang chiếu',
    body: `"${doc.data().title}" đang gây sốt phòng vé! Đặt vé ngay hôm nay để không bỏ lỡ suất đẹp.`,
    data: { type: 'movie', movieId: doc.id },
  };
}

async function buildComboPromo() {
  if (!firestore) return null;
  const snap = await firestore.collection('combos').limit(30).get();
  if (snap.empty) return null;
  const c = snap.docs[Math.floor(Math.random() * snap.docs.length)].data();
  return {
    title: '🍿 Mua 2 tặng 1 bắp nước!',
    body: `Combo "${c.title}" đang có ưu đãi mua 2 tặng 1 tại quầy - ghé rạp thưởng thức ngay!`,
    data: { type: 'combo' },
  };
}

function buildShowtimePromo() {
  const isWednesday = new Date().getDay() === 3;
  return {
    title: isWednesday ? '🎬 Thứ 4 vui vẻ!' : '🎬 Suất chiếu giá tốt',
    body: isWednesday
      ? 'Hôm nay là Thứ 4 - đồng giá vé cực hời cho mọi suất chiếu thường!'
      : 'Suất chiếu buổi sáng đang giảm giá - vừa xem phim vừa tiết kiệm!',
    data: { type: 'showtime' },
  };
}

async function buildPromoNotification() {
  const builders = [buildVoucherPromo, buildMoviePromo, buildComboPromo, async () => buildShowtimePromo()];
  for (let i = builders.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [builders[i], builders[j]] = [builders[j], builders[i]];
  }
  for (const build of builders) {
    try {
      const result = await build();
      if (result) return result;
    } catch (e) {
      console.error('Lỗi khi tạo nội dung promo push:', e.message);
    }
  }
  return null;
}

async function sendPromoPushToAllUsers() {
  if (!firestore) return;
  const notif = await buildPromoNotification();
  if (!notif) {
    console.log('[promo-push] Không có nội dung phù hợp, bỏ qua lượt này.');
    return;
  }
  const result = await sendFcmToAllTokens({
    title: notif.title,
    body: notif.body,
    data: notif.data,
    imageUrl: APP_LOGO_URL,
  });
  if (result.totalTokens === 0) {
    console.log('[promo-push] Chưa có thiết bị nào đăng ký FCM token.');
    return;
  }
  console.log(`[promo-push] Đã gửi "${notif.title}" tới ${result.successCount}/${result.totalTokens} thiết bị.`);
}

module.exports = {
  APP_LOGO_URL,
  getAllUserFcmTokens,
  sendFcmToAllTokens,
  sendPromoPushToAllUsers
};
