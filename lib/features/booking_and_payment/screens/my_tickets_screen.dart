import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants.dart';
import '../viewmodels/ticket_viewmodel.dart';

class MyTicketsScreen extends ConsumerStatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  ConsumerState<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends ConsumerState<MyTicketsScreen> with SingleTickerProviderStateMixin {
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

  // Hủy vé giờ đi qua backend /cancel-ticket (Admin SDK, 1 transaction duy
  // nhất cho cả hoàn ví + đổi trạng thái vé) thay vì 3 lệnh ghi Firestore rời
  // rạc như trước - tránh trường hợp ví đã được hoàn tiền nhưng bước đổi
  // trạng thái vé bị Firestore rules từ chối (vé COMPLETED), khiến vé vẫn
  // còn hiệu lực trong khi khách đã nhận lại tiền, và có thể lặp lại nhiều
  // lần vì nút hủy không có trạng thái "đang xử lý" để chặn double-tap.
  void _showCancelTicketDialog(BuildContext context, String ticketId, String title) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        bool isCancelling = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: const Color(0xFF0A0A0A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 22),
                SizedBox(width: 8),
                Text('XÁC NHẬN HỦY VÉ', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            content: Text(
              'Bạn có chắc chắn muốn hủy vé bộ phim "$title" không? Chỉ áp dụng cho vé còn tối thiểu 30 phút trước giờ chiếu. Hệ thống sẽ tự động hoàn tiền và gửi thông báo xác nhận về hộp thư của bạn.',
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: isCancelling ? null : () => Navigator.pop(dialogContext),
                child: const Text('QUAY LẠI', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              ElevatedButton(
                onPressed: isCancelling
                    ? null
                    : () async {
                        setDialogState(() => isCancelling = true);
                        final navigator = Navigator.of(dialogContext);
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
                          final response = await http.post(
                            Uri.parse('${AppConfig.paymentBackendUrl}/cancel-ticket'),
                            headers: {
                              'Content-Type': 'application/json',
                              if (idToken != null) 'Authorization': 'Bearer $idToken',
                            },
                            body: jsonEncode({'ticketId': ticketId}),
                          ).timeout(const Duration(seconds: 15));

                          final body = jsonDecode(response.body) as Map<String, dynamic>;
                          final ok = body['success'] == true;
                          navigator.pop();
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(ok
                                  ? 'Đã hủy vé và hoàn tiền thành công! Vui lòng kiểm tra Ví & Thông báo. 🎉'
                                  : (body['message'] ?? 'Hủy vé thất bại')),
                              backgroundColor: ok ? Colors.teal : Colors.redAccent,
                            ),
                          );
                        } catch (e) {
                          navigator.pop();
                          messenger.showSnackBar(
                            SnackBar(content: Text('Lỗi kết nối máy chủ khi hủy vé: $e'), backgroundColor: Colors.redAccent),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  disabledBackgroundColor: Colors.redAccent.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: isCancelling
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('XÁC NHẬN HỦY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
        );
      },
    );
  }

  // Parse "yyyy-MM-dd" (showtime thật do theater_manager tạo) hoặc
  // "Hôm nay (dd/MM)"/"Thứ X (dd/MM)" (khung giờ mẫu dự phòng) thành DateTime
  // thật - dùng chung logic với backend-payos/server.js parseShowDateTime.
  DateTime? _parseShowDateTime(String showDate, String showTime) {
    try {
      final parts = showTime.split(':');
      final hh = int.parse(parts[0]);
      final mm = int.parse(parts[1]);
      final isoMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(showDate);
      if (isoMatch != null) {
        return DateTime(int.parse(isoMatch[1]!), int.parse(isoMatch[2]!), int.parse(isoMatch[3]!), hh, mm);
      }
      final ddmmMatch = RegExp(r'\((\d{2})/(\d{2})\)').firstMatch(showDate);
      if (ddmmMatch != null) {
        final now = DateTime.now();
        return DateTime(now.year, int.parse(ddmmMatch[2]!), int.parse(ddmmMatch[1]!), hh, mm);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // Ghi thật vào ứng dụng Lịch của thiết bị (mở app Calendar có sẵn để người
  // dùng xác nhận lưu) - trước đây chỉ là hiệu ứng loading giả rồi hiện dialog
  // "đã lưu" mà không hề đụng tới calendar thật nào trên máy.
  void _addToDeviceCalendar(BuildContext context, String movieTitle, String showDate, String showTime, String theaterName) {
    final start = _parseShowDateTime(showDate, showTime);
    if (start == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không đọc được ngày giờ suất chiếu để thêm vào lịch.'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }
    final event = Event(
      title: 'Xem phim: $movieTitle',
      description: 'Vé xem phim tại $theaterName - Stella Cinema',
      location: theaterName,
      startDate: start,
      endDate: start.add(const Duration(hours: 2)),
      iosParams: const IOSParams(reminder: Duration(minutes: 30)),
      androidParams: const AndroidParams(emailInvites: []),
    );
    Add2Calendar.addEvent2Cal(event);
  }

  void _showReviewDialog(BuildContext context, String ticketId, String movieTitle) {
    int rating = 5;
    final commentCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF16161F),
            title: Text('Đánh giá: $movieTitle', style: const TextStyle(color: Colors.amber, fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return IconButton(
                      icon: Icon(index < rating ? Icons.star_rounded : Icons.star_outline_rounded, color: Colors.amber, size: 32),
                      onPressed: () => setState(() => rating = index + 1),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: commentCtrl,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Chia sẻ cảm nhận của bạn...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF1E1E2A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy', style: TextStyle(color: Colors.white54))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                onPressed: () async {
                  await FirebaseFirestore.instance.collection('reviews').add({
                    'ticketId': ticketId,
                    'movieTitle': movieTitle,
                    'rating': rating,
                    'comment': commentCtrl.text.trim(),
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cảm ơn bạn đã đánh giá!')));
                  }
                },
                child: const Text('Gửi', style: TextStyle(color: Colors.black)),
              ),
            ],
          );
        });
      },
    );
  }

  void _showGiftDialog(BuildContext context, String ticketId, String qrSignature) {
    final emailCtrl = TextEditingController();
    bool isProcessing = false;
    String? errorMsg;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF16161F),
            title: const Text('Tặng vé (Chuyển nhượng)', style: TextStyle(color: Colors.pinkAccent, fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nhập Email tài khoản của người nhận. Vé sẽ được chuyển thẳng sang tài khoản của họ.', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 16),
                TextField(
                  controller: emailCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Nhập Email bạn bè...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white10,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
                if (errorMsg != null) ...[
                  const SizedBox(height: 8),
                  Text(errorMsg!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                ]
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy', style: TextStyle(color: Colors.white54))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent),
                onPressed: isProcessing ? null : () async {
                  final email = emailCtrl.text.trim();
                  if (email.isEmpty) {
                    setState(() => errorMsg = 'Vui lòng nhập Email');
                    return;
                  }
                  
                  if (email == FirebaseAuth.instance.currentUser?.email) {
                    setState(() => errorMsg = 'Bạn không thể tự tặng vé cho chính mình');
                    return;
                  }

                  setState(() {
                    isProcessing = true;
                    errorMsg = null;
                  });

                  try {
                    // Tìm user theo email
                    final usersSnap = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: email).get();
                    if (usersSnap.docs.isEmpty) {
                      setState(() {
                        errorMsg = 'Không tìm thấy người dùng có Email này trong hệ thống.';
                        isProcessing = false;
                      });
                      return;
                    }

                    final receiverId = usersSnap.docs.first.id;

                    // Đổi chủ sở hữu vé
                    await FirebaseFirestore.instance.collection('tickets').doc(ticketId).update({
                      'userId': receiverId,
                    });

                    if (context.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Tặng vé thành công! Vé đã được chuyển.'), backgroundColor: Colors.teal),
                      );
                    }
                  } catch (e) {
                    setState(() {
                      errorMsg = 'Lỗi hệ thống: $e';
                      isProcessing = false;
                    });
                  }
                },
                child: isProcessing 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Xác nhận Tặng', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        });
      },
    );
  }

  void _showTicketDetailsModal(BuildContext context, String ticketId, Map<String, dynamic> ticketData) {
    final title = ticketData['movieTitle'] ?? 'Phim Stella Cinema';
    final posterUrl = ticketData['posterUrl'] ?? '';
    final List<dynamic> seats = ticketData['seats'] ?? [];
    final int amount = ticketData['totalAmount'] ?? (ticketData['ticketAmount'] ?? 0);
    final formatAmount = amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');
    final String showDate = ticketData['showDate'] ?? 'Unknown Date';
    final String showTime = ticketData['showTime'] ?? 'Unknown Time';
    final String theaterName = ticketData['theaterName'] ?? ticketData['selectedTheater'] ?? 'Stella Cinema';
    final String? roomName = ticketData['roomName'] as String?;
    final String? duration = ticketData['duration'] as String?;
    final isCancelled = ticketData['paymentStatus'] == 'CANCELLED';
    final String? qrSignature = ticketData['qrSignature'] as String?;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 20,
            left: 20,
            right: 20,
            top: MediaQuery.of(context).padding.top + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ticket Card
              ClipPath(
                clipper: TicketClipper(),
                child: Container(
                  color: Colors.white,
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Section
                      Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (posterUrl.isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  posterUrl,
                                  width: 100,
                                  height: 140,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _buildPlaceholderPoster(),
                                ),
                              )
                            else
                              _buildPlaceholderPoster(),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      const Icon(Icons.access_time_rounded, size: 16, color: Colors.black54),
                                      const SizedBox(width: 6),
                                      Text(duration?.isNotEmpty == true ? duration! : 'Đang cập nhật', style: const TextStyle(color: Colors.black87, fontSize: 13)),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(Icons.videocam_outlined, size: 16, color: Colors.black54),
                                      const SizedBox(width: 6),
                                      const Expanded(child: Text('Hành động, Phiêu lưu', style: TextStyle(color: Colors.black87, fontSize: 13))), // Mock genre
                                    ],
                                  ),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                      
                      // Date and Seat Info
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.calendar_month_outlined, size: 36, color: Colors.black87),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(showTime, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                                    Text(showDate, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                                  ],
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                const Icon(Icons.chair_alt_outlined, size: 36, color: Colors.black87),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Ghế', style: TextStyle(color: Colors.black54, fontSize: 12)),
                                    Text(seats.join(', '), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14)),
                                  ],
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      // Dashed Divider
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: CustomPaint(
                          painter: DashedLinePainter(),
                          child: const SizedBox(width: double.infinity, height: 1),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Location & Price
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.monetization_on_outlined, size: 20, color: Colors.black87),
                                const SizedBox(width: 12),
                                Text('$formatAmount VND', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.location_on_outlined, size: 20, color: Colors.black87),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        roomName?.isNotEmpty == true ? '$theaterName - $roomName' : theaterName,
                                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text('Please arrive 15 minutes early.', style: TextStyle(color: Colors.black54, fontSize: 13)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // QR Code Section
                      const SizedBox(height: 16),
                      if (isCancelled)
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                            child: const Text('VÉ NÀY ĐÃ BỊ HỦY', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                          ),
                        )
                      else if (qrSignature != null)
                        Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(left: 20, right: 10),
                                  child: Text('Xuất trình mã QR này tại quầy vé để nhận vé', style: TextStyle(color: Colors.black87, fontSize: 13)),
                                )
                              ),
                              Padding(
                                padding: const EdgeInsets.only(right: 20),
                                child: QrImageView(
                                  data: jsonEncode({'ticketId': ticketId, 'signature': qrSignature}),
                                  version: QrVersions.auto,
                                  size: 90,
                                  backgroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      
                      // Bottom Section (Barcode)
                      const SizedBox(height: 30),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: const BarcodeWidget(color: Colors.black), // Passed color
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Text('Order ID: ${ticketId.toUpperCase()}', style: const TextStyle(color: Colors.black87, fontSize: 12)),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              if (!isCancelled) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _addToDeviceCalendar(context, title, showDate, showTime, theaterName),
                        icon: const Icon(Icons.calendar_month_rounded, color: Colors.amber, size: 16),
                        label: const Text('Lưu lịch', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.amber),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                      ),
                      if (qrSignature != null) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _showGiftDialog(context, ticketId, qrSignature),
                          icon: const Icon(Icons.card_giftcard_rounded, color: Colors.pinkAccent, size: 16),
                          label: const Text('Tặng vé', style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.pinkAccent),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _showReviewDialog(context, ticketId, title),
                        icon: const Icon(Icons.star_rounded, color: Colors.lightGreenAccent, size: 16),
                        label: const Text('Đánh giá', style: TextStyle(color: Colors.lightGreenAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.lightGreenAccent),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // Close button
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(16),
                ),
                child: const Icon(Icons.close),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlaceholderPoster() {
    return Container(
      width: 100,
      height: 140,
      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(12)),
      child: const Icon(Icons.movie, color: Colors.grey, size: 40),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
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
      body: ref.watch(userTicketsProvider).when(
        data: (allTickets) {
          return TabBarView(
            controller: _tabController,
            children: [
              _buildTicketList(allTickets, activeOnly: true),
              _buildTicketList(allTickets, activeOnly: false),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.amber)),
        error: (error, stackTrace) => Center(
          child: Text('Đã xảy ra lỗi: $error', style: const TextStyle(color: Colors.redAccent)),
        ),
      ),
    );
  }

  Widget _buildTicketList(List<QueryDocumentSnapshot> allTickets, {required bool activeOnly}) {
    // Phân loại: Vé sắp xem có payment_status == 'COMPLETED'. Lịch sử có status == 'CANCELLED' hoặc vé cũ
    final filteredTickets = allTickets.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data['paymentStatus'] ?? 'COMPLETED';
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
        final String title = ticketData['movieTitle'] ?? 'Phim Stella Cinema';
        final String posterUrl = ticketData['posterUrl'] ?? '';
        final List<dynamic> seats = ticketData['seats'] ?? [];
        final int amount = ticketData['totalAmount'] ?? 0;
        final formatAmount = amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');
        final isCancelled = ticketData['paymentStatus'] == 'CANCELLED';

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
              color: const Color(0xFF1E1E2C),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: isCancelled ? Colors.redAccent.withValues(alpha: 0.1) : Colors.amber.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showTicketDetailsModal(context, ticketId, ticketData),
                  child: SizedBox(
                    height: 140,
                    child: Row(
                      children: [
                      // Image Section
                      SizedBox(
                        width: 100,
                        height: 140,
                        child: posterUrl.isNotEmpty
                            ? Image.network(posterUrl, fit: BoxFit.cover, errorBuilder: (c, e, s) => Container(color: const Color(0xFF222232), child: const Icon(Icons.movie, color: Colors.white24)))
                            : Container(color: const Color(0xFF222232), child: const Icon(Icons.movie, color: Colors.white24)),
                      ),
                      // Dashed Divider
                      Container(
                        width: 1,
                        height: 140,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: CustomPaint(
                          painter: DashedLineVerticalPainter(),
                        ),
                      ),
                      // Details Section
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(Icons.chair_alt_rounded, size: 14, color: isCancelled ? Colors.redAccent : Colors.amber),
                                  const SizedBox(width: 4),
                                  Expanded(child: Text(seats.join(", "), style: TextStyle(color: isCancelled ? Colors.redAccent : Colors.amber, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.monetization_on_outlined, size: 14, color: Colors.white54),
                                  const SizedBox(width: 4),
                                  Text('$formatAmount đ', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                ],
                              ),
                              const Spacer(),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    isCancelled ? '❌ ĐÃ HỦY' : '🎟️ NHẤN ĐỂ XEM',
                                    style: TextStyle(
                                      color: isCancelled ? Colors.redAccent : Colors.white54,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  if (!isCancelled)
                                    InkWell(
                                      onTap: () => _showCancelTicketDialog(context, ticketId, title),
                                      borderRadius: BorderRadius.circular(4),
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        child: Text('HỦY', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class BarcodeWidget extends StatelessWidget {
  final Color color;
  const BarcodeWidget({super.key, this.color = Colors.white70});

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
          color: isSpace ? Colors.transparent : color,
        );
      }),
    );
  }
}

class DashedLineVerticalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    var max = size.height;
    var dashWidth = 5.0;
    var dashSpace = 5.0;
    double startY = 0;
    
    while (startY < max) {
      canvas.drawLine(Offset(0, startY), Offset(0, startY + dashWidth), paint);
      startY += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class TicketClipper extends CustomClipper<Path> {
  final double holeRadius = 16.0;
  final double cornerRadius = 16.0;
  
  @override
  Path getClip(Size size) {
    final path = Path();
    final double holeY = size.height * 0.65;

    path.moveTo(cornerRadius, 0);
    path.lineTo(size.width - cornerRadius, 0);
    path.quadraticBezierTo(size.width, 0, size.width, cornerRadius);
    path.lineTo(size.width, holeY - holeRadius);
    path.arcToPoint(
      Offset(size.width, holeY + holeRadius),
      radius: Radius.circular(holeRadius),
      clockwise: false,
    );
    path.lineTo(size.width, size.height - cornerRadius);
    path.quadraticBezierTo(size.width, size.height, size.width - cornerRadius, size.height);
    path.lineTo(cornerRadius, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - cornerRadius);
    path.lineTo(0, holeY + holeRadius);
    path.arcToPoint(
      Offset(0, holeY - holeRadius),
      radius: Radius.circular(holeRadius),
      clockwise: false,
    );
    path.lineTo(0, cornerRadius);
    path.quadraticBezierTo(0, 0, cornerRadius, 0);
    
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const double dashWidth = 6.0;
    const double dashSpace = 4.0;
    double startX = 0;

    while (startX < size.width) {
      canvas.drawLine(Offset(startX, 0), Offset(startX + dashWidth, 0), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

