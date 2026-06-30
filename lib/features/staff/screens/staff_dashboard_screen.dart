import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../providers/user_provider.dart';

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
      backgroundColor: const Color(0xFF0F0F13),
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.tealAccent),
            onPressed: _openQrScanner,
            tooltip: 'Quét mã QR',
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
          ),
        ],
      ),
    );
  }

  void _openQrScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _QrScanScreen()),
    );
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
  String _statusFilter = 'confirmed';

  @override
  Widget build(BuildContext context) {
    Query query = FirebaseFirestore.instance
        .collection('tickets')
        .where('status', isEqualTo: _statusFilter);

    if (widget.theater != null) {
      query = query.where('theater', isEqualTo: widget.theater);
    }

    return Column(
      children: [
        // Status filter chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              _chip('Đã thanh toán', 'confirmed', Colors.green),
              const SizedBox(width: 8),
              _chip('Đã check-in', 'checked_in', Colors.tealAccent),
            ],
          ),
        ),

        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: query.orderBy('created_at', descending: true).limit(50).snapshots(),
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
    final status = d['payment_status'] ?? '';
    final isCheckedIn = status == 'CHECKED_IN';
    final seats = (d['seats'] as List?)?.join(', ') ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF16161F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCheckedIn ? Colors.tealAccent.withOpacity(0.3) : Colors.white.withOpacity(0.05),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isCheckedIn ? Colors.teal.withOpacity(0.15) : Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isCheckedIn ? Icons.check_circle_rounded : Icons.confirmation_number_rounded,
              color: isCheckedIn ? Colors.tealAccent : Colors.amber,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d['title'] ?? '—',
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
              child: const Text('CHECK-IN', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
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

  Future<void> _checkIn(BuildContext context, String ticketId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('XÁC NHẬN CHECK-IN', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 14)),
        content: const Text('Xác nhận cho khách vào rạp?', style: TextStyle(color: Colors.white70)),
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
    if (confirm == true) {
      await FirebaseFirestore.instance.collection('tickets').doc(ticketId).update({
        'payment_status': 'CHECKED_IN',
        'checked_in_at': Timestamp.now(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check-in thành công!'), backgroundColor: Colors.teal),
        );
      }
    }
  }
}

// ── Shift stats tab ────────────────────────────────────────────────────────────
class _ShiftStatsTab extends StatelessWidget {
  final String? theater;
  final String staffEmail;
  const _ShiftStatsTab({this.theater, required this.staffEmail});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tickets')
          .where('payment_status', isEqualTo: 'CHECKED_IN')
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final checkedInCount = docs.length;
        final revenue = docs.fold<int>(0, (sum, d) {
          final data = d.data() as Map<String, dynamic>;
          return sum + (data['totalPrice'] as num? ?? 0).toInt();
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

// ── QR Scanner screen ──────────────────────────────────────────────────────────
class _QrScanScreen extends StatefulWidget {
  const _QrScanScreen();

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
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null) return;

    setState(() => _processing = true);
    await _ctrl.stop();

    try {
      // Ticket ID baked vào QR
      final snap = await FirebaseFirestore.instance.collection('tickets').doc(code).get();
      if (!snap.exists) {
        _show('Vé không tồn tại!', false);
        return;
      }
      final data = snap.data()!;
      final status = data['payment_status'];
      if (status == 'CHECKED_IN') {
        _show('Vé đã được sử dụng!', false);
        return;
      }
      if (status != 'confirmed') {
        _show('Vé chưa thanh toán!', false);
        return;
      }
      await FirebaseFirestore.instance.collection('tickets').doc(code).update({
        'payment_status': 'CHECKED_IN',
        'checked_in_at': Timestamp.now(),
      });
      _show('Check-in thành công!\n${data['title'] ?? ''}', true);
    } catch (e) {
      _show('Lỗi: $e', false);
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
