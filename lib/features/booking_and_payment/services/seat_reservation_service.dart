import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants.dart';

/// Kết quả gọi [holdSeats] - null nếu giữ ghế thất bại (xem [message] và
/// [unavailableSeatIds] để biết ghế nào đã bị người khác giữ).
class HoldSeatsResult {
  final bool success;
  final String? holdToken;
  final String? message;
  final List<String> unavailableSeatIds;

  const HoldSeatsResult({
    required this.success,
    this.holdToken,
    this.message,
    this.unavailableSeatIds = const [],
  });
}

/// Giữ ghế tạm thời (5 phút) qua backend - ATOMIC thật sự (Firestore
/// transaction phía server, xem backend-payos/server.js
/// POST /showtimes/:id/seats/hold), thay cho việc client tự ghi vào
/// 'temporary_locks' trước đây (không atomic, chỉ mang tính hiển thị, 2
/// người vẫn có thể cùng "giữ được" 1 ghế do race condition đọc-rồi-ghi
/// không có transaction). Gọi hàm này khi khách bấm "Tiếp tục" sau khi chọn
/// xong ghế trên seat_booking_screen.dart - KHÔNG gọi mỗi lần tap 1 ghế.
Future<HoldSeatsResult> holdSeats({
  required String showtimeId,
  required List<String> seatIds,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return const HoldSeatsResult(success: false, message: 'Vui lòng đăng nhập');
  try {
    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('${AppConfig.paymentBackendUrl}/showtimes/$showtimeId/seats/hold'),
      headers: {
        'Content-Type': 'application/json',
        if (idToken != null) 'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({'seatIds': seatIds}),
    ).timeout(const Duration(seconds: 15));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['success'] == true) {
      return HoldSeatsResult(success: true, holdToken: data['holdToken'] as String?);
    }
    return HoldSeatsResult(
      success: false,
      message: data['message'] as String?,
      unavailableSeatIds: (data['unavailable'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  } catch (e) {
    return HoldSeatsResult(success: false, message: e.toString());
  }
}

/// Trả ghế đang giữ về AVAILABLE trước khi hết hạn tự nhiên - dùng khi khách
/// rời màn chọn ghế/huỷ giữa chừng trước khi thanh toán. Best-effort (không
/// throw) vì nếu gọi lỗi, ghế vẫn tự hết hạn sau tối đa 5 phút.
Future<void> releaseHeldSeats({required String showtimeId, required String holdToken}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  try {
    final idToken = await user.getIdToken();
    await http.post(
      Uri.parse('${AppConfig.paymentBackendUrl}/showtimes/$showtimeId/seats/release'),
      headers: {
        'Content-Type': 'application/json',
        if (idToken != null) 'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({'holdToken': holdToken}),
    ).timeout(const Duration(seconds: 10));
  } catch (_) {
    // best-effort - ghế tự hết hạn sau 5 phút nếu gọi lỗi
  }
}

/// Đọc trạng thái ghế trong transaction đang chạy (PHẢI gọi trước bất kỳ
/// transaction.set/update/delete nào khác - ràng buộc Firestore: mọi read
/// phải xảy ra trước mọi write). Xác nhận ghế đang HOLDING đúng bởi
/// [holdToken]/[userId] này - đây là bước "chốt" ghế đã giữ thành đơn hàng
/// thật, không phải bước giữ ban đầu (đã làm ở [holdSeats] qua backend).
/// Trả về false nếu bất kỳ ghế nào không hợp lệ (không tồn tại/không phải
/// đang HOLDING bởi đúng người này) - gọi ngay sau đó nên return, KHÔNG gọi
/// [bookHeldSeats].
Future<bool> areHeldSeatsValid(
  Transaction transaction, {
  required String showtimeId,
  required List<String> seatIds,
  required String holdToken,
  required String userId,
}) async {
  final seatRefs = seatIds
      .map((id) => FirebaseFirestore.instance.collection('showtimes').doc(showtimeId).collection('seats').doc(id));
  for (final ref in seatRefs) {
    final doc = await transaction.get(ref);
    if (!doc.exists) return false;
    final d = doc.data()!;
    if (d['status'] != 'HOLDING' || d['heldBy'] != userId || d['holdToken'] != holdToken) return false;
  }
  return true;
}

/// Chốt ghế đã giữ hợp lệ ([areHeldSeatsValid] đã trả về true) thành BOOKED,
/// gắn với vé vừa tạo trong CÙNG transaction - thay cho reserveSeats() cũ ghi
/// vào mảng bookedSeatIds gộp. QUAN TRỌNG: chỉ gọi SAU KHI đã xác nhận
/// [areHeldSeatsValid] VÀ mọi điều kiện khác (đủ số dư ví...) hợp lệ - lý do
/// giống hệt reserveSeats() cũ, xem cảnh báo gốc: Firestore transaction
/// commit MỌI write đã gọi miễn callback không throw, return sớm sau khi gọi
/// hàm này sẽ không rollback lại.
void bookHeldSeats(
  Transaction transaction, {
  required String showtimeId,
  required List<String> seatIds,
  required String bookingId,
}) {
  for (final seatId in seatIds) {
    final ref = FirebaseFirestore.instance.collection('showtimes').doc(showtimeId).collection('seats').doc(seatId);
    transaction.update(ref, {
      'status': 'BOOKED',
      'bookingId': bookingId,
      'version': FieldValue.increment(1),
    });
  }
}

/// Kiểm tra + đặt ghế trực tiếp (AVAILABLE -> BOOKED), KHÔNG qua bước giữ
/// (holdToken) - dành riêng cho staff bán vé tại quầy
/// (staff_walkin_sale_screen.dart), nơi vé tạo ra là COMPLETED ngay lập tức
/// (đã thu tiền mặt tại chỗ), không có giai đoạn "khách đang cân nhắc" cần
/// giữ chỗ trước. firestore.rules cho phép isStaff() ghi trực tiếp subcollection
/// này (khác user thường phải qua /seats/hold rồi mới tự "chốt" được).
/// PHẢI gọi trước bất kỳ transaction write nào khác (ràng buộc Firestore).
Future<bool> areSeatsAvailableDirect(
  Transaction transaction, {
  required String showtimeId,
  required List<String> seatIds,
}) async {
  for (final seatId in seatIds) {
    final ref = FirebaseFirestore.instance.collection('showtimes').doc(showtimeId).collection('seats').doc(seatId);
    final doc = await transaction.get(ref);
    if (!doc.exists) continue; // suất chiếu chưa có ShowtimeSeat (tạo trước Giai đoạn C) - coi như trống
    final data = doc.data()!;
    final status = data['status'];
    if (status == 'BOOKED' || status == 'UNAVAILABLE' || status == 'BLOCKED') return false;
    if (status == 'HOLDING') {
      final heldUntil = data['heldUntil'] as Timestamp?;
      final stillHeld = heldUntil == null || heldUntil.toDate().isAfter(DateTime.now());
      // Ghế đang được khách giữ thật qua app (chưa hết hạn) - staff KHÔNG được
      // bán đè, dù đang đứng trước mặt khách khác muốn mua đúng ghế đó.
      if (stillHeld) return false;
    }
  }
  return true;
}

void bookSeatsDirect(
  Transaction transaction, {
  required String showtimeId,
  required List<String> seatIds,
  required String bookingId,
}) {
  for (final seatId in seatIds) {
    final ref = FirebaseFirestore.instance.collection('showtimes').doc(showtimeId).collection('seats').doc(seatId);
    transaction.set(ref, {
      'status': 'BOOKED',
      'bookingId': bookingId,
      'holdToken': null,
      'heldBy': null,
      'heldUntil': null,
      'version': FieldValue.increment(1),
    }, SetOptions(merge: true));
  }
}
