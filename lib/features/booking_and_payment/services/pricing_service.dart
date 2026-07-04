import '../../../models/room_layout.dart';
import '../../../models/session_type.dart';

/// Giá gốc theo hạng ghế (Thường/VIP/Sweetbox đôi), dùng chung cho
/// seat_booking_screen.dart (khách đặt qua app) và staff_walkin_sale_screen.dart
/// (bán tại quầy) - trước đây 2 nơi tính giá ghế đôi khác nhau (`priceVip * 2`
/// ở app vs `priceVip + 80000` cứng ở quầy), nên cùng 1 suất chiếu có thể ra
/// giá ghế đôi khác nhau tuỳ kênh bán vé.
int seatBasePrice({
  required String seatId,
  required RoomLayout layout,
  required int priceStandard,
  required int priceVip,
}) {
  final row = seatId[0];
  if (layout.sweetboxRowLabels.contains(row)) return priceVip * 2;
  if (layout.vipRowLabels.contains(row)) return priceVip;
  return priceStandard;
}

/// Phụ thu/giảm giá theo ngày+giờ suất chiếu thật (showAt), thay cho các bản
/// kiểm tra chuỗi hiển thị ngày rải rác trước đây trong seat_booking_screen.dart
/// (từng `.contains('13/06')` hardcode 1 ngày cụ thể, `.contains('Thứ 4')`
/// string-match trên nhãn hiển thị). Chỉ dùng cho kênh đặt vé qua app; bán tại
/// quầy (staff_walkin_sale_screen.dart) bán đúng giá suất chiếu theater_manager
/// đã cấu hình, không cộng thêm phụ thu ngày/giờ này.
class ShowtimeSurcharge {
  final bool isWeekend;
  final bool isWednesday;
  final int timeOfDaySurcharge;

  const ShowtimeSurcharge({
    required this.isWeekend,
    required this.isWednesday,
    required this.timeOfDaySurcharge,
  });

  // [sessionType]: loại suất chiếu đã lưu sẵn trên showtime (Early Bird/
  // Matinee/Prime Time/Late Night/Sneak Show/First Day/Marathon/Fan
  // Screening/Special Event - xem models/session_type.dart). Khi có, dùng
  // đúng priceAdjustment của loại đó thay cho công thức giờ cũ (chỉ phân
  // biệt sớm/khuya). Khi null (suất chiếu cũ chưa có field này), fallback về
  // công thức giờ cũ để không đổi giá vé đã bán trước đó.
  factory ShowtimeSurcharge.fromShowAt(DateTime showAt, {String? sessionType}) {
    final spec = findSessionTypeSpec(sessionType);
    int timeSurcharge;
    if (spec != null) {
      timeSurcharge = spec.priceAdjustment;
    } else if (showAt.hour < 12) {
      timeSurcharge = -10000; // Giảm giá suất sớm
    } else if (showAt.hour >= 22) {
      timeSurcharge = 10000; // Phụ thu suất khuya
    } else {
      timeSurcharge = 0;
    }
    return ShowtimeSurcharge(
      isWeekend: showAt.weekday == DateTime.saturday || showAt.weekday == DateTime.sunday,
      isWednesday: showAt.weekday == DateTime.wednesday,
      timeOfDaySurcharge: timeSurcharge,
    );
  }
}
