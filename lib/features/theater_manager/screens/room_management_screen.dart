import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/room_layout.dart';
import '../widgets/seat_grid_widget.dart';

// Bảng cấu hình định dạng phòng (kRoomFormatSpecs), enum SeatLayoutKind, và
// helper roomFormatsForTheaterSize/findRoomFormatSpec đều sống ở
// models/room_layout.dart (data domain dùng chung cho cả UI lẫn migration ở
// db_updater.dart) - ở đây chỉ derive vài hằng số/hàm tiện dùng riêng cho UI.

List<String> get kRoomFormats => kRoomFormatSpecs.map((s) => s.name).toList();

/// Định dạng "cao cấp trở lên": áp giá vé cao hơn phòng thường (xem
/// seat_booking_screen.dart) và không được áp dụng ưu đãi Thứ 4 (xem
/// discount_service.dart) - vì đây đã là phân khúc cao cấp, không cần
/// thêm khuyến mãi giảm giá sâu.
Set<String> get kPremiumRoomFormats =>
    kRoomFormatSpecs.where((s) => s.isPremium).map((s) => s.name).toSet();

Color roomFormatColor(String? format) => findRoomFormatSpec(format)?.color ?? Colors.blueAccent;

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
              final format = d['roomFormat'] as String? ?? 'Standard';
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
                        } else if (v == 'maintenance') {
                          _SeatMaintenanceDialog.show(context, roomDoc: docs[i]);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('Chỉnh sửa', style: TextStyle(color: Colors.white))),
                        const PopupMenuItem(value: 'maintenance', child: Text('Bảo trì ghế', style: TextStyle(color: Colors.orangeAccent))),
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
  // Quy mô rạp (Small/Medium/Large) - quyết định định dạng nào được phép
  // chọn (roomFormatsForTheaterSize). null trong lúc đang tải.
  String? _theaterSize;

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
    _loadTheaterSize();
  }

  Future<void> _loadTheaterSize() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('theaters')
          .where('name', isEqualTo: widget.theater)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty && mounted) {
        setState(() => _theaterSize = snap.docs.first.data()['size'] as String? ?? 'Medium');
      }
    } catch (_) {
      // Giữ null (roomFormatsForTheaterSize mặc định coi như 'Medium') nếu lỗi mạng.
    }
  }

  // Định dạng hiển thị trong dropdown: giới hạn theo quy mô rạp, nhưng luôn
  // giữ định dạng hiện tại trong danh sách (kể cả khi không còn phù hợp quy
  // mô rạp, VD rạp bị đổi size sau khi đã có phòng VIP) để dropdown không bị
  // lỗi "value không khớp item nào".
  List<String> _dropdownFormats() {
    final allowed = roomFormatsForTheaterSize(_theaterSize);
    return allowed.contains(_format) ? allowed : [...allowed, _format];
  }

  // Preset gợi ý ghế theo định dạng phòng khi chọn - quản lý vẫn chỉnh số
  // lượng được nếu muốn.
  void _applyFormatPreset(String format) {
    final spec = findRoomFormatSpec(format);
    setState(() {
      _format = format;
      if (spec != null) {
        _stdCtrl.text = '${spec.standardRows}';
        _vipCtrl.text = '${spec.vipRows}';
        _sweetCtrl.text = '${spec.sweetboxRows}';
        _perRowCtrl.text = '${spec.seatsPerRow}';
      }
    });
  }

  String? _formatHint(String format) => findRoomFormatSpec(format)?.hint;

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
              items: _dropdownFormats().map((f) => DropdownMenuItem(value: f, child: Text(f, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => _applyFormatPreset(v ?? kRoomFormats.first),
            ),
            if (_theaterSize != null && !roomFormatsForTheaterSize(_theaterSize).contains(_format))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Định dạng này không còn phù hợp với quy mô rạp hiện tại ($_theaterSize).',
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 10),
                ),
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
                  findRoomFormatSpec(_format)?.seatLayoutKind == SeatLayoutKind.allSingleLarge ? 'Hàng ghế đơn cỡ lớn' : 'Hàng VIP',
                  Icons.star_rounded,
                  type: TextInputType.number)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _field(
                  _sweetCtrl,
                  findRoomFormatSpec(_format)?.seatLayoutKind == SeatLayoutKind.allCouple ? 'Hàng ghế đôi' : 'Hàng Sweetbox',
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
      'seatLayoutKind': seatLayoutKindToString(seatLayoutKindForFormat(_format)),
    };
    if (widget.existing != null) {
      await widget.existing!.reference.update(data);
    } else {
      await FirebaseFirestore.instance.collection('rooms').add(data);
    }
    if (mounted) Navigator.pop(context);
  }
}

class _SeatMaintenanceDialog extends StatefulWidget {
  final QueryDocumentSnapshot roomDoc;
  const _SeatMaintenanceDialog({required this.roomDoc});

  static Future<void> show(BuildContext context, {required QueryDocumentSnapshot roomDoc}) {
    return showDialog(context: context, builder: (_) => _SeatMaintenanceDialog(roomDoc: roomDoc));
  }

  @override
  State<_SeatMaintenanceDialog> createState() => _SeatMaintenanceDialogState();
}

class _SeatMaintenanceDialogState extends State<_SeatMaintenanceDialog> {
  late RoomLayout _layout;
  late Set<String> _brokenSeats;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.roomDoc.data() as Map<String, dynamic>;
    _layout = RoomLayout.fromMap(widget.roomDoc.id, d);
    _brokenSeats = {..._layout.brokenSeats};
  }

  void _toggleSeat(String seatId) {
    setState(() {
      if (_brokenSeats.contains(seatId)) {
        _brokenSeats.remove(seatId);
      } else {
        _brokenSeats.add(seatId);
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.roomDoc.reference.update({
        'brokenSeats': _brokenSeats.toList(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E2A),
      title: const Text('Bảo trì ghế', style: TextStyle(color: Colors.orangeAccent)),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Chạm vào ghế để đánh dấu hỏng/bảo trì', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 20),
              // Screen curve
              Container(
                height: 40,
                alignment: Alignment.bottomCenter,
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Colors.white38, width: 2),
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.elliptical(200, 30),
                    topRight: Radius.elliptical(200, 30),
                  ),
                ),
                child: const Text('MÀN HÌNH', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 2)),
              ),
              const SizedBox(height: 30),
              SeatGridView(
                layout: _layout,
                mode: SeatGridMode.maintenance,
                brokenSeats: _brokenSeats,
                onToggleBroken: _toggleSeat,
                dense: true,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy', style: TextStyle(color: Colors.white54))),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)) : const Text('Lưu', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
