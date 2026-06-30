import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../providers/user_provider.dart';

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
    _tab = TabController(length: 3, vsync: this);
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
      backgroundColor: const Color(0xFF0F0F13),
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_tab.index == 0)
            IconButton(
              icon: const Icon(Icons.add_rounded, color: Colors.deepPurpleAccent),
              onPressed: () => _showAddShowtimeDialog(context, theater),
              tooltip: 'Thêm suất chiếu',
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
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _ShowtimesTab(theater: theater),
          _TheaterRevenueTab(theater: theater),
          _StaffListTab(theater: theater),
        ],
      ),
    );
  }

  void _showAddShowtimeDialog(BuildContext context, String theater) {
    _ShowtimeDialog.show(context, theater: theater);
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
    final status = d['payment_status'] ?? 'active';
    final isActive = status == 'active';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF16161F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? Colors.deepPurpleAccent.withOpacity(0.2) : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.local_movies_rounded, color: Colors.deepPurpleAccent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d['movieTitle'] ?? '—',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isActive ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isActive ? 'Hoạt động' : 'Đã hủy',
                  style: TextStyle(color: isActive ? Colors.greenAccent : Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold),
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
    } else {
      _priceStdCtrl.text = '90000';
      _priceVipCtrl.text = '120000';
    }
  }

  @override
  void dispose() {
    _movieCtrl.dispose(); _roomCtrl.dispose(); _dateCtrl.dispose();
    _timeCtrl.dispose(); _priceStdCtrl.dispose(); _priceVipCtrl.dispose();
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
            _field(_roomCtrl, 'Phòng chiếu (VD: Phòng 1)', Icons.weekend_rounded),
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

  Future<void> _save() async {
    final data = {
      'movieTitle': _movieCtrl.text.trim(),
      'theaterName': widget.theater,
      'roomName': _roomCtrl.text.trim(),
      'date': _dateCtrl.text.trim(),
      'time': _timeCtrl.text.trim(),
      'priceStandard': int.tryParse(_priceStdCtrl.text) ?? 90000,
      'priceVip': int.tryParse(_priceVipCtrl.text) ?? 120000,
      'status': 'active',
    };

    if (widget.existingId != null) {
      await FirebaseFirestore.instance.collection('showtimes').doc(widget.existingId).update(data);
    } else {
      data['createdAt'] = Timestamp.now();
      await FirebaseFirestore.instance.collection('showtimes').add(data);
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
          .where('theater', isEqualTo: theater)
          .where('payment_status', isEqualTo: 'COMPLETED')
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final revenue = docs.fold<int>(0, (s, d) => s + ((d.data() as Map)['totalPrice'] as num? ?? 0).toInt());
        final checkedIn = docs.where((d) => (d.data() as Map)['status'] == 'CHECKED_IN').length;

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
                            Expanded(child: Text(d['title'] ?? '—',
                                style: const TextStyle(color: Colors.white70, fontSize: 12), overflow: TextOverflow.ellipsis)),
                            Text('${_fmt((d['totalPrice'] as num? ?? 0).toInt())} đ',
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
    return StreamBuilder<QuerySnapshot>(
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
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final name = d['displayName'] ?? '';
            final email = d['email'] ?? '';
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
                      (name.isNotEmpty ? name : email).substring(0, 1).toUpperCase(),
                      style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.isNotEmpty ? name : email,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      if (name.isNotEmpty)
                        Text(email, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('NHÂN VIÊN', style: TextStyle(color: Colors.tealAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
