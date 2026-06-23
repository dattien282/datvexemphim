import 'package:flutter/material.dart';
import 'payment_screen.dart';

class ComboSelectionScreen extends StatefulWidget {
  final Map<String, dynamic> movieData;
  final List<String> selectedSeats;
  final int ticketPrice;

  const ComboSelectionScreen({
    super.key,
    required this.movieData,
    required this.selectedSeats,
    required this.ticketPrice,
  });

  @override
  State<ComboSelectionScreen> createState() => _ComboSelectionScreenState();
}

class _ComboSelectionScreenState extends State<ComboSelectionScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'Tất cả';

  final List<Map<String, dynamic>> _combos = [
    {
      'id': 'solo',
      'title': 'Combo Solo',
      'desc': '1 Bắp ngọt vừa + 1 Nước ngọt Pepsi cỡ lớn. Thích hợp cho một người xem phim.',
      'price': 75000,
      'quantity': 0,
      'icon': Icons.local_play_rounded,
      'category': 'Combo',
    },
    {
      'id': 'couple',
      'title': 'Combo Couple',
      'desc': '1 Bắp lớn + 2 Nước ngọt Pepsi cỡ lớn. Phù hợp cho cặp đôi hẹn hò xem phim.',
      'price': 110000,
      'quantity': 0,
      'icon': Icons.people_alt_rounded,
      'category': 'Combo',
    },
    {
      'id': 'premium',
      'title': 'Combo Stella Premium',
      'desc': '2 Bắp lớn + 3 Nước ngọt lớn + 1 phần Quà lưu niệm độc quyền từ Stella.',
      'price': 160000,
      'quantity': 0,
      'icon': Icons.card_giftcard_rounded,
      'category': 'Combo',
    },
    {
      'id': 'popcorn_sweet',
      'title': 'Bắp ngọt Stella',
      'desc': 'Bắp rang bơ truyền thống thơm ngon vị ngọt dịu nhẹ.',
      'price': 35000,
      'quantity': 0,
      'icon': Icons.lunch_dining_rounded,
      'category': 'Đồ ăn',
    },
    {
      'id': 'popcorn_cheese',
      'title': 'Bắp phô mai đặc biệt',
      'desc': 'Bắp rang bơ phủ bột phô mai béo ngậy mặn ngọt đậm đà.',
      'price': 45000,
      'quantity': 0,
      'icon': Icons.bakery_dining_rounded,
      'category': 'Đồ ăn',
    },
    {
      'id': 'pepsi',
      'title': 'Nước ngọt Pepsi lớn',
      'desc': 'Nước ngọt Pepsi có ga mát lạnh sảng khoái cỡ lớn.',
      'price': 30000,
      'quantity': 0,
      'icon': Icons.local_drink_rounded,
      'category': 'Nước ngọt',
    },
    {
      'id': 'water',
      'title': 'Nước tinh khiết Stella',
      'desc': 'Nước suối tinh khiết đóng chai Stella thanh mát mát lạnh.',
      'price': 15000,
      'quantity': 0,
      'icon': Icons.water_drop_rounded,
      'category': 'Nước ngọt',
    },
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int get _comboTotalAmount {
    int total = 0;
    for (var combo in _combos) {
      total += (combo['price'] as int) * (combo['quantity'] as int);
    }
    return total;
  }

  List<Map<String, dynamic>> get _filteredCombos {
    final query = _searchQuery.toLowerCase();
    return _combos.where((item) {
      final matchesQuery = item['title'].toString().toLowerCase().contains(query) ||
          item['desc'].toString().toLowerCase().contains(query);
      final matchesCategory = _selectedCategory == 'Tất cả' || item['category'] == _selectedCategory;
      return matchesQuery && matchesCategory;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final int totalAmount = widget.ticketPrice + _comboTotalAmount;
    final formatTicketPrice = widget.ticketPrice.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');
    final formatComboPrice = _comboTotalAmount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');
    final formatTotalAmount = totalAmount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');

    final categories = ['Tất cả', 'Combo', 'Đồ ăn', 'Nước ngọt'];

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text('CHỌN BẮP NƯỚC (F&B)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Banner quảng cáo
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF1E1E2A),
            child: const Row(
              children: [
                Icon(Icons.fastfood_rounded, color: Colors.amber, size: 18),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Đăng ký trực tuyến để nhận ưu đãi lên đến 15% so với mua trực tiếp tại quầy!',
                    style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),

          // Ô TÌM KIẾM
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Tìm kiếm bắp rang, nước ngọt, combo...',
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white30, size: 18),
                filled: true,
                fillColor: const Color(0xFF16161F),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // TABS PHÂN LOẠI
          Container(
            height: 38,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];
                final isSelected = _selectedCategory == category;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedCategory = category;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.amber : const Color(0xFF16161F),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? Colors.amber : Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      category,
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white70,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // DANH SÁCH SẢN PHẨM LỌC ĐỘNG
          Expanded(
            child: _filteredCombos.isEmpty
                ? const Center(
                    child: Text(
                      'Không tìm thấy sản phẩm bắp nước phù hợp.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _filteredCombos.length,
                    itemBuilder: (context, index) {
                      final combo = _filteredCombos[index];
                      final String title = combo['title'];
                      final String desc = combo['desc'];
                      final int price = combo['price'];
                      final int qty = combo['quantity'];
                      final IconData iconData = combo['icon'];
                      final formatPrice = price.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16161F),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(iconData, color: Colors.amber, size: 24),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    desc,
                                    style: const TextStyle(color: Colors.grey, fontSize: 10, height: 1.3),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '$formatPrice đ',
                                    style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),

                            // BỘ ĐIỀU CHỈNH SỐ LƯỢNG VỚI HIỆU ỨNG MICRO-ANIMATION
                            Column(
                              children: [
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    setState(() {
                                      combo['quantity'] = qty + 1;
                                    });
                                  },
                                  icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.amber, size: 22),
                                ),
                                const SizedBox(height: 4),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  transitionBuilder: (Widget child, Animation<double> animation) {
                                    return ScaleTransition(scale: animation, child: child);
                                  },
                                  child: Text(
                                    '$qty',
                                    key: ValueKey<int>(qty),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: qty == 0
                                      ? null
                                      : () {
                                          setState(() {
                                            combo['quantity'] = qty - 1;
                                          });
                                        },
                                  icon: Icon(
                                    Icons.remove_circle_outline_rounded,
                                    color: qty == 0 ? Colors.white24 : Colors.amber,
                                    size: 22,
                                  ),
                                ),
                              ],
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
              color: Color(0xFF16161F),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Tiền vé xem phim:', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text('$formatTicketPrice đ', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Tiền bắp nước (F&B):', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text('$formatComboPrice đ', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tổng số tiền:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          SizedBox(height: 2),
                          Text('(Đã bao gồm VAT)', style: TextStyle(color: Colors.grey, fontSize: 10)),
                        ],
                      ),
                      Text(
                        '$formatTotalAmount đ',
                        style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        // Lọc sản phẩm đã chọn thực tế
                        final List<Map<String, dynamic>> selectedCombos = _combos
                            .where((c) => (c['quantity'] as int) > 0)
                            .map((c) => {
                                  'title': c['title'],
                                  'quantity': c['quantity'],
                                  'price': c['price'],
                                })
                            .toList();

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PaymentScreen(
                              movieData: widget.movieData,
                              selectedSeats: widget.selectedSeats,
                              totalPrice: totalAmount,
                              combos: selectedCombos,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text(
                        'TIẾP TỤC THANH TOÁN',
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
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
