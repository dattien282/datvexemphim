# KỊCH BẢN THUYẾT TRÌNH DỰ ÁN STELLA CINEMA (Nhóm 5 người)

Dự án: **Stella Cinema** — Ứng dụng đặt vé xem phim (Flutter + Firebase + Backend PayOS).
Thời lượng gợi ý: ~20 phút trình bày (mỗi người ~4 phút) + 5-10 phút hỏi đáp.
Cấu trúc: 20 slide, chia đều 4 slide/người. Mỗi mục gồm **Nội dung hiển thị trên slide** và **Lời thoại (Speaker Notes)** để đọc/diễn.

---

# 🎤 NGƯỜI 1 — MỞ ĐẦU, ĐẶT VẤN ĐỀ & KIẾN TRÚC TỔNG THỂ

## Slide 1: Trang bìa
**Nội dung hiển thị:**
- STELLA CINEMA — Hệ thống đặt vé xem phim thông minh
- Môn học / Đề tài, Nhóm 5, tên GVHD
- Danh sách 5 thành viên + vai trò phụ trách (VD: Kiến trúc & Backend / User flow / Vận hành rạp / Quản trị hệ thống / Kỹ thuật & Tổng kết)
- Công nghệ: Flutter · Firebase · Node.js · PayOS · Cloudinary · Gemini AI

**Lời thoại:**
> "Kính chào thầy/cô và các bạn. Nhóm em xin phép trình bày đồ án Stella Cinema — một hệ thống đặt vé xem phim hoàn chỉnh, được xây dựng bằng Flutter kết hợp Firebase và một backend riêng xử lý thanh toán PayOS. Đây không chỉ là một ứng dụng đặt vé đơn thuần, mà là một hệ thống đa vai trò, mô phỏng đầy đủ nghiệp vụ vận hành thực tế của một chuỗi rạp chiếu phim — từ khách hàng, nhân viên bán vé, quản lý rạp, cho đến kế toán, marketing và quản trị viên hệ thống. Sau đây, nhóm em xin lần lượt trình bày."

## Slide 2: Đặt vấn đề
**Nội dung hiển thị:**
- Thực trạng: đặt vé tại quầy gây xếp hàng, dễ trùng ghế; quản lý rạp thủ công tốn nhân lực; khó kiểm soát doanh thu nhiều chi nhánh theo thời gian thực.
- Bài toán đặt ra:
  1. Làm sao đặt vé online tránh trùng ghế khi nhiều người đặt cùng lúc?
  2. Làm sao quản lý vận hành nhiều rạp – nhiều vai trò trên cùng một hệ thống?
  3. Làm sao đảm bảo thanh toán, vé điện tử không bị giả mạo?

**Lời thoại:**
> "Trước khi đi vào chi tiết, nhóm em xin nêu vấn đề thực tế. Việc đặt vé xem phim truyền thống thường gặp tình trạng xếp hàng, đặt trùng ghế khi lượng khách đông, và việc quản lý vận hành nhiều rạp – nhiều vai trò như quản lý, nhân viên, kế toán thường tách rời, khó đồng bộ dữ liệu. Ngoài ra, vé giấy hoặc vé điện tử đơn giản rất dễ bị làm giả. Từ đó, nhóm em đặt mục tiêu xây dựng một hệ thống giải quyết đồng thời cả ba bài toán: đặt ghế real-time không trùng lặp, hệ thống đa vai trò vận hành thống nhất, và vé điện tử có chữ ký bảo mật chống giả mạo."

## Slide 3: Tổng quan hệ thống & Công nghệ sử dụng
**Nội dung hiển thị:**
- Frontend: Flutter (đa nền tảng, chính là Android), state management **Riverpod**, kiến trúc **MVVM** (screens/viewmodels/repositories/services theo từng feature module).
- Backend riêng `backend-payos/`: Node.js + Express — xử lý PayOS, ví nội bộ Stella Wallet, ký QR vé (HMAC), OTP, email (Nodemailer), push FCM, chatbot Gemini, import phim từ TMDB, cron jobs.
- Dữ liệu: **Cloud Firestore** (~20 collection: users, movies, showtimes, tickets, vouchers...), **Firebase Authentication**, ảnh lưu trên **Cloudinary**.
- Nguyên tắc thiết kế: mọi tính năng tách theo module `lib/features/<module>/{screens, viewmodels, repositories, services}`.

**Lời thoại:**
> "Về mặt công nghệ, ứng dụng được xây dựng theo mô hình MVVM rõ ràng: mỗi tính năng là một module riêng gồm màn hình, viewmodel xử lý logic và repository giao tiếp dữ liệu, giúp code dễ bảo trì và mở rộng. Phần giao diện dùng Flutter với Riverpod để quản lý trạng thái. Dữ liệu chính lưu trên Cloud Firestore với khoảng 20 collection khác nhau, xác thực người dùng qua Firebase Authentication, còn hình ảnh như poster phim hay ảnh CCCD thì lưu trên Cloudinary. Đặc biệt, nhóm em tách riêng một backend Node.js độc lập chỉ để xử lý những nghiệp vụ nhạy cảm về tiền bạc và bảo mật — thanh toán PayOS, ví nội bộ, ký vé điện tử, gửi OTP — nhằm không để lộ bất kỳ khóa bí mật nào ở phía client."

## Slide 4: Kiến trúc tổng thể & Luồng dữ liệu
**Nội dung hiển thị:**
- Sơ đồ: [Flutter App] ⇄ [Firebase: Auth/Firestore] ⇄ [Backend PayOS: Node.js/Express] ⇄ [PayOS / Cloudinary / Gemini / TMDB / FCM]
- Nguyên tắc **"Authoritative pricing"**: giá tiền luôn được backend/collection `pricing_rules` tính lại lần cuối để tránh sai lệch/gian lận giá ở client.
- `firestore.rules` là tầng phân quyền thật ở server, không chỉ ẩn UI.
- 3 cron job nền: dọn vé PENDING quá hạn, tính giá động (dynamic pricing), đẩy thông báo quảng cáo định kỳ.

**Lời thoại:**
> "Đây là sơ đồ kiến trúc tổng thể. Ứng dụng Flutter giao tiếp trực tiếp với Firebase cho các thao tác đọc/ghi dữ liệu thông thường, nhưng với mọi thứ liên quan đến tiền — như thanh toán, ví, giá vé cuối cùng — hệ thống luôn gọi qua backend PayOS để tính toán lại, tránh trường hợp người dùng can thiệp giá ở phía client. Firestore Rules đóng vai trò như một lớp bảo vệ dữ liệu thật sự ở tầng server, không chỉ là ẩn nút bấm trên giao diện. Ngoài ra, backend còn chạy 3 tác vụ nền định kỳ: tự động huỷ những vé giữ chỗ quá hạn chưa thanh toán, tính lại giá vé động theo khung giờ, và gửi thông báo khuyến mãi theo lịch. Đây chính là phần xương sống giúp toàn bộ hệ thống vận hành tự động và an toàn."
> *(Chuyển giao)* "Sau đây em xin mời bạn [Tên người 2] trình bày trải nghiệm của người dùng cuối trên ứng dụng."

---

# 🎤 NGƯỜI 2 — TRẢI NGHIỆM NGƯỜI DÙNG (USER FLOW)

## Slide 5: Đăng ký / Đăng nhập bảo mật
**Nội dung hiển thị:**
- 2 phương thức: Google Sign-In hoặc Email + mật khẩu kèm **OTP xác thực 2 lớp** (gửi qua email bằng Nodemailer từ backend).
- Xác minh tuổi tự động cho phim giới hạn độ tuổi (T18): người dùng upload ảnh CCCD qua Cloudinary → vào hàng chờ `age_verification_requests` → Admin duyệt.
- Màn hình liên quan: `lib/features/auth/screens` (login, profile), `auth_viewmodel.dart`.

**Lời thoại:**
> "Em xin trình bày phần trải nghiệm người dùng, bắt đầu từ đăng nhập. Người dùng có thể đăng nhập nhanh bằng Google, hoặc đăng ký bằng email kèm lớp bảo mật thứ hai là mã OTP gửi về email, do backend xử lý và gửi qua Nodemailer. Đây là bước quan trọng để đảm bảo tài khoản không bị chiếm đoạt. Một điểm đặc biệt của hệ thống là cơ chế xác minh độ tuổi tự động: khi người dùng muốn đặt vé cho phim dán nhãn 18+, hệ thống sẽ yêu cầu chụp ảnh căn cước công dân, ảnh được lưu an toàn trên Cloudinary, sau đó vào hàng chờ để quản trị viên xét duyệt thủ công trước khi cho phép mua vé phim đó."

## Slide 6: Duyệt phim & Đặt vé
**Nội dung hiển thị:**
- Trang chủ: phim đang chiếu / sắp chiếu, tìm kiếm, đánh giá phim.
- Chọn rạp → chọn suất chiếu → **sơ đồ ghế thời gian thực**: ghế đang được người khác giữ sẽ khoá tạm thời (transaction), tránh trùng ghế.
- 13 định dạng phòng chiếu: Standard, VIP, IMAX, 4DX, Dolby Atmos...
- Chọn combo bắp nước, áp mã voucher, tích điểm loyalty.

**Lời thoại:**
> "Sau khi đăng nhập, người dùng vào trang chủ để duyệt danh sách phim đang chiếu và sắp chiếu, xem đánh giá từ những người xem trước. Khi chọn một phim, người dùng chọn rạp, suất chiếu, rồi đến sơ đồ ghế. Đây là phần kỹ thuật nhóm em tâm đắc nhất: sơ đồ ghế cập nhật thời gian thực, khi một người đang chọn ghế thì ghế đó lập tức bị khoá tạm thời bằng transaction trên Firestore, để không ai khác có thể chọn trùng — giải quyết đúng bài toán trùng ghế đã nêu ở đầu. Hệ thống còn hỗ trợ 13 định dạng phòng chiếu khác nhau như VIP, IMAX, 4DX, Dolby Atmos, mỗi loại có giá khác nhau. Sau khi chọn ghế, người dùng có thể thêm combo bắp nước, áp mã giảm giá voucher, và tích điểm thành viên."

## Slide 7: Thanh toán & Vé điện tử
**Nội dung hiển thị:**
- 2 phương thức thanh toán: **PayOS** (quét mã QR / chuyển khoản ngân hàng, có webhook xác nhận tự động) hoặc **Stella Wallet** (ví nội bộ).
- Vé điện tử: mã QR được **ký số bằng HMAC** ở backend → chống làm giả, chỉ backend mới xác thực được.
- Ưu đãi theo hạng thành viên, tích/dùng điểm loyalty.

**Lời thoại:**
> "Về thanh toán, hệ thống hỗ trợ hai hình thức: thanh toán qua PayOS bằng mã QR hoặc chuyển khoản ngân hàng — khi giao dịch thành công, PayOS sẽ gửi webhook về backend để tự động xác nhận đơn hàng mà không cần người dùng bấm 'đã thanh toán'. Hình thức thứ hai là ví nội bộ Stella Wallet, tiện cho khách hàng thân thiết nạp tiền trước. Sau khi thanh toán, hệ thống sinh ra vé điện tử dưới dạng mã QR, nhưng mã này không đơn thuần là chuỗi ký tự — nó được ký số bằng thuật toán HMAC ở phía backend, nghĩa là chỉ backend mới có khóa bí mật để xác thực được vé thật, giúp chống giả mạo vé hoàn toàn."

## Slide 8: Demo Chatbot AI & Trung tâm thông báo
**Nội dung hiển thị:**
- Chatbot AI (`cinema_ai_chatbot_screen.dart`) dùng **Gemini API**, có cơ chế fallback trả lời offline nếu chưa cấu hình API key — hỗ trợ tư vấn phim, giải đáp thắc mắc.
- Trung tâm thông báo real-time (Firestore StreamBuilder) + Push Notification (FCM) khi có vé mới, khuyến mãi, nhắc lịch chiếu.
- *(Demo trực tiếp trên app tại đây nếu có)*

**Lời thoại:**
> "Điểm nhấn cuối trong trải nghiệm người dùng là chatbot AI tích hợp Gemini, có thể tư vấn phim phù hợp hoặc giải đáp thắc mắc, và nếu chưa cấu hình API key thì hệ thống tự chuyển sang chế độ trả lời offline dự phòng để không bị lỗi. Song song đó là Trung tâm thông báo, đồng bộ thời gian thực từ Firestore và kết hợp Firebase Cloud Messaging để đẩy thông báo ngay cả khi người dùng không mở app — ví dụ xác nhận đặt vé thành công hay nhắc lịch chiếu sắp tới. Sau đây em xin demo nhanh luồng đặt vé và nhận thông báo trên ứng dụng thật."
> *(Chuyển giao)* "Em xin cảm ơn, và mời bạn [Tên người 3] tiếp tục phần vận hành phía nhân viên và quản lý rạp."

---

# 🎤 NGƯỜI 3 — VẬN HÀNH: NHÂN VIÊN (STAFF) & QUẢN LÝ RẠP (THEATER MANAGER)

## Slide 9: Vai trò Staff — Dashboard & bán vé quầy
**Nội dung hiển thị:**
- `staff_dashboard_screen.dart`: 3 tab — Vé hôm nay / Ca làm / Thống kê.
- `StaffWalkInSaleScreen`: bán vé trực tiếp tại quầy cho khách không đặt online.
- Chấm công ca làm bằng quét QR.

**Lời thoại:**
> "Em xin trình bày về vai trò Nhân viên rạp. Sau khi đăng nhập bằng tài khoản staff, nhân viên thấy dashboard riêng gồm 3 tab: danh sách vé hôm nay, ca làm việc, và thống kê nhanh. Với khách hàng đến trực tiếp quầy không đặt online, hệ thống có màn hình Bán vé tại quầy cho phép nhân viên chọn suất chiếu, ghế và thanh toán ngay tại chỗ, dữ liệu vẫn đồng bộ chung với hệ thống đặt online để tránh trùng ghế. Ngoài ra, nhân viên chấm công ca làm bằng cách quét mã QR, giúp quản lý rạp theo dõi giờ làm chính xác."

## Slide 10: Vai trò Staff — Check-in & Bảo trì ghế
**Nội dung hiển thị:**
- Check-in vé: quét QR (xác thực chữ ký HMAC qua backend) hoặc nhập mã thủ công, ghi vào `checkin_audit_log`.
- `StaffSeatMaintenanceScreen`: báo cáo ghế hỏng, ghế dành cho xe lăn, gửi `incidents`.
- Chế độ **offline** khi mất mạng vẫn thao tác được, đồng bộ lại sau.

**Lời thoại:**
> "Khi khách đến rạp, nhân viên quét mã QR trên vé để check-in — hệ thống sẽ gửi yêu cầu xác thực chữ ký HMAC về backend để đảm bảo vé đó là thật, đồng thời ghi lại nhật ký check-in để tra soát sau này nếu cần. Một tính năng thực tế khác là màn hình Bảo trì ghế, nơi nhân viên có thể báo cáo ghế bị hỏng hoặc đánh dấu ghế dành riêng cho người khuyết tật, thông tin này sẽ tự động ẩn ghế đó khỏi sơ đồ đặt chỗ. Đặc biệt, các thao tác quan trọng như check-in vẫn hoạt động được ở chế độ offline khi mạng yếu, và tự đồng bộ lại dữ liệu khi có mạng trở lại — rất phù hợp với thực tế sảnh rạp đông người, sóng wifi chập chờn."

## Slide 11: Vai trò Theater Manager — Vận hành rạp
**Nội dung hiển thị:**
- `theater_manager_dashboard_screen.dart`: 4 tab — Suất chiếu / Vé & Doanh thu / Nhân viên / Voucher.
- `RoomManagementScreen`: cấu hình phòng chiếu, seat heatmap (bản đồ nhiệt ghế bán chạy).
- `TheaterAttendanceScreen` + **Smart Roster**: phân ca thông minh cho nhân viên.

**Lời thoại:**
> "Ở cấp cao hơn là Quản lý rạp — người chịu trách nhiệm vận hành toàn bộ một chi nhánh. Dashboard của họ có 4 tab: quản lý suất chiếu, theo dõi vé và doanh thu, quản lý nhân viên, và quản lý voucher riêng cho rạp đó. Trong phần quản lý phòng chiếu, có tính năng seat heatmap — bản đồ nhiệt hiển thị trực quan những khu vực ghế bán chạy nhất, giúp quản lý ra quyết định về giá hoặc bố trí phòng. Về nhân sự, hệ thống có tính năng Smart Roster hỗ trợ phân ca làm việc một cách thông minh dựa trên lịch chiếu và số lượng nhân viên sẵn có, cùng với màn hình theo dõi điểm danh của toàn bộ nhân viên rạp."

## Slide 12: Demo trực tiếp — Bán vé quầy & Check-in QR
**Nội dung hiển thị:**
- *(Demo live)* Nhân viên bán vé quầy cho khách vãng lai → sinh vé QR → chuyển sang màn hình check-in → quét mã → xác thực thành công.
- Nhấn mạnh: dữ liệu đồng bộ tức thời giữa vé bán quầy và vé đặt online trên cùng sơ đồ ghế.

**Lời thoại:**
> "Sau đây nhóm em xin demo trực tiếp luồng nghiệp vụ: đầu tiên là nhân viên bán một vé tại quầy cho khách vãng lai, hệ thống sinh vé QR ngay lập tức. Sau đó em chuyển sang màn hình check-in, quét chính mã QR vừa tạo để cho thấy hệ thống xác thực chữ ký thành công và ghi nhận khách đã vào rạp. Điều quan trọng cần lưu ý là ghế vừa bán tại quầy này ngay lập tức biến mất khỏi sơ đồ ghế trống bên phía ứng dụng khách hàng, chứng minh dữ liệu được đồng bộ real-time giữa hai luồng bán vé online và offline."
> *(Chuyển giao)* "Em xin mời bạn [Tên người 4] trình bày phần quản trị hệ thống ở cấp cao nhất."

---

# 🎤 NGƯỜI 4 — QUẢN TRỊ HỆ THỐNG: ADMIN / ACCOUNTANT / MARKETING & BẢO MẬT

## Slide 13: Admin Dashboard — Trung tâm điều khiển toàn hệ thống
**Nội dung hiển thị:**
- `AdminDashboardScreen`: 10 chức năng chính — quản lý phim, quản lý user & phân quyền, định dạng phòng chiếu, pricing rules, voucher, kiểm duyệt đánh giá, broadcast thông báo, duyệt xác minh tuổi, audit log, cấu hình server, báo cáo doanh thu.
- Cơ chế **RBAC** (Role-Based Access Control) dựa trên field `role` trong collection `users`.

**Lời thoại:**
> "Ở cấp cao nhất là Quản trị viên hệ thống, với dashboard tổng hợp 10 chức năng quản lý toàn diện. Toàn bộ hệ thống phân quyền dựa trên nguyên tắc RBAC — mỗi tài khoản trong Firestore có một trường 'role' xác định họ là user, staff, theater manager, accountant, marketing hay admin, và giao diện lẫn quyền truy cập dữ liệu đều tự động điều chỉnh theo vai trò đó. Điều đặc biệt là hai vai trò Kế toán và Marketing dùng chung giao diện AdminDashboardScreen nhưng menu được lọc riêng: Kế toán chỉ thấy phần báo cáo doanh thu, còn Marketing chỉ thấy voucher và gửi thông báo — tối ưu code mà vẫn tách bạch nghiệp vụ."

## Slide 14: Quản lý nội dung & Giá vé
**Nội dung hiển thị:**
- Quản lý phim: nhập liệu tự động qua **TMDB API**.
- Quản lý định dạng phòng chiếu (room formats) và **pricing rules** — quy tắc giá dùng chung giữa app và backend để đảm bảo giá luôn khớp.
- Cấu hình server động: seed dữ liệu, Gemini API key, tham số hệ thống.

**Lời thoại:**
> "Về quản lý nội dung, thay vì nhập tay từng bộ phim, quản trị viên có thể import trực tiếp dữ liệu phim từ TMDB — kho dữ liệu điện ảnh lớn nhất thế giới — chỉ với vài thao tác. Về giá vé, hệ thống có màn hình quản lý pricing rules cho phép admin thiết lập quy tắc tính giá theo định dạng phòng, khung giờ, ngày trong tuần... và quy tắc này được dùng chung bởi cả ứng dụng lẫn backend, đảm bảo giá hiển thị cho khách luôn khớp với giá backend tính khi thanh toán, tránh sai lệch giá dẫn đến tranh chấp. Ngoài ra còn có màn hình cấu hình server để quản trị các tham số hệ thống như khóa API của Gemini hay seed dữ liệu ban đầu."

## Slide 15: Kiểm duyệt & Truyền thông
**Nội dung hiển thị:**
- Duyệt yêu cầu **xác minh tuổi** (age_verification_requests) cho phim T18.
- Kiểm duyệt đánh giá phim (movie_reviews) — ẩn/xoá đánh giá vi phạm.
- **Broadcast thông báo** phân khúc khách hàng + đẩy qua FCM (`admin_broadcast_screen.dart`).
- Quản lý voucher toàn hệ thống.

**Lời thoại:**
> "Về mặt kiểm duyệt, admin là người xét duyệt các yêu cầu xác minh tuổi mà người dùng gửi lên khi muốn xem phim 18+, kiểm tra ảnh CCCD trước khi phê duyệt. Admin cũng kiểm duyệt các đánh giá phim từ người dùng để loại bỏ nội dung vi phạm. Về truyền thông, tính năng Broadcast cho phép gửi thông báo hàng loạt đến khách hàng theo từng phân khúc — ví dụ chỉ gửi cho khách VIP hoặc khách lâu chưa quay lại — và thông báo này được đẩy trực tiếp đến điện thoại qua Firebase Cloud Messaging. Song song đó là quản lý voucher khuyến mãi áp dụng toàn hệ thống."

## Slide 16: Bảo mật & Minh bạch dữ liệu
**Nội dung hiển thị:**
- `firestore.rules`: phân quyền thật ở tầng server, không phải chỉ ẩn UI.
- `admin_audit_log`: ghi lại mọi thao tác nhạy cảm của admin (ai làm gì, khi nào).
- Nguyên tắc **Authoritative pricing** & vé QR ký HMAC — nhắc lại điểm mấu chốt bảo mật xuyên suốt hệ thống.

**Lời thoại:**
> "Cuối cùng, về bảo mật — đây là điểm nhóm em đầu tư kỹ nhất. Toàn bộ quyền truy cập dữ liệu được kiểm soát bằng firestore.rules ở tầng server, nghĩa là dù ai đó có can thiệp vào ứng dụng client thì cũng không thể đọc hay ghi dữ liệu trái phép, vì Firebase sẽ chặn ngay ở server. Mọi hành động nhạy cảm của admin — như xoá user, đổi quyền, duyệt xác minh tuổi — đều được ghi vào audit log để có thể truy vết trách nhiệm. Kết hợp với nguyên tắc giá tiền luôn được backend tính lại lần cuối và vé QR được ký số HMAC mà em đã đề cập ở phần trước, có thể nói toàn bộ hệ thống được xây dựng theo tư duy 'không tin tưởng phía client' — một nguyên tắc bảo mật cốt lõi trong phát triển ứng dụng thực tế."
> *(Chuyển giao)* "Em xin mời bạn [Tên người 5] trình bày phần kỹ thuật nổi bật, khó khăn và tổng kết dự án."

---

# 🎤 NGƯỜI 5 — ĐIỂM KỸ THUẬT NỔI BẬT, KHÓ KHĂN, HƯỚNG PHÁT TRIỂN & KẾT LUẬN

## Slide 17: Điểm kỹ thuật nổi bật
**Nội dung hiển thị:**
- **Seat-locking bằng Firestore Transaction**: đảm bảo tính nhất quán khi nhiều người cùng đặt một ghế.
- **3 Cron jobs** ở backend: dọn vé PENDING treo, dynamic pricing, push quảng cáo định kỳ.
- Kiến trúc **module hoá MVVM** dễ mở rộng, mỗi feature độc lập (screens/viewmodels/repositories/services).
- Chế độ **offline-first** cho một số thao tác của nhân viên.

**Lời thoại:**
> "Em xin tổng kết những điểm kỹ thuật mà nhóm tâm đắc nhất. Thứ nhất là cơ chế khoá ghế bằng Firestore Transaction, đảm bảo tuyệt đối không có chuyện hai người đặt trùng một ghế cùng lúc, kể cả trong trường hợp hàng trăm người truy cập đồng thời. Thứ hai là ba tác vụ nền tự động chạy định kỳ ở backend, giúp hệ thống tự 'dọn dẹp' và vận hành mà không cần con người can thiệp thủ công. Thứ ba là kiến trúc module hoá theo mô hình MVVM, giúp 5 thành viên trong nhóm có thể làm việc song song trên các module khác nhau mà không giẫm chân lên nhau — đây cũng là lý do vì sao một hệ thống có nhiều vai trò và tính năng như thế này vẫn hoàn thành đúng tiến độ."

## Slide 18: Khó khăn gặp phải & Cách giải quyết
**Nội dung hiển thị:**
- Khó khăn 1: Đồng bộ giá vé giữa client và backend → Giải pháp: nguyên tắc authoritative pricing + collection `pricing_rules` dùng chung.
- Khó khăn 2: Tránh trùng ghế khi nhiều người đặt đồng thời → Giải pháp: Firestore transaction khoá ghế tạm thời.
- Khó khăn 3: Bảo mật vé điện tử, tránh giả mạo → Giải pháp: ký số HMAC ở backend.
- Khó khăn 4: Phối hợp 5 thành viên trên 1 codebase lớn → Giải pháp: chia module rõ ràng theo `lib/features/`.

**Lời thoại:**
> "Trong quá trình thực hiện, nhóm em gặp không ít khó khăn. Khó nhất là đảm bảo giá vé hiển thị cho khách luôn khớp với giá thực tính khi thanh toán, vì có nhiều yếu tố như combo, voucher, hạng thành viên cùng tác động — nhóm em giải quyết bằng cách đưa toàn bộ logic tính giá về một nguồn dữ liệu chung là pricing_rules và luôn để backend tính lại lần cuối. Khó khăn thứ hai là tránh đặt trùng ghế, được giải quyết bằng transaction. Thứ ba là đảm bảo vé điện tử không bị làm giả, nhóm em học và áp dụng chữ ký số HMAC dù trước đó chưa từng làm. Và cuối cùng, khó khăn về mặt làm việc nhóm — 5 người cùng code trên một dự án lớn — được giải quyết bằng cách chia module độc lập ngay từ đầu, hạn chế xung đột code."

## Slide 19: Hướng phát triển tương lai
**Nội dung hiển thị:**
- Đa nền tảng: hoàn thiện bản iOS/Web.
- Rich notifications: kèm poster phim/QR vé ngay trên thanh thông báo.
- Gợi ý phim cá nhân hoá bằng AI dựa trên lịch sử xem.
- Geo-fencing: nhắc lịch chiếu khi khách ở gần rạp.
- Mở rộng thanh toán: thêm ví điện tử khác (Momo, ZaloPay...).

**Lời thoại:**
> "Về hướng phát triển trong tương lai, nhóm em dự định hoàn thiện thêm bản iOS và Web để tiếp cận nhiều người dùng hơn. Về trải nghiệm, nhóm muốn nâng cấp thông báo đẩy để hiển thị trực tiếp poster phim hoặc mã QR vé ngay trên thanh thông báo mà không cần mở app. Nhóm cũng dự kiến tận dụng dữ liệu lịch sử xem phim để gợi ý phim cá nhân hoá bằng AI, và tích hợp thêm tính năng nhắc lịch theo vị trí địa lý khi khách ở gần rạp. Về thanh toán, nhóm sẽ mở rộng thêm các ví điện tử phổ biến khác ngoài PayOS để tăng sự tiện lợi cho khách hàng."

## Slide 20: Tổng kết & Cảm ơn
**Nội dung hiển thị:**
- Kết quả đạt được: hệ thống hoàn chỉnh 6 vai trò, từ đặt vé đến vận hành và quản trị, có bảo mật thực chiến.
- Bài học rút ra: thiết kế kiến trúc từ đầu quan trọng hơn code nhanh; bảo mật phải nghĩ từ tầng dữ liệu chứ không chỉ giao diện.
- Lời cảm ơn thầy/cô và các bạn.
- Mời đặt câu hỏi (Q&A).

**Lời thoại:**
> "Tóm lại, qua đồ án này, nhóm em đã xây dựng thành công một hệ thống đặt vé xem phim hoàn chỉnh với 6 vai trò người dùng khác nhau, bao phủ toàn bộ nghiệp vụ từ đặt vé, vận hành rạp, cho đến quản trị hệ thống, đồng thời áp dụng các nguyên tắc bảo mật thực chiến như transaction, chữ ký số và phân quyền tầng server. Bài học lớn nhất nhóm em rút ra là việc thiết kế kiến trúc và phân quyền ngay từ đầu quan trọng hơn nhiều so với việc code nhanh nhưng thiếu định hướng, và bảo mật cần được nghĩ tới từ tầng dữ liệu chứ không chỉ ở giao diện người dùng. Nhóm em xin chân thành cảm ơn thầy/cô và các bạn đã lắng nghe. Nhóm em xin phép nhận câu hỏi và góp ý ạ."

---

## 📋 GHI CHÚ PHÂN CÔNG NHANH

| Người | Vai trò trình bày | Slide | Thời lượng |
|---|---|---|---|
| 1 | Mở đầu, vấn đề, kiến trúc | 1–4 | ~4 phút |
| 2 | Trải nghiệm người dùng (User) | 5–8 | ~4 phút |
| 3 | Vận hành: Staff & Theater Manager | 9–12 | ~4 phút |
| 4 | Quản trị: Admin/Accountant/Marketing & Bảo mật | 13–16 | ~4 phút |
| 5 | Kỹ thuật nổi bật, khó khăn, hướng phát triển, kết luận | 17–20 | ~4 phút |

**Lưu ý khi luyện tập:**
- Mỗi người nên tự demo trực tiếp phần mình phụ trách trên app thật (không chỉ nói chay) — đặc biệt slide 8 và slide 12.
- Câu chuyển giao cuối mỗi phần đã viết sẵn — luyện tập nói mượt để buổi thuyết trình liền mạch.
- Chuẩn bị trước 3–5 câu hỏi phản biện thường gặp: "Vì sao tách backend riêng thay vì để Cloud Functions?", "Cơ chế chống trùng ghế hoạt động thế nào khi mất mạng giữa chừng?", "Vé QR bị lộ ảnh chụp thì có bị giả mạo không?"
