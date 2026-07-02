import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants.dart';
import '../../theater_manager/screens/room_management_screen.dart' show roomFormatColor;

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

  int _standardRows = 3, _vipRows = 5, _sweetboxRows = 2, _seatsPerRow = 10;
  Set<String> _brokenSeats = {};

  List<String> get _allRowLabels =>
      List.generate(_standardRows + _vipRows + _sweetboxRows, (i) => String.fromCharCode('A'.codeUnitAt(0) + i));
  List<String> get _vipRowLabels => _allRowLabels.sublist(_standardRows, _standardRows + _vipRows);
  List<String> get _sweetboxRowLabels => _allRowLabels.sublist(_standardRows + _vipRows);

  @override
  void dispose() {
    _customerNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _onShowtimeSelected(QueryDocumentSnapshot doc) async {
    setState(() {
      _selectedShowtime = doc;
      _selectedSeats.clear();
      _standardRows = 3;
      _vipRows = 5;
      _sweetboxRows = 2;
      _seatsPerRow = 10;
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
    final rd = roomSnap.docs.first.data();
    setState(() {
      _standardRows = (rd['standardRows'] as num? ?? 3).toInt();
      _vipRows = (rd['vipRows'] as num? ?? 5).toInt();
      _sweetboxRows = (rd['sweetboxRows'] as num? ?? 2).toInt();
      _seatsPerRow = (rd['seatsPerRow'] as num? ?? 10).toInt();
      _brokenSeats = ((rd['brokenSeats'] as List?) ?? []).map((e) => e.toString()).toSet();
    });
  }

  int _seatPrice(String seatId, int priceStandard, int priceVip) {
    final row = seatId[0];
    if (_sweetboxRowLabels.contains(row)) return priceVip + 80000;
    if (_vipRowLabels.contains(row)) return priceVip;
    return priceStandard;
  }

  Future<void> _confirmSale() async {
    if (_selectedShowtime == null || _selectedSeats.isEmpty) return;
    final staff = FirebaseAuth.instance.currentUser;
    final d = _selectedShowtime!.data() as Map<String, dynamic>;
    final priceStandard = (d['priceStandard'] as num? ?? 90000).toInt();
    final priceVip = (d['priceVip'] as num? ?? 120000).toInt();
    final total = _selectedSeats.fold<int>(0, (sum, s) => sum + _seatPrice(s, priceStandard, priceVip));

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
      final ticketRef = await FirebaseFirestore.instance.collection('tickets').add({
        'orderCode': DateTime.now().millisecondsSinceEpoch % 1000000,
        'userId': staff?.uid,
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
        'soldByStaffUid': staff?.uid,
        'soldByStaffEmail': staff?.email,
        'createdAt': Timestamp.now(),
        'paidAt': Timestamp.now(),
      });

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
                            child: Text('${d['movieTitle']} • ${d['date']} ${d['time']} • ${d['roomName'] ?? ''}',
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
        final bookedSeats = <String>{};
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
                for (final row in _allRowLabels.sublist(0, _standardRows + _vipRows))
                  _buildRow(row, bookedSeats, isSweetbox: false),
                if (_sweetboxRows > 0) ...[
                  const SizedBox(height: 10),
                  const Text('GHẾ ĐÔI', style: TextStyle(color: Colors.pinkAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  for (final row in _sweetboxRowLabels) _buildRow(row, bookedSeats, isSweetbox: true),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRow(String row, Set<String> bookedSeats, {required bool isSweetbox}) {
    final isVip = _vipRowLabels.contains(row);
    final count = isSweetbox ? (_seatsPerRow / 2).floor() : _seatsPerRow;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(width: 20, child: Text(row, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold))),
        ...List.generate(count, (i) {
          final seatId = isSweetbox ? '$row${i * 2 + 1}-$row${i * 2 + 2}' : '$row${i + 1}';
          final isBooked = bookedSeats.contains(seatId) || _brokenSeats.contains(seatId);
          final isSelected = _selectedSeats.contains(seatId);
          Color color = const Color(0xFF222232);
          if (isBooked) {
            color = Colors.redAccent.withValues(alpha: 0.3);
          } else if (isSelected) {
            color = Colors.amber;
          } else if (isSweetbox) {
            color = const Color(0xFF3A2232);
          } else if (isVip) {
            color = const Color(0xFF322A1E);
          }
          return GestureDetector(
            onTap: isBooked
                ? null
                : () => setState(() {
                      if (isSelected) {
                        _selectedSeats.remove(seatId);
                      } else {
                        _selectedSeats.add(seatId);
                      }
                    }),
            child: Container(
              margin: const EdgeInsets.all(2),
              width: isSweetbox ? 50 : 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5)),
              child: Text(
                isSweetbox ? '${i * 2 + 1}•${i * 2 + 2}' : '${i + 1}',
                style: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          );
        }),
      ],
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
