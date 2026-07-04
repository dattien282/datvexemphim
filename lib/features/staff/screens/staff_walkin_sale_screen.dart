import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants.dart';
import 'package:dat_ve_xem_phim_group5/features/theater_manager/screens/room_management_screen.dart' show roomFormatColor;
import '../../../models/room_layout.dart';
import '../../booking_and_payment/services/pricing_service.dart';
import '../../booking_and_payment/services/seat_reservation_service.dart';
import '../../theater_manager/widgets/seat_grid_widget.dart';

/// Bán vé tại quầy cho khách vãng lai (không có tài khoản/app) - trước đây
/// staff chỉ soát được vé đã đặt sẵn qua app, không có cách nào tạo vé mới
/// trực tiếp cho khách mua tại quầy bằng tiền mặt. Vé tạo ra ở đây có
/// paymentStatus COMPLETED ngay (đã thu tiền mặt tại chỗ) và được ký QR như
/// vé mua qua app để staff khác vẫn check-in được bình thường.
class StaffWalkInSaleScreen extends StatefulWidget {
  final String? theater;
  const StaffWalkInSaleScreen({super.key, required this.theater});

  @override
  State<StaffWalkInSaleScreen> createState() => _StaffWalkInSaleScreenState();
}

class _StaffWalkInSaleScreenState extends State<StaffWalkInSaleScreen> {
  QueryDocumentSnapshot? _selectedShowtime;
  final List<String> _selectedSeats = [];
  final _customerNameCtrl = TextEditingController();
  bool _saving = false;

  RoomLayout _layout = const RoomLayout(theaterName: '', roomName: '', roomFormat: 'Standard');

  @override
  void dispose() {
    _customerNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _onShowtimeSelected(QueryDocumentSnapshot doc) async {
    setState(() {
      _selectedShowtime = doc;
      _selectedSeats.clear();
      _layout = const RoomLayout(theaterName: '', roomName: '', roomFormat: 'Standard');
    });
    final d = doc.data() as Map<String, dynamic>;
    final roomName = d['roomName'] as String?;
    if (roomName == null || widget.theater == null) return;
    final roomSnap = await FirebaseFirestore.instance
        .collection('rooms')
        .where('theaterName', isEqualTo: widget.theater)
        .where('roomName', isEqualTo: roomName)
        .limit(1)
        .get();
    if (roomSnap.docs.isEmpty || !mounted) return;
    final roomDoc = roomSnap.docs.first;
    setState(() {
      _layout = RoomLayout.fromMap(roomDoc.id, roomDoc.data());
    });
  }

  int _seatPrice(String seatId, int priceStandard, int priceVip) =>
      seatBasePrice(seatId: seatId, layout: _layout, priceStandard: priceStandard, priceVip: priceVip);

  // Kiểm tra trước (best-effort, không transaction) xem có ghế nào đang được
  // khách giữ qua app (temporary_locks) không - trước đây staff bán tại quầy
  // hoàn toàn bỏ qua bảng khoá này, chỉ check vé đã hoàn tất, nên có thể bán
  // trùng đúng lúc khách đang thao tác chọn ghế đó trên app.
  Future<Set<String>> _fetchActiveLockedSeats(Map<String, dynamic> showtimeData) async {
    final now = DateTime.now();
    final snap = await FirebaseFirestore.instance
        .collection('temporary_locks')
        .where('theater', isEqualTo: widget.theater)
        .where('date', isEqualTo: showtimeData['date'])
        .where('time', isEqualTo: showtimeData['time'])
        .get();
    final locked = <String>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final expiresAt = (data['expiresAt'] as Timestamp?)?.toDate();
      if (expiresAt != null && expiresAt.isAfter(now)) {
        locked.add(data['seatId'] as String);
      }
    }
    return locked;
  }

  Future<void> _confirmSale() async {
    if (_selectedShowtime == null || _selectedSeats.isEmpty) return;
    final staff = FirebaseAuth.instance.currentUser;
    final d = _selectedShowtime!.data() as Map<String, dynamic>;
    final priceStandard = (d['priceStandard'] as num? ?? 90000).toInt();
    final priceVip = (d['priceVip'] as num? ?? 120000).toInt();
    final total = _selectedSeats.fold<int>(0, (sum, s) => sum + _seatPrice(s, priceStandard, priceVip));

    final lockedSeats = await _fetchActiveLockedSeats(d);
    final conflictingSeats = _selectedSeats.where(lockedSeats.contains).toList();
    if (conflictingSeats.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ghế ${conflictingSeats.join(", ")} đang được khách giữ qua app, vui lòng chọn ghế khác.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('XÁC NHẬN BÁN VÉ', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 14)),
        content: Text(
          'Ghế: ${_selectedSeats.join(', ')}\nTổng tiền mặt thu: ${_fmt(total)} đ\n\nXác nhận đã thu đủ tiền mặt từ khách?',
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('HỦY', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            child: const Text('ĐÃ THU TIỀN - TẠO VÉ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _saving = true);
    try {
      final showtimeId = _selectedShowtime!.id;
      final seatIds = List<String>.from(_selectedSeats);
      final ticketRef = FirebaseFirestore.instance.collection('tickets').doc();

      // Bọc trong transaction để xác thực lại ghế còn trống ngay tại thời
      // điểm ghi vé - chặn trường hợp 2 giao dịch (VD: staff bán tại quầy +
      // khách thanh toán qua app) cùng thắng 1 ghế nếu cả 2 gần như đồng thời.
      final reserved = await FirebaseFirestore.instance.runTransaction((transaction) async {
        final seatsAvailable = await areSeatsAvailable(transaction, showtimeId: showtimeId, seatIds: seatIds);
        if (!seatsAvailable) return false;

        reserveSeats(transaction, showtimeId: showtimeId, seatIds: seatIds);
        transaction.set(ticketRef, {
          'orderCode': DateTime.now().millisecondsSinceEpoch % 1000000,
          'userId': staff?.uid,
          'showtimeId': showtimeId,
          'email': _customerNameCtrl.text.trim().isEmpty ? (staff?.email ?? 'quầy vé') : _customerNameCtrl.text.trim(),
          'movieTitle': d['movieTitle'],
          'posterUrl': '',
          'seats': _selectedSeats,
          'combos': const [],
          'ticketAmount': total,
          'discountAmount': 0,
          'totalAmount': total,
          'voucherCode': null,
          'paymentMethod': 'cash_counter',
          'paymentStatus': 'COMPLETED',
          'theaterName': widget.theater,
          'showDate': d['date'],
          'showTime': d['time'],
          'showtime': '${widget.theater} | ${d['date']} | ${d['time']}',
          'roomName': d['roomName'],
          'roomFormat': d['roomFormat'],
          'language': d['language'] ?? 'Phụ đề',
          'sessionType': d['sessionType'] ?? 'Standard',
          'soldByStaffUid': staff?.uid,
          'soldByStaffEmail': staff?.email,
          'createdAt': Timestamp.now(),
          'paidAt': Timestamp.now(),
        });
        return true;
      });

      if (!reserved) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ghế vừa được đặt bởi giao dịch khác, vui lòng chọn lại ghế.'), backgroundColor: Colors.redAccent),
          );
        }
        return;
      }

      // Ký QR giống vé mua qua app để staff khác vẫn check-in bình thường.
      try {
        await http.post(
          Uri.parse('${AppConfig.paymentBackendUrl}/sign-ticket'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'ticketId': ticketRef.id}),
        ).timeout(const Duration(seconds: 10));
      } catch (_) {
        // Không chặn luồng bán vé nếu ký QR lỗi - vé vẫn có thể check-in thủ công.
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã tạo vé bán tại quầy thành công!'), backgroundColor: Colors.teal),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi tạo vé: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _fmt(int v) => v.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');

  @override
  Widget build(BuildContext context) {
    final theater = widget.theater;
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text('BÁN VÉ TẠI QUẦY', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 14)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: theater == null
          ? const Center(child: Text('Tài khoản chưa được gán rạp.', style: TextStyle(color: Colors.white38)))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('showtimes')
                        .where('theaterName', isEqualTo: theater)
                        .where('status', isEqualTo: 'active')
                        .snapshots(),
                    builder: (context, snap) {
                      final docs = snap.data?.docs ?? [];
                      final currentId = _selectedShowtime != null && docs.any((d) => d.id == _selectedShowtime!.id)
                          ? _selectedShowtime!.id
                          : null;
                      return DropdownButtonFormField<String>(
                        value: currentId,
                        dropdownColor: const Color(0xFF1E1E2A),
                        isExpanded: true,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF16161F),
                          prefixIcon: const Icon(Icons.local_movies_rounded, color: Colors.tealAccent, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                        ),
                        hint: const Text('Chọn suất chiếu', style: TextStyle(color: Colors.white38, fontSize: 12)),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        items: docs.map((doc) {
                          final d = doc.data() as Map<String, dynamic>;
                          return DropdownMenuItem<String>(
                            value: doc.id,
                            child: Text('${d['movieTitle']} • ${d['date']} ${d['time']} • ${d['roomName'] ?? ''} • ${d['language'] ?? 'Phụ đề'} • ${d['sessionType'] ?? 'Standard'}',
                                overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (id) {
                          if (id != null) {
                            final doc = docs.firstWhere((d) => d.id == id);
                            _onShowtimeSelected(doc);
                          }
                        },
                      );
                    },
                  ),
                ),
                if (_selectedShowtime != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _customerNameCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Tên/SĐT khách (không bắt buộc)',
                        hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF16161F),
                        prefixIcon: const Icon(Icons.person_outline_rounded, color: Colors.tealAccent, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(child: _buildSeatGrid()),
                  _buildSummaryBar(),
                ] else
                  const Expanded(
                    child: Center(child: Text('Chọn suất chiếu để bắt đầu bán vé.', style: TextStyle(color: Colors.white38))),
                  ),
              ],
            ),
    );
  }

  Widget _buildSeatGrid() {
    final d = _selectedShowtime!.data() as Map<String, dynamic>;
    final theater = widget.theater;
    final date = d['date'];
    final time = d['time'];
    final roomFormat = d['roomFormat'] as String?;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tickets')
          .where('theaterName', isEqualTo: theater)
          .where('showDate', isEqualTo: date)
          .where('showTime', isEqualTo: time)
          .snapshots(),
      builder: (context, snap) {
        final bookedSeats = <String>{..._layout.brokenSeats};
        for (final doc in snap.data?.docs ?? []) {
          final td = doc.data() as Map<String, dynamic>;
          if (td['paymentStatus'] != 'CANCELLED') {
            for (final s in (td['seats'] as List? ?? [])) bookedSeats.add(s.toString());
          }
        }
        return InteractiveViewer(
          minScale: 1.0,
          maxScale: 2.5,
          child: SingleChildScrollView(
            child: Column(
              children: [
                if (roomFormat != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(roomFormat, style: TextStyle(color: roomFormatColor(roomFormat), fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                SeatGridView(
                  layout: _layout,
                  selectedSeats: _selectedSeats.toSet(),
                  bookedSeats: bookedSeats,
                  onSeatTap: (seatId) => setState(() {
                    if (_selectedSeats.contains(seatId)) {
                      _selectedSeats.remove(seatId);
                    } else {
                      _selectedSeats.add(seatId);
                    }
                  }),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryBar() {
    final d = _selectedShowtime!.data() as Map<String, dynamic>;
    final priceStandard = (d['priceStandard'] as num? ?? 90000).toInt();
    final priceVip = (d['priceVip'] as num? ?? 120000).toInt();
    final total = _selectedSeats.fold<int>(0, (sum, s) => sum + _seatPrice(s, priceStandard, priceVip));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(color: Color(0xFF0A0A0A), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_selectedSeats.isEmpty ? 'Chưa chọn ghế' : 'Ghế: ${_selectedSeats.join(', ')}',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  Text('${_fmt(total)} đ', style: const TextStyle(color: Colors.tealAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: (_selectedSeats.isEmpty || _saving) ? null : _confirmSale,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                disabledBackgroundColor: Colors.white10,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('BÁN VÉ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
