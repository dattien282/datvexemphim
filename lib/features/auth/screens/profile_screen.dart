import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../main.dart';
import '../../../providers/user_provider.dart';
import '../../admin/screens/admin_dashboard_screen.dart';
import '../../staff/screens/staff_dashboard_screen.dart';
import '../../theater_manager/screens/theater_manager_dashboard_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final User? _user = FirebaseAuth.instance.currentUser;
  bool _isResetting = false;
  bool _isUploadingAvatar = false;

  // ── Edit profile dialog ──────────────────────────────────────────────────
  void _showEditProfileDialog(UserProfile profile) {
    final nameCtrl = TextEditingController(text: profile.displayName);
    final phoneCtrl = TextEditingController(text: profile.phone);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'CHỈNH SỬA HỒ SƠ',
          style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildField(nameCtrl, 'Họ và tên', Icons.person_outline_rounded),
            const SizedBox(height: 12),
            _buildField(phoneCtrl, 'Số điện thoại', Icons.phone_android_rounded,
                inputType: TextInputType.phone),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('HỦY', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final uid = _user?.uid;
              if (uid == null) return;
              await FirebaseFirestore.instance.collection('users').doc(uid).set({
                'displayName': nameCtrl.text.trim(),
                'phone': phoneCtrl.text.trim(),
              }, SetOptions(merge: true));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã cập nhật hồ sơ thành công!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: const Text('LƯU', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String hint, IconData icon,
      {TextInputType inputType = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      keyboardType: inputType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.amber, size: 20),
        filled: true,
        fillColor: const Color(0xFF1E1E2A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  // ── Avatar picker ─────────────────────────────────────────────────────────
  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked == null) return;

    final uid = _user?.uid;
    if (uid == null) return;

    setState(() => _isUploadingAvatar = true);
    try {
      final ref = FirebaseStorage.instance.ref('avatars/$uid.jpg');
      await ref.putFile(File(picked.path));
      final url = await ref.getDownloadURL();
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'avatarUrl': url},
        SetOptions(merge: true),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã cập nhật ảnh đại diện!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi upload ảnh: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  // ── Reset password ────────────────────────────────────────────────────────
  void _handleResetPassword() async {
    final email = _user?.email;
    if (email == null) return;
    setState(() => _isResetting = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã gửi link đặt lại mật khẩu đến $email'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────
  void _handleLogout() async {
    final navigator = Navigator.of(context);
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('ĐĂNG XUẤT',
            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 15)),
        content: const Text('Bạn có chắc muốn đăng xuất?',
            style: TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('KHÔNG', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ĐĂNG XUẤT', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainAppWrapper()),
        (route) => false,
      );
    }
  }

  // ── Top-up dialog ─────────────────────────────────────────────────────────
  void _showTopUpDialog(int currentBalance) {
    final ctrl = TextEditingController(text: '100000');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('NẠP TIỀN STELLA WALLET',
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Số tiền nạp sẽ được cộng vào ví ảo Stella:',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1E1E2A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                suffixText: 'đ',
                suffixStyle: const TextStyle(color: Colors.amber),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [100000, 200000, 500000].map((amount) {
                final label = _formatMoney(amount);
                return GestureDetector(
                  onTap: () => ctrl.text = amount.toString(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFF1E1E2A), borderRadius: BorderRadius.circular(6)),
                    child: Text('+$label', style: const TextStyle(color: Colors.amber, fontSize: 11)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('HỦY', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              final amount = int.tryParse(ctrl.text.trim()) ?? 0;
              if (amount <= 0) return;
              Navigator.pop(ctx);
              final uid = _user?.uid;
              if (uid != null) {
                await FirebaseFirestore.instance.collection('users').doc(uid).set(
                  {'wallet_balance': currentBalance + amount},
                  SetOptions(merge: true),
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Đã nạp ${_formatMoney(amount)} đ vào ví!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: const Text('XÁC NHẬN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _formatMoney(int amount) =>
      amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text('HỒ SƠ CÁ NHÂN',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          profileAsync.when(
            data: (profile) => profile != null
                ? IconButton(
                    icon: const Icon(Icons.edit_rounded, color: Colors.amber, size: 20),
                    onPressed: () => _showEditProfileDialog(profile),
                    tooltip: 'Chỉnh sửa hồ sơ',
                  )
                : const SizedBox(),
            loading: () => const SizedBox(),
            error: (_, __) => const SizedBox(),
          ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.amber)),
        error: (e, _) => Center(child: Text('Lỗi: $e', style: const TextStyle(color: Colors.white))),
        data: (profile) => _buildBody(profile),
      ),
    );
  }

  Widget _buildBody(UserProfile? profile) {
    final email = _user?.email ?? 'Chưa đăng nhập';
    final displayName = profile?.displayName ?? '';
    final phone = profile?.phone ?? '';
    final avatarUrl = profile?.avatarUrl;
    final walletBalance = profile?.walletBalance ?? 500000;
    final nameInitials = displayName.isNotEmpty
        ? displayName.substring(0, displayName.length >= 2 ? 2 : 1).toUpperCase()
        : email.substring(0, 2).toUpperCase();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 30.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Avatar ──────────────────────────────────────────────────────
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 54,
                  backgroundColor: Colors.amber.withOpacity(0.1),
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: Colors.amber,
                    backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
                    child: avatarUrl == null
                        ? Text(nameInitials,
                            style: const TextStyle(color: Colors.black, fontSize: 26, fontWeight: FontWeight.w900))
                        : null,
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 4,
                  child: GestureDetector(
                    onTap: _isUploadingAvatar ? null : _pickAndUploadAvatar,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
                      child: _isUploadingAvatar
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                          : const Icon(Icons.camera_alt_rounded, color: Colors.black, size: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (displayName.isNotEmpty)
            Text(displayName,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          Text(email, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 20),

          // ── Membership card ──────────────────────────────────────────────
          _MembershipCard(email: email),
          const SizedBox(height: 20),

          // ── Wallet ───────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E272C), Color(0xFF0F2027)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.account_balance_wallet_rounded, color: Colors.amber, size: 16),
                        SizedBox(width: 8),
                        Text('VÍ STELLA WALLET',
                            style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('${_formatMoney(walletBalance)} đ',
                        style: const TextStyle(color: Colors.amber, fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () => _showTopUpDialog(walletBalance),
                  icon: const Icon(Icons.add_card_rounded, color: Colors.black, size: 14),
                  label: const Text('NẠP TIỀN',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Contact info ─────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF16161F),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.04)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('THÔNG TIN LIÊN HỆ',
                        style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                    GestureDetector(
                      onTap: profile != null ? () => _showEditProfileDialog(profile) : null,
                      child: const Text('Chỉnh sửa',
                          style: TextStyle(color: Colors.amber, fontSize: 12, decoration: TextDecoration.underline)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _infoRow(Icons.email_outlined, 'Địa chỉ Email', email),
                const Divider(color: Colors.white10, height: 24),
                _infoRow(Icons.phone_android_rounded, 'Số điện thoại',
                    phone.isNotEmpty ? phone : 'Chưa liên kết',
                    valueColor: phone.isNotEmpty ? Colors.white : Colors.white38),
                const Divider(color: Colors.white10, height: 24),
                _infoRow(Icons.person_outline_rounded, 'Họ và tên',
                    displayName.isNotEmpty ? displayName : 'Chưa cập nhật',
                    valueColor: displayName.isNotEmpty ? Colors.white : Colors.white38),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Settings ─────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF16161F),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.04)),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_reset_rounded, color: Colors.amber),
                  title: const Text('Đặt lại mật khẩu', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: const Text('Gửi email reset mật khẩu', style: TextStyle(color: Colors.grey, fontSize: 11)),
                  trailing: _isResetting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2))
                      : const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
                  onTap: _isResetting ? null : _handleResetPassword,
                ),
                const Divider(color: Colors.white10, height: 1),
                ListTile(
                  leading: const Icon(Icons.security_rounded, color: Colors.amber),
                  title: const Text('Điều khoản sử dụng', style: TextStyle(color: Colors.white, fontSize: 14)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
                  onTap: () {},
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),

          // ── Role badge ────────────────────────────────────────────────────
          if (profile != null && profile.role != UserRole.user) ...[
            const SizedBox(height: 8),
            _RoleBadge(role: profile.role),
            const SizedBox(height: 12),
          ],

          // ── Dashboard buttons theo role ───────────────────────────────────
          if (profile?.hasAdminAccess == true) ...[
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const AdminDashboardScreen())),
                icon: const Icon(Icons.admin_panel_settings_rounded, color: Colors.black, size: 20),
                label: const Text('ADMIN DASHBOARD',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ] else if (profile?.hasManagerAccess == true) ...[
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => TheaterManagerDashboardScreen(managerProfile: profile!))),
                icon: const Icon(Icons.business_rounded, color: Colors.white, size: 20),
                label: const Text('QUẢN LÝ RẠP',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ] else if (profile?.hasStaffAccess == true) ...[
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => StaffDashboardScreen(staffProfile: profile!))),
                icon: const Icon(Icons.badge_rounded, color: Colors.black, size: 20),
                label: const Text('SOÁT VÉ – NHÂN VIÊN',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.tealAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Logout ───────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _handleLogout,
              icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
              label: const Text('ĐĂNG XUẤT TÀI KHOẢN',
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {Color valueColor = Colors.white}) {
    return Row(
      children: [
        Icon(icon, color: Colors.white38, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(color: valueColor, fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Role Badge ────────────────────────────────────────────────────────────────
class _RoleBadge extends StatelessWidget {
  final UserRole role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    switch (role) {
      case UserRole.admin:
        color = Colors.amber; icon = Icons.admin_panel_settings_rounded;
      case UserRole.theaterManager:
        color = Colors.deepPurpleAccent; icon = Icons.business_rounded;
      case UserRole.staff:
        color = Colors.tealAccent; icon = Icons.badge_rounded;
      case UserRole.user:
        color = Colors.lightBlueAccent; icon = Icons.person_rounded;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(role.label,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }
}

// ── Membership Card (tách widget riêng) ─────────────────────────────────────
class _MembershipCard extends StatelessWidget {
  final String email;
  const _MembershipCard({required this.email});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tickets')
          .where('email', isEqualTo: email)
          .snapshots(),
      builder: (context, snapshot) {
        final int ticketCount = snapshot.hasData ? snapshot.data!.docs.length : 0;
        final int points = ticketCount * 50;

        String tierName = 'THÀNH VIÊN ĐỒNG';
        List<Color> gradient = [const Color(0xFF8B5A2B), const Color(0xFFCD7F32), const Color(0xFFE5A65D)];
        Color tierColor = const Color(0xFFCD7F32);

        if (ticketCount >= 3 && ticketCount <= 5) {
          tierName = 'THÀNH VIÊN BẠC';
          gradient = [const Color(0xFF7F8C8D), const Color(0xFFBDC3C7), const Color(0xFFECF0F1)];
          tierColor = const Color(0xFFBDC3C7);
        } else if (ticketCount > 5) {
          tierName = 'THÀNH VIÊN VÀNG VIP';
          gradient = [const Color(0xFFD4AF37), const Color(0xFFF1C40F), const Color(0xFFF39C12)];
          tierColor = const Color(0xFFF1C40F);
        }

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: tierColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: tierColor.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.stars_rounded, color: tierColor, size: 16),
                  const SizedBox(width: 6),
                  Text(tierName,
                      style: TextStyle(color: tierColor, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              height: 180,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: tierColor.withOpacity(0.2), blurRadius: 15, spreadRadius: 2, offset: const Offset(0, 8))],
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -50, bottom: -50,
                    child: Container(width: 200, height: 200, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.08))),
                  ),
                  Positioned(
                    right: 40, top: -60,
                    child: Container(width: 150, height: 150, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.05))),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('STELLA CINEMA',
                                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.5)),
                                Text('MEMBER PASS',
                                    style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold, fontSize: 8, letterSpacing: 1.5)),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: Colors.black.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                              child: const Text('G5', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 14)),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(email, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 4),
                            const Text('MÃ THẺ: STL-8290-7491',
                                style: TextStyle(color: Colors.black45, fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('TỔNG ĐÃ MUA',
                                    style: TextStyle(color: Colors.black54, fontSize: 8, fontWeight: FontWeight.bold)),
                                Text('$ticketCount vé',
                                    style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text('ĐIỂM TÍCH LŨY',
                                    style: TextStyle(color: Colors.black54, fontSize: 8, fontWeight: FontWeight.bold)),
                                Text('$points Pts',
                                    style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
