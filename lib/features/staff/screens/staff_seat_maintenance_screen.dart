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
  MaintenanceTarget _target = MaintenanceTarget.broken;

  @override
  Widget build(BuildContext context) {
    final theater = widget.theater;
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text('GHẾ HỎNG / XE LĂN', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 14)),
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
                        initialValue: current,
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
              // Chỉ 2 lựa chọn - hiện cả 2 nút thay vì giấu trong dropdown, để
              // staff thấy ngay đang ở chế độ đánh dấu nào trước khi chạm ghế.
              Row(
                children: [
                  Expanded(
                    child: _TargetButton(
                      label: 'GHẾ HỎNG',
                      icon: Icons.build_rounded,
                      color: Colors.redAccent,
                      selected: _target == MaintenanceTarget.broken,
                      onTap: () => setState(() => _target = MaintenanceTarget.broken),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TargetButton(
                      label: 'GHẾ XE LĂN',
                      icon: Icons.accessible_rounded,
                      color: Colors.blueAccent,
                      selected: _target == MaintenanceTarget.wheelchair,
                      onTap: () => setState(() => _target = MaintenanceTarget.wheelchair),
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Chạm vào ghế để đánh dấu/gỡ đánh dấu theo loại đang chọn ở trên', style: TextStyle(color: Colors.white38, fontSize: 11)),
              ),
              SeatGridView(
                layout: layout,
                mode: SeatGridMode.maintenance,
                maintenanceTarget: _target,
                brokenSeats: layout.brokenSeats,
                wheelchairSeats: layout.wheelchairSeats,
                onToggleBroken: (seatId) => _toggleBroken(seatId, layout.brokenSeats.contains(seatId)),
                onToggleWheelchair: (seatId) => _toggleWheelchair(seatId, layout.wheelchairSeats.contains(seatId)),
              ),
            ],
          ),
        );
      },
    );
  }

  void _toggleBroken(String seatId, bool currentlyBroken) async {
    final update = {
      'brokenSeats': currentlyBroken ? FieldValue.arrayRemove([seatId]) : FieldValue.arrayUnion([seatId]),
    };
    final batch = FirebaseFirestore.instance.batch();
    batch.update(_selectedRoom!.reference, update);
    // Ghi cả vào seat_map_versions hiện tại (nguồn thật cho suất chiếu mới -
    // xem models/showtime.dart Showtime.seatMapVersionId), không chỉ document
    // phòng (vốn chỉ là bản sao cache hiển thị nhanh).
    final currentVersionId = (_selectedRoom!.data() as Map<String, dynamic>)['currentSeatMapVersionId'] as String?;
    if (currentVersionId != null) {
      batch.update(FirebaseFirestore.instance.collection('seat_map_versions').doc(currentVersionId), update);
    }
    await batch.commit();
  }

  void _toggleWheelchair(String seatId, bool currentlyWheelchair) async {
    final update = {
      'wheelchairSeats': currentlyWheelchair ? FieldValue.arrayRemove([seatId]) : FieldValue.arrayUnion([seatId]),
    };
    final batch = FirebaseFirestore.instance.batch();
    batch.update(_selectedRoom!.reference, update);
    final currentVersionId = (_selectedRoom!.data() as Map<String, dynamic>)['currentSeatMapVersionId'] as String?;
    if (currentVersionId != null) {
      batch.update(FirebaseFirestore.instance.collection('seat_map_versions').doc(currentVersionId), update);
    }
    await batch.commit();
  }
}

class _TargetButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _TargetButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.18) : const Color(0xFF16161F),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? color : Colors.white12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? color : Colors.white38, size: 18),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: selected ? color : Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
