import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theater_manager/screens/room_management_screen.dart' show roomFormatColor;
import 'combo_selection_screen.dart';

class SeatBookingScreen extends StatefulWidget {
  final Map<String, dynamic> movieData;
  const SeatBookingScreen({super.key, required this.movieData});

  @override
  State<SeatBookingScreen> createState() => _SeatBookingScreenState();
}

class _SeatBookingScreenState extends State<SeatBookingScreen> {
  final List<String> _selectedSeats = [];
  int _totalPrice = 0;

  // Sơ đồ phòng mặc định (khớp layout cũ trước khi có mô hình phòng theo
  // rạp): 3 hàng Thường + 5 hàng VIP + 2 hàng Sweetbox, 10 ghế/hàng.
  int _standardRows = 3;
  int _vipRows = 5;
  int _sweetboxRows = 2;
  int _seatsPerRow = 10;
  // Định dạng phòng (2D Phụ đề/2D Lồng tiếng/VIP/Premium/GoldClass/L'amour).
  // GoldClass tái dùng field 'vipRows' để vẽ toàn ghế đơn cỡ lớn (không ghế
  // đôi); L'amour tái dùng 'sweetboxRows' để vẽ toàn ghế đôi - xem
  // room_management_screen.dart _applyFormatPreset để hiểu quy ước này.
  String? _roomFormat;
  bool get _isGoldClass => _roomFormat == 'GoldClass';
  bool get _isLamour => _roomFormat == "L'amour";
  // Ghế do staff đánh dấu hỏng/bảo trì tạm thời (staff_seat_maintenance_screen.dart)
  // - coi như "đã bán" để khách không chọn được, tới khi staff gỡ đánh dấu.
  Set<String> _brokenSeats = {};

  List<String> get _standardVipRowLabels =>
      List.generate(_standardRows + _vipRows, (i) => String.fromCharCode('A'.codeUnitAt(0) + i));
  List<String> get _vipRowLabels => _standardVipRowLabels.sublist(_standardRows);
  List<String> get _sweetboxRowLabels => List.generate(
      _sweetboxRows, (i) => String.fromCharCode('A'.codeUnitAt(0) + _standardRows + _vipRows + i));

  @override
  void initState() {
    super.initState();
    _roomFormat = widget.movieData['roomFormat'] as String?;
    _loadRoomLayout();
  }

  Future<void> _loadRoomLayout() async {
    final theater = widget.movieData['selectedTheater'];
    final roomName = widget.movieData['roomName'];
    if (theater == null || roomName == null) return; // dùng layout mặc định
    try {
      final snap = await FirebaseFirestore.instance
          .collection('rooms')
          .where('theaterName', isEqualTo: theater)
          .where('roomName', isEqualTo: roomName)
          .limit(1)
          .get();
      if (snap.docs.isEmpty || !mounted) return;
      final d = snap.docs.first.data();
      setState(() {
        _standardRows = (d['standardRows'] as num? ?? 3).toInt();
        _vipRows = (d['vipRows'] as num? ?? 5).toInt();
        _sweetboxRows = (d['sweetboxRows'] as num? ?? 2).toInt();
        _seatsPerRow = (d['seatsPerRow'] as num? ?? 10).toInt();
        _roomFormat = (d['roomFormat'] as String?) ?? _roomFormat;
        _brokenSeats = ((d['brokenSeats'] as List?) ?? []).map((e) => e.toString()).toSet();
      });
    } catch (_) {
      // giữ layout mặc định nếu lỗi mạng/không tìm thấy phòng
    }
  }

  bool _isWeekend() {
    final dateStr = (widget.movieData['selectedDate'] ?? '').toString();
    return dateStr.contains('Chủ Nhật') ||
        dateStr.contains('Thứ Bảy') ||
        dateStr.contains('13/06') ||
        dateStr.contains('14/06');
  }

  int _getTimeSurcharge() {
    final timeStr = (widget.movieData['selectedTime'] ?? '').toString();
    if (timeStr.isEmpty) return 0;
    try {
      final hourStr = timeStr.split(':')[0];
      final hour = int.parse(hourStr);
      if (hour < 12) {
        return -10000; // Giảm giá suất sớm
      } else if (hour >= 22) {
        return 10000; // Phụ thu suất khuya
      }
    } catch (_) {}
    return 0;
  }

  // Giá STD/VIP thật do theater_manager đặt cho suất chiếu này (nếu có
  // showtimeId), dùng chung cho cả sơ đồ giá, chú thích và bảng phân tích.
  int get _standardBasePrice => (widget.movieData['priceStandard'] as num?)?.toInt() ?? 90000;
  int get _vipBasePrice => (widget.movieData['priceVip'] as num?)?.toInt() ?? 120000;

  String _formatPrice(int price) =>
      '${price.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}đ';

  int _getSeatPrice(String seatId) {
    final row = seatId[0];

    int basePrice;
    if (_sweetboxRowLabels.contains(row)) {
      basePrice = _vipBasePrice + 80000; // Sweetbox đôi
    } else if (_vipRowLabels.contains(row)) {
      basePrice = _vipBasePrice; // VIP đơn
    } else {
      basePrice = _standardBasePrice; // Thường đơn
    }

    int weekendSurcharge = _isWeekend() ? 15000 : 0;
    int timeSurcharge = _getTimeSurcharge();

    return basePrice + weekendSurcharge + timeSurcharge;
  }

  String _getLockDocId(String seatId) {
    final movieTitle = widget.movieData['title'] ?? '';
    final theater = widget.movieData['selectedTheater'] ?? '';
    final date = widget.movieData['selectedDate'] ?? '';
    final time = widget.movieData['selectedTime'] ?? '';
    final rawId = '${movieTitle}_${theater}_${date}_${time}_$seatId';
    return rawId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
  }

  void _onSeatTap(String seatId, bool isDouble, List<String> bookedSeats, Map<String, String> currentLocks) {
    if (bookedSeats.contains(seatId) || _brokenSeats.contains(seatId)) return; // REAL-TIME LOCK: Đã bán/hỏng thì cấm chạm

    final userEmail = FirebaseAuth.instance.currentUser?.email ?? 'anonymous';
    final lockedBy = currentLocks[seatId];
    if (lockedBy != null && lockedBy != userEmail) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Ghế này đang được giữ bởi người khác! Vui lòng chọn ghế khác.'),
          backgroundColor: Colors.orangeAccent,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final price = _getSeatPrice(seatId);
    final docId = _getLockDocId(seatId);

    setState(() {
      if (_selectedSeats.contains(seatId)) {
        _selectedSeats.remove(seatId);
        _totalPrice -= price;
        // Xóa giữ ghế tạm thời trên Firestore
        FirebaseFirestore.instance.collection('temporary_locks').doc(docId).delete();
      } else {
        _selectedSeats.add(seatId);
        _totalPrice += price;
        // Lưu giữ ghế tạm thời lên Firestore trong 5 phút
        FirebaseFirestore.instance.collection('temporary_locks').doc(docId).set({
          'movieTitle': widget.movieData['title'] ?? '',
          'theater': widget.movieData['selectedTheater'] ?? '',
          'date': widget.movieData['selectedDate'] ?? '',
          'time': widget.movieData['selectedTime'] ?? '',
          'seatId': seatId,
          'lockedBy': userEmail,
          'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 5))),
        });
      }
    });
  }

  @override
  void dispose() {
    _clearUserLocks();
    super.dispose();
  }

  void _clearUserLocks() async {
    final userEmail = FirebaseAuth.instance.currentUser?.email;
    if (userEmail == null) return;
    for (final seatId in _selectedSeats) {
      try {
        final docId = _getLockDocId(seatId);
        await FirebaseFirestore.instance
            .collection('temporary_locks')
            .doc(docId)
            .delete();
      } catch (e) {
        print('Error clearing temporary lock: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String movieTitle = widget.movieData['title'] ?? 'CHỌN GHẾ';
    final String theater = widget.movieData['selectedTheater'] ?? 'Rạp chưa chọn';
    final String date = widget.movieData['selectedDate'] ?? '';
    final String time = widget.movieData['selectedTime'] ?? '';

    // Lọc real-time vé đã mua cho suất chiếu này
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tickets')
          .where('theaterName', isEqualTo: theater)
          .where('showDate', isEqualTo: date)
          .where('showTime', isEqualTo: time)
          .snapshots(),
      builder: (context, ticketSnapshot) {
        List<String> bookedSeats = [];
        if (ticketSnapshot.hasData) {
          for (var doc in ticketSnapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final String paymentStatus = data['paymentStatus'] ?? 'COMPLETED';
            if (paymentStatus != 'CANCELLED') {
              final List<dynamic> seats = data['seats'] ?? [];
              bookedSeats.addAll(seats.map((s) => s.toString()));
            }
          }
        }

        // Lọc real-time danh sách ghế đang bị giữ tạm thời
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('temporary_locks')
              .where('movieTitle', isEqualTo: movieTitle)
              .where('theater', isEqualTo: theater)
              .where('date', isEqualTo: date)
              .where('time', isEqualTo: time)
              .snapshots(),
          builder: (context, lockSnapshot) {
            final now = DateTime.now();
            final Map<String, String> currentLocks = {}; // seatId -> lockedBy
            if (lockSnapshot.hasData) {
              for (var doc in lockSnapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final expiresAt = (data['expiresAt'] as Timestamp?)?.toDate();
                if (expiresAt != null && expiresAt.isAfter(now)) {
                  final seatId = data['seatId'] as String;
                  final lockedBy = data['lockedBy'] as String;
                  currentLocks[seatId] = lockedBy;
                }
              }
            }

            final userEmail = FirebaseAuth.instance.currentUser?.email ?? 'anonymous';

            return Scaffold(
              backgroundColor: const Color(0xFF000000),
              appBar: AppBar(
                backgroundColor: const Color(0xFF0A0A0A),
                elevation: 0,
                centerTitle: true,
                title: Text(movieTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              body: Column(
                children: [
                  // LỊCH TRÌNH SUẤT CHIẾU
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    color: const Color(0xFF121212),
                    child: Text(
                      widget.movieData['roomFormat'] != null
                          ? '$theater  |  $date  |  Suất: $time  •  ${widget.movieData['roomFormat']}'
                          : '$theater  |  $date  |  Suất: $time',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w500, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 15),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          if (_isGoldClass)
                            _buildNoteItem('Ghế Gold (${_formatPrice(_vipBasePrice)})', const Color(0xFF322A1E))
                          else if (_isLamour)
                            _buildNoteItem("Ghế đôi L'amour (${_formatPrice(_vipBasePrice + 80000)})", const Color(0xFF3A1A1A))
                          else ...[
                            if (_standardRows > 0) _buildNoteItem('Thường (${_formatPrice(_standardBasePrice)})', const Color(0xFF222232)),
                            if (_vipRows > 0) _buildNoteItem('VIP (${_formatPrice(_vipBasePrice)})', const Color(0xFF322A1E)),
                            if (_sweetboxRows > 0) _buildNoteItem('Sweetbox (${_formatPrice(_vipBasePrice + 80000)})', const Color(0xFF3A2232)),
                          ],
                          _buildNoteItem('Đang chọn', Colors.amber),
                          _buildNoteItem('Đang giữ (5p)', Colors.grey.withValues(alpha: 0.3)),
                          _buildNoteItem('Đã bán', Colors.redAccent),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),

                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40), height: 4, width: double.infinity,
                    decoration: BoxDecoration(color: Colors.amber, boxShadow: [BoxShadow(color: Colors.amber.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 2)]),
                  ),
                  const SizedBox(height: 4),
                  const Text('MÀN HÌNH CHIẾU', style: TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const SizedBox(height: 20),

                  // SƠ ĐỒ GHẾ THU PHÓNG (PINCH-TO-ZOOM)
                  Expanded(
                    child: InteractiveViewer(
                      minScale: 1.0,
                      maxScale: 2.5,
                      boundaryMargin: const EdgeInsets.all(20),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Column(
                            children: [
                              for (var row in _standardVipRowLabels) ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(width: 20, alignment: Alignment.center, child: Text(row, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12))),
                                    ...List.generate(_seatsPerRow, (index) {
                                      final seatId = '$row${index + 1}';
                                      final isSelected = _selectedSeats.contains(seatId);
                                      final isBooked = bookedSeats.contains(seatId) || _brokenSeats.contains(seatId);
                                      final lockedBy = currentLocks[seatId];
                                      final isLockedByOthers = lockedBy != null && lockedBy != userEmail;
                                      final isVIP = _vipRowLabels.contains(row);
                                      final isGold = _isGoldClass && isVIP;
                                      final goldColor = roomFormatColor('GoldClass');

                                      Color seatColor = const Color(0xFF222232);
                                      Color borderColor = Colors.white.withValues(alpha: 0.05);
                                      Color labelColor = Colors.white70;
                                      if (isBooked) {
                                        seatColor = Colors.redAccent.withValues(alpha: 0.3);
                                        borderColor = Colors.redAccent;
                                      } else if (isLockedByOthers) {
                                        seatColor = Colors.grey.withValues(alpha: 0.15);
                                        borderColor = Colors.grey.withValues(alpha: 0.3);
                                      } else if (isSelected) {
                                        seatColor = isVIP ? (isGold ? goldColor : Colors.orangeAccent) : Colors.amber;
                                        borderColor = Colors.white;
                                        labelColor = Colors.black;
                                      } else if (isGold) {
                                        seatColor = const Color(0xFF2A2415);
                                        borderColor = goldColor.withValues(alpha: 0.4);
                                        labelColor = goldColor;
                                      } else if (isVIP) {
                                        seatColor = const Color(0xFF322A1E);
                                        borderColor = Colors.orangeAccent.withValues(alpha: 0.2);
                                        labelColor = Colors.orangeAccent;
                                      }
                                      if (isBooked) labelColor = Colors.redAccent;

                                      final seatSize = isGold ? 40.0 : 28.0;

                                      return GestureDetector(
                                        onTap: () => _onSeatTap(seatId, false, bookedSeats, currentLocks),
                                        child: Container(
                                          margin: const EdgeInsets.all(3),
                                          width: seatSize, height: seatSize,
                                          decoration: BoxDecoration(
                                            color: seatColor,
                                            borderRadius: BorderRadius.circular(isGold ? 8 : 5),
                                            border: Border.all(color: borderColor, width: isGold ? 1.5 : 1),
                                          ),
                                          alignment: Alignment.center,
                                          child: isLockedByOthers
                                              ? const Icon(Icons.lock_rounded, color: Colors.grey, size: 12)
                                              : (isGold
                                                  ? Icon(Icons.event_seat_rounded, color: labelColor, size: 20)
                                                  : Text(
                                                      '${index + 1}',
                                                      style: TextStyle(color: labelColor, fontSize: 10, fontWeight: FontWeight.bold),
                                                    )),
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ],
                              if (_sweetboxRows > 0) ...[
                              const SizedBox(height: 15),
                              Text(
                                _isLamour ? "HÀNG GHẾ ĐÔI L'AMOUR - RIÊNG TƯ LÃNG MẠN" : 'HÀNG GHẾ ĐÔI SWEETBOX PREMIUM',
                                style: TextStyle(color: _isLamour ? roomFormatColor("L'amour") : Colors.pinkAccent, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              for (var row in _sweetboxRowLabels) ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(width: 20, alignment: Alignment.center, child: Text(row, style: TextStyle(color: _isLamour ? roomFormatColor("L'amour") : Colors.pinkAccent, fontWeight: FontWeight.bold, fontSize: 12))),
                                    ...List.generate((_seatsPerRow / 2).floor(), (index) {
                                      final seatId = '$row${index * 2 + 1}-$row${index * 2 + 2}';
                                      final isSelected = _selectedSeats.contains(seatId);
                                      final isBooked = bookedSeats.contains(seatId) || _brokenSeats.contains(seatId);
                                      final lockedBy = currentLocks[seatId];
                                      final isLockedByOthers = lockedBy != null && lockedBy != userEmail;
                                      final accentColor = _isLamour ? roomFormatColor("L'amour") : Colors.pinkAccent;

                                      Color sweetColor = const Color(0xFF3A2232);
                                      Color sweetBorder = accentColor.withValues(alpha: 0.2);
                                      if (isBooked) {
                                        sweetColor = Colors.redAccent.withValues(alpha: 0.2);
                                        sweetBorder = Colors.redAccent;
                                      } else if (isLockedByOthers) {
                                        sweetColor = Colors.grey.withValues(alpha: 0.15);
                                        sweetBorder = Colors.grey.withValues(alpha: 0.3);
                                      } else if (isSelected) {
                                        sweetColor = accentColor;
                                        sweetBorder = Colors.white;
                                      }

                                      return GestureDetector(
                                        onTap: () => _onSeatTap(seatId, true, bookedSeats, currentLocks),
                                        child: Container(
                                          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                                          width: 62, height: 30,
                                          decoration: BoxDecoration(
                                            color: sweetColor,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: sweetBorder),
                                          ),
                                          alignment: Alignment.center,
                                          child: isLockedByOthers
                                              ? const Icon(Icons.lock_rounded, color: Colors.grey, size: 14)
                                              : Text(
                                                  '$row${index * 2 + 1}•$row${index * 2 + 2}',
                                                  style: TextStyle(
                                                    color: isBooked ? Colors.redAccent : Colors.white,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ],
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // HIỂN THỊ CHI TIẾT GIÁ (PHÂN TÍCH GIÁ ĐỘNG)
                  if (_selectedSeats.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                      color: const Color(0xFF0A0A0A).withValues(alpha: 0.8),
                      child: Text(
                        (_isGoldClass
                                ? 'Phân tích giá vé: Ghế Gold: ${_formatPrice(_vipBasePrice)}. '
                                : _isLamour
                                    ? "Phân tích giá vé: Ghế đôi L'amour: ${_formatPrice(_vipBasePrice + 80000)}. "
                                    : 'Phân tích giá vé: Ghế Thường: ${_formatPrice(_standardBasePrice)}, VIP: ${_formatPrice(_vipBasePrice)}, Sweetbox: ${_formatPrice(_vipBasePrice + 80000)}. ') +
                        '${_isWeekend() ? "Cuối tuần (+15k/ghế)" : "Ngày thường (+0k)"} '
                        '${_getTimeSurcharge() < 0 ? "| Suất sớm (-10k/ghế)" : (_getTimeSurcharge() > 0 ? "| Suất khuya (+10k/ghế)" : "| Suất thường (+0k)")}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white38, fontSize: 10, fontStyle: FontStyle.italic),
                      ),
                    ),

                  // BOTTOM SUMMARY BAR
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(color: Color(0xFF0A0A0A), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                    child: SafeArea(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_selectedSeats.isEmpty ? 'Chưa chọn ghế' : 'Ghế: ${_selectedSeats.join(', ')}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(height: 4),
                              Text('Tổng: ${_totalPrice.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')} đ', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 18)),
                            ],
                          ),
                          ElevatedButton(
                            onPressed: _selectedSeats.isEmpty ? null : () {
                              showDialog(
                                context: context,
                                builder: (dialogContext) {
                                  return AlertDialog(
                                    backgroundColor: const Color(0xFF121212),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    title: const Text('🌟 ƯU ĐÃI ĐẶC BIỆT', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center),
                                    content: SizedBox(
                                      // AlertDialog đo content bằng IntrinsicWidth - Image.network với
                                      // width: double.infinity bên trong sẽ crash ("input.isFinite")
                                      // nếu không có ràng buộc chiều rộng cụ thể bao ngoài trước.
                                      width: double.maxFinite,
                                      child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Image.asset(
                                            'assets/images/combo_couple.png',
                                            width: double.infinity,
                                            height: 150,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) => Container(
                                              width: double.infinity,
                                              height: 150,
                                              color: Colors.black26,
                                              child: const Icon(Icons.fastfood_rounded, color: Colors.amber, size: 50),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        const Text(
                                          'Combo Premium',
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          '2 Bắp lớn + 3 Nước ngọt lớn + 1 phần Quà lưu niệm độc quyền từ Stella.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.white70, fontSize: 12),
                                        ),
                                        const SizedBox(height: 12),
                                        const Text(
                                          'Chỉ với 160.000 đ',
                                          style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                      ],
                                      ),
                                    ),
                                    actionsAlignment: MainAxisAlignment.spaceEvenly,
                                    actions: [
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(dialogContext); // Đóng popup
                                          final expiryTime = DateTime.now().add(const Duration(minutes: 5));
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => ComboSelectionScreen(
                                                movieData: widget.movieData,
                                                selectedSeats: _selectedSeats,
                                                ticketPrice: _totalPrice,
                                                expiryTime: expiryTime,
                                                preSelectedComboId: null,
                                              ),
                                            ),
                                          );
                                        },
                                        child: const Text('BỎ QUA', style: TextStyle(color: Colors.grey)),
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
                                          Navigator.pop(dialogContext); // Đóng popup
                                          final expiryTime = DateTime.now().add(const Duration(minutes: 5));
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => ComboSelectionScreen(
                                                movieData: widget.movieData,
                                                selectedSeats: _selectedSeats,
                                                ticketPrice: _totalPrice,
                                                expiryTime: expiryTime,
                                                preSelectedComboId: 'premium',
                                              ),
                                            ),
                                          );
                                        },
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                                        child: const Text('MUA NGAY', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, disabledBackgroundColor: Colors.white10, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            child: const Text('Tiếp Tục', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildNoteItem(String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(color: Colors.grey, fontSize: 11)),
      ],
    );
  }
}