import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_audit_log.dart';
import '../../../utils/db_updater.dart';

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
  bool _isUpdatingDb = false;
  bool _isMigratingShowtimes = false;
  bool _isMigratingFormats = false;
  bool _isSeedingRoomFormats = false;
  bool _isSeedingStaffDemo = false;

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

  Future<void> _runDbUpdater() async {
    setState(() => _isUpdatingDb = true);
    try {
      await updateTheaterSizesAndSeedShowtimes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cập nhật DB thành công!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUpdatingDb = false);
    }
  }

  Future<void> _runShowtimeMigration() async {
    setState(() => _isMigratingShowtimes = true);
    try {
      await migrateShowtimesToTimestamp();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã backfill showAt cho các suất chiếu cũ!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _isMigratingShowtimes = false);
    }
  }

  Future<void> _runRoomFormatMigration() async {
    setState(() => _isMigratingFormats = true);
    try {
      await migrateRoomFormatsToStellaBranding();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã đổi định dạng phòng cũ sang hệ Stella Cinema!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _isMigratingFormats = false);
    }
  }

  Future<void> _runSeedRoomFormats() async {
    setState(() => _isSeedingRoomFormats = true);
    try {
      await migrateRoomFormatsToFirestore();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã seed danh mục định dạng phòng vào Firestore (bỏ qua nếu đã có sẵn)!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSeedingRoomFormats = false);
    }
  }

  Future<void> _runSeedStaffDemo() async {
    setState(() => _isSeedingStaffDemo = true);
    try {
      await seedStaffManagerDemoData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã seed demo sự cố/ca làm/điểm danh cho các rạp đã có tài khoản staff!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSeedingStaffDemo = false);
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
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isUpdatingDb ? null : _runDbUpdater,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        disabledBackgroundColor: Colors.white10,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isUpdatingDb
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('CẬP NHẬT DB (THEATER & SHOWTIMES)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Backfill "showAt" (Timestamp) cho các suất chiếu cũ chưa có field này - sửa lỗi ngày tháng lẫn 2 định dạng string.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isMigratingShowtimes ? null : _runShowtimeMigration,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurpleAccent,
                        disabledBackgroundColor: Colors.white10,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isMigratingShowtimes
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('MIGRATE SHOWTIMES → showAt', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Đổi tên định dạng phòng cũ (VIP, GoldClass, Premium, L\'amour, IMAX, 4DX, ScreenX, 2D Phụ đề/Lồng tiếng) sang hệ định dạng riêng của Stella Cinema cho rooms và showtimes.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isMigratingFormats ? null : _runRoomFormatMigration,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        disabledBackgroundColor: Colors.white10,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isMigratingFormats
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('MIGRATE ĐỊNH DẠNG PHÒNG → STELLA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Đưa 13 định dạng phòng chiếu mặc định (Standard, VIP, IMAX, 4DX...) vào collection "room_formats" - sau bước này admin tự thêm/sửa định dạng qua màn "Định dạng phòng chiếu" mà không cần sửa code. Chỉ chạy 1 lần (bỏ qua nếu đã có dữ liệu).',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isSeedingRoomFormats ? null : _runSeedRoomFormats,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigoAccent,
                        disabledBackgroundColor: Colors.white10,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSeedingRoomFormats
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('SEED DANH MỤC ĐỊNH DẠNG PHÒNG', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Tạo vài sự cố mẫu (Báo cáo Sự cố), ca làm hôm nay (Smart Roster) và 1 lượt điểm danh vào ca (Điểm danh ca làm) cho các rạp đã có tài khoản staff/manager - để demo staff/manager không trống trơn. Bỏ qua rạp nào chưa có tài khoản staff nào, và bỏ qua nếu rạp đó đã có dữ liệu hôm nay (chạy lại không tạo trùng).',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isSeedingStaffDemo ? null : _runSeedStaffDemo,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        disabledBackgroundColor: Colors.white10,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSeedingStaffDemo
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('SEED DEMO STAFF/MANAGER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
