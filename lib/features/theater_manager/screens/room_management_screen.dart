import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Định dạng phòng chiếu: quyết định phim gì phù hợp (phụ đề cho phim người
/// thật, lồng tiếng cho phim hoạt hình) và hạng ghế (VIP/Premium cho rạp lớn).
/// Suất chiếu (showtimes) denormalize field này từ phòng lúc tạo, để hiển thị
/// ở showtime_selection_screen.dart mà không cần query thêm.
const List<String> kRoomFormats = [
  '2D Phụ đề',
  '2D Lồng tiếng',
  'VIP',
  'Premium',
  'GoldClass',
  "L'amour",
];

Color roomFormatColor(String? format) {
  switch (format) {
    case 'VIP':
      return Colors.amber;
    case 'Premium':
      return Colors.pinkAccent;
    case 'GoldClass':
      return const Color(0xFFD4AF37); // vàng gold đậm, khác VIP amber
    case "L'amour":
      return Colors.redAccent;
    case '2D Lồng tiếng':
      return Colors.tealAccent;
    default:
      return Colors.blueAccent; // '2D Phụ đề' hoặc chưa đặt
  }
}

/// Per-room seat layout, keyed by (theaterName, roomName). Lets each theater
/// define its own room sizes instead of every room in the app sharing one
/// hardcoded 8-row + 2-sweetbox-row layout (see seat_booking_screen.dart).
class RoomManagementScreen extends StatelessWidget {
  final String theater;
  const RoomManagementScreen({super.key, required this.theater});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text('QUẢN LÝ PHÒNG CHIẾU',
            style: TextStyle(color: Colors.deepPurpleAccent, fontWeight: FontWeight.bold, fontSize: 14)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: Colors.deepPurpleAccent),
            onPressed: () => _RoomDialog.show(context, theater: theater),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('rooms')
            .where('theaterName', isEqualTo: theater)
            .snapshots(),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.weekend_rounded, color: Colors.white24, size: 48),
                  const SizedBox(height: 12),
                  const Text('Chưa có phòng chiếu nào.\nSuất chiếu sẽ dùng sơ đồ ghế mặc định.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.white38)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _RoomDialog.show(context, theater: theater),
                    icon: const Icon(Icons.add_rounded, color: Colors.black),
                    label: const Text('Tạo phòng đầu tiên', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              final format = d['roomFormat'] as String? ?? '2D Phụ đề';
              final color = roomFormatColor(format);
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161F),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.15)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.weekend_rounded, color: Colors.deepPurpleAccent, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(d['roomName'] ?? '—', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                                child: Text(format, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${d['standardRows'] ?? 0} hàng Thường • ${d['vipRows'] ?? 0} hàng VIP • ${d['sweetboxRows'] ?? 0} hàng Sweetbox • ${d['seatsPerRow'] ?? 10} ghế/hàng',
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, color: Colors.white38, size: 18),
                      color: const Color(0xFF1E1E2A),
                      onSelected: (v) async {
                        if (v == 'edit') {
                          _RoomDialog.show(context, theater: theater, existing: docs[i]);
                        } else if (v == 'delete') {
                          await docs[i].reference.delete();
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('Chỉnh sửa', style: TextStyle(color: Colors.white))),
                        const PopupMenuItem(value: 'delete', child: Text('Xóa', style: TextStyle(color: Colors.redAccent))),
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
}

class _RoomDialog {
  static Future<void> show(BuildContext context, {required String theater, QueryDocumentSnapshot? existing}) {
    return showDialog(context: context, builder: (ctx) => _RoomDialogWidget(theater: theater, existing: existing));
  }
}

class _RoomDialogWidget extends StatefulWidget {
  final String theater;
  final QueryDocumentSnapshot? existing;
  const _RoomDialogWidget({required this.theater, this.existing});

  @override
  State<_RoomDialogWidget> createState() => _RoomDialogWidgetState();
}

class _RoomDialogWidgetState extends State<_RoomDialogWidget> {
  final _nameCtrl = TextEditingController();
  final _stdCtrl = TextEditingController(text: '3');
  final _vipCtrl = TextEditingController(text: '5');
  final _sweetCtrl = TextEditingController(text: '2');
  final _perRowCtrl = TextEditingController(text: '10');
  String _format = kRoomFormats.first;

  @override
  void initState() {
    super.initState();
    final d = widget.existing?.data() as Map<String, dynamic>?;
    if (d != null) {
      _nameCtrl.text = d['roomName'] ?? '';
      _stdCtrl.text = '${d['standardRows'] ?? 3}';
      _vipCtrl.text = '${d['vipRows'] ?? 5}';
      _sweetCtrl.text = '${d['sweetboxRows'] ?? 2}';
      _perRowCtrl.text = '${d['seatsPerRow'] ?? 10}';
      _format = (d['roomFormat'] as String?) ?? kRoomFormats.first;
    }
  }

  // Preset gợi ý ghế theo định dạng phòng khi chọn - quản lý vẫn chỉnh số
  // lượng được nếu muốn. GoldClass/L'amour tái dùng field 'vipRows'/
  // 'sweetboxRows' sẵn có (ghế đơn cỡ lớn / ghế đôi) thay vì thêm field mới,
  // vì cơ chế hiển thị ghế đơn-lớn và ghế đôi đã có sẵn ở seat_booking_screen.dart
  // - chỉ cần gắn roomFormat để đổi màu/nhãn/kích thước khi render.
  void _applyFormatPreset(String format) {
    setState(() {
      _format = format;
      if (format == 'Premium') {
        _stdCtrl.text = '0';
        _vipCtrl.text = '0';
        _sweetCtrl.text = '3';
        _perRowCtrl.text = '6';
      } else if (format == 'GoldClass') {
        // Toàn bộ ghế đơn cỡ lớn (tái dùng field VIP), không có ghế đôi.
        _stdCtrl.text = '0';
        _vipCtrl.text = '4';
        _sweetCtrl.text = '0';
        _perRowCtrl.text = '6';
      } else if (format == "L'amour") {
        // Toàn bộ phòng chỉ có ghế đôi (tái dùng field Sweetbox).
        _stdCtrl.text = '0';
        _vipCtrl.text = '0';
        _sweetCtrl.text = '4';
        _perRowCtrl.text = '10';
      }
    });
  }

  String? _formatHint(String format) {
    switch (format) {
      case 'Premium':
        return "Premium: đã gợi ý hạn chế ghế, chỉ dùng hàng Sweetbox cao cấp nhất. Có thể chỉnh lại số hàng bên dưới.";
      case 'GoldClass':
        return "GoldClass: đã gợi ý toàn bộ ghế đơn cỡ lớn (nhập ở 'Hàng VIP'), không có ghế đôi, mỗi hàng ít ghế hơn để có khoảng ngả rộng.";
      case "L'amour":
        return "L'amour: đã gợi ý toàn bộ phòng chỉ bán theo ghế đôi (nhập ở 'Hàng Sweetbox'), không có ghế đơn.";
      default:
        return null;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _stdCtrl.dispose(); _vipCtrl.dispose(); _sweetCtrl.dispose(); _perRowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF16161F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(widget.existing != null ? 'CHỈNH SỬA PHÒNG' : 'THÊM PHÒNG CHIẾU',
          style: const TextStyle(color: Colors.deepPurpleAccent, fontWeight: FontWeight.bold, fontSize: 14)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(_nameCtrl, 'Tên phòng (VD: Phòng 1)', Icons.weekend_rounded),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _format,
              dropdownColor: const Color(0xFF1E1E2A),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1E1E2A),
                prefixIcon: const Icon(Icons.high_quality_rounded, color: Colors.deepPurpleAccent, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: kRoomFormats.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
              onChanged: (v) => _applyFormatPreset(v ?? kRoomFormats.first),
            ),
            if (_formatHint(_format) != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _formatHint(_format)!,
                    style: TextStyle(color: roomFormatColor(_format), fontSize: 10),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _field(_stdCtrl, 'Hàng Thường', Icons.event_seat_rounded, type: TextInputType.number)),
              const SizedBox(width: 8),
              Expanded(child: _field(
                  _vipCtrl,
                  _format == 'GoldClass' ? 'Hàng ghế Gold (đơn, lớn)' : 'Hàng VIP',
                  Icons.star_rounded,
                  type: TextInputType.number)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _field(
                  _sweetCtrl,
                  _format == "L'amour" ? "Hàng ghế đôi L'amour" : 'Hàng Sweetbox',
                  Icons.favorite_rounded,
                  type: TextInputType.number)),
              const SizedBox(width: 8),
              Expanded(child: _field(_perRowCtrl, 'Ghế/hàng', Icons.grid_view_rounded, type: TextInputType.number)),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('HỦY', style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
          child: Text(widget.existing != null ? 'CẬP NHẬT' : 'THÊM', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _field(TextEditingController ctrl, String hint, IconData icon, {TextInputType type = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
        prefixIcon: Icon(icon, color: Colors.deepPurpleAccent, size: 18),
        filled: true,
        fillColor: const Color(0xFF1E1E2A),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      ),
    );
  }

  Future<void> _save() async {
    final roomName = _nameCtrl.text.trim();
    if (roomName.isEmpty) return;
    final data = {
      'theaterName': widget.theater,
      'roomName': roomName,
      'roomFormat': _format,
      'standardRows': int.tryParse(_stdCtrl.text) ?? 3,
      'vipRows': int.tryParse(_vipCtrl.text) ?? 5,
      'sweetboxRows': int.tryParse(_sweetCtrl.text) ?? 2,
      'seatsPerRow': int.tryParse(_perRowCtrl.text) ?? 10,
    };
    if (widget.existing != null) {
      await widget.existing!.reference.update(data);
    } else {
      await FirebaseFirestore.instance.collection('rooms').add(data);
    }
    if (mounted) Navigator.pop(context);
  }
}
