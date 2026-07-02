import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_audit_log.dart';

/// Duyệt yêu cầu xác minh độ tuổi (CCCD 2 mặt) do khách hàng không có
/// birthDate gửi lên khi cố đặt vé phim T18 - xem ảnh, chấp nhận/từ chối.
class AdminAgeVerificationScreen extends StatelessWidget {
  const AdminAgeVerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text('DUYỆT XÁC MINH ĐỘ TUỔI',
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('age_verification_requests')
            .where('status', isEqualTo: 'pending')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.amber));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('Không có yêu cầu nào cần duyệt.', style: TextStyle(color: Colors.white38)));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final doc = docs[i];
              final d = doc.data() as Map<String, dynamic>;
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161F),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d['email'] ?? '—', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _imageTile('Mặt trước', d['frontUrl'])),
                        const SizedBox(width: 10),
                        Expanded(child: _imageTile('Mặt sau', d['backUrl'])),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _decide(context, doc.id, d['userId'], approve: false),
                            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent)),
                            child: const Text('TỪ CHỐI', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _decide(context, doc.id, d['userId'], approve: true),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                            child: const Text('CHẤP NHẬN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _imageTile(String label, String? url) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: url == null
              ? Container(height: 100, color: const Color(0xFF1E1E2A))
              : Image.network(url, height: 100, width: double.infinity, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(height: 100, color: const Color(0xFF1E1E2A), child: const Icon(Icons.broken_image_rounded, color: Colors.white24))),
        ),
      ],
    );
  }

  void _decide(BuildContext context, String requestId, String userId, {required bool approve}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(approve ? 'CHẤP NHẬN XÁC MINH' : 'TỪ CHỐI XÁC MINH',
            style: TextStyle(color: approve ? Colors.teal : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14)),
        content: Text(
          approve
              ? 'Xác nhận CCCD hợp lệ và khách đủ 18 tuổi? Tài khoản sẽ được đánh dấu đã xác minh vĩnh viễn.'
              : 'Từ chối yêu cầu này? Khách sẽ phải chụp lại ảnh CCCD và gửi lại.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('HỦY', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: approve ? Colors.teal : Colors.redAccent),
            child: Text(approve ? 'CHẤP NHẬN' : 'TỪ CHỐI', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final newStatus = approve ? 'approved' : 'rejected';
    await FirebaseFirestore.instance.collection('age_verification_requests').doc(requestId).update({
      'status': newStatus,
      'reviewedAt': Timestamp.now(),
    });
    if (approve) {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'ageVerified': true,
        'ageVerifiedAt': Timestamp.now(),
      });
    }
    await logAdminAction(
      action: approve ? 'approve_age_verification' : 'reject_age_verification',
      targetCollection: 'age_verification_requests',
      targetId: requestId,
      after: {'status': newStatus, 'userId': userId},
    );
  }
}
