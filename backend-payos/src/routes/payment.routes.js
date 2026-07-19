const express = require('express');
const crypto = require('crypto');
const { firestore, Timestamp, FieldValue } = require('../config/firebase');
const { requireAuth } = require('../middleware/auth.middleware');
const payos = require('../services/payment.service');
const { checkAgeRestriction, computeAuthoritativeAmount } = require('../services/pricing.service');

const router = express.Router();

const TICKET_SIGNING_SECRET = process.env.TICKET_SIGNING_SECRET || 'dev-only-insecure-secret-change-me';

function signTicket(ticketId, orderCode, paymentStatus) {
  const payload = `${ticketId}:${orderCode || ''}:${paymentStatus}`;
  return crypto.createHmac('sha256', TICKET_SIGNING_SECRET).update(payload).digest('hex');
}

async function bumpVoucherUsage(tx, voucherCode, { strict }) {
  if (!voucherCode) return true;
  const voucherRef = firestore.collection('vouchers').doc(voucherCode);
  const voucherSnap = await tx.get(voucherRef);
  if (!voucherSnap.exists) return true;
  const v = voucherSnap.data();
  const maxUses = Number(v.maxUses) || 0;
  const currentUses = Number(v.currentUses) || 0;
  if (strict && maxUses > 0 && currentUses >= maxUses) return false;
  tx.update(voucherRef, { currentUses: currentUses + 1 });
  return true;
}

router.post('/create-payment-link', requireAuth, async (req, res) => {
  if (!firestore) {
    return res.status(503).json({ error: -1, message: 'Server chưa cấu hình Firebase Admin SDK', data: null });
  }
  try {
    const { ticketId, returnUrl, cancelUrl } = req.body;
    if (!ticketId) {
      return res.status(400).json({ error: -1, message: 'Thiếu ticketId', data: null });
    }

    const ticketRef = firestore.collection('tickets').doc(ticketId);
    const ticketDoc = await ticketRef.get();
    if (!ticketDoc.exists) {
      return res.status(404).json({ error: -1, message: 'Vé không tồn tại', data: null });
    }
    const ticketData = ticketDoc.data();
    if (ticketData.userId !== req.userUid) {
      return res.status(403).json({ error: -1, message: 'Bạn không có quyền thanh toán vé này', data: null });
    }
    if (ticketData.paymentStatus !== 'PENDING') {
      return res.status(400).json({ error: -1, message: `Vé đang ở trạng thái không hợp lệ để thanh toán: ${ticketData.paymentStatus}`, data: null });
    }

    const ageOk = await checkAgeRestriction(ticketData);
    if (!ageOk) {
      return res.status(403).json({ error: -1, message: 'Phim này giới hạn 18+. Cần xác minh độ tuổi trước khi thanh toán.', data: null });
    }

    const { finalAmount, usedLoyaltyPoints } = await computeAuthoritativeAmount(ticketData);
    if (finalAmount <= 0) {
      return res.status(400).json({ error: -1, message: 'Số tiền thanh toán không hợp lệ', data: null });
    }

    const orderCode = Date.now() * 1000 + Math.floor(Math.random() * 1000);

    const requestData = {
      orderCode: orderCode,
      amount: finalAmount,
      description: `Ve ${orderCode}`.slice(0, 25),
      returnUrl: returnUrl || 'http://localhost:3000/success.html',
      cancelUrl: cancelUrl || 'http://localhost:3000/cancel.html',
    };

    const paymentLinkRes = await payos.paymentRequests.create(requestData);

    await ticketRef.update({ orderCode, totalAmount: finalAmount, usedLoyaltyPoints, earnedLoyaltyPoints: Math.floor(finalAmount / 1000) });

    return res.status(200).json({
      error: 0,
      message: 'Success',
      data: {
        bin: paymentLinkRes.bin,
        checkoutUrl: paymentLinkRes.checkoutUrl,
        accountNumber: paymentLinkRes.accountNumber,
        accountName: paymentLinkRes.accountName,
        amount: paymentLinkRes.amount,
        description: paymentLinkRes.description,
        orderCode: paymentLinkRes.orderCode,
        qrCode: paymentLinkRes.qrCode,
      }
    });
  } catch (error) {
    if (error && error.status) {
      return res.status(error.status).json({ error: -1, message: error.message, data: null });
    }
    console.error('Error creating payment link:', error);
    return res.status(500).json({
      error: -1,
      message: 'Failed to create payment link',
      data: null
    });
  }
});

router.post('/pay-wallet', requireAuth, async (req, res) => {
  if (!firestore) {
    return res.status(503).json({ error: -1, message: 'Server chưa cấu hình Firebase Admin SDK', data: null });
  }
  try {
    const { ticketId } = req.body;
    if (!ticketId) {
      return res.status(400).json({ error: -1, message: 'Thiếu ticketId', data: null });
    }

    const ticketRef = firestore.collection('tickets').doc(ticketId);
    const ticketDoc = await ticketRef.get();
    if (!ticketDoc.exists) {
      return res.status(404).json({ error: -1, message: 'Vé không tồn tại', data: null });
    }
    const ticketData = ticketDoc.data();
    if (ticketData.userId !== req.userUid) {
      return res.status(403).json({ error: -1, message: 'Bạn không có quyền thanh toán vé này', data: null });
    }
    if (ticketData.paymentStatus !== 'PENDING') {
      return res.status(400).json({ error: -1, message: `Vé đang ở trạng thái không hợp lệ để thanh toán: ${ticketData.paymentStatus}`, data: null });
    }

    const ageOk = await checkAgeRestriction(ticketData);
    if (!ageOk) {
      return res.status(403).json({ error: -1, message: 'Phim này giới hạn 18+. Cần xác minh độ tuổi trước khi thanh toán.', data: null });
    }

    const { finalAmount, usedLoyaltyPoints } = await computeAuthoritativeAmount(ticketData);
    if (finalAmount <= 0 && usedLoyaltyPoints <= 0) {
      return res.status(400).json({ error: -1, message: 'Số tiền thanh toán không hợp lệ', data: null });
    }

    const userRef = firestore.collection('users').doc(req.userUid);

    const result = await firestore.runTransaction(async (tx) => {
      const userSnap = await tx.get(userRef);
      const balance = Number(userSnap.data()?.wallet_balance) || 0;
      const currentPoints = Number(userSnap.data()?.loyalty_points) || 0;

      if (balance < finalAmount) return 'INSUFFICIENT_BALANCE';
      if (usedLoyaltyPoints > 0 && currentPoints < usedLoyaltyPoints) return 'INSUFFICIENT_BALANCE';

      const voucherOk = await bumpVoucherUsage(tx, ticketData.voucherCode, { strict: true });
      if (!voucherOk) return 'VOUCHER_EXHAUSTED';

      const earnedPoints = Math.floor(finalAmount / 1000);
      tx.update(userRef, {
        wallet_balance: balance - finalAmount,
        loyalty_points: (currentPoints - usedLoyaltyPoints) + earnedPoints,
      });
      tx.update(ticketRef, {
        paymentStatus: 'COMPLETED',
        totalAmount: finalAmount,
        earnedLoyaltyPoints: earnedPoints,
        paidAt: Timestamp.now(),
      });
      return 'OK';
    });

    if (result === 'INSUFFICIENT_BALANCE') {
      return res.status(400).json({ error: -1, message: 'INSUFFICIENT_BALANCE', data: null });
    }
    if (result === 'VOUCHER_EXHAUSTED') {
      return res.status(400).json({ error: -1, message: 'Mã giảm giá vừa hết lượt sử dụng, vui lòng bỏ mã và thử lại', data: null });
    }

    return res.status(200).json({ error: 0, message: 'Success', data: { finalAmount } });
  } catch (error) {
    if (error && error.status) {
      return res.status(error.status).json({ error: -1, message: error.message, data: null });
    }
    console.error('Error processing wallet payment:', error);
    return res.status(500).json({ error: -1, message: 'Failed to process wallet payment', data: null });
  }
});

// Giữ nguyên logic nạp ví vô hạn theo yêu cầu của người dùng
router.post('/topup-wallet', requireAuth, async (req, res) => {
  if (!firestore) {
    return res.status(503).json({ success: false, message: 'Server chưa cấu hình Firebase Admin SDK' });
  }
  try {
    const amount = Number(req.body.amount);
    if (!Number.isFinite(amount) || amount <= 0) {
      return res.status(400).json({ success: false, message: 'Số tiền nạp không hợp lệ' });
    }
    const userRef = firestore.collection('users').doc(req.userUid);
    await userRef.set({ wallet_balance: FieldValue.increment(amount) }, { merge: true });
    return res.status(200).json({ success: true });
  } catch (error) {
    console.error('Lỗi khi nạp ví:', error.message);
    return res.status(500).json({ success: false, message: 'Lỗi máy chủ' });
  }
});

router.post('/payos-webhook', async (req, res) => {
  try {
    const webhookData = req.body;
    const paymentData = await payos.webhooks.verify(webhookData);

    console.log('Xác thực Webhook thành công:', paymentData);
    console.log(`Đơn hàng ${paymentData.orderCode} đã thanh toán thành công số tiền ${paymentData.amount}`);

    if (!firestore) {
      console.error('Firestore chưa được khởi tạo (thiếu serviceAccountKey.json) - không thể cập nhật vé.');
      return res.status(200).json({ success: true, message: 'Verified but Firestore not configured' });
    }

    const ticketsRef = firestore.collection('tickets');
    const snap = await ticketsRef.where('orderCode', '==', paymentData.orderCode).limit(1).get();

    if (snap.empty) {
      console.error(`Không tìm thấy vé nào có orderCode ${paymentData.orderCode}`);
      return res.status(200).json({ success: true, message: 'Verified but no matching ticket' });
    }

    const ticketDoc = snap.docs[0];
    if (ticketDoc.data().paymentStatus === 'COMPLETED') {
      console.log(`Vé ${ticketDoc.id} đã ở trạng thái COMPLETED, bỏ qua webhook lặp lại.`);
      return res.status(200).json({ success: true, message: 'Already completed' });
    }

    const ticketData = ticketDoc.data();
    const qrSignature = signTicket(ticketDoc.id, ticketData.orderCode, 'COMPLETED');

    await firestore.runTransaction(async (tx) => {
      const freshTicketSnap = await tx.get(ticketDoc.ref);
      if (!freshTicketSnap.exists || freshTicketSnap.data().paymentStatus === 'COMPLETED') return;

      if (ticketData.userId) {
        const userRef = firestore.collection('users').doc(ticketData.userId);
        const userSnap = await tx.get(userRef);
        if (userSnap.exists) {
          const currentPoints = Number(userSnap.data()?.loyalty_points) || 0;
          const usedLoyaltyPoints = Math.min(Number(ticketData.usedLoyaltyPoints) || 0, currentPoints);
          const earnedPoints = Number(ticketData.earnedLoyaltyPoints) || 0;
          tx.update(userRef, { loyalty_points: currentPoints - usedLoyaltyPoints + earnedPoints });
        }
      }

      await bumpVoucherUsage(tx, ticketData.voucherCode, { strict: false });

      tx.update(ticketDoc.ref, {
        paymentStatus: 'COMPLETED',
        paidAt: Timestamp.now(),
        qrSignature,
      });
    });
    console.log(`Đã cập nhật vé ${ticketDoc.id} thành COMPLETED và ký QR.`);

    return res.status(200).json({
      success: true,
      message: 'Ok',
    });

  } catch (error) {
    console.error('Lỗi khi xử lý webhook (Hoặc sai chữ ký):', error.message);
    return res.status(400).json({
      success: false,
      message: 'Invalid webhook',
    });
  }
});

module.exports = router;
