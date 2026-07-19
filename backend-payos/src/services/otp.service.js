const crypto = require('crypto');
const nodemailer = require('nodemailer');
const { TICKET_SIGNING_SECRET } = require('../config/firebase');

// ── OTP đăng nhập 2 lớp (2FA qua email) ─────────────────────────────────────
// Sau khi client xác thực đúng email/password bằng Firebase Auth (client SDK),
// login_screen.dart gọi /auth/send-otp (kèm ID token vừa lấy được) TRƯỚC KHI
// cho vào app - server sinh mã 6 số, lưu vào Firestore otp_codes/{uid} (không
// có rule cho client đọc/ghi collection này, chỉ Admin SDK truy cập được) và
// gửi qua Gmail SMTP. Client nhập mã, gọi /auth/verify-otp để hoàn tất đăng
// nhập. Không dùng cho đăng nhập Google (đã xác thực qua OAuth của Google).
const otpTransporter = (process.env.SMTP_USER && process.env.SMTP_PASS)
  ? nodemailer.createTransport({
      service: 'gmail',
      auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
    })
  : null;

const OTP_TTL_MS = 5 * 60 * 1000;
const OTP_MAX_ATTEMPTS = 5;

// Băm mã OTP bằng HMAC-SHA256 (khoá = TICKET_SIGNING_SECRET đã có sẵn, dùng
// lại thay vì thêm biến .env mới) thay vì lưu thẳng 6 số dạng plaintext vào
// Firestore - trước đây ai đọc được document otp_codes/{uid} (backup, export,
// Console...) là biết luôn mã thật đang có hiệu lực. Gắn cả uid vào input để
// 2 người khác nhau cùng ra 1 mã ngẫu nhiên (trùng số, hiếm nhưng có thể xảy
// ra với 1 triệu tổ hợp) không cho ra cùng 1 hash.
function hashOtpCode(code, uid) {
  return crypto.createHmac('sha256', TICKET_SIGNING_SECRET).update(`${uid}:${code}`).digest('hex');
}

module.exports = { otpTransporter, OTP_TTL_MS, OTP_MAX_ATTEMPTS, hashOtpCode };
