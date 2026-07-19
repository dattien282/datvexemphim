# Stella Cinema (dat_ve_xem_phim_group5)

Dự án ứng dụng đặt vé xem phim toàn diện được phát triển bằng **Flutter** và **Firebase**, cùng với một backend Node.js/Express (`backend-payos/`) phụ trách mọi thao tác liên quan tới tiền, vé, và bí mật (thanh toán PayOS, ví nội bộ, ký QR, gửi email/push, chatbot AI...). Ứng dụng phục vụ đầy đủ quy trình khép kín cho 6 vai trò: Khách hàng (User), Nhân viên rạp (Staff), Quản lý cụm rạp (Theater Manager), Kế toán (Accountant), Marketing, và Quản trị viên (Admin).

> 📌 Repo: https://github.com/dattien282/datvexemphim
> 📄 Lịch sử audit kỹ thuật đầy đủ (từng đợt rà soát, bug đã tìm/đã sửa, quyết định thiết kế): xem [`AUDIT_AND_ROADMAP.md`](AUDIT_AND_ROADMAP.md). File này (README) tập trung vào **cách chạy dự án và bản đồ tính năng hiện tại**; lịch sử "trước đây bị gì, sửa ra sao" nằm ở file kia.

---

## 📚 Mục lục

1. [Tính năng & Quy trình theo từng vai trò](#-tính-năng--quy-trình-theo-từng-vai-trò)
2. [Kiến trúc hệ thống](#️-kiến-trúc-hệ-thống)
3. [Cấu trúc thư mục](#-cấu-trúc-thư-mục)
4. [Mô hình dữ liệu Firestore](#-mô-hình-dữ-liệu-firestore)
5. [Hướng dẫn cài đặt & chạy dự án](#-hướng-dẫn-cài-đặt--chạy-dự-án-dành-cho-máy-mới-clone-repo)
6. [Luồng bảo mật mã QR](#️-luồng-bảo-mật-mã-qr)
7. [Luồng OTP đăng nhập 2 lớp](#-luồng-otp-đăng-nhập-2-lớp)
8. [Cron job & tác vụ nền](#-cron-job--tác-vụ-nền-backend)
9. [Những điều cần biết trước khi phát triển tiếp](#-những-điều-cần-biết-trước-khi-phát-triển-tiếp)

---

## 🌟 Tính năng & Quy trình theo từng vai trò

Hệ thống phân quyền Role-Based Access Control (RBAC) với 6 vai trò lưu ở field `role` trong `users/{uid}`: `user`, `staff`, `theater_manager`, `admin`, `accountant`, `marketing`. Điều hướng sau đăng nhập nằm ở `_navigateByRole` (`lib/features/auth/screens/login_screen.dart`), dựa trên các getter `hasStaffAccess`/`hasManagerAccess`/`hasAdminAccess`/`hasBackofficeAccess` (`lib/models/user_profile.dart`).

### 1. Khách hàng (User)
- **Đăng nhập/Đăng ký**: Email/Password (có xác thực email bắt buộc trước khi vào app) hoặc Google Sign-In (bỏ qua bước xác thực email vì đã qua OAuth của Google).
- **Xác thực 2 lớp (OTP qua email)**: sau khi đăng nhập email/password thành công, khách hàng phải nhập mã 6 số gửi qua email trước khi vào app (không áp dụng cho Google Sign-In và các tài khoản do admin cấp — staff/manager/admin/accountant/marketing). Xem chi tiết ở [mục riêng bên dưới](#-luồng-otp-đăng-nhập-2-lớp).
- **Trang chủ & Khám phá phim**: danh sách phim Đang chiếu/Sắp chiếu, banner khuyến mãi, popup ưu đãi.
- **Trợ lý AI (Chatbot)**: hỏi đáp về phim/giá vé/rạp qua Gemini (yêu cầu đăng nhập — xem [Cron job & tác vụ nền](#-cron-job--tác-vụ-nền-backend)); nếu chưa đăng nhập hoặc chưa cấu hình `GEMINI_API_KEY`, tự động rơi về chế độ trả lời offline (bảng dữ liệu tĩnh dựng sẵn trong app).
- **Quy trình Đặt vé**:
  1. Chọn phim, xem chi tiết/trailer, đánh giá phim (yêu cầu đã có vé COMPLETED cho đúng phim đó — chặn spam review ảo).
  2. Chọn rạp, ngày, giờ chiếu — mỗi suất chiếu có **loại suất chiếu** (`sessionType`: Morning/Late Morning/Afternoon/Prime Time/Evening/Midnight/Sneak Show/First Day, hoặc gán tay Marathon/Fan Screening/Special Event) ảnh hưởng phụ thu/giảm giá. Xác thực độ tuổi tự động nếu phim T18 (bắt buộc xác minh CCCD qua ảnh chụp, upload ký số qua Cloudinary — không public).
  3. Chọn ghế trên sơ đồ phòng — **13 định dạng phòng chiếu** cấu hình được (Standard/Couple/VIP/VIP - Laurus/VIP - Lagom/Gold Class/Premium/Dolby Atmos/Onyx LED/IMAX/ScreenX/4DX/Starium), mỗi phòng có thể hỗ trợ nhiều tổ hợp trình chiếu/âm thanh (VD 1 phòng IMAX vừa chiếu IMAX 2D vừa IMAX 3D). Ghế xe lăn và ghế hỏng được đánh dấu riêng, chặn đặt ở cả app lẫn quầy. Hỗ trợ khoá ghế tạm thời (giữ chỗ atomic qua transaction, tự nhả khi hết hạn/huỷ giữa chừng).
  4. Chọn Combo Bắp Nước (giá theo từng rạp, xác thực lại ở server trước khi trừ tiền).
  5. **Thanh toán**:
     - Áp dụng Voucher hoặc ưu đãi tự động (hạng thành viên theo tổng chi tiêu/Happy Wednesday) — hệ thống áp dụng mức có lợi hơn, không cộng dồn cả hai; điểm loyalty (đổi vé lấy voucher, dùng điểm giảm giá khi thanh toán) tính riêng, luôn cộng thêm được.
     - Thanh toán qua **PayOS** (chuyển khoản/QR ngân hàng, xác thực webhook) hoặc **Stella Wallet** (ví nội bộ — nạp/trừ đều qua backend bằng Admin SDK, app không ghi trực tiếp Firestore).
     - Giá hiển thị và giá trừ tiền thật đều đọc cùng 1 nguồn: `pricing_rules` (nếu admin đã cấu hình) hoặc bảng phụ thu theo `sessionType`/giờ/cuối tuần mặc định — hai bên (Flutter + backend) luôn khớp nhau.
- **Quản lý Vé (Kho Vé)**: xem vé đã đặt (đúng tên phòng chiếu, thời lượng phim thật), mã QR ký số chống giả mạo, huỷ vé/hoàn tiền có kiểm soát thời gian (≥30 phút trước giờ chiếu với vé đã thanh toán), tự huỷ vé PENDING treo khi thoát ngang giữa chừng thanh toán.
- **Loyalty System**: tích điểm khi mua vé (1 điểm = 100đ), đổi điểm giảm giá khi thanh toán, hoặc đổi điểm lấy voucher trong màn **Membership**.
- **Thông báo**: nhận thông báo đặt vé thành công, sắp đến giờ chiếu, huỷ vé/hoàn tiền, broadcast từ admin/marketing, và push quảng cáo định kỳ tự động (voucher/phim hot/combo/suất chiếu ưu đãi xoay vòng theo dữ liệu thật).

### 2. Nhân viên rạp (Staff)

Dashboard (`staff_dashboard_screen.dart`) có 3 tab (VÉ HÔM NAY / CA LÀM / THỐNG KÊ) + 4 icon hành động trên AppBar (Bán vé tại quầy, Ghế hỏng/bảo trì, Báo cáo sự cố, Quét mã QR). Mọi truy vấn đều tự lọc theo `assignedTheater` của tài khoản — staff không thấy được dữ liệu rạp khác.

- **Tab "VÉ HÔM NAY"**: danh sách vé của rạp mình theo `showDate` = hôm nay, lọc theo trạng thái (chip "Đã thanh toán" / "Đã check-in"). Mỗi vé chưa check-in có nút **CHECK-IN THỦ CÔNG** (dùng khi khách không mở được QR/máy quét lỗi) — gọi `/manual-checkin`, ghi log riêng vào `checkin_audit_log` với lý do `manual_override` để admin đối soát sau này, khác hẳn với quét QR thường.
- **Soát vé bằng Quét mã QR**: mở camera quét, nhận diện 2 loại QR khác nhau qua nội dung JSON giải mã được:
  - QR vé xem phim (`{ticketId}` hoặc chuỗi thô) → gọi `/verify-checkin`, server xác thực chữ ký HMAC bằng `crypto.timingSafeEqual`, kiểm tra đúng rạp + trong khung giờ hợp lệ (-30 đến +180 phút quanh giờ chiếu), rồi mới đổi trạng thái vé thành `CHECKED_IN`.
  - QR điểm danh ca làm (`{type: 'attendance', theater, date}`, do quản lý rạp tạo ra ở màn **Điểm danh ca làm**) → xác nhận staff có được phân ca hôm đó tại đúng rạp (query `shifts`), rồi tự động ghi **vào ca** (nếu chưa có log hôm nay) hoặc **ra ca** (nếu đã check-in, chưa check-out) vào `attendance_logs`.
  - Vé đã check-in/hết hạn/sai rạp đều bị từ chối với thông báo rõ lý do trên màn hình quét.
- **Chế độ Ngoại tuyến (Offline Mode)**: bật công tắc "CHẾ ĐỘ NGOẠI TUYẾN" trên dashboard khi mất mạng tại rạp — trước đó cần bấm "ĐỒNG BỘ VÉ HÔM NAY" (khi còn mạng) để cache toàn bộ vé của rạp vào máy. Khi offline, quét QR sẽ đối chiếu với cache local thay vì gọi server; các lượt check-in ngoại tuyến được xếp hàng chờ, tự động đồng bộ ngược lên `tickets`/Firestore khi tắt chế độ này (bật lại mạng).
- **Bán vé tại quầy** (`StaffWalkInSaleScreen`): chọn suất chiếu đang active của rạp mình → chọn ghế trên sơ đồ thật (ghế đã bán/hỏng bị khoá) → nhập tên/SĐT khách (không bắt buộc) → bấm **BÁN VÉ**. App gọi `/walkin-sale` với `preview: true` trước để lấy giá thu tiền mặt CHÍNH XÁC từ server (cùng công thức `computeAuthoritativeAmount` với khách tự đặt online — không còn công thức riêng chỉ cộng đơn giá ghế như trước), hiện dialog xác nhận "Đã thu đủ tiền mặt?", rồi mới gọi lại với `preview: false` để thực sự tạo vé (COMPLETED ngay, ký QR như vé mua online).
- **Ghế hỏng / xe lăn** (`StaffSeatMaintenanceScreen`): chọn phòng chiếu của rạp mình → 2 nút chuyển chế độ **GHẾ HỎNG** / **GHẾ XE LĂN** → chạm vào ghế trên sơ đồ để bật/tắt đánh dấu (ghi trực tiếp `arrayUnion`/`arrayRemove` vào cả document `rooms` và bản `seat_map_versions` hiện hành của phòng).
- **Báo cáo Sự cố**: chọn loại (Hết bắp nước/Hỏng ghế/Vệ sinh/Khách hàng/Khác) + mô tả chi tiết → ghi vào `incidents` kèm email người báo cáo, quản lý rạp xem và đánh dấu xử lý ở màn riêng của họ.
- **Tab "CA LÀM"**: danh sách ca mình đã được quản lý rạp phân công (từ `shifts`, lọc theo `staffIds` chứa uid của mình).
- **Tab "THỐNG KÊ"**: số vé đã soát hôm nay + doanh thu check-in hôm nay (lọc đúng theo `checkedInAt` trong ngày, không cộng dồn toàn bộ lịch sử).

### 3. Quản lý cụm rạp (Theater Manager)

Dashboard (`theater_manager_dashboard_screen.dart`) có 4 tab (SUẤT CHIẾU / VÉ-DOANH THU / NHÂN VIÊN / VOUCHER) + icon hành động mở các màn quản lý riêng, tất cả tự khoanh vùng theo `assignedTheater`.

- **Tạo/sửa suất chiếu**: chọn phim (tự tra thời lượng thật từ `movies` để tính toán, không còn hardcode), phòng, ngày/giờ, ngôn ngữ, giá vé Thường/VIP, và tuỳ chọn nâng cao (số phút quảng cáo trước phim/thời gian khách ra về/thời gian dọn phòng — mặc định 0/10/0 phút). **Thanh timeline trực quan** hiện các suất chiếu đã có trong ngày của phòng đó (khối màu đỏ) và suất đang tạo (khối xanh lá nếu không trùng, khối vàng nếu trùng) để quản lý thấy ngay xung đột trước khi lưu. Loại suất chiếu (`sessionType`) tự động suy ra từ giờ chiếu + ngày công chiếu phim (Sneak Show nếu chiếu trước ngày công chiếu, First Day nếu đúng ngày, còn lại theo khung giờ Morning/Late Morning/Afternoon/Prime Time/Evening/Midnight), hoặc quản lý có thể tự chọn tay 3 loại đặc biệt (Marathon/Fan Screening/Special Event). Có tuỳ chọn "lặp lại N ngày" để tạo hàng loạt, ngày nào trùng giờ thì tự bỏ qua ngày đó (không chặn cả loạt).
- **Quản lý phòng chiếu** (`RoomManagementScreen`): tạo/sửa phòng — nhập số hàng Thường/VIP/Sweetbox, chọn định dạng phòng (dropdown đọc từ 13 định dạng mặc định + định dạng admin tự thêm), chọn tổ hợp trình chiếu/âm thanh phòng hỗ trợ (VD 1 phòng vừa gắn nhãn "IMAX 2D" vừa "IMAX 3D" — khi tạo suất chiếu cho phòng này, nếu có >1 tổ hợp thì được hỏi chọn đúng combo cho suất đó). Menu 3 chấm mỗi phòng: **Chỉnh sửa**, **Bảo trì ghế** (dialog chọn GHẾ HỎNG/GHẾ XE LĂN rồi chạm ghế để đánh dấu — y hệt cơ chế bên staff), **Bảo trì cả phòng** (chuyển trạng thái ACTIVE ↔ MAINTENANCE, phòng đang bảo trì không tạo được suất chiếu mới), **Xóa** (bị chặn nếu phòng còn suất chiếu `active` chưa diễn ra — phải huỷ/chuyển phòng cho các suất đó trước). Mỗi lần sửa cấu trúc phòng, hệ thống tự tạo 1 bản `seat_map_versions` mới; suất chiếu đã chốt sơ đồ trước đó (qua `seatMapVersionId`) không bị ảnh hưởng.
- **Sơ đồ nhiệt ghế (Seat Heatmap)**: chọn 1 phòng → gom trạng thái ghế từ tối đa 30 suất chiếu gần nhất của phòng đó, tô màu từng ghế theo tần suất được đặt (xanh dương nhạt = ít khách chọn, đỏ đậm = luôn kín) kèm chỉ ra hàng bán chạy nhất — hỗ trợ quyết định vận hành (hàng nào ế nên đổi giá/loại ghế).
- **Điểm danh ca làm** (`TheaterAttendanceScreen`): tab "MÃ ĐIỂM DANH" hiện 1 mã QR (chứa rạp + ngày hôm nay) để nhân viên tự quét bằng chính app của họ (qua màn Quét mã QR bên Staff) nhằm chấm công vào ca/ra ca; tab "LỊCH SỬ HÔM NAY" liệt kê ai đã vào/ra ca kèm giờ chính xác.
- **Smart Roster (Phân công ca làm)**: chọn ngày (mũi tên trái/phải), 3 thẻ ca Sáng (08:00-15:00)/Chiều (15:00-22:00)/Tối (22:00-02:00) — bấm icon bút ở mỗi thẻ để mở danh sách toàn bộ staff của rạp (checkbox chọn nhiều người) rồi lưu vào `shifts`.
- **Báo cáo Sự cố**: danh sách sự cố nhân viên gửi lên (loại, mô tả, người báo cáo, thời gian), nút **Đánh dấu đã xử lý** cho các sự cố đang "Chờ xử lý".
- **Tab VÉ/DOANH THU**: doanh thu theo thời gian thực của rạp. **Tab VOUCHER**: voucher giới hạn theo rạp mình (`theaterScope`).

### 4. Kế toán (Accountant)
- Đăng nhập vào đúng `AdminDashboardScreen` (dùng chung class với Admin) nhưng menu tự lọc chỉ còn đúng 1 mục: **Báo cáo Doanh thu** (xem mô tả chi tiết ở mục Admin bên dưới — Kế toán dùng y hệt màn đó, chỉ khác là không thấy các mục quản trị khác).

### 5. Marketing
- Đăng nhập vào `AdminDashboardScreen`, menu tự lọc còn 2 mục: **Voucher & Khuyến mãi** và **Gửi thông báo chung** (xem mô tả chi tiết ở mục Admin bên dưới — cùng 2 màn hình y hệt Admin dùng).

### 6. Quản trị viên (Admin)

`AdminDashboardScreen` hiện lưới ô vuông các chức năng — Admin thấy đủ cả 10 mục, Accountant/Marketing chỉ thấy phần của mình (xem mục 4-5).

- **Quản lý Phim**: danh sách phim (poster, thể loại, rating, trạng thái Đang chiếu/Sắp chiếu) với nút Sửa/Xoá riêng từng phim. Bấm + để thêm phim mới — có ô **"Nhập mã TMDB"** + nút TẢI: nhập ID phim trên TMDB (vd `533535`), app gọi `/api/movies/import-tmdb` (kèm Firebase ID token) để tự động điền toàn bộ 11 trường (tên, thể loại, rating, poster, đạo diễn, diễn viên, thời lượng, ngày khởi chiếu, mô tả, quốc gia, trailer YouTube) — nếu server chưa cấu hình `TMDB_API_KEY`, trả về dữ liệu mẫu (mock) cố định theo ID để vẫn test được cả luồng nhập liệu. Xoá phim là soft-delete (`isDeleted: true`) — vé/đánh giá cũ của phim đó không bị ảnh hưởng, phim chỉ ẩn khỏi danh sách hiển thị.
- **Quản lý Người dùng**: ô tìm kiếm theo tên/email, mỗi user có menu **Phân quyền** → dialog chọn 1 trong 6 role (radio button, có icon+màu riêng từng role); nếu chọn `staff`/`theater_manager` thì hiện thêm dropdown **"Rạp phụ trách"** (bắt buộc chọn để giới hạn phạm vi dữ liệu người đó thấy được). Đổi role ghi cả `role` lẫn field `isAdmin` (legacy, giữ để tương thích ngược), và xoá `assignedTheater` nếu đổi về `user`/`admin`.
- **Định dạng phòng chiếu**: CRUD collection `room_formats` — mỗi định dạng gồm tên, mô tả ngắn, kiểu ghế (Ghế Thường+VIP / Toàn ghế đơn cỡ lớn / Toàn ghế đôi / Ghế Motion rung-4DX), preset số hàng Thường/VIP/Sweetbox + số ghế/hàng gợi ý khi tạo phòng mới, quy mô rạp được phép mở định dạng này (chip chọn nhiều: Small/Medium/Large), màu hiển thị (14 màu có sẵn), công tắc "Cao cấp" (giá cao hơn, không áp dụng ưu đãi Thứ 4) và công tắc "Đang cho chọn" (ẩn định dạng cũ mà không xoá — phòng đang dùng định dạng ẩn vẫn hoạt động bình thường). **Lần đầu dùng màn này cần vào "Cấu hình Server" bấm "SEED DANH MỤC ĐỊNH DẠNG PHÒNG"** để đưa 13 định dạng mặc định vào Firestore.
- **Luật giá vé (Pricing Rules)**: CRUD collection `pricing_rules` — mỗi luật có tên, **nhóm** (Cuối tuần / Khung giờ-Loại suất / Khác — luật cùng nhóm loại trừ nhau theo độ ưu tiên, khác nhóm cộng dồn), kiểu điều chỉnh (Cộng tiền cố định hoặc Phần trăm) + giá trị (số âm = giảm giá), độ ưu tiên, và các điều kiện khớp tuỳ chọn (bỏ trống = áp dụng mọi trường hợp): loại suất chiếu cụ thể, các ngày trong tuần (chip T2-CN), khung giờ (range slider giờ bắt đầu-kết thúc), tên rạp. *Ví dụ thực tế*: tạo 1 luật nhóm "Cuối tuần", khớp ngày Thứ 6/Thứ 7/Chủ Nhật, khung giờ 18h-24h, kiểu Phần trăm +15% → mọi suất chiếu tối cuối tuần tự động phụ thu 15% mà không cần sửa code/build lại app. Y hệt collection này được cả app (hiển thị giá) lẫn backend (trừ tiền thật) cùng đọc, nên luôn khớp nhau.
- **Voucher & Khuyến mãi**: tạo mã giảm giá (mã code, giảm theo % hoặc số tiền cố định, đơn tối thiểu, giới hạn số lượt dùng, ngày hết hạn, giới hạn theo 1 rạp cụ thể hoặc "ALL").
- **Kiểm duyệt Đánh giá**: danh sách toàn bộ đánh giá phim (tên phim, người gửi, rating, nội dung, số lượt thích, ngày gửi), nút **Xoá** cho từng đánh giá không phù hợp (xoá vĩnh viễn, có xác nhận).
- **Gửi thông báo chung (Broadcast)**: chọn **phân khúc mục tiêu** (Tất cả thành viên / Kim Cương ≥1000 điểm / Vàng ≥500 điểm / Bạc ≥200 điểm / Nhân viên rạp / Quản lý rạp) → nhập tiêu đề + nội dung → gửi. Ghi 1 document vào `notifications` cho **từng** người dùng thuộc phân khúc (batch theo lô 400) để họ thấy trong app, đồng thời gọi `/api/send-fcm` để đẩy push thật ra thiết bị.
- **Duyệt xác minh độ tuổi**: danh sách yêu cầu đang `pending` (email người gửi + ảnh mặt trước/sau CCCD tải từ Cloudinary) — nút **CHẤP NHẬN** (đánh dấu `ageVerified: true` trên tài khoản, cho phép đặt vé phim T18) hoặc **TỪ CHỐI**; cả 2 trường hợp đều gửi thông báo kết quả cho người dùng.
- **Nhật ký Hành động**: danh sách toàn bộ thao tác quản trị đã ghi log (đổi role, tạo/sửa/xoá phim, xoá đánh giá, gửi broadcast, CRUD định dạng phòng/luật giá...), lọc theo loại (Tạo mới/Cập nhật/Xóa/Thông báo/Khác), mỗi dòng có màu riêng theo loại hành động.
- **Cấu hình Server**: ô nhập/hiện **Gemini API Key** (lưu vào `configs/server_config`, backend đọc lại có cache 60 giây — đổi xong không cần restart server) + 4 nút vận hành dữ liệu: **Cập nhật DB** (quy mô rạp + seed suất chiếu mẫu), **Migrate Showtimes → showAt** (backfill Timestamp cho suất chiếu cũ), **Migrate Định dạng phòng → Stella** (đổi tên định dạng cũ sang hệ đặt tên riêng), **Seed danh mục định dạng phòng** (đưa 13 định dạng mặc định vào Firestore, tự bỏ qua nếu đã có dữ liệu).
- **Báo cáo Doanh thu**: lọc theo khoảng ngày (từ-đến) và rạp (hoặc "Tất cả rạp"), xuất báo cáo ra file **PDF** hoặc **Excel** để chia sẻ/lưu trữ ngoài app.

---

## ⚙️ Kiến trúc Hệ thống

- **Frontend**: Flutter (Android là nền tảng chính đang build/test; iOS/Windows/macOS/Linux có khung sườn nhưng chưa kiểm thử đầy đủ).
- **State Management**: Riverpod.
- **Cơ sở dữ liệu & Auth**:
  - **Firebase Authentication**, **Cloud Firestore** — xem danh sách collection đầy đủ ở [Mô hình dữ liệu Firestore](#-mô-hình-dữ-liệu-firestore).
  - **Firestore Security Rules** (`firestore.rules`) là tầng phân quyền server-side thật sự (không chỉ ẩn UI ở client) — **bắt buộc phải deploy**, xem [mục Cài đặt](#4-deploy-firestore-rules--indexes-bắt-buộc).
  - **Firebase Storage**: có cấu hình `storage.rules` (avatar) nhưng bucket Storage của project **chưa được khởi tạo trên Firebase Console** — thực tế toàn bộ ảnh (avatar, CCCD xác minh tuổi) đang lưu trên **Cloudinary** (xem bên dưới), không dùng Firebase Storage.
- **Ảnh (Cloudinary)**: avatar và ảnh CCCD xác minh tuổi upload lên Cloudinary qua **signed upload** — backend cấp chữ ký (`/cloudinary-sign`, yêu cầu Firebase ID token hợp lệ) trước mỗi lượt upload, không dùng "unsigned preset" công khai.
- **Backend Node.js** (`backend-payos/`, Express) — chịu trách nhiệm **mọi thao tác liên quan tới tiền/bí mật/email**, tách module theo chức năng:
  ```
  backend-payos/
  ├── index.js                 # entrypoint: load .env, khởi động app.js, app.listen()
  └── src/
      ├── app.js                # khởi tạo Express, mount toàn bộ route, gọi startCronJobs()
      ├── config/firebase.js    # khởi tạo Firebase Admin SDK, export firestore/auth/messaging + secrets (TICKET_SIGNING_SECRET, CLOUDINARY_*)
      ├── middleware/auth.middleware.js  # requireAuth / requireStaffAuth / requireManagerAuth (verify Firebase ID token)
      ├── routes/               # 1 file/nhóm endpoint: auth (OTP), payment (PayOS + ví), seats (giữ/nhả ghế), showtime (tạo suất chiếu), ticket (bán quầy/check-in/huỷ vé), cloudinary (ký upload), chat (Gemini), notification (FCM broadcast), movies (import TMDB)
      ├── services/             # logic nghiệp vụ thuần: pricing (tính tiền authoritative), seat/showtime (layout, sinh ghế, chống trùng giờ), ticket (ký QR), otp, gemini, notification, payment (client PayOS)
      └── jobs/cron.js          # 3 tác vụ nền: dọn vé PENDING treo, dynamic pricing theo tỷ lệ lấp đầy, push quảng cáo định kỳ
  ```
  - **Toàn bộ thao tác đụng tới tiền/điểm/vé đều tính lại "authoritative" ở server** (không tin số liệu client gửi lên): giá ghế, combo, voucher, giảm giá tự động, điểm loyalty, phụ thu theo loại suất chiếu.
  - Ví Stella Wallet (nạp/trừ), huỷ vé PENDING dở dang, ký/xác thực QR vé, cấp chữ ký upload Cloudinary — tất cả đi qua Admin SDK, client không ghi thẳng Firestore cho các thao tác này.
- **Routing**: Deep Link (`stella://`) xử lý callback PayOS (thành công/huỷ).

---

## 📁 Cấu trúc thư mục

```
lib/
├── core/                  # constants (PAYMENT_BACKEND_URL), widget dùng chung (GlobalInternetCheckWidget)
├── models/                # Movie, Theater, UserProfile, RoomLayout/RoomFormatSpec, Showtime, SessionTypeSpec...
├── providers/              # Riverpod providers (movies, theaters, user, room_formats...)
├── features/
│   ├── auth/               # login (+ OTP gate), register, profile, membership
│   ├── home/               # trang chủ, banner, popup khuyến mãi
│   ├── booking_and_payment/ # chi tiết phim, chọn suất/ghế/combo, thanh toán, vé của tôi
│   │   ├── services/       # pricing_service.dart (client-side, mirror JS backend), seat_reservation_service.dart, seat_layout_helper.dart (gợi ý ghế)
│   │   └── tasks/          # ghi chú việc cần làm dạng checklist (không phải code)
│   ├── staff/              # dashboard, soát vé, bán quầy, bảo trì ghế, báo cáo sự cố
│   ├── theater_manager/     # dashboard, quản lý phòng, heatmap, roster, điểm danh, sự cố
│   ├── admin/               # dashboard (tự lọc menu theo role), quản lý phim/user/voucher/định dạng phòng/luật giá/server config
│   ├── chat_ai/            # chatbot Gemini
│   ├── notifications/      # màn thông báo, FCM router (mở đúng màn khi bấm vào thông báo)
│   └── maps/               # bản đồ rạp
backend-payos/              # xem sơ đồ ở mục Kiến trúc Hệ thống phía trên
firestore.rules             # security rules — nguồn sự thật cho phân quyền
firestore.indexes.json      # composite index cho các query nhiều điều kiện
storage.rules                # cấu hình sẵn, hiện không dùng (xem ghi chú ở mục Kiến trúc)
AUDIT_AND_ROADMAP.md         # lịch sử audit/roadmap chi tiết theo từng đợt rà soát
```

---

## 🗄️ Mô hình dữ liệu Firestore

| Collection | Ai ghi | Mô tả |
|---|---|---|
| `users` | app (đăng ký) + admin (đổi role) | Hồ sơ người dùng: `role`, `isAdmin` (legacy), `assignedTheater`, `wallet_balance`, `loyalty_points`, `ageVerified`... |
| `movies` | admin | Phim (soft-delete qua `isDeleted`), có thể nhập nhanh từ TMDB. |
| `theaters` | admin (seed thủ công) | Danh sách rạp (tên phải khớp chính xác với `tickets.theaterName`). |
| `rooms` | theater_manager | Cấu hình phòng chiếu: số hàng, định dạng, tổ hợp trình chiếu/âm thanh, `brokenSeats`/`wheelchairSeats`. |
| `seat_map_versions` | theater_manager (tự động khi sửa phòng) | Snapshot lịch sử sơ đồ ghế — suất chiếu chốt `seatMapVersionId` để không bị ảnh hưởng khi phòng sửa sau này. |
| `room_formats` | admin | Danh mục định dạng phòng chiếu (13 loại mặc định + admin tự thêm). |
| `pricing_rules` | admin | Luật phụ thu/giảm giá tự cấu hình (thay công thức cứng). |
| `showtimes` (+ subcollection `seats`) | theater_manager | Suất chiếu; mỗi ghế là 1 document trong subcollection `seats` (trạng thái AVAILABLE/HOLDING/BOOKED, atomic qua transaction). |
| `showtime_seat_status` | backend | Mảng ghế đã đặt theo suất chiếu (tương thích ngược cho suất chiếu cũ chưa có subcollection `seats`). |
| `tickets` | backend (qua app gọi API) | Vé: seats, combos, giá, trạng thái (PENDING/COMPLETED/CANCELLED/CHECKED_IN), `qrSignature`. |
| `combos` | admin | Combo bắp nước theo rạp. |
| `vouchers` | admin/marketing | Mã giảm giá, `currentUses`/`maxUses` tăng trong transaction. |
| `movie_reviews` | app (khách hàng) | Đánh giá phim, bắt buộc kèm `ticketId` trỏ đúng vé COMPLETED. |
| `age_verification_requests` | app → admin duyệt | Yêu cầu xác minh tuổi (ảnh CCCD trên Cloudinary). |
| `notifications` | backend/admin | Thông báo trong app (khác với push FCM quảng cáo — cái đó không lưu Firestore). |
| `shifts` | theater_manager | Phân ca (Smart Roster) — nhân viên chỉ đọc được ca của chính mình. |
| `incidents` | staff | Báo cáo sự cố tại rạp. |
| `attendance_logs` | staff (check-in ca) | Điểm danh giờ vào ca thực tế. |
| `otp_codes` | backend only | Mã OTP đăng nhập (hash HMAC, không client nào đọc/ghi được — chỉ Admin SDK). |
| `checkin_audit_log` | backend only | Log mọi lượt check-in (kể cả thủ công) để đối soát. |
| `admin_audit_log` | backend/admin | Log đổi role, CRUD phim/voucher. |
| `configs` | admin | `server_config` (Gemini API Key sửa qua UI). |

---

## 🚀 Hướng dẫn Cài đặt & Chạy Dự án (dành cho máy mới clone repo)

> Toàn bộ bảng dưới đây ghi **đúng phiên bản đã verify chạy được** trên máy dev hiện tại của dự án (Windows), kèm cách kiểm tra máy bạn có khớp không. Nếu máy bạn khác phiên bản, cứ thử trước — hầu hết đều chấp nhận biên độ, chỉ JDK 17 cho Gradle là bắt buộc cứng.

### 0. Yêu cầu phiên bản công cụ

| Công cụ | Phiên bản đã verify chạy được | Lệnh kiểm tra máy bạn | Ghi chú |
|---|---|---|---|
| Flutter SDK | 3.44.4 (tối thiểu 3.35+, `pubspec.yaml` yêu cầu Dart ≥ 3.11.5) | `flutter --version` | Cài theo hướng dẫn chính thức tại https://docs.flutter.dev/get-started/install nếu chưa có |
| Dart SDK | 3.12.2 | đi kèm Flutter, không cài riêng | |
| Node.js | v24.13.0 (tối thiểu 18+) | `node --version` | Cài từ https://nodejs.org (bản LTS là đủ) |
| npm | 11.8.0 | `npm --version` | Đi kèm Node.js |
| JDK cho Gradle build Android | **17** (bắt buộc — `android/app/build.gradle.kts` ép cứng `sourceCompatibility/targetCompatibility = VERSION_17`) | Xem bước "Kiểm tra JDK" bên dưới | **Lưu ý quan trọng**: `java -version` ở terminal hệ thống có thể ra JDK khác (VD JDK 8) — điều đó **bình thường và không sao**, vì Android Studio dùng JDK **riêng của nó** (bundled JBR) để chạy Gradle, không phụ thuộc `java` trên PATH hệ thống. Chỉ cần đảm bảo Android Studio trỏ đúng JDK 17 (xem bên dưới), không cần sửa PATH hệ thống. |
| Android Gradle Plugin | 8.12.1 (đã khai báo sẵn trong `android/settings.gradle.kts`) | — | Không cần chỉnh, Gradle tự tải khi build lần đầu |
| Kotlin | 2.2.20 (đã khai báo sẵn) | — | Không cần chỉnh |
| Android NDK | 28.2.13676358 (đã khai báo sẵn trong `android/app/build.gradle.kts`) | — | Android Studio tự tải qua SDK Manager nếu thiếu (sẽ hiện prompt khi build lần đầu) |
| Firebase CLI | 15.20.0 | `firebase --version` | Cài bằng `npm i -g firebase-tools`; cần để deploy rules/indexes |
| ngrok (hoặc tương đương) | bất kỳ bản mới | `ngrok version` | Tải tại https://ngrok.com/download, cần tạo tài khoản miễn phí + `ngrok config add-authtoken <token>` (token lấy ở https://dashboard.ngrok.com/get-started/your-authtoken) trước khi dùng lệnh `ngrok http` |

**Kiểm tra JDK Android Studio đang dùng** (không phải JDK hệ thống): Android Studio → menu **File → Settings** (Windows/Linux) hoặc **Android Studio → Settings** (macOS) → **Build, Execution, Deployment → Build Tools → Gradle** → mục **Gradle JDK** phải là bản 17 trở lên (thường có sẵn lựa chọn "Embedded JDK" hoặc tự động tải "17" trong dropdown — chọn cái đó, không cần cài JDK riêng theo tay).

Kiểm tra nhanh toàn bộ môi trường Flutter: chạy `flutter doctor -v` trong terminal tại thư mục gốc project — mọi mục nên có dấu ✓ (mục "Android toolchain" nếu thiếu license thì chạy thêm `flutter doctor --android-licenses` và gõ `y` cho từng câu hỏi).

### 1. Clone & lấy các file cấu hình bí mật (KHÔNG có trong git)

```bash
git clone https://github.com/dattien282/datvexemphim.git
cd datvexemphim
```

3 file sau chứa secret nên **không được commit** (đã có trong `.gitignore`) — máy đang chạy dự án này (nếu là máy gốc) đã có sẵn cả 3, còn nếu là **máy khác/máy mới clone thì CHƯA CÓ**, phải tự xin hoặc tự tạo:

| File cần xin/tạo | Đặt đúng vào đường dẫn | Dùng để làm gì | Lấy ở đâu |
|---|---|---|---|
| `google-services.json` | `android/app/google-services.json` | Bắt buộc để Gradle build Android — plugin `com.google.gms.google-services` (khai báo trong `android/app/build.gradle.kts`) sẽ **báo lỗi build ngay lập tức** nếu thiếu file này, dù config Firebase runtime đã hardcode sẵn trong `lib/main.dart` | Firebase Console → chọn project → biểu tượng bánh răng ⚙️ (góc trên trái) → **Project settings** → tab **General** → cuộn xuống "Your apps" → chọn app Android (package name `com.example.dat_ve_xem_phim_group5`) → nút **google-services.json** để tải về. Nếu project CHƯA có app Android nào đăng ký, bấm "Add app" → chọn biểu tượng Android → nhập package name chính xác **`com.example.dat_ve_xem_phim_group5`** (lấy từ `android/app/build.gradle.kts`, dòng `applicationId`) → làm theo hướng dẫn để tải file |
| `serviceAccountKey.json` | `backend-payos/serviceAccountKey.json` | Firebase Admin SDK cho backend (thanh toán, ví, check-in, huỷ vé, gửi OTP, mọi thao tác Firestore phía server đều cần) | Firebase Console → ⚙️ **Project settings** → tab **Service accounts** → nút **Generate new private key** → xác nhận → file JSON tự tải về, đổi tên/di chuyển vào đúng thư mục trên |
| `.env` | `backend-payos/.env` | Chứa mọi secret khác (PayOS, Cloudinary, SMTP, TMDB...) | Tự tạo file mới, xem nội dung mẫu đầy đủ ở bước 2 bên dưới |

> Firebase project hiện tại: **`datvexemphimgroup5`** (project ID — thấy trong `lib/main.dart` phần `FirebaseOptions`, và trong `android/app/google-services.json` field `project_id`). Nếu bạn được thêm vào project này (không tự tạo project riêng), cần được chủ dự án cấp quyền **Editor** hoặc **Owner** trong Firebase Console (Project settings → **Users and permissions** → Add member, nhập đúng email Google của bạn) — thiếu quyền này bạn sẽ không tải được `google-services.json`/`serviceAccountKey.json` dù đã được thêm làm member xem-only.
>
> **Nếu muốn tự tạo Firebase project riêng** (tách dữ liệu, không dùng chung): tạo project mới tại https://console.firebase.google.com → bật **Authentication** (Email/Password + Google), **Cloud Firestore** (chọn Production mode), **Cloud Messaging** → đăng ký 1 app Android với đúng package name `com.example.dat_ve_xem_phim_group5` → tải `google-services.json` → tải `serviceAccountKey.json` như hướng dẫn trên → **quan trọng**: phải tự sửa `FirebaseOptions` hardcode trong `lib/main.dart` (dòng `apiKey`, `appId`, `messagingSenderId`, `projectId`, `storageBucket`) sang đúng thông số project mới của bạn (lấy ở Project settings → General → "Your apps" → SDK setup and configuration), nếu không app vẫn kết nối vào project cũ dù đã đổi `google-services.json`.

### 2. Cài đặt Backend (`backend-payos/`)

```bash
cd backend-payos
npm install
```
Lệnh này đọc `package.json` và cài toàn bộ 7 dependency (`express`, `firebase-admin`, `@payos/node`, `@google/generative-ai`, `cors`, `dotenv`, `nodemailer`) vào `backend-payos/node_modules/` (không commit, tự sinh lại bằng lệnh trên).

Tạo file **mới** tên `.env` (cùng cấp `package.json`, tức `backend-payos/.env`) với nội dung sau — mỗi biến kèm chỉ dẫn lấy giá trị ở đâu:

```env
PORT=3000

# PayOS - đăng ký tài khoản doanh nghiệp tại https://business.payos.vn (miễn phí
# cho sandbox/test), sau khi tạo kênh thanh toán vào mục "Kênh thanh toán" > "Thông
# tin kết nối API" để lấy 3 giá trị dưới. Không có PayOS thì chuyển khoản/QR ngân
# hàng sẽ không hoạt động, nhưng thanh toán bằng Stella Wallet vẫn dùng được bình
# thường (không phụ thuộc PayOS).
PAYOS_CLIENT_ID=...
PAYOS_API_KEY=...
PAYOS_CHECKSUM_KEY=...

# Ký/xác thực QR vé + mã OTP - tự sinh 1 chuỗi ngẫu nhiên đủ dài (không cần nhớ,
# không cần ý nghĩa), KHÔNG dùng giá trị mặc định khi chạy thật. Sinh nhanh bằng:
#   node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
TICKET_SIGNING_SECRET=doi_thanh_chuoi_ngau_nhien_that_dai_cua_ban

# Cloudinary - dùng để upload avatar + ảnh CCCD xác minh tuổi (signed upload,
# không public). Đăng ký tài khoản miễn phí tại https://cloudinary.com/users/register/free
# → sau khi đăng nhập, trang Dashboard mặc định đã hiện đủ 3 giá trị này
# (Cloud name / API Key / API Secret) - bấm icon con mắt để hiện API Secret.
CLOUDINARY_CLOUD_NAME=g9u2mtmv
CLOUDINARY_API_KEY=...
CLOUDINARY_API_SECRET=...

# Gmail dùng để gửi mã OTP đăng nhập. SMTP_USER = địa chỉ Gmail bất kỳ (có thể
# tạo 1 Gmail riêng cho dự án). SMTP_PASS = "App Password" 16 ký tự, KHÔNG PHẢI
# mật khẩu Gmail thật - lấy tại https://myaccount.google.com/apppasswords
# (yêu cầu tài khoản Gmail đó đã bật Xác minh 2 bước/2FA trước, nếu chưa bật thì
# trang App Passwords sẽ không hiện ra, phải bật 2FA ở
# https://myaccount.google.com/signinoptions/two-step-verification trước).
SMTP_USER=...
SMTP_PASS=...

# Tuỳ chọn - chatbot AI Gemini; lấy API key miễn phí tại https://aistudio.google.com/apikey
# (đăng nhập bằng tài khoản Google bất kỳ). Có thể để trống và cấu hình sau qua
# màn Admin > Cấu hình Server trong app thay vì sửa .env + restart server.
GEMINI_API_KEY=

# Tuỳ chọn - nhập phim nhanh từ TMDB, lấy API key miễn phí tại
# https://www.themoviedb.org/settings/api (cần đăng ký tài khoản TMDB trước).
# Để trống thì dùng dữ liệu mẫu (mock) khi bấm "Nhập từ TMDB", vẫn test được
# luồng nhập liệu mà không cần key thật.
TMDB_API_KEY=

# Tuỳ chọn - push quảng cáo định kỳ (voucher/phim hot/combo/suất chiếu ưu đãi)
# gửi thẳng xuống thiết bị qua FCM, không cần admin bấm tay. Mặc định: bật, mỗi 6 giờ.
PROMO_PUSH_ENABLED=true
PROMO_PUSH_INTERVAL_HOURS=6

# Tuỳ chọn - phụ thu tự động theo tỷ lệ lấp đầy ghế (>70% -> +5%, >90% -> +10%).
# Mặc định: bật. Đặt false để tắt.
DYNAMIC_PRICING_ENABLED=true
```

Đặt file `serviceAccountKey.json` (đã tải ở bước 1) vào đúng `backend-payos/serviceAccountKey.json` — cùng cấp với `package.json`, **không** để trong `src/`.

Chạy server:
```bash
npm start
# lệnh trên tương đương chạy trực tiếp: node index.js
```
Server chạy tại `http://localhost:3000`. Log khởi động **phải** hiện đủ các dòng sau (thứ tự có thể khác nhau chút, không sao):
```
✅ Firebase Admin SDK initialized.
✅ Promo push tự động: bật, mỗi 6 giờ.
✅ Cron dọn vé PENDING treo: bật, quét mỗi 5 phút.
✅ Dynamic pricing: bật, quét mỗi 30 phút (tắt bằng DYNAMIC_PRICING_ENABLED=false).
Server đang chạy tại http://localhost:3000
```
Nếu thấy cảnh báo `⚠️ Firebase Admin SDK init failed` thay vì dòng đầu tiên, gần như chắc chắn `serviceAccountKey.json` sai vị trí/sai nội dung — kiểm tra lại trước khi làm gì tiếp theo, vì gần như mọi tính năng thanh toán/vé/OTP sẽ không hoạt động nếu thiếu.

Mở trình duyệt vào `http://localhost:3000` — thấy dòng chữ `✅ Stella Cinema PayOS Backend is running!` là server đã chạy đúng, sẵn sàng để app Flutter gọi vào.

Để dừng server: quay lại cửa sổ terminal đang chạy `npm start`, bấm `Ctrl + C`.

**Cho PayOS webhook gọi được vào máy bạn** (bắt buộc để trạng thái vé tự chuyển COMPLETED sau khi chuyển khoản qua PayOS — không cần bước này nếu chỉ test thanh toán bằng Stella Wallet):
```bash
ngrok http 3000
```
Lệnh này mở 1 cửa sổ terminal MỚI (giữ nguyên, không tắt) hiện dòng dạng `Forwarding  https://xxxx.ngrok-free.app -> http://localhost:3000`. Copy đúng URL `https://xxxx.ngrok-free.app` này, vào PayOS Dashboard → mục Webhook → dán vào kèm `/payos-webhook` ở cuối, tức `https://xxxx.ngrok-free.app/payos-webhook`. **Lưu ý**: bản ngrok miễn phí đổi URL này mỗi lần chạy lại `ngrok http 3000` — mỗi lần khởi động lại ngrok phải cập nhật lại URL webhook trên PayOS Dashboard.

### 3. Cài đặt Frontend (Flutter App)

Ở thư mục gốc project (thoát khỏi `backend-payos/`, `cd ..` nếu đang ở đó):
```bash
flutter pub get
```
Lệnh này tải toàn bộ package khai báo trong `pubspec.yaml` (Firebase, Riverpod, các UI package...) — chạy lại lệnh này bất cứ khi nào `pubspec.yaml` thay đổi hoặc sau khi mới clone repo.

`google-services.json` đã đặt đúng chỗ ở bước 1 (`android/app/google-services.json`) — không cần làm gì thêm ở đây, chỉ nhắc lại vì thiếu file này thì bước build ở dưới sẽ báo lỗi ngay (thường là lỗi `File google-services.json is missing`).

**Cấu hình địa chỉ backend** (`lib/core/constants.dart` mặc định trỏ `PAYMENT_BACKEND_URL` tới `http://10.0.2.2:3000` — `10.0.2.2` là địa chỉ IP đặc biệt mà Android Emulator dùng để trỏ ngược về `localhost` của MÁY TÍNH đang chạy emulator đó, không phải địa chỉ thật, chỉ hiểu được bên trong emulator):

- **Chạy Android Emulator + backend `npm start` cùng 1 máy tính**: không cần chỉnh gì, dùng mặc định, cứ `flutter run` bình thường.
- **Chạy trên điện thoại thật qua USB, hoặc backend chạy máy khác trong mạng LAN, hoặc dùng ngrok**: bắt buộc truyền `--dart-define` khi chạy/build, nếu không app sẽ cố gọi vào `10.0.2.2` (không tồn tại ngoài emulator) và mọi thao tác cần backend sẽ báo lỗi kết nối:
  ```bash
  flutter run --dart-define=PAYMENT_BACKEND_URL=https://xxxx.ngrok-free.app
  ```
  (thay bằng URL ngrok thật ở bước 2, hoặc `http://<IP-LAN-của-máy-chạy-backend>:3000` nếu điện thoại và máy tính chạy backend cùng 1 mạng Wi-Fi — lấy IP LAN bằng `ipconfig` trên Windows, tìm dòng "IPv4 Address").

**Chạy ứng dụng trên Android**:
1. Mở Android Emulator có sẵn trong Android Studio (Tools → Device Manager → bấm nút Play cạnh 1 thiết bị ảo), HOẶC cắm điện thoại thật qua cáp USB và bật **Chế độ nhà phát triển → Gỡ lỗi USB** (Developer Options → USB Debugging) trên điện thoại.
2. Kiểm tra thiết bị được nhận diện: `flutter devices` (phải thấy tên thiết bị trong danh sách).
3. Chạy: `flutter run` (hoặc kèm `--dart-define` như trên nếu cần).

Lần build đầu tiên thường mất vài phút (Gradle tải dependency Android). Nếu build lỗi liên quan Gradle/NDK, mở project bằng Android Studio 1 lần trước (File → Open → chọn thư mục `android/` bên trong project) để Android Studio tự tải đủ SDK/NDK cần thiết, rồi quay lại chạy `flutter run` từ terminal.

### 4. Deploy Firestore Rules & Indexes (bắt buộc)

Rules quyết định toàn bộ phân quyền server-side (roles, ai đọc/ghi được gì) — **nếu không deploy, một số tính năng sẽ bị `permission-denied`** dù code app không lỗi gì. Indexes cần khớp với mọi query nhiều điều kiện trong app/backend — thiếu index thì query đó lỗi `FAILED_PRECONDITION` khi dữ liệu đủ lớn (thường không thấy lỗi lúc dev vì ít dữ liệu).

Ở thư mục gốc project (nơi có file `firebase.json`):
```bash
firebase login
```
Lệnh này mở trình duyệt yêu cầu đăng nhập bằng tài khoản Google có quyền truy cập project Firebase (phải là tài khoản đã được cấp Editor/Owner ở bước 1). Đăng nhập xong quay lại terminal sẽ thấy "Success! Logged in as ...".

```bash
firebase use datvexemphimgroup5    # hoặc project ID Firebase thật của bạn nếu tự tạo project riêng
firebase deploy --only firestore:rules,firestore:indexes,storage
```
Deploy xong sẽ thấy dòng `✔ Deploy complete!` cùng link tới Firebase Console. Kiểm tra lại đúng chưa: Firebase Console → Firestore Database → tab **Rules** phải thấy đúng nội dung khớp với file `firestore.rules` trong repo (so ngày giờ cập nhật).

> Mỗi khi thêm 1 query Firestore mới có từ 2 điều kiện `.where()` trở lên (hoặc `.where()` kèm `.orderBy()` trên field khác), nhớ kiểm tra `firestore.indexes.json` đã có index tương ứng chưa, rồi deploy lại `firestore:indexes`. Index Firestore build ngầm mất vài phút sau khi deploy — theo dõi tiến độ ở Firebase Console → Firestore Database → tab **Indexes**.

### 5. Seed dữ liệu rạp (tuỳ chọn, nếu Firestore đang trống)

`lib/utils/db_updater.dart` có sẵn các hàm vận hành dữ liệu, gọi được trực tiếp từ UI qua màn **Admin → Cấu hình Server**:
- **Cập nhật DB (Theater & Showtimes)**: cập nhật quy mô rạp + seed suất chiếu mẫu.
- **Migrate Showtimes → showAt**: backfill field `showAt` (Timestamp) cho suất chiếu cũ.
- **Migrate Định dạng phòng → Stella**: đổi tên định dạng phòng cũ sang hệ định dạng riêng của Stella Cinema.
- **Seed danh mục định dạng phòng**: đưa 13 định dạng phòng mặc định vào collection `room_formats` (chỉ cần chạy 1 lần, tự bỏ qua nếu đã có dữ liệu).

### 6. Thiết lập tài khoản Admin đầu tiên

1. Đăng ký tài khoản `user` bình thường trên app (nếu là email/password, cần xác thực email + nhập OTP trước khi vào app lần đầu).
2. Firebase Console → Firestore Database → collection `users` → tìm document vừa tạo (id = uid).
3. Sửa field `role` từ `"user"` thành `"admin"`.
4. Đăng xuất/đăng nhập lại (hoặc khởi động lại app) để thấy Admin Dashboard.

Từ tài khoản Admin, bạn có thể cấp các vai trò còn lại (`staff`, `theater_manager`, `accountant`, `marketing`) qua màn **Quản lý Người dùng** — các vai trò này bỏ qua bước OTP/xác thực email vì được xem là do quản trị viên cấp trực tiếp.

---

## 🛡️ Luồng bảo mật mã QR

1. Khi vé được tạo/thanh toán xong, backend ký một chữ ký (HMAC-SHA256, `TICKET_SIGNING_SECRET`) gồm `ticketId` + `orderCode` + trạng thái vé (`src/services/ticket.service.js`).
2. QR Code trên app chứa `{ticketId, signature}` (không phải dữ liệu vé thô).
3. Staff quét QR → app gửi `signature` lên `/verify-checkin` → server xác thực chữ ký bằng `crypto.timingSafeEqual` (chống timing attack), kiểm tra đúng rạp + khung giờ hợp lệ (-30 đến +180 phút quanh giờ chiếu) trước khi đánh dấu Đã Check-in. Toàn bộ lượt check-in (kể cả thủ công) được ghi vào `checkin_audit_log`.

---

## 🔐 Luồng OTP đăng nhập 2 lớp

Áp dụng cho khách hàng đăng nhập bằng Email/Password (không áp dụng Google Sign-In, không áp dụng staff/manager/admin/accountant/marketing — các role này do admin cấp trực tiếp, đã xác minh danh tính khi cấp tài khoản).

1. Sau khi Firebase Auth xác thực đúng email/password, app gọi `/auth/send-otp` (kèm ID token) — server sinh mã 6 số, lưu **hash** HMAC-SHA256 (không phải plaintext) vào `otp_codes/{uid}` (TTL 5 phút, tối đa 5 lần nhập sai), gửi qua Gmail SMTP.
2. Dialog nhập mã hiện **ngay lập tức** (không chờ email gửi xong mới hiện), có spinner báo đang gửi, nút gửi lại mã, và nút Huỷ.
3. Đóng dialog bằng bất kỳ cách nào (bấm ra ngoài, back, nút Huỷ) mà chưa xác thực xong → tự động đăng xuất, tránh để lại phiên đăng nhập dở dang.
4. Nhập đúng mã → `/auth/verify-otp` xác thực bằng `crypto.timingSafeEqual` → vào app.

---

## ⏱️ Cron job & tác vụ nền (backend)

Tất cả đăng ký trong `backend-payos/src/jobs/cron.js`, chạy khi backend khởi động (không cần thiết lập gì thêm ngoài các biến `.env` tuỳ chọn):

| Job | Chu kỳ | Việc làm |
|---|---|---|
| Dọn vé PENDING treo | mỗi 5 phút | Xoá vé PENDING quá 15 phút chưa thanh toán, nhả lại ghế đã giữ. |
| Dynamic pricing | mỗi 30 phút | Phụ thu tự động theo tỷ lệ lấp đầy ghế của suất chiếu sắp diễn ra (>70% ghế đã bán → +5%, >90% → +10%, chỉ tăng không giảm). Tắt bằng `DYNAMIC_PRICING_ENABLED=false`. |
| Push quảng cáo định kỳ | mặc định mỗi 6 giờ | Gửi thẳng notification FCM (không lưu vào `notifications` trong app) — nội dung xoay vòng theo voucher/phim hot/combo/suất chiếu ưu đãi thật. Tắt bằng `PROMO_PUSH_ENABLED=false`, đổi chu kỳ bằng `PROMO_PUSH_INTERVAL_HOURS`. |

---

## 📝 Những điều cần biết trước khi phát triển tiếp

- **`/gemini-chat` yêu cầu đăng nhập** (thêm `requireAuth` để chặn lạm dụng quota Gemini) — khách vãng lai chưa đăng nhập tự động rơi về chế độ trả lời offline, không báo lỗi rõ ràng cho người dùng biết vì sao chatbot "kém" hơn.
- **Firebase API Key / Google Maps API Key vẫn hardcode trong source** (`lib/main.dart`, `AndroidManifest.xml`) — chấp nhận được vì được Firestore/Storage Rules bảo vệ ở tầng dữ liệu, nhưng nên xoay vòng nếu repo public.
- **`storage.rules` tồn tại nhưng không dùng** — bucket Firebase Storage chưa được khởi tạo trên project, toàn bộ ảnh đi qua Cloudinary. Đừng debug nhầm hướng nếu thấy lỗi upload ảnh — kiểm tra `CLOUDINARY_*` trong `.env` trước.
- **Mỗi lần thêm/sửa query Firestore nhiều điều kiện**, nhớ đối chiếu lại `firestore.indexes.json` và deploy lại — index thiếu không lỗi ngay lúc code ít dữ liệu, chỉ lộ ra khi chạy thật.
- Lịch sử đầy đủ các bug đã tìm thấy/đã sửa qua từng đợt rà soát (bao gồm cả các quyết định thiết kế có chủ đích, ví dụ ví Stella Wallet nạp không giới hạn theo yêu cầu riêng của dự án) nằm ở [`AUDIT_AND_ROADMAP.md`](AUDIT_AND_ROADMAP.md) — đọc mục cuối cùng của file đó trước nếu chỉ muốn biết "hiện tại còn thiếu gì".

---

**Nhóm Phát Triển - Group 5**
Chúc bạn có những trải nghiệm tuyệt vời với Stella Cinema! 🍿🎬
