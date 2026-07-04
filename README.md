# Stella Cinema (dat_ve_xem_phim_group5)

Dự án ứng dụng đặt vé xem phim toàn diện được phát triển bằng **Flutter** và **Firebase**, cùng với Node.js Express server phục vụ cổng thanh toán PayOS. Ứng dụng cung cấp một quy trình khép kín, phục vụ đầy đủ nhu cầu của Khách hàng (User), Nhân viên soát vé (Staff), Quản lý cụm rạp (Theater Manager), Kế toán/Marketing và Quản trị viên (Admin).

> 📌 Repo: https://github.com/dattien282/datvexemphim
> 📄 Lịch sử audit kỹ thuật chi tiết (trước đợt cải thiện này): xem [`AUDIT_AND_ROADMAP.md`](AUDIT_AND_ROADMAP.md).

---

## 🌟 Các tính năng nổi bật & Quy trình (Workflow)

Hệ thống phân quyền Role-Based Access Control (RBAC) với 6 vai trò: `user`, `staff`, `theater_manager`, `admin`, `accountant`, `marketing` — mỗi vai trò có giao diện và chức năng riêng biệt.

### 1. Khách hàng (User)
- **Đăng nhập/Đăng ký**: Hỗ trợ đăng nhập Email/Password, Google Sign-In.
- **Trang chủ & Khám phá phim**: Xem danh sách phim Đang chiếu, Sắp chiếu, Banner khuyến mãi nổi bật.
- **Quy trình Đặt vé**:
  1. Chọn phim, xem chi tiết, trailer và đánh giá (đánh giá yêu cầu đã có vé COMPLETED cho đúng phim đó).
  2. Chọn rạp, ngày chiếu, giờ chiếu. Xác thực độ tuổi tự động (nếu phim yêu cầu T18, bắt buộc xác minh CCCD qua ảnh chụp — upload có ký số, không public).
  3. Chọn ghế trên sơ đồ rạp (Thường/VIP/Sweetbox-Couple, nhiều định dạng phòng: IMAX/4DX/ScreenX/Dolby Atmos...). Hỗ trợ khóa ghế tạm thời (Lock) 5 phút để tránh trùng lặp, tự dọn dẹp khi hết hạn.
  4. Chọn Combo Bắp Nước (giá theo từng rạp, xác thực lại ở server trước khi trừ tiền).
  5. **Thanh toán**:
     - Áp dụng Voucher hoặc ưu đãi tự động (hạng thành viên/Happy Wednesday) — hệ thống áp dụng mức có lợi hơn, không cộng dồn cả hai; điểm loyalty vẫn cộng thêm được.
     - Hỗ trợ thanh toán qua **PayOS** (chuyển khoản/QR ngân hàng) hoặc **Stella Wallet** (ví nội bộ, nạp/trừ đều qua backend, không ghi trực tiếp từ app).
- **Quản lý Vé (Kho Vé)**: xem vé đã đặt (kèm đúng tên phòng chiếu + thời lượng phim thật), mã QR ký số chống giả mạo, huỷ vé/hoàn tiền có kiểm soát thời gian (≥30 phút trước giờ chiếu với vé đã thanh toán).
- **Loyalty System**: tích điểm khi mua vé, đổi điểm giảm giá khi thanh toán.
- **Thông báo**: nhận thông báo khi đặt vé thành công, sắp đến giờ chiếu...

### 2. Nhân viên rạp (Staff)
- **Dashboard**: vé bán ra trong ngày, thống kê ca làm việc, ca của chính mình (không thấy ca rạp khác).
- **Soát vé (QR Scanner)**: quét mã QR, xác thực chữ ký + khung giờ hợp lệ qua backend.
- **Bán vé tại quầy**: đặt vé trực tiếp, thanh toán tiền mặt, có transaction chống double-booking ghế.
- **Báo cáo Sự cố**, **Bảo trì ghế hỏng** (ghế hỏng bị chặn đặt ở cả app lẫn quầy).

### 3. Quản lý cụm rạp (Theater Manager)
- **Dashboard doanh thu/heatmap ghế theo thời gian thực.**
- **Smart Roster**: phân ca nhân viên.
- **Quản lý phòng chiếu**: cấu hình sơ đồ ghế, đánh dấu ghế hỏng.
- **Tạo suất chiếu**: tự động chống trùng giờ trong cùng phòng theo đúng thời lượng phim thật (tra từ collection `movies`, không còn giả định cố định 150 phút cho mọi phim).

### 4. Kế toán (Accountant) — *vai trò mới*
- Xem báo cáo doanh thu (đã có quyền đọc `tickets` trong Firestore Rules).

### 5. Marketing — *vai trò mới*
- Quản lý Voucher & gửi thông báo broadcast (đã có quyền ghi `vouchers`/`promotions`).

### 6. Quản trị viên (Admin)
- Quản lý phim, cụm rạp, người dùng/phân quyền, cấu hình server (API keys qua UI), voucher, xác minh tuổi (duyệt CCCD).

---

## ⚙️ Kiến trúc Hệ thống

- **Frontend**: Flutter (Android là nền tảng chính đang được build/test; iOS/Windows/macOS/Linux có khung sườn nhưng chưa được kiểm thử đầy đủ).
- **State Management**: Riverpod.
- **Backend / Cơ sở dữ liệu**:
  - **Firebase Authentication**, **Cloud Firestore** (collections chính: `users`, `movies`, `showtimes`, `theaters`, `rooms`, `tickets`, `combos`, `vouchers`, `temporary_locks`, `showtime_seat_status`, `shifts`, `incidents`, `movie_reviews`, `age_verification_requests`, `notifications`, `admin_audit_log`, `checkin_audit_log`).
  - **Firestore Security Rules** (`firestore.rules`) khớp đúng logic client — **bắt buộc phải deploy**, xem mục Cài đặt bên dưới.
  - **Firebase Storage** (`storage.rules`): avatar (public) + ảnh CCCD xác minh tuổi (chỉ chủ ảnh + admin đọc được).
- **Payment & Security Server** (`backend-payos/`, Node.js Express):
  - Tích hợp PayOS tạo Payment Link, xác thực webhook.
  - Ký/xác thực QR vé (HMAC-SHA256).
  - **Toàn bộ thao tác đụng tới tiền/điểm/vé đều tính lại authoritative ở server** (không tin số liệu client gửi): giá ghế, combo, voucher, giảm giá tự động, điểm loyalty.
  - Ví Stella Wallet (nạp/trừ), huỷ vé PENDING dở dang, cấp chữ ký upload ảnh CCCD lên Cloudinary — tất cả đi qua Admin SDK, không cho client ghi thẳng Firestore.
- **Routing**: Deep Link (`stella://`) xử lý callback PayOS (thành công/huỷ).

---

## 🚀 Hướng dẫn Cài đặt & Chạy Dự án (dành cho máy mới clone repo)

### 0. Yêu cầu phiên bản công cụ

| Công cụ | Phiên bản khuyến nghị | Ghi chú |
|---|---|---|
| Flutter SDK | **3.35+** (đã test với 3.44.4) | `sdk: ^3.11.5` trong `pubspec.yaml` yêu cầu Dart ≥ 3.11.5 |
| Dart SDK | đi kèm Flutter (≥ 3.11.5, đã test 3.12.2) | |
| Node.js | **18+** (khuyến nghị 20+) | dùng cho `backend-payos/` |
| Android Studio / JDK | JDK **17** | `android/app/build.gradle.kts` ép `sourceCompatibility/targetCompatibility = VERSION_17` |
| Android Gradle Plugin | 8.12.1 (đã khai báo sẵn trong `android/settings.gradle.kts`) | không cần chỉnh |
| Kotlin | 2.2.20 (đã khai báo sẵn) | không cần chỉnh |
| NDK | 28.2.13676358 (đã khai báo sẵn trong `android/app/build.gradle.kts`) | Android Studio sẽ tự tải nếu thiếu |
| Firebase CLI | mới nhất (`npm i -g firebase-tools`) | để deploy rules/indexes |
| ngrok (hoặc tương đương) | bất kỳ | để PayOS webhook gọi được vào máy local |

Kiểm tra nhanh môi trường: `flutter doctor -v`.

### 1. Clone & lấy các file cấu hình bí mật (KHÔNG có trong git)

Các file sau chứa secret nên **không được commit** — bạn cần xin trực tiếp từ chủ dự án (qua Zalo/Drive nội bộ nhóm) hoặc tự tạo Firebase project riêng nếu muốn tách dữ liệu:

| File cần xin/tạo | Đặt vào đâu | Dùng để làm gì |
|---|---|---|
| `google-services.json` | `android/app/google-services.json` | Bắt buộc để Gradle build Android (plugin `com.google.gms.google-services` yêu cầu file này tồn tại, dù config Firebase runtime đã hardcode sẵn trong `lib/main.dart`) |
| `serviceAccountKey.json` | `backend-payos/serviceAccountKey.json` | Firebase Admin SDK cho backend (thanh toán, ví, check-in, huỷ vé... đều cần) |
| `.env` | `backend-payos/.env` | Xem bảng biến môi trường ở bước 2 |

> Firebase project hiện tại: `datvexemphimgroup5` (project ID, xem `lib/main.dart`). Nếu dùng chung project với nhóm, bạn cần được thêm làm **Editor/Owner** trong Firebase Console (Project Settings → Users and permissions) để tự tải `google-services.json`/`serviceAccountKey.json` cho tài khoản của mình.

### 2. Cài đặt Backend (`backend-payos/`)

```bash
cd backend-payos
npm install
```

Tạo file `.env` (cùng cấp `package.json`) với nội dung:

```env
PORT=3000

# PayOS - lấy tại https://business.payos.vn (Kênh thanh toán > API Keys)
PAYOS_CLIENT_ID=...
PAYOS_API_KEY=...
PAYOS_CHECKSUM_KEY=...

# Ký/xác thực QR vé - tự sinh 1 chuỗi ngẫu nhiên đủ dài, KHÔNG dùng giá trị mặc định khi chạy thật
TICKET_SIGNING_SECRET=doi_thanh_chuoi_ngau_nhien_that_dai_cua_ban

# Cloudinary - dùng để upload ảnh CCCD xác minh tuổi (signed upload, không public)
# Lấy tại Cloudinary Console > Dashboard > Account Details
CLOUDINARY_CLOUD_NAME=g9u2mtmv
CLOUDINARY_API_KEY=...
CLOUDINARY_API_SECRET=...

# Tuỳ chọn - chatbot AI Gemini; có thể để trống và cấu hình qua Admin > Server Config trong app thay vì .env
GEMINI_API_KEY=
```


Phần này là file `.env` cho `backend-payos` (server Node.js). Đây là mức độ cần thiết của từng phần:

| Biến | Có cần điền không | Vì sao |
|---|---|---|
| `PORT` | Không cần đổi | Mặc định 3000 là ổn |
| `PAYOS_CLIENT_ID/API_KEY/CHECKSUM_KEY` | **Chỉ cần nếu test thanh toán "Chuyển khoản ngân hàng (VietQR)"** | Không điền thì nút này sẽ lỗi khi bấm, nhưng thanh toán bằng **Ví Stella Wallet** (vừa sửa xong) vẫn chạy bình thường không cần cái này |
| `TICKET_SIGNING_SECRET` | **Nên đổi**, dù chỉ test local | Dùng ký/xác thực QR vé check-in — giá trị mặc định trong file không an toàn, đổi thành 1 chuỗi ngẫu nhiên bất kỳ (VD chạy `openssl rand -hex 32` hoặc gõ đại 1 chuỗi dài) |
| `CLOUDINARY_*` | **Chỉ cần nếu test luồng xác minh tuổi 18+** | Dùng upload ảnh CCCD; phim thường không đụng tới |
| `GEMINI_API_KEY` | Không bắt buộc | Để trống được — chatbot sẽ chạy chế độ offline, hoặc điền sau qua **Admin → Cấu hình server** ngay trong app (không cần sửa file này) |

Tóm lại: nếu chỉ đang test luồng đặt vé + thanh toán ví, chỉ cần đổi `TICKET_SIGNING_SECRET` là đủ chạy được, các mục còn lại điền sau khi cần test đúng tính năng đó.

Đặt file `serviceAccountKey.json` (xin từ chủ dự án) vào thư mục `backend-payos/`.


Chạy server:
```bash
npm start
# hoặc: node server.js
```
Server chạy tại `http://localhost:3000`. Log khởi động sẽ báo `✅ Firebase Admin SDK initialized.` nếu `serviceAccountKey.json` hợp lệ — nếu thấy cảnh báo `⚠️ Firebase Admin SDK init failed`, kiểm tra lại file này trước khi tiếp tục (gần như mọi tính năng thanh toán/vé sẽ không hoạt động nếu thiếu).

**Cho PayOS webhook gọi được vào máy bạn** (bắt buộc để trạng thái vé tự chuyển COMPLETED sau khi chuyển khoản):
```bash
ngrok http 3000
```
Lấy URL `https://xxxx.ngrok-free.app` và khai báo trong PayOS Dashboard → Webhook → trỏ tới `https://xxxx.ngrok-free.app/payos-webhook`.

### 3. Cài đặt Frontend (Flutter App)

```bash
flutter pub get
```

Đặt `google-services.json` (xin từ chủ dự án) vào `android/app/google-services.json`.

**Cấu hình địa chỉ backend** (mặc định `lib/core/constants.dart` trỏ tới `http://10.0.2.2:3000`, chỉ đúng khi chạy Android Emulator + backend chạy localhost cùng máy):

- Chạy Android Emulator + backend cùng máy: **không cần chỉnh gì**, dùng mặc định.
- Chạy trên thiết bị thật / iOS simulator, hoặc backend chạy máy khác: truyền `--dart-define` khi chạy/build:
  ```bash
  flutter run --dart-define=PAYMENT_BACKEND_URL=https://xxxx.ngrok-free.app
  ```

**Chạy ứng dụng**:
```bash
flutter run
```

### 4. Deploy Firestore/Storage Rules (bắt buộc)

Rules quyết định toàn bộ phân quyền server-side (roles, ai đọc/ghi được gì) — **nếu không deploy, một số tính năng sẽ bị `permission-denied`** dù code app không lỗi gì.

```bash
firebase login
firebase use datvexemphimgroup5    # hoặc project ID Firebase thật của bạn
firebase deploy --only firestore:rules,firestore:indexes,storage
```

### 5. Seed dữ liệu rạp (tuỳ chọn, nếu Firestore đang trống)

`tool/seed_theaters.dart` chứa danh sách rạp mẫu (tên/toạ độ) — đây là **dữ liệu tham khảo để copy tay** vào Firebase Console → Firestore → collection `theaters`, không phải script tự chạy được. Tên rạp phải khớp chính xác với những gì hiển thị ở màn chọn suất chiếu, vì tên này được lưu thẳng vào `tickets.theaterName`.

### 6. Thiết lập tài khoản Admin đầu tiên

1. Đăng ký tài khoản `user` bình thường trên app.
2. Firebase Console → Firestore Database → collection `users` → tìm document vừa tạo (id = uid).
3. Sửa field `role` từ `"user"` thành `"admin"`.
4. Đăng xuất/đăng nhập lại (hoặc khởi động lại app) để thấy Admin Dashboard.

Từ tài khoản Admin, bạn có thể cấp các vai trò còn lại (`staff`, `theater_manager`, `accountant`, `marketing`) qua màn **Quản lý Người dùng**.

---

## 🛡️ Luồng bảo mật mã QR

1. Khi vé được tạo/thanh toán xong, backend Node.js ký một chữ ký (HMAC-SHA256) gồm `ticketId` + `orderCode` + trạng thái vé.
2. QR Code trên app chứa `{ticketId, signature}` (không phải dữ liệu vé thô).
3. Staff quét QR → app gửi `signature` lên `/verify-checkin` → server xác thực chữ ký bằng `crypto.timingSafeEqual`, kiểm tra đúng rạp + khung giờ hợp lệ (-30 đến +180 phút quanh giờ chiếu) trước khi đánh dấu Đã Check-in. Toàn bộ lượt check-in (kể cả thủ công) được ghi vào `checkin_audit_log`.

---

## 🆕 Các nâng cấp/cải thiện gần đây

### Bảo mật & tiền bạc (server-authoritative, không tin client)
- **Điểm loyalty tính đúng**: dùng điểm giảm giá giờ thật sự trừ vào số tiền phải trả (trước đây server bỏ qua, khách mất điểm mà không được giảm); thanh toán qua PayOS/ngân hàng giờ cũng cộng/trừ điểm thật ở webhook (trước đây chỉ luồng ví mới xử lý điểm).
- **Nạp ví (`/topup-wallet`) và huỷ vé PENDING dở dang (`/discard-pending-ticket`)** chuyển hẳn qua backend (Admin SDK) — trước đây client tự ghi thẳng Firestore, bị `firestore.rules` chặn đứng khi rules được deploy đúng.
- **Giá combo lấy từ Firestore thật** (theo từng rạp) thay vì bảng giá cứng trong `server.js` đã lệch khỏi hệ thống combo mới — trước đây MỌI đơn có combo đều bị từ chối do thiếu `id` khớp bảng cũ.
- **Voucher không cộng dồn với giảm giá tự động** (hạng thành viên + Happy Wednesday) — hệ thống áp dụng mức có lợi hơn, không cộng cả hai; áp dụng cả ở client hiển thị lẫn server tính tiền.
- **Bộ đếm lượt dùng voucher (`currentUses`) tăng trong transaction ở server**, không còn tăng rời rạc từ client (tránh vượt `maxUses` khi nhiều người dùng cùng lúc).
- **Ảnh CCCD xác minh tuổi**: chuyển từ Cloudinary "unsigned upload" (ai cũng upload được, không cần đăng nhập) sang **signed upload** — backend cấp chữ ký (`/cloudinary-sign`) chỉ khi có Firebase ID token hợp lệ.

### Phân quyền & Firestore Rules
- Thêm vai trò `accountant`, `marketing` với quyền tương ứng (đọc `tickets`, ghi `vouchers`/`promotions`).
- `shifts`: nhân viên chỉ đọc được ca của chính mình (trước đây đọc được lịch ca của mọi rạp).
- `showtime_seat_status`: giới hạn ghi chỉ field `bookedSeatIds` kiểu list, chặn chèn dữ liệu tuỳ ý.
- `movie_reviews`: bắt buộc kèm `ticketId` trỏ tới đúng 1 vé COMPLETED của người gửi, đúng phim — chặn spam review ảo.

### Vé, phòng chiếu, suất chiếu
- Vé giờ lưu đúng **tên phòng chiếu** và **thời lượng phim thật** (trước đây thiếu tên phòng, và màn hình vé hardcode "120 phút" cho mọi phim).
- Chống trùng giờ suất chiếu trong cùng phòng tính theo **thời lượng phim thật** (tra từ `movies`), không còn giả định cố định 150 phút.
- Sửa lỗi hiển thị vé: nhãn "Phòng chiếu" trước đây hiển thị nhầm danh sách ghế.
- Dọn tự động **khóa ghế tạm thời** đã hết hạn (trước đây tồn tại vĩnh viễn trong Firestore dù không còn tác dụng).
- Sửa vài chuỗi tiếng Việt bị lỗi encoding (mojibake) ở màn hình ca làm việc của nhân viên.

Chi tiết lịch sử audit/kế hoạch trước đợt này (Firestore Rules ban đầu, ký QR, chuẩn hoá schema vé, soft-delete phim...) xem [`AUDIT_AND_ROADMAP.md`](AUDIT_AND_ROADMAP.md).

### Còn tồn đọng (chưa xử lý, để dành đợt sau)
- Chưa có Cloud Function/cron dọn `temporary_locks` phía server (hiện chỉ dọn khi client đang mở màn chọn ghế đúng suất đó).
- Chưa xác thực email khi đăng ký.
- Firebase API Key / Google Maps API Key vẫn đang hardcode trong source (`lib/main.dart`, `AndroidManifest.xml`) — chấp nhận được vì được Firestore/Storage Rules bảo vệ ở tầng dữ liệu, nhưng nên cân nhắc xoay vòng nếu public repo.

---

**Nhóm Phát Triển - Group 5**
Chúc bạn có những trải nghiệm tuyệt vời với Stella Cinema! 🍿🎬
