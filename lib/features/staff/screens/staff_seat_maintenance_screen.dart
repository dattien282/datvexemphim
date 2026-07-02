import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Đánh dấu ghế hỏng/bảo trì tạm thời cho phòng chiếu tại rạp mình phụ
/// trách - trước đây không có cách nào staff báo ghế hỏng, khách vẫn có thể
/// chọn phải ghế gãy/không dùng được. Ghế đánh dấu hỏng ở đây sẽ hiện "Đã
/// bán" (không chọn được) trong seat_booking_screen.dart và
/// staff_walkin_sale_screen.dart cho tới khi được gỡ đánh dấu.
class StaffSeatMaintenanceScreen extends StatefulWidget {
  final String? theater;
  const StaffSeatMaintenanceScreen({super.key, required this.theater});

  @override
  State<StaffSeatMaintenanceScreen> createState() => _StaffSeatMaintenanceScreenState();
}

class _StaffSeatMaintenanceScreenState extends State<StaffSeatMaintenanceScreen> {
  QueryDocumentSnapshot? _selectedRoom;

  @override
  Widget build(BuildContext context) {
    final theater = widget.theater;
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text('GHẾ HỎNG / BẢO TRÌ', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 14)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: theater == null
          ? const Center(child: Text('Tài khoản chưa được gán rạp.', style: TextStyle(color: Colors.white38)))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('rooms').where('theaterName', isEqualTo: theater).snapshots(),
                    builder: (context, snap) {
                      final docs = snap.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return const Text('Rạp này chưa cấu hình phòng chiếu nào.', style: TextStyle(color: Colors.white38, fontSize: 12));
                      }
                      final current = _selectedRoom != null && docs.any((d) => d.id == _selectedRoom!.id) ? _selectedRoom : null;
                      return DropdownButtonFormField<QueryDocumentSnapshot>(
                        value: current,
                        dropdownColor: const Color(0xFF1E1E2A),
                        isExpanded: true,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF16161F),
                          prefixIcon: const Icon(Icons.weekend_rounded, color: Colors.orangeAccent, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                        ),
                        hint: const Text('Chọn phòng chiếu', style: TextStyle(color: Colors.white38, fontSize: 12)),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        items: docs.map((doc) {
                          final d = doc.data() as Map<String, dynamic>;
                          return DropdownMenuItem(value: doc, child: Text(d['roomName'] ?? '—'));
                        }).toList(),
                        onChanged: (doc) => setState(() => _selectedRoom = doc),
                      );
                    },
                  ),
                ),
                if (_selectedRoom != null) Expanded(child: _buildSeatGrid()),
              ],
            ),
    );
  }

  Widget _buildSeatGrid() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _selectedRoom!.reference.snapshots(),
      builder: (context, snap) {
        final data = (snap.data?.data() as Map<String, dynamic>?) ?? (_selectedRoom!.data() as Map<String, dynamic>);
        final standardRows = (data['standardRows'] as num? ?? 3).toInt();
        final vipRows = (data['vipRows'] as num? ?? 5).toInt();
        final sweetboxRows = (data['sweetboxRows'] as num? ?? 2).toInt();
        final seatsPerRow = (data['seatsPerRow'] as num? ?? 10).toInt();
        final brokenSeats = ((data['brokenSeats'] as List?) ?? []).map((e) => e.toString()).toSet();

        final rowLabels = List.generate(standardRows + vipRows + sweetboxRows, (i) => String.fromCharCode('A'.codeUnitAt(0) + i));
        final sweetboxLabels = rowLabels.sublist(standardRows + vipRows);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Chạm vào ghế để đánh dấu hỏng/gỡ đánh dấu', style: TextStyle(color: Colors.white38, fontSize: 11)),
              ),
              for (final row in rowLabels.sublist(0, standardRows + vipRows))
                _buildRow(row, seatsPerRow, brokenSeats, isSweetbox: false),
              if (sweetboxRows > 0) ...[
                const SizedBox(height: 10),
                const Text('GHẾ ĐÔI', style: TextStyle(color: Colors.pinkAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                for (final row in sweetboxLabels) _buildRow(row, seatsPerRow, brokenSeats, isSweetbox: true),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildRow(String row, int seatsPerRow, Set<String> brokenSeats, {required bool isSweetbox}) {
    final count = isSweetbox ? (seatsPerRow / 2).floor() : seatsPerRow;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(width: 20, child: Text(row, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold))),
        ...List.generate(count, (i) {
          final seatId = isSweetbox ? '$row${i * 2 + 1}-$row${i * 2 + 2}' : '$row${i + 1}';
          final isBroken = brokenSeats.contains(seatId);
          return GestureDetector(
            onTap: () => _toggleBroken(seatId, isBroken),
            child: Container(
              margin: const EdgeInsets.all(2),
              width: isSweetbox ? 50 : 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isBroken ? Colors.redAccent.withValues(alpha: 0.4) : const Color(0xFF222232),
                borderRadius: BorderRadius.circular(5),
                border: isBroken ? Border.all(color: Colors.redAccent) : null,
              ),
              child: isBroken
                  ? const Icon(Icons.build_rounded, color: Colors.redAccent, size: 12)
                  : Text(isSweetbox ? '${i * 2 + 1}•${i * 2 + 2}' : '${i + 1}',
                      style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
            ),
          );
        }),
      ],
    );
  }

  void _toggleBroken(String seatId, bool currentlyBroken) async {
    await _selectedRoom!.reference.update({
      'brokenSeats': currentlyBroken ? FieldValue.arrayRemove([seatId]) : FieldValue.arrayUnion([seatId]),
    });
  }
}
