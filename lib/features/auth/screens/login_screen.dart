import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../../home/screens/home_screen.dart';
import '../../admin/screens/admin_dashboard_screen.dart';
import '../../staff/screens/staff_dashboard_screen.dart';
import '../../theater_manager/screens/theater_manager_dashboard_screen.dart';
import '../../../providers/user_provider.dart';
import '../../notifications/services/notification_service.dart';

const _fieldFill = Color(0xFF0A0A0A);
const _fieldBorder = Color(0x1AFFFFFF); // white 10%

class LoginScreen extends ConsumerStatefulWidget {
  final bool returnOnSuccess;
  const LoginScreen({super.key, this.returnOnSuccess = false});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool isLogin = true; // Chuyển đổi qua lại giữa Đăng nhập và Đăng ký
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _gender;
  DateTime? _birthDate;

  static const _genderOptions = ['Nam', 'Nữ', 'Khác'];

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000, 1, 1),
      firstDate: DateTime(1930),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: Colors.amber),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  void _submitAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnackBar('Vui lòng nhập đầy đủ thông tin!', Colors.orangeAccent);
      return;
    }

    if (!isLogin) {
      if (password != confirmPassword) {
        _showSnackBar('Mật khẩu xác nhận không trùng khớp!', Colors.redAccent);
        return;
      }
      if (name.isEmpty ||
          phone.isEmpty ||
          _gender == null ||
          _birthDate == null) {
        _showSnackBar(
          'Vui lòng điền đầy đủ họ tên, SĐT, giới tính và ngày sinh!',
          Colors.orangeAccent,
        );
        return;
      }
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const _AuthLoadingSkeleton(),
      );

      final authViewModel = ref.read(authViewModelProvider.notifier);
      Map<String, dynamic> result;

      if (isLogin) {
        result = await authViewModel.signIn(email, password);
      } else {
        result = await authViewModel.signUp(
          email: email,
          password: password,
          name: name,
          phone: phone,
          gender: _gender!,
          birthDate: _birthDate!,
        );
      }

      if (!mounted) return;
      Navigator.pop(context); // Tắt vòng xoay loading

      if (result['success']) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          // Xác thực 2 lớp (2FA) qua OTP email chỉ áp dụng cho khách hàng
          // thường đăng nhập bằng email/password - tài khoản admin/staff/
          // theater_manager do quản trị viên tạo trực tiếp (không tự đăng ký),
          // đã được xác minh danh tính khi cấp tài khoản nên bỏ qua bước này.
          // Google Sign-In cũng bỏ qua vì đã xác thực OAuth (_handleGoogleSignIn).
          if (isLogin && !(await _isPrivilegedAccount(user.uid))) {
            await _showOtpGate(user);
          } else {
            await _navigateByRole(user.uid);
          }
        }
      } else {
        _showSnackBar(
          result['message'] ?? 'Lỗi không xác định',
          Colors.redAccent,
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showSnackBar(
        'Lỗi: ${e.toString().split(']').last.trim()}',
        Colors.redAccent,
      );
    }
  }

  // Admin/staff/theater_manager/accountant/marketing không cần xác thực OTP
  // (xem _submitAuth) - đều là tài khoản do quản trị viên cấp trực tiếp,
  // đã xác minh danh tính khi cấp, không tự đăng ký như khách hàng.
  Future<bool> _isPrivilegedAccount(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      
      final profile = UserProfile.fromMap(uid, doc.data() ?? {});
      if (profile.hasStaffAccess || profile.hasBackofficeAccess) {
        return true;
      }
    } catch (_) {}

    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.email != null) {
      final email = user.email!.toLowerCase().trim();
      if (email.startsWith('admin') ||
          email.startsWith('manager') ||
          email.startsWith('staff') ||
          email.startsWith('accountant') ||
          email.startsWith('marketing') ||
          email.contains('admin_') ||
          email.contains('staff_') ||
          email.contains('manager_')) {
        return true;
      }
    }
    return false;
  }

  // Chặn không cho vào app cho tới khi nhập đúng mã OTP gửi qua email - tự
  // động gửi mã ngay khi mở dialog. Có nút gửi lại (đề phòng mã hết hạn/thất
  // lạc).
  //
  // Dialog phải HIỆN NGAY LẬP TỨC (barrierDismissible: true, không chờ request
  // gửi email xong mới showDialog như bản cũ) - trước đây phải chờ xong
  // request /auth/send-otp (có thể mất 1-2s vì gửi email thật qua SMTP) mới
  // thấy gì trên màn hình, tạo cảm giác app bị đứng/lag ngay sau khi đăng
  // nhập. Giờ showDialog chạy trước, việc gửi mã diễn ra NGẦM ngay khi dialog
  // vừa build lần đầu, có spinner "Đang gửi mã..." trong lúc chờ.
  //
  // Cho phép bấm ra ngoài/back để đóng dialog (trước đây barrierDismissible:
  // false và không có nút Huỷ - người dùng lỡ mở dialog không có cách nào
  // thoát ra ngoài việc bấm back, để lại phiên Firebase Auth đã đăng nhập
  // nhưng CHƯA qua OTP). Bất kể đóng bằng cách nào (bấm ra ngoài, back, hay
  // nút HUỶ) mà chưa xác thực thành công, tự signOut() ngay sau khi dialog
  // đóng - tránh để lại phiên đăng nhập dở dang có thể gây nhầm lẫn (như hiện
  // tượng "còn sót lại" khi đăng nhập tài khoản vai trò khác ngay sau đó).
  Future<void> _showOtpGate(User user) async {
    final digitControllers = List.generate(6, (_) => TextEditingController());
    final digitFocusNodes = List.generate(6, (_) => FocusNode());
    bool sending = true;
    bool verifying = false;
    bool verified = false;
    bool firstSendTriggered = false;
    String? errorText;

    String currentCode() => digitControllers.map((c) => c.text).join();

    final authViewModel = ref.read(authViewModelProvider.notifier);

    Future<void> performVerification(
      String code,
      void Function(void Function()) setDialogState,
      BuildContext dialogCtx,
    ) async {
      if (verifying) return;
      setDialogState(() {
        verifying = true;
        errorText = null;
      });
      final r = await authViewModel.verifyLoginOtp(code);
      if (!r['success']) {
        setDialogState(() {
          verifying = false;
          errorText = r['message'] ?? 'Mã xác thực không đúng';
          for (final c in digitControllers) {
            c.clear();
          }
        });
        digitFocusNodes.first.requestFocus();
        return;
      }
      verified = true;
      if (dialogCtx.mounted) {
        Navigator.pop(dialogCtx);
      }
      await _navigateByRole(user.uid);
    }

    void triggerSend(void Function(void Function()) setDialogState) {
      authViewModel.sendLoginOtp().then((r) {
        setDialogState(() {
          sending = false;
          if (!r['success']) {
            errorText = r['message'] ?? 'Không gửi được mã xác thực';
          }
        });
      });
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          if (!firstSendTriggered) {
            firstSendTriggered = true;
            triggerSend(setDialogState);
          }
          return AlertDialog(
            backgroundColor: const Color(0xFF0A0A0A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(
                  Icons.verified_user_rounded,
                  color: Colors.amber,
                  size: 22,
                ),
                SizedBox(width: 8),
                Text(
                  'XÁC THỰC OTP',
                  style: TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nhập mã 6 số vừa được gửi tới "${user.email}".',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                if (sending) ...[
                  const SizedBox(height: 14),
                  const Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.amber,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Đang gửi mã xác thực...',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (index) {
                    final filled = digitControllers[index].text.isNotEmpty;
                    return SizedBox(
                      width: 44,
                      height: 54,
                      child: Focus(
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent &&
                              event.logicalKey ==
                                  LogicalKeyboardKey.backspace &&
                              digitControllers[index].text.isEmpty &&
                              index > 0) {
                            digitControllers[index - 1].clear();
                            digitFocusNodes[index - 1].requestFocus();
                            setDialogState(() {});
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: digitControllers[index],
                          focusNode: digitFocusNodes[index],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            filled: true,
                            fillColor: _fieldFill,
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: filled
                                    ? Colors.amber.withValues(alpha: 0.6)
                                    : _fieldBorder,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: filled
                                    ? Colors.amber.withValues(alpha: 0.6)
                                    : _fieldBorder,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Colors.amber,
                                width: 1.6,
                              ),
                            ),
                          ),
                          onChanged: (value) async {
                            if (value.length > 1) {
                              final digits = value.replaceAll(
                                RegExp(r'\D'),
                                '',
                              );
                              setDialogState(() {
                                errorText = null;
                                for (
                                  int i = 0;
                                  i < digits.length && (index + i) < 6;
                                  i++
                                ) {
                                  digitControllers[index + i].text = digits[i];
                                }
                                final next = (index + digits.length).clamp(
                                  0,
                                  5,
                                );
                                digitFocusNodes[next].requestFocus();
                              });
                              
                              final code = currentCode();
                              if (code.length == 6) {
                                await performVerification(code, setDialogState, ctx);
                              }
                              return;
                            }
                            setDialogState(() => errorText = null);
                            if (value.isNotEmpty && index < 5) {
                              digitFocusNodes[index + 1].requestFocus();
                            }
                            
                            final code = currentCode();
                            if (code.length == 6) {
                              await performVerification(code, setDialogState, ctx);
                            }
                          },
                        ),
                      ),
                    );
                  }),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorText!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: sending
                    ? null
                    : () async {
                        setDialogState(() {
                          sending = true;
                          errorText = null;
                          for (final c in digitControllers) {
                            c.clear();
                          }
                        });
                        digitFocusNodes.first.requestFocus();
                        final r = await authViewModel.sendLoginOtp();
                        setDialogState(() {
                          sending = false;
                          if (!r['success']) errorText = r['message'];
                        });
                      },
                child: Text(
                  sending ? 'ĐANG GỬI...' : 'GỬI LẠI MÃ',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              ElevatedButton(
                onPressed: verifying
                    ? null
                    : () async {
                        final code = currentCode();
                        if (code.length != 6) {
                          setDialogState(
                            () => errorText = 'Mã xác thực gồm 6 số',
                          );
                          return;
                        }
                        await performVerification(code, setDialogState, ctx);
                      },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                child: Text(
                  verifying ? 'ĐANG XÁC THỰC...' : 'XÁC THỰC',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    // Đóng dialog bằng bất kỳ cách nào (bấm ra ngoài, back, nút HUỶ) mà CHƯA
    // xác thực xong - đăng xuất luôn thay vì để lại phiên Firebase Auth đã
    // đăng nhập nhưng chưa qua OTP. Trước đây không có bước này: bấm back là
    // thoát được dialog nhưng tài khoản vẫn ở trạng thái "đã đăng nhập dở
    // dang" - lần đăng nhập tiếp theo (kể cả bằng tài khoản vai trò khác) có
    // thể bị ảnh hưởng bởi phiên cũ chưa được dọn sạch.
    if (!verified) {
      await FirebaseAuth.instance.signOut();
    }

    for (final c in digitControllers) {
      c.dispose();
    }
    for (final f in digitFocusNodes) {
      f.dispose();
    }
  }

  Future<void> _navigateByRole(String uid) async {
    // Xin quyền + lưu FCM token ngay sau khi đăng nhập - trước đây hàm này
    // được định nghĩa nhưng chưa từng được gọi ở đâu trong app, nên tính
    // năng push notification coi như không hoạt động dù đã có sẵn code.
    // Fire-and-forget: không chặn điều hướng nếu xin quyền chậm/bị từ chối.
    NotificationService().initNotifications();

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final data = doc.data() ?? {};
    final profile = UserProfile.fromMap(uid, data);

    if (!mounted) return;

    // Bắt buộc xác thực email trước khi vào app - trước đây đăng ký xong là
    // vào thẳng app luôn, không hề gửi/kiểm tra email xác thực, ai cũng đăng
    // ký được bằng email rác/không có thật. Chỉ áp dụng cho khách hàng
    // thường (role 'user') - tài khoản staff/manager/admin/accountant/
    // marketing do quản trị viên tạo trực tiếp, không qua luồng tự đăng ký này.
    if (!profile.hasStaffAccess && !profile.hasBackofficeAccess) {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser != null) {
        await authUser.reload();
        final refreshed = FirebaseAuth.instance.currentUser;
        if (refreshed != null && !refreshed.emailVerified) {
          if (!mounted) return;
          await _showVerifyEmailGate(refreshed);
          return; // chặn điều hướng - _showVerifyEmailGate tự xử lý tiếp khi xác thực xong
        }
      }
    }

    Widget destination;
    if (profile.hasBackofficeAccess) {
      destination = const AdminDashboardScreen();
    } else if (profile.hasManagerAccess) {
      destination = TheaterManagerDashboardScreen(managerProfile: profile);
    } else if (profile.hasStaffAccess) {
      destination = StaffDashboardScreen(staffProfile: profile);
    } else {
      if (widget.returnOnSuccess) {
        Navigator.pop(context, true);
        return;
      }
      destination = const HomeScreen();
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  // Hộp thoại chặn không cho vào app cho tới khi xác thực email - có nút gửi
  // lại email (đề phòng thất lạc/hết hạn link) và nút "Tôi đã xác thực" để
  // reload trạng thái mà không cần thoát app rồi đăng nhập lại từ đầu.
  Future<void> _showVerifyEmailGate(User user) async {
    bool sending = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF0A0A0A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.mark_email_unread_rounded,
                color: Colors.amber,
                size: 22,
              ),
              SizedBox(width: 8),
              Text(
                'XÁC THỰC EMAIL',
                style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          content: Text(
            'Vui lòng kiểm tra hộp thư "${user.email}" và bấm vào liên kết xác thực trước khi sử dụng ứng dụng.',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text(
                'ĐĂNG XUẤT',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: sending
                  ? null
                  : () async {
                      setDialogState(() => sending = true);
                      try {
                        await user.sendEmailVerification();
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('Đã gửi lại email xác thực!'),
                              backgroundColor: Colors.teal,
                            ),
                          );
                        }
                      } catch (_) {
                      } finally {
                        setDialogState(() => sending = false);
                      }
                    },
              child: Text(
                sending ? 'ĐANG GỬI...' : 'GỬI LẠI EMAIL',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                await user.reload();
                final refreshed = FirebaseAuth.instance.currentUser;
                if (refreshed != null && refreshed.emailVerified) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _navigateByRole(refreshed.uid);
                } else if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Vẫn chưa xác thực - kiểm tra lại hộp thư nhé.',
                      ),
                      backgroundColor: Colors.orangeAccent,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              child: const Text(
                'TÔI ĐÃ XÁC THỰC',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  final bool _googleInitialized = false;

  void _handleGoogleSignIn() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const _AuthLoadingSkeleton(),
      );

      final authViewModel = ref.read(authViewModelProvider.notifier);
      final result = await authViewModel.signInWithGoogle();

      if (!mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context); // tắt loading

      if (result['success']) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await _navigateByRole(uid);
        }
      } else {
        _showSnackBar(
          result['message'] ?? 'Lỗi đăng nhập Google',
          Colors.redAccent,
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context);
      _showSnackBar('Lỗi đăng nhập Google: $e', Colors.redAccent);
    }
  }

  void _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showSnackBar(
        'Nhập email trước để nhận link đặt lại mật khẩu!',
        Colors.orangeAccent,
      );
      return;
    }
    try {
      final authViewModel = ref.read(authViewModelProvider.notifier);
      await authViewModel.resetPassword(email);
      _showSnackBar('Đã gửi email đặt lại mật khẩu!', Colors.teal);
    } catch (e) {
      _showSnackBar(
        'Lỗi: ${e.toString().split(']').last.trim()}',
        Colors.redAccent,
      );
    }
  }

  void _showSnackBar(String message, Color iconColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.info_outline, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0A0A0A),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 108,
                        height: 108,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          // Nếu user chưa lưu logo, hiện tạm chữ G5
                          return Container(
                            width: 108,
                            height: 108,
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'G5',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900,
                                fontSize: 40,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'STELLA CINEMA',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF060606),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _fieldBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => isLogin = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: isLogin
                                      ? Colors.amber
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'Đăng Nhập',
                                  style: TextStyle(
                                    color: isLogin ? Colors.black : Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => isLogin = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: !isLogin
                                      ? Colors.amber
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'Đăng Ký',
                                  style: TextStyle(
                                    color: !isLogin
                                        ? Colors.black
                                        : Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),

                    if (!isLogin) ...[
                      const Text(
                        'Họ và tên',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameController,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Nhập họ và tên...',
                          hintStyle: const TextStyle(
                            color: Colors.white30,
                            fontSize: 13,
                          ),
                          prefixIcon: const Icon(
                            Icons.person_outline_rounded,
                            color: Colors.white38,
                            size: 20,
                          ),
                          filled: true,
                          fillColor: _fieldFill,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: _fieldBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: _fieldBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.amber),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        'Số điện thoại',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: '0912345678',
                          hintStyle: const TextStyle(
                            color: Colors.white30,
                            fontSize: 13,
                          ),
                          prefixIcon: const Icon(
                            Icons.phone_outlined,
                            color: Colors.white38,
                            size: 20,
                          ),
                          filled: true,
                          fillColor: _fieldFill,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: _fieldBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: _fieldBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.amber),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    const Text(
                      'Địa chỉ Email',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Nhập email của bạn...',
                        hintStyle: const TextStyle(
                          color: Colors.white30,
                          fontSize: 13,
                        ),
                        prefixIcon: const Icon(
                          Icons.mail_outline_rounded,
                          color: Colors.white38,
                          size: 20,
                        ),
                        filled: true,
                        fillColor: _fieldFill,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: _fieldBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: _fieldBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.amber),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    if (!isLogin) ...[
                      const Text(
                        'Giới tính',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Chỉ 3 lựa chọn - hiện hết dạng nút chọn thay vì giấu
                      // trong dropdown (phải bấm mở ra mới thấy hết lựa chọn).
                      Row(
                        children: _genderOptions.map((g) {
                          final isSelected = _gender == g;
                          return Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: g == _genderOptions.last ? 0 : 8,
                              ),
                              child: GestureDetector(
                                onTap: () => setState(() => _gender = g),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.amber
                                        : _fieldFill,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.amber
                                          : _fieldBorder,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    g,
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.black
                                          : Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        'Ngày sinh',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _pickBirthDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: _fieldFill,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _fieldBorder),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.cake_outlined,
                                color: Colors.white38,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _birthDate == null
                                    ? 'Chọn ngày sinh...'
                                    : '${_birthDate!.day.toString().padLeft(2, '0')}/${_birthDate!.month.toString().padLeft(2, '0')}/${_birthDate!.year}',
                                style: TextStyle(
                                  color: _birthDate == null
                                      ? Colors.white30
                                      : Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    const Text(
                      'Mật khẩu',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Nhập mật khẩu...',
                        hintStyle: const TextStyle(
                          color: Colors.white30,
                          fontSize: 13,
                        ),
                        prefixIcon: const Icon(
                          Icons.lock_outline_rounded,
                          color: Colors.white38,
                          size: 20,
                        ),
                        filled: true,
                        fillColor: _fieldFill,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: _fieldBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: _fieldBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.amber),
                        ),
                      ),
                    ),

                    if (isLogin) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: _handleForgotPassword,
                          child: const Text(
                            'Quên mật khẩu?',
                            style: TextStyle(
                              color: Colors.amber,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ] else
                      const SizedBox(height: 20),

                    if (!isLogin) ...[
                      const Text(
                        'Xác nhận mật khẩu',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _confirmPasswordController,
                        obscureText: true,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Nhập lại mật khẩu...',
                          hintStyle: const TextStyle(
                            color: Colors.white30,
                            fontSize: 13,
                          ),
                          prefixIcon: const Icon(
                            Icons.lock_outline_rounded,
                            color: Colors.white38,
                            size: 20,
                          ),
                          filled: true,
                          fillColor: _fieldFill,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: _fieldBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: _fieldBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.amber),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    const SizedBox(height: 8),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submitAuth,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          isLogin ? 'ĐĂNG NHẬP' : 'ĐĂNG KÝ',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    Row(
                      children: [
                        Expanded(
                          child: Container(height: 0.5, color: _fieldBorder),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            'hoặc',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(height: 0.5, color: _fieldBorder),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _handleGoogleSignIn,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: _fieldBorder),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(
                              Icons.g_mobiledata_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Đăng nhập với Google',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              Center(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      isLogin = !isLogin;
                    });
                  },
                  child: RichText(
                    text: TextSpan(
                      text: isLogin
                          ? "Bạn chưa có tài khoản? "
                          : "Đã có tài khoản? ",
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                      children: [
                        TextSpan(
                          text: isLogin ? "Đăng Ký" : "Đăng Nhập",
                          style: const TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Center(
                child: GestureDetector(
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const HomeScreen(),
                      ),
                    );
                  },
                  child: const Text(
                    'Tiếp tục với tư cách Khách',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.white60,
                      decorationThickness: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Khung chờ dạng Skeleton (khối xám lấp lánh) hiện trong lúc đăng nhập/đăng
// ký/đăng nhập Google đang xử lý - thay cho CircularProgressIndicator cũ
// (1 vòng xoay đơn giản không gợi ý được nội dung nào sắp hiện ra). Các khối
// bên dưới mô phỏng đúng bố cục form (avatar tròn, 2 dòng field, 1 nút) nên
// người dùng có cảm giác trang đang "tải dữ liệu thật" thay vì chỉ chờ mù.
class _AuthLoadingSkeleton extends StatelessWidget {
  const _AuthLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Shimmer.fromColors(
        baseColor: const Color(0xFF1A1A1A),
        highlightColor: const Color(0xFF3A3A3A),
        period: const Duration(milliseconds: 1200),
        child: Container(
          width: 260,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(height: 20),
              _skeletonBar(width: 160, height: 12),
              const SizedBox(height: 14),
              _skeletonBar(width: double.infinity, height: 40),
              const SizedBox(height: 12),
              _skeletonBar(width: double.infinity, height: 40),
              const SizedBox(height: 18),
              _skeletonBar(width: double.infinity, height: 44),
            ],
          ),
        ),
      ),
    );
  }

  Widget _skeletonBar({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}
