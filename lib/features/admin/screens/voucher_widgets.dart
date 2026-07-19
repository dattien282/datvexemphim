import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../providers/theaters_provider.dart';
import 'admin_audit_log.dart';

class VoucherListView extends StatelessWidget {
  final String? theaterScopeFilter;
  const VoucherListView({super.key, this.theaterScopeFilter});

  @override
  Widget build(BuildContext context) {
    Query query = FirebaseFirestore.instance.collection('vouchers');
    query = theaterScopeFilter != null
        ? query.where('theaterScope', isEqualTo: theaterScopeFilter)
        : query.orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.amber));
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
                  onPressed: () => VoucherDialog.show(context, lockedTheaterScope: theaterScopeFilter),
                  icon: const Icon(Icons.add_rounded, color: Colors.black),
                  label: const Text('Tạo voucher đầu tiên',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (ctx, i) => VoucherCard(doc: docs[i]),
        );
      },
    );
  }
}

class VoucherCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  const VoucherCard({super.key, required this.doc});

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
    final String? theaterScope = d['theaterScope'] as String?;

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
        color: const Color(0xFF161622),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: effectiveActive ? Colors.amber.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: effectiveActive ? Colors.amber.withValues(alpha: 0.03) : Colors.transparent,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: effectiveActive ? Colors.amber.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.02),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_offer_rounded,
                        color: effectiveActive ? Colors.amber : Colors.white24, size: 18),
                    const SizedBox(width: 8),
                    Text(code,
                        style: TextStyle(
                            color: effectiveActive ? Colors.amber : Colors.white38,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            fontFamily: 'monospace',
                            letterSpacing: 1.5)),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: effectiveActive 
                            ? Colors.green.withValues(alpha: 0.15) 
                            : Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: effectiveActive 
                              ? Colors.greenAccent.withValues(alpha: 0.3) 
                              : Colors.redAccent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        effectiveActive ? 'Còn hiệu lực' : isExpired ? 'Hết hạn' : 'Đã tắt',
                        style: TextStyle(
                            color: effectiveActive ? Colors.greenAccent : Colors.redAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, color: Colors.white38, size: 18),
                      color: const Color(0xFF161622),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      onSelected: (v) async {
                        if (v == 'edit') {
                          VoucherDialog.show(context, existing: doc, lockedTheaterScope: theaterScope);
                        } else if (v == 'toggle') {
                          final newStatus = isActive ? 'inactive' : 'active';
                          await FirebaseFirestore.instance.collection('vouchers').doc(doc.id).update({
                            'status': newStatus,
                          });
                          await logAdminAction(
                            action: 'toggle_voucher',
                            targetCollection: 'vouchers',
                            targetId: doc.id,
                            before: {'status': status},
                            after: {'status': newStatus},
                          );
                        } else if (v == 'delete') {
                          await FirebaseFirestore.instance.collection('vouchers').doc(doc.id).delete();
                          await logAdminAction(
                            action: 'delete_voucher',
                            targetCollection: 'vouchers',
                            targetId: doc.id,
                            before: d,
                          );
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('Chỉnh sửa', style: TextStyle(color: Colors.white, fontSize: 13))),
                        PopupMenuItem(
                          value: 'toggle',
                          child: Text(isActive ? 'Tắt voucher' : 'Bật lại',
                              style: TextStyle(color: isActive ? Colors.redAccent : Colors.green, fontSize: 13)),
                        ),
                        const PopupMenuItem(value: 'delete', child: Text('Xóa', style: TextStyle(color: Colors.redAccent, fontSize: 13))),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _detail('Giảm giá', discountLabel, Colors.amber),
                    if (minOrder > 0) _detail('Đơn tối thiểu', '${_fmt(minOrder)}đ', Colors.white70),
                    _detail('Đã dùng', '$currentUses / ${maxUses == 0 ? '∞' : '$maxUses'}', Colors.blueAccent),
                    if (expires != null)
                      _detail('Hết hạn', DateFormat('dd/MM/yy').format(expires), Colors.white54),
                  ],
                ),
                const SizedBox(height: 12),
                Container(height: 1, color: Colors.white.withValues(alpha: 0.03)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.storefront_rounded, color: Colors.tealAccent, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Áp dụng: ${theaterScope ?? "Tất cả rạp"}',
                      style: const TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
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
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }

  static String _fmt(int v) =>
      v.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
}

class VoucherDialog {
  static Future<void> show(BuildContext context, {QueryDocumentSnapshot? existing, String? lockedTheaterScope}) {
    return showDialog(
      context: context,
      builder: (ctx) => _VoucherDialogWidget(existing: existing, lockedTheaterScope: lockedTheaterScope),
    );
  }
}

class _VoucherDialogWidget extends ConsumerStatefulWidget {
  final QueryDocumentSnapshot? existing;
  final String? lockedTheaterScope;
  const _VoucherDialogWidget({this.existing, this.lockedTheaterScope});

  @override
  ConsumerState<_VoucherDialogWidget> createState() => _VoucherDialogWidgetState();
}

class _VoucherDialogWidgetState extends ConsumerState<_VoucherDialogWidget> {
  final _codeCtrl = TextEditingController();
  final _pctCtrl = TextEditingController();
  final _amtCtrl = TextEditingController();
  final _minCtrl = TextEditingController(text: '0');
  final _maxCtrl = TextEditingController(text: '0');
  bool _isPercent = true;
  DateTime _expires = DateTime.now().add(const Duration(days: 30));
  String? _theaterScope;

  @override
  void initState() {
    super.initState();
    _theaterScope = widget.lockedTheaterScope;
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
      if (widget.lockedTheaterScope == null) {
        _theaterScope = d['theaterScope'] as String?;
      }
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
    final theaterNames = ref.watch(theaterNamesProvider);
    return AlertDialog(
      backgroundColor: const Color(0xFF0F0F14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      title: Text(
        widget.existing != null ? 'CHỈNH SỬA VOUCHER' : 'TẠO VOUCHER MỚI',
        style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(_codeCtrl, 'Mã voucher (VD: SUMMER20)', Icons.local_offer_rounded),
            const SizedBox(height: 12),
            if (widget.lockedTheaterScope == null) ...[
              const Text('Áp dụng cho rạp:', style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _theaterScope,
                dropdownColor: const Color(0xFF161622),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF161622),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                style: const TextStyle(color: Colors.white, fontSize: 12),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Tất cả rạp')),
                  ...theaterNames.map((t) => DropdownMenuItem<String?>(value: t, child: Text(t))),
                ],
                onChanged: (v) => setState(() => _theaterScope = v),
              ),
              const SizedBox(height: 12),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF161622), 
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.storefront_rounded, color: Colors.tealAccent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Chỉ áp dụng tại: ${widget.lockedTheaterScope}',
                          style: const TextStyle(color: Colors.tealAccent, fontSize: 12, fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ),
            ],
            
            // Discount type toggle
            const Text('Loại giảm giá:', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _toggle('% Phần trăm', true)),
                const SizedBox(width: 8),
                Expanded(child: _toggle('Cố định (đ)', false)),
              ],
            ),
            const SizedBox(height: 12),
            if (_isPercent)
              _field(_pctCtrl, 'Giảm % (VD: 20)', Icons.percent_rounded, type: TextInputType.number)
            else
              _field(_amtCtrl, 'Giảm (đ) (VD: 50000)', Icons.money_rounded, type: TextInputType.number),
            const SizedBox(height: 12),
            _field(_minCtrl, 'Đơn tối thiểu (đ) – 0 = không giới hạn', Icons.shopping_cart_rounded, type: TextInputType.number),
            const SizedBox(height: 12),
            _field(_maxCtrl, 'Số lần dùng tối đa – 0 = không giới hạn', Icons.repeat_rounded, type: TextInputType.number),
            const SizedBox(height: 12),
            
            // Date picker
            const Text('Hạn sử dụng:', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF161622),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month_rounded, color: Colors.amber, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      DateFormat('dd/MM/yyyy').format(_expires),
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
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
        TextButton(
          onPressed: () => Navigator.pop(context), 
          child: const Text('HỦY', style: TextStyle(color: Colors.white38))
        ),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(widget.existing != null ? 'CẬP NHẬT' : 'TẠO VOUCHER',
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
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? Colors.amber.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? Colors.amber : Colors.white10,
            width: 1.2,
          ),
        ),
        child: Text(
          label, 
          style: TextStyle(
            color: active ? Colors.amber : Colors.white38, 
            fontSize: 11,
            fontWeight: FontWeight.bold
          )
        ),
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
        prefixIcon: Icon(icon, color: Colors.amber, size: 18),
        filled: true,
        fillColor: const Color(0xFF161622),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), 
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), 
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), 
          borderSide: const BorderSide(color: Colors.amber, width: 1.2),
        ),
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
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.amber,
            onPrimary: Colors.black,
            surface: Color(0xFF0F0F14),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _expires = picked);
  }

  Future<void> _save() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;

    final pct = (int.tryParse(_pctCtrl.text) ?? 0).clamp(0, 100);
    final amt = (int.tryParse(_amtCtrl.text) ?? 0).clamp(0, 1 << 30);
    final minOrder = (int.tryParse(_minCtrl.text) ?? 0).clamp(0, 1 << 30);
    final maxUses = (int.tryParse(_maxCtrl.text) ?? 0).clamp(0, 1 << 30);

    final data = <String, dynamic>{
      'code': code,
      'discountPercent': _isPercent ? pct : 0,
      'discountAmount': _isPercent ? 0 : amt,
      'minOrder': minOrder,
      'maxUses': maxUses,
      'currentUses': 0,
      'expiresAt': Timestamp.fromDate(_expires),
      'status': 'active',
      'theaterScope': widget.lockedTheaterScope ?? _theaterScope,
    };

    try {
      if (widget.existing != null) {
        data.remove('currentUses');
        await FirebaseFirestore.instance.collection('vouchers').doc(widget.existing!.id).update(data);
        await logAdminAction(action: 'update_voucher', targetCollection: 'vouchers', targetId: widget.existing!.id, after: data);
      } else {
        data['createdAt'] = Timestamp.now();
        await FirebaseFirestore.instance.collection('vouchers').doc(code).set(data);
        await logAdminAction(action: 'create_voucher', targetCollection: 'vouchers', targetId: code, after: data);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi lưu voucher: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }
}
