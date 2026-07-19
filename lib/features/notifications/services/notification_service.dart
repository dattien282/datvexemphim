import 'dart:developer';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

    // 2. Lấy FCM Token và lưu vào Firestore - trước đây token chỉ log ra
    // console rồi bỏ, chưa từng được lưu lại nên server không có cách nào
    // gửi push notification tới đúng máy của user (tính năng coi như không
    // hoạt động dù đã xin quyền/khởi tạo FCM).
    await _saveTokenForCurrentUser();
    // Token có thể đổi (cài lại app, xoá dữ liệu...) - lắng nghe để cập nhật.
    _fcm.onTokenRefresh.listen((_) => _saveTokenForCurrentUser());

    // Lắng nghe foreground message + xử lý bấm vào thông báo (onMessage,
    // onMessageOpenedApp, getInitialMessage) đã chuyển hết sang main.dart
    // (_setupPushNotifications, NotificationRouter) - trước đây bị đăng ký
    // TRÙNG Ở CẢ 2 NƠI (main.dart lẫn file này), khiến 1 lần bấm vào thông
    // báo có nguy cơ điều hướng 2 lần. Class này giờ chỉ còn giữ đúng 1 việc:
    // xin quyền + lưu FCM token.
  }

  Future<void> _saveTokenForCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final token = await _fcm.getToken();
      if (token == null) return;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'fcmToken': token,
        'fcmTokenUpdatedAt': Timestamp.now(),
      });
      log('Đã lưu FCM token cho user ${user.uid}');
    } catch (e) {
      log('Lỗi khi lưu FCM token: $e');
    }
  }
}
