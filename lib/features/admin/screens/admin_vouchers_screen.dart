import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AdminVouchersScreen extends StatelessWidget {
  const AdminVouchersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text('VOUCHER & KHUYẾN MÃI',
            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 15)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: Colors.orange),
            onPressed: () => _VoucherDialog.show(context),
            tooltip: 'Thêm voucher',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('vouchers')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.orange));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.local_offer_outlined, color: Colors.white24, size: 56),
                  const SizedBox(height: 16),
                  const Text('Chưa có voucher nào.', style: TextStyle(color: Colors.white38)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _VoucherDialog.show(context),
                    icon: const Icon(Icons.add_rounded, color: Colors.black),
                    label: const Text('Tạo voucher đầu tiên',
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (ctx, i) => _VoucherCard(doc: docs[i]),
          );
        },
      ),
    );
  }
}

// ── Voucher card ───────────────────────────────────────────────────────────────
class _VoucherCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  const _VoucherCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final code = d['code'] ?? doc.id;
    final discountPct = (d['discountPercent'] as num?)?.toInt() ?? 0;
    final discountAmt = (d['discountAmount'] as num?)?.toInt() ?? 0;
    final maxUses = (d['maxUses'] as num?)?.toInt() ?? 0;
    final currentUses = (d['currentUses'] as num?)?.toInt() ?? 0;
    final minOrder = (d['minOrder'] as num?)?.toInt() ?? 0;
    final status = d['status'] ?? 'active';
    final isActive = status == 'active';

    DateTime? expires;
    if (d['expiresAt'] != null) {
      expires = (d['expiresAt'] as Timestamp).toDate();
    }
    final isExpired = expires != null && expires.isBefore(DateTime.now());
    final effectiveActive = isActive && !isExpired && (maxUses == 0 || currentUses < maxUses);

    final discountLabel = discountPct > 0 ? '-$discountPct%' : '-${_fmt(discountAmt)}đ';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF16161F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: effectiveActive ? Colors.orange.withOpacity(0.3) : Colors.white.withOpacity(0.05),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: effectiveActive ? Colors.orange.withOpacity(0.08) : Colors.white.withOpacity(0.03),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_offer_rounded,
                        color: effectiveActive ? Colors.orange : Colors.white24, size: 18),
                    const SizedBox(width: 8),
                    Text(code,
                        style: TextStyle(
                            color: effectiveActive ? Colors.orange : Colors.white38,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            fontFamily: 'monospace',
                            letterSpacing: 1.5)),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: effectiveActive ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        effectiveActive ? 'Còn hiệu lực' : isExpired ? 'Hết hạn' : 'Đã tắt',
                        style: TextStyle(
                            color: effectiveActive ? Colors.greenAccent : Colors.redAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, color: Colors.white38, size: 18),
                      color: const Color(0xFF1E1E2A),
                      onSelected: (v) async {
                        if (v == 'edit') {
                          _VoucherDialog.show(context, existing: doc);
                        } else if (v == 'toggle') {
                          await FirebaseFirestore.instance.collection('vouchers').doc(doc.id).update({
                            'status': isActive ? 'inactive' : 'active',
                          });
                        } else if (v == 'delete') {
                          await FirebaseFirestore.instance.collection('vouchers').doc(doc.id).delete();
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('Chỉnh sửa', style: TextStyle(color: Colors.white))),
                        PopupMenuItem(
                          value: 'toggle',
                          child: Text(isActive ? 'Tắt voucher' : 'Bật lại',
                              style: TextStyle(color: isActive ? Colors.redAccent : Colors.green)),
                        ),
                        const PopupMenuItem(value: 'delete', child: Text('Xóa', style: TextStyle(color: Colors.redAccent))),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Details
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(child: _detail('Giảm giá', discountLabel, Colors.orange)),
                if (minOrder > 0) Expanded(child: _detail('Đơn tối thiểu', '${_fmt(minOrder)}đ', Colors.white54)),
                Expanded(child: _detail('Đã dùng', '$currentUses / ${maxUses == 0 ? '∞' : '$maxUses'}', Colors.blue)),
                if (expires != null)
                  Expanded(child: _detail('Hết hạn', DateFormat('dd/MM/yy').format(expires), Colors.white54)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detail(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }

  static String _fmt(int v) =>
      v.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
}

// ── Voucher dialog ─────────────────────────────────────────────────────────────
class _VoucherDialog {
  static Future<void> show(BuildContext context, {QueryDocumentSnapshot? existing}) {
    return showDialog(
      context: context,
      builder: (ctx) => _VoucherDialogWidget(existing: existing),
    );
  }
}

class _VoucherDialogWidget extends StatefulWidget {
  final QueryDocumentSnapshot? existing;
  const _VoucherDialogWidget({this.existing});

  @override
  State<_VoucherDialogWidget> createState() => _VoucherDialogWidgetState();
}

class _VoucherDialogWidgetState extends State<_VoucherDialogWidget> {
  final _codeCtrl = TextEditingController();
  final _pctCtrl = TextEditingController();
  final _amtCtrl = TextEditingController();
  final _minCtrl = TextEditingController(text: '0');
  final _maxCtrl = TextEditingController(text: '0');
  bool _isPercent = true;
  DateTime _expires = DateTime.now().add(const Duration(days: 30));

  @override
  void initState() {
    super.initState();
    final d = widget.existing?.data() as Map<String, dynamic>?;
    if (d != null) {
      _codeCtrl.text = d['code'] ?? '';
      final pct = (d['discountPercent'] as num?)?.toInt() ?? 0;
      final amt = (d['discountAmount'] as num?)?.toInt() ?? 0;
      _isPercent = pct > 0 || amt == 0;
      _pctCtrl.text = '$pct';
      _amtCtrl.text = '$amt';
      _minCtrl.text = '${(d['minOrder'] as num?)?.toInt() ?? 0}';
      _maxCtrl.text = '${(d['maxUses'] as num?)?.toInt() ?? 0}';
      if (d['expiresAt'] != null) {
        _expires = (d['expiresAt'] as Timestamp).toDate();
      }
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose(); _pctCtrl.dispose(); _amtCtrl.dispose();
    _minCtrl.dispose(); _maxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF16161F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.existing != null ? 'CHỈNH SỬA VOUCHER' : 'TẠO VOUCHER MỚI',
        style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 14),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(_codeCtrl, 'Mã voucher (VD: SUMMER20)', Icons.local_offer_rounded),
            const SizedBox(height: 10),
            // Discount type toggle
            Row(
              children: [
                const Text('Loại giảm:', style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(width: 12),
                _toggle('% Phần trăm', true),
                const SizedBox(width: 8),
                _toggle('Số tiền cố định', false),
              ],
            ),
            const SizedBox(height: 10),
            if (_isPercent)
              _field(_pctCtrl, 'Giảm % (VD: 20)', Icons.percent_rounded, type: TextInputType.number)
            else
              _field(_amtCtrl, 'Giảm (đ) (VD: 50000)', Icons.money_rounded, type: TextInputType.number),
            const SizedBox(height: 10),
            _field(_minCtrl, 'Đơn tối thiểu (đ) – 0 = không giới hạn', Icons.shopping_cart_rounded, type: TextInputType.number),
            const SizedBox(height: 10),
            _field(_maxCtrl, 'Số lần dùng tối đa – 0 = không giới hạn', Icons.repeat_rounded, type: TextInputType.number),
            const SizedBox(height: 10),
            // Date picker
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month_rounded, color: Colors.orange, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      'Hết hạn: ${DateFormat('dd/MM/yyyy').format(_expires)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const Spacer(),
                    const Icon(Icons.edit_calendar_rounded, color: Colors.white38, size: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('HỦY', style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          child: Text(widget.existing != null ? 'CẬP NHẬT' : 'TẠO',
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _toggle(String label, bool value) {
    final active = _isPercent == value;
    return GestureDetector(
      onTap: () => setState(() => _isPercent = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? Colors.orange.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? Colors.orange : Colors.white24),
        ),
        child: Text(label, style: TextStyle(color: active ? Colors.orange : Colors.white38, fontSize: 11)),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint, IconData icon, {TextInputType type = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
        prefixIcon: Icon(icon, color: Colors.orange, size: 18),
        filled: true,
        fillColor: const Color(0xFF1E1E2A),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expires,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: Colors.orange)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _expires = picked);
  }

  Future<void> _save() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;

    final data = <String, dynamic>{
      'code': code,
      'discountPercent': _isPercent ? (int.tryParse(_pctCtrl.text) ?? 0) : 0,
      'discountAmount': _isPercent ? 0 : (int.tryParse(_amtCtrl.text) ?? 0),
      'minOrder': int.tryParse(_minCtrl.text) ?? 0,
      'maxUses': int.tryParse(_maxCtrl.text) ?? 0,
      'currentUses': 0,
      'expiresAt': Timestamp.fromDate(_expires),
      'status': 'active',
    };

    if (widget.existing != null) {
      data.remove('currentUses');
      await FirebaseFirestore.instance.collection('vouchers').doc(widget.existing!.id).update(data);
    } else {
      data['createdAt'] = Timestamp.now();
      await FirebaseFirestore.instance.collection('vouchers').doc(code).set(data);
    }
    if (mounted) Navigator.pop(context);
  }
}
