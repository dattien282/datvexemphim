import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../providers/user_provider.dart';
import '../../../core/constants.dart';
import '../../../main.dart';
import 'staff_walkin_sale_screen.dart';
import 'staff_seat_maintenance_screen.dart';

class StaffDashboardScreen extends StatefulWidget {
  final UserProfile staffProfile;
  const StaffDashboardScreen({super.key, required this.staffProfile});

  @override
  State<StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends State<StaffDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  String _dateFilter = _today();

  static String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: Column(
          children: [
            const Text('NHÂN VIÊN SOÁT VÉ',
                style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 14)),
            if (widget.staffProfile.assignedTheater != null)
              Text(widget.staffProfile.assignedTheater!,
                  style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.point_of_sale_rounded, color: Colors.tealAccent),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => StaffWalkInSaleScreen(theater: widget.staffProfile.assignedTheater)),
            ),
            tooltip: 'Bán vé tại quầy',
          ),
          IconButton(
            icon: const Icon(Icons.build_rounded, color: Colors.orangeAccent),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => StaffSeatMaintenanceScreen(theater: widget.staffProfile.assignedTheater)),
            ),
            tooltip: 'Ghế hỏng / bảo trì',
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.tealAccent),
            onPressed: _openQrScanner,
            tooltip: 'Quét mã QR',
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            onPressed: _handleLogout,
            tooltip: 'Đăng xuất',
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.tealAccent,
          labelColor: Colors.tealAccent,
          unselectedLabelColor: Colors.white38,
          tabs: const [
            Tab(text: 'VÉ HÔM NAY'),
            Tab(text: 'THỐNG KÊ CA'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _TicketListTab(
            theater: widget.staffProfile.assignedTheater,
            dateFilter: _dateFilter,
          ),
          _ShiftStatsTab(
            theater: widget.staffProfile.assignedTheater,
            staffEmail: widget.staffProfile.email,
            dateFilter: _dateFilter,
          ),
        ],
      ),
    );
  }

  void _openQrScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _QrScanScreen(theater: widget.staffProfile.assignedTheater)),
    );
  }

  void _handleLogout() async {
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

// ── Ticket list tab ────────────────────────────────────────────────────────────
class _TicketListTab extends StatefulWidget {
  final String? theater;
  final String dateFilter;
  const _TicketListTab({this.theater, required this.dateFilter});

  @override
  State<_TicketListTab> createState() => _TicketListTabState();
}

class _TicketListTabState extends State<_TicketListTab> {
  String _statusFilter = 'COMPLETED';

  @override
  Widget build(BuildContext context) {
    // "VÉ HÔM NAY" phải lọc theo showDate (suất chiếu hôm nay staff cần soát)
    // - trước đây widget.dateFilter được truyền xuống nhưng không hề dùng
    // trong query, nên tab này thực chất hiện 50 vé gần nhất mọi lúc, không
    // riêng hôm nay.
    Query query = FirebaseFirestore.instance
        .collection('tickets')
        .where('paymentStatus', isEqualTo: _statusFilter)
        .where('showDate', isEqualTo: widget.dateFilter);

    if (widget.theater != null) {
      query = query.where('theaterName', isEqualTo: widget.theater);
    }

    return Column(
      children: [
        // Status filter chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              _chip('Đã thanh toán', 'COMPLETED', Colors.green),
              const SizedBox(width: 8),
              _chip('Đã check-in', 'CHECKED_IN', Colors.tealAccent),
            ],
          ),
        ),

        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: query.orderBy('createdAt', descending: true).limit(50).snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Colors.tealAccent));
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.confirmation_number_outlined, color: Colors.white24, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        _statusFilter == 'COMPLETED' ? 'Chưa có vé cần soát' : 'Chưa có vé đã check-in',
                        style: const TextStyle(color: Colors.white38),
                      ),
                    ],
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (ctx, i) => _TicketCard(doc: docs[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, String value, Color color) {
    final active = _statusFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _statusFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? color : Colors.white24),
        ),
        child: Text(label,
            style: TextStyle(color: active ? color : Colors.white38, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ── Ticket card ────────────────────────────────────────────────────────────────
class _TicketCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  const _TicketCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final status = d['paymentStatus'] ?? '';
    final isCheckedIn = status == 'CHECKED_IN';
    final seats = (d['seats'] as List?)?.join(', ') ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A1A24),
            const Color(0xFF12121A),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCheckedIn ? Colors.tealAccent.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: isCheckedIn ? Colors.tealAccent.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.2),
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
              color: isCheckedIn ? Colors.teal.withValues(alpha: 0.15) : Colors.amber.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCheckedIn ? Icons.check_circle_rounded : Icons.confirmation_number_rounded,
              color: isCheckedIn ? Colors.tealAccent : Colors.amber,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d['movieTitle'] ?? '—',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                Text(d['email'] ?? '—', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                if (seats.isNotEmpty)
                  Text('Ghế: $seats', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                if (d['showtime'] != null)
                  Text('Suất: ${d['showtime']}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          if (!isCheckedIn)
            ElevatedButton(
              onPressed: () => _checkIn(context, doc.id),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('CHECK-IN THỦ CÔNG', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('ĐÃ VÀO', style: TextStyle(color: Colors.tealAccent, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  // Check-in thủ công (không quét QR) - dùng khi khách không mở được QR /
  // máy quét lỗi. Đi qua backend /manual-checkin (Admin SDK) thay vì ghi
  // thẳng Firestore từ client, để mọi lượt check-in - kể cả thủ công - đều
  // để lại dấu vết trong checkin_audit_log (reason: manual_override), tránh
  // lỗ hổng "staff tự ghi log giả" không có ai kiểm tra lại được.
  Future<void> _checkIn(BuildContext context, String ticketId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('XÁC NHẬN CHECK-IN THỦ CÔNG', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 14)),
        content: const Text('Chỉ dùng khi không quét được QR của khách. Xác nhận cho khách vào rạp?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('HỦY', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            child: const Text('XÁC NHẬN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http.post(
        Uri.parse('${AppConfig.paymentBackendUrl}/manual-checkin'),
        headers: {
          'Content-Type': 'application/json',
          if (idToken != null) 'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'ticketId': ticketId}),
      ).timeout(const Duration(seconds: 10));

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final ok = body['success'] == true;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? 'Check-in thành công!' : (body['message'] ?? 'Check-in thất bại')),
            backgroundColor: ok ? Colors.teal : Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi kết nối máy chủ soát vé: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }
}

// ── Shift stats tab ────────────────────────────────────────────────────────────
class _ShiftStatsTab extends StatelessWidget {
  final String? theater;
  final String staffEmail;
  final String dateFilter;
  const _ShiftStatsTab({this.theater, required this.staffEmail, required this.dateFilter});

  @override
  Widget build(BuildContext context) {
    // "Vé đã soát hôm nay"/"Doanh thu check-in" trước đây cộng dồn TOÀN BỘ
    // lịch sử CHECKED_IN, không lọc theo ngày dù nhãn ghi rõ "hôm nay" -
    // lọc theo checkedInAt (thời điểm thật soát vé) trong khoảng 00:00-24:00
    // của ngày staff đang xem.
    final dayStart = DateTime.parse('${dateFilter}T00:00:00');
    final dayEnd = dayStart.add(const Duration(days: 1));
    Query query = FirebaseFirestore.instance
        .collection('tickets')
        .where('paymentStatus', isEqualTo: 'CHECKED_IN')
        .where('checkedInAt', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
        .where('checkedInAt', isLessThan: Timestamp.fromDate(dayEnd));
    if (theater != null) {
      query = query.where('theaterName', isEqualTo: theater);
    }
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final checkedInCount = docs.length;
        final revenue = docs.fold<int>(0, (sum, d) {
          final data = d.data() as Map<String, dynamic>;
          return sum + (data['totalAmount'] as num? ?? 0).toInt();
        });

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _statCard('Vé đã soát hôm nay', '$checkedInCount', Icons.how_to_reg_rounded, Colors.tealAccent),
              const SizedBox(height: 12),
              _statCard('Doanh thu check-in', '${_fmt(revenue)} đ', Icons.attach_money_rounded, Colors.green),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161F),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('THÔNG TIN NHÂN VIÊN',
                        style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _infoRow(Icons.email_outlined, 'Email', staffEmail),
                    if (theater != null) ...[
                      const SizedBox(height: 8),
                      _infoRow(Icons.location_on_outlined, 'Rạp phụ trách', theater!),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
              Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.white38, size: 18),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      ],
    );
  }

  static String _fmt(int v) =>
      v.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
}

class _QrScanScreen extends StatefulWidget {
  final String? theater;
  const _QrScanScreen({this.theater});

  @override
  State<_QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<_QrScanScreen> {
  final MobileScannerController _ctrl = MobileScannerController();
  bool _processing = false;
  String? _resultMsg;
  bool _resultOk = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    setState(() => _processing = true);
    await _ctrl.stop();

    // QR hợp lệ chứa payload JSON {"ticketId": "...", "signature": "..."}
    // được backend ký lúc vé chuyển COMPLETED (xem payment_screen.dart,
    // backend-payos/server.js /sign-ticket & /payos-webhook).
    String? ticketId;
    String? signature;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      ticketId = decoded['ticketId'] as String?;
      signature = decoded['signature'] as String?;
    } catch (_) {
      // Không phải JSON hợp lệ - có thể là vé cũ/định dạng cũ.
    }

    if (ticketId == null || signature == null) {
      _show('Mã QR không hợp lệ hoặc vé chưa được ký. Dùng Check-in thủ công nếu cần.', false);
      return;
    }

    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http.post(
        Uri.parse('${AppConfig.paymentBackendUrl}/verify-checkin'),
        headers: {
          'Content-Type': 'application/json',
          if (idToken != null) 'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'ticketId': ticketId, 'signature': signature}),
      ).timeout(const Duration(seconds: 10));

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final ok = body['success'] == true;
      final message = ok
          ? 'Check-in thành công!\n${body['movieTitle'] ?? ''}'
          : (body['message'] ?? 'Check-in thất bại');
      _show(message, ok);
    } catch (e) {
      _show('Lỗi kết nối máy chủ soát vé: $e', false);
    }
  }

  void _show(String msg, bool ok) {
    setState(() {
      _resultMsg = msg;
      _resultOk = ok;
      _processing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('QUÉT MÃ VÉ', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_rounded, color: Colors.white),
            onPressed: () => _ctrl.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _ctrl, onDetect: _onDetect),
          // Overlay khung quét
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.tealAccent, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          // Result banner
          if (_resultMsg != null)
            Positioned(
              bottom: 60,
              left: 24,
              right: 24,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _resultOk ? Colors.teal.withOpacity(0.9) : Colors.redAccent.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(_resultOk ? Icons.check_circle_rounded : Icons.error_rounded,
                        color: Colors.white, size: 28),
                    const SizedBox(height: 8),
                    Text(_resultMsg!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {
                        setState(() => _resultMsg = null);
                        _ctrl.start();
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
                      child: Text('QUÉT TIẾP', style: TextStyle(color: _resultOk ? Colors.teal : Colors.redAccent, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          if (_processing)
            const Center(child: CircularProgressIndicator(color: Colors.tealAccent)),
        ],
      ),
    );
  }
}
