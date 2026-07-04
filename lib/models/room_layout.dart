import 'package:flutter/material.dart';

/// Cách phòng chiếu sắp xếp ghế đơn/ghế lớn/ghế đôi khi seatLayoutKind khác
/// 'standard': 'allSingleLarge' (ghế đơn cỡ lớn, VD VIP/Premium/Dolby Atmos/Onyx LED
/// Cinema - dùng field vipRows để đếm số hàng) và 'allCouple' (ghế đôi, VD
/// Couple - dùng field sweetboxRows để đếm số hàng). Xem
/// kRoomFormatSpecs bên dưới để biết định dạng nào dùng kind nào.
enum SeatLayoutKind { standard, allSingleLarge, allCouple }

SeatLayoutKind seatLayoutKindFromString(String? value) {
  switch (value) {
    case 'allSingleLarge':
      return SeatLayoutKind.allSingleLarge;
    case 'allCouple':
      return SeatLayoutKind.allCouple;
    default:
      return SeatLayoutKind.standard;
  }
}

String seatLayoutKindToString(SeatLayoutKind kind) {
  switch (kind) {
    case SeatLayoutKind.allSingleLarge:
      return 'allSingleLarge';
    case SeatLayoutKind.allCouple:
      return 'allCouple';
    case SeatLayoutKind.standard:
      return 'standard';
  }
}

/// 1 định dạng phòng chiếu Stella Cinema = 1 cấu hình đầy đủ (màu, loại ghế,
/// preset số hàng ghế gợi ý, mô tả, rạp quy mô nào được mở). Đặt ở model thay
/// vì UI (room_management_screen.dart) vì đây là dữ liệu domain dùng chung
/// cho cả migration (db_updater.dart) và suy luận seatLayoutKind - tránh
/// model phải import ngược lên màn hình UI.
///
/// Ngôn ngữ (phụ đề/lồng tiếng) KHÔNG còn là 1 phần của định dạng phòng - đó
/// là thuộc tính của từng suất chiếu (xem models/showtime.dart), vì cùng 1
/// phòng IMAX có thể chiếu cả 2 bản phụ đề/lồng tiếng vào giờ khác nhau.
class RoomFormatSpec {
  final String name;
  final Color color;
  final bool isPremium;
  final SeatLayoutKind seatLayoutKind;
  final int standardRows;
  final int vipRows;
  final int sweetboxRows;
  final int seatsPerRow;
  final String hint;
  final Set<String> allowedTheaterSizes;

  const RoomFormatSpec({
    required this.name,
    required this.color,
    required this.isPremium,
    required this.seatLayoutKind,
    required this.standardRows,
    required this.vipRows,
    required this.sweetboxRows,
    required this.seatsPerRow,
    required this.hint,
    required this.allowedTheaterSizes,
  });
}

const Set<String> _kAllSizes = {'Small', 'Medium', 'Large'};
const Set<String> _kMediumUp = {'Medium', 'Large'};
const Set<String> _kLargeOnly = {'Large'};

/// Màu đại diện cho 2 kiểu ghế đặc biệt (ghế đơn cỡ lớn / ghế đôi), dùng ở
/// seat_grid_widget.dart để tô màu ghế theo KIỂU chứ không phải theo tên 1
/// định dạng cụ thể - vì nhiều định dạng khác nhau (Premium/VIP/Dolby
/// Atmos/Onyx LED) đều dùng chung kiểu ghế đơn cỡ lớn.
const Color kSingleLargeSeatColor = Color(0xFFD4AF37);
const Color kCoupleSeatColor = Colors.redAccent;

/// Toàn bộ định dạng phòng chiếu Stella Cinema hỗ trợ, kèm sức chứa thực tế
/// tham khảo theo ngành rạp chiếu phim thật (Standard 120-180 ghế, IMAX
/// 250-450 ghế...). Rạp quy mô Small chỉ mở được Standard; Medium mở thêm
/// Couple (đầu tư thấp hơn IMAX/Dolby Atmos); Large mở đủ toàn bộ định dạng
/// cao cấp. Preset standardRows/vipRows/sweetboxRows/seatsPerRow được tính để
/// tổng số ghế rơi vào khoảng sức chứa tương ứng.
const List<RoomFormatSpec> kRoomFormatSpecs = [
  RoomFormatSpec(
    name: 'Standard',
    color: Colors.blueAccent,
    isPremium: false,
    seatLayoutKind: SeatLayoutKind.standard,
    standardRows: 8, vipRows: 6, sweetboxRows: 0, seatsPerRow: 10,
    hint: 'Phòng chiếu tiêu chuẩn, ghế Thường + VIP như thông thường. Sức chứa 120-180 ghế.',
    allowedTheaterSizes: _kAllSizes,
  ),
  RoomFormatSpec(
    name: 'Couple',
    color: kCoupleSeatColor,
    isPremium: true,
    seatLayoutKind: SeatLayoutKind.allCouple,
    standardRows: 0, vipRows: 0, sweetboxRows: 4, seatsPerRow: 8,
    hint: 'Toàn bộ phòng chỉ bán theo ghế đôi (Couple Sofa). Sức chứa 20-40 ghế (10-20 ghế đôi).',
    allowedTheaterSizes: _kMediumUp,
  ),
  RoomFormatSpec(
    name: 'VIP',
    color: Colors.amber,
    isPremium: true,
    seatLayoutKind: SeatLayoutKind.allSingleLarge,
    standardRows: 0, vipRows: 5, sweetboxRows: 0, seatsPerRow: 6,
    hint: 'Ghế đơn cỡ lớn (VIP Recliner). Sức chứa 20-40 ghế.',
    allowedTheaterSizes: _kLargeOnly,
  ),
  RoomFormatSpec(
    name: 'Premium',
    color: Colors.deepPurple,
    isPremium: true,
    seatLayoutKind: SeatLayoutKind.allSingleLarge,
    standardRows: 0, vipRows: 9, sweetboxRows: 0, seatsPerRow: 8,
    hint: 'Ghế đơn cỡ lớn cao cấp (Premium Recliner). Sức chứa 60-90 ghế.',
    allowedTheaterSizes: _kLargeOnly,
  ),
  RoomFormatSpec(
    name: 'Dolby Atmos',
    color: Colors.purpleAccent,
    isPremium: true,
    seatLayoutKind: SeatLayoutKind.allSingleLarge,
    standardRows: 0, vipRows: 12, sweetboxRows: 0, seatsPerRow: 10,
    hint: 'Âm thanh vòm Dolby Atmos, ghế Premium Recliner. Sức chứa 80-150 ghế.',
    allowedTheaterSizes: _kLargeOnly,
  ),
  RoomFormatSpec(
    name: 'Onyx LED',
    color: Colors.cyanAccent,
    isPremium: true,
    seatLayoutKind: SeatLayoutKind.allSingleLarge,
    standardRows: 0, vipRows: 12, sweetboxRows: 0, seatsPerRow: 10,
    hint: 'Màn hình LED công nghệ Samsung Onyx, ghế Premium Recliner. Sức chứa 80-150 ghế.',
    allowedTheaterSizes: _kLargeOnly,
  ),
  RoomFormatSpec(
    name: 'IMAX',
    color: Colors.deepOrangeAccent,
    isPremium: true,
    seatLayoutKind: SeatLayoutKind.standard,
    standardRows: 18, vipRows: 6, sweetboxRows: 0, seatsPerRow: 14,
    hint: 'Phòng lớn, màn hình khổng lồ, ghế Standard Seat. Sức chứa 250-450 ghế.',
    allowedTheaterSizes: _kLargeOnly,
  ),
  RoomFormatSpec(
    name: 'ScreenX',
    color: Colors.indigoAccent,
    isPremium: true,
    seatLayoutKind: SeatLayoutKind.standard,
    standardRows: 10, vipRows: 4, sweetboxRows: 0, seatsPerRow: 10,
    hint: 'Màn hình chiếu 270 độ bao quanh 3 mặt tường, ghế Standard Seat. Sức chứa 100-180 ghế.',
    allowedTheaterSizes: _kLargeOnly,
  ),
  RoomFormatSpec(
    name: '4DX',
    color: Colors.lightGreenAccent,
    isPremium: true,
    seatLayoutKind: SeatLayoutKind.standard,
    standardRows: 6, vipRows: 0, sweetboxRows: 0, seatsPerRow: 8,
    hint: 'Ghế rung/chuyển động theo phim (Motion Seat). Ít hàng hơn để đảm bảo khoảng cách an toàn. Sức chứa 40-60 ghế.',
    allowedTheaterSizes: _kLargeOnly,
  ),
];

RoomFormatSpec? findRoomFormatSpec(String? format) {
  for (final spec in kRoomFormatSpecs) {
    if (spec.name == format) return spec;
  }
  return null;
}

/// Định dạng nào được phép chọn cho rạp quy mô [theaterSize]
/// ('Small'/'Medium'/'Large' - khớp field theaters.size).
List<String> roomFormatsForTheaterSize(String? theaterSize) {
  final size = theaterSize ?? 'Medium';
  return kRoomFormatSpecs.where((s) => s.allowedTheaterSizes.contains(size)).map((s) => s.name).toList();
}

/// Suy ra seatLayoutKind từ định dạng phòng, dùng làm fallback khi field
/// seatLayoutKind chưa tồn tại trên document cũ (room chưa được lưu lại từ
/// khi field này ra đời) - tránh việc phòng VIP/Premium/Couple cũ bị hiển
/// thị nhầm thành ghế thường cho tới khi ai đó bấm lưu lại.
SeatLayoutKind seatLayoutKindForFormat(String format) =>
    findRoomFormatSpec(format)?.seatLayoutKind ?? SeatLayoutKind.standard;

/// Model thay cho `Map<String,dynamic>` thô khi đọc/ghi doc trong collection
/// 'rooms'. Theo đúng pattern Theater.fromMap/toMap ở providers/theaters_provider.dart.
class RoomLayout {
  final String? docId;
  final String theaterName;
  final String roomName;
  final String roomFormat;
  final int standardRows;
  final int vipRows;
  final int sweetboxRows;
  final int seatsPerRow;
  final Set<String> brokenSeats;
  final SeatLayoutKind seatLayoutKind;

  const RoomLayout({
    this.docId,
    required this.theaterName,
    required this.roomName,
    required this.roomFormat,
    this.standardRows = 3,
    this.vipRows = 5,
    this.sweetboxRows = 2,
    this.seatsPerRow = 10,
    this.brokenSeats = const {},
    this.seatLayoutKind = SeatLayoutKind.standard,
  });

  factory RoomLayout.fromMap(String docId, Map<String, dynamic> data) {
    return RoomLayout(
      docId: docId,
      theaterName: data['theaterName'] as String? ?? '',
      roomName: data['roomName'] as String? ?? '',
      roomFormat: data['roomFormat'] as String? ?? 'Standard',
      standardRows: (data['standardRows'] as num? ?? 3).toInt(),
      vipRows: (data['vipRows'] as num? ?? 5).toInt(),
      sweetboxRows: (data['sweetboxRows'] as num? ?? 2).toInt(),
      seatsPerRow: (data['seatsPerRow'] as num? ?? 10).toInt(),
      brokenSeats: ((data['brokenSeats'] as List?) ?? []).map((e) => e.toString()).toSet(),
      // Field mới: nếu chưa có (dữ liệu cũ), suy ra từ roomFormat thay vì mặc
      // định 'standard' - tránh phòng VIP/Premium/Couple cũ hiển thị sai layout.
      seatLayoutKind: data['seatLayoutKind'] != null
          ? seatLayoutKindFromString(data['seatLayoutKind'] as String?)
          : seatLayoutKindForFormat(data['roomFormat'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toMap() => {
        'theaterName': theaterName,
        'roomName': roomName,
        'roomFormat': roomFormat,
        'standardRows': standardRows,
        'vipRows': vipRows,
        'sweetboxRows': sweetboxRows,
        'seatsPerRow': seatsPerRow,
        'brokenSeats': brokenSeats.toList(),
        'seatLayoutKind': seatLayoutKindToString(seatLayoutKind),
      };

  // Tên getter giữ nguyên từ trước (khi seatLayoutKind chỉ có 2 định dạng cụ
  // thể chỉ VIP/Couple dùng tới) - nay nhiều định dạng khác cũng dùng
  // chung 2 seatLayoutKind này (VD Premium Cinema cũng allSingleLarge,
  // Sweetbox cũng allCouple), nhưng ý nghĩa "ghế đơn cỡ lớn"/"ghế đôi" không
  // đổi nên giữ tên cũ để không phải sửa lại seat_grid_widget.dart.
  bool get isGoldClass => seatLayoutKind == SeatLayoutKind.allSingleLarge;
  bool get isLamour => seatLayoutKind == SeatLayoutKind.allCouple;

  List<String> get standardVipRowLabels =>
      List.generate(standardRows + vipRows, (i) => String.fromCharCode('A'.codeUnitAt(0) + i));

  List<String> get vipRowLabels => standardVipRowLabels.sublist(standardRows);

  List<String> get sweetboxRowLabels =>
      List.generate(sweetboxRows, (i) => String.fromCharCode('A'.codeUnitAt(0) + standardRows + vipRows + i));

  /// Tổng số ghế thực tế theo sơ đồ (không trừ ghế hỏng - ghế hỏng là trạng
  /// thái bảo trì tạm thời, không phải ghế không tồn tại).
  int get capacity => (standardRows + vipRows) * seatsPerRow + sweetboxRows * (seatsPerRow ~/ 2);
}
