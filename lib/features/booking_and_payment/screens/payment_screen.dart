import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'my_tickets_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../notifications/screens/notification_service.dart';
import '../../home/screens/home_screen.dart';
import '../../../core/constants.dart';
import 'age_verification_screen.dart';
import '../services/discount_service.dart';
import '../services/discount_service.dart';
import '../services/age_verification_service.dart';
import '../services/payment_service.dart';
import '../services/seat_reservation_service.dart';

class PaymentScreen extends StatefulWidget {
  final Map<String, dynamic> movieData;
  final List<String> selectedSeats;
  final int totalPrice;
  final List<Map<String, dynamic>> combos;
  final DateTime? expiryTime;

  const PaymentScreen({
    super.key,
    required this.movieData,
    required this.selectedSeats,
    required this.totalPrice,
    this.combos = const [],
    this.expiryTime,
  });

  static const String backendBaseUrl = AppConfig.paymentBackendUrl;

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

  // Vé PENDING vừa tạo (luồng PayOS) - nếu khách bỏ ngang thanh toán (bấm
  // "HỦY GIAO DỊCH", để hết giờ đếm ngược, hoặc thoát màn hình), vé PENDING
  // này phải được hủy để nhả ghế ra, nếu không seat_booking_screen.dart sẽ
  // coi ghế đó là "đã bán" vĩnh viễn (chỉ lọc theo paymentStatus != CANCELLED).
  DocumentReference<Map<String, dynamic>>? _pendingTicketRef;
  bool _paymentCompleted = false;

  Future<void> _cancelPendingTicketIfAny() async {
    final ref = _pendingTicketRef;
    if (ref == null || _paymentCompleted) return;
    _pendingTicketRef = null;
    try {
      await ref.update({'paymentStatus': 'CANCELLED'});
      // Nhả ghế đã đặt trước trong showtime_seat_status (Phase 4) - nếu không
      // làm bước này, ghế của vé PENDING bỏ ngang sẽ bị kẹt vĩnh viễn trong
      // lớp check atomic mới dù vé đã CANCELLED (khác với seat_booking_screen.dart
      // vẫn thấy ghế trống đúng vì lọc theo paymentStatus != CANCELLED).
      final showtimeId = widget.movieData['showtimeId'] as String?;
      if (showtimeId != null) {
        await releaseShowtimeSeats(showtimeId: showtimeId, seatIds: widget.selectedSeats);
      }
    } catch (e) {
      debugPrint('Không hủy được vé PENDING bỏ ngang: $e');
    }
  }

  // Automatic discounts
  int _membershipDiscountPct = 0;
  String _membershipTierName = '';
  bool _isHappyWednesday = false;
  int _autoDiscountAmount = 0;

  // Tích điểm loyalty
  int _loyaltyPoints = 0;
  bool _useLoyaltyPoints = false;
  int get _loyaltyDiscountAmount => _useLoyaltyPoints ? _loyaltyPoints * 100 : 0; // 1 point = 100 VND

  // Voucher KHÔNG cộng dồn với giảm giá tự động (hạng thành viên + Happy
  // Wednesday) - rạp thật thường không cho 1 đơn vừa áp mã vừa hưởng ưu đãi
  // thành viên. Hệ thống tự áp dụng mức nào có lợi hơn cho khách, không cộng
  // cả hai. Điểm tích lũy vẫn cộng thêm bình thường (đó là tiêu tiền/điểm
  // khách đã tích được, không phải một chương trình khuyến mãi khác).
  int get _promoDiscount => math.max(_discountAmount, _autoDiscountAmount);

  // Nâng cấp: Các phương thức thanh toán và điều khoản
  String _selectedPaymentMethod = 'bank'; // 'bank' hoặc 'wallet'
  bool _agreedToTerms = false;

  // Vé phim mác T18: nếu tuổi khai báo (birthDate lúc đăng ký) dưới 18, phải
  // xác minh CCCD thật (khai gian tuổi) mới được đặt tiếp - lưu lại số CCCD
  // đã nhập vào vé để nhân viên soát vé có thể đối chiếu tại rạp nếu cần.
  String? _verifiedCccd;

  @override
  void initState() {
    super.initState();
    _initAfterAgeGate();
  }

  Future<void> _initAfterAgeGate() async {
    final ageResult = await AgeVerificationService().checkAgeRestrictionIfNeeded(context, widget.movieData);
    if (!ageResult.canProceed) {
      if (mounted) Navigator.pop(context);
      return;
    }
    if (ageResult.verifiedCccd != null) {
      _verifiedCccd = ageResult.verifiedCccd;
    }
    _calculateAutomaticDiscounts();
    if (widget.expiryTime != null) {
      _secondsRemaining = widget.expiryTime!.difference(DateTime.now()).inSeconds;
      if (_secondsRemaining < 0) _secondsRemaining = 0;
    }
    if (_secondsRemaining > 0) {
      _startTimer();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleTimeout();
      });
    }
  }


  void _calculateAutomaticDiscounts() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;
    
    final result = await DiscountService().calculateDiscounts(
      user.email!,
      roomFormat: widget.movieData['roomFormat'] as String?,
    );
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    
    if (mounted) {
      setState(() {
        _isHappyWednesday = result.isHappyWednesday;
        _membershipTierName = result.tierName;
        _membershipDiscountPct = result.membershipPct;
        _autoDiscountAmount = (widget.totalPrice * result.totalAutoPct / 100).round();
        if (userDoc.exists) {
          final data = userDoc.data() as Map<String, dynamic>;
          _loyaltyPoints = (data['loyalty_points'] as num?)?.toInt() ?? 0;
        }
      });
    }
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
    _cancelPendingTicketIfAny();
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: const Color(0xFF0A0A0A),
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
      final result = await DiscountService().validateVoucher(
        code: code,
        totalPrice: widget.totalPrice,
        selectedTheater: widget.movieData['selectedTheater'] as String?,
      );

      if (!result.isValid) {
        setState(() {
          _voucherError = result.errorMessage;
          _discountAmount = 0;
          _appliedVoucher = null;
        });
        return;
      }

      setState(() {
        _discountAmount = result.discountAmount;
        _appliedVoucher = result.appliedCode;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Áp dụng thành công: giảm ${result.discountAmount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} đ'), backgroundColor: Colors.green),
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
    _cancelPendingTicketIfAny(); // Hủy vé PENDING nếu thoát màn hình giữa chừng
    super.dispose();
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: const Color(0xFF0A0A0A),
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
                      Navigator.pop(dialogContext); // Đóng popup
                      // Reset lại toàn bộ stack về HomeScreen, sau đó đè MyTicketsScreen lên trên
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (context) => const HomeScreen()),
                        (route) => false,
                      );
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const MyTicketsScreen()),
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
      backgroundColor: const Color(0xFF0A0A0A),
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
    // Nếu dùng Ví ảo, xử lý trực tiếp không qua PayOS
    if (_selectedPaymentMethod == 'wallet') {
      _executeWalletPayment();
      return;
    }

    // Nếu qua Ngân hàng, dùng PayOS
    _processPayOSPayment();
  }

  void _processPayOSPayment() async {
    final finalPrice = (widget.totalPrice - _promoDiscount - _loyaltyDiscountAmount) < 0 ? 0 : (widget.totalPrice - _promoDiscount - _loyaltyDiscountAmount);

    if (finalPrice <= 0) {
      _executeWalletPayment(); // Miễn phí thì duyệt luôn
      return;
    }

    _timer?.cancel();
    setState(() => _isProcessing = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.amber)),
    );

    final paymentService = PaymentService();
    final result = await paymentService.createPayOSPayment(
      finalPrice: finalPrice,
      movieData: widget.movieData,
      selectedSeats: widget.selectedSeats,
      combos: widget.combos,
      totalPrice: widget.totalPrice,
      discountAmount: _promoDiscount + _loyaltyDiscountAmount,
      appliedVoucher: _appliedVoucher,
      verifiedCccd: _verifiedCccd,
      usedLoyaltyPoints: _useLoyaltyPoints ? _loyaltyPoints : 0,
    );

    if (!mounted) return;
    Navigator.pop(context); // Tắt loading

    if (!result.success) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? 'Lỗi không xác định'), backgroundColor: Colors.red),
      );
      return;
    }

    _pendingTicketRef = result.ticketRef;

    StreamSubscription<DocumentSnapshot>? sub;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0A0A0A),
          title: const Text('QUÉT MÃ ĐỂ THANH TOÁN', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 200,
                height: 200,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: QrImageView(
                    data: result.qrCodeString ?? '',
                    version: QrVersions.auto,
                    size: 200.0,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Số tiền: ${NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(result.amountToPay ?? 0)}',
                style: const TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Mở ứng dụng ngân hàng để quét mã VietQR. Hệ thống tự động xác nhận sau khi thanh toán thành công.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              const CircularProgressIndicator(color: Colors.amber, strokeWidth: 2),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                sub?.cancel();
                Navigator.pop(dialogCtx);
                _cancelPendingTicketIfAny();
                setState(() => _isProcessing = false);
                _startTimer();
              },
              child: const Text('HỦY GIAO DỊCH', style: TextStyle(color: Colors.grey)),
            )
          ],
        );
      }
    );

    sub = result.ticketRef!.snapshots().listen((doc) async {
      if (doc.exists && doc.data()!['paymentStatus'] == 'COMPLETED') {
        sub?.cancel();
        _paymentCompleted = true;

        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }

        await paymentService.sendPayOSSuccessNotification(
          movieTitle: widget.movieData['title'] ?? 'Phim Stella Cinema',
        );

        LocalNotificationService.showNotificationPopup(
          title: 'Thanh toán PayOS thành công',
          body: 'Vé xem phim ${widget.movieData['title']} của bạn đã sẵn sàng!',
        );

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MyTicketsScreen()),
          );
        }
      }
    });
  }

  void _executeWalletPayment() async {
    final finalPrice = (widget.totalPrice - _promoDiscount - _loyaltyDiscountAmount) < 0 ? 0 : (widget.totalPrice - _promoDiscount - _loyaltyDiscountAmount);

    _timer?.cancel();
    setState(() => _isProcessing = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.amber)),
    );

    final paymentService = PaymentService();
    final result = await paymentService.executeWalletPayment(
      finalPrice: finalPrice,
      movieData: widget.movieData,
      selectedSeats: widget.selectedSeats,
      combos: widget.combos,
      totalPrice: widget.totalPrice,
      discountAmount: _promoDiscount + _loyaltyDiscountAmount,
      appliedVoucher: _appliedVoucher,
      verifiedCccd: _verifiedCccd,
      usedLoyaltyPoints: _useLoyaltyPoints ? _loyaltyPoints : 0,
    );

    if (!mounted) return;
    Navigator.pop(context); // Tắt loading

    if (!result.success) {
      setState(() => _isProcessing = false);
      if (result.message == 'INSUFFICIENT_BALANCE') {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF0A0A0A),
            title: const Text('SỐ DƯ KHÔNG ĐỦ', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 15)),
            content: const Text('Số dư ví Stella Wallet không đủ để thanh toán. Vui lòng nạp tiền thêm hoặc chọn chuyển khoản ngân hàng.', style: TextStyle(color: Colors.white70, fontSize: 13)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('XÁC NHẬN', style: TextStyle(color: Colors.amber))),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xử lý thanh toán: ${result.message}'), backgroundColor: Colors.redAccent),
        );
      }
      return;
    }

    _clearTemporaryLocks();

    final movieTitle = widget.movieData['title'] ?? '';
    final theater = widget.movieData['selectedTheater'] ?? 'Stella Cinema';
    final date = widget.movieData['selectedDate'] ?? '';
    final time = widget.movieData['selectedTime'] ?? '';

    Future.delayed(const Duration(seconds: 5), () {
      LocalNotificationService.showNotificationPopup(
        title: '🎬 NHẮC LỊCH CHIẾU STELLA CINEMA',
        body: 'Phim "$movieTitle" của bạn sẽ khởi chiếu lúc $time ngày $date tại $theater. Chuẩn bị bắp nước thôi ní ơi! 🍿',
      );
    });

    _showSuccessDialog();
  }

  @override
  Widget build(BuildContext context) {
    final String movieTitle = widget.movieData['title'] ?? 'Phim Stella Cinema';
    final int finalPrice = (widget.totalPrice - _promoDiscount - _loyaltyDiscountAmount) < 0 ? 0 : (widget.totalPrice - _promoDiscount - _loyaltyDiscountAmount);
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
          backgroundColor: const Color(0xFF000000),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0A0A0A),
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
                  decoration: BoxDecoration(color: const Color(0xFF0A0A0A), borderRadius: BorderRadius.circular(12)),
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
                      if (_autoDiscountAmount > 0) ...[
                        const Divider(color: Colors.white12, height: 16),
                        if (_isHappyWednesday)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Ưu đãi Thứ 4 Vui Vẻ:', style: TextStyle(color: Colors.lightGreenAccent, fontSize: 13)),
                              const Text('-10%', style: TextStyle(color: Colors.lightGreenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        if (_membershipDiscountPct > 0)
                           Padding(
                             padding: const EdgeInsets.only(top: 4.0),
                             child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Ưu đãi hạng $_membershipTierName:', style: const TextStyle(color: Colors.amberAccent, fontSize: 13)),
                                Text('-$_membershipDiscountPct%', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                              ],
                             ),
                           ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Giảm tự động:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                            Text('-${_autoDiscountAmount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')} đ', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
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
                        if (_autoDiscountAmount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              _discountAmount >= _autoDiscountAmount
                                  ? '(Voucher có lợi hơn nên áp dụng, không cộng dồn với giảm tự động)'
                                  : '(Giảm tự động có lợi hơn nên áp dụng, không cộng dồn với voucher)',
                              style: const TextStyle(color: Colors.white38, fontSize: 10, fontStyle: FontStyle.italic),
                            ),
                          ),
                      ],
                      if (_loyaltyDiscountAmount > 0) ...[
                        const Divider(color: Colors.white12, height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Điểm tích luỹ:', style: TextStyle(color: Colors.orangeAccent, fontSize: 13)),
                            Text('-${_loyaltyDiscountAmount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')} đ', style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 13)),
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

                // ĐIỂM TÍCH LUỸ
                if (_loyaltyPoints > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: const Color(0xFF0A0A0A), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Dùng điểm tích luỹ', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('Bạn có $_loyaltyPoints điểm (-${(_loyaltyPoints * 100).toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')} đ)', style: const TextStyle(color: Colors.orangeAccent, fontSize: 11)),
                          ],
                        ),
                        Switch(
                          value: _useLoyaltyPoints,
                          activeColor: Colors.orangeAccent,
                          onChanged: (v) => setState(() => _useLoyaltyPoints = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // BỘ VOUCHER
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFF0A0A0A), borderRadius: BorderRadius.circular(12)),
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
                                fillColor: const Color(0xFF121212),
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
                      color: const Color(0xFF0A0A0A),
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
                          child: Text('Chuyển khoản Ngân hàng (Mã VietQR)', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
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
                      color: const Color(0xFF0A0A0A),
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
                  const Text('Bạn sẽ quét mã QR tự động sau khi ấn nút XÁC NHẬN THANH TOÁN', style: TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 14),
                ] else ...[
                  // Giao diện thanh toán qua ví
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0A0A),
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
