import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../../core/constants.dart';
import '../../../main.dart';
import '../../../providers/user_provider.dart';
import '../../../models/showtime.dart';
import '../../../models/session_type.dart';
import '../../../models/room_layout.dart' show RoomCapability, RoomLayout, parseCapabilities;
import '../widgets/seat_grid_widget.dart';
import 'theater_voucher_screen.dart';
import 'smart_roster_screen.dart';
import 'theater_attendance_screen.dart';
import 'manager_incident_screen.dart';
import 'seat_heatmap_screen.dart';
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
              icon: const Icon(Icons.local_fire_department_rounded, color: Colors.deepOrangeAccent),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => SeatHeatmapScreen(theater: theater)),
              ),
              tooltip: 'Heatmap lấp đầy ghế',
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
                    if (pct > 0.8) {
                      heatColor = Colors.redAccent;
                    } else if (pct > 0.5) heatColor = Colors.orangeAccent;
                    
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
                  color: (isActive
                          ? Colors.greenAccent
                          : status == 'sales_closed'
                              ? Colors.orangeAccent
                              : Colors.redAccent)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isActive
                      ? 'Hoạt động'
                      : status == 'sales_closed'
                          ? 'Dừng bán'
                          : 'Đã hủy',
                  style: TextStyle(
                      color: isActive
                          ? Colors.greenAccent
                          : status == 'sales_closed'
                              ? Colors.orangeAccent
                              : Colors.redAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
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
                  } else if (v == 'sales') {
                    // "Dừng bán vé" khác "Hủy suất": suất vẫn chiếu bình
                    // thường (vé đã mua vẫn hợp lệ, vẫn check-in được), chỉ
                    // không nhận thêm đơn mới - backend /seats/hold từ chối
                    // giữ ghế khi status != 'active'.
                    await FirebaseFirestore.instance.collection('showtimes').doc(doc.id).update({
                      'status': status == 'sales_closed' ? 'active' : 'sales_closed',
                    });
                  } else if (v == 'blockSeats') {
                    _ShowtimeSeatBlockDialog.show(context, showtimeDoc: doc, theater: theater);
                  } else if (v == 'delete') {
                    await FirebaseFirestore.instance.collection('showtimes').doc(doc.id).delete();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: _menuItem(Icons.edit_rounded, 'Chỉnh sửa', Colors.amber)),
                  PopupMenuItem(
                    value: 'sales',
                    child: _menuItem(
                      status == 'sales_closed' ? Icons.play_circle_rounded : Icons.pause_circle_rounded,
                      status == 'sales_closed' ? 'Mở bán lại' : 'Dừng bán vé',
                      status == 'sales_closed' ? Colors.greenAccent : Colors.orangeAccent,
                    ),
                  ),
                  PopupMenuItem(value: 'blockSeats', child: _menuItem(Icons.event_busy_rounded, 'Khoá ghế suất này', Colors.tealAccent)),
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
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
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
  final _priceStdCtrl = TextEditingController();
  final _priceVipCtrl = TextEditingController();
  final _repeatDaysCtrl = TextEditingController(text: '1');
  String? _roomFormat;
  // Tổ hợp trình chiếu/âm thanh của phòng đang chọn (RoomCapability, xem
  // models/room_layout.dart) - chỉ hiện dropdown chọn khi phòng hỗ trợ nhiều
  // hơn 1 tổ hợp (VD phòng IMAX vừa có IMAX 2D vừa IMAX 3D).
  List<RoomCapability> _availableCapabilities = [];
  RoomCapability? _selectedCapability;
  // Chốt cứng sơ đồ ghế hiện tại của phòng (rooms/{id}.currentSeatMapVersionId)
  // vào suất chiếu - xem models/showtime.dart Showtime.seatMapVersionId. Khi
  // sửa suất chiếu cũ mà KHÔNG đổi phòng, giữ nguyên giá trị cũ (không tự
  // nhảy sang version mới hơn dù phòng đã được sửa sau đó); chỉ tính lại khi
  // tạo mới hoặc khi người dùng đổi sang phòng khác (xem onChanged của
  // dropdown phòng bên dưới).
  String? _seatMapVersionId;
  // Ngôn ngữ suất chiếu - thuộc tính riêng của suất chiếu, không phải của
  // phòng (xem models/showtime.dart Showtime.language).
  String _language = 'Phụ đề';
  // null = "Tự động" (suy ra từ giờ chiếu + ngày công chiếu phim khi lưu) -
  // chỉ set khác null khi manager chủ động chọn 1 trong 3 loại đặc biệt
  // (Marathon/Fan Screening/Special Event, xem models/session_type.dart).
  String? _manualSessionType;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  List<Showtime> _dayShowtimes = [];
  bool _loadingShowtimes = false;
  final Map<String, int> _movieDurations = {};
  int _newMovieDuration = 120;
  String? _conflictReason;

  double _getMinutesFrom8AM(DateTime dt) {
    int hour = dt.hour;
    if (hour < 6) {
      hour += 24;
    }
    final totalMinutes = hour * 60 + dt.minute;
    return (totalMinutes - 480).toDouble();
  }

  Future<void> _loadDayShowtimes() async {
    final room = _roomCtrl.text.trim();
    if (room.isEmpty || _selectedDate == null) {
      if (mounted) setState(() => _dayShowtimes = []);
      return;
    }
    if (mounted) setState(() => _loadingShowtimes = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final snap = await FirebaseFirestore.instance
          .collection('showtimes')
          .where('theaterName', isEqualTo: widget.theater)
          .where('roomName', isEqualTo: room)
          .where('date', isEqualTo: dateStr)
          .get();
      final list = snap.docs
          .map((doc) => Showtime.fromMap(doc.id, doc.data()))
          .where((s) => s.id != widget.existingId)
          .toList();
      _dayShowtimes = list;
      await _loadAllMovieDurations(list);
    } catch (e) {
      debugPrint('Lỗi tải showtimes: $e');
    } finally {
      if (mounted) setState(() => _loadingShowtimes = false);
    }
  }

  Future<void> _loadAllMovieDurations(List<Showtime> showtimes) async {
    final titles = showtimes.map((s) => s.movieTitle).toSet();
    final currentMovie = _movieCtrl.text.trim();
    if (currentMovie.isNotEmpty) {
      titles.add(currentMovie);
    }
    for (final title in titles) {
      if (_movieDurations.containsKey(title)) continue;
      try {
        final snap = await FirebaseFirestore.instance
            .collection('movies')
            .where('title', isEqualTo: title)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final durationStr = snap.docs.first.data()['duration'] as String? ?? '';
          final numMatch = RegExp(r'\d+').firstMatch(durationStr);
          if (numMatch != null) {
            _movieDurations[title] = int.parse(numMatch.group(0)!);
          } else {
            _movieDurations[title] = 120;
          }
        } else {
          _movieDurations[title] = 120;
        }
      } catch (_) {
        _movieDurations[title] = 120;
      }
    }
  }

  Future<void> _loadMovieDuration() async {
    final title = _movieCtrl.text.trim();
    if (title.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('movies')
          .where('title', isEqualTo: title)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final durationStr = snap.docs.first.data()['duration'] as String? ?? '';
        final numMatch = RegExp(r'\d+').firstMatch(durationStr);
        if (numMatch != null) {
          _newMovieDuration = int.parse(numMatch.group(0)!);
        }
      }
    } catch (_) {}
  }

  void _verifyConflicts() {
    _conflictReason = null;
    if (_selectedDate == null || _selectedTime == null || _roomCtrl.text.isEmpty || _movieCtrl.text.trim().isEmpty) {
      if (mounted) setState(() {});
      return;
    }
    final candidateStart = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, _selectedTime!.hour, _selectedTime!.minute);
    final candidateStartMin = _getMinutesFrom8AM(candidateStart);
    final candidateEndMin = candidateStartMin + _newMovieDuration + 10; // content duration + 10 mins buffer
    
    for (final s in _dayShowtimes) {
      if (s.showAt == null) continue;
      final duration = _movieDurations[s.movieTitle] ?? 120;
      final startMin = _getMinutesFrom8AM(s.showAt!);
      final endMin = _getMinutesFrom8AM(s.roomReleaseAt(duration)!);
      if (candidateStartMin < endMin && candidateEndMin > startMin) {
        _conflictReason = 'Trùng lịch với phim [${s.movieTitle}] tại khung giờ ${Showtime.hhmm(s.showAt!)} - ${Showtime.hhmm(s.roomReleaseAt(duration)!)}!';
        break;
      }
    }
    if (mounted) setState(() {});
  }

  Widget _buildTimelineWidget() {
    if (_loadingShowtimes) {
      return const SizedBox(
        height: 40,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.deepPurpleAccent)),
      );
    }
    const totalMinutes = 1080.0; // 18 hours * 60 mins
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 28,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final List<Widget> children = [];
              
              for (final s in _dayShowtimes) {
                if (s.showAt == null) continue;
                final duration = _movieDurations[s.movieTitle] ?? 120;
                final startMin = _getMinutesFrom8AM(s.showAt!);
                final releaseMin = _getMinutesFrom8AM(s.roomReleaseAt(duration)!);
                final double start = startMin.clamp(0.0, totalMinutes);
                final double end = releaseMin.clamp(0.0, totalMinutes);
                if (end <= start) continue;
                final left = (start / totalMinutes) * width;
                final blockWidth = ((end - start) / totalMinutes) * width;
                children.add(
                  Positioned(
                    left: left,
                    width: blockWidth,
                    height: 26,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          s.movieTitle,
                          style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                );
              }
              
              if (_selectedDate != null && _selectedTime != null && _movieCtrl.text.trim().isNotEmpty) {
                final candidateStart = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, _selectedTime!.hour, _selectedTime!.minute);
                final startMin = _getMinutesFrom8AM(candidateStart);
                final releaseMin = startMin + _newMovieDuration + 10;
                final double start = startMin.clamp(0.0, totalMinutes);
                final double end = releaseMin.clamp(0.0, totalMinutes);
                if (end > start) {
                  final left = (start / totalMinutes) * width;
                  final blockWidth = ((end - start) / totalMinutes) * width;
                  final hasOverlap = _conflictReason != null;
                  children.add(
                    Positioned(
                      left: left,
                      width: blockWidth,
                      height: 26,
                      child: Container(
                        decoration: BoxDecoration(
                          color: hasOverlap 
                              ? Colors.amber.withValues(alpha: 0.8)
                              : Colors.greenAccent.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white70, width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            _movieCtrl.text.trim(),
                            style: const TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  );
                }
              }
              return Stack(children: children);
            },
          ),
        ),
        const SizedBox(height: 4),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('08:00', style: TextStyle(color: Colors.white24, fontSize: 8)),
            Text('12:00', style: TextStyle(color: Colors.white24, fontSize: 8)),
            Text('16:00', style: TextStyle(color: Colors.white24, fontSize: 8)),
            Text('20:00', style: TextStyle(color: Colors.white24, fontSize: 8)),
            Text('00:00', style: TextStyle(color: Colors.white24, fontSize: 8)),
            Text('02:00', style: TextStyle(color: Colors.white24, fontSize: 8)),
          ],
        ),
      ],
    );
  }

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
      final existingProjection = d['projectionFormat'] as String?;
      final existingSound = d['soundFormat'] as String?;
      if (existingProjection != null && existingSound != null) {
        _selectedCapability = RoomCapability(projectionFormat: existingProjection, soundFormat: existingSound);
      }
      _seatMapVersionId = d['seatMapVersionId'] as String?;
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

    _movieCtrl.addListener(() {
      _loadMovieDuration().then((_) => _verifyConflicts());
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMovieDuration()
          .then((_) => _loadDayShowtimes())
          .then((_) => _verifyConflicts());
    });
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
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadDayShowtimes().then((_) => _verifyConflicts());
    }
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
    if (picked != null) {
      setState(() => _selectedTime = picked);
      _verifyConflicts();
    }
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
                // Phòng MAINTENANCE/INACTIVE (Giai đoạn E) không nhận suất
                // chiếu MỚI - suất đã tạo trước đó không ảnh hưởng. Khi sửa
                // suất chiếu cũ đang nằm trong phòng bảo trì, phòng đó vẫn
                // được giữ trong dropdown (nhánh `current` bên dưới) để không
                // ép đổi phòng chỉ vì mở dialog lên xem.
                final rooms = (snap.data?.docs ?? [])
                    .where((r) =>
                        ((r.data() as Map)['status'] as String? ?? 'ACTIVE') == 'ACTIVE' ||
                        (r.data() as Map)['roomName'] == _roomCtrl.text)
                    .toList();
                if (rooms.isEmpty) {
                  // Chưa có phòng nào được định nghĩa - dùng nhập tay như cũ.
                  return _field(_roomCtrl, 'Phòng chiếu (VD: Phòng 1)', Icons.weekend_rounded);
                }
                final roomDocs = {for (final r in rooms) (r.data() as Map)['roomName'] as String: r.data() as Map};
                final roomNames = roomDocs.keys.toList();
                final current = roomNames.contains(_roomCtrl.text) ? _roomCtrl.text : null;
                _availableCapabilities = current != null
                    ? parseCapabilities(roomDocs[current]?['capabilities'], roomDocs[current]?['roomFormat'] as String? ?? 'Standard')
                    : const [];
                if (current != null && _seatMapVersionId == null) {
                  _seatMapVersionId = roomDocs[current]?['currentSeatMapVersionId'] as String?;
                }
                if (_selectedCapability == null || !_availableCapabilities.contains(_selectedCapability)) {
                  _selectedCapability = _availableCapabilities.isEmpty
                      ? null
                      : _availableCapabilities.firstWhere((c) => c.isDefault, orElse: () => _availableCapabilities.first);
                }
                return Column(
                  children: [
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: current,
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
                      onChanged: (v) {
                        setState(() {
                          _roomCtrl.text = v ?? '';
                          _roomFormat = v != null ? (roomDocs[v]?['roomFormat'] as String?) : null;
                          _selectedCapability = null; // để khối trên tự chọn lại mặc định cho phòng mới
                          _seatMapVersionId = v != null ? (roomDocs[v]?['currentSeatMapVersionId'] as String?) : null;
                        });
                        _loadDayShowtimes().then((_) => _verifyConflicts());
                      },
                    ),
                    // Chỉ hiện khi phòng hỗ trợ >1 tổ hợp trình chiếu/âm thanh
                    // (VD phòng IMAX vừa chiếu được IMAX 2D vừa IMAX 3D) - nếu
                    // chỉ có 1 tổ hợp thì tự dùng luôn, không cần hỏi thêm.
                    if (_availableCapabilities.length > 1) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<RoomCapability>(
                        isExpanded: true,
                        initialValue: _selectedCapability,
                        dropdownColor: const Color(0xFF1E1E2A),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF1E1E2A),
                          prefixIcon: const Icon(Icons.theaters_rounded, color: Colors.deepPurpleAccent, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                        ),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        items: _availableCapabilities
                            .map((c) => DropdownMenuItem(value: c, child: Text(c.label, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedCapability = v),
                      ),
                    ],
                  ],
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
              isExpanded: true,
              initialValue: _language,
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
              isExpanded: true,
              initialValue: _manualSessionType,
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
            const Divider(color: Colors.white12, height: 24),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'SƠ ĐỒ LỊCH CHIẾU TRONG NGÀY (08:00 - 02:00)',
                style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ),
            const SizedBox(height: 10),
            _buildTimelineWidget(),
            if (_conflictReason != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _conflictReason!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('HỦY', style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          onPressed: _conflictReason != null ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurpleAccent,
            disabledBackgroundColor: Colors.white10,
          ),
          child: Text(widget.existingId != null ? 'CẬP NHẬT' : 'THÊM',
              style: TextStyle(color: _conflictReason != null ? Colors.white24 : Colors.white, fontWeight: FontWeight.bold)),
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

  // Tạo/sửa suất chiếu qua backend (POST /showtimes/save) thay vì ghi thẳng
  // Firestore từ client - trước đây việc kiểm tra chồng giờ phòng (đọc suất
  // chiếu khác + so khớp) hoàn toàn nằm ở client: 2 quản lý bấm lưu gần như
  // đồng thời (hoặc 1 client bị sửa đổi bỏ qua bước kiểm tra) có thể ghi 2
  // suất chồng giờ cùng 1 phòng mà không gì chặn được, vì firestore.rules chỉ
  // kiểm tra được role chứ không kiểm tra được logic nhiều-tài-liệu này. Giờ
  // server (Admin SDK) là nơi DUY NHẤT quyết định có chồng giờ hay không và
  // là nơi ghi document suất chiếu + sinh ghế - xem backend-payos/server.js.
  Future<void> _save() async {
    final roomName = _roomCtrl.text.trim();

    if (roomName.isEmpty || _selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng điền đủ thông tin Phòng, Ngày và Giờ chiếu!'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    final baseShowAt = DateTime(
      _selectedDate!.year, _selectedDate!.month, _selectedDate!.day,
      _selectedTime!.hour, _selectedTime!.minute,
    );

    Map<String, dynamic> resData;
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http.post(
        Uri.parse('${AppConfig.paymentBackendUrl}/showtimes/save'),
        headers: {
          'Content-Type': 'application/json',
          if (idToken != null) 'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'existingId': widget.existingId,
          'theaterName': widget.theater,
          'roomName': roomName,
          'movieTitle': _movieCtrl.text.trim(),
          'roomFormat': _roomFormat ?? 'Standard',
          if (_selectedCapability != null) 'projectionFormat': _selectedCapability!.projectionFormat,
          if (_selectedCapability != null) 'soundFormat': _selectedCapability!.soundFormat,
          if (_seatMapVersionId != null) 'seatMapVersionId': _seatMapVersionId,
          'language': _language,
          'priceStandard': int.tryParse(_priceStdCtrl.text) ?? 90000,
          'priceVip': int.tryParse(_priceVipCtrl.text) ?? 120000,
          'manualSessionType': _manualSessionType,
          'showAtMillis': baseShowAt.millisecondsSinceEpoch,
          'repeatDays': int.tryParse(_repeatDaysCtrl.text) ?? 1,
        }),
      ).timeout(const Duration(seconds: 30));
      resData = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      resData = {'success': false, 'message': 'Không kết nối được máy chủ: $e'};
    }

    if (resData['success'] != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resData['message'] ?? 'Không lưu được suất chiếu'), backgroundColor: Colors.redAccent),
        );
      }
      return;
    }

    if (mounted) {
      if (widget.existingId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã cập nhật suất chiếu.'), backgroundColor: Colors.teal),
        );
      } else {
        final created = resData['created'] ?? 0;
        final skipped = resData['skipped'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(skipped > 0
                ? 'Đã tạo $created suất chiếu, bỏ qua $skipped ngày do trùng lịch.'
                : 'Đã tạo $created suất chiếu.'),
            backgroundColor: Colors.teal,
          ),
        );
      }
      Navigator.pop(context);
    }
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
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
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
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
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
            heroTag: 'attendance_btn',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => TheaterAttendanceScreen(theater: theater)));
            },
            backgroundColor: Colors.amber,
            icon: const Icon(Icons.co_present_rounded, color: Colors.black),
            label: const Text('Điểm danh ca', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
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
                  border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.1)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.teal.withValues(alpha: 0.15),
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

// ── Khoá ghế theo TỪNG SUẤT CHIẾU (Giai đoạn E) ────────────────────────────────
// Khác "Bảo trì ghế" cấp phòng (room_management_screen.dart - áp dụng cho MỌI
// suất trong phòng đó): ở đây chỉ khoá ghế cho đúng 1 suất chiếu cụ thể (VD
// giữ 1 dãy cho khách đoàn, sự kiện riêng) bằng cách set
// showtimes/{id}/seats/{seatId}.status = BLOCKED. Chỉ đổi được ghế đang
// AVAILABLE <-> BLOCKED - ghế đang HOLDING/BOOKED (khách thật) hoặc
// UNAVAILABLE (hỏng cấp phòng) không đụng tới.
class _ShowtimeSeatBlockDialog extends StatefulWidget {
  final QueryDocumentSnapshot showtimeDoc;
  final String theater;
  const _ShowtimeSeatBlockDialog({required this.showtimeDoc, required this.theater});

  static Future<void> show(BuildContext context, {required QueryDocumentSnapshot showtimeDoc, required String theater}) {
    return showDialog(
      context: context,
      builder: (_) => _ShowtimeSeatBlockDialog(showtimeDoc: showtimeDoc, theater: theater),
    );
  }

  @override
  State<_ShowtimeSeatBlockDialog> createState() => _ShowtimeSeatBlockDialogState();
}

class _ShowtimeSeatBlockDialogState extends State<_ShowtimeSeatBlockDialog> {
  RoomLayout? _layout;
  bool _hasSeats = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = widget.showtimeDoc.data() as Map<String, dynamic>;
    final firestore = FirebaseFirestore.instance;

    final seatCheck = await firestore
        .collection('showtimes').doc(widget.showtimeDoc.id).collection('seats').limit(1).get();
    if (seatCheck.docs.isEmpty && mounted) {
      setState(() => _hasSeats = false);
      return;
    }

    RoomLayout? layout;
    final versionId = d['seatMapVersionId'] as String?;
    if (versionId != null) {
      final versionDoc = await firestore.collection('seat_map_versions').doc(versionId).get();
      if (versionDoc.exists) layout = RoomLayout.fromMap(versionDoc.id, versionDoc.data()!);
    }
    if (layout == null && d['roomName'] != null) {
      final snap = await firestore
          .collection('rooms')
          .where('theaterName', isEqualTo: widget.theater)
          .where('roomName', isEqualTo: d['roomName'])
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) layout = RoomLayout.fromMap(snap.docs.first.id, snap.docs.first.data());
    }
    if (mounted) setState(() => _layout = layout);
  }

  Future<void> _toggleSeat(String seatId, Map<String, String> statusBySeat) async {
    final current = statusBySeat[seatId];
    if (current == 'HOLDING' || current == 'BOOKED') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ghế đang có khách giữ/đã bán - không thể khoá.'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }
    if (current == 'UNAVAILABLE') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ghế hỏng cấp phòng - gỡ ở màn Bảo trì ghế của phòng.'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }
    final newStatus = current == 'BLOCKED' ? 'AVAILABLE' : 'BLOCKED';
    await FirebaseFirestore.instance
        .collection('showtimes').doc(widget.showtimeDoc.id).collection('seats').doc(seatId)
        .update({'status': newStatus});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E2A),
      title: const Text('Khoá ghế suất này', style: TextStyle(color: Colors.tealAccent, fontSize: 15, fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: double.maxFinite,
        child: !_hasSeats
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Suất chiếu này chưa có dữ liệu ghế riêng (tạo trước khi có tính năng này).\n\n'
                  'Mở "Chỉnh sửa" suất chiếu rồi bấm CẬP NHẬT để sinh dữ liệu ghế, sau đó quay lại đây.',
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                ),
              )
            : _layout == null
                ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator(color: Colors.tealAccent)))
                : StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('showtimes').doc(widget.showtimeDoc.id).collection('seats')
                        .snapshots(),
                    builder: (context, snap) {
                      final statusBySeat = <String, String>{};
                      for (final doc in snap.data?.docs ?? []) {
                        statusBySeat[doc.id] = (doc.data() as Map<String, dynamic>)['status'] as String? ?? 'AVAILABLE';
                      }
                      final blocked = statusBySeat.entries
                          .where((e) => e.value == 'BLOCKED' || e.value == 'UNAVAILABLE' || e.value == 'BOOKED' || e.value == 'HOLDING')
                          .map((e) => e.key)
                          .toSet();
                      return SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Chạm ghế để khoá/mở riêng cho suất này.\nGhế đã bán/đang giữ/hỏng cấp phòng không đổi được.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.4),
                            ),
                            const SizedBox(height: 16),
                            SeatGridView(
                              layout: _layout!,
                              mode: SeatGridMode.maintenance,
                              brokenSeats: blocked,
                              onToggleBroken: (seatId) => _toggleSeat(seatId, statusBySeat),
                              dense: true,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('XONG', style: TextStyle(color: Colors.tealAccent))),
      ],
    );
  }
}
