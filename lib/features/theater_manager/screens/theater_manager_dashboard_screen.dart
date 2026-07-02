import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../main.dart';
import '../../../providers/user_provider.dart';
import 'theater_voucher_screen.dart';
import 'room_management_screen.dart' show RoomManagementScreen, roomFormatColor;

class TheaterManagerDashboardScreen extends StatefulWidget {
  final UserProfile managerProfile;
  const TheaterManagerDashboardScreen({super.key, required this.managerProfile});

  @override
  State<TheaterManagerDashboardScreen> createState() => _TheaterManagerDashboardScreenState();
}

class _TheaterManagerDashboardScreenState extends State<TheaterManagerDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theater = widget.managerProfile.assignedTheater ?? 'Chưa gán rạp';
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: Column(
          children: [
            const Text('QUẢN LÝ RẠP',
                style: TextStyle(color: Colors.deepPurpleAccent, fontWeight: FontWeight.bold, fontSize: 14)),
            Text(theater, style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ),
        automaticallyImplyLeading: false,
        actions: [
          if (_tab.index == 0) ...[
            IconButton(
              icon: const Icon(Icons.weekend_rounded, color: Colors.deepPurpleAccent),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => RoomManagementScreen(theater: theater)),
              ),
              tooltip: 'Quản lý phòng chiếu',
            ),
            IconButton(
              icon: const Icon(Icons.add_rounded, color: Colors.deepPurpleAccent),
              onPressed: () => _showAddShowtimeDialog(context, theater),
              tooltip: 'Thêm suất chiếu',
            ),
          ],
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            onPressed: () => _handleLogout(context),
            tooltip: 'Đăng xuất',
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.deepPurpleAccent,
          labelColor: Colors.deepPurpleAccent,
          unselectedLabelColor: Colors.white38,
          onTap: (_) => setState(() {}),
          tabs: const [
            Tab(text: 'SUẤT CHIẾU'),
            Tab(text: 'VÉ / DOANH THU'),
            Tab(text: 'NHÂN VIÊN'),
            Tab(text: 'VOUCHER'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _ShowtimesTab(theater: theater),
          _TheaterRevenueTab(theater: theater),
          _StaffListTab(theater: theater),
          TheaterVoucherTab(theater: theater),
        ],
      ),
    );
  }

  void _showAddShowtimeDialog(BuildContext context, String theater) {
    _ShowtimeDialog.show(context, theater: theater);
  }

  void _handleLogout(BuildContext context) async {
    final navigator = Navigator.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('ĐĂNG XUẤT', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 15)),
        content: const Text('Bạn có chắc muốn đăng xuất?', style: TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('KHÔNG', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ĐĂNG XUẤT', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainAppWrapper()),
        (route) => false,
      );
    }
  }
}

// ── Showtimes tab ──────────────────────────────────────────────────────────────
class _ShowtimesTab extends StatelessWidget {
  final String theater;
  const _ShowtimesTab({required this.theater});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('showtimes')
          .where('theaterName', isEqualTo: theater)
          .orderBy('date')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.event_busy_rounded, color: Colors.white24, size: 48),
                const SizedBox(height: 12),
                const Text('Chưa có suất chiếu nào.', style: TextStyle(color: Colors.white38)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _ShowtimeDialog.show(context, theater: theater),
                  icon: const Icon(Icons.add_rounded, color: Colors.black),
                  label: const Text('Thêm suất chiếu', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (ctx, i) => _ShowtimeCard(doc: docs[i], theater: theater),
        );
      },
    );
  }
}

class _ShowtimeCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final String theater;
  const _ShowtimeCard({required this.doc, required this.theater});

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final status = d['status'] ?? 'active';
    final isActive = status == 'active';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E1E2A),
            const Color(0xFF16161F),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? Colors.deepPurpleAccent.withValues(alpha: 0.3) : Colors.white12,
        ),
        boxShadow: [
          BoxShadow(
            color: isActive ? Colors.deepPurpleAccent.withValues(alpha: 0.05) : Colors.transparent,
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.deepPurpleAccent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.local_movies_rounded, color: Colors.deepPurpleAccent, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(d['movieTitle'] ?? '—',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (d['roomFormat'] != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: roomFormatColor(d['roomFormat']).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(d['roomFormat'],
                            style: TextStyle(color: roomFormatColor(d['roomFormat']), fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                Text('${d['date']} • ${d['time']}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
                Text('Phòng: ${d['roomName'] ?? '—'}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
                Row(
                  children: [
                    _priceChip('STD', d['priceStandard'], Colors.blue),
                    const SizedBox(width: 4),
                    _priceChip('VIP', d['priceVip'], Colors.amber),
                  ],
                ),
              ],
            ),
          ),
          Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isActive ? Colors.greenAccent.withValues(alpha: 0.15) : Colors.redAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isActive ? 'Hoạt động' : 'Đã hủy',
                  style: TextStyle(color: isActive ? Colors.greenAccent : Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 6),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white38, size: 18),
                color: const Color(0xFF1E1E2A),
                onSelected: (v) async {
                  if (v == 'edit') {
                    _ShowtimeDialog.show(context, theater: theater, existing: doc);
                  } else if (v == 'toggle') {
                    await FirebaseFirestore.instance.collection('showtimes').doc(doc.id).update({
                      'status': isActive ? 'cancelled' : 'active',
                    });
                  } else if (v == 'delete') {
                    await FirebaseFirestore.instance.collection('showtimes').doc(doc.id).delete();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: _menuItem(Icons.edit_rounded, 'Chỉnh sửa', Colors.amber)),
                  PopupMenuItem(
                    value: 'toggle',
                    child: _menuItem(
                      isActive ? Icons.cancel_rounded : Icons.check_circle_rounded,
                      isActive ? 'Hủy suất' : 'Kích hoạt lại',
                      isActive ? Colors.redAccent : Colors.green,
                    ),
                  ),
                  PopupMenuItem(value: 'delete', child: _menuItem(Icons.delete_rounded, 'Xóa', Colors.red)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _priceChip(String label, dynamic price, Color color) {
    final p = (price as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
      child: Text('$label: ${_fmt(p)}đ', style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  Widget _menuItem(IconData icon, String label, Color color) {
    return Row(children: [
      Icon(icon, color: color, size: 16),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(color: color, fontSize: 13)),
    ]);
  }

  static String _fmt(int v) =>
      v.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
}

// ── Showtime dialog (add/edit) ─────────────────────────────────────────────────
class _ShowtimeDialog {
  static Future<void> show(BuildContext context, {required String theater, QueryDocumentSnapshot? existing}) {
    final d = existing?.data() as Map<String, dynamic>?;
    return showDialog(
      context: context,
      builder: (ctx) => _ShowtimeDialogWidget(theater: theater, existing: d, existingId: existing?.id),
    );
  }
}

class _ShowtimeDialogWidget extends StatefulWidget {
  final String theater;
  final Map<String, dynamic>? existing;
  final String? existingId;
  const _ShowtimeDialogWidget({required this.theater, this.existing, this.existingId});

  @override
  State<_ShowtimeDialogWidget> createState() => _ShowtimeDialogWidgetState();
}

class _ShowtimeDialogWidgetState extends State<_ShowtimeDialogWidget> {
  final _movieCtrl = TextEditingController();
  final _roomCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _timeCtrl = TextEditingController();
  final _priceStdCtrl = TextEditingController();
  final _priceVipCtrl = TextEditingController();
  final _repeatDaysCtrl = TextEditingController(text: '1');
  String? _roomFormat;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    if (d != null) {
      _movieCtrl.text = d['movieTitle'] ?? '';
      _roomCtrl.text = d['roomName'] ?? '';
      _dateCtrl.text = d['date'] ?? '';
      _timeCtrl.text = d['time'] ?? '';
      _priceStdCtrl.text = '${d['priceStandard'] ?? 90000}';
      _priceVipCtrl.text = '${d['priceVip'] ?? 120000}';
      _roomFormat = d['roomFormat'] as String?;
    } else {
      _priceStdCtrl.text = '90000';
      _priceVipCtrl.text = '120000';
    }
  }

  @override
  void dispose() {
    _movieCtrl.dispose(); _roomCtrl.dispose(); _dateCtrl.dispose();
    _timeCtrl.dispose(); _priceStdCtrl.dispose(); _priceVipCtrl.dispose();
    _repeatDaysCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF16161F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.existingId != null ? 'CHỈNH SỬA SUẤT CHIẾU' : 'THÊM SUẤT CHIẾU',
        style: const TextStyle(color: Colors.deepPurpleAccent, fontWeight: FontWeight.bold, fontSize: 14),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(_movieCtrl, 'Tên phim', Icons.movie_rounded),
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('rooms')
                  .where('theaterName', isEqualTo: widget.theater)
                  .snapshots(),
              builder: (context, snap) {
                final rooms = snap.data?.docs ?? [];
                if (rooms.isEmpty) {
                  // Chưa có phòng nào được định nghĩa - dùng nhập tay như cũ.
                  return _field(_roomCtrl, 'Phòng chiếu (VD: Phòng 1)', Icons.weekend_rounded);
                }
                final roomDocs = {for (final r in rooms) (r.data() as Map)['roomName'] as String: r.data() as Map};
                final roomNames = roomDocs.keys.toList();
                final current = roomNames.contains(_roomCtrl.text) ? _roomCtrl.text : null;
                return DropdownButtonFormField<String>(
                  value: current,
                  dropdownColor: const Color(0xFF1E1E2A),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF1E1E2A),
                    prefixIcon: const Icon(Icons.weekend_rounded, color: Colors.deepPurpleAccent, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  ),
                  hint: const Text('Chọn phòng chiếu', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  items: roomNames
                      .map((r) => DropdownMenuItem(
                          value: r, child: Text('$r  (${roomDocs[r]?['roomFormat'] ?? '2D Phụ đề'})')))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _roomCtrl.text = v ?? '';
                    _roomFormat = v != null ? (roomDocs[v]?['roomFormat'] as String?) : null;
                  }),
                );
              },
            ),
            const SizedBox(height: 10),
            _field(_dateCtrl, 'Ngày (yyyy-MM-dd)', Icons.calendar_today_rounded,
                type: TextInputType.datetime),
            const SizedBox(height: 10),
            _field(_timeCtrl, 'Giờ (HH:mm)', Icons.access_time_rounded),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _field(_priceStdCtrl, 'Giá STD (đ)', Icons.chair_rounded, type: TextInputType.number)),
              const SizedBox(width: 8),
              Expanded(child: _field(_priceVipCtrl, 'Giá VIP (đ)', Icons.star_rounded, type: TextInputType.number)),
            ]),
            if (widget.existingId == null) ...[
              const SizedBox(height: 10),
              _field(_repeatDaysCtrl, 'Lặp lại liên tiếp (số ngày, VD: 7)', Icons.repeat_rounded, type: TextInputType.number),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tạo cùng 1 suất chiếu (cùng phim/phòng/giờ) lặp lại mỗi ngày bắt đầu từ ngày trên. Để 1 nếu chỉ tạo 1 suất duy nhất.',
                    style: TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('HỦY', style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
          child: Text(widget.existingId != null ? 'CẬP NHẬT' : 'THÊM',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

  // Ngày kế tiếp dạng "yyyy-MM-dd" (dùng cho lặp lại hàng loạt) - chỉ áp dụng
  // khi ngày gốc đúng định dạng ISO (suất chiếu do manager tạo luôn theo
  // định dạng này, khác với chuỗi tiếng Việt dự phòng của khách khi chưa có
  // suất thật).
  String? _addDays(String isoDate, int days) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(isoDate);
    if (m == null) return null;
    final d = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)).add(Duration(days: days));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    final roomName = _roomCtrl.text.trim();
    final date = _dateCtrl.text.trim();
    final time = _timeCtrl.text.trim();

    if (roomName.isEmpty || date.isEmpty || time.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng điền đủ thông tin Phòng, Ngày và Giờ chiếu!'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    final baseData = {
      'movieTitle': _movieCtrl.text.trim(),
      'theaterName': widget.theater,
      'roomName': roomName,
      'roomFormat': _roomFormat ?? '2D Phụ đề',
      'time': time,
      'priceStandard': int.tryParse(_priceStdCtrl.text) ?? 90000,
      'priceVip': int.tryParse(_priceVipCtrl.text) ?? 120000,
      'status': 'active',
    };

    if (widget.existingId != null) {
      // Sửa 1 suất đã có: giữ nguyên logic cũ, chặn hẳn nếu trùng.
      final conflictCheck = await FirebaseFirestore.instance
          .collection('showtimes')
          .where('theaterName', isEqualTo: widget.theater)
          .where('roomName', isEqualTo: roomName)
          .where('date', isEqualTo: date)
          .where('time', isEqualTo: time)
          .get();
      final hasConflict = conflictCheck.docs.any((doc) => doc.id != widget.existingId);
      if (hasConflict) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Phòng chiếu này đã có phim khác chiếu vào cùng giờ! Vui lòng chọn giờ hoặc phòng khác.'), backgroundColor: Colors.redAccent),
          );
        }
        return;
      }
      await FirebaseFirestore.instance.collection('showtimes').doc(widget.existingId).update({...baseData, 'date': date});
    } else {
      // Tạo mới - hỗ trợ lặp lại N ngày liên tiếp. Ngày nào bị trùng
      // phòng+giờ với suất đã có thì bỏ qua ngày đó (không chặn cả loạt),
      // báo lại cho manager biết đã tạo/bỏ qua bao nhiêu suất.
      final repeatDays = (int.tryParse(_repeatDaysCtrl.text) ?? 1).clamp(1, 60);
      final existingSnap = await FirebaseFirestore.instance
          .collection('showtimes')
          .where('theaterName', isEqualTo: widget.theater)
          .where('roomName', isEqualTo: roomName)
          .where('time', isEqualTo: time)
          .get();
      final existingDates = existingSnap.docs.map((d) => (d.data())['date'] as String?).whereType<String>().toSet();

      final batch = FirebaseFirestore.instance.batch();
      int created = 0, skipped = 0;
      for (int i = 0; i < repeatDays; i++) {
        final thisDate = i == 0 ? date : (_addDays(date, i) ?? date);
        if (existingDates.contains(thisDate)) {
          skipped++;
          continue;
        }
        existingDates.add(thisDate); // tránh tự trùng giữa các ngày mới tạo trong cùng lượt này
        final ref = FirebaseFirestore.instance.collection('showtimes').doc();
        batch.set(ref, {...baseData, 'date': thisDate, 'createdAt': Timestamp.now()});
        created++;
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(skipped > 0
                ? 'Đã tạo $created suất chiếu, bỏ qua $skipped ngày do trùng lịch.'
                : 'Đã tạo $created suất chiếu.'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    }
    if (mounted) Navigator.pop(context);
  }
}

// ── Theater revenue tab ────────────────────────────────────────────────────────
class _TheaterRevenueTab extends StatelessWidget {
  final String theater;
  const _TheaterRevenueTab({required this.theater});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tickets')
          .where('theaterName', isEqualTo: theater)
          .where('paymentStatus', whereIn: ['COMPLETED', 'CHECKED_IN'])
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final revenue = docs.fold<int>(0, (s, d) => s + ((d.data() as Map)['totalAmount'] as num? ?? 0).toInt());
        final checkedIn = docs.where((d) => (d.data() as Map)['paymentStatus'] == 'CHECKED_IN').length;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _card('Tổng vé đã bán', '${docs.length}', Icons.confirmation_number_rounded, Colors.amber),
              const SizedBox(height: 12),
              _card('Doanh thu', '${_fmt(revenue)} đ', Icons.monetization_on_rounded, Colors.green),
              const SizedBox(height: 12),
              _card('Đã check-in', '$checkedIn', Icons.how_to_reg_rounded, Colors.tealAccent),
              const SizedBox(height: 24),
              // Recent tickets
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161F),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('VÉ GẦN NHẤT', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ...docs.take(5).map((doc) {
                      final d = doc.data() as Map<String, dynamic>;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text(d['movieTitle'] ?? '—',
                                style: const TextStyle(color: Colors.white70, fontSize: 12), overflow: TextOverflow.ellipsis)),
                            Text('${_fmt((d['totalAmount'] as num? ?? 0).toInt())} đ',
                                style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _card(String label, String value, IconData icon, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
              Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(int v) =>
      v.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
}

// ── Staff list tab ─────────────────────────────────────────────────────────────
class _StaffListTab extends StatelessWidget {
  final String theater;
  const _StaffListTab({required this.theater});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _AssignStaffDialog.show(context, theater: theater),
        backgroundColor: Colors.deepPurpleAccent,
        icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
        label: const Text('Gán nhân viên', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('assignedTheater', isEqualTo: theater)
            .where('role', isEqualTo: 'staff')
            .snapshots(),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text('Chưa có nhân viên nào được gán cho rạp này.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white38)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final doc = docs[i];
              final d = doc.data() as Map<String, dynamic>;
              final name = d['displayName'] ?? '';
              final email = d['email'] ?? '';
              final displayLabel = (name.isNotEmpty ? name : email);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161F),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.tealAccent.withOpacity(0.1)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.teal.withOpacity(0.15),
                      child: Text(
                        displayLabel.isNotEmpty ? displayLabel.substring(0, 1).toUpperCase() : '?',
                        style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(displayLabel,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          if (name.isNotEmpty)
                            Text(email, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.person_remove_rounded, color: Colors.redAccent, size: 20),
                      tooltip: 'Xoá khỏi rạp',
                      onPressed: () => _confirmUnassign(context, doc.id, displayLabel),
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

  void _confirmUnassign(BuildContext context, String uid, String label) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('XOÁ NHÂN VIÊN KHỎI RẠP', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14)),
        content: Text('Gỡ "$label" khỏi rạp $theater? Tài khoản vẫn còn, chỉ không còn thuộc rạp này nữa.',
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
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
    if (confirm != true) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).update({'assignedTheater': null});
  }
}

// ── Gán nhân viên có sẵn (role 'staff') vào rạp đang quản lý ────────────────
class _AssignStaffDialog {
  static Future<void> show(BuildContext context, {required String theater}) {
    return showDialog(context: context, builder: (ctx) => _AssignStaffDialogWidget(theater: theater));
  }
}

class _AssignStaffDialogWidget extends StatelessWidget {
  final String theater;
  const _AssignStaffDialogWidget({required this.theater});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF16161F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('GÁN NHÂN VIÊN VÀO RẠP', style: TextStyle(color: Colors.deepPurpleAccent, fontWeight: FontWeight.bold, fontSize: 14)),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'staff').snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent));
            }
            // Chỉ hiện nhân viên CHƯA thuộc đúng rạp này (đã ở rạp này rồi
            // thì không cần gán lại; nhân viên rạp khác vẫn hiện để chuyển
            // sang rạp này nếu cần).
            final docs = (snap.data?.docs ?? [])
                .where((d) => (d.data() as Map)['assignedTheater'] != theater)
                .toList();
            if (docs.isEmpty) {
              return const Center(
                child: Text('Không có nhân viên nào khác để gán.', style: TextStyle(color: Colors.white38, fontSize: 12)),
              );
            }
            return ListView.builder(
              itemCount: docs.length,
              itemBuilder: (ctx, i) {
                final doc = docs[i];
                final d = doc.data() as Map<String, dynamic>;
                final name = d['displayName'] ?? '';
                final email = d['email'] ?? '';
                final currentTheater = d['assignedTheater'] as String?;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Colors.deepPurpleAccent.withValues(alpha: 0.15),
                    child: Text((name.isNotEmpty ? name : email).substring(0, 1).toUpperCase(),
                        style: const TextStyle(color: Colors.deepPurpleAccent, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(name.isNotEmpty ? name : email, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  subtitle: Text(
                    currentTheater == null || currentTheater.isEmpty ? 'Chưa gán rạp' : 'Đang ở: $currentTheater',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      await doc.reference.update({'assignedTheater': theater});
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('GÁN', style: TextStyle(color: Colors.deepPurpleAccent, fontWeight: FontWeight.bold)),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ĐÓNG', style: TextStyle(color: Colors.grey))),
      ],
    );
  }
}
