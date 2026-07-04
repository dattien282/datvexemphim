import 'room_layout.dart';

/// Nguồn duy nhất cho quy ước đặt tên hàng ghế/ID ghế, thay cho 4 bản copy-paste
/// độc lập từng có ở seat_booking_screen.dart, staff_walkin_sale_screen.dart,
/// staff_seat_maintenance_screen.dart và room_management_screen.dart's
/// _SeatMaintenanceDialog. Một bug thật đã từng xảy ra khi 1 trong các bản đó
/// viết nhầm biểu thức ghép ID ghế đôi (xem lịch sử room_management_screen.dart).
class SeatGrid {
  const SeatGrid._();

  static String rowLabel(int index) => String.fromCharCode('A'.codeUnitAt(0) + index);

  static String singleSeatId(String row, int indexInRow) => '$row${indexInRow + 1}';

  static String coupleSeatId(String row, int pairIndex) => '$row${pairIndex * 2 + 1}-$row${pairIndex * 2 + 2}';

  /// Toàn bộ seatId hợp lệ của 1 phòng theo sơ đồ hiện tại (không phụ thuộc
  /// suất chiếu cụ thể) - dùng để validate seatId đầu vào hoặc tính capacity.
  static List<String> generateSeatIds(RoomLayout layout) {
    final ids = <String>[];
    for (final row in layout.standardVipRowLabels) {
      for (var i = 0; i < layout.seatsPerRow; i++) {
        ids.add(singleSeatId(row, i));
      }
    }
    for (final row in layout.sweetboxRowLabels) {
      for (var i = 0; i < layout.seatsPerRow ~/ 2; i++) {
        ids.add(coupleSeatId(row, i));
      }
    }
    return ids;
  }
}
