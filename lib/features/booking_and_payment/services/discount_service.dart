import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theater_manager/screens/room_management_screen.dart' show kPremiumRoomFormats;

final discountServiceProvider = Provider((ref) => DiscountService());

class DiscountResult {
  final int membershipPct;
  final String tierName;
  final bool isHappyWednesday;
  final int totalAutoPct;

  DiscountResult({
    required this.membershipPct,
    required this.tierName,
    required this.isHappyWednesday,
    required this.totalAutoPct,
  });
}

class VoucherResult {
  final bool isValid;
  final String? errorMessage;
  final int discountAmount;
  final String? appliedCode;

  VoucherResult({
    required this.isValid,
    this.errorMessage,
    required this.discountAmount,
    this.appliedCode,
  });
}

class DiscountService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // roomFormat: định dạng phòng của suất chiếu đang đặt (nếu có). Phòng cao
  // cấp trở lên (xem kPremiumRoomFormats) không được cộng thêm ưu đãi Thứ 4,
  // vì đây đã là phân khúc giá cao hơn phòng thường.
  //
  // Lưu ý: "Happy Wednesday" ở đây cố ý dựa theo NGÀY ĐẶT VÉ (DateTime.now(),
  // giảm % trên tổng hoá đơn) - khác với ưu đãi Thứ 4 ở
  // seat_booking_screen.dart/pricing_service.dart (đồng giá 50k/100k mỗi ghế,
  // dựa theo NGÀY CỦA SUẤT CHIẾU thật - showtimeSurcharge.isWednesday). Đây là
  // 2 quy tắc nghiệp vụ khác nhau, có thể lệch nhau khi đặt vé trước cho suất
  // chiếu ở Thứ 4 tuần sau - cố tình không gộp làm một.
  Future<DiscountResult> calculateDiscounts(String userEmail, {String? roomFormat}) async {
    final isPremiumFormat = kPremiumRoomFormats.contains(roomFormat);
    bool isWednesday = DateTime.now().weekday == DateTime.wednesday && !isPremiumFormat;
    int wednesdayPct = isWednesday ? 10 : 0;

    int totalSpent = 0;
    try {
      final snapshot = await _firestore
          .collection('tickets')
          .where('email', isEqualTo: userEmail)
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['paymentStatus'] == 'COMPLETED') {
          totalSpent += (data['totalAmount'] as num?)?.toInt() ?? 0;
        }
      }
    } catch (e) {
      // Ignored for fallback
    }

    int memPct = 0;
    String tier = '';
    if (totalSpent >= 8000000) {
      tier = 'KIM CƯƠNG';
      memPct = 15;
    } else if (totalSpent >= 3000000) {
      tier = 'VÀNG VIP';
      memPct = 10;
    } else if (totalSpent >= 1000000) {
      tier = 'BẠC';
      memPct = 5;
    }

    return DiscountResult(
      membershipPct: memPct,
      tierName: tier,
      isHappyWednesday: isWednesday,
      totalAutoPct: wednesdayPct + memPct,
    );
  }

  Future<VoucherResult> validateVoucher({
    required String code, 
    required int totalPrice, 
    required String? selectedTheater
  }) async {
    final doc = await _firestore.collection('vouchers').doc(code).get();
    final promo = doc.data();

    if (!doc.exists || promo == null) return VoucherResult(isValid: false, errorMessage: 'Mã giảm giá không hợp lệ hoặc đã hết hạn!', discountAmount: 0);
    if (promo['status'] != 'active') return VoucherResult(isValid: false, errorMessage: 'Mã giảm giá đã bị tắt!', discountAmount: 0);
    
    final expiresAt = promo['expiresAt'] as Timestamp?;
    if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
      return VoucherResult(isValid: false, errorMessage: 'Mã giảm giá đã hết hạn!', discountAmount: 0);
    }
    
    final maxUses = (promo['maxUses'] as num? ?? 0).toInt();
    final currentUses = (promo['currentUses'] as num? ?? 0).toInt();
    if (maxUses > 0 && currentUses >= maxUses) {
      return VoucherResult(isValid: false, errorMessage: 'Mã giảm giá đã hết lượt sử dụng!', discountAmount: 0);
    }
    
    final String? theaterScope = promo['theaterScope'] as String?;
    if (theaterScope != null && theaterScope != selectedTheater) {
      return VoucherResult(isValid: false, errorMessage: 'Mã giảm giá chỉ áp dụng tại $theaterScope!', discountAmount: 0);
    }
    
    final int minOrder = (promo['minOrder'] as num? ?? 0).toInt();
    if (minOrder > 0 && totalPrice < minOrder) {
      return VoucherResult(isValid: false, errorMessage: 'Đơn hàng chưa đạt mức tối thiểu $minOrder đ!', discountAmount: 0);
    }

    final int discountPct = (promo['discountPercent'] as num? ?? 0).toInt();
    final int discountAmt = (promo['discountAmount'] as num? ?? 0).toInt();
    final int discount = discountPct > 0 ? (totalPrice * discountPct / 100).round() : discountAmt;
    
    return VoucherResult(
      isValid: true,
      discountAmount: discount,
      appliedCode: code,
    );
  }
}
