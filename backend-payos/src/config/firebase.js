const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore, Timestamp, FieldValue } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const { getMessaging } = require('firebase-admin/messaging');
const path = require('path');

let firestore = null;
let auth = null;
let messaging = null;

try {
  const serviceAccountPath = path.join(__dirname, '../../serviceAccountKey.json');
  const serviceAccount = require(serviceAccountPath);
  initializeApp({ credential: cert(serviceAccount) });
  firestore = getFirestore();
  auth = getAuth();
  messaging = getMessaging();
  console.log('✅ Firebase Admin SDK initialized.');
} catch (e) {
  console.warn('⚠️  Firebase Admin SDK init failed - Firestore/Auth features will not work.');
  console.warn('    Lỗi:', e.message);
  console.warn('    Kiểm tra backend-payos/serviceAccountKey.json có tồn tại và hợp lệ không.');
}

// Secret dùng để ký/verify QR vé (HMAC-SHA256, xem ticket.service.js) và mã
// OTP đăng nhập (otp.service.js) - BẮT BUỘC đặt TICKET_SIGNING_SECRET trong
// backend-payos/.env cho môi trường thật, giá trị mặc định dưới đây chỉ để
// server không crash khi thiếu cấu hình lúc dev, KHÔNG an toàn cho production.
const TICKET_SIGNING_SECRET = process.env.TICKET_SIGNING_SECRET || 'dev-only-insecure-secret-change-me';

// Cấu hình Cloudinary cho ảnh CCCD xác minh tuổi/avatar (cloudinary.routes.js) -
// client xin chữ ký ở /cloudinary-sign (yêu cầu Firebase ID token hợp lệ)
// trước khi được Cloudinary chấp nhận upload.
const CLOUDINARY_CLOUD_NAME = process.env.CLOUDINARY_CLOUD_NAME || 'g9u2mtmv';
const CLOUDINARY_API_KEY = process.env.CLOUDINARY_API_KEY || '';
const CLOUDINARY_API_SECRET = process.env.CLOUDINARY_API_SECRET || '';

module.exports = {
  firestore,
  auth,
  messaging,
  Timestamp,
  FieldValue,
  TICKET_SIGNING_SECRET,
  CLOUDINARY_CLOUD_NAME,
  CLOUDINARY_API_KEY,
  CLOUDINARY_API_SECRET
};
