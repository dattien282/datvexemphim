import 'package:cloud_firestore/cloud_firestore.dart';

/// Đọc trạng thái ghế đã đặt của 1 suất chiếu trong tài liệu
/// `showtime_seat_status/{showtimeId}` - KHÔNG ghi gì, chỉ kiểm tra xem các
/// seatIds yêu cầu còn trống hay không. PHẢI gọi trước bất kỳ
/// transaction.set/update/delete nào khác trong cùng transaction (ràng buộc
/// của Firestore: mọi read phải xảy ra trước mọi write).
Future<bool> areSeatsAvailable(
  Transaction transaction, {
  required String showtimeId,
  required List<String> seatIds,
}) async {
  final statusRef = FirebaseFirestore.instance.collection('showtime_seat_status').doc(showtimeId);
  final snap = await transaction.get(statusRef);
  final bookedSeatIds = Set<String>.from(
      (snap.data()?['bookedSeatIds'] as List?)?.map((e) => e.toString()) ?? const []);
  return !seatIds.any(bookedSeatIds.contains);
}

/// Đánh dấu ghế đã đặt (write) trong transaction đang chạy.
///
/// QUAN TRỌNG: chỉ gọi hàm này SAU KHI đã gọi [areSeatsAvailable] và xác nhận
/// true, VÀ sau khi mọi điều kiện khác của giao dịch (VD: đủ số dư ví) cũng
/// đã được xác nhận hợp lệ - vì Firestore transaction commit MỌI write đã gọi
/// miễn hàm callback của runTransaction trả về bình thường (không throw).
/// Return sớm SAU KHI đã gọi hàm này sẽ KHÔNG rollback lại write đã gọi, nên
/// gọi hàm này quá sớm (trước khi kiểm tra xong các điều kiện khác) có thể
/// khiến ghế bị đánh dấu "đã đặt" vĩnh viễn dù giao dịch cuối cùng thất bại
/// và không có vé nào được tạo.
void reserveSeats(
  Transaction transaction, {
  required String showtimeId,
  required List<String> seatIds,
}) {
  final statusRef = FirebaseFirestore.instance.collection('showtime_seat_status').doc(showtimeId);
  transaction.set(statusRef, {'bookedSeatIds': FieldValue.arrayUnion(seatIds)}, SetOptions(merge: true));
}

/// Giải phóng ghế đã đặt trước khi vé PENDING bị huỷ trước khi hoàn tất thanh
/// toán (khách bỏ ngang - xem payment_screen.dart _cancelPendingTicketIfAny).
/// Vé hủy qua backend /cancel-ticket được giải phóng tương ứng ở
/// backend-payos/server.js.
Future<void> releaseShowtimeSeats({required String showtimeId, required List<dynamic> seatIds}) {
  return FirebaseFirestore.instance
      .collection('showtime_seat_status')
      .doc(showtimeId)
      .set({'bookedSeatIds': FieldValue.arrayRemove(seatIds)}, SetOptions(merge: true));
}
