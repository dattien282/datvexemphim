import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theater_manager/screens/room_management_screen.dart' show kPremiumRoomFormats;
import '../../theater_manager/widgets/seat_grid_widget.dart';
import '../../../models/room_layout.dart';
import '../../../models/showtime.dart';
import '../services/pricing_service.dart';
import '../services/seat_layout_helper.dart';
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

  // Sơ đồ + định dạng phòng, tải lại từ collection 'rooms' trong _loadRoomLayout.
  // Mặc định khớp layout cũ trước khi có mô hình phòng theo rạp: 3 hàng
  // Thường + 5 hàng VIP + 2 hàng Sweetbox, 10 ghế/hàng.
  RoomLayout _layout = const RoomLayout(theaterName: '', roomName: '', roomFormat: 'Standard');
  String? get _roomFormat => _layout.roomFormat;
  bool get _isGoldClass => _layout.isGoldClass;
  bool get _isLamour => _layout.isLamour;
  bool get _isMotionSeat => _layout.isMotionSeat;

  @override
  void initState() {
    super.initState();
    final initialFormat = widget.movieData['roomFormat'] as String?;
    if (initialFormat != null) {
      _layout = RoomLayout(
        theaterName: '',
        roomName: '',
        roomFormat: initialFormat,
        seatLayoutKind: seatLayoutKindForFormat(initialFormat),
      );
    }
    _loadRoomLayout();
    _loadPricingRules();
  }

  String _theaterSize = 'Medium';


  Future<void> _loadRoomLayout() async {
    final theater = widget.movieData['selectedTheater'];
    final roomName = widget.movieData['roomName'];
    if (theater == null) return;
    
    try {
      // 1. Fetch theater size for pricing
      final theaterSnap = await FirebaseFirestore.instance
          .collection('theaters')
          .where('name', isEqualTo: theater)
          .limit(1)
          .get();
      
      if (theaterSnap.docs.isNotEmpty && mounted) {
        setState(() {
          _theaterSize = theaterSnap.docs.first.data()['size'] as String? ?? 'Medium';
        });
      }

      // 2. Fetch room layout - ưu tiên đúng phiên bản sơ đồ ghế đã chốt lúc
      // tạo suất chiếu (seatMapVersionId, xem models/room_layout.dart
      // SeatMapVersion) để không bị lệch nếu phòng được sửa sơ đồ sau khi
      // suất chiếu này đã bán vé. Suất chiếu cũ chưa có field này (tạo trước
      // khi tính năng version ra đời) fallback về tra theo tên phòng như cũ.
      final seatMapVersionId = widget.movieData['seatMapVersionId'] as String?;
      if (seatMapVersionId != null) {
        final versionDoc = await FirebaseFirestore.instance.collection('seat_map_versions').doc(seatMapVersionId).get();
        if (versionDoc.exists && mounted) {
          setState(() {
            _layout = RoomLayout.fromMap(versionDoc.id, versionDoc.data()!);
          });
        }
        return;
      }

      if (roomName == null) return;

      final snap = await FirebaseFirestore.instance
          .collection('rooms')
          .where('theaterName', isEqualTo: theater)
          .where('roomName', isEqualTo: roomName)
          .limit(1)
          .get();
      if (snap.docs.isEmpty || !mounted) return;
      final roomDoc = snap.docs.first;
      setState(() {
        _layout = RoomLayout.fromMap(roomDoc.id, roomDoc.data());
      });
    } catch (_) {
      // giữ layout mặc định nếu lỗi mạng/không tìm thấy phòng
    }
  }

  // Thời điểm chiếu thật của suất đã chọn: ưu tiên 'showAt' (millis, do
  // showtime_selection_screen.dart truyền qua từ Showtime thật) - fallback
  // parse chuỗi 'selectedDate'/'selectedTime' cho luồng cũ/demo không có
  // showtimeId thật (widget.movieData['showtimeId'] == null).
  DateTime? get _showAtDateTime {
    final raw = widget.movieData['showAt'];
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return Showtime.parseLegacyDateTime(
      widget.movieData['selectedDate']?.toString(),
      widget.movieData['selectedTime']?.toString(),
    );
  }

  // Luật giá từ collection pricing_rules (PricingEngine - Giai đoạn D), tải 1
  // lần khi mở màn hình. null = chưa tải xong hoặc collection trống/lỗi mạng
  // - _surcharge tự fallback về công thức cứng cũ trong trường hợp đó.
  List<PricingRule>? _pricingRules;

  Future<void> _loadPricingRules() async {
    final rules = await PricingEngine.load();
    if (rules != null && mounted) setState(() => _pricingRules = rules);
  }

  ShowtimeSurcharge? get _surcharge {
    final showAt = _showAtDateTime;
    if (showAt == null) return null;
    final sessionType = widget.movieData['sessionType'] as String?;
    final rules = _pricingRules;
    if (rules != null) {
      // basePrice (chỉ dùng cho luật kiểu percent) tính THÔ trực tiếp từ giá
      // suất chiếu/theater size - TUYỆT ĐỐI không đi qua _standardBasePrice:
      // getter đó kiểm tra _wednesdayDiscountApplies, vốn gọi ngược lại
      // _surcharge này -> đệ quy vô hạn (StackOverflow đã xảy ra thật khi mở
      // màn chọn ghế sau khi luật giá được tải).
      final rawBasePrice = _hasRealShowtime
          ? ((widget.movieData['priceStandard'] as num?)?.toInt() ?? _standardPriceFromTheaterSize)
          : _standardPriceFromTheaterSize;
      return PricingEngine.resolve(
        rules,
        showAt: showAt,
        sessionType: sessionType,
        theaterName: widget.movieData['selectedTheater'] as String?,
        basePrice: rawBasePrice,
      );
    }
    return ShowtimeSurcharge.fromShowAt(showAt, sessionType: sessionType);
  }

  bool get _hasRealShowtime => widget.movieData['showtimeId'] != null;

  // Phòng cao cấp trở lên (Premium/GoldClass/L'amour/IMAX/4DX/ScreenX) đã ở
  // phân khúc giá cao, nên không cộng thêm ưu đãi Thứ 4 vào giá vé của các
  // phòng này (khác với discount_service.dart giảm % trên tổng hóa đơn - đó
  // là ưu đãi "Happy Wednesday" theo NGÀY ĐẶT VÉ, còn ưu đãi ở đây theo NGÀY
  // SUẤT CHIẾU, 2 khái niệm khác nhau, cố tình không gộp làm một).
  bool get _isPremiumFormat => kPremiumRoomFormats.contains(_roomFormat);
  bool get _wednesdayDiscountApplies => (_surcharge?.isWednesday ?? false) && !_isPremiumFormat;

  int get _standardPriceFromTheaterSize {
    switch (_theaterSize) {
      case 'Large': return 90000;
      case 'Small': return 50000;
      case 'Medium':
      default: return 70000;
    }
  }

  int get _vipPriceFromTheaterSize {
    switch (_theaterSize) {
      case 'Large': return 150000;
      case 'Small': return 90000;
      case 'Medium':
      default: return 120000;
    }
  }

  // Giá STD/VIP: khi có suất chiếu thật (showtimeId), dùng đúng giá
  // priceStandard/priceVip theater_manager đã cấu hình cho suất này làm giá
  // gốc - trước đây phần này bị bỏ qua hoàn toàn, giá luôn tính lại từ theater
  // size + định dạng phòng nên giá staff cấu hình không có tác dụng gì. Chỉ
  // khi KHÔNG có suất chiếu thật (luồng cũ/demo) mới dùng công thức theater
  // size + phụ thu 30% cho phòng cao cấp làm phương án dự phòng.
  int get _standardBasePrice {
    if (_wednesdayDiscountApplies) return 50000;
    if (_hasRealShowtime) return (widget.movieData['priceStandard'] as num?)?.toInt() ?? _standardPriceFromTheaterSize;
    return _isPremiumFormat ? (_standardPriceFromTheaterSize * 1.3).round() : _standardPriceFromTheaterSize;
  }

  int get _vipBasePrice {
    if (_wednesdayDiscountApplies) return 50000;
    if (_hasRealShowtime) return (widget.movieData['priceVip'] as num?)?.toInt() ?? _vipPriceFromTheaterSize;
    return _isPremiumFormat ? (_vipPriceFromTheaterSize * 1.3).round() : _vipPriceFromTheaterSize;
  }

  String _formatPrice(int price) =>
      '${price.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}đ';

  int _getSeatPrice(String seatId) {
    final row = seatId[0];

    final basePrice = _wednesdayDiscountApplies
        ? (_layout.sweetboxRowLabels.contains(row) ? 100000 : 50000)
        : seatBasePrice(seatId: seatId, layout: _layout, priceStandard: _standardBasePrice, priceVip: _vipBasePrice);

    if (_wednesdayDiscountApplies) return basePrice; // Ưu đãi Thứ 4: đồng giá, không cộng thêm phụ thu khác

    final surcharge = _surcharge;
    // Mức phụ thu cuối tuần giờ đến từ pricing_rules (PricingEngine) thay vì
    // hằng số 15000 cứng - fallback công thức cũ trả về đúng 15000 nên hành
    // vi không đổi khi chưa seed luật giá.
    final weekendSurcharge = surcharge?.weekendSurcharge ?? 0;
    final timeSurcharge = surcharge?.timeOfDaySurcharge ?? 0;

    final subtotal = basePrice + weekendSurcharge + timeSurcharge;

    // Dynamic pricing (F.5): phụ thu % suất bán chạy, cùng giá trị server
    // dùng khi trừ tiền (dynamicSurchargePercent trên document suất chiếu).
    final dynPercent = (widget.movieData['dynamicSurchargePercent'] as num?)?.toInt() ?? 0;
    return dynPercent > 0 ? (subtotal * (100 + dynPercent)) ~/ 100 : subtotal;
  }

  // Chọn/bỏ ghế giờ CHỈ là state cục bộ trên máy này - việc giữ ghế thật
  // (atomic, chặn người khác) xảy ra 1 lần duy nhất khi bấm thanh toán
  // (payment_service.dart gọi holdSeats() qua backend /seats/hold - Giai đoạn
  // C). Bỏ hẳn việc ghi 'temporary_locks' mỗi lần tap như trước: vừa không
  // atomic (2 người vẫn giữ trùng được), vừa spam write Firestore theo từng
  // cú chạm. Ghế người khác đang giữ/đã bán realtime đến từ stream
  // showtimes/{id}/seats trong build().
  void _onSeatTap(String seatId, bool isDouble, List<String> bookedSeats, Map<String, String> currentLocks) {
    if (bookedSeats.contains(seatId) || _layout.brokenSeats.contains(seatId)) return;

    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
    final lockedBy = currentLocks[seatId];
    if (lockedBy != null && lockedBy != uid) {
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
    setState(() {
      if (_selectedSeats.contains(seatId)) {
        _selectedSeats.remove(seatId);
        _totalPrice -= price;
      } else {
        _selectedSeats.add(seatId);
        _totalPrice += price;
      }
    });

    // Cảnh báo mềm "ghế lẻ" (F.1): lựa chọn hiện tại để lại 1 ghế trống kẹt
    // giữa - không chặn (tuỳ chính sách rạp), chỉ nhắc để khách tự cân nhắc.
    final orphans = findOrphanSeats(
      _layout,
      {...bookedSeats, ..._layout.brokenSeats, ...currentLocks.keys},
      _selectedSeats.toSet(),
    );
    if (orphans.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('💡 Lựa chọn này để lại ghế ${orphans.join(", ")} trống một mình - cân nhắc dịch sang 1 ghế để hàng ghế đẹp hơn nhé!'),
          backgroundColor: Colors.blueGrey,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // F.2: chọn nhanh cụm ghế đẹp nhất cho nhóm N người (chấm điểm
  // center/distance/continuity - xem seat_layout_helper.dart).
  void _applySuggestion(int groupSize, List<String> bookedSeats, Map<String, String> currentLocks) {
    final occupied = {...bookedSeats, ..._layout.brokenSeats, ...currentLocks.keys};
    final suggestion = suggestBestSeats(_layout, occupied, groupSize);
    if (suggestion == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không còn $groupSize ghế liền kề nào trống cho suất này.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }
    setState(() {
      _selectedSeats.clear();
      _selectedSeats.addAll(suggestion.seatIds);
      _totalPrice = suggestion.seatIds.fold(0, (sum, s) => sum + _getSeatPrice(s));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✨ Gợi ý cho nhóm $groupSize người: ${suggestion.seatIds.join(", ")}'),
        backgroundColor: Colors.teal,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // F.4: mô phỏng góc nhìn từ hàng ghế - bản vẽ MINH HOẠ (schematic, không
  // phải ảnh chụp thật từ rạp) giúp khách hình dung màn hình to/nhỏ thế nào
  // từ vị trí hàng ghế trước khi chọn. Khoảng cách/góc nhìn ước lượng theo
  // chuẩn thiết kế rạp thông dụng (hàng đầu cách màn hình ~6m, mỗi hàng cách
  // nhau ~1m, màn hình cao ~8m).
  void _showViewSimulation() {
    final rows = _layout.standardVipRowLabels;
    if (rows.isEmpty) return;
    String selectedRow = _selectedSeats.isNotEmpty ? _selectedSeats.first[0] : rows[rows.length ~/ 2];
    if (!rows.contains(selectedRow)) selectedRow = rows[rows.length ~/ 2];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16161F),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final rowIndex = rows.indexOf(selectedRow);
          final distanceM = 6 + rowIndex; // hàng A ~6m, mỗi hàng lùi ~1m
          final viewAngleDeg = (2 * (180 / 3.14159) * math.atan(4.0 / distanceM)).round(); // màn cao 8m
          final position = rowIndex < rows.length / 3
              ? 'gần màn hình - hình ảnh choáng ngợp, hợp phim hành động'
              : rowIndex < rows.length * 2 / 3
                  ? 'khoảng giữa - cân bằng đẹp giữa hình ảnh và âm thanh'
                  : 'phía sau - bao quát toàn màn hình, đỡ mỏi cổ';
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('GÓC NHÌN TỪ HÀNG GHẾ (minh hoạ)',
                    style: TextStyle(color: Colors.indigoAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final row in rows)
                      GestureDetector(
                        onTap: () => setSheetState(() => selectedRow = row),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: row == selectedRow ? Colors.indigoAccent : const Color(0xFF222232),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(row,
                              style: TextStyle(
                                  color: row == selectedRow ? Colors.white : Colors.white54,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                // Bản vẽ phối cảnh: màn hình thu nhỏ dần khi hàng ghế lùi xa.
                SizedBox(
                  height: 140,
                  width: double.infinity,
                  child: CustomPaint(painter: _ViewSimulationPainter(rowIndex: rowIndex, totalRows: rows.length)),
                ),
                const SizedBox(height: 12),
                Text('Hàng $selectedRow • cách màn hình ~${distanceM}m • góc nhìn dọc ~$viewAngleDeg°',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Vị trí $position.',
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
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

        // Trạng thái ghế realtime từ subcollection showtimes/{id}/seats
        // (ShowtimeSeat - Giai đoạn C): HOLDING của người khác hiện "đang
        // giữ", BOOKED/BLOCKED/UNAVAILABLE gộp vào danh sách không chọn được.
        // Suất chiếu cũ (không có showtimeId thật hoặc chưa sinh seats) thì
        // stream rỗng - chỉ còn lớp check vé 'tickets' phía trên hoạt động,
        // đúng hành vi cũ trước Giai đoạn C.
        final String? showtimeId = widget.movieData['showtimeId'] as String?;
        return StreamBuilder<QuerySnapshot>(
          stream: showtimeId != null
              ? FirebaseFirestore.instance
                  .collection('showtimes').doc(showtimeId).collection('seats')
                  .snapshots()
              : const Stream<QuerySnapshot>.empty(),
          builder: (context, seatSnapshot) {
            final now = DateTime.now();
            final Map<String, String> currentLocks = {}; // seatId -> heldBy (uid)
            if (seatSnapshot.hasData) {
              for (var doc in seatSnapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final status = data['status'] as String?;
                if (status == 'HOLDING') {
                  final heldUntil = (data['heldUntil'] as Timestamp?)?.toDate();
                  if (heldUntil != null && heldUntil.isAfter(now)) {
                    currentLocks[doc.id] = data['heldBy'] as String? ?? '';
                  }
                } else if (status == 'BOOKED' || status == 'BLOCKED' || status == 'UNAVAILABLE') {
                  if (!bookedSeats.contains(doc.id)) bookedSeats.add(doc.id);
                }
              }
            }

            final userEmail = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';

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
                      (widget.movieData['roomFormat'] != null
                              ? '$theater  |  $date  |  Suất: $time  •  ${widget.movieData['roomFormat']}'
                              : '$theater  |  $date  |  Suất: $time') +
                          // F.5: báo rõ phụ thu suất bán chạy TRƯỚC khi khách
                          // chọn ghế - giá hiển thị từng ghế đã bao gồm sẵn.
                          (((widget.movieData['dynamicSurchargePercent'] as num?)?.toInt() ?? 0) > 0
                              ? '  •  🔥 Suất bán chạy +${widget.movieData['dynamicSurchargePercent']}%'
                              : ''),
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
                            _buildNoteItem('Ghế Recliner (${_formatPrice(_vipBasePrice)})', const Color(0xFF322A1E))
                          else if (_isLamour)
                            _buildNoteItem("Ghế đôi L'amour (${_formatPrice(_wednesdayDiscountApplies ? 100000 : (_vipBasePrice * 2))})", const Color(0xFF3A1A1A))
                          else if (_isMotionSeat)
                            _buildNoteItem('Ghế Motion 4DX (${_formatPrice(_standardBasePrice)})', const Color(0xFF15291A))
                          else ...[
                            if (_layout.standardRows > 0) _buildNoteItem('Thường (${_formatPrice(_standardBasePrice)})', const Color(0xFF222232)),
                            if (_layout.vipRows > 0) _buildNoteItem('VIP (${_formatPrice(_vipBasePrice)})', const Color(0xFF322A1E)),
                            if (_layout.sweetboxRows > 0) _buildNoteItem('Sweetbox (${_formatPrice(_wednesdayDiscountApplies ? 100000 : (_vipBasePrice * 2))})', const Color(0xFF3A2232)),
                          ],
                          if (_layout.wheelchairSeats.isNotEmpty)
                            _buildNoteItem('Ghế xe lăn', Colors.blueAccent.withValues(alpha: 0.25)),
                          _buildNoteItem('Đang chọn', Colors.amber),
                          _buildNoteItem('Đang giữ (5p)', Colors.grey.withValues(alpha: 0.3)),
                          _buildNoteItem('Đã bán', Colors.redAccent),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),

                  // F.2: gợi ý cụm ghế đẹp nhất theo cỡ nhóm + F.4: mô phỏng
                  // góc nhìn từ hàng ghế. Chỉ hiện cho phòng có hàng ghế đơn
                  // (phòng toàn ghế đôi chọn theo cặp, không cần gợi ý cụm).
                  if (_layout.standardVipRowLabels.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          const Text('✨ Gợi ý ghế:', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          for (final n in [1, 2, 3, 4]) ...[
                            GestureDetector(
                              onTap: () => _applySuggestion(n, bookedSeats, currentLocks),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.teal.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.teal.withValues(alpha: 0.4)),
                                ),
                                child: Text('$n người', style: const TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                          GestureDetector(
                            onTap: _showViewSimulation,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.indigo.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.indigoAccent.withValues(alpha: 0.4)),
                              ),
                              child: const Text('👁 Góc nhìn', style: TextStyle(color: Colors.indigoAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),

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
                          child: SeatGridView(
                            layout: _layout,
                            selectedSeats: _selectedSeats.toSet(),
                            bookedSeats: {...bookedSeats, ..._layout.brokenSeats},
                            lockedBySeatId: currentLocks,
                            currentUserKey: userEmail,
                            wheelchairSeats: _layout.wheelchairSeats,
                            onSeatTap: (seatId) => _onSeatTap(seatId, false, bookedSeats, currentLocks),
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
                        '${_isGoldClass
                                ? 'Phân tích giá vé: Ghế Recliner: ${_formatPrice(_vipBasePrice)}. '
                                : _isLamour
                                    ? "Phân tích giá vé: Ghế đôi L'amour: ${_formatPrice(_wednesdayDiscountApplies ? 100000 : (_vipBasePrice * 2))}. "
                                    : 'Phân tích giá vé: Ghế Thường: ${_formatPrice(_standardBasePrice)}, VIP: ${_formatPrice(_vipBasePrice)}, Sweetbox: ${_formatPrice(_wednesdayDiscountApplies ? 100000 : (_vipBasePrice * 2))}. '}${(_surcharge?.isWeekend ?? false) ? "Cuối tuần (+${_formatPrice(_surcharge?.weekendSurcharge ?? 0)}/ghế)" : "Ngày thường (+0k)"} | ${widget.movieData['sessionType'] ?? 'Standard'} (${(_surcharge?.timeOfDaySurcharge ?? 0) > 0 ? '+' : ''}${_formatPrice(_surcharge?.timeOfDaySurcharge ?? 0)}/ghế)',
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

// Bản vẽ phối cảnh minh hoạ cho _showViewSimulation (F.4): màn hình cong +
// vài hàng ghế phía trước, kích thước màn hình thu nhỏ dần theo hàng ghế
// càng lùi xa - KHÔNG phải ảnh thật từ rạp, chỉ giúp hình dung tương đối.
class _ViewSimulationPainter extends CustomPainter {
  final int rowIndex;
  final int totalRows;
  const _ViewSimulationPainter({required this.rowIndex, required this.totalRows});

  @override
  void paint(Canvas canvas, Size size) {
    // Tỷ lệ màn hình theo khoảng cách: hàng đầu nhìn màn hình chiếm ~95%
    // chiều rộng khung vẽ, hàng cuối ~45%.
    final t = totalRows <= 1 ? 0.0 : rowIndex / (totalRows - 1);
    final screenWidth = size.width * (0.95 - 0.5 * t);
    final screenHeight = size.height * (0.55 - 0.25 * t);
    final left = (size.width - screenWidth) / 2;
    final top = size.height * 0.08 + size.height * 0.12 * t;

    // Màn hình (cong nhẹ) + ánh sáng hắt.
    final screenPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.amber.withValues(alpha: 0.9), Colors.amber.withValues(alpha: 0.4)],
      ).createShader(Rect.fromLTWH(left, top, screenWidth, screenHeight));
    final screenPath = Path()
      ..moveTo(left, top + screenHeight * 0.15)
      ..quadraticBezierTo(left + screenWidth / 2, top - screenHeight * 0.1, left + screenWidth, top + screenHeight * 0.15)
      ..lineTo(left + screenWidth, top + screenHeight)
      ..quadraticBezierTo(left + screenWidth / 2, top + screenHeight * 0.85, left, top + screenHeight)
      ..close();
    canvas.drawPath(screenPath, screenPaint);

    // Vài hàng ghế phía trước (bóng đen) để tạo chiều sâu - số hàng thấy
    // được tăng dần khi ngồi càng xa.
    final headPaint = Paint()..color = const Color(0xFF222232);
    final headsRows = (1 + 2 * t).round();
    for (var r = 0; r < headsRows; r++) {
      final y = size.height * (0.78 + 0.09 * r);
      final headCount = 6 + r * 2;
      for (var h = 0; h < headCount; h++) {
        final x = size.width * (h + 0.5) / headCount;
        canvas.drawCircle(Offset(x, y), size.height * 0.045, headPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_ViewSimulationPainter old) => old.rowIndex != rowIndex || old.totalRows != totalRows;
}
