# Stella Cinema (datvexemphim) — Audit toàn diện & Kế hoạch xây dựng theo Role

> Ngày lập báo cáo: 2026-07-01 · Cập nhật trạng thái: 2026-07-01 (sau khi triển khai Phase 0–4)
> Phạm vi: toàn bộ `lib/` (~10.500 dòng), `backend-payos/` (Node.js/PayOS), cấu hình Firebase.
> Phương pháp: đọc trực tiếp toàn bộ màn hình theo từng module (Auth/Role, Booking/Payment/Staff/Theater Manager, Notification/AI/Maps).
>
> **Chú thích trạng thái:** ✅ Đã làm xong · ⚠️ Đã làm một phần / cần thao tác thủ công · *(không đánh dấu = chưa làm)*

---

## 1. Tổng quan kiến trúc

- **Frontend:** Flutter + Riverpod (state management tối thiểu — hầu hết logic nằm thẳng trong widget của từng màn hình, không có tầng service/repository thực sự).
- **Backend:** Firebase (Auth, Firestore, Storage, Cloud Messaging) là "backend chính". Có thêm một Node.js server riêng (`backend-payos/server.js`) chỉ để tạo link thanh toán PayOS.
- **File rỗng/chết:** `lib/core/constants.dart`, `theme.dart`, `utils.dart`, `widgets.dart`, `lib/features/notifications/{screens,services,widgets}.dart` đều 0 dòng — là stub chưa từng triển khai, nên xoá hoặc hiện thực hoá.
- **Không có Firestore Security Rules nào được tìm thấy trong repo** → đây là lỗ hổng nghiêm trọng nhất của toàn bộ dự án (xem mục 3).

---

## 2. Các Role trong hệ thống

Định nghĩa tại `lib/providers/user_provider.dart:6-64`, field `role` lưu trong Firestore `users/{uid}`:

| Role (giá trị lưu) | Ý nghĩa | Điều hướng sau đăng nhập |
|---|---|---|
| `user` (mặc định) | Khách hàng | `HomeScreen` |
| `staff` | Nhân viên rạp (check-in vé) | `StaffDashboardScreen` |
| `theater_manager` | Quản lý rạp (theo `assignedTheater`) | `TheaterManagerDashboardScreen` |
| `admin` | Quản trị hệ thống | `AdminDashboardScreen` |

Có thêm field cũ `isAdmin: boolean` song song với `role` (kỹ thuật nợ — 2 nguồn sự thật cho cùng một quyền, `admin_users_screen.dart` phải set cả hai mỗi khi đổi role).

**Vấn đề cốt lõi:** toàn bộ phân quyền là **client-side only**. `lib/main.dart:99-131` và `login_screen.dart:74-100` chỉ đọc `role` từ Firestore rồi điều hướng UI — không có Firestore Security Rules, không có Cloud Functions xác thực. Bất kỳ ai có thể tự sửa document `users/{uid}.role = "admin"` qua Firebase client SDK và có toàn quyền.

---

## 3. Business logic — Phát hiện nghiêm trọng nhất (toàn hệ thống)

### 3.1 Bảo mật (P0 — chặn production)
1. ✅ **Không có Firestore Security Rules** — đã tạo `firestore.rules` (gốc repo), mirror đúng `hasAdminAccess/hasManagerAccess/hasStaffAccess`. **Cần bạn tự deploy**: `firebase deploy --only firestore:rules,firestore:indexes`.
2. ✅ **Phân quyền admin/staff/manager chỉ kiểm tra ở client** — giờ đã được backup bởi Firestore Rules (mục 1) + middleware `requireStaffAuth` xác thực Firebase ID token trên `backend-payos/server.js` cho thao tác check-in.
3. ⚠️ **API key/secret bị hardcode trong source** — đã thêm `.gitignore` chặn `backend-payos/.env`/`serviceAccountKey.json` khỏi bị commit, đã sinh `TICKET_SIGNING_SECRET` mới. **Firebase API Key và PayOS credentials cũ vẫn chưa được xoay vòng — bạn cần tự làm** (Firebase Console + PayOS dashboard).
4. **Nạp ví (`wallet_balance`) ghi trực tiếp từ client** (`profile_screen.dart:189-263`) — *chưa xử lý*, vẫn không qua transaction/Cloud Function.
5. **Trừ ví khi thanh toán không dùng Firestore transaction** (`payment_screen.dart`) — *chưa xử lý*, vẫn có rủi ro race condition.

### 3.2 Đặt vé & Thanh toán (P0)
6. ✅ **Webhook PayOS không cập nhật Firestore** — đã nối `firebase-admin`, webhook tìm vé theo `orderCode` và set `paymentStatus = COMPLETED` (có idempotency guard + tự ký QR check-in). **Cần bạn đặt `serviceAccountKey.json` vào `backend-payos/`**.
7. ✅ **`_processToPayment()` crash** — xác minh lại: **không tái hiện**, code hiện tại đã đúng, không phải bug thật.
8. ✅ **Backend hardcode `http://10.0.2.2:3000`** — đã chuyển sang `AppConfig.paymentBackendUrl` (`--dart-define=PAYMENT_BACKEND_URL=...`), mặc định giữ nguyên giá trị cũ.
9. ✅ **`orderCode` không duy nhất** — đã đổi sang `Date.now() * 1000 + random`, không còn trùng lặp.
10. **Không có transaction/khoá nguyên tử khi giữ ghế** — *chưa xử lý*, `temporary_locks` vẫn không có transaction thật sự (rủi ro double-booking khi tải cao vẫn còn, dù đã fix được phần "vé không bao giờ COMPLETED" ở mục 6).
11. ✅ **Hai hệ thống giảm giá song song** — đã gộp: `payment_screen.dart` giờ đọc `vouchers` (cùng nguồn với Admin/Theater Manager quản lý), kiểm tra hạn dùng/số lượt/đơn tối thiểu/đúng rạp.
12. ⚠️ **Không tăng `currentUses` theo transaction** — đã thêm `FieldValue.increment(1)` khi thanh toán xong (cả 2 luồng), nhưng **không dùng Firestore transaction** nên vẫn có rủi ro hiếm khi vượt nhẹ `maxUses` lúc tải cao đồng thời — đã ghi chú trong code.

### 3.3 Check-in / Vé (P1)
13. ✅ **QR không ký số** — đã ký HMAC-SHA256 qua `backend-payos/server.js` (`/sign-ticket`, `/verify-checkin`), QR trong "Kho vé của tôi" giờ là QR thật mã hoá `{ticketId, signature}` (trước đây chỉ là hình trang trí không quét được).
14. ✅ **Không kiểm tra khung giờ khi check-in** — `/verify-checkin` chặn check-in ngoài khoảng -30 đến +180 phút quanh giờ chiếu.
15. ✅ **Không có audit log check-in/đổi quyền/xoá phim** — đã thêm `checkin_audit_log` (server ghi) và `admin_audit_log` (đổi role, CRUD phim/voucher).

### 3.4 Nhất quán dữ liệu (P1)
16. ✅ **Tên field không nhất quán** — đã chuẩn hoá toàn bộ schema `tickets` (`totalAmount`, `paymentStatus`, `theaterName`/`showDate`/`showTime`...) và migrate mọi nơi đọc/ghi (payment, seat booking, my tickets, staff, theater manager, admin dashboard, admin revenue).
17. ✅ **Ticket có cả `title` và `movieTitle`** — đã thống nhất về `movieTitle`.
18. ⚠️ **User có cả `role` và `isAdmin`** — phía đọc đã hợp nhất từ trước (`user_provider.dart`); giữ nguyên việc ghi cả 2 field khi đổi role để tương thích ngược (quyết định có chủ đích, không phải bug).
19. ⚠️ **Rạp/khung giờ/giá vé/combo hardcode nhiều nơi** — **rạp** đã đưa về Firestore (`theaters` collection + `theaters_provider.dart`, thay 3 danh sách không khớp nhau trước đó); **giá vé** giờ lấy từ `showtimes` nếu suất chiếu thật tồn tại. **Combo vẫn còn hardcode** (`combo_selection_screen.dart`) — chưa xử lý.
20. ✅ **Xoá phim không cascade** — đã chuyển sang soft-delete (`isDeleted`, `deletedAt`), lọc ở `movies_provider.dart` nên ẩn khỏi mọi nơi mà không mất dữ liệu vé/đánh giá cũ.

### 3.5 Khác
21. FCM token bị `log()` ra console — *chưa xử lý*.
22. Truy vấn `notifications` không có `.limit()` — *chưa xử lý*.
23. Chatbot AI gọi lại Firestore mỗi tin nhắn, giá/địa chỉ hardcode — *chưa xử lý*.
24. Không có xác thực email khi đăng ký; `register_screen.dart` không dùng — *chưa xử lý*.

---

## 4. Kế hoạch chi tiết theo từng Role

### 4.1 Role: `user` (Khách hàng)

**Hiện trạng workflow:** Xem phim (Home) → Chi tiết phim → Chọn rạp/suất → Chọn ghế → Chọn combo (❌ crash tại đây) → Thanh toán (ví hoạt động, chuyển khoản hỏng) → Vé của tôi.

**Kế hoạch:**
1. ✅ **[Khẩn cấp] Fix crash đặt vé** — xác minh không tái hiện, code đã đúng.
2. ✅ **[Khẩn cấp] Sửa luồng thanh toán chuyển khoản** — đã nối webhook↔Firestore qua `firebase-admin`, URL backend đã cấu hình được qua `--dart-define`.
3. ✅ **Gộp hệ thống khuyến mãi** — `payment_screen.dart` đọc `vouchers`, không còn `promotions` riêng biệt.
4. ✅ **Đưa dữ liệu rạp/suất chiếu/giá vé về Firestore** — `theaters` collection dùng chung; `showtime_selection_screen.dart` tra cứu suất chiếu thật do Theater Manager tạo, tự rơi về khung giờ mẫu nếu rạp chưa có suất chiếu.
5. **Thêm cơ chế huỷ vé / hoàn tiền có kiểm soát thời gian, qua transaction** — *chưa làm* (huỷ vé vẫn hoạt động như cũ, không giới hạn theo giờ chiếu, hoàn ví không transaction).
6. **Thêm xác thực email khi đăng ký, dọn `register_screen.dart`** — *chưa làm*.
7. **Nâng cấp hạng thành viên có ưu đãi thật** — *chưa làm*.
8. **Giới hạn `.limit()` cho truy vấn thông báo, lọc theo user** — *chưa làm*.

### 4.2 Role: `staff` (Nhân viên rạp)

**Hiện trạng:** Danh sách vé hôm nay theo rạp được gán (`assignedTheater`) + quét QR check-in + thống kê ca.

**Kế hoạch:**
1. ✅ **Ký số QR vé** (HMAC-SHA256) — `sign-ticket`/`verify-checkin` trên `backend-payos/server.js`.
2. ✅ **Kiểm tra khung giờ suất chiếu khi check-in** — chặn ngoài khoảng -30/+180 phút quanh giờ chiếu.
3. ✅ **Chuẩn hoá field đọc/ghi** — toàn bộ dùng `paymentStatus`/`totalAmount`.
4. ✅ **Thêm nhật ký check-in (audit log)** — collection `checkin_audit_log`, ghi bởi server.
5. **Thêm kênh liên lạc/báo cáo sự cố tới Theater Manager** — *chưa làm*.
6. ✅ **Ràng buộc quyền server-side** — middleware `requireStaffAuth` (xác minh Firebase ID token + role qua Admin SDK) thay cho Cloud Function; Firestore Rules cũng chặn ghi trực tiếp không đúng quyền.

### 4.3 Role: `theater_manager` (Quản lý rạp)

**Hiện trạng:** Tạo/sửa suất chiếu theo rạp được gán, xem doanh thu rạp, xem danh sách nhân viên rạp.

**Kế hoạch:**
1. ✅ **Kết nối suất chiếu do Theater Manager tạo với luồng đặt vé thực tế** — `showtime_selection_screen.dart` tra cứu `showtimes` theo rạp+phim, dùng giá STD/VIP thật khi có; fallback khung giờ mẫu khi rạp chưa có suất chiếu.
2. ✅ **Sửa lệch tên field doanh thu** — đồng bộ `totalAmount`/`paymentStatus`/`theaterName` với Admin.
3. ✅ **Cho phép quản lý voucher riêng rạp** — tab **VOUCHER** mới trong dashboard, `theaterScope` field, chỉ thấy/tạo voucher rạp mình.
4. ✅ **Quản lý phòng chiếu / sức chứa ghế theo từng phòng** — màn `room_management_screen.dart` mới, `seat_booking_screen.dart` render sơ đồ ghế động theo phòng đã cấu hình.
5. ✅ **Phân quyền server-side giới hạn theo `assignedTheater`** — Firestore Rules + `backend-payos` middleware đều kiểm tra `assignedTheater`.
6. **Quản lý/gán ca làm việc cho nhân viên** — *chưa làm* (vẫn chỉ xem danh sách).

### 4.4 Role: `admin` (Quản trị hệ thống)

**Hiện trạng:** Quản lý phim (CRUD), quản lý người dùng & phân quyền, quản lý voucher, xem báo cáo doanh thu tổng.

**Kế hoạch:**
1. ✅ **[Khẩn cấp] Viết Firestore Security Rules** — `firestore.rules` đã tạo, che toàn bộ collection chính. **Cần bạn tự deploy qua Firebase CLI.**
2. ⚠️ **Chuyển thao tác nhạy cảm sang backend có xác thực** — đã làm cho **check-in/ký QR** (qua `backend-payos` + middleware xác thực token, không dùng Cloud Functions). **Đổi role, cộng ví, tăng lượt voucher vẫn ghi thẳng từ client** (được Firestore Rules chặn ở mức hợp lý nhưng chưa qua Cloud Function).
3. ✅ **Cascade xoá / soft delete phim** — đã chuyển sang `isDeleted: true`.
4. ✅ **Audit log hành động admin** — collection `admin_audit_log` (đổi role, CRUD phim/voucher).
5. ✅ **Hợp nhất `role`/`isAdmin`** — phía đọc đã hợp nhất sẵn, xác nhận giữ nguyên ghi cả 2 field có chủ đích.
6. ✅ **Báo cáo doanh thu chi tiết hơn** — bộ lọc theo rạp (dùng `theatersProvider`), trừ vé `CANCELLED` khỏi doanh thu.
7. ✅ **Đưa danh sách rạp về Firestore** — `theaters` collection + `theaters_provider.dart`, thay hardcode ở `admin_users_screen.dart`, `showtime_selection_screen.dart`, `admin_revenue_screen.dart`.
8. ⚠️ **Dọn dẹp file rỗng** — chỉ `lib/core/constants.dart` đã hiện thực hoá (dùng cho `AppConfig`). `theme.dart`, `utils.dart`, `widgets.dart`, `lib/features/notifications/{screens,services,widgets}.dart` **vẫn còn rỗng** — chưa dọn.
9. ⚠️ **Xoay vòng secret bị lộ** — đã sinh `TICKET_SIGNING_SECRET` mới + gitignore `.env`/`serviceAccountKey.json`. **Firebase API Key và PayOS credentials cũ vẫn cần bạn tự xoay vòng thủ công.**

---

## 5. Độ ưu tiên tổng hợp

| Ưu tiên | Hạng mục | Trạng thái |
|---|---|---|
| **P0 — Phải làm trước khi phát hành thật** | Firestore Security Rules; fix crash `_processToPayment`; nối webhook PayOS↔Firestore; sửa URL backend hardcode | ✅ Xong (rules cần bạn tự deploy) |
| **P0 — còn lại** | Transaction cho ví (nạp/trừ tiền), transaction cho seat lock | Chưa làm |
| **P1 — Ưu tiên cao** | Ký số QR check-in; hợp nhất `promotions`/`vouchers`; chuẩn hoá field dữ liệu; kết nối suất chiếu thật vào luồng đặt vé; cascade xoá phim | ✅ Xong |
| **P2 — Nên làm** | Audit log (✅ xong); hạng thành viên có ưu đãi thật; huỷ vé/hoàn tiền có kiểm soát; quản lý rạp tập trung ở Firestore (✅ xong); email verification | Một phần đã xong |
| **P3 — Cải thiện dài hạn** | Phân trang truy vấn; cache chatbot; dọn dẹp file rỗng (một phần); logging có cấu trúc thay vì `print()`; rotate secret cũ (Firebase/PayOS) | Chưa làm / cần thao tác thủ công |

**Việc bạn cần tự làm (không thể tự động hoá được):**
1. `firebase deploy --only firestore:rules,firestore:indexes` (cần `firebase login` + `firebase use <project-id>`).
2. Tải `serviceAccountKey.json` từ Firebase Console → đặt vào `backend-payos/`.
3. `npm install` trong `backend-payos/`.
4. Seed dữ liệu `theaters` vào Firestore (xem `tool/seed_theaters.dart`).
5. Xoay vòng Firebase API Key và PayOS credentials cũ (đã có nguy cơ lộ trước khi được gitignore).

---

*Báo cáo tổng hợp từ 3 lượt rà soát song song trên toàn bộ mã nguồn Flutter và backend Node.js/PayOS.*
