const express = require('express');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const { firestore } = require('../config/firebase');
const { requireAuth } = require('../middleware/auth.middleware');

const router = express.Router();

let _geminiConfigCache = { key: null, fetchedAt: 0 };

async function getGeminiApiKey() {
  const now = Date.now();
  if (_geminiConfigCache.key && now - _geminiConfigCache.fetchedAt < 60000) {
    return _geminiConfigCache.key;
  }
  let key = process.env.GEMINI_API_KEY || '';
  if (firestore) {
    try {
      const doc = await firestore.collection('configs').doc('server_config').get();
      const configuredKey = doc.data()?.geminiApiKey;
      if (configuredKey) key = configuredKey;
    } catch (e) {
      console.warn('Không đọc được configs/server_config từ Firestore:', e.message);
    }
  }
  _geminiConfigCache = { key, fetchedAt: now };
  return key;
}

async function getGeminiClient() {
  const key = await getGeminiApiKey();
  return key ? new GoogleGenerativeAI(key) : null;
}

const GEMINI_SYSTEM_INSTRUCTION =
  "Bạn là Trợ lý ảo AI lịch sự và chuyên nghiệp của hệ thống rạp phim Stella Cinema. " +
  "Quy tắc giao tiếp bắt buộc:\n" +
  "1. Luôn xưng hô với khách hàng lịch sự là 'bạn' (ví dụ: 'chào bạn', 'bạn chọn phim gì', 'bạn cần trợ giúp gì'). Tự xưng là 'Stella' hoặc 'tôi'. Tuyệt đối tránh dùng các từ ngữ thân mật quá mức hoặc suồng sã như 'ní'.\n" +
  "2. Phong cách trả lời: Lịch sự, chuyên nghiệp, hỗ trợ tận tình, dùng emoji phù hợp.\n" +
  "3. Trả lời súc tích, ngắn gọn (trong khoảng 2-4 câu), trừ khi được yêu cầu liệt kê bảng giá hoặc địa điểm.\n" +
  "4. Luôn dựa trên dữ liệu thực tế được cung cấp trong prompt để tư vấn, không tự bịa tên phim khác đang chiếu.";

// RESTRICTION ADDED: requireAuth is now applied to prevent Gemini API quota abuse.
router.post('/gemini-chat', requireAuth, async (req, res) => {
  const geminiClient = await getGeminiClient();
  if (!geminiClient) {
    return res.status(503).json({ success: false, message: 'Server chưa cấu hình GEMINI_API_KEY' });
  }
  try {
    const { message, movieContext, history } = req.body;
    if (!message || typeof message !== 'string') {
      return res.status(400).json({ success: false, message: 'Thiếu message' });
    }

    const model = geminiClient.getGenerativeModel({
      model: 'gemini-3.5-flash',
      systemInstruction: GEMINI_SYSTEM_INSTRUCTION,
    });

    const contents = Array.isArray(history)
      ? history.slice(-10).map((h) => ({
          role: h.role === 'user' ? 'user' : 'model',
          parts: [{ text: String(h.text || '') }],
        }))
      : [];

    const prompt = `Câu hỏi của khách hàng: '${message}'\n${movieContext || ''}\n\nHãy tư vấn lịch sự, xưng hô 'bạn' và 'tôi' nhé.`;
    contents.push({ role: 'user', parts: [{ text: prompt }] });

    const result = await model.generateContent({ contents });
    const text = result.response.text();

    return res.status(200).json({ success: true, text });
  } catch (error) {
    console.error('Lỗi khi gọi Gemini:', error.message);
    return res.status(500).json({ success: false, message: 'Gemini API bị lỗi hoặc quá tải' });
  }
});

module.exports = router;
