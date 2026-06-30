import 'dart:io';
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/home/screens/home_screen.dart';
import 'features/admin/screens/admin_dashboard_screen.dart';
import 'features/staff/screens/staff_dashboard_screen.dart';
import 'features/theater_manager/screens/theater_manager_dashboard_screen.dart';
import 'features/notifications/screens/notification_service.dart';
import 'providers/user_provider.dart';

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
              const SizedBox(height: 32),
              const _DemoAccountSeeder(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Demo account seeder ────────────────────────────────────────────────────────
class _DemoAccountSeeder extends StatefulWidget {
  const _DemoAccountSeeder();

  @override
  State<_DemoAccountSeeder> createState() => _DemoAccountSeederState();
}

class _DemoAccountSeederState extends State<_DemoAccountSeeder> {
  bool _loading = false;

  static const _accounts = [
    {
      'email': 'admin@stellacinema.com',
      'password': 'Admin@123456',
      'displayName': 'Admin Stella',
      'role': 'admin',
      'isAdmin': true,
      'label': 'ADMIN',
      'color': 0xFFFFBF00,
    },
    {
      'email': 'manager@stellacinema.com',
      'password': 'Manager@123456',
      'displayName': 'Quản lý HCM',
      'role': 'theater_manager',
      'isAdmin': false,
      'assignedTheater': 'Stella Cinema – Hồ Chí Minh',
      'label': 'MANAGER',
      'color': 0xFF7C4DFF,
    },
    {
      'email': 'staff@stellacinema.com',
      'password': 'Staff@123456',
      'displayName': 'Nhân viên Stella',
      'role': 'staff',
      'isAdmin': false,
      'assignedTheater': 'Stella Cinema – Hồ Chí Minh',
      'label': 'STAFF',
      'color': 0xFF00BFA5,
    },
  ];

  Future<void> _seedAccounts() async {
    setState(() => _loading = true);
    final results = <String>[];

    for (final acc in _accounts) {
      try {
        UserCredential cred;
        try {
          cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: acc['email'] as String,
            password: acc['password'] as String,
          );
        } on FirebaseAuthException catch (e) {
          if (e.code == 'email-already-in-use') {
            // Account exists → just ensure Firestore doc is correct
            cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
              email: acc['email'] as String,
              password: acc['password'] as String,
            );
          } else {
            results.add('${acc['label']}: lỗi ${e.message}');
            continue;
          }
        }

        final uid = cred.user!.uid;
        final data = <String, dynamic>{
          'email': acc['email'],
          'displayName': acc['displayName'],
          'role': acc['role'],
          'isAdmin': acc['isAdmin'],
          'wallet_balance': 500000,
          'created_at': Timestamp.now(),
        };
        if (acc.containsKey('assignedTheater')) {
          data['assignedTheater'] = acc['assignedTheater'];
        }
        await FirebaseFirestore.instance.collection('users').doc(uid).set(data, SetOptions(merge: true));
        await FirebaseAuth.instance.signOut();
        results.add('${acc['label']}: OK');
      } catch (e) {
        results.add('${acc['label']}: lỗi $e');
      }
    }

    setState(() => _loading = false);
    if (!mounted) return;
    _showResult(results);
  }

  void _showResult(List<String> results) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('KẾT QUẢ TẠO TÀI KHOẢN',
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._accounts.map((acc) {
              final color = Color(acc['color'] as int);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                          child: Text(acc['label'] as String,
                              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      _credRow('Email:', acc['email'] as String),
                      _credRow('Mật khẩu:', acc['password'] as String),
                      if (acc.containsKey('assignedTheater'))
                        _credRow('Rạp:', (acc['assignedTheater'] as String).replaceFirst('Stella Cinema – ', '')),
                    ],
                  ),
                ),
              );
            }),
            const Divider(color: Colors.white12),
            ...results.map((r) => Text(r,
                style: TextStyle(
                    color: r.contains('OK') ? Colors.greenAccent : Colors.redAccent,
                    fontSize: 11))),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: const Text('ĐÓNG', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _credRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Text('$label ', style: const TextStyle(color: Colors.white38, fontSize: 11)),
          Flexible(
            child: Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Row(
          children: [
            Expanded(child: Divider(color: Colors.white12)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text('DEMO / TEST', style: TextStyle(color: Colors.white24, fontSize: 10)),
            ),
            Expanded(child: Divider(color: Colors.white12)),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            onPressed: _loading ? null : _seedAccounts,
            icon: _loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38))
                : const Icon(Icons.group_add_rounded, color: Colors.white54, size: 18),
            label: Text(
              _loading ? 'Đang tạo tài khoản...' : 'Tạo tài khoản Admin / Manager / Staff',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
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