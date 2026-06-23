import 'package:flutter_local_notifications/flutter_local_notifications.dart' as fln;

class LocalNotificationService {
  static final fln.FlutterLocalNotificationsPlugin _notificationsPlugin = fln.FlutterLocalNotificationsPlugin();

  // FIX TRIỆT ĐỂ: Gán chính xác tham số đặt tên 'settings:' theo đúng yêu cầu của thư viện
  static void initialize() {
    const fln.AndroidInitializationSettings initializationSettingsAndroid =
    fln.AndroidInitializationSettings('@mipmap/ic_launcher');

    const fln.InitializationSettings initializationSettings = fln.InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: null,
    );

    // ĐÃ SỬA: Truyền đúng cấu trúc settings: initializationSettings
    _notificationsPlugin.initialize(settings: initializationSettings);
  }

  // Hàm đẩy thông báo Popup thả từ trên đỉnh màn hình điện thoại xuống
  static void showNotificationPopup({required String title, required String body}) async {
    const fln.AndroidNotificationDetails androidPlatformChannelSpecifics = fln.AndroidNotificationDetails(
      'stella_cinema_channel_2026',
      'Stella Cinema Premium Notifications',
      channelDescription: 'Hệ thống thông báo rạp phim Stella Cinema',
      importance: fln.Importance.max,
      priority: fln.Priority.high,
      playSound: true,
    );

    const fln.NotificationDetails notificationDetails = fln.NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: null,
    );

    // Luồng hiển thị thông báo với các tham số gán tên chuẩn chỉnh
    await _notificationsPlugin.show(
      id: DateTime.now().millisecond % 100000,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
    );
  }
}