import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  int _getSeatPrice(String seatId) {
    final row = seatId[0];
    int basePrice = 90000;
    if (row == 'I' || row == 'J') {
      basePrice = 200000; // Sweetbox đôi
    } else if (['D', 'E', 'F', 'G', 'H'].contains(row)) {
      basePrice = 120000; // VIP đơn
    } else {
      basePrice = 90000; // Thường đơn
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
    if (bookedSeats.contains(seatId)) return; // REAL-TIME LOCK: Đã bán thì cấm chạm

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
          .where('showtime', isEqualTo: '$theater | $date | $time')
          .snapshots(),
      builder: (context, ticketSnapshot) {
        List<String> bookedSeats = [];
        if (ticketSnapshot.hasData) {
          for (var doc in ticketSnapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final String paymentStatus = data['payment_status'] ?? 'COMPLETED';
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
              backgroundColor: const Color(0xFF0F0F13),
              appBar: AppBar(
                backgroundColor: const Color(0xFF16161F),
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
                    color: const Color(0xFF1E1E2A),
                    child: Text(
                      '🎬 $theater  |  📅 $date  |  ⏰ Suất: $time',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w500, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 15),

                  // CHÚ THÍCH TRẠNG THÁI GHẾ NÂNG CẤP
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        _buildNoteItem('Thường (90k)', const Color(0xFF222232)),
                        _buildNoteItem('VIP (120k)', const Color(0xFF322A1E)),
                        _buildNoteItem('Sweetbox (200k)', const Color(0xFF3A2232)),
                        _buildNoteItem('Đang giữ (5p)', Colors.orangeAccent),
                        _buildNoteItem('Đang chọn', Colors.amber),
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
                              for (var row in ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H']) ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(width: 20, alignment: Alignment.center, child: Text(row, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12))),
                                    ...List.generate(10, (index) {
                                      final seatId = '$row${index + 1}';
                                      final isSelected = _selectedSeats.contains(seatId);
                                      final isBooked = bookedSeats.contains(seatId);
                                      final lockedBy = currentLocks[seatId];
                                      final isLockedByOthers = lockedBy != null && lockedBy != userEmail;
                                      final isVIP = ['D', 'E', 'F', 'G', 'H'].contains(row);

                                      Color seatColor = const Color(0xFF222232);
                                      Color borderColor = Colors.white.withValues(alpha: 0.05);
                                      if (isBooked) {
                                        seatColor = Colors.redAccent.withValues(alpha: 0.3);
                                        borderColor = Colors.redAccent;
                                      } else if (isLockedByOthers) {
                                        seatColor = Colors.orangeAccent.withValues(alpha: 0.15);
                                        borderColor = Colors.orangeAccent.withValues(alpha: 0.5);
                                      } else if (isSelected) {
                                        seatColor = isVIP ? Colors.orangeAccent : Colors.amber;
                                        borderColor = Colors.white;
                                      } else if (isVIP) {
                                        seatColor = const Color(0xFF322A1E);
                                        borderColor = Colors.orangeAccent.withValues(alpha: 0.2);
                                      }

                                      return GestureDetector(
                                        onTap: () => _onSeatTap(seatId, false, bookedSeats, currentLocks),
                                        child: Container(
                                          margin: const EdgeInsets.all(3),
                                          width: 28, height: 28,
                                          decoration: BoxDecoration(
                                            color: seatColor,
                                            borderRadius: BorderRadius.circular(5),
                                            border: Border.all(color: borderColor),
                                          ),
                                          alignment: Alignment.center,
                                          child: isLockedByOthers
                                              ? const Icon(Icons.hourglass_empty_rounded, color: Colors.orangeAccent, size: 12)
                                              : Text(
                                                  '${index + 1}',
                                                  style: TextStyle(
                                                    color: isBooked
                                                        ? Colors.redAccent
                                                        : (isSelected
                                                            ? Colors.black
                                                            : (isVIP ? Colors.orangeAccent : Colors.white70)),
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 15),
                              const Text('HÀNG GHẾ ĐÔI SWEETBOX PREMIUM', style: TextStyle(color: Colors.pinkAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              for (var row in ['I', 'J']) ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(width: 20, alignment: Alignment.center, child: Text(row, style: const TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold, fontSize: 12))),
                                    ...List.generate(5, (index) {
                                      final seatId = '$row${index * 2 + 1}-$row${index * 2 + 2}';
                                      final isSelected = _selectedSeats.contains(seatId);
                                      final isBooked = bookedSeats.contains(seatId);
                                      final lockedBy = currentLocks[seatId];
                                      final isLockedByOthers = lockedBy != null && lockedBy != userEmail;

                                      Color sweetColor = const Color(0xFF3A2232);
                                      Color sweetBorder = Colors.pinkAccent.withValues(alpha: 0.2);
                                      if (isBooked) {
                                        sweetColor = Colors.redAccent.withValues(alpha: 0.2);
                                        sweetBorder = Colors.redAccent;
                                      } else if (isLockedByOthers) {
                                        sweetColor = Colors.orangeAccent.withValues(alpha: 0.15);
                                        sweetBorder = Colors.orangeAccent.withValues(alpha: 0.5);
                                      } else if (isSelected) {
                                        sweetColor = Colors.pinkAccent;
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
                                              ? const Icon(Icons.hourglass_empty_rounded, color: Colors.orangeAccent, size: 14)
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
                      color: const Color(0xFF16161F).withValues(alpha: 0.8),
                      child: Text(
                        'Phân tích giá vé: Ghế Thường: 90k, VIP: 120k, Sweetbox: 200k. '
                        '${_isWeekend() ? "Cuối tuần (+15k/ghế)" : "Ngày thường (+0k)"} '
                        '${_getTimeSurcharge() < 0 ? "| Suất sớm (-10k/ghế)" : (_getTimeSurcharge() > 0 ? "| Suất khuya (+10k/ghế)" : "| Suất thường (+0k)")}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white38, fontSize: 10, fontStyle: FontStyle.italic),
                      ),
                    ),

                  // BOTTOM SUMMARY BAR
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(color: Color(0xFF16161F), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ComboSelectionScreen(
                                    movieData: widget.movieData,
                                    selectedSeats: _selectedSeats,
                                    ticketPrice: _totalPrice,
                                  ),
                                ),
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