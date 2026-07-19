import 'package:cloud_firestore/cloud_firestore.dart';

/// Model cho collection 'showtimes'. Ưu tiên đọc field 'showAt' (Timestamp);
/// nếu tài liệu cũ chưa có field này thì parse fallback từ 2 định dạng string
/// từng tồn tại trong field 'date': ISO 'yyyy-MM-dd' (ghi bởi
/// theater_manager_dashboard_screen.dart) và nhãn tiếng Việt 'Thứ 4, dd/MM'
/// (ghi bởi bản seed cũ trong lib/utils/db_updater.dart) - hai định dạng này
/// từng lẫn lộn trong cùng field khiến sort theo string bị sai.
class Showtime {
  final String id;
  final String theaterName;
  final String movieTitle;
  final String roomName;
  final String roomFormat;
  // Định dạng trình chiếu/âm thanh THẬT SỰ CHỌN cho suất này, khi phòng hỗ
  // trợ nhiều hơn 1 tổ hợp (VD phòng IMAX chiếu được cả IMAX 2D lẫn IMAX 3D)
  // - xem models/room_layout.dart RoomCapability. null cho suất chiếu cũ
  // (trước khi field này tồn tại) hoặc khi phòng chỉ có đúng 1 tổ hợp - hiển
  // thị vẫn fallback về roomFormat như cũ trong trường hợp đó.
  final String? projectionFormat;
  final String? soundFormat;
  // Chốt cứng lúc tạo suất chiếu = rooms/{id}.currentSeatMapVersionId tại
  // thời điểm đó (xem models/room_layout.dart SeatMapVersion) - đảm bảo suất
  // chiếu này luôn tra đúng sơ đồ ghế đã dùng khi bán vé, không bị ảnh hưởng
  // nếu phòng được sửa sơ đồ (thêm/bớt ghế) sau này. null cho suất chiếu tạo
  // trước khi tính năng version ra đời - seat_booking_screen.dart tự fallback
  // về tra theo tên phòng như cũ trong trường hợp đó.
  final String? seatMapVersionId;
  // Dynamic pricing (F.5): phụ thu % theo tỷ lệ lấp đầy (0/5/10), do cron
  // updateDynamicPricing ở backend-payos/server.js ghi lên - chỉ tăng không
  // giảm, suất mới luôn 0. App cộng vào giá hiển thị ở màn chọn ghế, server
  // cộng vào giá trừ tiền (computeAuthoritativeAmount) - 2 bên luôn khớp.
  final int dynamicSurchargePercent;
  // Ngôn ngữ suất chiếu ('Phụ đề'/'Lồng tiếng') - thuộc tính của SUẤT CHIẾU,
  // không phải của phòng/định dạng phòng (RoomFormatSpec), vì cùng 1 phòng có
  // thể chiếu cả 2 bản vào giờ khác nhau.
  final String language;
  // Loại suất chiếu (Morning/Late Morning/Afternoon/Prime Time/Evening/
  // Midnight/Sneak Show/First Day/Marathon/Fan Screening/Special Event) - xem
  // models/session_type.dart. Tự động suy ra lúc tạo suất chiếu (hoặc chọn
  // tay cho 3 loại đặc biệt), lưu sẵn trên showtime để không phải tính lại/
  // tra cứu ngày công chiếu phim mỗi lần hiển thị hay tính giá.
  final String sessionType;
  final DateTime? showAt;
  final int priceStandard;
  final int priceVip;
  final String status;
  // Mốc vận hành phòng chiếu (Giai đoạn G) - tách "giờ chiếu hiển thị cho
  // khách" (showAt, KHÔNG đổi ý nghĩa) khỏi "phòng thực sự bị chiếm bao lâu".
  // Trước đây toàn bộ hệ thống ngầm định 1 buffer cứng 10 phút sau khi phim
  // kết thúc (quảng cáo/dọn phòng gộp chung, không tách được), không có buffer
  // TRƯỚC giờ chiếu (quảng cáo/trailer trước phim) - 3 field dưới đây thay thế
  // con số cứng đó bằng cấu hình có thể chỉnh theo từng suất, mặc định giữ
  // NGUYÊN hành vi cũ (advertisingMinutes=0, exitBufferMinutes=10,
  // cleaningMinutes=0) để không đổi kết quả tính toán của suất chiếu cũ chưa
  // có các field này. Không lưu movieDurationMinutes trên Showtime (thuộc về
  // Movie, không phải Showtime - tránh trùng lặp/lệch dữ liệu), nên
  // contentEndAt/roomReleaseAt là HÀM nhận movieDurationMinutes làm tham số
  // thay vì getter đơn thuần.
  final int advertisingMinutes;
  final int exitBufferMinutes;
  final int cleaningMinutes;

  const Showtime({
    required this.id,
    required this.theaterName,
    required this.movieTitle,
    required this.roomName,
    required this.roomFormat,
    this.projectionFormat,
    this.soundFormat,
    this.seatMapVersionId,
    this.dynamicSurchargePercent = 0,
    required this.language,
    required this.sessionType,
    required this.showAt,
    required this.priceStandard,
    required this.priceVip,
    required this.status,
    this.advertisingMinutes = 0,
    this.exitBufferMinutes = 10,
    this.cleaningMinutes = 0,
  });

  factory Showtime.fromMap(String id, Map<String, dynamic> data) {
    final showAtTimestamp = data['showAt'] as Timestamp?;
    return Showtime(
      id: id,
      theaterName: data['theaterName'] as String? ?? '',
      movieTitle: data['movieTitle'] as String? ?? '',
      roomName: data['roomName'] as String? ?? '',
      roomFormat: data['roomFormat'] as String? ?? 'Standard',
      projectionFormat: data['projectionFormat'] as String?,
      soundFormat: data['soundFormat'] as String?,
      seatMapVersionId: data['seatMapVersionId'] as String?,
      dynamicSurchargePercent: (data['dynamicSurchargePercent'] as num? ?? 0).toInt(),
      language: data['language'] as String? ?? 'Phụ đề',
      sessionType: data['sessionType'] as String? ?? 'Standard',
      showAt: showAtTimestamp?.toDate() ?? parseLegacyDateTime(data['date'] as String?, data['time'] as String?),
      priceStandard: (data['priceStandard'] as num? ?? 90000).toInt(),
      priceVip: (data['priceVip'] as num? ?? 120000).toInt(),
      status: data['status'] as String? ?? 'active',
      advertisingMinutes: (data['advertisingMinutes'] as num? ?? 0).toInt(),
      exitBufferMinutes: (data['exitBufferMinutes'] as num? ?? 10).toInt(),
      cleaningMinutes: (data['cleaningMinutes'] as num? ?? 0).toInt(),
    );
  }

  /// Giờ chiếu hiển thị cho khách (đúng tên/ý nghĩa như bên ngoài quảng cáo)
  /// - alias ngữ nghĩa của [showAt], KHÔNG thay thế field cũ (mọi chỗ đọc
  /// 'showAt' vẫn hoạt động y hệt, tránh phải migrate hàng loạt).
  DateTime? get advertisedStartAt => showAt;

  /// Phim thật sự bắt đầu chiếu (sau đoạn quảng cáo/trailer, nếu có cấu hình).
  DateTime? get contentStartAt => advertisedStartAt?.add(Duration(minutes: advertisingMinutes));

  /// Phim kết thúc - cần biết thời lượng phim (thuộc Movie, không lưu trên
  /// Showtime) nên nhận làm tham số thay vì đọc field nội bộ.
  DateTime? contentEndAt(int movieDurationMinutes) =>
      contentStartAt?.add(Duration(minutes: movieDurationMinutes));

  /// Thời điểm phòng thật sự trống, sẵn sàng cho suất kế tiếp (đã cộng thời
  /// gian khách ra về + dọn phòng) - đây mới là mốc đúng để kiểm tra chồng
  /// giờ 2 suất cùng phòng, không phải chỉ mỗi giờ bắt đầu.
  DateTime? roomReleaseAt(int movieDurationMinutes) =>
      contentEndAt(movieDurationMinutes)?.add(Duration(minutes: exitBufferMinutes + cleaningMinutes));

  /// Parse fallback cho tài liệu cũ chưa có 'showAt'. Thử ISO 'yyyy-MM-dd'
  /// trước, rồi tới nhãn tiếng Việt 'Thứ x, dd/MM' (không có năm - suy ra năm
  /// hiện tại, hoặc năm sau nếu ngày đó đã lùi quá xa so với hôm nay, vì suất
  /// chiếu luôn nằm ở hiện tại/tương lai gần chứ không phải quá khứ xa).
  static DateTime? parseLegacyDateTime(String? dateStr, String? timeStr) {
    if (dateStr == null) return null;
    final (hour, minute) = _parseHourMinute(timeStr);

    final isoMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(dateStr.trim());
    if (isoMatch != null) {
      return DateTime(int.parse(isoMatch[1]!), int.parse(isoMatch[2]!), int.parse(isoMatch[3]!), hour, minute);
    }

    final viMatch = RegExp(r'(\d{1,2})/(\d{1,2})').firstMatch(dateStr);
    if (viMatch != null) {
      final day = int.parse(viMatch[1]!);
      final month = int.parse(viMatch[2]!);
      final now = DateTime.now();
      var candidate = DateTime(now.year, month, day, hour, minute);
      if (candidate.isBefore(now.subtract(const Duration(days: 180)))) {
        candidate = DateTime(now.year + 1, month, day, hour, minute);
      }
      return candidate;
    }

    return null;
  }

  static (int, int) _parseHourMinute(String? timeStr) {
    if (timeStr == null) return (0, 0);
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(timeStr.trim());
    if (m == null) return (0, 0);
    return (int.parse(m[1]!), int.parse(m[2]!));
  }

  /// Quy tắc 6h sáng: Các suất chiếu khuya (trước 6:00 sáng) thuộc về lịch
  /// chiếu của ngày hôm trước theo thói quen đi chơi đêm của khách hàng.
  static DateTime logicalShowDate(DateTime dt) {
    if (dt.hour < 6) {
      return dt.subtract(const Duration(days: 1));
    }
    return dt;
  }

  static String isoDate(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  static String hhmm(DateTime dt) => '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  /// Nhãn thứ trong tuần tiếng Việt, thay cho _getWeekday từng bị định nghĩa
  /// riêng trong lib/utils/db_updater.dart.
  static String vietnameseWeekday(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Thứ 2';
      case DateTime.tuesday:
        return 'Thứ 3';
      case DateTime.wednesday:
        return 'Thứ 4';
      case DateTime.thursday:
        return 'Thứ 5';
      case DateTime.friday:
        return 'Thứ 6';
      case DateTime.saturday:
        return 'Thứ 7';
      case DateTime.sunday:
        return 'Chủ Nhật';
      default:
        return '';
    }
  }
}
