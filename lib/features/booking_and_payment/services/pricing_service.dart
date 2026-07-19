import 'package:cloud_firestore/cloud_firestore.dart';

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
  // Mức phụ thu cuối tuần thật sự áp dụng (0 nếu không phải cuối tuần) -
  // trước đây hằng số 15000 nằm cứng ở seat_booking_screen.dart, giờ đọc
  // được từ pricing_rules (PricingEngine) nên phải nằm trong kết quả này.
  final int weekendSurcharge;

  const ShowtimeSurcharge({
    required this.isWeekend,
    required this.isWednesday,
    required this.timeOfDaySurcharge,
    this.weekendSurcharge = 0,
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
    final isWeekend = showAt.weekday == DateTime.saturday || showAt.weekday == DateTime.sunday;
    return ShowtimeSurcharge(
      isWeekend: isWeekend,
      isWednesday: showAt.weekday == DateTime.wednesday,
      timeOfDaySurcharge: timeSurcharge,
      weekendSurcharge: isWeekend ? 15000 : 0,
    );
  }
}

// ── PricingEngine (Giai đoạn D) ────────────────────────────────────────────────

/// 1 luật giá trong collection `pricing_rules` - admin cấu hình được qua
/// admin_pricing_rules_screen.dart thay vì sửa code + build lại app như công
/// thức cứng cũ (ShowtimeSurcharge.fromShowAt).
///
/// Cách khớp luật: field matcher nào null = wildcard (luôn khớp). Các luật
/// CÙNG `group` loại trừ nhau (chỉ luật khớp có `priority` cao nhất được áp
/// dụng - VD group 'session' có luật theo sessionType ưu tiên cao đè luật
/// theo giờ ưu tiên thấp), các group KHÁC nhau cộng dồn (VD group 'weekend'
/// cộng thêm vào group 'session') - đúng ngữ nghĩa công thức cũ.
///
/// Server (backend-payos/server.js computeAuthoritativeAmount) đọc CÙNG
/// collection này với cùng ngữ nghĩa - đổi luật ở admin là cả giá hiển thị
/// lẫn giá trừ tiền cùng đổi theo, không lệch nhau.
class PricingRule {
  final String id;
  final String label;
  final String group;
  final int priority;
  final String adjustmentType; // 'fixed' | 'percent'
  final int adjustmentValue;
  // Matchers - null = wildcard.
  final String? sessionType;
  final List<int>? daysOfWeek; // 1=Thứ 2 ... 7=Chủ Nhật (DateTime.weekday)
  final int? startHour; // khớp khi startHour <= giờ chiếu < endHour
  final int? endHour;
  final String? theaterName;
  final DateTime? validFrom;
  final DateTime? validTo;

  const PricingRule({
    required this.id,
    required this.label,
    required this.group,
    required this.priority,
    required this.adjustmentType,
    required this.adjustmentValue,
    this.sessionType,
    this.daysOfWeek,
    this.startHour,
    this.endHour,
    this.theaterName,
    this.validFrom,
    this.validTo,
  });

  factory PricingRule.fromMap(String id, Map<String, dynamic> d) => PricingRule(
        id: id,
        label: d['label'] as String? ?? '',
        group: d['group'] as String? ?? 'default',
        priority: (d['priority'] as num? ?? 0).toInt(),
        adjustmentType: d['adjustmentType'] as String? ?? 'fixed',
        adjustmentValue: (d['adjustmentValue'] as num? ?? 0).toInt(),
        sessionType: d['sessionType'] as String?,
        daysOfWeek: (d['daysOfWeek'] as List?)?.map((e) => (e as num).toInt()).toList(),
        startHour: (d['startHour'] as num?)?.toInt(),
        endHour: (d['endHour'] as num?)?.toInt(),
        theaterName: d['theaterName'] as String?,
        validFrom: (d['validFrom'] as Timestamp?)?.toDate(),
        validTo: (d['validTo'] as Timestamp?)?.toDate(),
      );

  bool matches({required DateTime showAt, String? sessionType, String? theaterName}) {
    if (validFrom != null && showAt.isBefore(validFrom!)) return false;
    if (validTo != null && showAt.isAfter(validTo!)) return false;
    if (this.sessionType != null && this.sessionType != sessionType) return false;
    if (daysOfWeek != null && !daysOfWeek!.contains(showAt.weekday)) return false;
    if (startHour != null && showAt.hour < startHour!) return false;
    if (endHour != null && showAt.hour >= endHour!) return false;
    if (this.theaterName != null && this.theaterName != theaterName) return false;
    return true;
  }

  int apply(int basePrice) =>
      adjustmentType == 'percent' ? (basePrice * adjustmentValue) ~/ 100 : adjustmentValue;
}

class PricingEngine {
  PricingEngine._();

  static List<PricingRule>? _cache;
  static DateTime? _cacheAt;

  /// Tải luật giá active (cache 5 phút trong phiên). Trả về null nếu collection
  /// trống hoặc lỗi mạng - caller tự fallback về công thức cứng cũ
  /// (ShowtimeSurcharge.fromShowAt), đảm bảo app hoạt động y hệt trước khi
  /// pricing_rules được seed/deploy.
  static Future<List<PricingRule>?> load() async {
    if (_cache != null && _cacheAt != null && DateTime.now().difference(_cacheAt!).inMinutes < 5) {
      return _cache!.isEmpty ? null : _cache;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('pricing_rules')
          .where('status', isEqualTo: 'active')
          .get();
      _cache = snap.docs.map((d) => PricingRule.fromMap(d.id, d.data())).toList();
      _cacheAt = DateTime.now();
      return _cache!.isEmpty ? null : _cache;
    } catch (_) {
      return null;
    }
  }

  /// Tính surcharge từ luật: nhóm theo `group`, mỗi group lấy đúng 1 luật khớp
  /// có priority cao nhất, cộng dồn các group. [basePrice] chỉ dùng cho luật
  /// kiểu percent.
  static ShowtimeSurcharge resolve(
    List<PricingRule> rules, {
    required DateTime showAt,
    String? sessionType,
    String? theaterName,
    int basePrice = 0,
  }) {
    final byGroup = <String, PricingRule>{};
    for (final r in rules) {
      if (!r.matches(showAt: showAt, sessionType: sessionType, theaterName: theaterName)) continue;
      final existing = byGroup[r.group];
      if (existing == null || r.priority > existing.priority) byGroup[r.group] = r;
    }

    int weekendSurcharge = 0;
    int timeSurcharge = 0;
    byGroup.forEach((group, rule) {
      final amount = rule.apply(basePrice);
      if (group == 'weekend') {
        weekendSurcharge += amount;
      } else {
        timeSurcharge += amount;
      }
    });

    return ShowtimeSurcharge(
      isWeekend: showAt.weekday == DateTime.saturday || showAt.weekday == DateTime.sunday,
      isWednesday: showAt.weekday == DateTime.wednesday,
      timeOfDaySurcharge: timeSurcharge,
      weekendSurcharge: weekendSurcharge,
    );
  }
}
