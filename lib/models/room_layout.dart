import 'package:flutter/material.dart';

/// Cách phòng chiếu sắp xếp ghế đơn/ghế lớn/ghế đôi/ghế rung khi seatLayoutKind
/// khác 'standard': 'allSingleLarge' (ghế đơn cỡ lớn, VD VIP/Premium/Dolby
/// Atmos/Onyx LED Cinema - dùng field vipRows để đếm số hàng), 'allCouple'
/// (ghế đôi, VD Couple - dùng field sweetboxRows để đếm số hàng), và 'motion'
/// (ghế rung/chuyển động theo phim, VD 4DX - dùng field standardRows để đếm
/// số hàng, kích thước ghế như Standard nhưng tô màu/chú thích riêng để khách
/// biết đây là ghế Motion Seat trước khi chọn). Xem kDefaultRoomFormatSpecs bên dưới
/// để biết định dạng nào dùng kind nào.
enum SeatLayoutKind { standard, allSingleLarge, allCouple, motion }

SeatLayoutKind seatLayoutKindFromString(String? value) {
  switch (value) {
    case 'allSingleLarge':
      return SeatLayoutKind.allSingleLarge;
    case 'allCouple':
      return SeatLayoutKind.allCouple;
    case 'motion':
      return SeatLayoutKind.motion;
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
    case SeatLayoutKind.motion:
      return 'motion';
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
  // null cho 13 định dạng mặc định hardcode (kDefaultRoomFormatSpecs) - chỉ
  // định dạng admin tự tạo qua AdminRoomFormatsScreen mới có docId thật trong
  // collection 'room_formats'.
  final String? docId;
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
  // 'active' (chọn được cho phòng mới) / 'archived' (ngừng dùng cho phòng
  // mới, nhưng phòng cũ đang dùng định dạng này vẫn phải tra được - xem
  // findRoomFormatSpec tìm cả archived, roomFormatsForTheaterSize chỉ lọc active).
  final String status;

  const RoomFormatSpec({
    this.docId,
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
    this.status = 'active',
  });

  factory RoomFormatSpec.fromMap(String docId, Map<String, dynamic> data) {
    return RoomFormatSpec(
      docId: docId,
      name: data['name'] as String? ?? '',
      color: colorFromHex(data['colorHex'] as String? ?? '#42A5F5'),
      isPremium: data['isPremium'] == true,
      seatLayoutKind: seatLayoutKindFromString(data['seatLayoutKind'] as String?),
      standardRows: (data['standardRows'] as num? ?? 0).toInt(),
      vipRows: (data['vipRows'] as num? ?? 0).toInt(),
      sweetboxRows: (data['sweetboxRows'] as num? ?? 0).toInt(),
      seatsPerRow: (data['seatsPerRow'] as num? ?? 10).toInt(),
      hint: data['hint'] as String? ?? '',
      allowedTheaterSizes: ((data['allowedTheaterSizes'] as List?) ?? const ['Small', 'Medium', 'Large'])
          .map((e) => e.toString())
          .toSet(),
      status: data['status'] as String? ?? 'active',
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'colorHex': colorToHex(color),
        'isPremium': isPremium,
        'seatLayoutKind': seatLayoutKindToString(seatLayoutKind),
        'standardRows': standardRows,
        'vipRows': vipRows,
        'sweetboxRows': sweetboxRows,
        'seatsPerRow': seatsPerRow,
        'hint': hint,
        'allowedTheaterSizes': allowedTheaterSizes.toList(),
        'status': status,
      };
}

/// Lưu [Color] trên Firestore dạng hex string ('#RRGGBB') cho dễ đọc trực
/// tiếp qua Firebase Console, thay vì số nguyên ARGB khó đối chiếu bằng mắt.
Color colorFromHex(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  final value = int.tryParse(cleaned, radix: 16) ?? 0x42A5F5;
  return Color(0xFF000000 | value);
}

String colorToHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

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
const List<RoomFormatSpec> kDefaultRoomFormatSpecs = [
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
  // VIP - Laurus/Lagom: 2 dòng ghế Recliner cao cấp theo đúng cách Galaxy
  // Cinema đặt tên phòng thật (2 mẫu ghế khác nhau, mỗi mẫu là 1 phòng riêng
  // trong cùng cụm rạp - không phải 1 phòng có 2 loại ghế trộn lẫn).
  RoomFormatSpec(
    name: 'VIP - Laurus',
    color: Color(0xFFE0B15C),
    isPremium: true,
    seatLayoutKind: SeatLayoutKind.allSingleLarge,
    standardRows: 0, vipRows: 6, sweetboxRows: 0, seatsPerRow: 7,
    hint: 'Ghế Recliner Laurus - đệm da cao cấp, ngả lưng êm ái. Sức chứa 30-45 ghế.',
    allowedTheaterSizes: _kMediumUp,
  ),
  RoomFormatSpec(
    name: 'VIP - Lagom',
    color: Color(0xFF8FBFA8),
    isPremium: true,
    seatLayoutKind: SeatLayoutKind.allSingleLarge,
    standardRows: 0, vipRows: 5, sweetboxRows: 0, seatsPerRow: 6,
    hint: 'Ghế Recliner Lagom - thiết kế tối giản phong cách Bắc Âu. Sức chứa 24-36 ghế.',
    allowedTheaterSizes: _kMediumUp,
  ),
  // Gold Class: phòng chiếu siêu nhỏ, siêu sang theo đúng định dạng flagship
  // của CGV - ít hàng ghế nhất trong toàn bộ danh mục để giữ đúng cảm giác
  // "phòng riêng tư" thật của định dạng này.
  RoomFormatSpec(
    name: 'Gold Class',
    color: Color(0xFFC9A44C),
    isPremium: true,
    seatLayoutKind: SeatLayoutKind.allSingleLarge,
    standardRows: 0, vipRows: 4, sweetboxRows: 0, seatsPerRow: 6,
    hint: 'Ghế bành da thật ngả 130 độ, có chuông gọi phục vụ riêng. Sức chứa 20-30 ghế.',
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
  // Dolby Atmos/Onyx LED: đổi từ "toàn ghế Recliner cỡ lớn" sang "Ghế Thường +
  // VIP" (seatLayoutKind.standard) - đây là công nghệ ÂM THANH/MÀN HÌNH,
  // không bắt buộc đi kèm loại ghế cụ thể nào. Recliner cao cấp vẫn CÓ THỂ
  // dùng cho 1 phòng Dolby Atmos cụ thể nếu rạp muốn (chỉnh trực tiếp
  // standardRows/vipRows = 0 + seatLayoutKind = allSingleLarge cho phòng đó
  // qua room_management_screen.dart, hoặc admin sửa preset qua
  // AdminRoomFormatsScreen) - preset dưới đây chỉ là mặc định phổ biến nhất.
  RoomFormatSpec(
    name: 'Dolby Atmos',
    color: Colors.purpleAccent,
    isPremium: true,
    seatLayoutKind: SeatLayoutKind.standard,
    standardRows: 6, vipRows: 6, sweetboxRows: 0, seatsPerRow: 10,
    hint: 'Âm thanh vòm Dolby Atmos, ghế Thường + VIP. Sức chứa 80-150 ghế.',
    allowedTheaterSizes: _kLargeOnly,
  ),
  RoomFormatSpec(
    name: 'Onyx LED',
    color: Colors.cyanAccent,
    isPremium: true,
    seatLayoutKind: SeatLayoutKind.standard,
    standardRows: 6, vipRows: 6, sweetboxRows: 0, seatsPerRow: 10,
    hint: 'Màn hình LED công nghệ Samsung Onyx, ghế Thường + VIP. Sức chứa 80-150 ghế.',
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
    seatLayoutKind: SeatLayoutKind.motion,
    standardRows: 6, vipRows: 0, sweetboxRows: 0, seatsPerRow: 8,
    hint: 'Ghế rung/chuyển động theo phim (Motion Seat). Ít hàng hơn để đảm bảo khoảng cách an toàn. Sức chứa 40-60 ghế.',
    allowedTheaterSizes: _kLargeOnly,
  ),
  RoomFormatSpec(
    name: 'Starium',
    color: Colors.lightBlueAccent,
    isPremium: true,
    seatLayoutKind: SeatLayoutKind.standard,
    standardRows: 20, vipRows: 6, sweetboxRows: 0, seatsPerRow: 16,
    hint: 'Màn hình cong khổng lồ (flagship), âm thanh vòm chuẩn rạp lớn nhất hệ thống. Sức chứa 300-450 ghế.',
    allowedTheaterSizes: _kLargeOnly,
  ),
];

// Cache đồng bộ, cập nhật ngầm bởi providers/room_formats_provider.dart (qua
// updateRoomFormatCache) - cùng kỹ thuật với _geminiConfigCache ở
// backend-payos/server.js: dữ liệu THẬT SỰ nằm ở Firestore (collection
// 'room_formats', admin tự sửa được qua AdminRoomFormatsScreen), nhưng đọc
// đồng bộ (không async/không cần Riverpod `ref`) để không phải sửa lại hàng
// chục nơi gọi findRoomFormatSpec/roomFormatsForTheaterSize/... kể cả từ
// RoomLayout.fromMap() (factory constructor thuần, không có ref). Mặc định =
// kDefaultRoomFormatSpecs (13 định dạng hardcode) cho tới khi stream đầu tiên
// trả về dữ liệu - hành vi y hệt hôm nay trong lúc app vừa mở.
List<RoomFormatSpec> _liveRoomFormatSpecs = kDefaultRoomFormatSpecs;

void updateRoomFormatCache(List<RoomFormatSpec> specs) {
  if (specs.isNotEmpty) _liveRoomFormatSpecs = specs;
}

/// Đọc toàn bộ cache hiện tại (kể cả archived) - dùng khi cần liệt kê/lọc
/// theo tiêu chí khác ngoài những gì findRoomFormatSpec/roomFormatsForTheaterSize
/// đã có sẵn (VD kPremiumRoomFormats ở room_management_screen.dart).
List<RoomFormatSpec> get liveRoomFormatSpecs => _liveRoomFormatSpecs;

/// Tìm trong TOÀN BỘ cache (kể cả định dạng đã 'archived') - phòng cũ đang
/// dùng 1 định dạng đã ngừng cho tạo mới vẫn phải tra đúng layout/màu/hint.
RoomFormatSpec? findRoomFormatSpec(String? format) {
  for (final spec in _liveRoomFormatSpecs) {
    if (spec.name == format) return spec;
  }
  return null;
}

/// 1 tổ hợp (định dạng trình chiếu + định dạng âm thanh) mà 1 phòng có thể
/// chiếu. Tách khỏi [RoomFormatSpec] (vốn gộp cả loại ghế lẫn công nghệ
/// trình chiếu vào 1 tên như "IMAX"/"Dolby Atmos") - 1 phòng vật lý (VD
/// phòng IMAX) thường chiếu được cả bản 2D lẫn 3D trên cùng màn hình, nên cần
/// là 1 danh sách thay vì 1 giá trị cố định. `roomFormat`/[RoomFormatSpec]
/// vẫn giữ nguyên vai trò cũ (loại ghế + phân khúc giá/khuyến mãi) - trường
/// `capabilities` này chỉ bổ sung thêm, không thay thế.
class RoomCapability {
  final String projectionFormat;
  final String soundFormat;
  final bool isDefault;

  const RoomCapability({
    required this.projectionFormat,
    required this.soundFormat,
    this.isDefault = false,
  });

  factory RoomCapability.fromMap(Map<String, dynamic> m) => RoomCapability(
        projectionFormat: m['projectionFormat'] as String? ?? '2D',
        soundFormat: m['soundFormat'] as String? ?? 'Dolby 7.1',
        isDefault: m['isDefault'] == true,
      );

  Map<String, dynamic> toMap() => {
        'projectionFormat': projectionFormat,
        'soundFormat': soundFormat,
        'isDefault': isDefault,
      };

  String get label => '$projectionFormat + $soundFormat';

  @override
  bool operator ==(Object other) =>
      other is RoomCapability && other.projectionFormat == projectionFormat && other.soundFormat == soundFormat;

  @override
  int get hashCode => Object.hash(projectionFormat, soundFormat);
}

/// Danh sách định dạng trình chiếu/âm thanh hợp lệ cho dropdown - tách khỏi
/// tên `roomFormat` cũ (loại ghế) hoàn toàn.
const List<String> kProjectionFormats = ['2D', '3D', 'IMAX 2D', 'IMAX 3D', '4DX', 'ScreenX', 'Dolby Cinema', 'Starium'];
const List<String> kSoundFormats = ['Dolby 7.1', 'Dolby Atmos', 'DTS:X', 'IMAX Sound'];

/// Suy ra bộ capability mặc định từ `roomFormat` cũ - dùng khi tạo phòng mới
/// (preset ban đầu, quản lý chỉnh lại được) và khi đọc phòng cũ chưa có field
/// `capabilities` (tương thích ngược, không cần migrate hết mới dùng được).
List<RoomCapability> defaultCapabilitiesForFormat(String roomFormat) {
  switch (roomFormat) {
    case 'IMAX':
      return const [
        RoomCapability(projectionFormat: 'IMAX 2D', soundFormat: 'IMAX Sound', isDefault: true),
        RoomCapability(projectionFormat: 'IMAX 3D', soundFormat: 'IMAX Sound'),
      ];
    case '4DX':
      return const [RoomCapability(projectionFormat: '4DX', soundFormat: 'Dolby 7.1', isDefault: true)];
    case 'ScreenX':
      return const [RoomCapability(projectionFormat: 'ScreenX', soundFormat: 'Dolby 7.1', isDefault: true)];
    case 'Dolby Atmos':
      return const [
        RoomCapability(projectionFormat: '2D', soundFormat: 'Dolby Atmos', isDefault: true),
        RoomCapability(projectionFormat: '3D', soundFormat: 'Dolby Atmos'),
      ];
    case 'Onyx LED':
      return const [RoomCapability(projectionFormat: '2D', soundFormat: 'Dolby Atmos', isDefault: true)];
    case 'Starium':
      return const [
        RoomCapability(projectionFormat: 'Starium', soundFormat: 'Dolby Atmos', isDefault: true),
        RoomCapability(projectionFormat: '3D', soundFormat: 'Dolby Atmos'),
      ];
    case 'Gold Class':
      return const [
        RoomCapability(projectionFormat: '2D', soundFormat: 'Dolby Atmos', isDefault: true),
        RoomCapability(projectionFormat: '3D', soundFormat: 'Dolby Atmos'),
      ];
    case 'VIP - Laurus':
    case 'VIP - Lagom':
      return const [RoomCapability(projectionFormat: '2D', soundFormat: 'Dolby 7.1', isDefault: true)];
    default:
      return const [
        RoomCapability(projectionFormat: '2D', soundFormat: 'Dolby 7.1', isDefault: true),
        RoomCapability(projectionFormat: '3D', soundFormat: 'Dolby 7.1'),
      ];
  }
}

/// Đọc field `capabilities` (List) từ document phòng thô; fallback về preset
/// mặc định theo `roomFormat` nếu phòng chưa có field này (dữ liệu cũ).
List<RoomCapability> parseCapabilities(dynamic raw, String roomFormat) {
  if (raw is List && raw.isNotEmpty) {
    return raw
        .whereType<Map>()
        .map((m) => RoomCapability.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }
  return defaultCapabilitiesForFormat(roomFormat);
}

/// Định dạng nào được phép chọn cho rạp quy mô [theaterSize]
/// ('Small'/'Medium'/'Large' - khớp field theaters.size). Chỉ lấy định dạng
/// 'active' - định dạng admin đã archive không còn gợi ý cho phòng MỚI, dù
/// phòng cũ đang dùng nó vẫn tra được bình thường qua findRoomFormatSpec.
List<String> roomFormatsForTheaterSize(String? theaterSize) {
  final size = theaterSize ?? 'Medium';
  return _liveRoomFormatSpecs
      .where((s) => s.status == 'active' && s.allowedTheaterSizes.contains(size))
      .map((s) => s.name)
      .toList();
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
  // Ghế xe lăn - không phải 1 "kind" riêng như motion/allSingleLarge/allCouple
  // (whole-room), mà là 1 vài ghế CỤ THỂ được đánh dấu bên trong 1 phòng bất
  // kỳ (Standard/VIP/IMAX...), giống cách brokenSeats hoạt động - chỉ đổi
  // icon/màu hiển thị của đúng ghế đó, không đổi seatLayoutKind của cả phòng.
  final Set<String> wheelchairSeats;
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
    this.wheelchairSeats = const {},
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
      wheelchairSeats: ((data['wheelchairSeats'] as List?) ?? []).map((e) => e.toString()).toSet(),
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
        'wheelchairSeats': wheelchairSeats.toList(),
        'seatLayoutKind': seatLayoutKindToString(seatLayoutKind),
      };

  // Tên getter giữ nguyên từ trước (khi seatLayoutKind chỉ có 2 định dạng cụ
  // thể chỉ VIP/Couple dùng tới) - nay nhiều định dạng khác cũng dùng
  // chung 2 seatLayoutKind này (VD Premium Cinema cũng allSingleLarge,
  // Sweetbox cũng allCouple), nhưng ý nghĩa "ghế đơn cỡ lớn"/"ghế đôi" không
  // đổi nên giữ tên cũ để không phải sửa lại seat_grid_widget.dart.
  bool get isGoldClass => seatLayoutKind == SeatLayoutKind.allSingleLarge;
  bool get isLamour => seatLayoutKind == SeatLayoutKind.allCouple;
  bool get isMotionSeat => seatLayoutKind == SeatLayoutKind.motion;

  List<String> get standardVipRowLabels =>
      List.generate(standardRows + vipRows, (i) => String.fromCharCode('A'.codeUnitAt(0) + i));

  List<String> get vipRowLabels => standardVipRowLabels.sublist(standardRows);

  List<String> get sweetboxRowLabels =>
      List.generate(sweetboxRows, (i) => String.fromCharCode('A'.codeUnitAt(0) + standardRows + vipRows + i));

  /// Tổng số ghế thực tế theo sơ đồ (không trừ ghế hỏng - ghế hỏng là trạng
  /// thái bảo trì tạm thời, không phải ghế không tồn tại).
  int get capacity => (standardRows + vipRows) * seatsPerRow + sweetboxRows * (seatsPerRow ~/ 2);
}
