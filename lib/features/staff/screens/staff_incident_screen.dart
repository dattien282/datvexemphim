import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StaffIncidentScreen extends StatefulWidget {
  final String theater;
  final String staffEmail;

  const StaffIncidentScreen({super.key, required this.theater, required this.staffEmail});

  @override
  State<StaffIncidentScreen> createState() => _StaffIncidentScreenState();
}

class _StaffIncidentScreenState extends State<StaffIncidentScreen> {
  final _descCtrl = TextEditingController();
  String _type = 'Hết bắp nước';
  bool _saving = false;

  final List<String> _types = ['Hết bắp nước', 'Hỏng ghế', 'Vệ sinh', 'Khách hàng', 'Khác'];

  Future<void> _submit() async {
    if (_descCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập mô tả')));
      return;
    }

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('incidents').add({
        'theater': widget.theater,
        'reporterEmail': widget.staffEmail,
        'type': _type,
        'description': _descCtrl.text.trim(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã báo cáo sự cố thành công!')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        title: const Text('Báo cáo sự cố', style: TextStyle(color: Colors.orangeAccent, fontSize: 16, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.orangeAccent),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Loại sự cố', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.2)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _type,
                  dropdownColor: const Color(0xFF1E1E2A),
                  isExpanded: true,
                  style: const TextStyle(color: Colors.white),
                  items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setState(() => _type = v!),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Mô tả chi tiết', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _descCtrl,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1E1E2A),
                hintText: 'Nhập thông tin chi tiết...',
                hintStyle: const TextStyle(color: Colors.white38),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.orangeAccent)),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : const Text('GỬI BÁO CÁO', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
