import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../main.dart';
import '../../../providers/user_provider.dart';
import '../../../models/showtime.dart';
import '../../../models/session_type.dart';
import 'theater_voucher_screen.dart';
import 'smart_roster_screen.dart';
import 'manager_incident_screen.dart';
import 'package:dat_ve_xem_phim_group5/features/theater_manager/screens/room_management_screen.dart' show RoomManagementScreen, roomFormatColor;

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
          IconButton(
            icon: const Icon(Icons.report_problem_rounded, color: Colors.orangeAccent),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ManagerIncidentScreen(theater: theater)),
            ),
            tooltip: 'Sự cố',
          ),
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
              icon: const Icon(Icons.add_rounded, color: Colors.white),
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
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent));
        }
        // Sort theo showAt thật (parse fallback cho tài liệu cũ) thay vì
        // orderBy('date') trên string - field 'date' từng lẫn lộn 2 định dạng
        // (ISO và nhãn tiếng Việt) nên sort theo string cho kết quả sai.
        final docs = (snap.data?.docs ?? []).toList()
          ..sort((a, b) {
            final sa = Showtime.fromMap(a.id, a.data() as Map<String, dynamic>).showAt;
            final sb = Showtime.fromMap(b.id, b.data() as Map<String, dynamic>).showAt;
            if (sa == null || sb == null) return 0;
            return sa.compareTo(sb);
          });
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
                Text('${d['date']} • ${d['time']} • ${d['language'] ?? 'Phụ đề'} • ${d['sessionType'] ?? 'Standard'}',
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
                const SizedBox(height: 8),
                // Heatmap (Tỷ lệ lấp đầy)
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('tickets')
                      .where('theaterName', isEqualTo: theater)
                      .where('showDate', isEqualTo: d['date'])
                      .where('showTime', isEqualTo: d['time'])
                      .where('movieTitle', isEqualTo: d['movieTitle']) // Thêm ràng buộc phim cho chắc
                      .snapshots(),
                  builder: (context, snapshot) {
                    int booked = 0;
                    if (snapshot.hasData) {
                      for (var t in snapshot.data!.docs) {
                        final tData = t.data() as Map<String, dynamic>;
                        if (tData['paymentStatus'] != 'CANCELLED') {
                          final seats = tData['seats'] as List<dynamic>? ?? [];
                          booked += seats.length;
                        }
                      }
                    }
                    // Giả sử capacity là 104
                    const int capacity = 104;
                    final pct = (booked / capacity).clamp(0.0, 1.0);
                    Color heatColor = Colors.greenAccent;
                    if (pct > 0.8) heatColor = Colors.redAccent;
                    else if (pct > 0.5) heatColor = Colors.orangeAccent;
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.people_alt_rounded, color: Colors.white54, size: 12),
                            const SizedBox(width: 4),
                            Text('Lấp đầy: $booked / $capacity (${(pct * 100).toStringAsFixed(1)}%)',
                                style: TextStyle(color: heatColor, fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: pct,
                            backgroundColor: Colors.white12,
                            color: heatColor,
                            minHeight: 4,
                          ),
                        ),
                      ],
                    );
                  },
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

// Thời lượng mặc định dùng khi không tra được phim trong collection 'movies'
// (vd. gõ sai tên, hoặc phim chưa được admin thêm vào hệ thống) - fallback an
// toàn, KHÔNG phải giá trị dùng cho mọi phim như trước (trước đây mọi suất
// chiếu đều giả định chiếm phòng đúng 150 phút bất kể phim ngắn/dài, khiến
// phim ngắn bị chặn nhầm suất kế tiếp còn phim dài có thể bị xếp chồng giờ
// thật mà không phát hiện ra).
const _kFallbackShowtimeDuration = Duration(minutes: 150);

// Cộng thêm 10 phút quảng cáo/dọn phòng sau khi phim kết thúc, khớp cách tính
// giờ ra về ở showtime_selection_screen.dart (durationMins + 10).
DateTime _showtimeWindowEnd(DateTime showAt, Duration movieDuration) =>
    showAt.add(movieDuration + const Duration(minutes: 10));

class _ShowtimeDialogWidgetState extends State<_ShowtimeDialogWidget> {
  final _movieCtrl = TextEditingController();
  final _roomCtrl = TextEditingController();
  final _priceStdCtrl = TextEditingController();
  final _priceVipCtrl = TextEditingController();
  final _repeatDaysCtrl = TextEditingController(text: '1');
  String? _roomFormat;
  // Ngôn ngữ suất chiếu - thuộc tính riêng của suất chiếu, không phải của
  // phòng (xem models/showtime.dart Showtime.language).
  String _language = 'Phụ đề';
  // null = "Tự động" (suy ra từ giờ chiếu + ngày công chiếu phim khi lưu) -
  // chỉ set khác null khi manager chủ động chọn 1 trong 3 loại đặc biệt
  // (Marathon/Fan Screening/Special Event, xem models/session_type.dart).
  String? _manualSessionType;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    if (d != null) {
      _movieCtrl.text = d['movieTitle'] ?? '';
      _roomCtrl.text = d['roomName'] ?? '';
      _priceStdCtrl.text = '${d['priceStandard'] ?? 90000}';
      _priceVipCtrl.text = '${d['priceVip'] ?? 120000}';
      _roomFormat = d['roomFormat'] as String?;
      _language = d['language'] as String? ?? 'Phụ đề';
      final existingSessionType = d['sessionType'] as String?;
      if (existingSessionType != null && kManualSessionTypes.contains(existingSessionType)) {
        _manualSessionType = existingSessionType;
      }
      final existingShowAt = Showtime.fromMap(widget.existingId ?? '', d).showAt;
      if (existingShowAt != null) {
        _selectedDate = DateTime(existingShowAt.year, existingShowAt.month, existingShowAt.day);
        _selectedTime = TimeOfDay(hour: existingShowAt.hour, minute: existingShowAt.minute);
      }
    } else {
      _priceStdCtrl.text = '90000';
      _priceVipCtrl.text = '120000';
    }
  }

  @override
  void dispose() {
    _movieCtrl.dispose(); _roomCtrl.dispose();
    _priceStdCtrl.dispose(); _priceVipCtrl.dispose();
    _repeatDaysCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: Colors.deepPurpleAccent)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: Colors.deepPurpleAccent)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedTime = picked);
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
                          value: r, child: Text('$r  (${roomDocs[r]?['roomFormat'] ?? 'Standard'})')))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _roomCtrl.text = v ?? '';
                    _roomFormat = v != null ? (roomDocs[v]?['roomFormat'] as String?) : null;
                  }),
                );
              },
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _pickerField(
                  label: _selectedDate == null ? 'Chọn ngày chiếu' : DateFormat('dd/MM/yyyy').format(_selectedDate!),
                  icon: Icons.calendar_today_rounded,
                  onTap: _pickDate,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _pickerField(
                  label: _selectedTime == null ? 'Chọn giờ chiếu' : _selectedTime!.format(context),
                  icon: Icons.access_time_rounded,
                  onTap: _pickTime,
                ),
              ),
            ]),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _language,
              dropdownColor: const Color(0xFF1E1E2A),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1E1E2A),
                prefixIcon: const Icon(Icons.subtitles_rounded, color: Colors.deepPurpleAccent, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: const [
                DropdownMenuItem(value: 'Phụ đề', child: Text('Phụ đề')),
                DropdownMenuItem(value: 'Lồng tiếng', child: Text('Lồng tiếng')),
              ],
              onChanged: (v) => setState(() => _language = v ?? 'Phụ đề'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              value: _manualSessionType,
              dropdownColor: const Color(0xFF1E1E2A),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1E1E2A),
                prefixIcon: const Icon(Icons.event_rounded, color: Colors.deepPurpleAccent, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Loại suất: Tự động (theo giờ chiếu)')),
                ...kManualSessionTypes.map((t) => DropdownMenuItem<String?>(value: t, child: Text(t))),
              ],
              onChanged: (v) => setState(() => _manualSessionType = v),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Để "Tự động" thì loại suất (Morning/Late Morning/Afternoon/Prime Time/Evening/Midnight/Sneak Show/First Day) sẽ tự tính theo giờ chiếu và ngày công chiếu phim khi lưu.',
                  style: TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ),
            ),
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

  Widget _pickerField({required String label, required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(color: const Color(0xFF1E1E2A), borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            Icon(icon, color: Colors.deepPurpleAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  bool _overlapsWindow(DateTime a, DateTime b, Duration movieDuration) {
    final aEnd = _showtimeWindowEnd(a, movieDuration);
    final bEnd = _showtimeWindowEnd(b, movieDuration);
    return a.isBefore(bEnd) && b.isBefore(aEnd);
  }

  Future<void> _save() async {
    final roomName = _roomCtrl.text.trim();

    if (roomName.isEmpty || _selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng điền đủ thông tin Phòng, Ngày và Giờ chiếu!'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    final baseData = {
      'movieTitle': _movieCtrl.text.trim(),
      'theaterName': widget.theater,
      'roomName': roomName,
      'roomFormat': _roomFormat ?? 'Standard',
      'language': _language,
      'priceStandard': int.tryParse(_priceStdCtrl.text) ?? 90000,
      'priceVip': int.tryParse(_priceVipCtrl.text) ?? 120000,
      'status': 'active',
    };

    final baseShowAt = DateTime(
      _selectedDate!.year, _selectedDate!.month, _selectedDate!.day,
      _selectedTime!.hour, _selectedTime!.minute,
    );

    // Tra phim theo tên (dùng chung 1 lượt đọc cho cả ngày công chiếu - để tự
    // động phát hiện Sneak Show/First Day, xem models/session_type.dart - và
    // thời lượng thật - để tính đúng khung giờ phòng bị chiếm khi chống trùng
    // giờ bên dưới, thay vì giả định cố định 150 phút cho mọi phim).
    DateTime? movieReleaseDate;
    Duration movieDuration = _kFallbackShowtimeDuration;
    final movieSnap = await FirebaseFirestore.instance
        .collection('movies')
        .where('title', isEqualTo: _movieCtrl.text.trim())
        .limit(1)
        .get();
    if (movieSnap.docs.isNotEmpty) {
      final movieData = movieSnap.docs.first.data();
      if (_manualSessionType == null) {
        movieReleaseDate = parseReleaseDate(movieData['releaseDate'] as String?);
      }
      final durationMatch = RegExp(r'\d+').firstMatch(movieData['duration'] as String? ?? '');
      if (durationMatch != null) {
        movieDuration = Duration(minutes: int.parse(durationMatch.group(0)!));
      }
    }
    String sessionTypeFor(DateTime showAt) =>
        _manualSessionType ?? detectSessionType(showAt, movieReleaseDate);

    // Suất chiếu khác cùng phòng, để check chồng giờ - chỉ dùng equality
    // filter (theaterName/roomName) nên không cần Firestore composite index
    // mới; so khớp thời gian thật (showAt) làm ở client.
    final roomShowtimesSnap = await FirebaseFirestore.instance
        .collection('showtimes')
        .where('theaterName', isEqualTo: widget.theater)
        .where('roomName', isEqualTo: roomName)
        .get();
    final otherShowAts = roomShowtimesSnap.docs
        .where((doc) => doc.id != widget.existingId)
        .map((doc) => Showtime.fromMap(doc.id, doc.data()).showAt)
        .whereType<DateTime>()
        .toList();

    if (widget.existingId != null) {
      if (otherShowAts.any((s) => _overlapsWindow(s, baseShowAt, movieDuration))) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Phòng chiếu này đã có phim khác chiếu chồng giờ! Vui lòng chọn giờ hoặc phòng khác.'), backgroundColor: Colors.redAccent),
          );
        }
        return;
      }
      await FirebaseFirestore.instance.collection('showtimes').doc(widget.existingId).update({
        ...baseData,
        'showAt': Timestamp.fromDate(baseShowAt),
        'date': Showtime.isoDate(baseShowAt),
        'time': Showtime.hhmm(baseShowAt),
        'sessionType': sessionTypeFor(baseShowAt),
      });
    } else {
      // Tạo mới - hỗ trợ lặp lại N ngày liên tiếp. Ngày nào chồng giờ với suất
      // đã có (hoặc với suất khác vừa tạo trong cùng lượt này) thì bỏ qua
      // ngày đó (không chặn cả loạt), báo lại cho manager biết đã tạo/bỏ qua
      // bao nhiêu suất.
      final repeatDays = (int.tryParse(_repeatDaysCtrl.text) ?? 1).clamp(1, 60);
      final batch = FirebaseFirestore.instance.batch();
      final newShowAts = <DateTime>[];
      int created = 0, skipped = 0;
      for (int i = 0; i < repeatDays; i++) {
        final thisShowAt = baseShowAt.add(Duration(days: i));
        final conflicts = [...otherShowAts, ...newShowAts].any((s) => _overlapsWindow(s, thisShowAt, movieDuration));
        if (conflicts) {
          skipped++;
          continue;
        }
        newShowAts.add(thisShowAt);
        final ref = FirebaseFirestore.instance.collection('showtimes').doc();
        batch.set(ref, {
          ...baseData,
          'showAt': Timestamp.fromDate(thisShowAt),
          'date': Showtime.isoDate(thisShowAt),
          'time': Showtime.hhmm(thisShowAt),
          'sessionType': sessionTypeFor(thisShowAt),
          'createdAt': Timestamp.now(),
        });
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'roster_btn',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => SmartRosterScreen(theater: theater)));
            },
            backgroundColor: Colors.blueAccent,
            icon: const Icon(Icons.calendar_month_rounded, color: Colors.white),
            label: const Text('Phân công ca', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'assign_btn',
            onPressed: () => _AssignStaffDialog.show(context, theater: theater),
            backgroundColor: Colors.deepPurpleAccent,
            icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
            label: const Text('Gán nhân viên', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
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
