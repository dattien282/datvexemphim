import 'package:flutter/material.dart';
import '../../../models/room_layout.dart';
import '../../../models/seat_grid.dart';

/// Chế độ hiển thị/tương tác của sơ đồ ghế:
/// - [booking]: có khái niệm ghế đang chọn/đã bán/đang bị người khác giữ, tap
///   để chọn/bỏ chọn ghế (seat_booking_screen.dart, staff_walkin_sale_screen.dart).
/// - [maintenance]: chỉ có khái niệm ghế hỏng/bảo trì, tap để bật/tắt đánh dấu
///   hỏng (staff_seat_maintenance_screen.dart, room_management_screen.dart's
///   seat maintenance dialog).
enum SeatGridMode { booking, maintenance }

/// Loại đánh dấu đang được chỉnh sửa trong [SeatGridMode.maintenance] - quyết
/// định tap vào ghế sẽ gọi [SeatGridView.onToggleBroken] hay
/// [SeatGridView.onToggleWheelchair]. Cả 2 loại đánh dấu vẫn luôn hiển thị
/// đồng thời bất kể đang sửa loại nào (1 ghế có thể vừa hỏng vừa là ghế xe
/// lăn), chỉ có hành vi tap là đổi theo target.
enum MaintenanceTarget { broken, wheelchair }

/// Sơ đồ ghế dùng chung, thay cho 4 bản dựng UI ghế độc lập trước đây (mỗi bản
/// tự tính row label + seatId + màu sắc riêng, dễ lệch nhau khi sửa 1 chỗ mà
/// quên sửa chỗ khác). Toàn bộ màu sắc/kích thước giữ nguyên như bản gốc trong
/// seat_booking_screen.dart (bản đầy đủ tính năng nhất) để không đổi UI.
class SeatGridView extends StatelessWidget {
  final RoomLayout layout;
  final SeatGridMode mode;

  // Dùng cho mode == booking.
  final Set<String> selectedSeats;
  final Set<String> bookedSeats;
  final Map<String, String> lockedBySeatId;
  final String? currentUserKey;
  final void Function(String seatId)? onSeatTap;

  // Dùng cho mode == maintenance.
  final Set<String> brokenSeats;
  final void Function(String seatId)? onToggleBroken;
  final void Function(String seatId)? onToggleWheelchair;
  final MaintenanceTarget maintenanceTarget;

  // Ghế xe lăn - hiển thị ở CẢ 2 mode (booking: khách thấy icon xe lăn để
  // biết ghế nào dành cho người khuyết tật; maintenance: staff đánh dấu ghế
  // nào là ghế xe lăn). Không gắn với 1 roomFormat/seatLayoutKind cụ thể nào -
  // phòng nào cũng có thể có vài ghế xe lăn (xem RoomLayout.wheelchairSeats).
  final Set<String> wheelchairSeats;

  /// Sơ đồ nhỏ hơn khi nhúng trong AlertDialog có giới hạn chiều rộng.
  final bool dense;

  const SeatGridView({
    super.key,
    required this.layout,
    this.mode = SeatGridMode.booking,
    this.selectedSeats = const {},
    this.bookedSeats = const {},
    this.lockedBySeatId = const {},
    this.currentUserKey,
    this.onSeatTap,
    this.brokenSeats = const {},
    this.onToggleBroken,
    this.onToggleWheelchair,
    this.maintenanceTarget = MaintenanceTarget.broken,
    this.wheelchairSeats = const {},
    this.dense = false,
  });

  bool get _isMaintenance => mode == SeatGridMode.maintenance;

  // Vị trí chèn LỐI ĐI giữa hàng ghế - chia đôi mỗi hàng thành 2 khối trái/
  // phải, giúp khách dễ nhận biết đường di chuyển vào/ra thay vì phải đếm ghế
  // để đoán lối đi ở đâu. Cùng 1 công thức cho mọi hàng trong 1 phòng (số ghế
  // mỗi hàng không đổi giữa các hàng) nên lối đi luôn thẳng hàng dọc suốt phòng.
  int _aisleAfterIndex(int seatCount) => (seatCount / 2).ceil();

  @override
  Widget build(BuildContext context) {
    final singleRows = layout.standardVipRowLabels;
    final coupleRows = layout.sweetboxRows > 0 ? layout.sweetboxRowLabels : const <String>[];
    final hasCoupleRows = coupleRows.isNotEmpty;

    return Column(
      children: [
        for (int i = 0; i < singleRows.length; i++)
          _buildSingleRow(
            singleRows[i],
            isFirstOverall: i == 0,
            isLastOverall: !hasCoupleRows && i == singleRows.length - 1,
          ),
        if (hasCoupleRows) ...[
          SizedBox(height: dense ? 10 : 15),
          Text(
            layout.isLamour ? 'HÀNG GHẾ ĐÔI COUPLE - RIÊNG TƯ LÃNG MẠN' : 'HÀNG GHẾ ĐÔI SWEETBOX PREMIUM',
            style: TextStyle(
              color: layout.isLamour ? kCoupleSeatColor : Colors.pinkAccent,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: dense ? 4 : 8),
          for (int i = 0; i < coupleRows.length; i++)
            _buildCoupleRow(
              coupleRows[i],
              isFirstOverall: singleRows.isEmpty && i == 0,
              isLastOverall: i == coupleRows.length - 1,
            ),
        ],
      ],
    );
  }

  // Khoảng trống LỐI ĐI - viền dọc mờ để trông như 1 khoảng hở có chủ đích
  // (không phải lỗi dàn trang), kèm icon mũi tên 2 đầu hàng đầu/cuối gợi ý
  // hướng di chuyển vào/ra dọc lối đi.
  Widget _aisleGap({required double height, IconData? icon}) {
    return SizedBox(
      width: dense ? 12 : 16,
      height: height,
      child: icon != null
          ? Icon(icon, color: Colors.amber.withValues(alpha: 0.7), size: dense ? 12 : 14)
          : Center(
              child: Container(width: 1.5, height: height * 0.65, color: Colors.white.withValues(alpha: 0.14)),
            ),
    );
  }

  Widget _buildSingleRow(String row, {required bool isFirstOverall, required bool isLastOverall}) {
    final isVip = layout.vipRowLabels.contains(row);
    final isGold = layout.isGoldClass && isVip;
    final isMotion = layout.isMotionSeat;
    final goldColor = kSingleLargeSeatColor;
    final seatSize = isGold ? 40.0 : 28.0;
    final aisleAfter = _aisleAfterIndex(layout.seatsPerRow);

    final rowChildren = <Widget>[];
    for (int index = 0; index < layout.seatsPerRow; index++) {
      if (index == aisleAfter) {
        rowChildren.add(_aisleGap(
          height: seatSize,
          icon: isFirstOverall
              ? Icons.keyboard_double_arrow_down_rounded
              : (isLastOverall ? Icons.keyboard_double_arrow_up_rounded : null),
        ));
      }
      final seatId = SeatGrid.singleSeatId(row, index);
      rowChildren.add(_isMaintenance
          ? _buildMaintenanceSeat(seatId, label: '${index + 1}', isDouble: false)
          : _buildBookingSingleSeat(seatId, index: index, isVip: isVip, isGold: isGold, isMotion: isMotion, goldColor: goldColor));
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 20,
          child: Text(row, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        ...rowChildren,
      ],
    );
  }

  Widget _buildCoupleRow(String row, {required bool isFirstOverall, required bool isLastOverall}) {
    final accentColor = layout.isLamour ? kCoupleSeatColor : Colors.pinkAccent;
    final pairCount = layout.seatsPerRow ~/ 2;
    final aisleAfter = _aisleAfterIndex(pairCount);

    final rowChildren = <Widget>[];
    for (int pairIndex = 0; pairIndex < pairCount; pairIndex++) {
      if (pairIndex == aisleAfter) {
        rowChildren.add(_aisleGap(
          height: 30,
          icon: isFirstOverall
              ? Icons.keyboard_double_arrow_down_rounded
              : (isLastOverall ? Icons.keyboard_double_arrow_up_rounded : null),
        ));
      }
      final seatId = SeatGrid.coupleSeatId(row, pairIndex);
      rowChildren.add(_isMaintenance
          ? _buildMaintenanceSeat(seatId, label: '${pairIndex * 2 + 1}•${pairIndex * 2 + 2}', isDouble: true)
          : _buildBookingCoupleSeat(seatId, pairIndex: pairIndex, accentColor: accentColor));
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 20,
          child: Text(row, textAlign: TextAlign.center,
              style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        ...rowChildren,
      ],
    );
  }

  Widget _buildBookingSingleSeat(String seatId,
      {required int index, required bool isVip, required bool isGold, required bool isMotion, required Color goldColor}) {
    final isSelected = selectedSeats.contains(seatId);
    final isBooked = bookedSeats.contains(seatId);
    final isWheelchair = wheelchairSeats.contains(seatId);
    final lockedBy = lockedBySeatId[seatId];
    final isLockedByOthers = lockedBy != null && lockedBy != currentUserKey;

    Color seatColor = const Color(0xFF222232);
    Color borderColor = Colors.white.withValues(alpha: 0.05);
    Color labelColor = Colors.white70;
    if (isBooked) {
      seatColor = Colors.redAccent.withValues(alpha: 0.3);
      borderColor = Colors.redAccent;
      labelColor = Colors.redAccent;
    } else if (isLockedByOthers) {
      seatColor = Colors.grey.withValues(alpha: 0.15);
      borderColor = Colors.grey.withValues(alpha: 0.3);
    } else if (isSelected) {
      seatColor = isVip ? (isGold ? goldColor : Colors.orangeAccent) : Colors.amber;
      borderColor = Colors.white;
      labelColor = Colors.black;
    } else if (isGold) {
      seatColor = const Color(0xFF2A2415);
      borderColor = goldColor.withValues(alpha: 0.4);
      labelColor = goldColor;
    } else if (isVip) {
      seatColor = const Color(0xFF322A1E);
      borderColor = Colors.orangeAccent.withValues(alpha: 0.2);
      labelColor = Colors.orangeAccent;
    } else if (isMotion) {
      // Ghế Motion (4DX) - kích thước như Standard, chỉ tô màu xanh lá đậm
      // riêng biệt để khách biết trước đây là ghế rung/chuyển động theo phim.
      seatColor = const Color(0xFF15291A);
      borderColor = Colors.lightGreenAccent.withValues(alpha: 0.3);
      labelColor = Colors.lightGreenAccent;
    }

    final seatSize = isGold ? 40.0 : 28.0;

    return GestureDetector(
      onTap: (isBooked || onSeatTap == null) ? null : () => onSeatTap!(seatId),
      child: Container(
        margin: const EdgeInsets.all(3),
        width: seatSize,
        height: seatSize,
        decoration: BoxDecoration(
          color: seatColor,
          borderRadius: BorderRadius.circular(isGold ? 8 : 5),
          border: Border.all(color: borderColor, width: isGold ? 1.5 : 1),
        ),
        alignment: Alignment.center,
        child: isLockedByOthers
            ? const Icon(Icons.lock_rounded, color: Colors.grey, size: 12)
            : (isWheelchair
                ? Icon(Icons.accessible_rounded, color: labelColor, size: 16)
                : (isGold
                    ? Icon(Icons.event_seat_rounded, color: labelColor, size: 20)
                    : Text('${index + 1}', style: TextStyle(color: labelColor, fontSize: 10, fontWeight: FontWeight.bold)))),
      ),
    );
  }

  Widget _buildBookingCoupleSeat(String seatId, {required int pairIndex, required Color accentColor}) {
    final isSelected = selectedSeats.contains(seatId);
    final isBooked = bookedSeats.contains(seatId);
    final lockedBy = lockedBySeatId[seatId];
    final isLockedByOthers = lockedBy != null && lockedBy != currentUserKey;

    Color sweetColor = const Color(0xFF3A2232);
    Color sweetBorder = accentColor.withValues(alpha: 0.2);
    if (isBooked) {
      sweetColor = Colors.redAccent.withValues(alpha: 0.2);
      sweetBorder = Colors.redAccent;
    } else if (isLockedByOthers) {
      sweetColor = Colors.grey.withValues(alpha: 0.15);
      sweetBorder = Colors.grey.withValues(alpha: 0.3);
    } else if (isSelected) {
      sweetColor = accentColor;
      sweetBorder = Colors.white;
    }

    return GestureDetector(
      onTap: (isBooked || onSeatTap == null) ? null : () => onSeatTap!(seatId),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        width: 62,
        height: 30,
        decoration: BoxDecoration(color: sweetColor, borderRadius: BorderRadius.circular(6), border: Border.all(color: sweetBorder)),
        alignment: Alignment.center,
        child: isLockedByOthers
            ? const Icon(Icons.lock_rounded, color: Colors.grey, size: 14)
            : Text('${pairIndex * 2 + 1}•${pairIndex * 2 + 2}',
                style: TextStyle(color: isBooked ? Colors.redAccent : Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildMaintenanceSeat(String seatId, {required String label, required bool isDouble}) {
    final isBroken = brokenSeats.contains(seatId);
    final isWheelchair = wheelchairSeats.contains(seatId);
    // Cả 2 loại đánh dấu cùng hiển thị (1 ghế có thể vừa hỏng vừa xe lăn) -
    // ưu tiên hiện icon hỏng khi trùng vì "không dùng được" quan trọng hơn.
    Color bg = const Color(0xFF222232);
    Color? border;
    Widget? icon;
    if (isBroken) {
      bg = Colors.redAccent.withValues(alpha: 0.4);
      border = Colors.redAccent;
      icon = const Icon(Icons.build_rounded, color: Colors.redAccent, size: 12);
    } else if (isWheelchair) {
      bg = Colors.blueAccent.withValues(alpha: 0.25);
      border = Colors.blueAccent;
      icon = const Icon(Icons.accessible_rounded, color: Colors.blueAccent, size: 14);
    }
    final onTap = maintenanceTarget == MaintenanceTarget.wheelchair ? onToggleWheelchair : onToggleBroken;
    return GestureDetector(
      onTap: onTap == null ? null : () => onTap(seatId),
      child: Container(
        margin: EdgeInsets.all(isDouble ? 2 : 2),
        width: isDouble ? 50 : 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(5),
          border: border != null ? Border.all(color: border) : null,
        ),
        child: icon ?? Text(label, style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
