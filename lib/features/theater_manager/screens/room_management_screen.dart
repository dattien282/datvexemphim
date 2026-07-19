import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/room_layout.dart';
import '../../../models/showtime.dart';
import '../widgets/seat_grid_widget.dart';

// Bảng cấu hình định dạng phòng, enum SeatLayoutKind, và helper
// roomFormatsForTheaterSize/findRoomFormatSpec đều sống ở
// models/room_layout.dart (data domain dùng chung cho cả UI lẫn migration ở
// db_updater.dart) - ở đây chỉ derive vài hằng số/hàm tiện dùng riêng cho UI.
// Đọc qua liveRoomFormatSpecs (cache đồng bộ, cập nhật ngầm từ collection
// Firestore 'room_formats') thay vì hằng số hardcode - để định dạng admin tự
// thêm mới qua AdminRoomFormatsScreen xuất hiện ngay ở đây không cần build lại app.

List<String> get kRoomFormats => liveRoomFormatSpecs.map((s) => s.name).toList();

/// Định dạng "cao cấp trở lên": áp giá vé cao hơn phòng thường (xem
/// seat_booking_screen.dart) và không được áp dụng ưu đãi Thứ 4 (xem
/// discount_service.dart) - vì đây đã là phân khúc cao cấp, không cần
/// thêm khuyến mãi giảm giá sâu.
Set<String> get kPremiumRoomFormats =>
    liveRoomFormatSpecs.where((s) => s.isPremium).map((s) => s.name).toSet();

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
              // Trạng thái vận hành của phòng (Giai đoạn E): ACTIVE (mặc
              // định) / MAINTENANCE (đang sửa chữa - không tạo được suất
              // chiếu mới, suất đã có không ảnh hưởng). Không xoá phòng khi
              // ngưng dùng - dùng trạng thái này thay thế.
              final roomStatus = d['status'] as String? ?? 'ACTIVE';
              final isMaintenance = roomStatus == 'MAINTENANCE';
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161F),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.15)),
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
                                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                                child: Text(format, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
                              ),
                              if (isMaintenance) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: Colors.orangeAccent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6)),
                                  child: const Text('BẢO TRÌ',
                                      style: TextStyle(color: Colors.orangeAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                                ),
                              ],
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
                          await _confirmAndDeleteRoom(context, docs[i], theater);
                        } else if (v == 'maintenance') {
                          _SeatMaintenanceDialog.show(context, roomDoc: docs[i]);
                        } else if (v == 'roomStatus') {
                          await docs[i].reference.update({'status': isMaintenance ? 'ACTIVE' : 'MAINTENANCE'});
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('Chỉnh sửa', style: TextStyle(color: Colors.white))),
                        const PopupMenuItem(value: 'maintenance', child: Text('Bảo trì ghế', style: TextStyle(color: Colors.orangeAccent))),
                        PopupMenuItem(
                          value: 'roomStatus',
                          child: Text(
                            isMaintenance ? 'Mở lại phòng' : 'Bảo trì cả phòng',
                            style: TextStyle(color: isMaintenance ? Colors.greenAccent : Colors.deepOrangeAccent),
                          ),
                        ),
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

/// Chặn xoá phòng nếu còn suất chiếu `active` chưa diễn ra - trước đây xoá
/// phòng không kiểm tra gì cả, để lại suất chiếu "mồ côi" (phòng không còn
/// tồn tại nhưng suất chiếu vẫn hiển thị cho khách đặt vé, seat_booking_screen.dart
/// sẽ không tìm được sơ đồ ghế cho suất chiếu mới tạo sau đó vì phòng đã mất -
/// vé/suất chiếu CŨ đã có seatMapVersionId riêng vẫn không bị ảnh hưởng, xem
/// models/showtime.dart). Quản lý phải huỷ hoặc đổi phòng cho các suất chiếu
/// đó trước khi xoá được phòng.
Future<void> _confirmAndDeleteRoom(BuildContext context, QueryDocumentSnapshot roomDoc, String theater) async {
  final roomData = roomDoc.data() as Map<String, dynamic>;
  final roomName = roomData['roomName'] as String? ?? '';

  final now = DateTime.now();
  final showtimesSnap = await FirebaseFirestore.instance
      .collection('showtimes')
      .where('theaterName', isEqualTo: theater)
      .where('roomName', isEqualTo: roomName)
      .where('status', isEqualTo: 'active')
      .get();
  final upcomingCount = showtimesSnap.docs
      .map((d) => Showtime.fromMap(d.id, d.data()).showAt)
      .where((showAt) => showAt == null || showAt.isAfter(now))
      .length;

  if (!context.mounted) return;

  if (upcomingCount > 0) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('KHÔNG THỂ XOÁ PHÒNG', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14)),
        content: Text(
          'Phòng "$roomName" còn $upcomingCount suất chiếu chưa diễn ra. Vui lòng huỷ hoặc chuyển các suất chiếu đó sang phòng khác trước khi xoá phòng này.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ĐÃ HIỂU', style: TextStyle(color: Colors.grey))),
        ],
      ),
    );
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF16161F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('XOÁ PHÒNG CHIẾU', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14)),
      content: Text(
        'Bạn có chắc muốn xoá phòng "$roomName"? Suất chiếu/vé cũ (nếu có, đã qua) vẫn giữ đúng sơ đồ ghế lịch sử, không bị ảnh hưởng.',
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('HỦY', style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
          child: const Text('XOÁ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await roomDoc.reference.delete();
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

  // Danh sách tổ hợp trình chiếu/âm thanh phòng này hỗ trợ (RoomCapability,
  // xem models/room_layout.dart) - tách khỏi _format (vốn chỉ quyết định
  // loại ghế + phân khúc giá). 1 phòng IMAX có thể vừa chiếu IMAX 2D vừa
  // IMAX 3D, nên đây là danh sách chứ không phải 1 giá trị.
  List<RoomCapability> _capabilities = [];
  String _newProjection = kProjectionFormats.first;
  String _newSound = kSoundFormats.first;

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
      _capabilities = parseCapabilities(d['capabilities'], _format);
    } else {
      _capabilities = defaultCapabilitiesForFormat(_format);
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
              isExpanded: true,
              initialValue: _format,
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
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Định dạng trình chiếu phòng này hỗ trợ',
                  style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final cap in _capabilities)
                  Chip(
                    backgroundColor: const Color(0xFF1E1E2A),
                    label: Text(cap.label, style: const TextStyle(color: Colors.white, fontSize: 11)),
                    deleteIconColor: Colors.white38,
                    onDeleted: _capabilities.length > 1
                        ? () => setState(() => _capabilities.remove(cap))
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _newProjection,
                  dropdownColor: const Color(0xFF1E1E2A),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF1E1E2A),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  items: kProjectionFormats.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                  onChanged: (v) => setState(() => _newProjection = v ?? kProjectionFormats.first),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _newSound,
                  dropdownColor: const Color(0xFF1E1E2A),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF1E1E2A),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  items: kSoundFormats.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                  onChanged: (v) => setState(() => _newSound = v ?? kSoundFormats.first),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_rounded, color: Colors.deepPurpleAccent),
                onPressed: () {
                  final newCap = RoomCapability(projectionFormat: _newProjection, soundFormat: _newSound);
                  if (_capabilities.contains(newCap)) return;
                  setState(() => _capabilities.add(newCap));
                },
              ),
            ]),
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

    // Các field ảnh hưởng sơ đồ ghế thật (số hàng/ghế, kiểu ghế, ghế hỏng)
    // được snapshot vào 1 document `seat_map_versions` MỚI mỗi lần lưu, thay
    // vì update tại chỗ trên document phòng - suất chiếu nào đã chốt
    // seatMapVersionId trước đó (xem models/showtime.dart) sẽ luôn tra đúng
    // sơ đồ tại thời điểm bán vé, không bị lệch khi phòng được sửa sau này.
    // `rooms/{id}` vẫn giữ 1 bản sao các field này (đọc nhanh cho danh sách/
    // dropdown), nhưng `seat_map_versions` mới là nguồn lịch sử thật.
    final layoutFields = {
      'theaterName': widget.theater,
      'roomName': roomName,
      'roomFormat': _format,
      'standardRows': int.tryParse(_stdCtrl.text) ?? 3,
      'vipRows': int.tryParse(_vipCtrl.text) ?? 5,
      'sweetboxRows': int.tryParse(_sweetCtrl.text) ?? 2,
      'seatsPerRow': int.tryParse(_perRowCtrl.text) ?? 10,
      'seatLayoutKind': seatLayoutKindToString(seatLayoutKindForFormat(_format)),
      'brokenSeats': (widget.existing?.data() as Map<String, dynamic>?)?['brokenSeats'] ?? [],
      'wheelchairSeats': (widget.existing?.data() as Map<String, dynamic>?)?['wheelchairSeats'] ?? [],
    };
    final roomData = {
      ...layoutFields,
      'capabilities': _capabilities.map((c) => c.toMap()).toList(),
    };

    final firestore = FirebaseFirestore.instance;
    final roomRef = widget.existing?.reference ?? firestore.collection('rooms').doc();
    final prevVersionId = (widget.existing?.data() as Map<String, dynamic>?)?['currentSeatMapVersionId'] as String?;
    final prevVersionNum = widget.existing == null
        ? 0
        : (prevVersionId != null
            ? ((await firestore.collection('seat_map_versions').doc(prevVersionId).get()).data()?['version'] as num? ?? 0).toInt()
            : 0);

    final newVersionRef = firestore.collection('seat_map_versions').doc();
    final batch = firestore.batch();
    batch.set(newVersionRef, {
      ...layoutFields,
      'roomId': roomRef.id,
      'version': prevVersionNum + 1,
      'status': 'active',
      'createdAt': Timestamp.now(),
    });
    if (prevVersionId != null) {
      batch.update(firestore.collection('seat_map_versions').doc(prevVersionId), {'status': 'superseded'});
    }
    batch.set(roomRef, {...roomData, 'currentSeatMapVersionId': newVersionRef.id}, SetOptions(merge: true));
    await batch.commit();

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
  late Set<String> _wheelchairSeats;
  MaintenanceTarget _target = MaintenanceTarget.broken;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.roomDoc.data() as Map<String, dynamic>;
    _layout = RoomLayout.fromMap(widget.roomDoc.id, d);
    _brokenSeats = {..._layout.brokenSeats};
    _wheelchairSeats = {..._layout.wheelchairSeats};
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

  void _toggleWheelchair(String seatId) {
    setState(() {
      if (_wheelchairSeats.contains(seatId)) {
        _wheelchairSeats.remove(seatId);
      } else {
        _wheelchairSeats.add(seatId);
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // Đánh dấu ghế hỏng là thao tác bảo trì tạm thời (KHÔNG phải đổi cấu
      // trúc phòng như số hàng/ghế), nên ghi thẳng vào version hiện tại thay
      // vì tạo version mới (tránh version tăng vô tội vạ mỗi lần bật/tắt 1
      // ghế hỏng). Ghi cả vào document phòng để giữ bản sao cache hiển thị
      // nhanh (room_management_screen.dart list, seat_grid_widget mặc định).
      final currentVersionId = (widget.roomDoc.data() as Map<String, dynamic>)['currentSeatMapVersionId'] as String?;
      final maintenanceFields = {
        'brokenSeats': _brokenSeats.toList(),
        'wheelchairSeats': _wheelchairSeats.toList(),
      };
      final batch = FirebaseFirestore.instance.batch();
      batch.update(widget.roomDoc.reference, maintenanceFields);
      if (currentVersionId != null) {
        batch.update(
          FirebaseFirestore.instance.collection('seat_map_versions').doc(currentVersionId),
          maintenanceFields,
        );
      }
      await batch.commit();
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
              const Text('Chạm vào ghế để đánh dấu/gỡ đánh dấu theo loại đang chọn', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('GHẾ HỎNG', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      avatar: Icon(Icons.build_rounded, size: 14,
                          color: _target == MaintenanceTarget.broken ? Colors.black : Colors.redAccent),
                      selected: _target == MaintenanceTarget.broken,
                      selectedColor: Colors.redAccent,
                      backgroundColor: const Color(0xFF16161F),
                      labelStyle: TextStyle(color: _target == MaintenanceTarget.broken ? Colors.black : Colors.white70),
                      onSelected: (_) => setState(() => _target = MaintenanceTarget.broken),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('GHẾ XE LĂN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      avatar: Icon(Icons.accessible_rounded, size: 14,
                          color: _target == MaintenanceTarget.wheelchair ? Colors.black : Colors.blueAccent),
                      selected: _target == MaintenanceTarget.wheelchair,
                      selectedColor: Colors.blueAccent,
                      backgroundColor: const Color(0xFF16161F),
                      labelStyle: TextStyle(color: _target == MaintenanceTarget.wheelchair ? Colors.black : Colors.white70),
                      onSelected: (_) => setState(() => _target = MaintenanceTarget.wheelchair),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
                maintenanceTarget: _target,
                brokenSeats: _brokenSeats,
                wheelchairSeats: _wheelchairSeats,
                onToggleBroken: _toggleSeat,
                onToggleWheelchair: _toggleWheelchair,
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
