const express = require('express');
const { Timestamp } = require('firebase-admin/firestore');
const { firestore } = require('../config/firebase');
const { requireManagerAuth } = require('../middleware/auth.middleware');
const { resolveLayoutForCreation, generateSeatsForShowtime } = require('../services/seat.service');
const {
  FALLBACK_SHOWTIME_DURATION_MS,
  parseReleaseDateJs,
  detectSessionTypeJs,
  overlapsWindowJs,
  Showtime_isoDate,
  Showtime_hhmm,
} = require('../services/showtime.service');

const router = express.Router();

// API: Tạo/sửa suất chiếu - kiểm tra chồng giờ phòng chiếu AUTHORITATIVE ở
// server (Giai đoạn F). Trước đây theater_manager_dashboard_screen.dart tự
// query + so khớp chồng giờ HOÀN TOÀN ở client rồi ghi thẳng vào Firestore -
// không có gì chặn 1 client đã sửa đổi (hoặc 2 quản lý bấm gần như đồng thời)
// ghi 2 suất chồng giờ cùng 1 phòng, vì firestore.rules chỉ kiểm tra role chứ
// không kiểm tra được logic nghiệp vụ nhiều-tài-liệu này. Endpoint này giữ
// nguyên đúng thuật toán chống chồng giờ cũ (showAt -> showAt + thời lượng
// phim + 10p) nhưng chạy ở server nơi không client nào bỏ qua được.
router.post('/showtimes/save', requireManagerAuth, async (req, res) => {
  if (!firestore) {
    return res.status(503).json({ success: false, message: 'Server chưa cấu hình Firebase Admin SDK' });
  }
  try {
    const {
      existingId, theaterName, roomName, movieTitle, roomFormat,
      projectionFormat, soundFormat, seatMapVersionId, language,
      priceStandard, priceVip, manualSessionType, showAtMillis, repeatDays,
      advertisingMinutes, exitBufferMinutes, cleaningMinutes,
    } = req.body;

    if (!theaterName || !roomName || !movieTitle || !showAtMillis) {
      return res.status(400).json({ success: false, message: 'Thiếu thông tin bắt buộc' });
    }
    // Manager chỉ được thao tác suất chiếu của đúng rạp mình phụ trách - admin
    // không bị giới hạn này (khớp firestore.rules không phân biệt rạp cho admin).
    if (!req.staffIsAdmin && req.staffTheater && req.staffTheater !== theaterName) {
      return res.status(403).json({ success: false, message: 'Bạn không phụ trách rạp này' });
    }

    const priceStd = Number(priceStandard) || 90000;
    const priceVipNum = Number(priceVip) || 120000;
    // Mặc định (0, 10, 0) khớp đúng công thức cứng cũ - xem models/showtime.dart.
    const advMin = advertisingMinutes != null ? Number(advertisingMinutes) : 0;
    const exitMin = exitBufferMinutes != null ? Number(exitBufferMinutes) : 10;
    const cleanMin = cleaningMinutes != null ? Number(cleaningMinutes) : 0;
    const baseData = {
      movieTitle, theaterName, roomName,
      roomFormat: roomFormat || 'Standard',
      ...(projectionFormat ? { projectionFormat } : {}),
      ...(soundFormat ? { soundFormat } : {}),
      ...(seatMapVersionId ? { seatMapVersionId } : {}),
      language: language || 'Phụ đề',
      priceStandard: priceStd,
      priceVip: priceVipNum,
      status: 'active',
      advertisingMinutes: advMin,
      exitBufferMinutes: exitMin,
      cleaningMinutes: cleanMin,
    };

    // Tra thời lượng phim + ngày công chiếu thật (để tự suy sessionType) -
    // cùng 1 nguồn 'movies' mà client vốn đọc, chỉ nay đọc lại ở server để
    // không tin số phút/ngày công chiếu do client tự gửi lên.
    let movieReleaseDate = null;
    let movieDurationMs = FALLBACK_SHOWTIME_DURATION_MS;
    const movieSnap = await firestore.collection('movies').where('title', '==', movieTitle).limit(1).get();
    if (!movieSnap.empty) {
      const movieData = movieSnap.docs[0].data();
      if (!manualSessionType) movieReleaseDate = parseReleaseDateJs(movieData.releaseDate);
      const durationMatch = /\d+/.exec(String(movieData.duration || ''));
      if (durationMatch) movieDurationMs = parseInt(durationMatch[0], 10) * 60 * 1000;
    }
    const sessionTypeFor = (showAt) => manualSessionType || detectSessionTypeJs(showAt, movieReleaseDate);

    // Toàn bộ suất chiếu khác cùng phòng - allow read:true trên 'showtimes'
    // nên đọc đủ hết mọi manager/session khác, không chỉ những gì client này
    // biết tới lúc submit (khác điểm mấu chốt so với check cũ chỉ ở client).
    // Mỗi suất chiếu khác dùng ĐÚNG buffer riêng của nó (mặc định 0/10/0 cho
    // suất cũ chưa có field này) khi tính mốc phòng-trống-lại của suất đó.
    const roomShowtimesSnap = await firestore.collection('showtimes')
      .where('theaterName', '==', theaterName).where('roomName', '==', roomName).get();
    const otherShowtimes = roomShowtimesSnap.docs
      .filter((d) => d.id !== existingId)
      .map((d) => {
        const dd = d.data();
        const showAt = dd.showAt && dd.showAt.toDate();
        if (!showAt) return null;
        return {
          showAt,
          advertisingMinutes: dd.advertisingMinutes != null ? Number(dd.advertisingMinutes) : 0,
          exitBufferMinutes: dd.exitBufferMinutes != null ? Number(dd.exitBufferMinutes) : 10,
          cleaningMinutes: dd.cleaningMinutes != null ? Number(dd.cleaningMinutes) : 0,
        };
      })
      .filter(Boolean);

    const asShowtime = (showAt) => ({ showAt, advertisingMinutes: advMin, exitBufferMinutes: exitMin, cleaningMinutes: cleanMin });

    if (existingId) {
      const baseShowAt = new Date(showAtMillis);
      const conflict = otherShowtimes.find((s) => overlapsWindowJs(s, asShowtime(baseShowAt), movieDurationMs));
      if (conflict) {
        return res.status(409).json({
          success: false,
          code: 'SHOWTIME_ROOM_CONFLICT',
          message: 'Phòng chiếu này đã có phim khác chiếu chồng giờ! Vui lòng chọn giờ hoặc phòng khác.',
        });
      }
      await firestore.collection('showtimes').doc(existingId).update({
        ...baseData,
        showAt: Timestamp.fromDate(baseShowAt),
        date: Showtime_isoDate(baseShowAt),
        time: Showtime_hhmm(baseShowAt),
        sessionType: sessionTypeFor(baseShowAt),
      });
      const existingSeats = await firestore.collection('showtimes').doc(existingId).collection('seats').limit(1).get();
      if (existingSeats.empty) {
        const layout = await resolveLayoutForCreation(seatMapVersionId, theaterName, roomName);
        await generateSeatsForShowtime(existingId, layout, priceStd, priceVipNum);
      }
      return res.status(200).json({ success: true });
    }

    // Tạo mới - hỗ trợ lặp lại N ngày, ngày nào chồng giờ thì bỏ qua ngày đó
    // (không chặn cả loạt) - khớp đúng hành vi cũ ở client.
    const days = Math.min(Math.max(parseInt(repeatDays, 10) || 1, 1), 60);
    const newShowtimes = [];
    const createdIds = [];
    let created = 0, skipped = 0;
    for (let i = 0; i < days; i++) {
      const thisShowAt = new Date(Number(showAtMillis) + i * 24 * 60 * 60 * 1000);
      const thisShowtime = asShowtime(thisShowAt);
      const conflicts = [...otherShowtimes, ...newShowtimes].some((s) => overlapsWindowJs(s, thisShowtime, movieDurationMs));
      if (conflicts) { skipped++; continue; }
      newShowtimes.push(thisShowtime);
      const ref = firestore.collection('showtimes').doc();
      await ref.set({
        ...baseData,
        showAt: Timestamp.fromDate(thisShowAt),
        date: Showtime_isoDate(thisShowAt),
        time: Showtime_hhmm(thisShowAt),
        sessionType: sessionTypeFor(thisShowAt),
        createdAt: Timestamp.now(),
      });
      createdIds.push(ref.id);
      created++;
    }

    if (createdIds.length > 0) {
      const layout = await resolveLayoutForCreation(seatMapVersionId, theaterName, roomName);
      for (const id of createdIds) {
        await generateSeatsForShowtime(id, layout, priceStd, priceVipNum);
      }
    }

    return res.status(200).json({ success: true, created, skipped });
  } catch (error) {
    console.error('Lỗi /showtimes/save:', error.message);
    return res.status(500).json({ success: false, message: 'Lỗi máy chủ' });
  }
});

module.exports = router;
