import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_audit_log.dart';

/// Cấu hình chung của server (Gemini API key...) qua UI thay vì phải sửa tay
/// file backend-payos/.env rồi restart server - server.js đọc
/// configs/server_config từ Firestore (cache 60s), fallback về .env nếu
/// Firestore chưa có gì.
class AdminServerConfigScreen extends StatefulWidget {
  const AdminServerConfigScreen({super.key});

  @override
  State<AdminServerConfigScreen> createState() => _AdminServerConfigScreenState();
}

class _AdminServerConfigScreenState extends State<AdminServerConfigScreen> {
  final _geminiKeyCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('configs').doc('server_config').get();
      _geminiKeyCtrl.text = doc.data()?['geminiApiKey'] ?? '';
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final data = {
        'geminiApiKey': _geminiKeyCtrl.text.trim(),
        'updatedAt': Timestamp.now(),
      };
      await FirebaseFirestore.instance.collection('configs').doc('server_config').set(data, SetOptions(merge: true));
      await logAdminAction(
        action: 'update_server_config',
        targetCollection: 'configs',
        targetId: 'server_config',
        after: {'geminiApiKey': _geminiKeyCtrl.text.trim().isEmpty ? '(trống)' : '(đã đặt)'},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu cấu hình! Có hiệu lực trong tối đa 60 giây (server cache).'), backgroundColor: Colors.teal),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi lưu cấu hình: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _geminiKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text('CẤU HÌNH SERVER', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('GEMINI API KEY', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    'Dùng cho Trợ lý AI (chatbot). Để trống sẽ dùng chatbot ở chế độ trả lời offline (không có Gemini).',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _geminiKeyCtrl,
                    obscureText: _obscure,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'AIza...',
                      hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                      filled: true,
                      fillColor: const Color(0xFF16161F),
                      prefixIcon: const Icon(Icons.vpn_key_rounded, color: Colors.amber, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: Colors.white38, size: 18),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        disabledBackgroundColor: Colors.white10,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _saving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Text('LƯU CẤU HÌNH', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
