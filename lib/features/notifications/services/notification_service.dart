import 'dart:developer';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  // Tạo instance của Firebase Messaging
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  Future<void> initNotifications() async {
    // 1. Xin quyền hiển thị thông báo (Bắt buộc từ Android 13 trở lên)
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      log('Tuyệt vời: Người dùng đã cấp quyền thông báo!');
    } else {
      log('Chú ý: Người dùng từ chối cấp quyền thông báo.');
    }

    // 2. Lấy FCM Token (Mã định danh duy nhất của cái điện thoại này)
    try {
      String? token = await _fcm.getToken();
      log("================== FCM TOKEN CỦA BẠN ĐÂY ==================");
      log(token ?? "Không lấy được mã token");
      log("==========================================================");
    } catch (e) {
      log("Lỗi khi lấy token: $e");
    }

    // 3. Lắng nghe thông báo khi ứng dụng ĐANG MỞ (Foreground)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      log('Có thông báo tới khi đang mở app: ${message.notification?.title}');
      log('Nội dung: ${message.notification?.body}');
      // Lưu ý: Mặc định khi đang mở app, thông báo sẽ không hiện pop-up (banner) rớt từ trên xuống.
      // Chúng ta sẽ cần thư viện flutter_local_notifications nếu muốn ép nó hiện thị,
      // nhưng tạm thời cứ log ra để biết nó hoạt động đã.
    });

    // 4. Lắng nghe hành vi người dùng BẤM VÀO THÔNG BÁO (Từ background hoặc khi tắt app)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      log('Người dùng vừa bấm vào thông báo: ${message.notification?.title}');
    });
  }
}