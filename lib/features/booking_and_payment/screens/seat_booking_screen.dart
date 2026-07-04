import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theater_manager/screens/room_management_screen.dart' show kPremiumRoomFormats;
import '../../theater_manager/widgets/seat_grid_widget.dart';
import '../../../models/room_layout.dart';
import '../../../models/showtime.dart';
import '../services/pricing_service.dart';
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

      if (roomName == null) return;

      // 2. Fetch room layout
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

  ShowtimeSurcharge? get _surcharge {
    final showAt = _showAtDateTime;
    if (showAt == null) return null;
    return ShowtimeSurcharge.fromShowAt(showAt, sessionType: widget.movieData['sessionType'] as String?);
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
    final weekendSurcharge = (surcharge?.isWeekend ?? false) ? 15000 : 0;
    final timeSurcharge = surcharge?.timeOfDaySurcharge ?? 0;

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
    if (bookedSeats.contains(seatId) || _layout.brokenSeats.contains(seatId)) return; // REAL-TIME LOCK: Đã bán/hỏng thì cấm chạm

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
                } else {
                  // Dọn dẹp khóa ghế đã hết hạn (best-effort) - trước đây chỉ
                  // bị ẩn ở client (lọc theo expiresAt), document vẫn tồn tại
                  // mãi trong Firestore không ai xóa, khiến temporary_locks
                  // phình to vô ích theo thời gian.
                  doc.reference.delete().catchError((_) {});
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
                            _buildNoteItem("Ghế đôi L'amour (${_formatPrice(_wednesdayDiscountApplies ? 100000 : (_vipBasePrice * 2))})", const Color(0xFF3A1A1A))
                          else ...[
                            if (_layout.standardRows > 0) _buildNoteItem('Thường (${_formatPrice(_standardBasePrice)})', const Color(0xFF222232)),
                            if (_layout.vipRows > 0) _buildNoteItem('VIP (${_formatPrice(_vipBasePrice)})', const Color(0xFF322A1E)),
                            if (_layout.sweetboxRows > 0) _buildNoteItem('Sweetbox (${_formatPrice(_wednesdayDiscountApplies ? 100000 : (_vipBasePrice * 2))})', const Color(0xFF3A2232)),
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
                          child: SeatGridView(
                            layout: _layout,
                            selectedSeats: _selectedSeats.toSet(),
                            bookedSeats: {...bookedSeats, ..._layout.brokenSeats},
                            lockedBySeatId: currentLocks,
                            currentUserKey: userEmail,
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
                        (_isGoldClass
                                ? 'Phân tích giá vé: Ghế Gold: ${_formatPrice(_vipBasePrice)}. '
                                : _isLamour
                                    ? "Phân tích giá vé: Ghế đôi L'amour: ${_formatPrice(_wednesdayDiscountApplies ? 100000 : (_vipBasePrice * 2))}. "
                                    : 'Phân tích giá vé: Ghế Thường: ${_formatPrice(_standardBasePrice)}, VIP: ${_formatPrice(_vipBasePrice)}, Sweetbox: ${_formatPrice(_wednesdayDiscountApplies ? 100000 : (_vipBasePrice * 2))}. ') +
                        '${(_surcharge?.isWeekend ?? false) ? "Cuối tuần (+15k/ghế)" : "Ngày thường (+0k)"} '
                        '| ${widget.movieData['sessionType'] ?? 'Standard'} (${(_surcharge?.timeOfDaySurcharge ?? 0) > 0 ? '+' : ''}${_formatPrice(_surcharge?.timeOfDaySurcharge ?? 0)}/ghế)',
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
