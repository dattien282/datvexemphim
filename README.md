# 🎬 Đặt Vé Xem Phim - Comprehensive System Documentation

Dự án **Đặt Vé Xem Phim** là một ứng dụng di động cấp doanh nghiệp (Enterprise-level) dành cho hệ thống chuỗi rạp chiếu phim. Ứng dụng được thiết kế tỉ mỉ từ giao diện người dùng (UI/UX) đến cấu trúc dữ liệu Backend, đảm bảo đáp ứng hàng ngàn giao dịch đồng thời mà không xảy ra tình trạng kẹt vé, trùng vé.

Tài liệu này đóng vai trò là Sách Trắng (Whitepaper) kiêm Hướng dẫn Dành cho Lập trình viên (Developer Guide) đi sâu vào từng ngóc ngách của dự án.

---

## 📑 Mục Lục Chi Tiết
1. [Kiến Trúc Tổng Thể (System Architecture)](#1-kiến-trúc-tổng-thể-system-architecture)
2. [Quản Lý Trạng Thái (State Management)](#2-quản-lý-trạng-thái-state-management)
3. [Luồng Nghiệp Vụ Chi Tiết Theo Role (Deep-Dive Workflows)](#3-luồng-nghiệp-vụ-chi-tiết-theo-role-deep-dive-workflows)
   - [3.1. Khách Hàng (User)](#31-khách-hàng-user)
   - [3.2. Nhân Viên (Staff)](#32-nhân-viên-staff)
   - [3.3. Quản Lý Rạp (Theater Manager)](#33-quản-lý-rạp-theater-manager)
   - [3.4. Quản Trị Viên Hệ Thống (Super Admin)](#34-quản-trị-viên-hệ-thống-super-admin)
4. [Các Giải Pháp Kỹ Thuật Cốt Lõi (Core Technical Solutions)](#4-các-giải-pháp-kỹ-thuật-cốt-lõi-core-technical-solutions)
   - [A. Real-time Seat Locking (Chống trùng lặp ghế)](#a-real-time-seat-locking-chống-trùng-lặp-ghế)
   - [B. Membership & Dynamic Discount (Tính giá động)](#b-membership--dynamic-discount-tính-giá-động)
   - [C. Ticket Lifecycle & QR Validation (Vòng đời vé)](#c-ticket-lifecycle--qr-validation-vòng-đời-vé)
5. [Cấu Trúc Database Trực Quan (Entity Relationship)](#5-cấu-trúc-database-trực-quan-entity-relationship)
6. [Tích Hợp Dịch Vụ Bên Thứ 3 (Third-Party Integrations)](#6-tích-hợp-dịch-vụ-bên-thứ-3-third-party-integrations)
7. [Hướng Dẫn Build & Triển Khai (Deployment Guide)](#7-hướng-dẫn-build--triển-khai-deployment-guide)

---

## 1. Kiến Trúc Tổng Thể (System Architecture)

Dự án áp dụng kiến trúc **Feature-First** (Nhóm theo Tính năng) kết hợp mô hình **MVVM (Model - View - ViewModel)** nhằm tối ưu hóa việc mở rộng:
- **Model (`lib/data/models/`)**: Chứa các class biểu diễn dữ liệu (VD: `UserModel`, `MovieModel`). Bao gồm các hàm `fromJson` và `toJson` để giao tiếp với NoSQL Firebase.
- **View (`lib/features/.../screens/`)**: Chứa các Widget UI thuần túy của Flutter. Tuyệt đối không chứa logic gọi database trực tiếp.
- **ViewModel/Service (`lib/features/.../services/` & `viewmodels/`)**: Xử lý Business Logic, tính toán giá, khóa ghế, CRUD (Tạo, Đọc, Sửa, Xóa) trên Firestore.

**Đặc điểm nổi bật:** Khả năng tách rời giao diện và logic giúp việc thay thế Database (từ Firebase sang một API Node.js tự build trong tương lai) chỉ cần sửa duy nhất tầng Service mà không ảnh hưởng một dòng code UI nào.

---

## 2. Quản Lý Trạng Thái (State Management)

Dự án sử dụng **`flutter_riverpod`** và **`Provider`** kết hợp với **`StreamBuilder`** cho việc quản lý trạng thái:
- **StreamBuilder:** Được sử dụng triệt để trong các màn hình Đặt ghế (Seat Booking), giúp UI cập nhật ngay lập tức (real-time) nếu một người dùng khác vừa bấm chọn chiếc ghế đó.
- **StateNotifier / Providers:** Lưu trữ phiên đăng nhập (`Auth State`). Toàn bộ app sẽ tự động văng ra màn hình đăng nhập nếu `GoogleSignIn` hoặc `FirebaseAuth` phát tín hiệu Log Out, không cần viết code điều hướng thủ công ở từng trang.

---

## 3. Luồng Nghiệp Vụ Chi Tiết Theo Role (Deep-Dive Workflows)

Hệ thống điều hướng tự động dựa trên biến `role` trong Firestore (`users/{uid}`).

### 3.1. Khách Hàng (User)
*Tập trung vào trải nghiệm mượt mà, tiện lợi.*
- **Onboarding & Auth:** Đăng nhập một chạm với Google hoặc Email. Trạng thái được cache offline để không phải đăng nhập lại lần sau.
- **Khám phá phim:**
  - Lấy dữ liệu phim (Đang chiếu / Sắp chiếu) từ `movies` collection.
  - Phim có liên kết `youtube_player_flutter` để bật Popup xem Trailer trực tiếp không cần rời khỏi app.
- **Luồng thanh toán (Payment Workflow):**
  1. Chọn Rạp, chọn Ngày giờ (hiển thị lọc suất chiếu từ `showtimes`).
  2. Bấm chọn ghế. Thuật toán sẽ chặn nếu ghế đang nằm trong bảng `temporary_locks`.
  3. Màn hình thanh toán: Tự động cộng/trừ tiền dựa theo 3 yếu tố: Giá gốc suất chiếu + Chiết khấu Hội viên (Bronze/Silver/Gold/Diamond) + Mã Voucher giảm giá.
  4. Thanh toán xong -> Bắn thông báo Push Notification -> Lưu vé vào `tickets` collection kèm theo 1 chuỗi chuỗi mã QR Hash hóa -> Mở popup gợi ý "Thêm vào Google Calendar" (`add_2_calendar`).

### 3.2. Nhân Viên (Staff)
*Tập trung vào thao tác nhanh, hỗ trợ trực tiếp tại quầy.*
- **Soát vé (Check-in Validation):**
  - Sử dụng Camera để quét mã QR (`mobile_scanner`).
  - Hệ thống kiểm tra: Vé đã dùng chưa? Vé có hợp lệ trong ngày hôm nay không? Sai rạp không?
  - Nếu hợp lệ: Update `status` của vé thành `used`, không cho phép quét lại lần 2.
- **Bán vé tại quầy (Walk-in Sale):**
  - Giao diện dành riêng cho nhân viên thao tác nhanh, bỏ qua bước thanh toán online.
  - Nhân viên tự chọn phim, chọn ghế, nhận tiền mặt từ khách.
  - In hóa đơn ra máy in nhiệt (thông qua package `printing` kết nối Bluetooth/Wifi) đưa cho khách.
- **Bảo trì ghế (Maintenance):** Nhân viên đánh dấu ghế hỏng (vd: ghế rách nệm, hỏng lò xo), hệ thống cập nhật màu xám, cấm User bình thường đặt vào ghế này.

### 3.3. Quản Lý Rạp (Theater Manager)
*Phân mảnh dữ liệu - Data Isolation.*
- Khi Admin tạo tài khoản Theater Manager, bắt buộc phải gán `theaterId` cho người này.
- **Quản lý phòng chiếu (Rooms):** Setup phòng có bao nhiêu hàng, cột, loại ghế (Thường, VIP, Couple).
- **Quản lý suất chiếu (Showtimes):** Kéo thả lịch chiếu vào các phòng. Hệ thống tự kiểm tra thời lượng phim (`duration`) cộng thêm thời gian dọn rạp (ví dụ 15 phút) để cảnh báo nếu 2 suất chiếu bị đè lên nhau (Overlap Validation).

### 3.4. Quản Trị Viên Hệ Thống (Super Admin)
*Kiểm soát vĩ mô toàn chuỗi rạp.*
- Nắm quyền sinh sát (CRUD) trên các bảng `theaters` (Thêm cụm rạp mới), `movies` (Cập nhật phim hot).
- Phân quyền: Cấp quyền Staff hoặc Theater Manager cho bất kỳ tài khoản User nào.
- **Thống kê Doanh Thu Nâng Cao:**
  - Query toàn bộ `tickets` collection, tính tổng doanh thu (`totalAmount`).
  - Lọc theo khoảng thời gian (Từ ngày - Đến ngày), lọc theo từng Cụm Rạp, từng Phim.
  - **Xuất Báo Cáo:** Sử dụng `pdf` và `excel` để tạo file Báo cáo tài chính, lưu vào thiết bị và có thể Chia sẻ (`share_plus`) thẳng qua Zalo, Email, Slack.

---

## 4. Các Giải Pháp Kỹ Thuật Cốt Lõi (Core Technical Solutions)

### A. Real-time Seat Locking (Chống trùng lặp ghế)
Bài toán: User A và User B cùng chọn ghế E4 lúc 20:00:00.
**Giải pháp:**
- Áp dụng **Distributed Lock** thủ công thông qua Firestore.
- Khi bấm chọn ghế, một record được ghi vào `temporary_locks/{showtimeId_seatId}` kèm theo tham số `lockedAt` và `userId`.
- Nếu ghi thành công, UI hiển thị ghế màu Vàng. Trạng thái này được Sync Real-time qua `StreamBuilder` tới máy của User B, khiến User B không bấm vào được nữa.
- Firebase Cloud Functions (hoặc một cronjob trên client) sẽ tự dọn dẹp các Lock quá 5 phút (Hết hạn giữ ghế).

### B. Membership & Dynamic Discount (Tính giá động)
Mọi hóa đơn thanh toán đều đi qua lớp tính toán trung tâm `PaymentService`:
1. `Base Price`: Lấy từ `showtime.price`.
2. Kiểm tra `Happy Wednesday` (Thứ 4 vui vẻ): Nếu `DateTime.now().weekday == 3`, giá vé set đồng giá (Vd: 50.000đ).
3. Kiểm tra `Membership`: Tính dựa trên `user.totalSpent`.
   - `> 10.000.000` đ (Diamond) -> Giảm 15%
   - `> 5.000.000` đ (Gold) -> Giảm 10%...
4. Cập nhật lại `totalSpent` sau khi thanh toán thành công để tự động thăng hạng.

### C. Ticket Lifecycle & QR Validation (Vòng đời vé)
Vé có 3 trạng thái (State Machine):
- `active`: Đã thanh toán, sẵn sàng sử dụng.
- `used`: Đã bị quét bởi Staff. (Vĩnh viễn không dùng lại được).
- `cancelled`: Bị hủy (do yêu cầu hoặc sự cố).
QR Code sinh ra từ chuỗi mã hóa bao gồm `TicketID + Mã bảo mật`. Dù khách hàng có tự scan bằng Zalo/Camera ngoài cũng chỉ ra chuỗi vô nghĩa, bắt buộc phải dùng App của Staff có logic giải mã mới check-in được.

---

## 5. Cấu Trúc Database Trực Quan (Entity Relationship)

Firestore (NoSQL) được cấu trúc dẹp (Flatten) để giảm thiểu độ trễ query:

- `users (uid)`: `{ email, name, role, totalSpent, avatarUrl, fcmToken, createdAt }`
- `movies (id)`: `{ title, genre, duration, synopsis, posterUrl, trailerUrl, releaseDate, isShowing }`
- `theaters (id)`: `{ name, address, latitude, longitude }`
- `rooms (id)`: `{ theaterId, name, rowCount, columnCount, maintenanceSeats (array) }`
- `showtimes (id)`: `{ movieId, theaterId, roomId, startTime, basePrice }`
- `tickets (id)`: `{ userId, showtimeId, seats (array), totalAmount, status (active/used/cancelled), bookedAt, qrCodeHash }`
- `vouchers (id)`: `{ code, discountPercent, maxDiscount, minSpend, expiryDate, usageCount, maxUsage }`
- `notifications (id)`: `{ userId, title, body, isRead, timestamp }`

**Bảo mật Database (`firestore.rules`):**
- Chỉ Admin mới được Write (Ghi) vào `movies`, `theaters`.
- Manager chỉ được Write vào `rooms` và `showtimes` thuộc rạp của mình.
- User chỉ được Read dữ liệu của chính mình, Write (Tạo) vé mới thông qua cơ chế khóa bảo mật. Tuyệt đối không cho User tự update `totalSpent` hay sửa giá vé ở máy khách (Tránh Hacker dùng cheat engine).

---

## 6. Tích Hợp Dịch Vụ Bên Thứ 3 (Third-Party Integrations)

- **Firebase Cloud Messaging (FCM):** Đăng ký device token khi User tải app. Kịch bản gửi: Nhắc nhở xem phim trước 2 tiếng, gửi thông báo khi có Voucher mới tung ra.
- **Google Maps API:** Vẽ Marker cụm rạp, kết hợp Geolocator tính khoảng cách từ tọa độ hiện tại của User để gợi ý "Rạp gần bạn nhất".
- **Google Sign-In:** Đăng nhập 1 chạm, tự động liên kết với hệ thống cấp phát Avatar.

---

## 7. Hướng Dẫn Build & Triển Khai (Deployment Guide)

### 7.1. Chạy trên máy ảo (Emulator/Simulator)
```bash
flutter clean
flutter pub get
flutter run -d emulator-5554 # Hoặc ID thiết bị của bạn
```

### 7.2. Build phiên bản phát hành (Production Build)

**Dành cho Android (Tạo file APK hoặc App Bundle upload CH Play):**
```bash
# Build APK cho mục đích Test nội bộ
flutter build apk --release

# Build App Bundle để đưa lên Google Play Store
flutter build appbundle --release
```

**Dành cho iOS (Cần máy Mac & Xcode):**
```bash
flutter build ios --release
# Mở thư mục ios/ bằng Xcode, thiết lập Signing Certificate, và Archive để đẩy lên TestFlight/App Store.
```

### 7.3. Cấu hình khóa bảo mật & Maps API
- Do sử dụng Google Maps, bạn cần lấy **Google Maps API Key** từ Google Cloud Console.
- Chèn key này vào file `android/app/src/main/AndroidManifest.xml` và `ios/Runner/AppDelegate.swift` theo chuẩn thư viện `google_maps_flutter`.
- Cấu hình SHA-1 và SHA-256 trên Firebase Console để Google Sign-in hoạt động ở chế độ Release.

---
*Developed with ❤️ using Flutter & Firebase by Group 5.*