import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/room_layout.dart';
import '../../theater_manager/widgets/seat_grid_widget.dart';

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
        final layout = RoomLayout.fromMap(_selectedRoom!.id, data);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Chạm vào ghế để đánh dấu hỏng/gỡ đánh dấu', style: TextStyle(color: Colors.white38, fontSize: 11)),
              ),
              SeatGridView(
                layout: layout,
                mode: SeatGridMode.maintenance,
                brokenSeats: layout.brokenSeats,
                onToggleBroken: (seatId) => _toggleBroken(seatId, layout.brokenSeats.contains(seatId)),
              ),
            ],
          ),
        );
      },
    );
  }

  void _toggleBroken(String seatId, bool currentlyBroken) async {
    await _selectedRoom!.reference.update({
      'brokenSeats': currentlyBroken ? FieldValue.arrayRemove([seatId]) : FieldValue.arrayUnion([seatId]),
    });
  }
}
