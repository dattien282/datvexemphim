import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants.dart';
import 'admin_audit_log.dart';

/// Gửi thông báo tới người dùng theo phân khúc cụ thể (Marketing & Admin tool)
class AdminBroadcastScreen extends StatefulWidget {
  const AdminBroadcastScreen({super.key});

  @override
  State<AdminBroadcastScreen> createState() => _AdminBroadcastScreenState();
}

class _AdminBroadcastScreenState extends State<AdminBroadcastScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _sending = false;
  
  String _selectedSegment = 'all';
  final Map<String, String> _segments = const {
    'all': 'Tất cả thành viên',
    'diamond': 'Thành viên Kim Cương (>= 1000 điểm)',
    'gold': 'Thành viên Vàng (>= 500 điểm)',
    'silver': 'Thành viên Bạc (>= 200 điểm)',
    'staff': 'Nhân viên rạp (Staff)',
    'manager': 'Quản lý rạp (Manager)',
  };

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
        content: Text('Gửi thông báo này tới phân khúc [${_segments[_selectedSegment]}]? Không thể thu hồi sau khi gửi.',
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
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
      Query query = FirebaseFirestore.instance.collection('users');
      if (_selectedSegment == 'diamond') {
        query = query.where('loyalty_points', isGreaterThanOrEqualTo: 1000);
      } else if (_selectedSegment == 'gold') {
        query = query.where('loyalty_points', isGreaterThanOrEqualTo: 500);
      } else if (_selectedSegment == 'silver') {
        query = query.where('loyalty_points', isGreaterThanOrEqualTo: 200);
      } else if (_selectedSegment == 'staff') {
        query = query.where('role', isEqualTo: 'staff');
      } else if (_selectedSegment == 'manager') {
        query = query.where('role', isEqualTo: 'theater_manager');
      }

      final usersSnap = await query.get();
      
      // Firestore giới hạn 500 write/batch - chia nhỏ theo lô 400 để an toàn.
      const chunkSize = 400;
      int sent = 0;
      for (var i = 0; i < usersSnap.docs.length; i += chunkSize) {
        final chunk = usersSnap.docs.skip(i).take(chunkSize);
        final batch = FirebaseFirestore.instance.batch();
        for (final userDoc in chunk) {
          final email = userDoc.data() as Map<String, dynamic>;
          final userEmail = email['email'] as String?;
          if (userEmail == null || userEmail.isEmpty) continue;
          final ref = FirebaseFirestore.instance.collection('notifications').doc();
          batch.set(ref, {
            'title': title,
            'body': body,
            'userEmail': userEmail,
            'type': 'broadcast',
            'isRead': false,
            'createdAt': Timestamp.now(),
          });
          sent++;
        }
        await batch.commit();
      }

      // Gửi Push Notification (FCM) qua Backend kèm thông tin phân khúc
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final token = await user.getIdToken();
        try {
          final uri = Uri.parse('${AppConfig.paymentBackendUrl}/api/send-fcm');
          await http.post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'title': title,
              'body': body,
              'segment': _selectedSegment,
            }),
          );
        } catch (e) {
          debugPrint('Lỗi gọi API FCM: $e');
        }
      }

      await logAdminAction(
        action: 'broadcast_notification',
        targetCollection: 'notifications',
        targetId: 'broadcast_${DateTime.now().millisecondsSinceEpoch}',
        after: {'title': title, 'body': body, 'recipientCount': sent, 'segment': _selectedSegment},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã gửi thông báo tới $sent thành viên của phân khúc! (In-app + FCM)'), backgroundColor: Colors.teal),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chọn phân khúc khách hàng mục tiêu để gửi tin nhắn in-app và đẩy thông báo FCM.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 16),
            
            // Dropdown chọn phân khúc
            const Text(
              'PHÂN KHÚC KHÁCH HÀNG',
              style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF16161F),
                borderRadius: BorderRadius.circular(10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedSegment,
                  dropdownColor: const Color(0xFF16161F),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.amber),
                  isExpanded: true,
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedSegment = val);
                  },
                  items: _segments.entries.map((entry) {
                    return DropdownMenuItem<String>(
                      value: entry.key,
                      child: Text(entry.value),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            const Text(
              'NỘI DUNG THÔNG BÁO',
              style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _titleCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Tiêu đề (vd: 🎉 Khuyến mãi bắp nước cuối tuần)',
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
              maxLines: 5,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Nhập nội dung tin nhắn gửi đi...',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFF16161F),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _sending ? null : _send,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  disabledBackgroundColor: Colors.white10,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                child: _sending
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Text('GỬI THÔNG BÁO', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
