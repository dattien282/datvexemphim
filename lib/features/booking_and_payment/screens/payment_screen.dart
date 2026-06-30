import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'my_tickets_screen.dart';
import '../../notifications/screens/notification_service.dart';

class PaymentScreen extends StatefulWidget {
  final Map<String, dynamic> movieData;
  final List<String> selectedSeats;
  final int totalPrice;
  final List<Map<String, dynamic>> combos;

  const PaymentScreen({
    super.key,
    required this.movieData,
    required this.selectedSeats,
    required this.totalPrice,
    this.combos = const [],
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  Timer? _timer;
  int _secondsRemaining = 300; // 5 phút đếm ngược
  final _voucherController = TextEditingController();
  int _discountAmount = 0;
  String? _appliedVoucher;
  String? _voucherError;
  bool _isProcessing = false;
  
  // Nâng cấp: Các phương thức thanh toán và điều khoản
  String _selectedPaymentMethod = 'bank'; // 'bank' hoặc 'wallet'
  bool _agreedToTerms = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        if (mounted) {
          setState(() {
            _secondsRemaining--;
          });
        }
      } else {
        _timer?.cancel();
        _handleTimeout();
      }
    });
  }

  void _clearTemporaryLocks() async {
    final movieTitle = widget.movieData['title'] ?? '';
    final theater = widget.movieData['selectedTheater'] ?? '';
    final date = widget.movieData['selectedDate'] ?? '';
    final time = widget.movieData['selectedTime'] ?? '';

    for (final seatId in widget.selectedSeats) {
      try {
        final rawId = '${movieTitle}_${theater}_${date}_${time}_$seatId';
        final docId = rawId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
        await FirebaseFirestore.instance
            .collection('temporary_locks')
            .doc(docId)
            .delete();
      } catch (e) {
        print('Error clearing temporary lock: $e');
      }
    }
  }

  void _handleTimeout() {
    _clearTemporaryLocks();
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: const Color(0xFF16161F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.timer_off_rounded, color: Colors.redAccent, size: 48),
                ),
                const SizedBox(height: 20),
                const Text(
                  'GIAO DỊCH HẾT HẠN',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Thời gian giao dịch thanh toán đã hết (5 phút). Ghế của bạn đã được giải phóng.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    child: const Text('QUAY VỀ TRANG CHỦ', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _applyVoucherCode() async {
    final code = _voucherController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _voucherError = 'Vui lòng nhập mã giảm giá!');
      return;
    }

    setState(() { _voucherError = null; });

    try {
      final snap = await FirebaseFirestore.instance
          .collection('promotions')
          .where('code', isEqualTo: code)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        setState(() {
          _voucherError = 'Mã giảm giá không hợp lệ hoặc đã hết hạn!';
          _discountAmount = 0;
          _appliedVoucher = null;
        });
        return;
      }

      final promo = snap.docs.first.data();
      final int discount = (promo['discount'] as num? ?? 0).toInt();
      setState(() {
        _discountAmount = discount;
        _appliedVoucher = code;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Áp dụng thành công: ${promo['title']} - giảm ${discount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} đ'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() => _voucherError = 'Lỗi kiểm tra mã: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _voucherController.dispose();
    _clearTemporaryLocks(); // Xóa giữ ghế tạm thời nếu thoát đột ngột
    super.dispose();
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: const Color(0xFF16161F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.lightGreenAccent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: Colors.lightGreenAccent, size: 48),
                ),
                const SizedBox(height: 20),
                const Text(
                  'THANH TOÁN THÀNH CÔNG',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'Giao dịch của bạn đã hoàn tất. Vé xem phim đã được chuyển vào kho vé của bạn thành công!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (context) => const MyTicketsScreen()),
                        (route) => route.isFirst,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    child: const Text('XEM KHO VÉ', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTermsAndConditions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16161F),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ĐIỀU KHOẢN ĐẶT VÉ & HOÀN TIỀN',
                style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5),
              ),
              const SizedBox(height: 16),
              const Text(
                '1. Khách hàng được phép hủy vé và hoàn tiền 100% về tài khoản/ví Stella trước giờ chiếu phim ít nhất 30 phút.\n\n'
                '2. Vé sau khi đã được quét kiểm tra tại quầy hoặc quá giờ chiếu sẽ không được hoàn trả dưới bất kỳ hình thức nào.\n\n'
                '3. Stella Cinema cam kết bảo mật thông tin tài khoản và giao dịch thanh toán của khách hàng.\n\n'
                '4. Vé xem phim điện tử QR Code trên ứng dụng có giá trị nhận vé trực tiếp tại quầy check-in tự động.',
                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 45,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                  child: const Text('ĐẠ ĐỒNG Ý', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  void _handleConfirmPayment() {
    // 1. Sinh mã OTP bảo mật giả lập gửi tới email người dùng (Mục 7)
    final String generatedOtp = (100000 + (DateTime.now().microsecondsSinceEpoch % 900000)).toString();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🔑 [Stella Pay OTP]: Mã xác thực giao dịch của bạn là: $generatedOtp'),
        backgroundColor: Colors.amber,
        duration: const Duration(seconds: 15),
      ),
    );

    final otpController = TextEditingController();
    String? otpError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF16161F),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.security_rounded, color: Colors.amber, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'XÁC THỰC MÃ OTP',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Để đảm bảo an toàn giao dịch, vui lòng nhập mã OTP 6 số đã được gửi tới Email đăng ký của bạn.',
                    style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 15, letterSpacing: 4),
                    maxLength: 6,
                    decoration: InputDecoration(
                      hintText: '      ******',
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: const Color(0xFF0F0F13),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      errorText: otpError,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('HỦY BỎ', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                ElevatedButton(
                  onPressed: () {
                    final enteredOtp = otpController.text.trim();
                    if (enteredOtp == generatedOtp) {
                      Navigator.pop(dialogContext); // Đóng dialog OTP
                      _executePayment(); // Thực hiện thanh toán thực tế!
                    } else {
                      setDialogState(() {
                        otpError = 'Mã OTP xác thực không đúng!';
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('XÁC NHẬN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _executePayment() async {
    final user = FirebaseAuth.instance.currentUser;
    final finalPrice = (widget.totalPrice - _discountAmount) < 0 ? 0 : (widget.totalPrice - _discountAmount);

    _timer?.cancel(); // Dừng bộ đếm ngược
    setState(() => _isProcessing = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.amber)),
    );

    try {
      // 1. Kiểm tra ví Stella Wallet nếu dùng phương thức Ví
      if (_selectedPaymentMethod == 'wallet') {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user?.uid).get();
        final int balance = userDoc.data()?['wallet_balance'] ?? 0;
        if (balance < finalPrice) {
          if (mounted) {
            Navigator.pop(context); // Tắt loading
            setState(() => _isProcessing = false);
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF16161F),
                title: const Text('SỐ DƯ KHÔNG ĐỦ', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 15)),
                content: const Text('Số dư ví Stella Wallet không đủ để thanh toán. Vui lòng nạp tiền thêm hoặc chọn chuyển khoản ngân hàng.', style: TextStyle(color: Colors.white70, fontSize: 13)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('XÁC NHẬN', style: TextStyle(color: Colors.amber))),
                ],
              ),
            );
          }
          return;
        }

        // Trừ tiền ví ảo
        await FirebaseFirestore.instance.collection('users').doc(user?.uid).update({
          'wallet_balance': balance - finalPrice,
        });
      }

      final String userEmail = user?.email ?? 'anonymous';
      final String movieTitle = widget.movieData['title'] ?? 'Phim Stella Cinema';
      final String posterUrl = widget.movieData['posterUrl'] ?? '';

      // 2. Ghi đè vé vào collection 'tickets'
      await FirebaseFirestore.instance.collection('tickets').add({
        'title': movieTitle,
        'posterUrl': posterUrl,
        'seats': widget.selectedSeats,
        'total_amount': finalPrice,
        'payment_status': 'COMPLETED',
        'created_at': Timestamp.now(),
        'combos': widget.combos,
        'voucher_code': _appliedVoucher,
        'discount_amount': _discountAmount,
        'showtime': '${widget.movieData['selectedTheater']} | ${widget.movieData['selectedDate']} | ${widget.movieData['selectedTime']}',
        'email': userEmail,
      });

      // 3. Đẩy thông báo đặt vé thành công vào collection 'notifications'
      await FirebaseFirestore.instance.collection('notifications').add({
        'title': 'ĐẶT VÉ THÀNH CÔNG 🎉',
        'body': 'Chúc mừng bạn đã đặt thành công ghế: ${widget.selectedSeats.join(", ")} cho bộ phim "$movieTitle".',
        'userEmail': userEmail,
        'type': 'ticket',
        'isRead': false,
        'createdAt': Timestamp.now(),
      });

      // 4. Giải phóng ghế đang giữ tạm thời
      _clearTemporaryLocks();

      // 5. Kích hoạt Local Push Notification nhắc lịch chiếu sau 5 giây để mô phỏng kiểm thử
      final theater = widget.movieData['selectedTheater'] ?? 'Stella Cinema';
      final date = widget.movieData['selectedDate'] ?? '';
      final time = widget.movieData['selectedTime'] ?? '';
      Future.delayed(const Duration(seconds: 5), () {
        LocalNotificationService.showNotificationPopup(
          title: '🎬 NHẮC LỊCH CHIẾU STELLA CINEMA',
          body: 'Phim "$movieTitle" của bạn sẽ khởi chiếu lúc $time ngày $date tại $theater. Chuẩn bị bắp nước thôi ní ơi! 🍿',
        );
      });

      if (!mounted) return;
      Navigator.pop(context); // Tắt xoay loading
      _showSuccessDialog(); // Hiện popup thành công
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Tắt xoay loading
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xử lý thanh toán: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String movieTitle = widget.movieData['title'] ?? 'Phim Stella Cinema';
    final int finalPrice = (widget.totalPrice - _discountAmount) < 0 ? 0 : (widget.totalPrice - _discountAmount);
    final formatFinalPrice = finalPrice.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');

    final minutes = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsRemaining % 60).toString().padLeft(2, '0');

    final user = FirebaseAuth.instance.currentUser;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
      builder: (context, userSnapshot) {
        int walletBalance = 0;
        if (userSnapshot.hasData && userSnapshot.data!.exists) {
          final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
          walletBalance = userData?['wallet_balance'] ?? 0;
        }

        return Scaffold(
          backgroundColor: const Color(0xFF0F0F13),
          appBar: AppBar(
            backgroundColor: const Color(0xFF16161F),
            elevation: 0,
            centerTitle: true,
            title: const Text('THANH TOÁN HÓA ĐƠN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // HỘP ĐẾM NGƯỢC
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  decoration: BoxDecoration(
                    color: _secondsRemaining < 60 ? Colors.redAccent.withValues(alpha: 0.1) : Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _secondsRemaining < 60 ? Colors.redAccent : Colors.amber),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.timer_rounded, color: _secondsRemaining < 60 ? Colors.redAccent : Colors.amber, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Ghế được giữ trong: $minutes:$seconds',
                        style: TextStyle(color: _secondsRemaining < 60 ? Colors.redAccent : Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // TÓM TẮT THÔNG TIN VÉ ĐÃ ĐẶT
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFF16161F), borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TỔNG HỢP VÉ & BẮP NƯỚC', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Tên phim:', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          Text(movieTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Ghế đã đặt:', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          Text(widget.selectedSeats.join(', '), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                      if (widget.combos.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('Đồ ăn bắp nước kèm theo:', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        ...widget.combos.map((combo) {
                          final title = combo['title'];
                          final qty = combo['quantity'];
                          final price = combo['price'];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('  • $title (x$qty)', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                Text('${(price * qty).toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')} đ', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              ],
                            ),
                          );
                        }),
                      ],
                      if (_discountAmount > 0) ...[
                        const Divider(color: Colors.white12, height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Giảm giá voucher:', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                            Text('-${_discountAmount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')} đ', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      ],
                      const Divider(color: Colors.white12, height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Tổng tiền thanh toán:', style: TextStyle(color: Colors.grey, fontSize: 13)),
                          Text('$formatFinalPrice đ', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 18)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // BỘ VOUCHER
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFF16161F), borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Mã giảm giá (Promo Code)', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _voucherController,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Nhập mã (STELLA50, STELLA100)...',
                                hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                                filled: true,
                                fillColor: const Color(0xFF1E1E2A),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                errorText: _voucherError,
                                errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _applyVoucherCode,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            child: const Text('ÁP DỤNG', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                      if (_appliedVoucher != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Đã áp dụng mã $_appliedVoucher thành công! Giảm -${_discountAmount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')} đ',
                          style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ]
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // PHƯƠNG THỨC THANH TOÁN SELECTOR
                const Text('PHƯƠNG THỨC THANH TOÁN', style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => setState(() => _selectedPaymentMethod = 'bank'),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161F),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedPaymentMethod == 'bank' ? Colors.amber : Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.qr_code_scanner_rounded, color: _selectedPaymentMethod == 'bank' ? Colors.amber : Colors.grey, size: 20),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text('Chuyển khoản Ngân hàng (TPBank QR)', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                        if (_selectedPaymentMethod == 'bank')
                          const Icon(Icons.check_circle_rounded, color: Colors.amber, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => setState(() => _selectedPaymentMethod = 'wallet'),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161F),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedPaymentMethod == 'wallet' ? Colors.amber : Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.account_balance_wallet_rounded, color: _selectedPaymentMethod == 'wallet' ? Colors.amber : Colors.grey, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Ví điện tử Stella Wallet', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text(
                                'Số dư ví: ${walletBalance.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')} đ',
                                style: TextStyle(
                                  color: walletBalance >= finalPrice ? Colors.lightGreenAccent : Colors.redAccent,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_selectedPaymentMethod == 'wallet')
                          const Icon(Icons.check_circle_rounded, color: Colors.amber, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // HIỂN THỊ CHI TIẾT TỪNG PHƯƠNG THỨC
                if (_selectedPaymentMethod == 'bank') ...[
                  const Text('QUÉT MÃ ĐỂ TỰ ĐỘNG LÀM LỆNH CHUYỂN TIỀN', style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 14),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: Image.network(
                        'https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=247Banking_StellaCinema_Amount_$formatFinalPrice',
                        width: 180,
                        height: 180,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 25),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFF1E1E2A), borderRadius: BorderRadius.circular(12)),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• Ngân hàng: TPBank (Ngân hàng Tiên Phong)', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.6)),
                        Text('• Số tài khoản: 0000 9999 888', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.6)),
                        Text('• Tên tài khoản: STELLA CINEMA GROUP', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.6)),
                      ],
                    ),
                  ),
                ] else ...[
                  // Giao diện thanh toán qua ví
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161F),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), shape: BoxShape.circle),
                          child: const Icon(Icons.fingerprint_rounded, color: Colors.amber, size: 54),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'THANH TOÁN MỘT CHẠM AN TOÀN',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Nhấn xác nhận bên dưới để thanh toán trực tiếp qua ví Stella Wallet. Tiền sẽ được trừ tự động và vé in tức thời.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 35),

                // ĐIỀU KHOẢN HỦY VÉ CHECKBOX
                Row(
                  children: [
                    Checkbox(
                      value: _agreedToTerms,
                      activeColor: Colors.amber,
                      checkColor: Colors.black,
                      onChanged: (val) {
                        setState(() {
                          _agreedToTerms = val ?? false;
                        });
                      },
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: _showTermsAndConditions,
                        child: const Text.rich(
                          TextSpan(
                            text: 'Tôi đồng ý với ',
                            style: TextStyle(color: Colors.white60, fontSize: 12),
                            children: [
                              TextSpan(
                                text: 'Điều khoản đặt vé & hoàn tiền',
                                style: TextStyle(color: Colors.amber, decoration: TextDecoration.underline, fontWeight: FontWeight.bold),
                              ),
                              TextSpan(text: ' của Stella Cinema.'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                // NÚT THANH TOÁN
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: (_isProcessing || !_agreedToTerms) ? null : _handleConfirmPayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      disabledBackgroundColor: Colors.white10,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: Text(
                      'XÁC NHẬN THANH TOÁN',
                      style: TextStyle(
                        color: _agreedToTerms ? Colors.black : Colors.white30,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}