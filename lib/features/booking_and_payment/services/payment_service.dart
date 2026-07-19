import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants.dart';
import 'seat_reservation_service.dart';

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
    int usedLoyaltyPoints = 0,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return PaymentResult(message: 'Vui lòng đăng nhập');

    try {
      // Id do client sinh trước (thay vì .add()) để có thể ghi vé trong cùng 1
      // transaction với việc "chốt" ghế đã giữ - đảm bảo không thể có vé mà
      // ghế đã bị người khác giành mất ngay trước đó trong tích tắc. Việc trừ
      // tiền ví KHÔNG làm ở đây (xem lý do bên dưới), chỉ tạo vé PENDING.
      final walletTicketRef = FirebaseFirestore.instance.collection('tickets').doc();
      final showtimeId = movieData['showtimeId'] as String?;
      final seatIds = selectedSeats.map((s) => s.toString()).toList();

      final String userEmail = user.email ?? 'anonymous';
      final String movieTitle = movieData['title'] ?? 'Phim Stella Cinema';
      final String posterUrl = movieData['posterUrl'] ?? '';
      final String theaterName = movieData['selectedTheater'] ?? '';
      final String showDate = movieData['selectedDate'] ?? '';
      final String showTime = movieData['selectedTime'] ?? '';
      // roomName/duration đến từ Showtime thật (showtime_selection_screen.dart)
      // hoặc dữ liệu phim gốc - lưu vào vé để hiển thị đúng phòng chiếu/thời
      // lượng thay vì hardcode ở my_tickets_screen.dart.
      final String? roomName = movieData['roomName'] as String?;
      final String? duration = movieData['duration'] as String?;

      // Giữ ghế atomic qua backend (Giai đoạn C - xem seat_reservation_service.dart
      // holdSeats) NGAY TRƯỚC KHI tạo vé, thay cho areSeatsAvailable/reserveSeats
      // cũ thao tác trên 1 document gộp showtime_seat_status. Suất chiếu chưa có
      // ShowtimeSeat (tạo trước Giai đoạn C, chưa từng sinh subcollection 'seats')
      // thì bỏ qua bước này, coi như không cần giữ ghế atomic (giữ nguyên hành vi
      // cũ cho suất chiếu cũ, tránh chặn nhầm đặt vé hợp lệ).
      String? holdToken;
      if (showtimeId != null) {
        final holdResult = await holdSeats(showtimeId: showtimeId, seatIds: seatIds);
        if (!holdResult.success) {
          return PaymentResult(success: false, message: holdResult.message ?? 'SEATS_ALREADY_BOOKED');
        }
        holdToken = holdResult.holdToken;
      }

      final reserved = await FirebaseFirestore.instance.runTransaction((transaction) async {
        final seatsValid = (showtimeId != null && holdToken != null)
            ? await areHeldSeatsValid(transaction, showtimeId: showtimeId, seatIds: seatIds, holdToken: holdToken, userId: user.uid)
            : true;
        if (!seatsValid) return false;

        if (showtimeId != null) {
          bookHeldSeats(transaction, showtimeId: showtimeId, seatIds: seatIds, bookingId: walletTicketRef.id);
        }
        transaction.set(walletTicketRef, {
          'userId': user.uid,
          'showtimeId': ?showtimeId,
          'movieTitle': movieTitle,
          'posterUrl': posterUrl,
          'seats': selectedSeats,
          'combos': combos,
          'ticketAmount': totalPrice,
          'discountAmount': discountAmount,
          'totalAmount': finalPrice,
          'voucherCode': appliedVoucher,
          'usedLoyaltyPoints': usedLoyaltyPoints,
          'paymentMethod': 'wallet',
          'paymentStatus': 'PENDING',
          'theaterName': theaterName,
          'roomName': ?roomName,
          'duration': ?duration,
          'showDate': showDate,
          'showTime': showTime,
          'showtime': '$theaterName | $showDate | $showTime',
          'email': userEmail,
          'verifiedCccd': ?verifiedCccd,
          'createdAt': Timestamp.now(),
        });
        return true;
      });

      if (!reserved) {
        if (showtimeId != null && holdToken != null) {
          await releaseHeldSeats(showtimeId: showtimeId, holdToken: holdToken);
        }
        return PaymentResult(success: false, message: 'SEATS_ALREADY_BOOKED');
      }

      // Trừ tiền ví qua backend (Admin SDK) thay vì tự trừ trực tiếp từ app -
      // rule Firestore 'users' cấm tuyệt đối user tự sửa wallet_balance qua
      // client SDK (đúng, tránh gian lận số dư tự ý). Server tự tính lại
      // authoritative amount, không tin finalPrice app gửi - giống hệt cách
      // /create-payment-link đã làm cho PayOS.
      final idToken = await user.getIdToken();
      try {
        final response = await http.post(
          Uri.parse('$backendBaseUrl/pay-wallet'),
          headers: {
            'Content-Type': 'application/json',
            if (idToken != null) 'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode({'ticketId': walletTicketRef.id}),
        ).timeout(const Duration(seconds: 15));

        final resData = jsonDecode(response.body);
        if (resData['error'] != 0) {
          await _discardPendingTicket(idToken, walletTicketRef.id);
          final message = resData['message'] ?? 'Không thể thanh toán bằng ví';
          return PaymentResult(success: false, message: message);
        }
      } catch (e) {
        await _discardPendingTicket(idToken, walletTicketRef.id);
        return PaymentResult(success: false, message: e.toString());
      }

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
    int usedLoyaltyPoints = 0,
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
      final String? roomName = movieData['roomName'] as String?;
      final String? duration = movieData['duration'] as String?;
      final orderCode = DateTime.now().millisecondsSinceEpoch % 1000000;
      final showtimeId = movieData['showtimeId'] as String?;
      final seatIds = selectedSeats.map((s) => s.toString()).toList();

      final ticketRef = FirebaseFirestore.instance.collection('tickets').doc();

      // Giữ ghế atomic qua backend trước - xem executeWalletPayment() ở trên
      // để biết lý do (giống hệt, chỉ khác luồng thanh toán).
      String? holdToken;
      if (showtimeId != null) {
        final holdResult = await holdSeats(showtimeId: showtimeId, seatIds: seatIds);
        if (!holdResult.success) {
          return PaymentResult(success: false, message: holdResult.message ?? 'SEATS_ALREADY_BOOKED');
        }
        holdToken = holdResult.holdToken;
      }

      final reserved = await FirebaseFirestore.instance.runTransaction((transaction) async {
        // Chỉ đọc trước, chưa ghi gì.
        final seatsValid = (showtimeId != null && holdToken != null)
            ? await areHeldSeatsValid(transaction, showtimeId: showtimeId, seatIds: seatIds, holdToken: holdToken, userId: user.uid)
            : true;
        if (!seatsValid) return false;

        if (showtimeId != null) {
          bookHeldSeats(transaction, showtimeId: showtimeId, seatIds: seatIds, bookingId: ticketRef.id);
        }
        transaction.set(ticketRef, {
          'orderCode': orderCode,
          'userId': user.uid,
          'showtimeId': ?showtimeId,
          'movieTitle': movieTitle,
          'posterUrl': posterUrl,
          'seats': selectedSeats,
          'combos': combos,
          'ticketAmount': totalPrice,
          'discountAmount': discountAmount,
          'totalAmount': finalPrice,
          'voucherCode': appliedVoucher,
          'usedLoyaltyPoints': usedLoyaltyPoints,
          'earnedLoyaltyPoints': finalPrice ~/ 1000,
          'paymentMethod': 'bank',
          'paymentStatus': 'PENDING',
          'theaterName': theaterName,
          'roomName': ?roomName,
          'duration': ?duration,
          'showDate': showDate,
          'showTime': showTime,
          'showtime': '$theaterName | $showDate | $showTime',
          'email': userEmail,
          'verifiedCccd': ?verifiedCccd,
          'createdAt': Timestamp.now(),
        });
        return true;
      });

      if (!reserved) {
        if (showtimeId != null && holdToken != null) {
          await releaseHeldSeats(showtimeId: showtimeId, holdToken: holdToken);
        }
        return PaymentResult(success: false, message: 'SEATS_ALREADY_BOOKED');
      }

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
        await _discardPendingTicket(idToken, ticketRef.id);
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

  /// Huỷ vé PENDING vừa tạo khi bước thanh toán thất bại, qua backend (Admin
  /// SDK) thay vì tự gọi ticketRef.delete() từ client - firestore.rules chỉ
  /// cho phép isAdmin() xoá vé nên gọi trực tiếp luôn bị permission-denied,
  /// để lại vé rác và giữ ghế vĩnh viễn. Backend xoá vé + nhả ghế atomic
  /// trong 1 transaction (xem /discard-pending-ticket ở server.js) - kể cả
  /// ghế đã chuyển BOOKED (Giai đoạn C, gắn với vé PENDING này) chứ không chỉ
  /// còn HOLDING, nên đây cũng là cách đúng để huỷ khi khách bỏ ngang màn
  /// thanh toán PayOS (xem payment_screen.dart _cancelPendingTicketIfAny) -
  /// không dùng releaseHeldSeats (chỉ áp dụng cho ghế còn HOLDING, chưa có vé).
  Future<void> _discardPendingTicket(String? idToken, String ticketId) async {
    try {
      await http.post(
        Uri.parse('$backendBaseUrl/discard-pending-ticket'),
        headers: {
          'Content-Type': 'application/json',
          if (idToken != null) 'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'ticketId': ticketId}),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      // Best-effort: nếu rollback lỗi, vé PENDING sẽ tự hết hạn/được dọn dẹp
      // sau; không nên làm lộ thêm lỗi thứ hai che mất lỗi thanh toán gốc.
    }
  }

  /// Bản public của [_discardPendingTicket] - dùng khi khách chủ động bỏ
  /// ngang màn thanh toán (thoát màn hình, bấm "Huỷ giao dịch", hết giờ đếm
  /// ngược) chứ không phải khi 1 bước thanh toán nội bộ thất bại.
  Future<void> discardPendingTicket(String ticketId) async {
    final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    await _discardPendingTicket(idToken, ticketId);
  }
}
