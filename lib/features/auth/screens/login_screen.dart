import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
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
        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: Colors.amber)),
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
      if (name.isEmpty || phone.isEmpty || _gender == null || _birthDate == null) {
        _showSnackBar('Vui lòng điền đầy đủ họ tên, SĐT, giới tính và ngày sinh!', Colors.orangeAccent);
        return;
      }
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.amber)),
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
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await _navigateByRole(uid);
        }
      } else {
        _showSnackBar(result['message'] ?? 'Lỗi không xác định', Colors.redAccent);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showSnackBar('Lỗi: ${e.toString().split(']').last.trim()}', Colors.redAccent);
    }
  }

  Future<void> _navigateByRole(String uid) async {
    // Xin quyền + lưu FCM token ngay sau khi đăng nhập - trước đây hàm này
    // được định nghĩa nhưng chưa từng được gọi ở đâu trong app, nên tính
    // năng push notification coi như không hoạt động dù đã có sẵn code.
    // Fire-and-forget: không chặn điều hướng nếu xin quyền chậm/bị từ chối.
    NotificationService().initNotifications();

    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data() ?? {};
    final profile = UserProfile.fromMap(uid, data);

    if (!mounted) return;

    // Bắt buộc xác thực email trước khi vào app - trước đây đăng ký xong là
    // vào thẳng app luôn, không hề gửi/kiểm tra email xác thực, ai cũng đăng
    // ký được bằng email rác/không có thật. Chỉ áp dụng cho khách hàng
    // thường (role 'user') - tài khoản staff/manager/admin do quản trị viên
    // tạo trực tiếp, không qua luồng tự đăng ký này.
    if (!profile.hasStaffAccess) {
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
    if (profile.hasAdminAccess) {
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.mark_email_unread_rounded, color: Colors.amber, size: 22),
              SizedBox(width: 8),
              Text('XÁC THỰC EMAIL', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          content: Text(
            'Vui lòng kiểm tra hộp thư "${user.email}" và bấm vào liên kết xác thực trước khi sử dụng ứng dụng.',
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('ĐĂNG XUẤT', style: TextStyle(color: Colors.grey)),
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
                            const SnackBar(content: Text('Đã gửi lại email xác thực!'), backgroundColor: Colors.teal),
                          );
                        }
                      } catch (_) {
                      } finally {
                        setDialogState(() => sending = false);
                      }
                    },
              child: Text(sending ? 'ĐANG GỬI...' : 'GỬI LẠI EMAIL', style: const TextStyle(color: Colors.white70)),
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
                    const SnackBar(content: Text('Vẫn chưa xác thực - kiểm tra lại hộp thư nhé.'), backgroundColor: Colors.orangeAccent),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              child: const Text('TÔI ĐÃ XÁC THỰC', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  bool _googleInitialized = false;

  void _handleGoogleSignIn() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.amber)),
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
        _showSnackBar(result['message'] ?? 'Lỗi đăng nhập Google', Colors.redAccent);
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
      _showSnackBar('Nhập email trước để nhận link đặt lại mật khẩu!', Colors.orangeAccent);
      return;
    }
    try {
      final authViewModel = ref.read(authViewModelProvider.notifier);
      await authViewModel.resetPassword(email);
      _showSnackBar('Đã gửi email đặt lại mật khẩu!', Colors.teal);
    } catch (e) {
      _showSnackBar('Lỗi: ${e.toString().split(']').last.trim()}', Colors.redAccent);
    }
  }

  void _showSnackBar(String message, Color iconColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.info_outline, color: iconColor),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 13))),
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
                            decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(20)),
                            alignment: Alignment.center,
                            child: const Text('G5', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 40)),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('STELLA CINEMA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1)),
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
                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => isLogin = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  color: isLogin ? Colors.amber : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.center,
                                child: Text('Đăng Nhập', style: TextStyle(color: isLogin ? Colors.black : Colors.grey, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => isLogin = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  color: !isLogin ? Colors.amber : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.center,
                                child: Text('Đăng Ký', style: TextStyle(color: !isLogin ? Colors.black : Colors.grey, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),

                    if (!isLogin) ...[
                      const Text('Họ và tên', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameController,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Nhập họ và tên...',
                          hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                          prefixIcon: const Icon(Icons.person_outline_rounded, color: Colors.white38, size: 20),
                          filled: true,
                          fillColor: _fieldFill,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _fieldBorder)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _fieldBorder)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.amber)),
                        ),
                      ),
                      const SizedBox(height: 20),

                      const Text('Số điện thoại', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Nhập số điện thoại...',
                          hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                          prefixIcon: const Icon(Icons.phone_outlined, color: Colors.white38, size: 20),
                          filled: true,
                          fillColor: _fieldFill,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _fieldBorder)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _fieldBorder)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.amber)),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    const Text('Địa chỉ Email', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Nhập email của bạn...',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                        prefixIcon: const Icon(Icons.mail_outline_rounded, color: Colors.white38, size: 20),
                        filled: true,
                        fillColor: _fieldFill,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _fieldBorder)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _fieldBorder)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.amber)),
                      ),
                    ),
                    const SizedBox(height: 20),

                    if (!isLogin) ...[
                      const Text('Giới tính', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _gender,
                        dropdownColor: const Color(0xFF0A0A0A),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Chọn giới tính',
                          hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                          prefixIcon: const Icon(Icons.wc_rounded, color: Colors.white38, size: 20),
                          filled: true,
                          fillColor: _fieldFill,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _fieldBorder)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _fieldBorder)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.amber)),
                        ),
                        items: _genderOptions.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                        onChanged: (v) => setState(() => _gender = v),
                      ),
                      const SizedBox(height: 20),

                      const Text('Ngày sinh', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _pickBirthDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(
                            color: _fieldFill,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _fieldBorder),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.cake_outlined, color: Colors.white38, size: 20),
                              const SizedBox(width: 12),
                              Text(
                                _birthDate == null
                                    ? 'Chọn ngày sinh...'
                                    : '${_birthDate!.day.toString().padLeft(2, '0')}/${_birthDate!.month.toString().padLeft(2, '0')}/${_birthDate!.year}',
                                style: TextStyle(color: _birthDate == null ? Colors.white30 : Colors.white, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    const Text('Mật khẩu', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Nhập mật khẩu...',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                        prefixIcon: const Icon(Icons.lock_outline_rounded, color: Colors.white38, size: 20),
                        filled: true,
                        fillColor: _fieldFill,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _fieldBorder)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _fieldBorder)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.amber)),
                      ),
                    ),

                    if (isLogin) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: _handleForgotPassword,
                          child: const Text('Quên mật khẩu?', style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.w500)),
                        ),
                      ),
                    ] else
                      const SizedBox(height: 20),

                    if (!isLogin) ...[
                      const Text('Xác nhận mật khẩu', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _confirmPasswordController,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Nhập lại mật khẩu...',
                          hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                          prefixIcon: const Icon(Icons.lock_outline_rounded, color: Colors.white38, size: 20),
                          filled: true,
                          fillColor: _fieldFill,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _fieldBorder)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _fieldBorder)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.amber)),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: Text(
                          isLogin ? 'ĐĂNG NHẬP' : 'ĐĂNG KÝ',
                          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    Row(
                      children: [
                        Expanded(child: Container(height: 0.5, color: _fieldBorder)),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text('hoặc', style: TextStyle(color: Colors.white38, fontSize: 12)),
                        ),
                        Expanded(child: Container(height: 0.5, color: _fieldBorder)),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.g_mobiledata_rounded, color: Colors.white, size: 26),
                            SizedBox(width: 4),
                            Text('Đăng nhập với Google', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13)),
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
                      text: isLogin ? "Bạn chưa có tài khoản? " : "Đã có tài khoản? ",
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                      children: [
                        TextSpan(
                          text: isLogin ? "Đăng Ký" : "Đăng Nhập",
                          style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
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
                      MaterialPageRoute(builder: (context) => const HomeScreen()),
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
