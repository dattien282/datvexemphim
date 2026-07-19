import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/home/screens/home_screen.dart';
import 'features/splash/screens/splash_screen.dart';
import 'features/admin/screens/admin_dashboard_screen.dart';
import 'features/staff/screens/staff_dashboard_screen.dart';
import 'features/theater_manager/screens/theater_manager_dashboard_screen.dart';
import 'features/notifications/screens/notification_service.dart';
import 'features/notifications/services/notification_router.dart';
import 'providers/user_provider.dart';
import 'providers/room_formats_provider.dart';
import 'models/room_layout.dart' show updateRoomFormatCache;
import 'core/widgets/global_internet_check_widget.dart';

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

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: NotificationRouter.navigatorKey,
      title: 'Stella Cinema',
      debugShowCheckedModeBanner: false, // tắt dải "DEBUG" đỏ ở góc màn hình
      theme: ThemeData.dark(),
      builder: (context, child) {
        return Stack(
          children: [
            child!,
            const GlobalInternetCheckWidget(),
          ],
        );
      },
      home: const SplashScreen(next: MainAppWrapper()),
    );
  }
}

class MainAppWrapper extends ConsumerStatefulWidget {
  const MainAppWrapper({super.key});

  @override
  ConsumerState<MainAppWrapper> createState() => _MainAppWrapperState();
}

class _MainAppWrapperState extends ConsumerState<MainAppWrapper> {
  ProviderSubscription? _roomFormatsSub;

  @override
  void initState() {
    super.initState();
    // Kích hoạt ngầm cấu hình thông báo đẩy (FCM & Local Popup) mà không gây nghẽn giao diện khởi động
    _setupPushNotifications();
    _checkCurrentUser();
    // Đồng bộ cache đồng bộ (models/room_layout.dart) từ collection Firestore
    // 'room_formats' trong suốt vòng đời app - đây là ĐIỂM DUY NHẤT app lắng
    // nghe stream này, để 25+ nơi gọi findRoomFormatSpec/roomFormatColor/...
    // ở khắp app đọc được đồng bộ mà không cần tự watch provider. Dùng
    // listenManual (thay vì ref.listen trong build) vì cần chạy 1 lần cho cả
    // vòng đời widget gốc, không phụ thuộc rebuild - phải tự đóng ở dispose().
    _roomFormatsSub = ref.listenManual(roomFormatsProvider, (previous, next) {
      next.whenData(updateRoomFormatCache);
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _roomFormatsSub?.close();
    super.dispose();
  }

  void _checkCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _navigateByRole(user.uid);
      });
    }
  }

  Future<void> _navigateByRole(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data() ?? {};
      final role = data['role'] as String? ?? 'user';
      final isAdmin = data['isAdmin'] == true;

      if (!mounted) return;

      Widget destination;
      if (isAdmin || role == 'admin') {
        destination = const AdminDashboardScreen();
      } else if (role == 'theater_manager') {
        final profile = UserProfile.fromMap(uid, data);
        destination = TheaterManagerDashboardScreen(managerProfile: profile);
      } else if (role == 'staff') {
        final profile = UserProfile.fromMap(uid, data);
        destination = StaffDashboardScreen(staffProfile: profile);
      } else {
        destination = const HomeScreen();
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => destination),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
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

      // 6. Bấm vào thông báo khi app đang chạy nền (background) - mở đúng
      // màn hình ưu đãi/phim theo field 'type' trong data payload (xem
      // NotificationRouter). Trước đây chỉ log ra console, không mở gì cả.
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        NotificationRouter.handleTap(message.data);
      });

      // 7. Bấm vào thông báo khi app ĐÃ TẮT HẲN (không có process nào chạy) -
      // onMessageOpenedApp ở trên KHÔNG bắt được trường hợp này, phải hỏi
      // riêng getInitialMessage() lúc khởi động.
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        NotificationRouter.handleTap(initialMessage.data);
      }
    } catch (e) {
      print("Lỗi thiết lập thông báo đẩy: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // Bỏ màn "Chào mừng" trung gian - vào thẳng màn Đăng nhập/Đăng ký.
    // MainAppWrapper vẫn giữ vai trò chạy các side-effect lúc khởi động
    // (đăng ký push notification, force sign-out) ở initState phía trên.
    return const LoginScreen();
  }
}




