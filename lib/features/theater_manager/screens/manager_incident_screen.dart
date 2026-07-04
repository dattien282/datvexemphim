import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ManagerIncidentScreen extends StatelessWidget {
  final String theater;
  const ManagerIncidentScreen({super.key, required this.theater});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111115),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        title: const Text('Báo cáo sự cố', style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.redAccent),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('incidents')
            .where('theater', isEqualTo: theater)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.redAccent));
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('Không có sự cố nào.', style: TextStyle(color: Colors.white38)));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final createdAt = data['createdAt'] as Timestamp?;
              final timeStr = createdAt != null ? DateFormat('dd/MM/yyyy HH:mm').format(createdAt.toDate()) : '';
              final status = data['status'] ?? 'pending';

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: status == 'resolved' ? Colors.green.withValues(alpha: 0.3) : Colors.redAccent.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(data['type'] ?? 'Khác', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: status == 'resolved' ? Colors.green.withValues(alpha: 0.2) : Colors.redAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            status == 'resolved' ? 'Đã xử lý' : 'Chờ xử lý',
                            style: TextStyle(color: status == 'resolved' ? Colors.green : Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Mô tả: ${data['description'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text('Người báo cáo: ${data['reporterEmail'] ?? ''}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text('Thời gian: $timeStr', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    if (status == 'pending') ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => doc.reference.update({'status': 'resolved', 'resolvedAt': FieldValue.serverTimestamp()}),
                          icon: const Icon(Icons.check_circle_rounded, color: Colors.green),
                          label: const Text('Đánh dấu đã xử lý', style: TextStyle(color: Colors.green)),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
