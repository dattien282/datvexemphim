const express = require('express');
const crypto = require('crypto');
const nodemailer = require('nodemailer');
const { firestore, Timestamp, FieldValue, TICKET_SIGNING_SECRET } = require('../config/firebase');
const { requireAuth } = require('../middleware/auth.middleware');

const router = express.Router();

const OTP_TTL_MS = 5 * 60 * 1000;
const OTP_MAX_ATTEMPTS = 5;

const otpTransporter = (process.env.SMTP_USER && process.env.SMTP_PASS)
  ? nodemailer.createTransport({
      service: 'gmail',
      auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
    })
  : null;

function hashOtpCode(code, uid) {
  return crypto.createHmac('sha256', TICKET_SIGNING_SECRET).update(`${uid}:${code}`).digest('hex');
}

router.post('/send-otp', requireAuth, async (req, res) => {
  if (!firestore) {
    return res.status(503).json({ success: false, message: 'Server chưa cấu hình Firebase Admin SDK' });
  }
  if (!otpTransporter) {
    return res.status(503).json({ success: false, message: 'Server chưa cấu hình SMTP_USER/SMTP_PASS' });
  }
  if (!req.userEmail) {
    return res.status(400).json({ success: false, message: 'Tài khoản không có email' });
  }
  try {
    const code = String(crypto.randomInt(0, 1000000)).padStart(6, '0');
    await firestore.collection('otp_codes').doc(req.userUid).set({
      codeHash: hashOtpCode(code, req.userUid),
      expiresAt: Timestamp.fromMillis(Date.now() + OTP_TTL_MS),
      attempts: 0,
      createdAt: Timestamp.now(),
    });

    await otpTransporter.sendMail({
      from: `"Stella Cinema" <${process.env.SMTP_USER}>`,
      to: req.userEmail,
      subject: 'Mã xác thực đăng nhập Stella Cinema',
      text: `Mã xác thực đăng nhập của bạn là: ${code}. Mã có hiệu lực trong 5 phút. Không chia sẻ mã này với bất kỳ ai.`,
      html: `<p>Mã xác thực đăng nhập của bạn là:</p><h2 style="letter-spacing:4px">${code}</h2><p>Mã có hiệu lực trong 5 phút. Không chia sẻ mã này với bất kỳ ai.</p>`,
    });

    return res.status(200).json({ success: true });
  } catch (error) {
    console.error('Lỗi /auth/send-otp:', error.message);
    return res.status(500).json({ success: false, message: 'Không gửi được mã xác thực' });
  }
});

router.post('/verify-otp', requireAuth, async (req, res) => {
  if (!firestore) {
    return res.status(503).json({ success: false, message: 'Server chưa cấu hình Firebase Admin SDK' });
  }
  const code = String(req.body.code || '').trim();
  if (!code) {
    return res.status(400).json({ success: false, message: 'Thiếu mã xác thực' });
  }
  try {
    const otpRef = firestore.collection('otp_codes').doc(req.userUid);
    const otpDoc = await otpRef.get();
    if (!otpDoc.exists) {
      return res.status(400).json({ success: false, message: 'Chưa yêu cầu mã xác thực hoặc mã đã được dùng' });
    }
    const data = otpDoc.data();
    if (data.expiresAt.toMillis() < Date.now()) {
      await otpRef.delete();
      return res.status(400).json({ success: false, message: 'Mã xác thực đã hết hạn, vui lòng gửi lại' });
    }
    if ((data.attempts || 0) >= OTP_MAX_ATTEMPTS) {
      await otpRef.delete();
      return res.status(400).json({ success: false, message: 'Bạn đã nhập sai quá nhiều lần, vui lòng gửi lại mã' });
    }
    
    const submittedHash = Buffer.from(hashOtpCode(code, req.userUid));
    const storedHash = Buffer.from(String(data.codeHash || ''));
    const matches = submittedHash.length === storedHash.length && crypto.timingSafeEqual(submittedHash, storedHash);
    if (!matches) {
      await otpRef.update({ attempts: FieldValue.increment(1) });
      return res.status(400).json({ success: false, message: 'Mã xác thực không đúng' });
    }
    await otpRef.delete();
    return res.status(200).json({ success: true });
  } catch (error) {
    console.error('Lỗi /auth/verify-otp:', error.message);
    return res.status(500).json({ success: false, message: 'Lỗi máy chủ' });
  }
});

module.exports = router;
