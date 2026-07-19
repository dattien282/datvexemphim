import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/room_layout.dart';
import '../../../models/seat_grid.dart';

/// Heatmap lấp đầy ghế theo PHÒNG (F.3): gom trạng thái ghế từ subcollection
/// showtimes/{id}/seats của tối đa 30 suất chiếu gần nhất trong phòng, tô màu
/// từng ghế theo tần suất được đặt (BOOKED) - trả lời các câu hỏi vận hành:
/// hàng nào bán chạy nhất, ghế nào gần như không bao giờ bán (cân nhắc hạ
/// giá/đổi loại ghế), giá VIP có đang quá cao không (dải VIP nguội hơn dải
/// thường là tín hiệu). Chỉ đọc dữ liệu, không ghi gì.
class SeatHeatmapScreen extends StatefulWidget {
  final String theater;
  const SeatHeatmapScreen({super.key, required this.theater});

  @override
  State<SeatHeatmapScreen> createState() => _SeatHeatmapScreenState();
}

class _SeatHeatmapScreenState extends State<SeatHeatmapScreen> {
  QueryDocumentSnapshot? _selectedRoom;
  bool _loading = false;
  // seatId -> số lần BOOKED trong các suất đã quét.
  Map<String, int> _bookedCount = {};
  int _showtimesScanned = 0;

  Future<void> _loadHeatmap() async {
    final room = _selectedRoom;
    if (room == null) return;
    setState(() {
      _loading = true;
      _bookedCount = {};
      _showtimesScanned = 0;
    });
    try {
      final roomName = (room.data() as Map<String, dynamic>)['roomName'] as String?;
      final showtimesSnap = await FirebaseFirestore.instance
          .collection('showtimes')
          .where('theaterName', isEqualTo: widget.theater)
          .where('roomName', isEqualTo: roomName)
          .limit(30)
          .get();

      final counts = <String, int>{};
      int scanned = 0;
      for (final st in showtimesSnap.docs) {
        final seats = await st.reference.collection('seats').where('status', isEqualTo: 'BOOKED').get();
        // Suất chưa có dữ liệu ghế (tạo trước Giai đoạn C) vẫn tính vào mẫu
        // quét nếu có vé - nhưng để đơn giản chỉ đếm suất có subcollection.
        if (seats.docs.isEmpty) {
          final anySeat = await st.reference.collection('seats').limit(1).get();
          if (anySeat.docs.isEmpty) continue;
        }
        scanned++;
        for (final seat in seats.docs) {
          counts[seat.id] = (counts[seat.id] ?? 0) + 1;
        }
      }
      if (mounted) {
        setState(() {
          _bookedCount = counts;
          _showtimesScanned = scanned;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _heatColor(double ratio) {
    if (ratio <= 0) return const Color(0xFF222232);
    if (ratio < 0.25) return Colors.teal.withValues(alpha: 0.45);
    if (ratio < 0.5) return Colors.greenAccent.withValues(alpha: 0.55);
    if (ratio < 0.75) return Colors.orangeAccent.withValues(alpha: 0.7);
    return Colors.redAccent.withValues(alpha: 0.85);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text('HEATMAP LẤP ĐẦY GHẾ',
            style: TextStyle(color: Colors.deepOrangeAccent, fontWeight: FontWeight.bold, fontSize: 14)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('rooms')
                  .where('theaterName', isEqualTo: widget.theater)
                  .snapshots(),
              builder: (context, snap) {
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Text('Rạp này chưa cấu hình phòng chiếu nào.',
                      style: TextStyle(color: Colors.white38, fontSize: 12));
                }
                final current = _selectedRoom != null && docs.any((d) => d.id == _selectedRoom!.id) ? _selectedRoom : null;
                return DropdownButtonFormField<QueryDocumentSnapshot>(
                  initialValue: current,
                  dropdownColor: const Color(0xFF1E1E2A),
                  isExpanded: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF16161F),
                    prefixIcon: const Icon(Icons.local_fire_department_rounded, color: Colors.deepOrangeAccent, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  ),
                  hint: const Text('Chọn phòng chiếu để xem heatmap', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  items: docs.map((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    return DropdownMenuItem(
                        value: doc, child: Text('${d['roomName'] ?? '—'}  (${d['roomFormat'] ?? 'Standard'})'));
                  }).toList(),
                  onChanged: (doc) {
                    setState(() => _selectedRoom = doc);
                    _loadHeatmap();
                  },
                );
              },
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator(color: Colors.deepOrangeAccent)))
          else if (_selectedRoom != null)
            Expanded(child: _buildHeatmap()),
        ],
      ),
    );
  }

  Widget _buildHeatmap() {
    final layout = RoomLayout.fromMap(_selectedRoom!.id, _selectedRoom!.data() as Map<String, dynamic>);
    if (_showtimesScanned == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Chưa có suất chiếu nào trong phòng này có dữ liệu ghế (ShowtimeSeat).\n\n'
            'Dữ liệu ghế được sinh khi tạo suất chiếu mới - heatmap sẽ dày lên theo thời gian.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
          ),
        ),
      );
    }

    final maxCount = _showtimesScanned;
    // Thống kê nhanh theo hàng để đọc xu hướng không cần nhìn màu.
    final rowTotals = <String, int>{};
    _bookedCount.forEach((seatId, count) {
      final row = seatId[0];
      rowTotals[row] = (rowTotals[row] ?? 0) + count;
    });
    final hottestRow = rowTotals.entries.isEmpty
        ? null
        : rowTotals.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            'Gom từ $_showtimesScanned suất chiếu gần nhất • màu càng đậm = ghế càng hay được đặt'
            '${hottestRow != null ? ' • hàng bán chạy nhất: $hottestRow' : ''}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            children: [
              _legend('0%', const Color(0xFF222232)),
              _legend('<25%', Colors.teal.withValues(alpha: 0.45)),
              _legend('<50%', Colors.greenAccent.withValues(alpha: 0.55)),
              _legend('<75%', Colors.orangeAccent.withValues(alpha: 0.7)),
              _legend('≥75%', Colors.redAccent.withValues(alpha: 0.85)),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 30),
            height: 3,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          const Text('MÀN HÌNH', style: TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 2)),
          const SizedBox(height: 16),
          for (final row in layout.standardVipRowLabels) _buildRow(row, layout, maxCount, isCouple: false),
          for (final row in layout.sweetboxRowLabels) _buildRow(row, layout, maxCount, isCouple: true),
        ],
      ),
    );
  }

  Widget _legend(String label, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
    ]);
  }

  Widget _buildRow(String row, RoomLayout layout, int maxCount, {required bool isCouple}) {
    final count = isCouple ? layout.seatsPerRow ~/ 2 : layout.seatsPerRow;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 18,
          child: Text(row, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        ...List.generate(count, (i) {
          final seatId = isCouple ? SeatGrid.coupleSeatId(row, i) : SeatGrid.singleSeatId(row, i);
          final ratio = maxCount == 0 ? 0.0 : (_bookedCount[seatId] ?? 0) / maxCount;
          return Tooltip(
            message: '$seatId: ${_bookedCount[seatId] ?? 0}/$maxCount suất',
            child: Container(
              margin: const EdgeInsets.all(2),
              width: isCouple ? 46 : 22,
              height: 22,
              decoration: BoxDecoration(color: _heatColor(ratio), borderRadius: BorderRadius.circular(4)),
            ),
          );
        }),
      ],
    );
  }
}
