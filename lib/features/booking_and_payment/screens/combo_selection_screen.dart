import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../auth/screens/login_screen.dart';
import 'payment_screen.dart';

/// Combo áp dụng cho mọi rạp (không gắn riêng 1 cụm rạp cụ thể) - dùng làm
/// giá trị field 'theaterName' trong Firestore collection 'combos'.
const String kGlobalComboScope = 'ALL';

class ComboSelectionScreen extends StatefulWidget {
  final Map<String, dynamic> movieData;
  final List<String> selectedSeats;
  final int ticketPrice;
  final DateTime? expiryTime;
  final String? preSelectedComboId;

  const ComboSelectionScreen({
    super.key,
    required this.movieData,
    required this.selectedSeats,
    required this.ticketPrice,
    this.expiryTime,
    this.preSelectedComboId,
  });

  @override
  State<ComboSelectionScreen> createState() => _ComboSelectionScreenState();
}

class _ComboSelectionScreenState extends State<ComboSelectionScreen> {
  Timer? _timer;
  int _secondsRemaining = 0;

  // Nạp từ Firestore collection 'combos': gồm combo dùng chung cho mọi rạp
  // (theaterName == kGlobalComboScope) + combo riêng của rạp đang đặt vé
  // (theaterName == tên rạp), để đa dạng lựa chọn theo từng cụm rạp.
  List<Map<String, dynamic>> _combos = [];
  bool _loadingCombos = true;

  @override
  void initState() {
    super.initState();
    _loadCombos();

    // Xử lý đếm ngược thời gian
    if (widget.expiryTime != null) {
      _secondsRemaining = widget.expiryTime!
          .difference(DateTime.now())
          .inSeconds;
      if (_secondsRemaining > 0) {
        _startTimer();
      } else {
        _secondsRemaining = 0;
      }
    }
  }

  Future<void> _loadCombos() async {
    final theater = widget.movieData['selectedTheater'] as String?;
    final scopes = {kGlobalComboScope, ?theater}.toList();
    try {
      final snap = await FirebaseFirestore.instance
          .collection('combos')
          .where('theaterName', whereIn: scopes)
          .get();
      final loaded =
          snap.docs.map((d) {
            final data = d.data();
            return {
              'id': d.id,
              'title': data['title'] ?? '',
              'desc': data['desc'] ?? '',
              'price': (data['price'] as num?)?.toInt() ?? 0,
              'quantity': (widget.preSelectedComboId != null && 
                          (widget.preSelectedComboId == d.id || 
                           (data['title'] ?? '').toString().toLowerCase().contains(widget.preSelectedComboId!.toLowerCase()))) ? 1 : 0,
              'imageAsset': data['imageAsset'] as String?,
              'imageUrl': data['imageUrl'] as String?,
            };
          }).toList()..sort(
            (a, b) => (a['title'] as String).compareTo(b['title'] as String),
          );
      if (mounted) {
        setState(() {
          _combos = loaded;
          _loadingCombos = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCombos = false);
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        if (mounted) {
          setState(() {
            _secondsRemaining--;
          });
        }
      } else {
        _timer?.cancel();
        _handleTimeout();
      }
    });
  }

  void _handleTimeout() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0A0A0A),
          title: const Text(
            'GIAO DỊCH HẾT HẠN',
            style: TextStyle(color: Colors.amber),
          ),
          content: const Text(
            'Thời gian giữ ghế đã hết. Vui lòng đặt lại vé.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              child: const Text(
                'QUAY VỀ TRANG CHỦ',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int get _comboTotalAmount {
    int total = 0;
    for (var combo in _combos) {
      total += (combo['price'] as int) * (combo['quantity'] as int);
    }
    return total;
  }

  String _formatTime(int seconds) {
    int m = seconds ~/ 60;
    int s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _processToPayment(int totalAmount) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: const Color(0xFF0A0A0A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.lock_outline, color: Colors.amber, size: 22),
                SizedBox(width: 8),
                Text(
                  'YÊU CẦU ĐĂNG NHẬP',
                  style: TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            content: const Text(
              'Bạn cần đăng nhập tài khoản Stella Cinema để tiến hành thanh toán và nhận vé điện tử.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'HỦY',
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context, false);
                  final success = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const LoginScreen(returnOnSuccess: true),
                    ),
                  );
                  if (success == true && mounted) {
                    _navigateToPayment(totalAmount);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'ĐĂNG NHẬP / ĐĂNG KÝ',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          );
        },
      );
    } else {
      _navigateToPayment(totalAmount);
    }
  }

  void _navigateToPayment(int totalAmount) {
    final List<Map<String, dynamic>> selectedCombos = _combos
        .where((c) => (c['quantity'] as int) > 0)
        .map(
          (c) => {
            'id': c['id'],
            'title': c['title'],
            'quantity': c['quantity'],
            'price': c['price'],
          },
        )
        .toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentScreen(
          movieData: widget.movieData,
          selectedSeats: widget.selectedSeats,
          totalPrice: totalAmount,
          combos: selectedCombos,
          expiryTime: widget.expiryTime,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int totalAmount = widget.ticketPrice + _comboTotalAmount;
    final formatTicketPrice = widget.ticketPrice.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
    final formatComboPrice = _comboTotalAmount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
    final formatTotalAmount = totalAmount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.timer_outlined, color: Colors.amber, size: 20),
            const SizedBox(width: 8),
            Text(
              'Thời gian giữ ghế: ${_formatTime(_secondsRemaining)}',
              style: const TextStyle(
                color: Colors.amber,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Banner quảng cáo
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF121212),
            child: const Row(
              children: [
                Icon(Icons.fastfood_rounded, color: Colors.amber, size: 18),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Đăng ký trực tuyến để nhận ưu đãi lên đến 15% so với mua trực tiếp tại quầy!',
                    style: TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // DANH SÁCH BẮP NƯỚC
          Expanded(
            child: _loadingCombos
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.amber),
                  )
                : _combos.isEmpty
                ? const Center(
                    child: Text(
                      'Rạp này chưa có combo bắp nước.',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: _combos.length,
                    itemBuilder: (context, index) {
                      final combo = _combos[index];
                      final String title = combo['title'];
                      final String desc = combo['desc'];
                      final int price = combo['price'];
                      final int qty = combo['quantity'];
                      final String? imageAsset = combo['imageAsset'] as String?;
                      final String? imageUrl = combo['imageUrl'] as String?;
                      final formatPrice = price.toString().replaceAllMapped(
                        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                        (Match m) => '${m[1]}.',
                      );

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A0A0A),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Hình ảnh minh họa Combo - ưu tiên ảnh mạng (imageUrl,
                            // dùng cho combo riêng theo rạp), rồi mới tới asset cục bộ.
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: (imageUrl != null && imageUrl.isNotEmpty)
                                  ? Image.network(
                                      imageUrl,
                                      width: 80,
                                      height: 80,
                                      fit: BoxFit.cover,
                                      loadingBuilder:
                                          (
                                            context,
                                            child,
                                            progress,
                                          ) => progress == null
                                          ? child
                                          : Container(
                                              width: 80,
                                              height: 80,
                                              color: Colors.white10,
                                              child: const Center(
                                                child: SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                        color: Colors.amber,
                                                        strokeWidth: 2,
                                                      ),
                                                ),
                                              ),
                                            ),
                                      errorBuilder:
                                          (
                                            context,
                                            error,
                                            stackTrace,
                                          ) => Container(
                                            width: 80,
                                            height: 80,
                                            color: Colors.white10,
                                            child: const Icon(
                                              Icons.image_not_supported_rounded,
                                              color: Colors.white30,
                                            ),
                                          ),
                                    )
                                  : Image.asset(
                                      imageAsset ??
                                          'assets/images/combo_premium.png',
                                      width: 80,
                                      height: 80,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (
                                            context,
                                            error,
                                            stackTrace,
                                          ) => Container(
                                            width: 80,
                                            height: 80,
                                            color: Colors.white10,
                                            child: const Icon(
                                              Icons.image_not_supported_rounded,
                                              color: Colors.white30,
                                            ),
                                          ),
                                    ),
                            ),
                            const SizedBox(width: 12),

                            // Thông tin chi tiết
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    desc,
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 11,
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  // Hàng chứa Giá và Nút cộng trừ
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '$formatPrice đ',
                                        style: const TextStyle(
                                          color: Colors.amber,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),

                                      // Nút thao tác DỄ BẤM hơn
                                      Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.05,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              padding: const EdgeInsets.all(8),
                                              constraints:
                                                  const BoxConstraints(),
                                              onPressed: qty == 0
                                                  ? null
                                                  : () {
                                                      setState(() {
                                                        combo['quantity'] =
                                                            qty - 1;
                                                      });
                                                    },
                                              icon: Icon(
                                                Icons.remove_rounded,
                                                color: qty == 0
                                                    ? Colors.white24
                                                    : Colors.white,
                                                size: 20,
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                  ),
                                              constraints: const BoxConstraints(
                                                minWidth: 24,
                                              ),
                                              alignment: Alignment.center,
                                              child: AnimatedSwitcher(
                                                duration: const Duration(
                                                  milliseconds: 200,
                                                ),
                                                transitionBuilder:
                                                    (
                                                      Widget child,
                                                      Animation<double>
                                                      animation,
                                                    ) {
                                                      return ScaleTransition(
                                                        scale: animation,
                                                        child: child,
                                                      );
                                                    },
                                                child: Text(
                                                  '$qty',
                                                  key: ValueKey<int>(qty),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              padding: const EdgeInsets.all(8),
                                              constraints:
                                                  const BoxConstraints(),
                                              onPressed: () {
                                                setState(() {
                                                  combo['quantity'] = qty + 1;
                                                });
                                              },
                                              icon: const Icon(
                                                Icons.add_rounded,
                                                color: Colors.amber,
                                                size: 20,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // TỔNG HỢP CHI PHÍ
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFF0A0A0A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Tiền vé xem phim:',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      Text(
                        '$formatTicketPrice đ',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Tiền bắp nước (F&B):',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      Text(
                        '$formatComboPrice đ',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tổng số tiền:',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '(Đã bao gồm VAT)',
                            style: TextStyle(color: Colors.grey, fontSize: 10),
                          ),
                        ],
                      ),
                      Text(
                        '$formatTotalAmount đ',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => _processToPayment(totalAmount),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'TIẾP TỤC THANH TOÁN',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
