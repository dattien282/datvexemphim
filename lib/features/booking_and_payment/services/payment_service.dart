import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants.dart';

class PaymentResult {
  final bool success;
  final String? message;
  final String? qrCodeString;
  final int? amountToPay;
  final DocumentReference<Map<String, dynamic>>? ticketRef;

  PaymentResult({this.success = false, this.message, this.qrCodeString, this.amountToPay, this.ticketRef});
}

class PaymentService {
  static const String backendBaseUrl = AppConfig.paymentBackendUrl;

  /// Xử lý thanh toán qua Ví Stella Wallet
  Future<PaymentResult> executeWalletPayment({
    required int finalPrice,
    required Map<String, dynamic> movieData,
    required List<dynamic> selectedSeats,
    required List<Map<String, dynamic>> combos,
    required int totalPrice,
    required int discountAmount,
    required String? appliedVoucher,
    required String? verifiedCccd,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return PaymentResult(message: 'Vui lòng đăng nhập');

    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final success = await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(userRef);
        final int balance = snapshot.data()?['wallet_balance'] ?? 0;
        
        if (balance < finalPrice) return false;
        
        transaction.update(userRef, {'wallet_balance': balance - finalPrice});
        return true;
      });

      if (!success) {
        return PaymentResult(success: false, message: 'INSUFFICIENT_BALANCE');
      }

      final String userEmail = user.email ?? 'anonymous';
      final String movieTitle = movieData['title'] ?? 'Phim Stella Cinema';
      final String posterUrl = movieData['posterUrl'] ?? '';
      final String theaterName = movieData['selectedTheater'] ?? '';
      final String showDate = movieData['selectedDate'] ?? '';
      final String showTime = movieData['selectedTime'] ?? '';

      final walletTicketRef = await FirebaseFirestore.instance.collection('tickets').add({
        'userId': user.uid,
        'movieTitle': movieTitle,
        'posterUrl': posterUrl,
        'seats': selectedSeats,
        'combos': combos,
        'ticketAmount': totalPrice,
        'discountAmount': discountAmount,
        'totalAmount': finalPrice,
        'voucherCode': appliedVoucher,
        'paymentMethod': 'wallet',
        'paymentStatus': 'COMPLETED',
        'theaterName': theaterName,
        'showDate': showDate,
        'showTime': showTime,
        'showtime': '$theaterName | $showDate | $showTime',
        'email': userEmail,
        if (verifiedCccd != null) 'verifiedCccd': verifiedCccd,
        'createdAt': Timestamp.now(),
      });

      try {
        await http.post(
          Uri.parse('$backendBaseUrl/sign-ticket'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'ticketId': walletTicketRef.id}),
        ).timeout(const Duration(seconds: 8));
      } catch (e) {
        // Lỗi chữ ký không chặn luồng thanh toán ví
      }

      await FirebaseFirestore.instance.collection('notifications').add({
        'title': 'ĐẶT VÉ THÀNH CÔNG 🎉',
        'body': 'Chúc mừng bạn đã đặt thành công ghế: ${selectedSeats.join(", ")} cho bộ phim "$movieTitle".',
        'userEmail': userEmail,
        'type': 'ticket',
        'isRead': false,
        'createdAt': Timestamp.now(),
      });

      return PaymentResult(success: true, ticketRef: walletTicketRef);
    } catch (e) {
      return PaymentResult(success: false, message: e.toString());
    }
  }

  /// Xử lý tạo link thanh toán qua PayOS (Tạo vé PENDING)
  Future<PaymentResult> createPayOSPayment({
    required int finalPrice,
    required Map<String, dynamic> movieData,
    required List<dynamic> selectedSeats,
    required List<Map<String, dynamic>> combos,
    required int totalPrice,
    required int discountAmount,
    required String? appliedVoucher,
    required String? verifiedCccd,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return PaymentResult(message: 'Vui lòng đăng nhập');

    try {
      final String userEmail = user.email ?? 'anonymous';
      final String movieTitle = movieData['title'] ?? 'Phim Stella Cinema';
      final String posterUrl = movieData['posterUrl'] ?? '';
      final String theaterName = movieData['selectedTheater'] ?? '';
      final String showDate = movieData['selectedDate'] ?? '';
      final String showTime = movieData['selectedTime'] ?? '';
      final orderCode = DateTime.now().millisecondsSinceEpoch % 1000000;

      final ticketRef = await FirebaseFirestore.instance.collection('tickets').add({
        'orderCode': orderCode,
        'userId': user.uid,
        'movieTitle': movieTitle,
        'posterUrl': posterUrl,
        'seats': selectedSeats,
        'combos': combos,
        'ticketAmount': totalPrice,
        'discountAmount': discountAmount,
        'totalAmount': finalPrice,
        'voucherCode': appliedVoucher,
        'paymentMethod': 'bank',
        'paymentStatus': 'PENDING',
        'theaterName': theaterName,
        'showDate': showDate,
        'showTime': showTime,
        'showtime': '$theaterName | $showDate | $showTime',
        'email': userEmail,
        if (verifiedCccd != null) 'verifiedCccd': verifiedCccd,
        'createdAt': Timestamp.now(),
      });

      final idToken = await user.getIdToken();
      final response = await http.post(
        Uri.parse('$backendBaseUrl/create-payment-link'),
        headers: {
          'Content-Type': 'application/json',
          if (idToken != null) 'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'ticketId': ticketRef.id,
          'returnUrl': 'stella://payment-success',
          'cancelUrl': 'stella://payment-cancel',
        }),
      ).timeout(const Duration(seconds: 15));

      final resData = jsonDecode(response.body);
      if (resData['error'] != 0) {
        await ticketRef.delete();
        return PaymentResult(success: false, message: resData['message'] ?? 'Không thể tạo link thanh toán');
      }

      return PaymentResult(
        success: true,
        ticketRef: ticketRef,
        qrCodeString: resData['data']['qrCode'],
        amountToPay: resData['data']['amount'],
      );
    } catch (e) {
      return PaymentResult(success: false, message: e.toString());
    }
  }

  /// Gửi thông báo khi PayOS báo thành công (Webhook trigger)
  Future<void> sendPayOSSuccessNotification({
    required String movieTitle,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userEmail = user.email ?? 'anonymous';
    
    await FirebaseFirestore.instance.collection('notifications').add({
      'userEmail': userEmail,
      'title': '🎟️ Đặt vé thành công',
      'body': 'Thanh toán PayOS thành công cho phim $movieTitle! Chúc bạn xem phim vui vẻ.',
      'type': 'ticket',
      'isRead': false,
      'createdAt': Timestamp.now(),
    });
  }
}
