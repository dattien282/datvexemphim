import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/room_layout.dart';
import 'admin_audit_log.dart';

/// CRUD collection 'room_formats' (Giai đoạn H) - thay cho việc danh mục
/// định dạng phòng chiếu (Standard/VIP/IMAX/4DX/Gold Class...) nằm cứng
/// trong kDefaultRoomFormatSpecs (models/room_layout.dart), phải sửa code +
/// build lại app mỗi lần muốn thêm/sửa định dạng. Toàn app đọc collection
/// này qua 1 cache đồng bộ (xem room_layout.dart updateRoomFormatCache, đồng
/// bộ bởi providers/room_formats_provider.dart ở main.dart) nên sửa ở đây có
/// hiệu lực ngay, không cần build lại app.
///
/// Trước khi dùng màn này lần đầu: vào "Cấu hình Server" bấm "SEED DANH MỤC
/// ĐỊNH DẠNG PHÒNG" để đưa 13 định dạng mặc định vào Firestore.
class AdminRoomFormatsScreen extends StatelessWidget {
  const AdminRoomFormatsScreen({super.key});

  static const _seatLayoutKinds = ['standard', 'allSingleLarge', 'allCouple', 'motion'];
  static const _seatLayoutKindLabels = {
    'standard': 'Ghế Thường + VIP (2 loại trong 1 phòng)',
    'allSingleLarge': 'Toàn ghế đơn cỡ lớn (Recliner)',
    'allCouple': 'Toàn ghế đôi (Sofa/Couple)',
    'motion': 'Ghế Motion (rung/chuyển động - 4DX)',
  };
  static const _theaterSizes = ['Small', 'Medium', 'Large'];
  static const _colorPalette = [
    Colors.blueAccent, Colors.amber, Colors.deepPurple, Colors.purpleAccent,
    Colors.cyanAccent, Colors.deepOrangeAccent, Colors.indigoAccent, Colors.lightGreenAccent,
    Colors.lightBlueAccent, Colors.redAccent, Colors.tealAccent, Colors.pinkAccent,
    Colors.orangeAccent, Colors.greenAccent,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text('ĐỊNH DẠNG PHÒNG CHIẾU',
            style: TextStyle(color: Colors.indigoAccent, fontWeight: FontWeight.bold, fontSize: 14)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: Colors.indigoAccent, size: 24),
            onPressed: () => _showFormatDialog(context, null),
            tooltip: 'Thêm định dạng',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('room_formats').snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.indigoAccent));
          }
          final docs = snap.data?.docs.toList() ?? [];
          docs.sort((a, b) =>
              ((a.data() as Map)['name'] as String? ?? '').compareTo((b.data() as Map)['name'] as String? ?? ''));
          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Chưa có định dạng nào trong Firestore - app đang dùng 13 định dạng mặc định '
                  'trong code (Standard, VIP, IMAX, 4DX...).\n\nVào "Cấu hình Server" bấm "SEED DANH MỤC '
                  'ĐỊNH DẠNG PHÒNG" để đưa chúng vào đây, hoặc bấm + để tạo định dạng đầu tiên.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, i) => _FormatTile(doc: docs[i]),
          );
        },
      ),
    );
  }

  static void _showFormatDialog(BuildContext context, QueryDocumentSnapshot? existing) {
    final d = existing?.data() as Map<String, dynamic>?;
    final spec = d != null ? RoomFormatSpec.fromMap(existing!.id, d) : null;

    final nameCtrl = TextEditingController(text: spec?.name ?? '');
    final hintCtrl = TextEditingController(text: spec?.hint ?? '');
    final stdCtrl = TextEditingController(text: '${spec?.standardRows ?? 0}');
    final vipCtrl = TextEditingController(text: '${spec?.vipRows ?? 0}');
    final sweetCtrl = TextEditingController(text: '${spec?.sweetboxRows ?? 0}');
    final perRowCtrl = TextEditingController(text: '${spec?.seatsPerRow ?? 10}');
    String seatLayoutKind = seatLayoutKindToString(spec?.seatLayoutKind ?? SeatLayoutKind.standard);
    bool isPremium = spec?.isPremium ?? true;
    bool active = (spec?.status ?? 'active') == 'active';
    Color color = spec?.color ?? _colorPalette.first;
    final theaterSizes = <String>{...(spec?.allowedTheaterSizes ?? _theaterSizes.toSet())};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: const Color(0xFF16161F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            existing == null ? 'THÊM ĐỊNH DẠNG PHÒNG' : 'SỬA ĐỊNH DẠNG PHÒNG',
            style: const TextStyle(color: Colors.indigoAccent, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _field(nameCtrl, 'Tên định dạng (vd: Dolby Cinema) *'),
                  _field(hintCtrl, 'Mô tả ngắn (hiện dưới dropdown khi tạo phòng)'),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: seatLayoutKind,
                    dropdownColor: const Color(0xFF1E1E2A),
                    isExpanded: true,
                    decoration: _dropdownDecoration('Kiểu ghế'),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    items: _seatLayoutKinds
                        .map((k) => DropdownMenuItem(value: k, child: Text(_seatLayoutKindLabels[k] ?? k, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) => setState(() => seatLayoutKind = v ?? 'standard'),
                  ),
                  const SizedBox(height: 10),
                  const Text('SỐ HÀNG GHẾ GỢI Ý (preset khi tạo phòng mới)',
                      style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _field(stdCtrl, 'Hàng Thường', inputType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
                    const SizedBox(width: 8),
                    Expanded(child: _field(vipCtrl, 'Hàng VIP/ghế lớn', inputType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
                  ]),
                  Row(children: [
                    Expanded(child: _field(sweetCtrl, 'Hàng ghế đôi', inputType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
                    const SizedBox(width: 8),
                    Expanded(child: _field(perRowCtrl, 'Ghế/hàng', inputType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
                  ]),
                  const Divider(color: Colors.white12, height: 24),
                  const Text('RẠP QUY MÔ NÀO ĐƯỢC MỞ ĐỊNH DẠNG NÀY',
                      style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  // Chỉ 3 giá trị - hiện hết dạng chip thay vì giấu trong dropdown/checkbox list.
                  Wrap(
                    spacing: 6,
                    children: _theaterSizes.map((size) {
                      final selected = theaterSizes.contains(size);
                      return FilterChip(
                        label: Text(size, style: TextStyle(color: selected ? Colors.black : Colors.white70, fontSize: 11)),
                        selected: selected,
                        selectedColor: Colors.indigoAccent,
                        backgroundColor: const Color(0xFF1E1E2A),
                        onSelected: (v) => setState(() => v ? theaterSizes.add(size) : theaterSizes.remove(size)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  const Text('MÀU HIỂN THỊ', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _colorPalette.map((c) {
                      final selected = c.toARGB32() == color.toARGB32();
                      return GestureDetector(
                        onTap: () => setState(() => color = c),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 2),
                          ),
                          child: selected ? const Icon(Icons.check_rounded, color: Colors.black, size: 18) : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Switch(
                      value: isPremium,
                      onChanged: (v) => setState(() => isPremium = v),
                      activeThumbColor: Colors.indigoAccent,
                    ),
                    const Expanded(
                      child: Text('Định dạng cao cấp (giá cao hơn, không áp dụng ưu đãi Thứ 4)',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ),
                  ]),
                  Row(children: [
                    Switch(
                      value: active,
                      onChanged: (v) => setState(() => active = v),
                      activeThumbColor: Colors.indigoAccent,
                    ),
                    Text(active ? 'Đang cho chọn khi tạo phòng mới' : 'Đã ẩn (phòng cũ vẫn dùng bình thường)',
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('HỦY', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty || theaterSizes.isEmpty) return;
                Navigator.pop(ctx);
                final newSpec = RoomFormatSpec(
                  name: nameCtrl.text.trim(),
                  color: color,
                  isPremium: isPremium,
                  seatLayoutKind: seatLayoutKindFromString(seatLayoutKind),
                  standardRows: int.tryParse(stdCtrl.text) ?? 0,
                  vipRows: int.tryParse(vipCtrl.text) ?? 0,
                  sweetboxRows: int.tryParse(sweetCtrl.text) ?? 0,
                  seatsPerRow: int.tryParse(perRowCtrl.text) ?? 10,
                  hint: hintCtrl.text.trim(),
                  allowedTheaterSizes: theaterSizes,
                  status: active ? 'active' : 'archived',
                );
                final data = newSpec.toMap();
                final col = FirebaseFirestore.instance.collection('room_formats');
                if (existing == null) {
                  final ref = await col.add(data);
                  await logAdminAction(action: 'create_room_format', targetCollection: 'room_formats', targetId: ref.id, after: data);
                } else {
                  await col.doc(existing.id).update(data);
                  await logAdminAction(
                      action: 'update_room_format',
                      targetCollection: 'room_formats',
                      targetId: existing.id,
                      before: d,
                      after: data);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigoAccent),
              child: Text(existing == null ? 'THÊM' : 'CẬP NHẬT',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

// Ước lượng sức chứa từ preset số hàng/ghế mỗi hàng (ghế đôi tính 2 chỗ ngồi
// mỗi cặp) - chỉ mang tính tham khảo hiển thị trong danh sách, phòng thật có
// thể chỉnh riêng số hàng khác preset này.
int _estimatedSeats(RoomFormatSpec spec) =>
    (spec.standardRows + spec.vipRows) * spec.seatsPerRow + spec.sweetboxRows * spec.seatsPerRow;

class _FormatTile extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  const _FormatTile({required this.doc});

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final spec = RoomFormatSpec.fromMap(doc.id, d);
    final active = spec.status == 'active';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF16161F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: active ? spec.color.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: spec.color, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(spec.name,
                        style: TextStyle(color: active ? Colors.white : Colors.white38, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  if (spec.isPremium) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                      child: const Text('CAO CẤP', style: TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ],
                  if (!active) ...[
                    const SizedBox(width: 6),
                    const Text('(đã ẩn)', style: TextStyle(color: Colors.white24, fontSize: 10)),
                  ],
                ]),
                const SizedBox(height: 4),
                Text(
                  '${spec.allowedTheaterSizes.join(', ')} • ~${_estimatedSeats(spec)} ghế',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: Colors.indigoAccent, size: 18),
            onPressed: () => AdminRoomFormatsScreen._showFormatDialog(context, doc),
          ),
          IconButton(
            icon: const Icon(Icons.delete_rounded, color: Colors.redAccent, size: 18),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF16161F),
                  title: const Text('XOÁ ĐỊNH DẠNG', style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                  content: Text(
                    'Xoá định dạng "${spec.name}"? Nếu còn phòng chiếu đang dùng định dạng này, '
                    'phòng đó sẽ hiển thị lỗi. Cân nhắc ẨN (tắt công tắc "Đang cho chọn") thay vì xoá hẳn.',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
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
                await logAdminAction(action: 'delete_room_format', targetCollection: 'room_formats', targetId: doc.id, before: d);
              }
            },
          ),
        ],
      ),
    );
  }
}
