import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class SmartRosterScreen extends StatefulWidget {
  final String theater;
  const SmartRosterScreen({super.key, required this.theater});

  @override
  State<SmartRosterScreen> createState() => _SmartRosterScreenState();
}

class _SmartRosterScreenState extends State<SmartRosterScreen> {
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    return Scaffold(
      backgroundColor: const Color(0xFF111115),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        title: const Text('Phân công ca làm', style: TextStyle(color: Colors.deepPurpleAccent, fontSize: 16, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.deepPurpleAccent),
      ),
      body: Column(
        children: [
          // Date selector
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
                  onPressed: () => setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1))),
                ),
                Text(
                  DateFormat('dd/MM/yyyy').format(_selectedDate),
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, color: Colors.white),
                  onPressed: () => setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1))),
                ),
              ],
            ),
          ),
          // Shifts list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('shifts')
                  .where('theater', isEqualTo: widget.theater)
                  .where('date', isEqualTo: dateStr)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent));
                }
                final docs = snapshot.data?.docs ?? [];
                
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildShiftCard('Sáng (08:00 - 15:00)', docs, 'morning', dateStr),
                    _buildShiftCard('Chiều (15:00 - 22:00)', docs, 'afternoon', dateStr),
                    _buildShiftCard('Tối (22:00 - 02:00)', docs, 'night', dateStr),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftCard(String title, List<QueryDocumentSnapshot> docs, String shiftType, String dateStr) {
    final shiftDoc = docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      return data['shiftType'] == shiftType;
    }).firstOrNull;
    final staffList = shiftDoc != null ? List<String>.from((shiftDoc.data() as Map)['staffIds'] ?? []) : <String>[];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.edit_rounded, color: Colors.deepPurpleAccent, size: 20),
                onPressed: () => _assignStaffDialog(shiftType, staffList, dateStr, shiftDoc?.id),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (staffList.isEmpty)
            const Text('Chưa có nhân viên', style: TextStyle(color: Colors.white38, fontSize: 13))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: staffList.map((s) => Chip(
                label: FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance.collection('users').doc(s).get(),
                  builder: (ctx, snap) {
                    if (!snap.hasData) return const Text('...');
                    final d = snap.data!.data() as Map<String, dynamic>?;
                    return Text(d?['displayName'] ?? d?['email'] ?? 'Unknown', style: const TextStyle(color: Colors.white, fontSize: 12));
                  },
                ),
                backgroundColor: Colors.deepPurpleAccent.withValues(alpha: 0.2),
                side: BorderSide.none,
              )).toList(),
            ),
        ],
      ),
    );
  }

  void _assignStaffDialog(String shiftType, List<String> currentStaff, String dateStr, String? docId) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'staff')
        .where('assignedTheater', isEqualTo: widget.theater)
        .get();
        
    final allStaff = snap.docs;
    List<String> selectedStaff = List.from(currentStaff);

    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2A),
          title: const Text('Phân công nhân viên', style: TextStyle(color: Colors.deepPurpleAccent)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: allStaff.length,
              itemBuilder: (ctx, i) {
                final d = allStaff[i].data();
                final name = d['displayName'] ?? d['email'] ?? 'Unknown';
                final uid = allStaff[i].id;
                final isSelected = selectedStaff.contains(uid);
                
                return CheckboxListTile(
                  title: Text(name, style: const TextStyle(color: Colors.white)),
                  value: isSelected,
                  activeColor: Colors.deepPurpleAccent,
                  onChanged: (v) {
                    setDlg(() {
                      if (v == true) selectedStaff.add(uid);
                      else selectedStaff.remove(uid);
                    });
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final data = {
                  'theater': widget.theater,
                  'date': dateStr,
                  'shiftType': shiftType,
                  'staffIds': selectedStaff,
                };
                if (docId != null) {
                  await FirebaseFirestore.instance.collection('shifts').doc(docId).update(data);
                } else {
                  await FirebaseFirestore.instance.collection('shifts').add(data);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
              child: const Text('Lưu', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
