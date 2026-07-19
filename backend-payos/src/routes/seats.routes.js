const express = require('express');
const crypto = require('crypto');
const { firestore, Timestamp } = require('../config/firebase');
const { requireAuth } = require('../middleware/auth.middleware');
const { resolveLayoutForShowtime, seatTypeAndPrice } = require('../services/seat.service');

const router = express.Router();

router.post('/:showtimeId/seats/hold', requireAuth, async (req, res) => {
  if (!firestore) {
    return res.status(503).json({ success: false, message: 'Server chưa cấu hình Firebase Admin SDK' });
  }
  const { showtimeId } = req.params;
  const { seatIds } = req.body;
  if (!Array.isArray(seatIds) || seatIds.length === 0) {
    return res.status(400).json({ success: false, message: 'Thiếu seatIds' });
  }

  const holdToken = crypto.randomUUID();
  const heldUntilMs = Date.now() + 5 * 60 * 1000;
  const heldUntil = Timestamp.fromMillis(heldUntilMs);

  try {
    const showtimeRef = firestore.collection('showtimes').doc(showtimeId);
    const seatRefs = seatIds.map((id) => showtimeRef.collection('seats').doc(String(id)));

    const precheckDocs = await Promise.all(seatRefs.map((ref) => ref.get()));
    const hasMissing = precheckDocs.some((d) => !d.exists);
    let layout = null;
    if (hasMissing) {
      const showtimeDoc = await showtimeRef.get();
      if (!showtimeDoc.exists) {
        return res.status(404).json({ success: false, message: 'Suất chiếu không tồn tại' });
      }
      layout = await resolveLayoutForShowtime(showtimeDoc);
    }

    await firestore.runTransaction(async (tx) => {
      const showtimeTxDoc = await tx.get(showtimeRef);
      if (!showtimeTxDoc.exists) {
        throw { status: 404, message: 'Suất chiếu không tồn tại' };
      }
      const showtimeStatus = showtimeTxDoc.data().status || 'active';
      if (showtimeStatus !== 'active') {
        throw {
          status: 409,
          message: showtimeStatus === 'sales_closed'
            ? 'Suất chiếu này đã tạm dừng bán vé'
            : 'Suất chiếu này đã bị hủy',
        };
      }

      const seatDocs = await Promise.all(seatRefs.map((ref) => tx.get(ref)));

      const now = Date.now();
      const unavailable = [];
      seatDocs.forEach((doc, i) => {
        if (!doc.exists) return;
        const d = doc.data();
        const expiredHold = d.status === 'HOLDING' && d.heldUntil && d.heldUntil.toMillis() < now;
        const canHold = d.status === 'AVAILABLE' || expiredHold;
        if (!canHold) unavailable.push(seatIds[i]);
      });
      if (unavailable.length > 0) {
        throw { status: 409, message: `Ghế đã có người khác giữ: ${unavailable.join(', ')}`, unavailable };
      }

      seatRefs.forEach((ref, i) => {
        const doc = seatDocs[i];
        if (doc.exists) {
          const currentVersion = Number(doc.data()?.version) || 0;
          tx.update(ref, { status: 'HOLDING', holdToken, heldBy: req.userUid, heldUntil, version: currentVersion + 1 });
        } else {
          const { seatType, price } = seatTypeAndPrice(seatIds[i], layout);
          tx.set(ref, {
            seatType, price,
            status: 'HOLDING', holdToken, heldBy: req.userUid, heldUntil,
            bookingId: null, version: 0,
          });
        }
      });
    });

    return res.status(200).json({ success: true, holdToken, expiresAt: heldUntilMs });
  } catch (error) {
    if (error && error.status) {
      return res.status(error.status).json({ success: false, message: error.message, unavailable: error.unavailable });
    }
    console.error('Lỗi /seats/hold:', error.message);
    return res.status(500).json({ success: false, message: 'Lỗi máy chủ' });
  }
});

router.post('/:showtimeId/seats/release', requireAuth, async (req, res) => {
  if (!firestore) {
    return res.status(503).json({ success: false, message: 'Server chưa cấu hình Firebase Admin SDK' });
  }
  const { showtimeId } = req.params;
  const { holdToken } = req.body;
  if (!holdToken) {
    return res.status(400).json({ success: false, message: 'Thiếu holdToken' });
  }
  try {
    const snap = await firestore
      .collection('showtimes').doc(showtimeId).collection('seats')
      .where('holdToken', '==', holdToken)
      .where('heldBy', '==', req.userUid)
      .get();
    if (snap.empty) {
      return res.status(200).json({ success: true, released: 0 });
    }
    const batch = firestore.batch();
    snap.docs.forEach((doc) => {
      batch.update(doc.ref, { status: 'AVAILABLE', holdToken: null, heldBy: null, heldUntil: null });
    });
    await batch.commit();
    return res.status(200).json({ success: true, released: snap.size });
  } catch (error) {
    console.error('Lỗi /seats/release:', error.message);
    return res.status(500).json({ success: false, message: 'Lỗi máy chủ' });
  }
});

module.exports = router;
