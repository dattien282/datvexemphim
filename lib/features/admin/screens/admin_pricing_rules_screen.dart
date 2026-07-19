import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/session_type.dart';
import 'admin_audit_log.dart';

/// CRUD collection 'pricing_rules' (Giai đoạn D) - thay cho việc luật giá
/// (phụ thu cuối tuần/khung giờ/loại suất chiếu) nằm cứng trong code, phải
/// sửa code + build lại app mỗi lần muốn đổi. Cả app (PricingEngine trong
/// pricing_service.dart) lẫn backend (computeAuthoritativeAmount trong
/// server.js) cùng đọc collection này nên đổi ở đây là đổi đồng bộ cả giá
/// hiển thị lẫn giá trừ tiền thật.
///
/// Ngữ nghĩa luật: field matcher bỏ trống = áp dụng mọi trường hợp. Luật cùng
/// NHÓM loại trừ nhau (chỉ luật khớp có ưu tiên cao nhất được áp), khác nhóm
/// cộng dồn vào nhau.
class AdminPricingRulesScreen extends StatelessWidget {
  const AdminPricingRulesScreen({super.key});

  static const _groups = ['weekend', 'session', 'custom'];
  static const _groupLabels = {
    'weekend': 'Cuối tuần',
    'session': 'Khung giờ / Loại suất',
    'custom': 'Khác',
  };
  static const _dayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text('LUẬT GIÁ VÉ',
            style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 15)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: Colors.greenAccent, size: 24),
            onPressed: () => _showRuleDialog(context, null),
            tooltip: 'Thêm luật giá',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('pricing_rules').orderBy('group').snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Chưa có luật giá nào - app đang dùng công thức mặc định trong code '
                  '(cuối tuần +15.000đ, phụ thu theo loại suất chiếu).\n\nBấm + để tạo luật đầu tiên.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, i) => _RuleTile(doc: docs[i]),
          );
        },
      ),
    );
  }

  static String describeMatchers(Map<String, dynamic> d) {
    final parts = <String>[];
    if (d['sessionType'] != null) parts.add('Suất: ${d['sessionType']}');
    final days = (d['daysOfWeek'] as List?)?.map((e) => (e as num).toInt()).toList();
    if (days != null && days.isNotEmpty) {
      parts.add('Ngày: ${days.map((w) => _dayLabels[w - 1]).join(", ")}');
    }
    if (d['startHour'] != null || d['endHour'] != null) {
      parts.add('Giờ: ${d['startHour'] ?? 0}h-${d['endHour'] ?? 24}h');
    }
    if (d['theaterName'] != null) parts.add('Rạp: ${d['theaterName']}');
    return parts.isEmpty ? 'Mọi suất chiếu' : parts.join(' • ');
  }

  static void _showRuleDialog(BuildContext context, QueryDocumentSnapshot? existing) {
    final d = existing?.data() as Map<String, dynamic>?;
    final labelCtrl = TextEditingController(text: d?['label'] ?? '');
    final valueCtrl = TextEditingController(text: '${d?['adjustmentValue'] ?? 0}');
    final priorityCtrl = TextEditingController(text: '${d?['priority'] ?? 0}');
    // Khung giờ áp dụng: trước đây 2 ô nhập tay riêng biệt (dễ gõ startHour >
    // endHour mà không có gì chặn) - giờ 1 RangeSlider tự đảm bảo start <= end,
    // kèm 1 công tắc bật/tắt để giữ được ngữ nghĩa "bỏ trống = áp dụng mọi giờ"
    // (null/null) mà slider (luôn có giá trị cụ thể) không tự biểu diễn được.
    bool useHourRange = d?['startHour'] != null || d?['endHour'] != null;
    RangeValues hourRange = RangeValues(
      (d?['startHour'] as num?)?.toDouble() ?? 0,
      (d?['endHour'] as num?)?.toDouble() ?? 24,
    );
    String group = (d?['group'] as String?) ?? 'custom';
    if (!_groups.contains(group)) group = 'custom';
    String adjustmentType = (d?['adjustmentType'] as String?) ?? 'fixed';
    String? sessionType = d?['sessionType'] as String?;
    final selectedDays = <int>{...((d?['daysOfWeek'] as List?)?.map((e) => (e as num).toInt()) ?? const <int>[])};
    bool active = (d?['status'] as String? ?? 'active') == 'active';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: const Color(0xFF16161F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            existing == null ? 'THÊM LUẬT GIÁ' : 'SỬA LUẬT GIÁ',
            style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _field(labelCtrl, 'Tên luật (vd: Phụ thu cuối tuần) *'),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: group,
                    dropdownColor: const Color(0xFF1E1E2A),
                    decoration: _dropdownDecoration('Nhóm (cùng nhóm: ưu tiên cao nhất thắng)'),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    items: _groups
                        .map((g) => DropdownMenuItem(value: g, child: Text(_groupLabels[g] ?? g)))
                        .toList(),
                    onChanged: (v) => setState(() => group = v ?? 'custom'),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: adjustmentType,
                        dropdownColor: const Color(0xFF1E1E2A),
                        decoration: _dropdownDecoration('Kiểu'),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        items: const [
                          DropdownMenuItem(value: 'fixed', child: Text('Cộng tiền (đ)')),
                          DropdownMenuItem(value: 'percent', child: Text('Phần trăm (%)')),
                        ],
                        onChanged: (v) => setState(() => adjustmentType = v ?? 'fixed'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _field(
                      valueCtrl, 'Giá trị (âm = giảm)',
                      inputType: TextInputType.numberWithOptions(signed: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d-]'))],
                    )),
                  ]),
                  _field(
                    priorityCtrl, 'Ưu tiên (số lớn thắng khi cùng nhóm)',
                    inputType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const Divider(color: Colors.white12, height: 24),
                  const Text('ĐIỀU KIỆN ÁP DỤNG (bỏ trống = áp dụng tất cả)',
                      style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: sessionType,
                    dropdownColor: const Color(0xFF1E1E2A),
                    decoration: _dropdownDecoration('Loại suất chiếu'),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('(Mọi loại suất)')),
                      ...kSessionTypeSpecs.map((s) => DropdownMenuItem<String?>(value: s.name, child: Text(s.name))),
                    ],
                    onChanged: (v) => setState(() => sessionType = v),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    children: List.generate(7, (i) {
                      final weekday = i + 1;
                      final selected = selectedDays.contains(weekday);
                      return FilterChip(
                        label: Text(_dayLabels[i], style: TextStyle(color: selected ? Colors.black : Colors.white70, fontSize: 11)),
                        selected: selected,
                        selectedColor: Colors.greenAccent,
                        backgroundColor: const Color(0xFF1E1E2A),
                        onSelected: (v) => setState(() => v ? selectedDays.add(weekday) : selectedDays.remove(weekday)),
                      );
                    }),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Switch(
                      value: useHourRange,
                      onChanged: (v) => setState(() => useHourRange = v),
                      activeThumbColor: Colors.greenAccent,
                    ),
                    const Text('Giới hạn theo khung giờ', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ]),
                  if (useHourRange) ...[
                    Text(
                      'Từ ${hourRange.start.round()}h đến trước ${hourRange.end.round()}h',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    RangeSlider(
                      values: hourRange,
                      min: 0,
                      max: 24,
                      divisions: 24,
                      activeColor: Colors.greenAccent,
                      inactiveColor: Colors.white12,
                      labels: RangeLabels('${hourRange.start.round()}h', '${hourRange.end.round()}h'),
                      onChanged: (v) => setState(() => hourRange = v),
                    ),
                  ],
                  Row(children: [
                    Switch(
                      value: active,
                      onChanged: (v) => setState(() => active = v),
                      activeThumbColor: Colors.greenAccent,
                    ),
                    Text(active ? 'Đang áp dụng' : 'Tạm tắt', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ]),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('HỦY', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: () async {
                if (labelCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                final data = {
                  'label': labelCtrl.text.trim(),
                  'group': group,
                  'priority': int.tryParse(priorityCtrl.text) ?? 0,
                  'adjustmentType': adjustmentType,
                  'adjustmentValue': int.tryParse(valueCtrl.text) ?? 0,
                  'sessionType': sessionType,
                  'daysOfWeek': selectedDays.isEmpty ? null : (selectedDays.toList()..sort()),
                  'startHour': useHourRange ? hourRange.start.round() : null,
                  'endHour': useHourRange ? hourRange.end.round() : null,
                  'status': active ? 'active' : 'inactive',
                };
                final col = FirebaseFirestore.instance.collection('pricing_rules');
                if (existing == null) {
                  final ref = await col.add({...data, 'createdAt': Timestamp.now()});
                  await logAdminAction(action: 'create_pricing_rule', targetCollection: 'pricing_rules', targetId: ref.id, after: data);
                } else {
                  await col.doc(existing.id).update(data);
                  await logAdminAction(
                      action: 'update_pricing_rule',
                      targetCollection: 'pricing_rules',
                      targetId: existing.id,
                      before: existing.data() as Map<String, dynamic>,
                      after: data);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent),
              child: Text(existing == null ? 'THÊM' : 'CẬP NHẬT',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  static InputDecoration _dropdownDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
        filled: true,
        fillColor: const Color(0xFF1E1E2A),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );

  static Widget _field(
    TextEditingController ctrl,
    String label, {
    TextInputType inputType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: inputType,
        inputFormatters: inputFormatters,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
          filled: true,
          fillColor: const Color(0xFF1E1E2A),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  const _RuleTile({required this.doc});

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final active = (d['status'] as String? ?? 'active') == 'active';
    final isPercent = d['adjustmentType'] == 'percent';
    final value = (d['adjustmentValue'] as num? ?? 0).toInt();
    final amountLabel = isPercent
        ? '${value > 0 ? '+' : ''}$value%'
        : '${value > 0 ? '+' : ''}${value.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}đ';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF16161F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: active ? Colors.greenAccent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(d['label'] ?? '—',
                        style: TextStyle(
                            color: active ? Colors.white : Colors.white38, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (value >= 0 ? Colors.greenAccent : Colors.orangeAccent).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(amountLabel,
                        style: TextStyle(
                            color: value >= 0 ? Colors.greenAccent : Colors.orangeAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                  if (!active) ...[
                    const SizedBox(width: 6),
                    const Text('(tắt)', style: TextStyle(color: Colors.white24, fontSize: 10)),
                  ],
                ]),
                const SizedBox(height: 4),
                Text(
                  '${AdminPricingRulesScreen._groupLabels[d['group']] ?? d['group']} • Ưu tiên ${d['priority'] ?? 0} • ${AdminPricingRulesScreen.describeMatchers(d)}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: Colors.greenAccent, size: 18),
            onPressed: () => AdminPricingRulesScreen._showRuleDialog(context, doc),
          ),
          IconButton(
            icon: const Icon(Icons.delete_rounded, color: Colors.redAccent, size: 18),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF16161F),
                  title: const Text('XOÁ LUẬT GIÁ', style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                  content: Text('Xoá luật "${d['label']}"? Giá vé sẽ thay đổi ngay với các suất chiếu đang mở bán.',
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('HỦY', style: TextStyle(color: Colors.grey))),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                      child: const Text('XOÁ', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await doc.reference.delete();
                await logAdminAction(action: 'delete_pricing_rule', targetCollection: 'pricing_rules', targetId: doc.id, before: d);
              }
            },
          ),
        ],
      ),
    );
  }
}
