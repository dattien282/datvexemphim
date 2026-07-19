# Stella Cinema (datvexemphim) — Audit toàn diện & Kế hoạch xây dựng theo Role

> Ngày lập báo cáo: 2026-07-01 · Cập nhật trạng thái: 2026-07-14 (sau khi rà soát commit `7943f38` — đợt 2 "Sửa lỗi thanh toán/điểm loyalty/combo, siết chặt Firestore rules")
> Phạm vi: toàn bộ `lib/` (~10.500 dòng), `backend-payos/` (Node.js/PayOS), cấu hình Firebase.
> Phương pháp: đọc trực tiếp toàn bộ màn hình theo từng module (Auth/Role, Booking/Payment/Staff/Theater Manager, Notification/AI/Maps).
>
> **Chú thích trạng thái:** ✅ Đã làm xong · ⚠️ Đã làm một phần / cần thao tác thủ công · *(không đánh dấu = chưa làm)*
>
> **Mục 0–5 dưới đây giữ nguyên làm hồ sơ lịch sử của đợt audit đầu (tính đến 2026-07-01).** Toàn bộ phát hiện mới, xác nhận trạng thái hiện tại, và kế hoạch tiếp theo nằm ở **[Mục 6 — Rà soát đợt 2](#6-rà-soát-đợt-2--2026-07-14-sau-commit-7943f38)** ở cuối file — đọc mục đó trước nếu chỉ muốn biết "hiện tại còn thiếu gì".

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

---

## 6. Rà soát đợt 2 — 2026-07-14 (sau commit `7943f38`)

Từ 2026-07-01 đến nay có thêm 1 commit lớn (`7943f38`, 2026-07-04, +5654/-1409 dòng trên 57 file) giải quyết phần lớn các mục P0/P1 còn tồn đọng ở Mục 3–5. Phần dưới đây xác nhận lại **từng mục cụ thể** bằng cách đọc trực tiếp code hiện tại (không suy đoán từ commit message), nêu phát hiện mới, và đề xuất việc cần làm tiếp để dự án hoàn thiện hơn.

### 6.1 Các mục P0 cũ nay đã xác nhận **hoàn thành thật sự**

| # | Hạng mục (tham chiếu Mục 3/4 cũ) | Bằng chứng |
|---|---|---|
| 1 | Nạp ví không còn ghi thẳng Firestore từ client | `profile_screen.dart` chỉ gọi dialog nạp ví, không còn set `wallet_balance`; backend có `POST /topup-wallet` (`backend-payos/server.js:586-599`) dùng Admin SDK. |
| 2 | Trừ ví khi thanh toán đã dùng transaction | `payment_service.dart:58-90` tạo vé PENDING + giữ ghế trong 1 transaction, sau đó gọi `POST /pay-wallet`; server trừ tiền/điểm/voucher trong `firestore.runTransaction` (`server.js:539-562`). |
| 3 | **Giữ ghế có transaction nguyên tử thật sự** (trước đây mục 3.2.10 đánh giá "chưa xử lý") | `seat_reservation_service.dart` (`areSeatsAvailable`/`reserveSeats`) chạy trong cùng transaction Firestore với tạo vé — 2 khách chọn trùng ghế cùng lúc sẽ có 1 người bị transaction abort, không còn double-booking do race condition ở tầng ứng dụng. |
| 4 | Huỷ vé/hoàn tiền có kiểm soát thời gian, qua transaction | `POST /cancel-ticket` (`server.js:959-1037`): transaction kiểm tra quyền sở hữu, trạng thái, chặn huỷ vé đã check-in, chặn huỷ vé COMPLETED trong vòng 30 phút trước giờ chiếu, hoàn tiền vào ví và nhả ghế `showtime_seat_status` — tất cả trong 1 transaction. |
| 5 | Tăng `currentUses` voucher đúng transaction thanh toán | Helper `bumpVoucherUsage()` (`server.js:392-402`) gọi trong cùng transaction ở cả `/pay-wallet` (strict) lẫn webhook PayOS (không strict, vì webhook có thể retry) — không còn rủi ro vượt `maxUses`. |
| 6 | Giá combo đọc đúng Firestore theo rạp | Xác nhận qua `combo_selection_screen.dart` + phần tính giá lại ở server — bảng giá cứng cũ trong `server.js` đã bị xoá. |
| 7 | Điểm loyalty tính đúng ở cả 2 luồng thanh toán | Cả `/pay-wallet` và webhook PayOS đều tính lại điểm ở server, không tin số client gửi. |
| 8 | **Xác thực email khi đăng ký — thực ra đã xong**, đánh giá "chưa làm" ở bản audit cũ là **lỗi thời** | `login_screen.dart:128-165` chặn user thường (không phải staff/manager/admin) chưa `emailVerified`, hiện dialog `_showVerifyEmailGate` (dòng 170-237) yêu cầu xác thực trước khi vào app. README (commit `7943f38`) liệt kê mục này vào "Còn tồn đọng" — **đây là điểm README bị lệch với code thật, nên sửa lại README**. |
| 9 | Ảnh CCCD xác minh tuổi dùng signed upload | Cloudinary signed upload qua `/cloudinary-sign`, yêu cầu Firebase ID token hợp lệ — không còn unsigned preset công khai. |
| 10 | Review phim yêu cầu vé COMPLETED đúng phim | Kiểm tra cả client lẫn `firestore.rules` (field `ticketId` bắt buộc trỏ đúng vé). |
| 11 | Thêm vai trò `accountant`, `marketing` trong Firestore Rules + enum | `firestore.rules`, `UserRole` enum (`user_provider.dart:6`), UI riêng trong `admin_dashboard_screen.dart:110-116`, `admin_users_screen.dart:113-125`. |

### 6.2 Phát hiện mới (chưa có trong bản audit đầu)

1. **[BUG P1 mới] Tài khoản `accountant`/`marketing` không bao giờ vào được dashboard của mình.**
   `admin_dashboard_screen.dart` đã có nhánh UI riêng cho `UserRole.accountant`/`UserRole.marketing` (dòng 110-116), nhưng điều hướng sau đăng nhập ở `login_screen.dart` (`_navigateByRole`, dòng 146-159) chỉ kiểm tra `profile.hasAdminAccess` / `hasManagerAccess` / `hasStaffAccess`. Ba getter này định nghĩa ở `user_provider.dart:70-72`:
   ```dart
   bool get hasAdminAccess => role == UserRole.admin || isAdmin;
   bool get hasManagerAccess => role == UserRole.theaterManager || hasAdminAccess;
   bool get hasStaffAccess => role == UserRole.staff || hasManagerAccess;
   ```
   → không bao gồm `accountant`/`marketing`, nên 2 role này rơi vào nhánh `else` và bị đẩy thẳng ra `HomeScreen` (giao diện khách hàng) thay vì `AdminDashboardScreen`. Kết quả: tạo tài khoản `accountant`/`marketing` từ màn Quản lý người dùng xong, đăng nhập vào **không thấy được** màn hình đã xây riêng cho họ — tính năng coi như vô dụng dù đã có đủ Firestore Rules + UI.
   **Cách sửa gọn nhất:** thêm 1 getter `hasBackofficeAccess` (bao gồm cả `accountant`/`marketing`) và dùng nó ở bước điều hướng, trỏ tới `AdminDashboardScreen` (màn này tự lọc action theo `role` sẵn rồi).

2. **File rác/trùng lặp trong `lib/features/notifications/`** — không còn liên quan tới "stub rỗng" như audit cũ nữa, mà là **file trùng tên chứa code chết**:
   - `lib/features/notifications/screens.dart`, `services.dart`, `widgets.dart` (0 dòng, stub cũ) — vẫn còn, nên xoá.
   - **Mới phát sinh**: `lib/features/notifications/screens/notification_service.dart` (44 dòng) **trùng chức năng** với `lib/features/notifications/services/notification_service.dart` (62 dòng, bản đang được import/sử dụng thật). File đặt sai thư mục (`screens/notification_service.dart`) nên dọn để tránh nhầm lẫn khi sửa sau này.

3. **`lib/core/theme.dart`, `utils.dart`, `widgets.dart` vẫn 0 dòng** — chưa dọn như audit cũ đã ghi, vẫn nên xoá vì không có import nào trỏ tới.

4. **`register_screen.dart` + `auth_service.dart` (đường đăng ký cũ) là code chết, không phải chỉ "chưa xác thực email".** Luồng đăng ký thật hiện nay nằm trong `login_screen.dart` (form đăng ký lồng trong màn đăng nhập, gọi `AuthViewModel.signUp` → `auth_repository.dart`). `register_screen.dart` dùng `AuthService.registerWithEmail` cũ, không route tới nó từ đâu cả trong `lib/` — nên xoá hẳn 2 file này (hoặc `auth_service.dart` nếu còn dùng nơi khác thì giữ, cần grep lại trước khi xoá) thay vì "dọn dẹp" nửa vời.

5. **Truy vấn `notifications` vẫn không có `.limit()`** — xác nhận lại còn nguyên ở `notification_screen.dart` (dòng ~19-23 và ~48-51, cả stream chính lẫn hàm xoá tất cả). Với tài khoản dùng lâu, số document tăng vô hạn, mỗi lần mở màn Thông báo tải toàn bộ lịch sử.

6. **Chatbot AI: đã vá được lỗ hổng lộ API key (tốt), nhưng vẫn còn 2 vấn đề hiệu năng cũ:**
   - Vẫn gọi `FirebaseFirestore.instance.collection('movies').get()` **2 lần cho mỗi tin nhắn** (dòng 52 và 80 của `cinema_ai_chatbot_screen.dart`) — nên cache trong state của widget, chỉ refetch khi mở lại màn hình.
   - Nhánh fallback không dùng Gemini vẫn hardcode giá vé/địa chỉ rạp trong chuỗi text.

7. **README (`README.md:226`, phần "Còn tồn đọng") liệt kê nhầm "chưa xác thực email khi đăng ký"** — như nêu ở mục 6.1.8, việc này đã xong từ commit `ff7c76d` (2026-07-02), **trước cả commit viết ra dòng README này** (`7943f38`, 2026-07-04). Cần sửa lại README cho khớp thực tế.

8. **`temporary_locks` (collection tên cũ trong audit đầu) không còn tồn tại như một cơ chế riêng** — đã được thay bằng `showtime_seat_status` + transaction (xem 6.1.3), nên phần "chưa xử lý" của mục 3.2.10 trong audit gốc **coi như đã giải quyết bằng cách khác tốt hơn**, không phải bằng cron dọn dẹp `temporary_locks` như dự kiến ban đầu. README hiện ghi đúng: "chỉ dọn khi client đang mở màn chọn ghế đúng suất đó" — nghĩa là nếu khách thoát app đột ngột giữa chừng chọn ghế (trước khi tạo vé PENDING), ghế có thể bị giữ tạm thời hơi lâu hơn dự kiến trong `showtime_seat_status`; **rủi ro thấp** vì `reserveSeats` chỉ chạy sau khi vé PENDING đã tạo trong cùng transaction, không phải ngay khi bấm chọn ghế — cần xác nhận thêm bằng cách đọc `seat_booking_screen.dart` nếu muốn chắc chắn 100%.

### 6.3 Bảng cập nhật độ ưu tiên còn lại (thay thế Mục 5 cho phần chưa xong)

| Ưu tiên | Hạng mục | Trạng thái |
|---|---|---|
| **P1 — Sửa ngay** | Bug điều hướng `accountant`/`marketing` không vào được dashboard (mục 6.2.1) | Chưa làm |
| **P2** | Xoá code chết: `register_screen.dart`, `auth_service.dart` (nếu không còn dùng), `lib/core/{theme,utils,widgets}.dart`, `lib/features/notifications/{screens,services,widgets}.dart` (stub cũ), `notifications/screens/notification_service.dart` (trùng) | Chưa làm |
| **P2** | `.limit()` cho truy vấn `notifications` + phân trang khi danh sách dài | Chưa làm |
| **P2** | Sửa README mục "Còn tồn đọng" (bỏ dòng email verification đã xong) | Chưa làm |
| **P3** | Cache dữ liệu phim trong chatbot thay vì query Firestore mỗi tin nhắn; bỏ hardcode giá/địa chỉ ở nhánh fallback | Chưa làm |
| **P3** | Xoay vòng Firebase API Key / Google Maps API Key (đang hardcode, được Rules bảo vệ nên không khẩn cấp nhưng nên làm nếu repo public) | Cần thao tác thủ công |
| **Đã xong ở đợt 2** | Transaction ví (nạp/trừ), transaction giữ ghế, huỷ vé/hoàn tiền qua transaction, tăng lượt voucher đúng transaction, giá combo theo Firestore, điểm loyalty 2 luồng, xác thực email, upload CCCD signed, review yêu cầu vé COMPLETED | ✅ |

### 6.4 Đề xuất tiếp theo để dự án "hoàn thiện" hơn (ngoài phạm vi bug-fix)

Đây là các hạng mục audit gốc chưa từng đề cập, mang tính hoàn thiện sản phẩm hơn là vá lỗi:

1. **Kiểm thử tự động**: `test/` hiện gần như trống (chỉ có template mặc định của `flutter create`) — với độ phức tạp nghiệp vụ hiện tại (transaction ví, voucher, giữ ghế), nên có ít nhất unit test cho `pricing_service.dart`/`discount_service.dart` (thuần Dart, dễ test, chứa logic tính tiền quan trọng nhất của app) và integration test happy-path cho luồng đặt vé.
2. **Xử lý lỗi mạng ở luồng thanh toán**: nếu app crash/mất mạng giữa lúc gọi `/pay-wallet` hoặc `/pay-payos` sau khi đã tạo vé PENDING, cần xác nhận có luồng dọn vé PENDING treo (đã có `/discard-pending-ticket` — kiểm tra nó được gọi tự động khi mở lại "Vé của tôi" hoặc chỉ khi người dùng chủ động thoát màn thanh toán).
3. **Rate limiting cho backend** (`backend-payos/server.js`): các endpoint `/pay-wallet`, `/cancel-ticket`, `/verify-checkin` hiện chỉ có `requireAuth`, chưa có giới hạn số request/phút theo user — nên cân nhắc thêm (vd. `express-rate-limit`) để chặn spam/brute-force, đặc biệt cho `/verify-checkin` (thử sai chữ ký QR liên tục).
4. **Logging có cấu trúc**: `server.js` dùng `console.log`/`console.error` rải rác — nếu deploy production thật (không chỉ chạy qua ngrok để demo), nên chuyển sang logger có level/format (pino/winston) để dễ debug khi có sự cố thanh toán thật.
5. **CI tối thiểu**: chưa thấy GitHub Actions/workflow nào — nên thêm 1 workflow chạy `flutter analyze` + `flutter test` khi có PR, tránh lỗi biên dịch lọt vào `main`.
6. **Đồng bộ Firestore Indexes**: `firestore.indexes.json` cần rà lại xem có khớp với các query mới thêm ở đợt 2 (vd. lọc `incidents` theo rạp, `shifts` theo user) — nếu thiếu index, các màn hình mới (`manager_incident_screen.dart`, `smart_roster_screen.dart`) sẽ lỗi khi data đủ lớn dù chạy mượt lúc dev với ít dữ liệu.

---

*Mục 6 được biên soạn từ việc đọc trực tiếp code hiện tại (không chỉ dựa vào commit message/README) — ngày 2026-07-14.*

---

## 7. Rà soát đợt 3 — 2026-07-19 (sau khi tách backend + tự thêm tính năng)

Từ đợt 2 tới nay, dự án có 2 luồng thay đổi lớn cộng dồn, **tất cả đều chưa commit**:

1. **Tách `backend-payos/server.js` (monolith ~2270 dòng) thành `backend-payos/src/{config,middleware,routes,services,jobs}/`** + entrypoint mới `backend-payos/index.js` — đã verify parity với `server.js` cũ (cùng response cho mọi endpoint test được), rồi chính chủ dự án tự xoá hẳn `server.js` sau khi hài lòng với bản tách.
2. **Chủ dự án tự thêm tính năng/màn hình mới và sửa code song song**: `admin_pricing_rules_screen.dart`, `admin_room_formats_screen.dart`, `theater_attendance_screen.dart`, `manager_incident_screen.dart`, `staff_incident_screen.dart`, `smart_roster_screen.dart`, `seat_heatmap_screen.dart`, `seat_layout_helper.dart`, models `movie.dart`/`theater.dart`/`user_profile.dart` tách riêng từ các provider, và tự sửa `backend-payos/src/config/firebase.js` (chuyển PayOS sang `payment.service.js` riêng) + `backend-payos/src/routes/chat.routes.js` (thêm `requireAuth` cho `/gemini-chat`).

Rà soát lần này dùng 4 lượt đọc code song song (data layer/models, backend + Firestore rules, admin/staff/manager, customer) rồi xác minh lại từng phát hiện bằng cách đọc trực tiếp file trước khi kết luận.

### 7.1 Bug nghiêm trọng — đã tìm thấy và **sửa luôn** trong đợt rà soát này

| # | Bug | Vị trí | Ảnh hưởng | Đã sửa |
|---|---|---|---|---|
| 1 | `config/firebase.js` không còn export `TICKET_SIGNING_SECRET`/`CLOUDINARY_*` sau khi chủ dự án tách `payos` sang file riêng | `backend-payos/src/config/firebase.js` | `signTicket()` (ký QR vé) crash `TypeError` ở **mọi** `/walkin-sale`, `/sign-ticket`, `/verify-checkin` — bán vé quầy/check-in gãy hoàn toàn. `/cloudinary-sign` luôn trả 503 — upload CCCD xác minh tuổi + avatar gãy hoàn toàn. | ✅ Thêm lại 4 hằng số vào export, `auth.routes.js` đổi sang dùng chung nguồn thay vì tự định nghĩa trùng lặp. |
| 2 | Đổi voucher bằng điểm thành viên dùng sai tên field Firestore | `lib/features/auth/screens/membership_screen.dart:64,70` (đọc/ghi `'loyaltyPoints'` thay vì `'loyalty_points'` — mọi nơi khác trong app + backend đều dùng `loyalty_points`) | Transaction luôn đọc ra 0 điểm → luôn báo "Bạn không đủ điểm!" dù tài khoản có đủ điểm — tính năng đổi điểm lấy voucher coi như hỏng hoàn toàn từ khi thêm. | ✅ Sửa cả 2 chỗ về `'loyalty_points'`. |
| 3 | Mất dữ liệu `wheelchairSeats` khi sửa thông tin phòng | `lib/features/theater_manager/screens/room_management_screen.dart` (`_save()`, đoạn snapshot `layoutFields` cho `seat_map_versions`) | Mỗi lần theater_manager bấm "Chỉnh sửa" phòng (kể cả chỉ đổi tên/định dạng), bản `seat_map_versions` mới được tạo **thiếu hẳn field `wheelchairSeats`** — ghế đã đánh dấu ưu tiên xe lăn "biến mất" khỏi mọi suất chiếu tạo sau đó (dù `rooms/{id}` gốc vẫn còn). | ✅ Thêm `'wheelchairSeats'` vào `layoutFields`, snapshot đúng như `brokenSeats`. |
| 4 | API import phim từ TMDB không hoạt động | `lib/features/admin/screens/admin_movies_screen.dart` gọi `/api/movies/import-tmdb`, nhưng route này chỉ tồn tại trong `backend-payos/src/routes/admin.routes.js` — **file không hề được `require` trong `app.js`** | Admin bấm "Nhập từ TMDB" trong màn Quản lý phim → luôn lỗi (404/kết nối thất bại), không tự dò được — tính năng coi như biến mất sau khi tách backend dù code vẫn còn nguyên. | ✅ Tách riêng route này ra `backend-payos/src/routes/movies.routes.js` (chỉ phụ thuộc `requireAuth`, không dính các route trùng lặp khác trong `admin.routes.js`) và mount vào `app.js`. |
| 5 | Thiếu 3 Firestore composite index cho tính năng mới | `firestore.indexes.json` | `theater_attendance_screen.dart` (query `attendance_logs` theo `theater`+`date`+order `checkInTime`), `manager_incident_screen.dart` (query `incidents` theo `theater`+order `createdAt`), và cron `updateDynamicPricing` (query `showtimes` theo `status`+range `showAt`) đều sẽ ném lỗi `FAILED_PRECONDITION` khi data đủ lớn — dev ít data nên chưa thấy lỗi. Đây chính là điều Mục 6.4.6 đã cảnh báo trước, giờ xác nhận đúng. | ✅ Thêm 3 index vào `firestore.indexes.json` — **cần tự chạy `firebase deploy --only firestore:indexes` để áp dụng thật** (mình không tự deploy lần này). |
| 6 | 2 màn hình mới không xử lý lỗi Firestore stream, hiển thị nhầm "không có dữ liệu" khi thật ra là lỗi (vd. do thiếu index ở mục 5) | `manager_incident_screen.dart`, `smart_roster_screen.dart` | Quản lý rạp thấy "Không có sự cố nào" / roster trống dù dữ liệu thật đang lỗi truy vấn — dễ hiểu nhầm là "chưa có ai báo cáo sự cố" thay vì "màn hình đang lỗi". | ✅ Thêm nhánh `snapshot.hasError` hiển thị rõ thông báo lỗi. |

### 7.2 Phát hiện khác — cần bạn quyết định, **chưa tự sửa**

| # | Vấn đề | Vị trí | Đề xuất |
|---|---|---|---|
| 1 | ~~File backend trùng lặp, không được mount, tự chứa bug riêng~~ | ~~`admin.routes.js`, `tickets.routes.js` (số nhiều), `cron/dynamic-pricing.js`, `cron/stale-ticket-cleanup.js`~~ | ✅ **Đã xoá** (2026-07-19) — lúc xoá phát hiện thêm 1 file cùng loại mà báo cáo đợt 3 bỏ sót: `src/cron/promo-push.js` (trùng phần promo-push đã có trong `src/jobs/cron.js`), đã xoá luôn cùng đợt. Xoá cả thư mục `src/cron/` rỗng sau đó. Verify lại: server boot sạch, health check OK. |
| 2 | ~~Vai trò `accountant`/`marketing` chưa có dashboard nào tồn tại~~ | ~~Grep không ra class `AccountantDashboard`/`MarketingDashboard`~~ | **Đính chính**: nhận định "chưa từng được xây" ở lần rà soát này là **sai** — `admin_dashboard_screen.dart:116-124` đã có sẵn nhánh lọc menu riêng cho `UserRole.accountant` (chỉ hiện "Báo cáo Doanh thu") và `UserRole.marketing` (chỉ hiện "Voucher & Khuyến mãi" + "Gửi thông báo chung"), tự dùng chung 1 class `AdminDashboardScreen` — không có class riêng nên grep tên class mới ra "không tìm thấy". Bug thật đúng như Mục 6.2.1 đã ghi từ đầu: chỉ là lỗi điều hướng ở `login_screen.dart` (`_navigateByRole` chỉ check `hasAdminAccess`/`hasManagerAccess`/`hasStaffAccess`, thiếu nhánh cho 2 role này) — fix nhỏ, không phải xây dashboard mới. ✅ **Đã fix** (2026-07-19): thêm getter `hasBackofficeAccess` vào `user_profile.dart`, dùng ở `_navigateByRole` + cổng OTP (`_isPrivilegedAccount`) + cổng xác thực email trong `login_screen.dart` — accountant/marketing giờ vào đúng `AdminDashboardScreen` và được miễn OTP/email-verification như các tài khoản do admin cấp khác. |
| 3 | **Giá vé lệch giữa client và server cho suất chiếu có `sessionType` đặc biệt** | `lib/features/booking_and_payment/services/pricing_service.dart` (áp dụng phụ thu/giảm giá riêng cho Midnight/Sneak Show/First Day/Marathon/Fan Screening/Special Event) vs `backend-payos/src/services/pricing.service.js` hàm `timeSurcharge()` (chỉ biết giờ &lt;12/&ge;22, không biết gì về `sessionType`) | Khi collection `pricing_rules` còn trống (đang là mặc định hiện tại), server tính tiền thật (`computeAuthoritativeAmount`, luôn thắng client) có thể **khác** giá hiển thị lúc khách chọn ghế cho các suất chiếu đặc biệt này. ✅ **Đã fix** (2026-07-19): thêm bảng `SESSION_TYPE_ADJUSTMENTS` (mirror `kSessionTypeSpecs`) vào `pricing.service.js`, `timeSurcharge()` nhận thêm tham số `sessionType` — ưu tiên bảng, fallback công thức giờ cũ cho suất chưa có sessionType. Verify bằng script đối chiếu 18 case JS vs Dart: tất cả khớp. |
| 4 | **Màn "Bảo trì ghế" cũ của theater_manager chưa hỗ trợ ghế ưu tiên xe lăn** | `room_management_screen.dart` (`_SeatMaintenanceDialog` nội bộ, mở từ menu "Bảo trì ghế" trong danh sách phòng) chỉ toggle được `brokenSeats`, không có `wheelchairSeats`/`MaintenanceTarget` như `staff_seat_maintenance_screen.dart` (bản mới hơn) | ✅ **Đã fix** (2026-07-19): `_SeatMaintenanceDialog` giờ có 2 ChoiceChip GHẾ HỎNG/GHẾ XE LĂN (mirror pattern `staff_seat_maintenance_screen.dart`), toggle + lưu cả `wheelchairSeats` vào cả room doc lẫn `seat_map_versions`. |
| 5 | Vài nit nhỏ không ảnh hưởng chức năng | `pricing_service.dart` (Dart): field `isWeekend` trong `PricingEngine.resolve` suy từ `weekendSurcharge != 0` thay vì check thứ Bảy/Chủ Nhật thật — hiện chưa ai đọc field này nên chưa gây bug, nhưng là bẫy cho người dùng sau; `seat_layout_helper.dart` comment ghi công thức trọng số `0.4/0.3/0.2` nhưng code là `0.4/0.3/0.3`; comment cũ còn nhắc tên `kRoomFormatSpecs` dù đã đổi thành `kDefaultRoomFormatSpecs`. | ✅ **Đã sửa hết** (2026-07-19): `isWeekend` check thứ Bảy/CN thật; comment trọng số sửa thành `0.4/0.3/0.3` khớp code; 3 comment `kRoomFormatSpecs` đổi thành `kDefaultRoomFormatSpecs`. |

### 7.3 Xác nhận sạch (không có vấn đề)

- Toàn bộ 5 file model/provider mới (`movie.dart`, `theater.dart`, `user_profile.dart`, `room_formats_provider.dart`, 2 widget mới trong `lib/core/widgets/` + `lib/features/home/widgets/`) đều là tách refactor sạch, được import/dùng đúng chỗ, không trùng lặp định nghĩa.
- Xoá 5 file rác cũ (`lib/core/theme.dart`/`utils.dart`/`widgets.dart`, `lib/data/models.dart`/`services.dart`) không để lại import gãy nào.
- Rules Firestore khớp đủ với mọi collection backend đọc/ghi; không có `allow write: if true` nào lộ ra ngoài ý muốn; `otp_codes`/`checkin_audit_log` đúng như thiết kế (chỉ Admin SDK truy cập, không rule cho client — không phải thiếu sót).
- `AndroidManifest.xml` chỉ thêm 2 `meta-data` cho icon/màu thông báo FCM — không có quyền mới hay nguy cơ bảo mật.
- Dropdown thiếu `isExpanded` (bug tràn viền tìm thấy đầu đợt rà soát này) đã rà lại toàn bộ 13 file admin/staff/manager có dùng Dropdown — không sót chỗ nào.
- `cinema_ai_chatbot_screen.dart` đã cập nhật đúng để gửi kèm token khi `/gemini-chat` được thêm `requireAuth` — khách vãng lai không bị lỗi, chỉ tự động rơi về chế độ trả lời offline (có thể cân nhắc thêm dòng thông báo "Đăng nhập để chat với AI" cho rõ ràng hơn, không bắt buộc).

### 7.4 Việc cần bạn tự làm

1. **Deploy lại Firestore rules/indexes**: `firebase deploy --only firestore:rules,firestore:indexes` (mình không tự deploy lần này vì đã hỏi ý kiến bạn ở lượt trước rồi mới làm — lần này để bạn chủ động).
2. Quyết định có xoá 4 file backend thừa ở mục 7.2.1 không.
3. Quyết định độ ưu tiên xây dashboard `accountant`/`marketing` (mục 7.2.2) — việc lớn, không phải bugfix.
4. Xác nhận có cần fix ngay lệch giá `sessionType` (mục 7.2.3) hay để sau khi có dữ liệu `pricing_rules` thật (khi đó server tự ưu tiên đọc từ đó, ít bị lệch hơn).

---

*Mục 7 biên soạn bằng 4 lượt đọc code song song + xác minh lại thủ công từng phát hiện bằng cách đọc trực tiếp file hiện tại — ngày 2026-07-19. Các bug ở mục 7.1 đã được sửa trực tiếp trong lúc rà soát; mục 7.2 chỉ báo cáo, chưa động vào code.*
