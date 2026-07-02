import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Xem lại nhật ký hành động admin/manager - logAdminAction() (admin_audit_log.dart)
/// đã ghi log từ lâu (đổi role, CRUD phim/voucher...) nhưng chưa có màn hình
/// nào trong app để thực sự xem lại, chỉ có thể tra trực tiếp Firestore Console.
class AdminAuditLogScreen extends StatelessWidget {
  const AdminAuditLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text('NHẬT KÝ HÀNH ĐỘNG',
            style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 14)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('admin_audit_log')
            .orderBy('timestamp', descending: true)
            .limit(200)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.cyanAccent));
          }
          if (snap.hasError) {
            return Center(child: Text('Lỗi tải nhật ký: ${snap.error}', style: const TextStyle(color: Colors.redAccent)));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('Chưa có hành động nào được ghi lại.', style: TextStyle(color: Colors.white38)));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              final ts = (d['timestamp'] as Timestamp?)?.toDate();
              final action = d['action'] ?? '—';
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161F),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Colors.cyanAccent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                          child: Text(action, style: const TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        const Spacer(),
                        if (ts != null)
                          Text('${ts.day}/${ts.month}/${ts.year} ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(color: Colors.white24, fontSize: 10)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(d['adminEmail'] ?? '—', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                    Text('${d['targetCollection'] ?? ''} / ${d['targetId'] ?? ''}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
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
