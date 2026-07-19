import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/room_layout.dart';
import '../../theater_manager/widgets/seat_grid_widget.dart';

class StaffSeatMaintenanceScreen extends StatefulWidget {
  final String? theater;
  const StaffSeatMaintenanceScreen({super.key, required this.theater});

  @override
  State<StaffSeatMaintenanceScreen> createState() => _StaffSeatMaintenanceScreenState();
}

class _StaffSeatMaintenanceScreenState extends State<StaffSeatMaintenanceScreen> {
  String? _selectedRoomId;
  MaintenanceTarget _target = MaintenanceTarget.broken;

  @override
  Widget build(BuildContext context) {
    final theater = widget.theater;
    return Scaffold(
      backgroundColor: const Color(0xFF09090F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F14),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'GHẾ HỎNG / XE LĂN', 
          style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: Colors.white.withValues(alpha: 0.05),
            height: 1,
          ),
        ),
      ),
      body: theater == null
          ? const Center(child: Text('Tài khoản chưa được gán rạp.', style: TextStyle(color: Colors.white38)))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('rooms').where('theaterName', isEqualTo: theater).snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.amber));
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('Rạp này chưa cấu hình phòng chiếu nào.', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  );
                }
                
                final hasSelected = docs.any((d) => d.id == _selectedRoomId);
                final currentId = hasSelected ? _selectedRoomId : null;
                final selectedDoc = hasSelected 
                    ? docs.firstWhere((d) => d.id == _selectedRoomId)
                    : null;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: DropdownButtonFormField<String>(
                        initialValue: currentId,
                        dropdownColor: const Color(0xFF161622),
                        isExpanded: true,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF161622),
                          prefixIcon: const Icon(Icons.weekend_rounded, color: Colors.amber, size: 18),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14), 
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14), 
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14), 
                            borderSide: const BorderSide(color: Colors.amber, width: 1.2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                        ),
                        hint: const Text('Chọn phòng chiếu', style: TextStyle(color: Colors.white38, fontSize: 12)),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        items: docs.map((doc) {
                          final d = doc.data() as Map<String, dynamic>;
                          return DropdownMenuItem<String>(
                            value: doc.id, 
                            child: Text(d['roomName'] ?? '—', style: const TextStyle(fontWeight: FontWeight.bold)),
                          );
                        }).toList(),
                        onChanged: (id) => setState(() => _selectedRoomId = id),
                      ),
                    ),
                    if (selectedDoc != null) Expanded(child: _buildSeatGrid(selectedDoc)),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildSeatGrid(QueryDocumentSnapshot doc) {
    return StreamBuilder<DocumentSnapshot>(
      stream: doc.reference.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: Colors.amber));
        }
        final data = (snap.data?.data() as Map<String, dynamic>?) ?? (doc.data() as Map<String, dynamic>);
        final layout = RoomLayout.fromMap(doc.id, data);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
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
                  const SizedBox(width: 12),
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
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Chạm vào ghế để đánh dấu/gỡ đánh dấu theo loại đang chọn ở trên', 
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
              SeatGridView(
                layout: layout,
                mode: SeatGridMode.maintenance,
                maintenanceTarget: _target,
                brokenSeats: layout.brokenSeats,
                wheelchairSeats: layout.wheelchairSeats,
                onToggleBroken: (seatId) => _toggleBroken(doc, data, seatId, layout.brokenSeats.contains(seatId)),
                onToggleWheelchair: (seatId) => _toggleWheelchair(doc, data, seatId, layout.wheelchairSeats.contains(seatId)),
              ),
            ],
          ),
        );
      },
    );
  }

  void _toggleBroken(QueryDocumentSnapshot doc, Map<String, dynamic> docData, String seatId, bool currentlyBroken) async {
    final update = {
      'brokenSeats': currentlyBroken ? FieldValue.arrayRemove([seatId]) : FieldValue.arrayUnion([seatId]),
    };
    final batch = FirebaseFirestore.instance.batch();
    batch.update(doc.reference, update);
    final currentVersionId = docData['currentSeatMapVersionId'] as String?;
    if (currentVersionId != null) {
      batch.update(FirebaseFirestore.instance.collection('seat_map_versions').doc(currentVersionId), update);
    }
    await batch.commit();
  }

  void _toggleWheelchair(QueryDocumentSnapshot doc, Map<String, dynamic> docData, String seatId, bool currentlyWheelchair) async {
    final update = {
      'wheelchairSeats': currentlyWheelchair ? FieldValue.arrayRemove([seatId]) : FieldValue.arrayUnion([seatId]),
    };
    final batch = FirebaseFirestore.instance.batch();
    batch.update(doc.reference, update);
    final currentVersionId = docData['currentSeatMapVersionId'] as String?;
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
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : const Color(0xFF161622),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? color.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.05), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: selected ? color.withValues(alpha: 0.05) : Colors.transparent,
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? color : Colors.white38, size: 18),
            const SizedBox(height: 6),
            Text(
              label, 
              style: TextStyle(
                color: selected ? color : Colors.white54, 
                fontSize: 10, 
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              )
            ),
          ],
        ),
      ),
    );
  }
}
