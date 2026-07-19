const express = require('express');
const { firestore } = require('../config/firebase');
const { requireAuth } = require('../middleware/auth.middleware');
const { sendFcmToAllTokens, sendPromoPushToAllUsers, APP_LOGO_URL } = require('../services/notification.service');

const router = express.Router();

// API gửi Push Notification qua FCM - dùng cho admin_broadcast_screen.dart
// (gửi tay tới TẤT CẢ user). Trước đây gửi qua topic 'all_users' nhưng không
// có nơi nào trong app gọi subscribeToTopic() nên KHÔNG thiết bị nào thực sự
// nhận được (bug câm, không báo lỗi) - giờ luôn gửi trực tiếp theo danh sách
// fcmToken thật lấy từ Firestore, giống hệt cách push quảng cáo tự động hoạt
// động.
router.post('/api/send-fcm', requireAuth, async (req, res) => {
  if (!firestore) {
    return res.status(503).json({ success: false, message: 'Server chưa cấu hình Firebase Admin SDK' });
  }

  try {
    const userDoc = await firestore.collection('users').doc(req.userUid).get();
    if (!userDoc.exists) return res.status(403).json({ success: false, message: 'Không tìm thấy user' });
    const userData = userDoc.data();
    if (userData.role !== 'admin' && userData.role !== 'marketing' && userData.isAdmin !== true) {
      return res.status(403).json({ success: false, message: 'Bạn không có quyền gửi broadcast' });
    }

    const { title, body } = req.body;
    if (!title || !body) {
      return res.status(400).json({ success: false, message: 'Thiếu title hoặc body' });
    }

    const result = await sendFcmToAllTokens({
      title,
      body,
      data: { type: 'broadcast' },
      imageUrl: APP_LOGO_URL,
    });
    return res.json({ success: true, data: result });
  } catch (error) {
    console.error('Lỗi send FCM:', error);
    return res.status(500).json({ success: false, message: error.message });
  }
});

// Endpoint kích hoạt gửi thử push quảng cáo ngay (admin) - để test không phải
// chờ đúng chu kỳ giờ mới thấy kết quả.
router.post('/api/trigger-promo-push', requireAuth, async (req, res) => {
  if (!firestore) {
    return res.status(503).json({ success: false, message: 'Server chưa cấu hình Firebase Admin SDK' });
  }
  try {
    const userDoc = await firestore.collection('users').doc(req.userUid).get();
    const role = userDoc.data()?.role;
    if (role !== 'admin' && userDoc.data()?.isAdmin !== true) {
      return res.status(403).json({ success: false, message: 'Chỉ admin mới gửi thử được' });
    }
    await sendPromoPushToAllUsers();
    return res.json({ success: true });
  } catch (error) {
    console.error('Lỗi trigger-promo-push:', error.message);
    return res.status(500).json({ success: false, message: error.message });
  }
});

module.exports = router;
