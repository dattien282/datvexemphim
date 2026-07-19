const express = require('express');
const crypto = require('crypto');
const { requireAuth } = require('../middleware/auth.middleware');
const { CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET } = require('../config/firebase');

const router = express.Router();

// API: Ký upload Cloudinary cho ảnh CCCD/avatar (age_verification_screen.dart,
// profile_screen.dart) - không dùng "unsigned upload preset" nữa (bất kỳ ai
// biết cloud name + preset đều upload thẳng lên Cloudinary được, không cần
// đăng nhập app), giờ client phải xin chữ ký ở đây (yêu cầu Firebase ID token
// hợp lệ) trước khi được Cloudinary chấp nhận upload.
router.post('/cloudinary-sign', requireAuth, (req, res) => {
  if (!CLOUDINARY_API_KEY || !CLOUDINARY_API_SECRET) {
    return res.status(503).json({ success: false, message: 'Server chưa cấu hình CLOUDINARY_API_KEY/CLOUDINARY_API_SECRET' });
  }
  const timestamp = Math.floor(Date.now() / 1000);
  const isAvatar = req.body.type === 'avatar';

  const publicId = isAvatar
    ? `avatars/${req.userUid}`
    : `age_verification/${req.userUid}/${req.body.kind === 'back' ? 'back' : 'front'}_${crypto.randomUUID()}`;

  // Cloudinary yêu cầu ký đúng các tham số sẽ gửi kèm (trừ file, api_key,
  // cloud_name, resource_type), sắp xếp theo alphabet: "key=value&key=value...".
  // Avatar gửi kèm 'overwrite=true' nên phải có trong chữ ký, CCCD thì không.
  const signParams = isAvatar
    ? `overwrite=true&public_id=${publicId}&timestamp=${timestamp}`
    : `public_id=${publicId}&timestamp=${timestamp}`;
  const signature = crypto.createHash('sha1').update(`${signParams}${CLOUDINARY_API_SECRET}`).digest('hex');

  return res.status(200).json({
    success: true,
    cloudName: CLOUDINARY_CLOUD_NAME,
    apiKey: CLOUDINARY_API_KEY,
    timestamp,
    publicId,
    signature,
    overwrite: isAvatar,
  });
});

module.exports = router;
