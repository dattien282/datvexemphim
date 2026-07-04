/// Cấu hình 1 "loại suất chiếu" (Morning/Late Morning/Afternoon/Prime
/// Time/Evening/Midnight/Sneak Show/First Day/Marathon/Fan Screening/Special
/// Event). 8 loại đầu tự động suy ra từ giờ chiếu + ngày công chiếu của phim
/// (xem detectSessionType), 3 loại cuối (isManualOnly) chỉ được gán khi
/// theater_manager chủ động chọn (không có cách nào suy luận tự động, VD
/// "Fan Screening" là quyết định kinh doanh, không phải quy luật thời gian).
class SessionTypeSpec {
  final String name;
  final String description;
  final int priceAdjustment;
  final bool isManualOnly;

  const SessionTypeSpec({
    required this.name,
    required this.description,
    required this.priceAdjustment,
    required this.isManualOnly,
  });
}

/// Thay thế công thức phụ thu sớm/khuya cũ (chỉ -10000/+10000 theo giờ) bằng
/// 1 bảng rõ ràng theo loại suất - xem pricing_service.dart ShowtimeSurcharge.
const List<SessionTypeSpec> kSessionTypeSpecs = [
  SessionTypeSpec(name: 'Morning', description: 'Suất sáng sớm (07:00–10:00)', priceAdjustment: -10000, isManualOnly: false),
  SessionTypeSpec(name: 'Late Morning', description: 'Suất cuối sáng (10:00–12:00)', priceAdjustment: -5000, isManualOnly: false),
  SessionTypeSpec(name: 'Afternoon', description: 'Suất chiều (12:00–17:00)', priceAdjustment: 0, isManualOnly: false),
  SessionTypeSpec(name: 'Prime Time', description: 'Giờ vàng (17:00–21:00)', priceAdjustment: 0, isManualOnly: false),
  SessionTypeSpec(name: 'Evening', description: 'Suất tối (21:00–24:00)', priceAdjustment: 10000, isManualOnly: false),
  SessionTypeSpec(name: 'Midnight', description: 'Suất khuya (sau 24:00)', priceAdjustment: 15000, isManualOnly: false),
  SessionTypeSpec(name: 'Sneak Show', description: 'Chiếu sớm trước ngày công chiếu', priceAdjustment: 20000, isManualOnly: false),
  SessionTypeSpec(name: 'First Day', description: 'Ngày đầu công chiếu', priceAdjustment: 15000, isManualOnly: false),
  SessionTypeSpec(name: 'Marathon', description: 'Chiếu liên tục nhiều phần', priceAdjustment: -5000, isManualOnly: true),
  SessionTypeSpec(name: 'Fan Screening', description: 'Suất dành cho fan', priceAdjustment: 10000, isManualOnly: true),
  SessionTypeSpec(name: 'Special Event', description: 'Giao lưu, công chiếu đặc biệt', priceAdjustment: 30000, isManualOnly: true),
];

SessionTypeSpec? findSessionTypeSpec(String? name) {
  for (final spec in kSessionTypeSpecs) {
    if (spec.name == name) return spec;
  }
  return null;
}

/// 3 loại chỉ được gán tay (không tham gia suy luận tự động) - dùng để lọc
/// dropdown "chọn tay" trong theater_manager_dashboard_screen.dart.
List<String> get kManualSessionTypes =>
    kSessionTypeSpecs.where((s) => s.isManualOnly).map((s) => s.name).toList();

/// Parse 'dd/MM/yyyy' (định dạng ngày công chiếu ghi bởi admin_movies_screen.dart)
/// thành DateTime. Trả về null nếu không parse được (VD ngày công chiếu để
/// trống hoặc nhập tự do không đúng định dạng).
DateTime? parseReleaseDate(String? releaseDate) {
  if (releaseDate == null) return null;
  final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(releaseDate.trim());
  if (m == null) return null;
  return DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
}

/// Tự động suy ra loại suất chiếu từ giờ chiếu thật ([showAt]) và ngày công
/// chiếu của phim ([movieReleaseDate], null nếu không xác định được) - không
/// bao giờ trả về 1 trong 3 loại isManualOnly (Marathon/Fan Screening/Special
/// Event), vì các loại đó chỉ được gán khi theater_manager chủ động chọn.
String detectSessionType(DateTime showAt, DateTime? movieReleaseDate) {
  if (movieReleaseDate != null) {
    final showDate = DateTime(showAt.year, showAt.month, showAt.day);
    final releaseDate = DateTime(movieReleaseDate.year, movieReleaseDate.month, movieReleaseDate.day);
    if (showDate.isBefore(releaseDate)) return 'Sneak Show';
    if (showDate.isAtSameMomentAs(releaseDate)) return 'First Day';
  }
  final hour = showAt.hour;
  if (hour < 7) return 'Midnight'; // trước 07:00 = "sau 24:00" của suất khuya hôm trước
  if (hour < 10) return 'Morning';
  if (hour < 12) return 'Late Morning';
  if (hour < 17) return 'Afternoon';
  if (hour < 21) return 'Prime Time';
  return 'Evening';
}
