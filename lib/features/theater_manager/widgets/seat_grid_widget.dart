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
    this.dense = false,
  });

  bool get _isMaintenance => mode == SeatGridMode.maintenance;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in layout.standardVipRowLabels) _buildSingleRow(row),
        if (layout.sweetboxRows > 0) ...[
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
          for (final row in layout.sweetboxRowLabels) _buildCoupleRow(row),
        ],
      ],
    );
  }

  Widget _buildSingleRow(String row) {
    final isVip = layout.vipRowLabels.contains(row);
    final isGold = layout.isGoldClass && isVip;
    final goldColor = kSingleLargeSeatColor;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 20,
          child: Text(row, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        ...List.generate(layout.seatsPerRow, (index) {
          final seatId = SeatGrid.singleSeatId(row, index);
          return _isMaintenance
              ? _buildMaintenanceSeat(seatId, label: '${index + 1}', isDouble: false)
              : _buildBookingSingleSeat(seatId, index: index, isVip: isVip, isGold: isGold, goldColor: goldColor);
        }),
      ],
    );
  }

  Widget _buildCoupleRow(String row) {
    final accentColor = layout.isLamour ? kCoupleSeatColor : Colors.pinkAccent;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 20,
          child: Text(row, textAlign: TextAlign.center,
              style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        ...List.generate(layout.seatsPerRow ~/ 2, (pairIndex) {
          final seatId = SeatGrid.coupleSeatId(row, pairIndex);
          return _isMaintenance
              ? _buildMaintenanceSeat(seatId, label: '${pairIndex * 2 + 1}•${pairIndex * 2 + 2}', isDouble: true)
              : _buildBookingCoupleSeat(seatId, pairIndex: pairIndex, accentColor: accentColor);
        }),
      ],
    );
  }

  Widget _buildBookingSingleSeat(String seatId,
      {required int index, required bool isVip, required bool isGold, required Color goldColor}) {
    final isSelected = selectedSeats.contains(seatId);
    final isBooked = bookedSeats.contains(seatId);
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
            : (isGold
                ? Icon(Icons.event_seat_rounded, color: labelColor, size: 20)
                : Text('${index + 1}', style: TextStyle(color: labelColor, fontSize: 10, fontWeight: FontWeight.bold))),
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
    return GestureDetector(
      onTap: onToggleBroken == null ? null : () => onToggleBroken!(seatId),
      child: Container(
        margin: EdgeInsets.all(isDouble ? 2 : 2),
        width: isDouble ? 50 : 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isBroken ? Colors.redAccent.withValues(alpha: 0.4) : const Color(0xFF222232),
          borderRadius: BorderRadius.circular(5),
          border: isBroken ? Border.all(color: Colors.redAccent) : null,
        ),
        child: isBroken
            ? const Icon(Icons.build_rounded, color: Colors.redAccent, size: 12)
            : Text(label, style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
