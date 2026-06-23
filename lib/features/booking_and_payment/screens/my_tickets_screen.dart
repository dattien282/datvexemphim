import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class MyTicketsScreen extends StatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  State<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends State<MyTicketsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showCancelTicketDialog(BuildContext context, String ticketId, String title) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF16161F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 22),
              SizedBox(width: 8),
              Text('XÁC NHẬN HỦY VÉ', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          content: Text(
            'Bạn có chắc chắn muốn hủy vé bộ phim "$title" không? Hệ thống sẽ tự động hoàn tiền và gửi thông báo xác nhận về hộp thư của bạn.',
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('QUAY LẠI', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đang xử lý hoàn vé và cập nhật hệ thống thông báo...')),
                );

                try {
                  // 1. Bắn thông báo hủy vé liên thông vào đúng bộ sưu tập 'user_notifications'
                  await FirebaseFirestore.instance.collection('user_notifications').add({
                    'title': 'HỦY VÉ HOÀN TIỀN THÀNH CÔNG 💸',
                    'content': 'Stella Cinema xác nhận yêu cầu hủy vé phim "$title" của Quý khách đã được phê duyệt thành công. Số tiền hoàn lại đã được gửi trả về tài khoản nguồn của bạn.',
                    'time': DateFormat('HH:mm - dd/MM/yyyy').format(DateTime.now()),
                    'type': 'system',
                    'isRead': false,
                    'created_at': Timestamp.now(),
                  });

                  // 2. Chuyển trạng thái vé thành CANCELLED thay vì xóa hẳn (lịch sử vé)
                  await FirebaseFirestore.instance.collection('tickets').doc(ticketId).update({
                    'payment_status': 'CANCELLED',
                  });

                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã hủy vé thành công! Vui lòng kiểm tra Trung tâm thông báo. 🎉')),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Lỗi hệ thống khi hủy vé: $e')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('XÁC NHẬN HỦY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        );
      },
    );
  }

  void _simulateSaveToCalendar(BuildContext context, String movieTitle, String showtime) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.amber),
            SizedBox(height: 16),
            Text('Đang đồng bộ với lịch hệ thống...', style: TextStyle(color: Colors.white70, fontSize: 13, decoration: TextDecoration.none)),
          ],
        ),
      ),
    );

    Future.delayed(const Duration(milliseconds: 1500), () {
      Navigator.pop(context); 

      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: const Color(0xFF16161F),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.calendar_today_rounded, color: Colors.amber, size: 22),
                SizedBox(width: 10),
                Text('ĐÃ THÊM VÀO LỊCH 📅', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sự kiện xem phim đã được đồng bộ hóa thành công vào ứng dụng Lịch của thiết bị:', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E2A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🎬 Sự kiện: Xem phim "$movieTitle"',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '📅 Lịch chiếu: $showtime',
                        style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '📍 Địa điểm: Stella Cinema (Vui lòng đến trước 15 phút)',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                )
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ĐÃ HIỂU', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
              )
            ],
          );
        },
      );
    });
  }

  void _showTicketDetailsModal(BuildContext context, Map<String, dynamic> ticketData) {
    final title = ticketData['title'] ?? 'Phim Stella Cinema';
    final posterUrl = ticketData['posterUrl'] ?? '';
    final List<dynamic> seats = ticketData['seats'] ?? [];
    final int amount = ticketData['total_amount'] ?? 0;
    final formatAmount = amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');
    final showtime = ticketData['showtime'] ?? 'Stella Cinema';
    final isCancelled = ticketData['payment_status'] == 'CANCELLED';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16161F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              
              // Chi tiết vé
              const Text(
                'VÉ XEM PHIM ĐIỆN TỬ',
                style: TextStyle(color: Colors.white30, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 2),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (posterUrl.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        posterUrl,
                        width: 55,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 55,
                          height: 80,
                          color: Colors.white12,
                          child: const Icon(Icons.movie, color: Colors.white30, size: 24),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          showtime,
                          style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w500, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 30),

              // Mock QR Code & Barcode
              if (isCancelled)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Text('VÉ NÀY ĐÃ BỊ HỦY / HOÀN TIỀN', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                )
              else ...[
                const MockQRCodeWidget(),
                const SizedBox(height: 12),
                const BarcodeWidget(),
                const SizedBox(height: 8),
                const Text('MÃ VÉ: STL-8392-749', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
              
              const Divider(color: Colors.white12, height: 30),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Ghế đã đặt:', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Text(seats.join(', '), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Tổng thanh toán:', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Text('$formatAmount đ', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
              const SizedBox(height: 30),
              
              if (!isCancelled) ...[
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: () => _simulateSaveToCalendar(context, title, showtime),
                    icon: const Icon(Icons.calendar_today_rounded, color: Colors.black, size: 16),
                    label: const Text('THÊM VÀO LỊCH CHIẾU HỆ THỐNG', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isCancelled ? null : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Đang tạo ảnh vé... Đã lưu ảnh thành công vào Album của bạn! 📸'), backgroundColor: Colors.green),
                        );
                      },
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text('CHIA SẺ VÉ'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: const Text('ĐÓNG', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text('KHO VÉ CỦA TÔI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'Vé sắp xem'),
            Tab(text: 'Lịch sử giao dịch'),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('tickets').orderBy('created_at', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.amber));
          }

          final List<QueryDocumentSnapshot> allTickets = snapshot.hasData ? snapshot.data!.docs : [];

          return TabBarView(
            controller: _tabController,
            children: [
              _buildTicketList(allTickets, activeOnly: true),
              _buildTicketList(allTickets, activeOnly: false),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTicketList(List<QueryDocumentSnapshot> allTickets, {required bool activeOnly}) {
    // Phân loại: Vé sắp xem có payment_status == 'COMPLETED'. Lịch sử có status == 'CANCELLED' hoặc vé cũ
    final filteredTickets = allTickets.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data['payment_status'] ?? 'COMPLETED';
      return activeOnly ? (status == 'COMPLETED') : (status == 'CANCELLED');
    }).toList();

    if (filteredTickets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.confirmation_number_outlined, color: Colors.white24, size: 54),
            const SizedBox(height: 12),
            Text(
              activeOnly ? 'Bạn chưa có vé hoạt động nào sắp diễn ra.' : 'Không có lịch sử giao dịch nào.',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredTickets.length,
      itemBuilder: (context, index) {
        final ticketDoc = filteredTickets[index];
        final ticketData = ticketDoc.data() as Map<String, dynamic>;

        final String ticketId = ticketDoc.id;
        final String title = ticketData['title'] ?? 'Phim Stella Cinema';
        final String posterUrl = ticketData['posterUrl'] ?? '';
        final List<dynamic> seats = ticketData['seats'] ?? [];
        final int amount = ticketData['total_amount'] ?? 0;
        final formatAmount = amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');
        final isCancelled = ticketData['payment_status'] == 'CANCELLED';

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 150 + (index * 60)),
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 15 * (1 - value)),
              child: Opacity(opacity: value, child: child),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF16161F),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isCancelled ? Colors.redAccent.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
              ),
            ),
            child: InkWell(
              onTap: () => _showTicketDetailsModal(context, ticketData),
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(16)),
                        child: posterUrl.isNotEmpty
                            ? Image.network(posterUrl, width: 85, height: 115, fit: BoxFit.cover, errorBuilder: (c, e, s) => Container(width: 85, height: 115, color: const Color(0xFF222232), child: const Icon(Icons.movie, color: Colors.white24)))
                            : Container(width: 85, height: 115, color: const Color(0xFF222232), child: const Icon(Icons.movie, color: Colors.white24)),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 6),
                              Text('Ghế ngồi: ${seats.join(", ")}', style: TextStyle(color: isCancelled ? Colors.redAccent : Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                              const SizedBox(height: 6),
                              Text('Tổng tiền: $formatAmount đ', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: const BoxDecoration(color: Color(0xFF1E1E2A), borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isCancelled ? '❌ GIAO DỊCH ĐÃ HỦY' : '🎟️ Chạm để xem QR vào rạp',
                          style: TextStyle(
                            color: isCancelled ? Colors.redAccent : Colors.white38,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (!isCancelled)
                          TextButton.icon(
                            onPressed: () => _showCancelTicketDialog(context, ticketId, title),
                            icon: const Icon(Icons.cancel_presentation_rounded, color: Colors.redAccent, size: 16),
                            label: const Text('HỦY VÉ', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class BarcodeWidget extends StatelessWidget {
  const BarcodeWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(40, (index) {
        final double width = (index % 3 == 0) ? 3.0 : ((index % 5 == 0) ? 2.5 : 1.2);
        final bool isSpace = index % 4 == 0;
        return Container(
          width: width,
          height: 40,
          color: isSpace ? Colors.transparent : Colors.white70,
        );
      }),
    );
  }
}

class MockQRCodeWidget extends StatelessWidget {
  const MockQRCodeWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      height: 130,
      color: Colors.white,
      padding: const EdgeInsets.all(8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 15,
        ),
        itemCount: 15 * 15,
        itemBuilder: (context, index) {
          final x = index % 15;
          final y = index ~/ 15;
          bool isBlack = false;

          if (x < 4 && y < 4) {
            isBlack = (x == 0 || x == 3 || y == 0 || y == 3);
          } else if (x >= 11 && y < 4) {
            isBlack = (x == 11 || x == 14 || y == 0 || y == 3);
          } else if (x < 4 && y >= 11) {
            isBlack = (x == 0 || x == 3 || y == 11 || y == 14);
          } else {
            isBlack = (index * 7 + index % 3) % 2 == 0;
          }

          return Container(
            color: isBlack ? const Color(0xFF0F0F13) : Colors.white,
          );
        },
      ),
    );
  }
}