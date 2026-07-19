const { GoogleGenerativeAI } = require('@google/generative-ai');
const { firestore } = require('../config/firebase');

// Gemini API key giờ chỉ tồn tại ở server, không còn được gửi xuống app
// Flutter dưới bất kỳ hình thức nào (trước đây app đọc key này từ Firestore
// configs/gemini về máy khách để tự gọi Gemini - key có thể bị trích xuất
// bằng cách bắt gói tin/reverse-engineer app, dùng ké quota của dự án).
// Client giờ chỉ gọi /gemini-chat, server giữ key và gọi Gemini hộ.
//
// Key ưu tiên đọc từ Firestore configs/server_config (admin sửa qua UI
// AdminServerConfigScreen, không cần restart server) - rơi về biến môi
// trường .env nếu Firestore chưa có/chưa cấu hình. Cache 60 giây để không
// phải đọc Firestore trên mỗi tin nhắn chat.
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

module.exports = { getGeminiApiKey, getGeminiClient, GEMINI_SYSTEM_INSTRUCTION };
