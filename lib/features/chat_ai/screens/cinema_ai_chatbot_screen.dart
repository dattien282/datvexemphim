import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../booking_and_payment/screens/movie_detail_screen.dart';
import '../../booking_and_payment/screens/showtime_selection_screen.dart';
import '../../../core/constants.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../providers/user_provider.dart';
import '../../../providers/theaters_provider.dart';

class CinemaAiChatbotScreen extends ConsumerStatefulWidget {
  const CinemaAiChatbotScreen({super.key});

  @override
  ConsumerState<CinemaAiChatbotScreen> createState() => _CinemaAiChatbotScreenState();
}

class _CinemaAiChatbotScreenState extends ConsumerState<CinemaAiChatbotScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  bool _isTyping = false;
  bool _isGeminiAvailable = true;

  // Lịch sử chat cục bộ
  final List<Map<String, dynamic>> _messages = [];

  // Nhập liệu bằng giọng nói (Speech-to-Text)
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;

  // Câu hỏi gợi ý nhanh (Suggestion Chips)
  final List<String> _suggestions = [
    "Phim nào đang hot nhất hôm nay? 🔥",
    "Giá vé các loại ghế của rạp? 🎫",
    "Có những combo bắp nước nào? 🍿",
    "Có mã giảm giá hoặc voucher gì không? 🎁",
  ];

  @override
  void initState() {
    super.initState();
    // Khởi tạo tin nhắn chào mừng
    _messages.add({
      'sender': 'ai',
      'text': 'Xin chào bạn! Tôi là Trợ lý AI thông minh của Stella Cinema G5. Tôi có thể giúp bạn xem thông tin phim đang hot, giá vé, bắp nước hoặc hỗ trợ đặt vé nhanh đó. Hôm nay bạn muốn tìm phim gì nào? 🎬🍿',
      'movieData': null,
    });
    _initSpeech();
    _loadChatHistory();
  }

  void _initSpeech() async {
    try {
      await _speech.initialize(
        onError: (err) => debugPrint('Speech error: $err'),
        onStatus: (status) => debugPrint('Speech status: $status'),
      );
    } catch (e) {
      debugPrint('Không thể khởi tạo SpeechToText: $e');
    }
  }

  void _loadChatHistory() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('chat_messages')
          .orderBy('createdAt', descending: false)
          .get();
      if (snapshot.docs.isNotEmpty) {
        setState(() {
          _messages.clear();
          // Đưa tin nhắn chào mừng ban đầu vào
          _messages.add({
            'sender': 'ai',
            'text': 'Xin chào bạn! Tôi là Trợ lý AI thông minh của Stella Cinema G5. Tôi có thể giúp bạn xem thông tin phim đang hot, giá vé, bắp nước hoặc hỗ trợ đặt vé nhanh đó. Hôm nay bạn muốn tìm phim gì nào? 🎬🍿',
            'movieData': null,
          });
          for (var doc in snapshot.docs) {
            final data = doc.data();
            _messages.add({
              'sender': data['sender'],
              'text': data['text'],
              'movieData': data['movieData'],
            });
          }
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint("Lỗi tải lịch sử chat: $e");
    }
  }

  void _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onError: (err) => debugPrint('Listen error: $err'),
        onStatus: (status) => debugPrint('Listen status: $status'),
      );
      if (!mounted) return;
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) {
            setState(() {
              _messageController.text = val.recognizedWords;
            });
          },
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể nhận diện giọng nói. Vui lòng cấp quyền micro trong cài đặt.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  // Ghi nhận tin nhắn mới lên Firestore nếu người dùng đã đăng nhập
  void _saveMessageToFirestore(String sender, String text, Map<String, dynamic>? movieData) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('chat_messages')
          .add({
            'sender': sender,
            'text': text,
            'movieData': movieData,
            'createdAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint("Lỗi lưu tin nhắn vào Firestore: $e");
    }
  }

  // Xử lý logic AI (Gemini + RAG + GPS + User Context + Fallback)
  Future<Map<String, dynamic>> _getAiResponseData(String userText) async {
    final String text = userText.toLowerCase().trim();

    if (_isGeminiAvailable) {
      try {
        // 1. Tối ưu RAG thông minh (Selective RAG)
        String movieContext = "";
        try {
          final moviesSnapshot = await FirebaseFirestore.instance.collection('movies').get();
          if (moviesSnapshot.docs.isNotEmpty) {
            var docs = moviesSnapshot.docs.where((d) => d.data()['isDeleted'] != true).toList();
            bool hasTitleMatch = false;
            for (var doc in docs) {
              final title = (doc.data()['title'] as String? ?? '').toLowerCase();
              if (text.contains(title)) {
                hasTitleMatch = true;
                break;
              }
            }
            
            movieContext = "\n[Dữ liệu phim đang chiếu tại Stella Cinema]:\n";
            int count = 0;
            for (var doc in docs) {
              final data = doc.data();
              final title = data['title'] ?? '';
              final genre = data['genre'] ?? '';
              final rating = data['rating'] ?? '9.8';
              final director = data['director'] ?? '';
              final time = data['selectedTime'] ?? '19:00';
              
              if (hasTitleMatch && !text.contains(title.toLowerCase())) {
                continue;
              }
              movieContext += "- Phim: $title | Thể loại: $genre | Đánh giá: $rating★ | Đạo diễn: $director | Giờ chiếu mẫu: $time\n";
              count++;
              if (!hasTitleMatch && count >= 5) break; // Chỉ lấy top 5 phim hot nhất nếu hỏi chung chung
            }
          }
        } catch (_) {}

        // 2. Tính khoảng cách rạp theo vị trí thực tế của khách hàng (GPS Aware)
        bool wantsLocation = text.contains('gần tôi') || text.contains('gần nhất') || text.contains('địa chỉ') || text.contains('ở đâu') || text.contains('chi nhánh');
        String locationContext = "";
        if (wantsLocation) {
          try {
            bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
            if (serviceEnabled) {
              LocationPermission permission = await Geolocator.checkPermission();
              if (permission == LocationPermission.denied) {
                permission = await Geolocator.requestPermission();
              }
              if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
                Position pos = await Geolocator.getCurrentPosition(
                  locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
                );
                final theaters = ref.read(theatersProvider).valueOrNull ?? [];
                if (theaters.isNotEmpty) {
                  final List<Map<String, dynamic>> sortedTheaters = [];
                  for (var t in theaters) {
                    double dist = Geolocator.distanceBetween(pos.latitude, pos.longitude, t.lat, t.lng);
                    sortedTheaters.add({
                      'name': t.name,
                      'address': t.address,
                      'distance': dist / 1000,
                    });
                  }
                  sortedTheaters.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));
                  locationContext = "\n[Khoảng cách thực tế từ vị trí khách hàng đến các rạp]:\n";
                  for (var t in sortedTheaters) {
                    locationContext += "- ${t['name']} | Địa chỉ: ${t['address']} | Cách khách hàng: ${(t['distance'] as double).toStringAsFixed(1)} km\n";
                  }
                }
              }
            }
          } catch (e) {
            debugPrint("Lỗi xác định vị trí GPS: $e");
          }
        }

        // 3. Cá nhân hóa theo tài khoản khách hàng (User Context)
        String userContext = "";
        try {
          final userProfile = ref.read(userProfileProvider).valueOrNull;
          if (userProfile != null) {
            userContext = "\n[Thông tin người dùng đang trò chuyện]:\n"
                "- Tên: ${userProfile.displayName.isNotEmpty ? userProfile.displayName : 'Chưa cập nhật'}\n"
                "- Email: ${userProfile.email}\n"
                "- Số dư ví Stella Wallet: ${userProfile.walletBalance}đ\n"
                "- Vai trò: ${userProfile.role.label}\n";
            
            final ticketsSnap = await FirebaseFirestore.instance
                .collection('tickets')
                .where('email', isEqualTo: userProfile.email)
                .get();
            if (ticketsSnap.docs.isNotEmpty) {
              userContext += "- Số lượng vé đã đặt trước đó: ${ticketsSnap.docs.length} vé\n";
            }
          }
        } catch (_) {}

        // Trích xuất lịch sử cuộc trò chuyện
        final history = _messages.skip(1).take(10).map((msg) {
          return {'role': msg['sender'] == 'user' ? 'user' : 'model', 'text': msg['text'] ?? ''};
        }).toList();


        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          throw 'User not authenticated';
        }
        final token = await user.getIdToken();

        final response = await http.post(
          Uri.parse('${AppConfig.paymentBackendUrl}/gemini-chat'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'message': userText, 'movieContext': movieContext, 'history': history}),

        final fullMovieContext = "$movieContext\n$locationContext\n$userContext";

        final response = await http.post(
          Uri.parse('${AppConfig.paymentBackendUrl}/gemini-chat'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'message': userText, 'movieContext': fullMovieContext, 'history': history}),
        ).timeout(const Duration(seconds: 20));

        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['success'] == true) {
          final String responseText = (body['text'] as String? ?? '').trim();
          if (responseText.isNotEmpty) {
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
        debugPrint("Gemini API proxy bị lỗi: $e. Dùng Fallback.");
        if (mounted) setState(() => _isGeminiAvailable = false);
      }
    }

    // 2. Chế độ Fallback offline (Keyword filter)
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
        'text': 'Bắp nước tại Stella Cinema luôn nóng hổi giòn rụm nha bạn:\n• Combo Solo (1 bắp ngọt lớn + 1 nước ngọt): 70.000 đ\n• Combo Couple (1 bắp ngọt lớn + 2 nước ngọt): 110.000 đ\n• Combo Gia đình (2 bắp ngọt lớn + 3 nước ngọt + 1 phần quà độc quyền): 160.000 đ\nBạn có thể chọn thêm bắp nước ở bước sau khi chọn ghế nhé! 🍿🥤',
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

  void _sendMessage({String? customText}) async {
    final String text = customText ?? _messageController.text.trim();
    if (text.isEmpty) return;

    if (customText == null) {
      _messageController.clear();
    }

    setState(() {
      _messages.add({'sender': 'user', 'text': text, 'movieData': null});
      _isTyping = true;
    });
    _scrollToBottom();

    // Lưu tin nhắn gửi của user vào Firestore
    _saveMessageToFirestore('user', text, null);

    // Gọi AI
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

    // Lưu phản hồi của AI vào Firestore
    _saveMessageToFirestore('ai', aiResult['text'], aiResult['movieData']);
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
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
    _speech.stop();
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
                Row(
                  children: [
                    PulsingStatusIndicator(isActive: _isGeminiAvailable),
                    const SizedBox(width: 5),
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
          ],
        ),
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // Lịch sử tin nhắn chat
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                // Đang soạn tin nhắn (Typing indicator)
                if (index == _messages.length) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F0F15),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                          bottomLeft: Radius.circular(0),
                          bottomRight: Radius.circular(16),
                        ),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 0.5),
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isAi) ...[
                        const CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.amber,
                          child: Icon(Icons.smart_toy_rounded, color: Colors.black, size: 14),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                        decoration: BoxDecoration(
                          gradient: isAi
                              ? null
                              : const LinearGradient(
                                  colors: [Colors.amber, Colors.orangeAccent],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                          color: isAi ? const Color(0xFF0F0F15) : null,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isAi ? 0 : 16),
                            bottomRight: Radius.circular(isAi ? 16 : 0),
                          ),
                          border: isAi
                              ? Border.all(color: Colors.amber.withValues(alpha: 0.15), width: 0.5)
                              : null,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Render Markdown cho AI, Text cho User
                            isAi
                                ? MarkdownBody(
                                    data: chat['text']!,
                                    styleSheet: MarkdownStyleSheet(
                                      p: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                                      strong: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                                      listBullet: const TextStyle(color: Colors.amber, fontSize: 13),
                                    ),
                                  )
                                : Text(
                                    chat['text']!,
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      height: 1.4,
                                    ),
                                  ),
                            
                            // Card phim và các Deep link shortcut
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
                              Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 32,
                                      child: OutlinedButton(
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => MovieDetailScreen(movieData: movieData),
                                            ),
                                          );
                                        },
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(color: Colors.amber, width: 1),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                          padding: EdgeInsets.zero,
                                        ),
                                        child: const Text(
                                          'CHI TIẾT PHIM',
                                          style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 10),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: SizedBox(
                                      height: 32,
                                      child: ElevatedButton(
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => ShowtimeSelectionScreen(movieData: movieData),
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
                                          'MUA VÉ NHANH',
                                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Suggestion Chips (Gợi ý nhanh) hiển thị khi hội thoại mới bắt đầu
          if (_messages.length <= 1)
            Container(
              height: 36,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _suggestions.length,
                itemBuilder: (context, index) {
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(
                        _suggestions[index],
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                      backgroundColor: const Color(0xFF16161F),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 0.5),
                      ),
                      onPressed: () => _sendMessage(customText: _suggestions[index]),
                    ),
                  );
                },
              ),
            ),

          // Input Bar (Thanh nhập tin nhắn kèm phím Micro thu âm)
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
                        hintText: _isListening ? 'Stella đang lắng nghe bạn...' : 'Hỏi Stella phim hot, giá vé, combo...',
                        hintStyle: TextStyle(
                          color: _isListening ? Colors.amber : Colors.white30,
                          fontSize: 13,
                          fontStyle: _isListening ? FontStyle.italic : FontStyle.normal,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF000000),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        prefixIcon: _isListening
                            ? const Icon(Icons.keyboard_voice_rounded, color: Colors.amber, size: 18)
                            : null,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _listen,
                    child: CircleAvatar(
                      backgroundColor: _isListening ? Colors.redAccent : const Color(0xFF16161F),
                      radius: 20,
                      child: Icon(
                        _isListening ? Icons.mic_off_rounded : Icons.mic_rounded,
                        color: _isListening ? Colors.white : Colors.amber,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _sendMessage(),
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

// ── Pulsing status indicator ──────────────────────────────────────────────────
class PulsingStatusIndicator extends StatefulWidget {
  final bool isActive;
  const PulsingStatusIndicator({super.key, required this.isActive});

  @override
  State<PulsingStatusIndicator> createState() => _PulsingStatusIndicatorState();
}

class _PulsingStatusIndicatorState extends State<PulsingStatusIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final double pulse = _animController.value;
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: widget.isActive
                ? Colors.greenAccent.withValues(alpha: 0.4 + 0.6 * pulse)
                : Colors.orangeAccent.withValues(alpha: 0.4 + 0.6 * pulse),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.isActive ? Colors.greenAccent : Colors.orangeAccent,
                blurRadius: 4 * pulse,
                spreadRadius: 1 * pulse,
              )
            ],
          ),
        );
      },
    );
  }
}

// ── Typing Indicator (AI is typing...) ─────────────────────────────────────────
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
            final delay = index * 0.2;
            final animValue = (1.0 - ((_controller.value - delay) % 1.0).abs() * 2).clamp(0.0, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: 5,
              height: 5,
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
