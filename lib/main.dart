import 'dart:io';
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/home/screens/home_screen.dart';
import 'features/notifications/screens/notification_service.dart';

// ✅ 1. HÀM XỬ LÝ BACKGROUND KHI TẮT APP
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Nhận thông báo chạy ngầm: ${message.notification?.title}");
}

void main() async {
  // Thần chú chống treo logo bắt buộc khi chạy APK độc lập
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: "AIzaSyDcgvqlf94qhJD0-W-dNrtN1BVkw2gFaLY",
          appId: "1:112033693184:android:7459f37fc856c7a600a2e5",
          messagingSenderId: "112033693184",
          projectId: "datvexemphimgroup5",
          storageBucket: "datvexemphimgroup5.firebasestorage.app",
        ),
      );
    }
  } catch (e) {
    print('Firebase đã được khởi tạo trước đó hoặc lỗi seed: $e');
  }

  // Đăng ký nhận thông báo chạy ngầm khi tắt app
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stella Cinema',
      theme: ThemeData.dark(),
      builder: (context, child) {
        return Stack(
          children: [
            child!,
            const GlobalInternetCheckWidget(),
          ],
        );
      },
      home: const MainAppWrapper(),
    );
  }
}

class MainAppWrapper extends StatefulWidget {
  const MainAppWrapper({super.key});

  @override
  State<MainAppWrapper> createState() => _MainAppWrapperState();
}

class _MainAppWrapperState extends State<MainAppWrapper> {
  @override
  void initState() {
    super.initState();
    // Kích hoạt ngầm cấu hình thông báo đẩy (FCM & Local Popup) mà không gây nghẽn giao diện khởi động
    _setupPushNotifications();
    _checkCurrentUser();
  }

  void _checkCurrentUser() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      });
    }
  }

  Future<void> _setupPushNotifications() async {
    try {
      // 1. Kích hoạt dịch vụ thông báo đẩy cục bộ v22 (Named parameters)
      LocalNotificationService.initialize();

      // 2. Xin quyền thông báo đẩy
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // 3. Ép cấu hình hiển thị banner cảnh báo khi app chạy ở Foreground
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 4. Lắng nghe thông báo khi app đang mở ở Foreground để tự động show banner popup nổi
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print("Nhận thông báo nổi (Foreground): ${message.notification?.title}");
        if (message.notification != null) {
          LocalNotificationService.showNotificationPopup(
            title: message.notification!.title ?? 'Thông báo mới',
            body: message.notification!.body ?? '',
          );
        }
      });

      // 5. Lấy FCM Token để kiểm tra kết nối nếu cần
      String? token = await messaging.getToken();
      print("FCM TOKEN CHÍNH CHỦ: $token");
    } catch (e) {
      print("Lỗi thiết lập thông báo đẩy: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Chào mừng bạn đến với Stella Cinema!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.amber),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('ĐĂNG NHẬP HỆ THỐNG', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const HomeScreen()),
                  );
                },
                child: const Text(
                  'Bỏ qua đăng nhập (Xem trực tiếp rạp phim)',
                  style: TextStyle(color: Colors.white70, fontSize: 14, decoration: TextDecoration.underline),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GlobalInternetCheckWidget extends StatefulWidget {
  const GlobalInternetCheckWidget({super.key});

  @override
  State<GlobalInternetCheckWidget> createState() => _GlobalInternetCheckWidgetState();
}

class _GlobalInternetCheckWidgetState extends State<GlobalInternetCheckWidget> {
  bool _hasInternet = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkConnection();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _checkConnection());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 3));
      final connected = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      if (mounted && _hasInternet != connected) {
        setState(() {
          _hasInternet = connected;
        });
      }
    } catch (_) {
      if (mounted && _hasInternet) {
        setState(() {
          _hasInternet = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasInternet) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.redAccent.withOpacity(0.95),
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: const Material(
            color: Colors.transparent,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text(
                  'Mất kết nối Internet! Đang kiểm tra lại...',
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}