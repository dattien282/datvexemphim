import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_audit_log.dart';

/// Gửi thông báo tới toàn bộ user - trước đây admin không có cách nào báo
/// tin (khuyến mãi mới, bảo trì hệ thống...) cho tất cả khách hàng cùng lúc,
/// chỉ có thông báo tự động theo từng hành động (đặt vé/hủy vé...).
class AdminBroadcastScreen extends StatefulWidget {
  const AdminBroadcastScreen({super.key});

  @override
  State<AdminBroadcastScreen> createState() => _AdminBroadcastScreenState();
}

class _AdminBroadcastScreenState extends State<AdminBroadcastScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập đủ tiêu đề và nội dung'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('XÁC NHẬN GỬI', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
        content: const Text('Gửi thông báo này tới TẤT CẢ người dùng? Không thể thu hồi sau khi gửi.',
            style: TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('HỦY', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: const Text('GỬI', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _sending = true);
    try {
      final usersSnap = await FirebaseFirestore.instance.collection('users').get();
      // Firestore giới hạn 500 write/batch - chia nhỏ theo lô 400 để an toàn.
      const chunkSize = 400;
      int sent = 0;
      for (var i = 0; i < usersSnap.docs.length; i += chunkSize) {
        final chunk = usersSnap.docs.skip(i).take(chunkSize);
        final batch = FirebaseFirestore.instance.batch();
        for (final userDoc in chunk) {
          final email = userDoc.data()['email'] as String?;
          if (email == null || email.isEmpty) continue;
          final ref = FirebaseFirestore.instance.collection('notifications').doc();
          batch.set(ref, {
            'title': title,
            'body': body,
            'userEmail': email,
            'type': 'broadcast',
            'isRead': false,
            'createdAt': Timestamp.now(),
          });
          sent++;
        }
        await batch.commit();
      }

      await logAdminAction(
        action: 'broadcast_notification',
        targetCollection: 'notifications',
        targetId: 'broadcast_${DateTime.now().millisecondsSinceEpoch}',
        after: {'title': title, 'body': body, 'recipientCount': sent},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã gửi thông báo tới $sent người dùng!'), backgroundColor: Colors.teal),
        );
        _titleCtrl.clear();
        _bodyCtrl.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi gửi thông báo: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text('GỬI THÔNG BÁO CHUNG',
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Thông báo sẽ được gửi tới hộp thư trong app của TẤT CẢ người dùng đã đăng ký.',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 20),
            TextField(
              controller: _titleCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Tiêu đề (vd: 🎉 Ưu đãi cuối tuần)',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFF16161F),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyCtrl,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Nội dung thông báo...',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFF16161F),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _sending ? null : _send,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  disabledBackgroundColor: Colors.white10,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _sending
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Text('GỬI THÔNG BÁO', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
