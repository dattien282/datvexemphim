# SLIDE THUYẾT TRÌNH: BÁO CÁO PHÂN KHÚC DỰ ÁN - MODULE 5: NOTIFICATIONS SCREEN & SERVICES

Tài liệu này được biên soạn chi tiết nhằm phục vụ buổi thuyết trình về module thông báo của dự án **Stella Cinema (Ứng dụng đặt vé xem phim nhóm 5)**. Mỗi slide bao gồm nội dung hiển thị trên bảng chiếu và kịch bản nói (Speaker Notes) chi tiết để bạn tự tin thuyết trình trước giảng viên và hội đồng.

---

## Slide 1: Trang bìa giới thiệu (Title Slide)
* **Tiêu đề Slide:** DỰ ÁN STELLA CINEMA - HỆ THỐNG THÔNG BÁO THỜI GIAN THỰC & ĐẨY CỤC BỘ (REAL-TIME & LOCAL PUSH NOTIFICATIONS)
* **Nội dung hiển thị:**
  * Ứng dụng đặt vé xem phim Stella Cinema - PRM393
  * **Module báo cáo:** Phần 5 - Notifications Screen & Services (Trung tâm thông báo & Dịch vụ thông báo đẩy)
  * **Nhóm thực hiện:** Nhóm 5
  * **Công nghệ cốt lõi:** Flutter, Firebase Messaging, Cloud Firestore, Flutter Local Notifications.
* **Lời thoại thuyết trình (Speaker Notes):**
  > *"Kính chào thầy và các bạn. Hôm nay, đại diện cho Nhóm 5, em xin phép được trình bày phần báo cáo tiến độ và demo chức năng thuộc Module 5 của ứng dụng Stella Cinema. Đây là module về Hệ thống Thông báo thời gian thực kết hợp với Thông báo đẩy trên thiết bị di động. Phần này đóng vai trò quan trọng trong việc giữ tương tác, nhắc nhở lịch chiếu và gửi biên lai giao dịch cho khách hàng. Sau đây, em xin phép bắt đầu buổi thuyết trình."*

---

## Slide 2: Tổng quan dự án & Vai trò của các thành viên (Project Overview & Team Roles)
* **Tiêu đề Slide:** TỔNG QUAN PHẦN VIỆC CỦA TEAM & VAI TRÒ THÀNH VIÊN
* **Nội dung hiển thị:**
  * **Tổng quan dự án:** Ứng dụng đặt vé xem phim Stella Cinema gồm các module:
    1. Trang chủ & Danh sách phim đang chiếu/sắp chiếu (Home & Movies)
    2. Đặt vé, chọn ghế, chọn bắp nước Combo (Booking & Seats)
    3. Áp dụng mã giảm giá và Thanh toán ví ảo (Voucher & Payment)
    4. Bản đồ định vị rạp chiếu phim (Google Maps Integration)
    5. **Hệ thống thông báo đẩy & Trung tâm thông báo (Notifications Center)**
  * **Phân công công việc:** Cả team cùng phối hợp thiết kế UI và kết nối cơ sở dữ liệu. Phần nộp báo cáo sớm lần này tập trung hoàn thiện và tối ưu hóa trước **Phần 5: Notifications Screen** làm nền tảng kiểm thử.
* **Lời thoại thuyết trình (Speaker Notes):**
  > *"Trước khi đi sâu vào Module 5, em xin giới thiệu sơ qua về tổng thể dự án. Ứng dụng Stella Cinema của nhóm chúng em hỗ trợ người dùng từ việc duyệt phim, giữ ghế, mua combo bắp nước, áp mã voucher, thanh toán qua ví ảo, cho đến việc xem bản đồ định vị rạp và nhận thông báo. Trong báo cáo tiến độ đợt này, do yêu cầu nộp trước phần 5 nên nhóm chúng em đã tập trung xây dựng hoàn chỉnh và chạy thử nghiệm thành công toàn bộ luồng thông báo của ứng dụng để chứng minh khả năng kết nối Firebase và tương tác trên thiết bị di động."*

---

## Slide 3: Đặt vấn đề & Mục tiêu giải pháp (The Problem & The Solution)
* **Tiêu đề Slide:** ĐẶT VẤN ĐỀ VÀ MỤC TIÊU CỦA MODULE NOTIFICATIONS
* **Nội dung hiển thị:**
  * **Vấn đề đặt ra:**
    * Làm sao để khách hàng không quên lịch chiếu phim đã đặt?
    * Làm sao xác nhận giao dịch thanh toán thành công tức thời mà không cần reload trang?
    * Làm sao để quản trị viên có thể gửi tin tức khuyến mãi đến toàn bộ người dùng?
  * **Mục tiêu giải pháp:**
    * Xây dựng **Trung tâm Thông báo** gom nhóm thông báo khoa học (Tất cả, Giao dịch, Hệ thống).
    * Thiết lập **Thông báo đẩy (Push Notifications)** nổi lên màn hình thiết bị ngay cả khi app đang chạy ngầm hoặc tắt.
    * Đồng bộ thời gian thực từ Database về giao diện người dùng.
* **Lời thoại thuyết trình (Speaker Notes):**
  > *"Trong các ứng dụng di động hiện đại, đặc biệt là ứng dụng đặt vé dịch vụ, trải nghiệm thông báo là cực kỳ quan trọng. Khách hàng khi mua vé xong cần nhận được xác nhận ngay lập tức để yên tâm. Ngoài ra, việc nhắc lịch chiếu trước giờ phim bắt đầu giúp họ không bị trễ giờ. Vì thế, mục tiêu của nhóm em là xây dựng một kiến trúc thông báo toàn diện: vừa đồng bộ dữ liệu thời gian thực lên màn hình Trung tâm thông báo, vừa đẩy pop-up thông báo hiển thị trực quan từ khay hệ thống của điện thoại."*

---

## Slide 4: Cơ chế & Cách hoạt động (Underlying Mechanism)
* **Tiêu đề Slide:** CƠ CHẾ VÀ KIẾN TRÚC HOẠT ĐỘNG
* **Nội dung hiển thị:**
  * Vẽ sơ đồ luồng hoạt động bằng 3 trụ cột chính:
    1. **Cloud Firestore StreamBuilder:** Lắng nghe real-time collection `user_notifications`. Khi database thay đổi, giao diện tự động vẽ lại danh sách thông báo mà không cần gọi API.
    2. **Flutter Local Notifications Plugin:** Khởi chạy các thông báo cục bộ ngay trên thiết bị. Dùng để giả lập nhắc lịch chiếu sau 5 giây kể từ khi đặt vé thành công hoặc hiển thị banner khi đang mở ứng dụng.
    3. **Firebase Cloud Messaging (FCM):** Lấy FCM Token định danh thiết bị. Sẵn sàng nhận các thông báo từ Firebase Console gửi xuống điện thoại khi ứng dụng chạy ngầm (Background) hoặc tắt (Terminated).
* **Lời thoại thuyết trình (Speaker Notes):**
  > *"Để hiện thực hóa điều đó, chúng em kết hợp 3 cơ chế công nghệ lớn trên nền tảng Flutter. Thứ nhất là Firestore StreamBuilder, tạo ra luồng kết nối liên tục đến cơ sở dữ liệu Cloud Firestore, giúp cập nhật thông tin ngay lập tức khi admin gửi tin nhắn hoặc khi người dùng mua vé. Thứ hai là Flutter Local Notifications, chịu trách nhiệm vẽ các banner thông báo thả từ trên đỉnh màn hình xuống. Thứ ba là Firebase Cloud Messaging, giúp hệ thống đăng ký FCM Token duy nhất cho mỗi điện thoại để nhận thông báo đẩy từ xa của máy chủ."*

---

## Slide 5: Chi tiết thiết kế giao diện & Tương tác (UI/UX Design)
* **Tiêu đề Slide:** THIẾT KẾ GIAO DIỆN & TRẢI NGHIỆM TƯƠNG TÁC
* **Nội dung hiển thị:**
  * **Giao diện tối (Dark Theme):** Màu nền đen xám `#0F0F13` và `#16161F`, phối màu chữ vàng hổ phách (Amber) sang trọng đồng bộ thương hiệu rạp phim.
  * **Phân loại Tab thông minh:**
    * *Tất cả:* Hiển thị toàn bộ thông báo.
    * *Giao dịch:* Lọc các thông báo mua vé (Icon vé vàng).
    * *Hệ thống:* Lọc các tin tức từ rạp (Icon chuông xanh).
  * **Tương tác Micro-animations:**
    * Nhấp để đọc thông báo: Tự động cập nhật `isRead: true` lên Firestore, làm mờ thẻ và ẩn dấu chấm vàng unread.
    * Vuốt sang trái để xóa (Swipe-to-delete): Sử dụng widget `Dismissible` có animation rút thẻ mượt mà, đồng thời xóa dữ liệu trên Firestore.
    * Hiệu ứng trượt danh sách: Sử dụng `TweenAnimationBuilder` để danh sách hiện ra trượt nhẹ từ phải qua trái.
* **Lời thoại thuyết trình (Speaker Notes):**
  > *"Giao diện Trung tâm Thông báo được nhóm chúng em thiết kế theo phong cách rạp chiếu phim cao cấp với tone màu tối làm nền và màu vàng Amber làm điểm nhấn. Người dùng dễ dàng chuyển đổi giữa các tab để lọc thông báo giao dịch hoặc hệ thống. Chúng em cũng chú trọng đến các tương tác nhỏ nhưng tăng trải nghiệm người dùng như: hiệu ứng chuyển động trượt khi mở danh sách, việc chạm vào để đánh dấu đã đọc, và đặc biệt là tính năng vuốt sang trái để xóa thông báo khỏi màn hình kèm theo hiệu ứng xóa dữ liệu tức thời trên server."*

---

## Slide 6: Kịch bản Demo dự án (Interactive Demo Flow)
* **Tiêu đề Slide:** KỊCH BẢN DEMO THỰC TẾ TRÊN ỨNG DỤNG
* **Nội dung hiển thị:**
  * **Bước 1: Khởi động app & Cấp quyền:** Ứng dụng hỏi xin quyền thông báo trên thiết bị Android 13+. In ra FCM Token trong console log.
  * **Bước 2: Mua vé & Thanh toán:** Người dùng tiến hành đặt vé phim thành công.
  * **Bước 3: Nhận thông báo tự động:**
    * Một tài liệu thông báo dạng `ticket` được chèn vào Firestore.
    * Sau 5 giây, một banner cục bộ nổi lên đỉnh màn hình cảnh báo nhắc lịch chiếu phim.
  * **Bước 4: Trải nghiệm tại Trung tâm Thông báo:**
    * Người dùng vào Trung tâm Thông báo, kiểm tra bộ lọc tab.
    * Thực hiện thao tác chạm để đọc thông báo, vuốt để xóa, và nút "Xóa tất cả" để dọn sạch hộp thư.
* **Lời thoại thuyết trình (Speaker Notes):**
  > *"Sau đây, chúng em xin trình bày kịch bản chạy thử nghiệm (demo) trực tiếp của module này. Đầu tiên khi mở app, hệ thống sẽ yêu cầu cấp quyền thông báo và log ra mã token định danh. Tiếp theo, chúng em sẽ mô phỏng việc đặt vé thành công. Ngay khi giao dịch hoàn tất, hệ thống tự động ghi nhận thông báo vào cơ sở dữ liệu. Đồng thời, sau 5 giây, một thông báo nhắc lịch chiếu sẽ tự động nhảy ra từ khay hệ thống của điện thoại để giả lập nhắc nhở người dùng. Cuối cùng, chúng em sẽ mở màn hình Trung tâm thông báo để trình diễn các chức năng lọc tab, vuốt để xóa và xóa tất cả."*

---

## Slide 7: Đề xuất cải tiến nâng cao cho dự án (Proposed Enhancements)
* **Tiêu đề Slide:** ĐỀ XUẤT CẢI TIẾN THÊM CHO ỨNG DỤNG (BEYOND MVP)
* **Nội dung hiển thị:**
  * **1. Rich Notifications (Thông báo đa phương tiện):**
    * Gửi kèm ảnh poster phim hoặc mã QR Code vé trực tiếp trên thanh thông báo hệ thống để người dùng quét vào rạp nhanh không cần mở app.
  * **2. Interactive Notification Actions (Hành động nhanh):**
    * Tích hợp nút bấm ngay trên banner thông báo thả xuống (Ví dụ: [Xem vé] hoặc [Dẫn đường đến rạp]).
  * **3. Geo-fencing Notifications (Thông báo theo vị trí địa lý):**
    * Kết hợp với GPS, khi người dùng đi vào phạm vi 500m gần rạp chiếu phim vào ngày có lịch chiếu, ứng dụng tự động nhắc nhở chuẩn bị soát vé.
  * **4. Preference Settings (Tùy chỉnh cá nhân hóa):**
    * Cho phép người dùng lựa chọn chỉ nhận thông báo giao dịch, tắt thông báo khuyến mãi để tránh bị làm phiền.
* **Lời thoại thuyết trình (Speaker Notes):**
  > *"Bên cạnh các tính năng cơ bản đã chạy tốt, nhóm chúng em đề xuất thêm 4 hướng cải tiến nâng cao để ứng dụng tiệm cận sản phẩm thương mại thực tế. Thứ nhất là Rich Notifications giúp hiển thị poster phim hay mã QR vé ngay trên thanh trạng thái của điện thoại. Thứ hai là gắn các nút tương tác nhanh để người dùng không cần mở app vẫn tương tác được. Thứ ba là Geo-fencing, sử dụng định vị GPS để nhắc nhở khi khách hàng di chuyển đến gần rạp. Và cuối cùng là trang cài đặt cho phép người dùng tùy chọn bật tắt các luồng thông báo theo nhu cầu cá nhân."*

---

## Slide 8: Tổng kết & Câu hỏi thảo luận (Q&A)
* **Tiêu đề Slide:** TỔNG KẾT & CÂU HỎI THẢO LUẬN
* **Nội dung hiển thị:**
  * **Kết quả đạt được:**
    * Hoàn thành đầy đủ logic kết nối thông báo thời gian thực & thông báo đẩy.
    * Giao diện mượt mà, tối ưu hóa trải nghiệm người dùng di động.
    * Viết tài liệu hướng dẫn Lab 5 chi tiết giúp các thành viên khác dễ dàng tích hợp.
  * **Xin ý kiến đóng góp:** Cảm ơn thầy và các bạn đã lắng nghe!
* **Lời thoại thuyết trình (Speaker Notes):**
  > *"Tóm lại, Module 5 đã được xây dựng hoàn chỉnh cả về phần xử lý logic dịch vụ lẫn giao diện người dùng trực quan. Nhóm em cũng đã đóng gói toàn bộ quy trình này thành file tài liệu hướng dẫn Lab 5 chi tiết để các nhóm khác hoặc các thành viên tiếp theo có thể dễ dàng hoàn thành và sử dụng được tính năng này. Em xin chân thành cảm ơn thầy và các bạn đã chú ý theo dõi. Rất mong nhận được những ý kiến đóng góp và câu hỏi từ thầy và các bạn để nhóm hoàn thiện dự án tốt hơn!"*
