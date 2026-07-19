import '../../../models/room_layout.dart';
import '../../../models/seat_grid.dart';

/// Logic thuần (không đụng Firestore/UI) cho 2 tính năng của màn chọn ghế:
/// - Cảnh báo "ghế lẻ" (orphan seat): chọn ghế sao cho để lại đúng 1 ghế
///   trống kẹt giữa 2 bên đã có người/tường - ghế đó gần như không bao giờ
///   bán được cho khách đi theo cặp/nhóm.
/// - Gợi ý ghế đẹp cho nhóm N người: chấm điểm các cụm ghế trống liền kề
///   theo công thức center/distance/continuity.
/// Tách thành hàm thuần để test được không cần dựng widget/Firestore.

/// Các ghế đơn lẻ còn trống sẽ bị "bỏ rơi" nếu chốt danh sách [selected]:
/// ghế trống có cả 2 phía (trái/phải trong cùng hàng) đều là ghế đã có
/// người (đã bán/đang chọn) hoặc tường. Chỉ xét hàng ghế đơn - hàng ghế đôi
/// (sweetbox) bán theo cặp nguyên khối, không có khái niệm ghế lẻ.
List<String> findOrphanSeats(RoomLayout layout, Set<String> occupied, Set<String> selected) {
  final orphans = <String>[];
  final allTaken = {...occupied, ...selected};
  for (final row in layout.standardVipRowLabels) {
    for (var i = 0; i < layout.seatsPerRow; i++) {
      final seatId = SeatGrid.singleSeatId(row, i);
      if (allTaken.contains(seatId)) continue;
      final leftBlocked = i == 0 || allTaken.contains(SeatGrid.singleSeatId(row, i - 1));
      final rightBlocked = i == layout.seatsPerRow - 1 || allTaken.contains(SeatGrid.singleSeatId(row, i + 1));
      if (!leftBlocked || !rightBlocked) continue;
      // Chỉ cảnh báo khi ghế lẻ này do CHÍNH lượt chọn hiện tại tạo ra (có ít
      // nhất 1 ghế đang chọn kề bên) - ghế lẻ có sẵn từ trước do người khác
      // đặt thì không phải lỗi của khách này, cảnh báo chỉ gây khó hiểu.
      final adjacentToSelection =
          (i > 0 && selected.contains(SeatGrid.singleSeatId(row, i - 1))) ||
          (i < layout.seatsPerRow - 1 && selected.contains(SeatGrid.singleSeatId(row, i + 1)));
      if (adjacentToSelection) orphans.add(seatId);
    }
  }
  return orphans;
}

/// Kết quả gợi ý ghế: danh sách seatId liền kề nhau trong cùng 1 hàng.
class SeatSuggestion {
  final List<String> seatIds;
  final double score;
  const SeatSuggestion(this.seatIds, this.score);
}

/// Gợi ý cụm [groupSize] ghế trống liền kề "đẹp nhất" theo công thức:
///   score = center×0.4 + distance×0.3 + continuity×0.3
/// - center: cụm càng gần chính giữa hàng càng cao.
/// - distance: hàng ở ~2/3 phòng tính từ màn hình là vị trí xem tối ưu.
/// - continuity: chọn xong không để lại ghế lẻ thì điểm cao hơn.
/// (Không có preference_score theo lịch sử người dùng - chưa có dữ liệu nền,
/// hệ số của nó dồn vào continuity.) Trả về null nếu không còn cụm nào đủ chỗ.
SeatSuggestion? suggestBestSeats(RoomLayout layout, Set<String> occupied, int groupSize) {
  if (groupSize <= 0) return null;
  final rows = layout.standardVipRowLabels;
  if (rows.isEmpty) return null;

  SeatSuggestion? best;
  final optimalRowIndex = (rows.length * 2) / 3;

  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    // Quét mọi "cửa sổ" groupSize ghế liền kề còn trống trong hàng.
    for (var start = 0; start + groupSize <= layout.seatsPerRow; start++) {
      var free = true;
      for (var k = start; k < start + groupSize; k++) {
        if (occupied.contains(SeatGrid.singleSeatId(row, k))) { free = false; break; }
      }
      if (!free) continue;

      final windowCenter = start + (groupSize - 1) / 2;
      final rowCenter = (layout.seatsPerRow - 1) / 2;
      final centerScore = 1 - ((windowCenter - rowCenter).abs() / rowCenter).clamp(0.0, 1.0);
      final distanceScore = 1 - ((r - optimalRowIndex).abs() / rows.length).clamp(0.0, 1.0);

      final seatIds = [for (var k = start; k < start + groupSize; k++) SeatGrid.singleSeatId(row, k)];
      final continuityScore = findOrphanSeats(layout, occupied, seatIds.toSet()).isEmpty ? 1.0 : 0.0;

      final score = centerScore * 0.4 + distanceScore * 0.3 + continuityScore * 0.3;
      if (best == null || score > best.score) best = SeatSuggestion(seatIds, score);
    }
  }
  return best;
}
