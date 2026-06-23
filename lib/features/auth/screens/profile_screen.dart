import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../main.dart'; // For MainAppWrapper

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final User? _user = FirebaseAuth.instance.currentUser;
  bool _isResetting = false;

  void _handleResetPassword() async {
    final email = _user?.email;
    if (email == null) return;
    
    setState(() => _isResetting = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã gửi liên kết đặt lại mật khẩu đến $email. Vui lòng kiểm tra hộp thư đến.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi gửi email đặt lại mật khẩu: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  void _handleLogout() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    
    // Hiện xác nhận trước khi đăng xuất
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('ĐĂNG XUẤT', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 15)),
        content: const Text('Bạn có chắc chắn muốn đăng xuất tài khoản Stella Cinema?', style: TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('KHÔNG', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('ĐĂNG XUẤT', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const MainAppWrapper()),
        (route) => false,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Đã đăng xuất tài khoản thành công.')),
      );
    }
  }

  void _showTopUpDialog(BuildContext context, int currentBalance) {
    final controller = TextEditingController(text: '100000');
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF16161F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('NẠP TIỀN STELLA WALLET', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Hệ thống Stella Wallet giúp thanh toán vé nhanh chóng. Số tiền nạp sẽ được mô phỏng cộng vào tài khoản ảo:', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: 'Nhập số tiền nạp...',
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: const Color(0xFF1E1E2A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  suffixText: 'đ',
                  suffixStyle: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [100000, 200000, 500000].map((amount) {
                  final format = amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');
                  return GestureDetector(
                    onTap: () {
                      controller.text = amount.toString();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFF1E1E2A), borderRadius: BorderRadius.circular(6)),
                      child: Text('+$format', style: const TextStyle(color: Colors.amber, fontSize: 11)),
                    ),
                  );
                }).toList(),
              )
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('HỦY BỎ', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
            ElevatedButton(
              onPressed: () async {
                final amountText = controller.text.trim();
                final int amount = int.tryParse(amountText) ?? 0;
                if (amount <= 0) return;
                
                Navigator.pop(context);
                
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid != null) {
                  await FirebaseFirestore.instance.collection('users').doc(uid).set({
                    'wallet_balance': currentBalance + amount,
                  }, SetOptions(merge: true));
                  
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Đã nạp thành công ${amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')} đ vào ví!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              child: const Text('XÁC NHẬN NẠP', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
            )
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = _user?.email ?? 'Chưa đăng nhập';
    final nameInitials = email.isNotEmpty ? email.substring(0, 2).toUpperCase() : 'US';

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text('HỒ SƠ CÁ NHÂN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 30.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar Circle
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 54,
                    backgroundColor: Colors.amber.withOpacity(0.1),
                    child: CircleAvatar(
                      radius: 48,
                      backgroundColor: Colors.amber,
                      child: Text(
                        nameInitials,
                        style: const TextStyle(color: Colors.black, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 1),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
                      child: const Icon(Icons.edit_rounded, color: Colors.black, size: 16),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 25),
            
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('tickets')
                  .where('email', isEqualTo: email)
                  .snapshots(),
              builder: (context, snapshot) {
                final int ticketCount = snapshot.hasData ? snapshot.data!.docs.length : 0;
                final int points = ticketCount * 50;
                
                String tierName = 'THÀNH VIÊN ĐỒNG';
                List<Color> cardGradient = [
                  const Color(0xFF8B5A2B),
                  const Color(0xFFCD7F32),
                  const Color(0xFFE5A65D),
                ];
                Color tierColor = const Color(0xFFCD7F32);
                
                if (ticketCount >= 3 && ticketCount <= 5) {
                  tierName = 'THÀNH VIÊN BẠC';
                  cardGradient = [
                    const Color(0xFF7F8C8D),
                    const Color(0xFFBDC3C7),
                    const Color(0xFFECF0F1),
                  ];
                  tierColor = const Color(0xFFBDC3C7);
                } else if (ticketCount > 5) {
                  tierName = 'THÀNH VIÊN VÀNG VIP';
                  cardGradient = [
                    const Color(0xFFD4AF37),
                    const Color(0xFFF1C40F),
                    const Color(0xFFF39C12),
                  ];
                  tierColor = const Color(0xFFF1C40F);
                }

                return Column(
                  children: [
                    // Thẻ tag nhỏ
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: tierColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: tierColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.stars_rounded, color: tierColor, size: 16),
                          const SizedBox(width: 6),
                          Text(tierName, style: TextStyle(color: tierColor, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 25),

                    // THẺ THÀNH VIÊN METALLIC GRADIENT SIÊU PREMIUM
                    Container(
                      width: double.infinity,
                      height: 180,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: cardGradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: tierColor.withValues(alpha: 0.2),
                            blurRadius: 15,
                            spreadRadius: 2,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          // Họa tiết trang trí vòng tròn chìm bên dưới
                          Positioned(
                            right: -50,
                            bottom: -50,
                            child: Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 40,
                            top: -60,
                            child: Container(
                              width: 150,
                              height: 150,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.05),
                              ),
                            ),
                          ),
                          // Nội dung thẻ
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
                                        Text(
                                          'STELLA CINEMA',
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                            letterSpacing: 1.5,
                                          ),
                                        ),
                                        Text(
                                          'MEMBER PASS',
                                          style: TextStyle(
                                            color: Colors.black54,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 8,
                                            letterSpacing: 1.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'G5',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      email,
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'MÃ THẺ: STL-8290-7491',
                                      style: TextStyle(
                                        color: Colors.black45,
                                        fontFamily: 'monospace',
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'TỔNG ĐÃ MUA',
                                          style: TextStyle(
                                            color: Colors.black54,
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          '$ticketCount vé',
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        const Text(
                                          'ĐIỂM TÍCH LŨY',
                                          style: TextStyle(
                                            color: Colors.black54,
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          '$points Pts',
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
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
            ),
            const SizedBox(height: 20),

            // Ví Stella Wallet Card
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(_user?.uid).snapshots(),
              builder: (context, userSnapshot) {
                int walletBalance = 500000; // Mặc định tặng 500k làm vốn trải nghiệm
                if (userSnapshot.hasData && userSnapshot.data!.exists) {
                  final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                  walletBalance = userData?['wallet_balance'] ?? 500000;
                } else if (userSnapshot.hasData && !userSnapshot.data!.exists && _user != null) {
                  // Tự động khởi tạo ví trên Firestore
                  FirebaseFirestore.instance.collection('users').doc(_user.uid).set({
                    'email': _user.email,
                    'wallet_balance': 500000,
                    'created_at': Timestamp.now(),
                  });
                }

                final formatBalance = walletBalance.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E272C), Color(0xFF0F2027)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
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
                              Text('VÍ STELLA WALLET', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$formatBalance đ',
                            style: const TextStyle(color: Colors.amber, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _showTopUpDialog(context, walletBalance),
                        icon: const Icon(Icons.add_card_rounded, color: Colors.black, size: 14),
                        label: const Text('NẠP TIỀN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 30),

            // Profile info box
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
                  const Text('THÔNG TIN LIÊN HỆ', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.email_outlined, color: Colors.white38, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Địa chỉ Email', style: TextStyle(color: Colors.grey, fontSize: 11)),
                            const SizedBox(height: 2),
                            Text(email, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10, height: 24),
                  const Row(
                    children: [
                      Icon(Icons.phone_android_rounded, color: Colors.white38, size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Số điện thoại', style: TextStyle(color: Colors.grey, fontSize: 11)),
                            SizedBox(height: 2),
                            Text('Chưa liên kết', style: TextStyle(color: Colors.white38, fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Settings options box
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
                    subtitle: const Text('Gửi email yêu cầu reset mật khẩu', style: TextStyle(color: Colors.grey, fontSize: 11)),
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

            // Logout Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _handleLogout,
                icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                label: const Text('ĐĂNG XUẤT TÀI KHOẢN', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.redAccent, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
