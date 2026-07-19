# CinemaHub Phase 4: User Features Tasks

- `[x]` 1. Sửa Lỗi Xác Thực Route Chatbot Gemini AI
  - `[x]` Thêm header `Authorization` truyền ID Token vào yêu cầu gửi tới `/gemini-chat` trong `cinema_ai_chatbot_screen.dart`
  - `[x]` Xác thực và kiểm soát lỗi nếu người dùng chưa đăng nhập.

- `[ ]` 2. Tích Hợp Hệ Thống Đổi Điểm Thưởng Ưu Đãi (Loyalty Redemption)
  - `[ ]` Thiết kế mục "Đổi điểm quà tặng bắp nước / voucher" trong `membership_screen.dart`
  - `[ ]` Tạo hàm giao dịch atomic khấu trừ `loyaltyPoints` và ghi nhận voucher vào collection `vouchers`
  - `[ ]` Hiển thị mã voucher vừa sinh cùng nút Sao chép (Copy) tiện lợi.

- `[ ]` 3. Kiểm Tra & Bàn Giao
  - `[ ]` Chạy `flutter analyze` xác thực 0 lỗi compile
  - `[ ]` Cập nhật báo cáo walkthrough.md
