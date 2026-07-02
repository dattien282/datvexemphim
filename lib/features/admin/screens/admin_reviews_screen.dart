import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_audit_log.dart';

/// Kiểm duyệt đánh giá phim - trước đây review chỉ tự xoá được bởi chính chủ
/// hoặc admin thao tác trực tiếp trên Firestore Console, không có UI trong
/// app để admin xử lý review vi phạm (spam, ngôn từ xấu...).
class AdminReviewsScreen extends StatelessWidget {
  const AdminReviewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text('KIỂM DUYỆT ĐÁNH GIÁ',
            style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold, fontSize: 14)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('movie_reviews')
            .orderBy('created_at', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.pinkAccent));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text('Chưa có đánh giá nào.', style: TextStyle(color: Colors.white38)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final doc = docs[i];
              final d = doc.data() as Map<String, dynamic>;
              final rating = (d['rating'] as num?)?.toDouble() ?? 0;
              final likes = (d['likes'] as List?)?.length ?? 0;
              final ts = (d['created_at'] as Timestamp?)?.toDate();
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161F),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(d['movieTitle'] ?? '—',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                        const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                        const SizedBox(width: 2),
                        Text(rating.toStringAsFixed(1), style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(d['email'] ?? 'Ẩn danh', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    const SizedBox(height: 8),
                    Text(d['comment'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.favorite_rounded, color: Colors.redAccent.withValues(alpha: 0.6), size: 12),
                        const SizedBox(width: 4),
                        Text('$likes lượt thích', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                        if (ts != null) ...[
                          const SizedBox(width: 12),
                          Text('${ts.day}/${ts.month}/${ts.year}', style: const TextStyle(color: Colors.white24, fontSize: 10)),
                        ],
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => _confirmDelete(context, doc.id, d),
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
                          label: const Text('Xoá', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
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

  void _confirmDelete(BuildContext context, String reviewId, Map<String, dynamic> data) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('XOÁ ĐÁNH GIÁ', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14)),
        content: const Text('Xoá đánh giá này vĩnh viễn? Không thể hoàn tác.', style: TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('HỦY', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('XOÁ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await FirebaseFirestore.instance.collection('movie_reviews').doc(reviewId).delete();
    await logAdminAction(action: 'delete_review', targetCollection: 'movie_reviews', targetId: reviewId, before: data);
  }
}
