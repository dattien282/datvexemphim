import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../booking_and_payment/screens/movie_detail_screen.dart';
import '../../../core/constants.dart';

class CinemaAiChatbotScreen extends StatefulWidget {
  const CinemaAiChatbotScreen({super.key});

  @override
  State<CinemaAiChatbotScreen> createState() => _CinemaAiChatbotScreenState();
}

class _CinemaAiChatbotScreenState extends State<CinemaAiChatbotScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  bool _isTyping = false;
  // Trạng thái Gemini giờ chỉ để hiển thị UI ("Trực tuyến với Gemini AI" hay
  // "Fallback offline") - server tự quyết định có dùng được Gemini hay không
  // dựa trên GEMINI_API_KEY của nó, client không còn giữ API key nào cả.
  bool _isGeminiAvailable = true;

  // Danh sách hội thoại
  final List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _messages.add({
      'sender': 'ai',
      'text': 'Xin chào bạn! Tôi là Trợ lý AI thông minh của Stella Cinema G5. Tôi có thể giúp bạn xem thông tin phim đang hot, giá vé, bắp nước hoặc hỗ trợ đặt vé nhanh đó. Hôm nay bạn muốn tìm phim gì nào? 🎬🍿',
      'movieData': null,
    });
  }

  // Xử lý logic AI (chạy Gemini + RAG + Fallback)
  Future<Map<String, dynamic>> _getAiResponseData(String userText) async {
    final String text = userText.toLowerCase().trim();

    // 1. Chạy Gemini qua backend proxy (server giữ API key, client không còn
    // biết key này tồn tại dưới hình thức nào - tránh lộ key qua Firestore
    // hoặc qua chuỗi biên dịch sẵn trong app như trước đây).
    if (_isGeminiAvailable) {
      try {
        // Truy vấn danh sách phim thật từ Firestore để làm ngữ cảnh (RAG) -
        // đây là dữ liệu công khai (ai cũng đọc được collection 'movies'),
        // không phải secret, nên vẫn lấy trực tiếp từ client như trước.
        String movieContext = "";
        try {
          final moviesSnapshot = await FirebaseFirestore.instance.collection('movies').get();
          if (moviesSnapshot.docs.isNotEmpty) {
            movieContext = "\n[Dữ liệu phim đang chiếu thực tế tại rạp Stella Cinema]:\n";
            for (var doc in moviesSnapshot.docs) {
              final data = doc.data();
              movieContext += "- Phim: ${data['title']} | Thể loại: ${data['genre']} | Đánh giá: ${data['rating']}★ | Đạo diễn: ${data['director']} | Suất chiếu mẫu: ${data['selectedTime']}\n";
            }
          }
        } catch (_) {}

        // Trích xuất lịch sử hội thoại gần nhất (tối đa 10 tin nhắn) để truyền ngữ cảnh hội thoại liên tục
        final history = _messages.skip(1).take(10).map((msg) {
          return {'role': msg['sender'] == 'user' ? 'user' : 'model', 'text': msg['text'] ?? ''};
        }).toList();

        final response = await http.post(
          Uri.parse('${AppConfig.paymentBackendUrl}/gemini-chat'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'message': userText, 'movieContext': movieContext, 'history': history}),
        ).timeout(const Duration(seconds: 20));

        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['success'] == true) {
          final String responseText = (body['text'] as String? ?? '').trim();
          if (responseText.isNotEmpty) {
            // Tự động phân tích xem người dùng có muốn đặt bộ phim nào không để đính kèm card đặt vé nhanh
            Map<String, dynamic>? detectedMovie;
            try {
              final moviesSnapshot = await FirebaseFirestore.instance.collection('movies').get();
              for (var doc in moviesSnapshot.docs) {
                final data = doc.data();
                final String title = data['title'] ?? '';
                if (text.contains(title.toLowerCase())) {
                  detectedMovie = data;
                  detectedMovie['id'] = doc.id;
                  break;
                }
              }
            } catch (_) {}

            return {
              'text': responseText,
              'movieData': detectedMovie,
            };
          }
        } else if (mounted) {
          setState(() => _isGeminiAvailable = false);
        }
      } catch (e) {
        debugPrint("Gemini API (qua backend) bị lỗi hoặc quá tải: $e. Chuyển hướng sang Fallback offline.");
        if (mounted) setState(() => _isGeminiAvailable = false);
      }
    }

    // 2. Chế độ Fallback offline (Bộ lọc từ khóa thông minh)
    if (text.contains('phim') && (text.contains('hot') || text.contains('hay') || text.contains('suất') || text.contains('lịch') || text.contains('chiếu'))) {
      try {
        final query = await FirebaseFirestore.instance
            .collection('movies')
            .where('title', isEqualTo: 'Mai')
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          final movieDoc = query.docs.first;
          final movieData = movieDoc.data();
          movieData['id'] = movieDoc.id;
          return {
            'text': 'Hiện tại rạp đang cháy vé phim "Mai" của Trấn Thành (Tâm lý, Tình cảm - 8.5★). Suất chiếu trải dài từ 09:30 đến 23:00 hàng ngày. Bạn có thể bấm nút Đặt Vé Ngay dưới đây để chọn suất chiếu nhé! 🔥',
            'movieData': movieData,
          };
        }
      } catch (_) {}
      return {
        'text': 'Hiện tại rạp đang cháy vé phim "Mai" của Trấn Thành (Tâm lý, Tình cảm - 8.5★). Bạn có thể bấm Đặt Vé trên trang chủ nhé! 🔥',
        'movieData': null,
      };
    } else if (text.contains('giá') || text.contains('vé') || text.contains('bao nhiêu') || text.contains('tiền')) {
      return {
        'text': 'Dạ giá vé tại rạp Stella Cinema cực kỳ hợp lý:\n• Ghế Thường (Single Standard): 90.000 đ\n• Ghế VIP (Single VIP): 120.000 đ\n• Cặp ghế đôi Sweetbox cuối rạp: 200.000 đ (Đã bao gồm vách ngăn riêng tư)\n*Cuối tuần phụ thu +15k/ghế; Suất sớm giảm -10k/ghế; Suất khuya phụ thu +10k/ghế nha bạn! 🎫',
        'movieData': null,
      };
    } else if (text.contains('bắp') || text.contains('nước') || text.contains('combo') || text.contains('đồ ăn') || text.contains('ăn')) {
      return {
        'text': 'Bắp nước tại Stella Cinema luôn nóng hổi giòn rụm nha bạn:\n• Combo Solo (1 bắp ngọt lớn + 1 nước ngọt): 70.000 đ\n• Combo Couple (1 bắp ngọt lớn + 2 nước ngọt): 110.000 đ\n• Combo Gia đình (2 bắp ngọt lớn + 3 nước ngọt + 1 snack): 160.000 đ\nBạn có thể chọn thêm bắp nước ở bước sau khi chọn ghế nhé! 🍿🥤',
        'movieData': null,
      };
    } else if (text.contains('km') || text.contains('khuyến mãi') || text.contains('ưu đãi') || text.contains('voucher') || text.contains('mã')) {
      return {
        'text': 'Hôm nay đang có chương trình giảm giá độc quyền cho bạn nè:\n• Nhập mã "STELLA50" được giảm 50.000 đ\n• Nhập mã "STELLA100" được giảm 100.000 đ trực tiếp khi đặt vé bắp nước đó bạn ơi! Nhớ nhập mã tại màn hình thanh toán nhé! 🎁',
        'movieData': null,
      };
    } else if (text.contains('địa chỉ') || text.contains('địa điểm') || text.contains('rạp') || text.contains('ở đâu') || text.contains('chi nhánh') || text.contains('bản đồ')) {
      return {
        'text': 'Hệ thống rạp Stella Cinema có mặt tại các chi nhánh sau:\n1. Stella Nguyễn Du: 116 Nguyễn Du, Quận 1, TP.HCM\n2. Stella Vạn Hạnh Mall: Tầng 6, Vạn Hạnh Mall, Quận 10, TP.HCM\n3. Stella Mipec: Tầng 5, TTTM Mipec Long Biên, Hà Nội\n4. Stella Đà Nẵng: TTTM CoopMart, Thanh Khê, Đà Nẵng\n5. Stella Cần Thơ: Tầng 2, Sense City, Cần Thơ\n👉 Bạn có thể bấm vào mục "Hệ Thống Rạp" ngoài trang chủ để xem định vị GPS trực quan trên Google Maps nhé!',
        'movieData': null,
      };
    } else if (text.contains('hủy') || text.contains('hoàn') || text.contains('trả')) {
      return {
        'text': 'Chính sách hủy vé của Stella rất linh hoạt:\nBạn được phép hủy vé tự động trước giờ chiếu ít nhất 30 phút. Hệ thống sẽ tự động hoàn 100% tiền vé về ví điện tử Stella Wallet của bạn ngay lập tức. Để hủy vé, bạn vào "Kho vé" > chọn vé > bấm nút "Hủy vé" màu đỏ nhé! 💸',
        'movieData': null,
      };
    } else if (text.contains('bảo mật') || text.contains('otp') || text.contains('an toàn')) {
      return {
        'text': 'Stella Cinema cam kết bảo mật thanh toán tuyệt đối. Khi bạn chọn thanh toán, hệ thống sẽ tự động gửi mã OTP xác thực 6 số về Email đăng ký. Chỉ khi nhập chính xác mã OTP thì giao dịch mới được thực hiện thành công, an tâm tuyệt đối nha bạn! 🛡️',
        'movieData': null,
      };
    }

    return {
      'text': 'Dạ Stella đã ghi nhận ý kiến của bạn. Do hiện tại đang chạy offline nên Stella chỉ trả lời được các câu hỏi cơ bản. Bạn hãy thử hỏi về "Phim đang hot", "Giá vé ghế Sweetbox", "Bắp nước combo", "Khuyến mãi giảm giá", "Địa chỉ các rạp" nha! ❤️',
      'movieData': null,
    };
  }

  void _sendMessage() async {
    final String text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'sender': 'user', 'text': text, 'movieData': null});
      _messageController.clear();
      _isTyping = true;
    });

    _scrollToBottom();

    // Gọi AI hoặc fallback
    final aiResult = await _getAiResponseData(text);

    if (!mounted) return;
    setState(() {
      _isTyping = false;
      _messages.add({
        'sender': 'ai',
        'text': aiResult['text'],
        'movieData': aiResult['movieData'],
      });
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
              child: const Icon(Icons.psychology_rounded, color: Colors.black, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TRỢ LÝ AI STELLA', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                Text(
                  _isGeminiAvailable ? 'Trực tuyến với Gemini AI' : 'Trực tuyến (Fallback offline)',
                  style: TextStyle(
                    color: _isGeminiAvailable ? Colors.greenAccent : Colors.orangeAccent,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                // Hiển thị hiệu ứng AI đang soạn tin nhắn
                if (index == _messages.length) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0A0A),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                          bottomLeft: Radius.circular(0),
                          bottomRight: Radius.circular(16),
                        ),
                        border: Border.all(color: Colors.white10, width: 0.5),
                      ),
                      child: const TypingIndicator(),
                    ),
                  );
                }

                final chat = _messages[index];
                bool isAi = chat['sender'] == 'ai';
                final movieData = chat['movieData'];

                return Align(
                  alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                    decoration: BoxDecoration(
                      color: isAi ? const Color(0xFF0A0A0A) : Colors.amber,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isAi ? 0 : 16),
                        bottomRight: Radius.circular(isAi ? 16 : 0),
                      ),
                      border: isAi ? Border.all(color: Colors.white10, width: 0.5) : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chat['text']!,
                          style: TextStyle(
                            color: isAi ? Colors.white70 : Colors.black,
                            fontSize: 13,
                            fontWeight: isAi ? FontWeight.normal : FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                        if (movieData != null) ...[
                          const Divider(color: Colors.white12, height: 20),
                          Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  movieData['posterUrl'] ?? '',
                                  width: 45,
                                  height: 65,
                                  fit: BoxFit.cover,
                                  errorBuilder: (c, e, s) => Container(
                                    width: 45,
                                    height: 65,
                                    color: Colors.white12,
                                    child: const Icon(Icons.movie, size: 20, color: Colors.white24),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      movieData['title'] ?? 'Phim Stella',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      movieData['genre'] ?? 'Hành Động',
                                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.star, color: Colors.amber, size: 12),
                                        const SizedBox(width: 2),
                                        Text(
                                          movieData['rating'] ?? '9.8',
                                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 32,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => MovieDetailScreen(movieData: movieData),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                elevation: 0,
                                padding: EdgeInsets.zero,
                              ),
                              child: const Text(
                                'ĐẶT VÉ NGAY',
                                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ),
                          )
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Thanh nhập hội thoại
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(color: Color(0xFF0A0A0A)),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      keyboardType: TextInputType.text,
                      textCapitalization: TextCapitalization.sentences,
                      enableSuggestions: true,
                      autocorrect: true,
                      decoration: InputDecoration(
                        hintText: 'Hỏi Stella phim hot, giá vé, combo...',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFF000000),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: const CircleAvatar(
                      backgroundColor: Colors.amber,
                      radius: 20,
                      child: Icon(Icons.send_rounded, color: Colors.black, size: 18),
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

// Widget hiệu ứng 3 chấm nháy nháy mượt mà cho Trợ lý AI
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            // Độ trễ cho từng dấu chấm nhấp nháy tạo gợn sóng
            final delay = index * 0.2;
            final animValue = (1.0 - ((_controller.value - delay) % 1.0).abs() * 2).clamp(0.0, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white70.withValues(alpha: 0.2 + 0.8 * animValue),
                shape: BoxShape.circle,
              ),
            );
          },
        );
      }),
    );
  }
}