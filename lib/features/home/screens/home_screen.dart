import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../booking_and_payment/screens/showtime_selection_screen.dart'; // ĐÃ IMPORT: Màn hình chọn Rạp/Ngày/Suất chiếu trung gian
import '../../booking_and_payment/screens/my_tickets_screen.dart';
import '../../notifications/screens/notification_screen.dart';
import '../../chat_ai/screens/cinema_ai_chatbot_screen.dart';
import '../../maps/screens/theater_maps_screen.dart';
import '../../auth/screens/login_screen.dart';
import '../../auth/screens/profile_screen.dart';
import '../../auth/screens/membership_screen.dart';
import '../../booking_and_payment/screens/movie_detail_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../viewmodels/movie_viewmodel.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ValueNotifier<String> _searchQuery = ValueNotifier('');
  final ValueNotifier<String> _selectedCategory = ValueNotifier('Tất cả');
  final List<String> _categories = ['Tất cả', 'Hành Động', 'Tâm Lý', 'Kịch Tính', 'Kinh Dị', 'Hoạt Hình'];

  final List<_BannerItem> bannerItems = const [
    _BannerItem(
      imageUrl: 'https://images.unsplash.com/photo-1542204165-65bf26472b9b?w=800&q=80',
      badge: 'THỨ 4 VUI VẺ',
      badgeColor: Color(0xFFE91E63),
      title: 'HAPPY WEDNESDAY',
      subtitle: 'Giảm 10% toàn bộ giao dịch đặt vé vào Thứ 4 hàng tuần',
      action: _BannerAction.combo,
    ),
    _BannerItem(
      imageUrl: 'https://images.unsplash.com/photo-1557672172-298e090bd0f1?w=800&q=80',
      badge: 'VOUCHER',
      badgeColor: Color(0xFF00B0FF),
      title: 'MÙA HÈ SÔI ĐỘNG',
      subtitle: 'Nhập mã MUAHE2024 giảm ngay 20K. Bấm để sao chép!',
      action: _BannerAction.voucher,
      voucherCode: 'MUAHE2024',
    ),
    _BannerItem(
      imageUrl: 'https://media.themoviedb.org/t/p/w600_and_h900_face/z8OWDTR7pQuZi7jkEuR7yMXRrQt.jpg',
      badge: 'ĐANG CHIẾU',
      badgeColor: Color(0xFFE53935),
      title: 'MINIONS & QUÁI VẬT',
      subtitle: 'Phiêu Lưu, Hoạt Hình, Hài, Gia Đình',
      action: _BannerAction.movie,
      movieTitle: 'Minions & Quái Vật',
    ),
    _BannerItem(
      imageUrl: 'https://en.wikipedia.org/wiki/Special:FilePath/The_Odyssey_(2026_film)_poster.jpg',
      badge: 'SẮP CHIẾU',
      badgeColor: Color(0xFF1565C0),
      title: 'THE ODYSSEY',
      subtitle: 'Christopher Nolan • Sử Thi, Phiêu Lưu',
      action: _BannerAction.movie,
      movieTitle: 'The Odyssey',
    ),
    _BannerItem(
      imageUrl: 'https://en.wikipedia.org/wiki/Special:FilePath/Spider-Man_Brand_New_Day_poster.jpg',
      badge: 'HOT',
      badgeColor: Color(0xFFFF6F00),
      title: 'SPIDER-MAN: KHỞI ĐẦU MỚI',
      subtitle: 'Tom Holland • Hành Động, Siêu Anh Hùng',
      action: _BannerAction.movie,
      movieTitle: 'Spider-Man: Khởi Đầu Mới',
    ),
    _BannerItem(
      imageUrl: 'https://images.unsplash.com/photo-1585647347483-22b66260dfff?w=800&q=80',
      badge: 'KHUYẾN MÃI',
      badgeColor: Color(0xFF2E7D32),
      title: 'THỨ 4 VUI VẺ',
      subtitle: 'Đồng giá vé 70K toàn hệ thống (Áp dụng cho mọi khung giờ) 🥳',
      action: _BannerAction.combo,
    ),
    _BannerItem(
      imageUrl: 'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?w=800&q=80',
      badge: 'ƯU ĐÃI THÀNH VIÊN',
      badgeColor: Color(0xFF6A1B9A),
      title: 'STELLA MEMBER VIP',
      subtitle: 'Tích điểm mỗi vé • Đổi quà hấp dẫn • Ưu tiên chỗ ngồi',
      action: _BannerAction.profile,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Đã tắt auto-seed phim mẫu: giờ `movies` chứa dữ liệu thật do admin quản lý
    // qua AdminMoviesScreen, seed lại sẽ xoá mất dữ liệu thật đó.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowPromoPopup());
  }

  // Pop-up quảng bá phim đang chiếu, hiện 1 lần mỗi khi mở app - trừ khi
  // người dùng tick "Không hiển thị lại" (lưu SharedPreferences theo tên phim,
  // để khi admin đổi phim quảng bá thì pop-up mới lại hiện đúng 1 lần nữa).
  Future<void> _maybeShowPromoPopup() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('movies')
          .where('isShowingNow', isEqualTo: true)
          .get();
      final docs = snap.docs.where((d) => d.data()['isDeleted'] != true).toList();
      if (docs.isEmpty) return;
      docs.sort((a, b) {
        final ra = double.tryParse('${a.data()['rating'] ?? 0}') ?? 0;
        final rb = double.tryParse('${b.data()['rating'] ?? 0}') ?? 0;
        return rb.compareTo(ra);
      });
      final movieDoc = docs.first;
      final movieData = {'id': movieDoc.id, ...movieDoc.data()};
      final title = movieData['title'] as String? ?? '';

      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('promo_dismissed_$title') == true) return;

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => _PromoPopup(movieData: movieData),
      );
    } catch (_) {
      // Không chặn màn hình chính nếu lỗi mạng/query - pop-up chỉ là gợi ý phụ.
    }
  }

  Future<void> _seedDatabaseIfNeeded() async {
    try {
      final List<Map<String, dynamic>> initialMovies = [
        // --- 10 PHIM ĐANG CHIẾU ---
        {
          'title': 'Mai',
          'genre': 'Tâm Lý, Tình Cảm',
          'rating': '8.5',
          'posterUrl': 'https://upload.wikimedia.org/wikipedia/en/3/36/Mai_2024_poster.jpg',
          'trailerUrl': 'https://www.youtube.com/watch?v=HKm5rF2L31Y',
          'director': 'Trấn Thành',
          'cast': 'Phương Anh Đào, Tuấn Trần, Hồng Đào',
          'duration': '131 phút',
          'releaseDate': '10/02/2024',
          'selectedTheater': 'Stella Cinema Nguyễn Du (Quận 1)',
          'selectedDate': DateFormat('dd/MM/yyyy').format(DateTime.now()),
          'selectedTime': '19:00',
          'description': 'Tác phẩm xoay quanh câu chuyện về Mai, một người phụ nữ gần 40 tuổi làm nghề mát-xa trị liệu, luôn gánh chịu nhiều định kiến xã hội. Cuộc đời cô bước sang trang mới khi gặp Dương, một chàng trai trẻ đam mê âm nhạc kém cô 7 tuổi.',
          'isShowingNow': true,
        },
        {
          'title': 'Quật Mộ Trùng Độc',
          'genre': 'Kinh Dị, Kịch Tính',
          'rating': '9.2',
          'posterUrl': 'https://upload.wikimedia.org/wikipedia/en/1/13/Exhuma_film_poster.jpg',
          'trailerUrl': 'https://www.youtube.com/watch?v=f_Vp_72kXrs',
          'director': 'Jang Jae-hyun',
          'cast': 'Choi Min-sik, Kim Go-eun, Yoo Hae-jin, Lee Do-hyun',
          'duration': '134 phút',
          'releaseDate': '15/03/2024',
          'selectedTheater': 'Stella Cinema Vạn Hạnh Mall (Quận 10)',
          'selectedDate': DateFormat('dd/MM/yyyy').format(DateTime.now()),
          'selectedTime': '20:30',
          'description': 'Hai pháp sư trẻ được thuê bởi một gia đình giàu có ở Los Angeles để di dời phần mộ của tổ tiên họ nhằm giải lời nguyền bí ẩn đang đeo bám đứa con sơ sinh. Khi thực hiện, họ vô tình giải phóng một thế lực tà ác khủng khiếp.',
          'isShowingNow': true,
        },
        {
          'title': 'Dune: Hành Tinh Cát - Phần 2',
          'genre': 'Hành Động, Khoa Học Viễn Tưởng',
          'rating': '9.4',
          'posterUrl': 'https://upload.wikimedia.org/wikipedia/en/5/52/Dune_Part_Two_poster.jpeg',
          'trailerUrl': 'https://www.youtube.com/watch?v=Way9Dexny3w',
          'director': 'Denis Villeneuve',
          'cast': 'Timothée Chalamet, Zendaya, Rebecca Ferguson, Josh Brolin',
          'duration': '166 phút',
          'releaseDate': '01/03/2024',
          'selectedTheater': 'Stella Cinema Mipec Long Biên (Hà Nội)',
          'selectedDate': DateFormat('dd/MM/yyyy').format(DateTime.now()),
          'selectedTime': '18:15',
          'description': 'Paul Atreides hợp lực cùng Chani và tộc người Fremen để thực hiện cuộc trả thù chống lại những kẻ đã hủy hoại gia đình mình. Anh phải lựa chọn giữa tình yêu của đời mình và vận mệnh của vũ trụ.',
          'isShowingNow': true,
        },
        {
          'title': 'Lật Mặt 7: Một Điều Ước',
          'genre': 'Tâm Lý, Gia Đình',
          'rating': '9.3',
          'posterUrl': 'https://upload.wikimedia.org/wikipedia/vi/d/d4/%C3%81p_ph%C3%ADch_ch%C3%ADnh_th%E1%BB%A9c_L%E1%BA%ADt_m%E1%BA%B7t_7.jpg',
          'trailerUrl': 'https://www.youtube.com/watch?v=8VzGZ7F4rMs',
          'director': 'Lý Hải',
          'cast': 'Thanh Hằng, Trương Minh Cường, Đinh Y Nhung, Quách Ngọc Tuyên',
          'duration': '112 phút',
          'releaseDate': '26/04/2024',
          'selectedTheater': 'Stella Cinema Nguyễn Du (Quận 1)',
          'selectedDate': DateFormat('dd/MM/yyyy').format(DateTime.now()),
          'selectedTime': '15:45',
          'description': 'Câu chuyện gia đình ấm áp, cảm động xoay quanh người mẹ già một đời tần tảo nuôi lớn 5 người con. Đến khi bà gặp tai nạn chấn thương, câu hỏi "Ai sẽ nuôi mẹ?" trở thành nỗi trăn trở của những người con xa quê.',
          'isShowingNow': true,
        },
        {
          'title': 'Kung Fu Panda 4',
          'genre': 'Hoạt Hình, Hài Hước, Gia Đình',
          'rating': '8.9',
          'posterUrl': 'https://upload.wikimedia.org/wikipedia/en/7/7f/Kung_Fu_Panda_4_poster.jpg',
          'trailerUrl': 'https://www.youtube.com/watch?v=_inKs4EEGrI',
          'director': 'Mike Mitchell',
          'cast': 'Jack Black, Awkwafina, Viola Davis, Dustin Hoffman',
          'duration': '94 phút',
          'releaseDate': '08/03/2024',
          'selectedTheater': 'Stella Cinema Vạn Hạnh Mall (Quận 10)',
          'selectedDate': DateFormat('dd/MM/yyyy').format(DateTime.now()),
          'selectedTime': '10:00',
          'description': 'Gấu trúc Po chuẩn bị trở thành Thủ lĩnh tinh thần của Thung lũng Hòa Bình, nhưng trước đó cậu phải tìm kiếm và huấn luyện một Hào hiệp Long nhân mới. Đồng thời, Po phải đối mặt với Tắc Kè Bông - một kẻ thù nguy hiểm có thể biến hình.',
          'isShowingNow': true,
        },
        {
          'title': 'Vây Hãm: Kẻ Trừng Phạt',
          'genre': 'Hành Động, Hình Sự, Kịch Tính',
          'rating': '9.0',
          'posterUrl': 'https://upload.wikimedia.org/wikipedia/en/a/ae/The_Roundup_Punishment_film_poster.jpg',
          'trailerUrl': 'https://www.youtube.com/watch?v=e2lA6K-k6iQ',
          'director': 'Heo Myung-haeng',
          'cast': 'Ma Dong-seok, Kim Mu-yeol, Park Ji-hwan',
          'duration': '109 phút',
          'releaseDate': '24/04/2024',
          'selectedTheater': 'Stella Cinema Đà Nẵng (Thanh Khê)',
          'selectedDate': DateFormat('dd/MM/yyyy').format(DateTime.now()),
          'selectedTime': '16:30',
          'description': 'Thanh tra quái vật Ma Seok-do đối đầu với một tổ chức cờ bạc trực tuyến quy mô toàn cầu cực kỳ tàn bạo, được chỉ đạo bởi một cựu lính đặc nhiệm nguy hiểm.',
          'isShowingNow': true,
        },
        {
          'title': 'Hành Tinh Khỉ: Vương Quốc Mới',
          'genre': 'Hành Động, Khoa Học Viễn Tưởng, Phiêu Lưu',
          'rating': '8.7',
          'posterUrl': 'https://upload.wikimedia.org/wikipedia/en/c/cf/Kingdom_of_the_Planet_of_the_Apes_poster.jpg',
          'trailerUrl': 'https://www.youtube.com/watch?v=Kdr5eedS30Y',
          'director': 'Wes Ball',
          'cast': 'Owen Teague, Freya Allan, Kevin Durand',
          'duration': '145 phút',
          'releaseDate': '10/05/2024',
          'selectedTheater': 'Stella Cinema Cần Thơ (Sense City)',
          'selectedDate': DateFormat('dd/MM/yyyy').format(DateTime.now()),
          'selectedTime': '14:00',
          'description': 'Nhiều thế hệ sau triều đại của Caesar, một chú khỉ trẻ dấn thân vào hành trình định đoạt tương lai của cả loài khỉ và loài người.',
          'isShowingNow': true,
        },
        {
          'title': 'Godzilla x Kong: Đế Chế Mới',
          'genre': 'Hành Động, Khoa Học Viễn Tưởng',
          'rating': '8.8',
          'posterUrl': 'https://upload.wikimedia.org/wikipedia/en/b/be/Godzilla_x_kong_the_new_empire_poster.jpg',
          'trailerUrl': 'https://www.youtube.com/watch?v=lV1OOlGwExM',
          'director': 'Adam Wingard',
          'cast': 'Rebecca Hall, Brian Tyree Henry, Dan Stevens',
          'duration': '115 phút',
          'releaseDate': '29/03/2024',
          'selectedTheater': 'Stella Cinema Đà Nẵng (Thanh Khê)',
          'selectedDate': DateFormat('dd/MM/yyyy').format(DateTime.now()),
          'selectedTime': '21:00',
          'description': 'Hai siêu quái thú Godzilla và Kong phải dẹp bỏ hiềm khích để cùng đối mặt với một mối đe dọa hủy diệt mới ẩn sâu trong lòng Trái Đất.',
          'isShowingNow': true,
        },
        {
          'title': 'Kẻ Trộm Mặt Trăng 4',
          'genre': 'Hoạt Hình, Hài Hước, Gia Đình',
          'rating': '9.1',
          'posterUrl': 'https://upload.wikimedia.org/wikipedia/en/e/ed/Despicable_Me_4_Theatrical_Release_Poster.jpeg',
          'trailerUrl': 'https://www.youtube.com/watch?v=LtP46C7EwBY',
          'director': 'Chris Renaud',
          'cast': 'Steve Carell, Kristen Wiig, Will Ferrell',
          'duration': '95 phút',
          'releaseDate': '03/07/2024',
          'selectedTheater': 'Stella Cinema Cần Thơ (Sense City)',
          'selectedDate': DateFormat('dd/MM/yyyy').format(DateTime.now()),
          'selectedTime': '11:15',
          'description': 'Gru chào đón thành viên mới Gru Jr., nhưng gia đình anh sớm phải chạy trốn khi một kẻ thù nguy hiểm trốn thoát khỏi nhà tù thề sẽ trả thù anh.',
          'isShowingNow': true,
        },
        {
          'title': 'Inside Out 2',
          'genre': 'Hoạt Hình, Hài Hước, Gia Đình',
          'rating': '9.5',
          'posterUrl': 'https://upload.wikimedia.org/wikipedia/en/f/f7/Inside_Out_2_poster.jpg',
          'trailerUrl': 'https://www.youtube.com/watch?v=LEjhY15eCx0',
          'director': 'Kelsey Mann',
          'cast': 'Amy Poehler, Maya Hawke, Kensington Tallman',
          'duration': '96 phút',
          'releaseDate': '14/06/2024',
          'selectedTheater': 'Stella Cinema Nguyễn Du (Quận 1)',
          'selectedDate': DateFormat('dd/MM/yyyy').format(DateTime.now()),
          'selectedTime': '13:30',
          'description': 'Tâm trí của cô bé Riley ở tuổi dậy thì bỗng xáo trộn khi xuất hiện một nhóm Cảm xúc mới dẫn đầu là Lo Âu (Anxiety), thách thức các cảm xúc cũ.',
          'isShowingNow': true,
        },
        // --- 10 PHIM SẮP CHIẾU ---
        {
          'title': 'Deadpool & Wolverine',
          'genre': 'Hành Động, Hài Hước, Khoa Học Viễn Tưởng',
          'rating': '9.6',
          'posterUrl': 'https://upload.wikimedia.org/wikipedia/en/4/4c/Deadpool_%26_Wolverine_poster.jpg',
          'trailerUrl': 'https://www.youtube.com/watch?v=73_1biulkYw',
          'director': 'Shawn Levy',
          'cast': 'Ryan Reynolds, Hugh Jackman, Emma Corrin',
          'duration': '127 phút',
          'releaseDate': DateFormat('dd/MM/yyyy').format(DateTime.now().add(const Duration(days: 7))),
          'selectedTheater': 'Stella Cinema Nguyễn Du (Quận 1)',
          'selectedDate': DateFormat('dd/MM/yyyy').format(DateTime.now().add(const Duration(days: 7))),
          'selectedTime': '20:00',
          'description': 'Deadpool bị lôi kéo vào hàng ngũ TVA và buộc phải hợp tác với một Wolverine bất đắc dĩ từ vũ trụ khác để cứu lấy dòng thời gian của mình.',
          'isShowingNow': false,
        },
        {
          'title': 'Alien: Romulus',
          'genre': 'Kinh Dị, Khoa Học Viễn Tưởng',
          'rating': '8.9',
          'posterUrl': 'https://upload.wikimedia.org/wikipedia/en/c/cb/Alien_Romulus_2024_%28poster%29.jpg',
          'trailerUrl': 'https://www.youtube.com/watch?v=x0XDEJCw8lk',
          'director': 'Fede Álvarez',
          'cast': 'Cailee Spaeny, David Jonsson, Archie Renaux',
          'duration': '119 phút',
          'releaseDate': DateFormat('dd/MM/yyyy').format(DateTime.now().add(const Duration(days: 14))),
          'selectedTheater': 'Stella Cinema Vạn Hạnh Mall (Quận 10)',
          'selectedDate': DateFormat('dd/MM/yyyy').format(DateTime.now().add(const Duration(days: 14))),
          'selectedTime': '22:15',
          'description': 'Một nhóm người trẻ dọn dẹp không gian đối mặt với sinh vật ngoài hành tinh khát máu và đáng sợ nhất vũ trụ trên một trạm không gian hoang phế.',
          'isShowingNow': false,
        },
        {
          'title': 'Joker: Folie à Deux',
          'genre': 'Tâm Lý, Hình Sự, Nhạc Kịch',
          'rating': '8.7',
          'posterUrl': 'https://upload.wikimedia.org/wikipedia/en/e/e8/Joker_-_Folie_%C3%A0_Deux_poster.jpg',
          'trailerUrl': 'https://www.youtube.com/watch?v=xy8aJw1vYHo',
          'director': 'Todd Phillips',
          'cast': 'Joaquin Phoenix, Lady Gaga, Zazie Beetz',
          'duration': '138 phút',
          'releaseDate': DateFormat('dd/MM/yyyy').format(DateTime.now().add(const Duration(days: 20))),
          'selectedTheater': 'Stella Cinema Mipec Long Biên (Hà Nội)',
          'selectedDate': DateFormat('dd/MM/yyyy').format(DateTime.now().add(const Duration(days: 20))),
          'selectedTime': '19:30',
          'description': 'Arthur Fleck bị giam giữ tại Arkham chờ xét xử, nơi anh tìm thấy tình yêu đích thực và âm nhạc bên trong tâm hồn mình cùng Harleen Quinzel.',
          'isShowingNow': false,
        },
        {
          'title': 'Gladiator II',
          'genre': 'Hành Động, Lịch Sử, Phiêu Lưu',
          'rating': '9.0',
          'posterUrl': 'https://upload.wikimedia.org/wikipedia/en/0/04/Gladiator_II_%282024%29_poster.jpg',
          'trailerUrl': 'https://www.youtube.com/watch?v=GP3m1a5e1p0',
          'director': 'Ridley Scott',
          'cast': 'Paul Mescal, Pedro Pascal, Denzel Washington',
          'duration': '148 phút',
          'releaseDate': DateFormat('dd/MM/yyyy').format(DateTime.now().add(const Duration(days: 25))),
          'selectedTheater': 'Stella Cinema Đà Nẵng (Thanh Khê)',
          'selectedDate': DateFormat('dd/MM/yyyy').format(DateTime.now().add(const Duration(days: 25))),
          'selectedTime': '18:00',
          'description': 'Nhiều thế hệ sau triều đại của Caesar, một chú khỉ trẻ dấn thân vào hành trình định đoạt tương lai của cả loài khỉ và loài người.',
          'isShowingNow': false,
        },
        {
          'title': 'Wicked',
          'genre': 'Kỳ Ảo, Nhạc Kịch, Tình Cảm',
          'rating': '8.6',
          'posterUrl': 'https://upload.wikimedia.org/wikipedia/en/3/3c/Wicked_%282024_film%29_poster.png',
          'trailerUrl': 'https://www.youtube.com/watch?v=R2RzN2P8lC8',
          'director': 'Jon M. Chu',
          'cast': 'Cynthia Erivo, Ariana Grande, Jonathan Bailey',
          'duration': '160 phút',
          'releaseDate': DateFormat('dd/MM/yyyy').format(DateTime.now().add(const Duration(days: 30))),
          'selectedTheater': 'Stella Cinema Cần Thơ (Sense City)',
          'selectedDate': DateFormat('dd/MM/yyyy').format(DateTime.now().add(const Duration(days: 30))),
          'selectedTime': '15:15',
          'description': 'Câu chuyện chưa kể về tình bạn và sự đối địch giữa Elphaba - Phù thủy xứ Oz tương lai và Glinda - Phù thủy tốt lành.',
          'isShowingNow': false,
        },
        {
          'title': 'Moana 2',
          'genre': 'Hoạt Hình, Phiêu Lưu, Nhạc Kịch',
          'rating': '9.2',
          'posterUrl': 'https://upload.wikimedia.org/wikipedia/en/7/73/Moana_2_poster.jpg',
          'trailerUrl': 'https://www.youtube.com/watch?v=hDZ7y8M8F2U',
          'director': 'David Derrick Jr.',
          'cast': 'Auli\'i Cravalho, Dwayne Johnson',
          'duration': '100 phút',
          'releaseDate': DateFormat('dd/MM/yyyy').format(DateTime.now().add(const Duration(days: 35))),
          'selectedTheater': 'Stella Cinema Nguyễn Du (Quận 1)',
          'selectedDate': DateFormat('dd/MM/yyyy').format(DateTime.now().add(const Duration(days: 35))),
          'selectedTime': '14:30',
          'description': 'Sau khi nhận được lời kêu gọi bất ngờ từ tổ tiên, Moana cùng Maui dấn thân vào một cuộc hành trình mới đến vùng biển xa xôi để kết nối lại các bộ tộc.',
          'isShowingNow': false,
        },
        {
          'title': 'Mufasa: Vua Sư Tử',
          'genre': 'Hoạt Hình, Phiêu Lưu, Gia Đình',
          'rating': '8.8',
          'posterUrl': 'https://upload.wikimedia.org/wikipedia/en/0/0b/Mufasa_The_Lion_King_Movie_2024.jpeg',
          'trailerUrl': 'https://www.youtube.com/watch?v=o17MF9vJ-I4',
          'director': 'Barry Jenkins',
          'cast': 'Aaron Pierre, Kelvin Harrison Jr., Seth Rogen',
          'duration': '120 phút',
          'releaseDate': DateFormat('dd/MM/yyyy').format(DateTime.now().add(const Duration(days: 40))),
          'selectedTheater': 'Stella Cinema Vạn Hạnh Mall (Quận 10)',
          'selectedDate': DateFormat('dd/MM/yyyy').format(DateTime.now().add(const Duration(days: 40))),
          'selectedTime': '09:45',
          'description': 'Rafiki kể câu chuyện về huyền thoại Mufasa, một chú sư tử mồ côi từng bước vươn lên trở thành một trong những vị vua vĩ đại nhất của Vùng Đất Kiêu Hãnh.',
          'isShowingNow': false,
        },
        {
          'title': 'Sonic the Hedgehog 3',
          'genre': 'Hành Động, Hoạt Hình, Phiêu Lưu',
          'rating': '8.9',
          'posterUrl': 'https://upload.wikimedia.org/wikipedia/en/0/07/Sonic3-box-us-225.jpg',
          'trailerUrl': 'https://www.youtube.com/watch?v=qSu6i2iFhJ8',
          'director': 'Jeff Fowler',
          'cast': 'Ben Schwartz, Jim Carrey, Keanu Reeves',
          'duration': '110 phút',
          'releaseDate': DateFormat('dd/MM/yyyy').format(DateTime.now().add(const Duration(days: 45))),
          'selectedTheater': 'Stella Cinema Mipec Long Biên (Hà Nội)',
          'selectedDate': DateFormat('dd/MM/yyyy').format(DateTime.now().add(const Duration(days: 45))),
          'selectedTime': '16:00',
          'description': 'Sonic, Knuckles và Tails phải đối đầu với một đối thủ mới vô cùng mạnh mẽ tên là Shadow - kẻ sở hữu sức mạnh vượt trội.',
          'isShowingNow': false,
        },
        {
          'title': 'Avatar 3: Lửa và Tro',
          'genre': 'Hành Động, Khoa Học Viễn Tưởng, Kịch Tính',
          'rating': '9.5',
          'posterUrl': 'https://upload.wikimedia.org/wikipedia/en/9/95/Avatar_Fire_and_Ash_poster.jpeg',
          'trailerUrl': 'https://www.youtube.com/watch?v=GP3m1a5e1p0',
          'director': 'James Cameron',
          'cast': 'Sam Worthington, Zoe Saldana, Sigourney Weaver',
          'duration': '190 phút',
          'releaseDate': DateFormat('dd/MM/yyyy').format(DateTime.now().add(const Duration(days: 60))),
          'selectedTheater': 'Stella Cinema Đà Nẵng (Thanh Khê)',
          'selectedDate': DateFormat('dd/MM/yyyy').format(DateTime.now().add(const Duration(days: 60))),
          'selectedTime': '19:00',
          'description': 'Jake Sully và Neytiri gặp gỡ một bộ tộc Na\'vi mới hung bạo sống ở vùng núi lửa núi tro, buộc họ phải đối mặt với thử thách chưa từng có.',
          'isShowingNow': false,
        },
        {
          'title': 'Mission: Impossible 8',
          'genre': 'Hành Động, Kịch Tính, Phiêu Lưu',
          'rating': '9.3',
          'posterUrl': 'https://upload.wikimedia.org/wikipedia/en/1/1f/Mission_Impossible_%E2%80%93_The_Final_Reckoning_Poster.jpg',
          'trailerUrl': 'https://www.youtube.com/watch?v=73_1biulkYw',
          'director': 'Christopher McQuarrie',
          'cast': 'Tom Cruise, Hayley Atwell, Ving Rhames',
          'duration': '145 phút',
          'releaseDate': DateFormat('dd/MM/yyyy').format(DateTime.now().add(const Duration(days: 75))),
          'selectedTheater': 'Stella Cinema Cần Thơ (Sense City)',
          'selectedDate': DateFormat('dd/MM/yyyy').format(DateTime.now().add(const Duration(days: 75))),
          'selectedTime': '20:15',
          'description': 'Ethan Hunt tiếp tục cuộc chạy đua nghẹt thở chống lại Thực thể AI tự trị khét tiếng nhằm bảo vệ tương lai của toàn thế giới.',
          'isShowingNow': false,
        }
      ];

      // Kiểm tra xem database hiện tại đã đủ 20 phim và sử dụng các ảnh của Wikipedia chưa
      final existingMovies = await FirebaseFirestore.instance.collection('movies').get();
      
      bool needToSeed = false;
      if (existingMovies.docs.length != 20) {
        needToSeed = true;
      } else {
        for (var doc in existingMovies.docs) {
          final data = doc.data();
          final posterUrl = data['posterUrl'] ?? '';
          final isShowingNowField = data['isShowingNow'];
          
          // Nếu poster trống hoặc vẫn dùng Unsplash/Galaxy/TMDB hoặc chưa có cờ isShowingNow thì bắt buộc re-seed
          if (posterUrl.isEmpty ||
              posterUrl.contains('unsplash.com') ||
              posterUrl.contains('galaxycine.vn') ||
              posterUrl.contains('image.tmdb.org') ||
              isShowingNowField == null) {
            needToSeed = true;
            break;
          }
        }
      }

      if (needToSeed) {
        // Xóa tất cả các phim cũ để cập nhật danh sách phim mới chuẩn
        for (var doc in existingMovies.docs) {
          await doc.reference.delete();
        }

        for (var movie in initialMovies) {
          await FirebaseFirestore.instance.collection('movies').add(movie);
        }
        debugPrint('Đã seed thành công 20 phim với ảnh Wikipedia CDN và trạng thái Đang Chiếu/Sắp Chiếu!');
      } else {
        debugPrint('Database đã khớp cấu hình chuẩn, không cần seed lại.');
      }
    } catch (e) {
      debugPrint('Lỗi seed data trong HomeScreen: $e');
    }
  }

  bool _checkLoginRequirement(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            backgroundColor: const Color(0xFF0A0A0A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.lock_outline, color: Colors.amber, size: 22),
                SizedBox(width: 8),
                Text('YÊU CẦU ĐĂNG NHẬP', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            content: const Text(
              'Tính năng này yêu cầu đăng nhập tài khoản Stella Cinema. Bạn có muốn đăng nhập ngay không?',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('ĐỂ SAU', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('ĐĂNG NHẬP', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          );
        },
      );
      return false;
    }
    return true;
  }

  void _handleBannerTap(_BannerItem item) async {
    switch (item.action) {
      case _BannerAction.movie:
        final title = item.movieTitle;
        if (title == null) return;
        // Hiện loading
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.amber)),
        );
        try {
          final snap = await FirebaseFirestore.instance
              .collection('movies')
              .where('title', isEqualTo: title)
              .limit(1)
              .get();
          if (!mounted) return;
          Navigator.pop(context); // đóng loading
          if (snap.docs.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Không tìm thấy thông tin phim.')),
            );
            return;
          }
          final movieData = {'id': snap.docs.first.id, ...snap.docs.first.data()};
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => MovieDetailScreen(movieData: movieData)),
          );
        } catch (e) {
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Lỗi tải thông tin phim: $e')),
            );
          }
        }
        break;

      case _BannerAction.combo:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Chọn phim & suất chiếu trước để áp dụng ưu đãi Combo nhé!'),
            backgroundColor: const Color(0xFF2E7D32),
            action: SnackBarAction(
              label: 'CHỌN PHIM',
              textColor: Colors.amber,
              onPressed: () => _tabController.animateTo(0),
            ),
          ),
        );
        break;

      case _BannerAction.profile:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MembershipScreen()),
        );
        break;
      case _BannerAction.voucher:
        if (item.voucherCode != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Mã ${item.voucherCode} (Giảm 20K) đã được lưu vào khay nhớ tạm!'),
              backgroundColor: const Color(0xFF00B0FF),
            ),
          );
        }
        break;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchQuery.dispose();
    _selectedCategory.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/images/logo.png',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: const Text('S', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'STELLA',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.location_on_rounded, color: Colors.lightGreenAccent, size: 26),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const TheaterMapsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.psychology_rounded, color: Colors.cyanAccent, size: 26),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CinemaAiChatbotScreen()),
              );
            },
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseAuth.instance.currentUser == null
                ? const Stream.empty()
                : FirebaseFirestore.instance
                    .collection('notifications')
                    .where('userEmail', isEqualTo: FirebaseAuth.instance.currentUser!.email)
                    .where('isRead', isEqualTo: false)
                    .snapshots(),
            builder: (context, snapshot) {
              final unreadCount = snapshot.hasData ? snapshot.data!.docs.length : 0;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_none_rounded, color: Colors.white70, size: 26),
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationScreen()));
                    },
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                        alignment: Alignment.center,
                        child: Text(
                          '$unreadCount',
                          style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.confirmation_number_rounded, color: Colors.amber, size: 24),
            onPressed: () {
              if (_checkLoginRequirement(context)) {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const MyTicketsScreen()));
              }
            },
          ),
          // NÚT ĐĂNG NHẬP / HỒ SƠ CÁ NHÂN PHÂN HÓA ĐỘNG
          FirebaseAuth.instance.currentUser != null
              ? IconButton(
                  icon: const Icon(Icons.account_circle_outlined, color: Colors.amber, size: 24),
                  tooltip: 'Hồ sơ cá nhân',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ProfileScreen()),
                    );
                  },
                )
              : IconButton(
                  icon: const Icon(Icons.login_rounded, color: Colors.amber, size: 24),
                  tooltip: 'Đăng nhập',
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
                      (route) => false,
                    );
                  },
                ),
          const SizedBox(width: 8),
        ],
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Banner Carousel -> widget riêng, setState không ảnh hưởng HomeScreen
                  _BannerCarousel(items: bannerItems, onTap: _handleBannerTap),

                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [const Color(0xFF1A1A1A), Colors.amber.shade900.withValues(alpha: 0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.stars_rounded, color: Colors.amber, size: 28),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'STELLA HAPPY WEDNESDAY',
                                style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Đồng giá 50K tất cả cụm rạp vào Thứ 4 hàng tuần. Đặt vé ngay!',
                                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 2. Search Bar – ValueNotifier thay setState
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TextField(
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Tìm tên phim Stella Cinema...',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54, size: 20),
                        filled: true,
                        fillColor: const Color(0xFF0A0A0A),
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      onChanged: (value) => _searchQuery.value = value,
                    ),
                  ),

                  // 3. Category selector chips trượt ngang
                  SizedBox(
                    height: 50,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: _categories.length,
                      itemBuilder: (context, index) {
                        final cat = _categories[index];
                        return ValueListenableBuilder<String>(
                          valueListenable: _selectedCategory,
                          builder: (_, selected, __) {
                            final isSel = selected == cat;
                            return GestureDetector(
                              onTap: () => _selectedCategory.value = cat,
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(
                                  color: isSel ? Colors.amber : const Color(0xFF0A0A0A),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: isSel ? Colors.white : Colors.white.withValues(alpha: 0.04)),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  cat,
                                  style: TextStyle(
                                    color: isSel ? Colors.black : Colors.white70,
                                    fontSize: 11,
                                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),

                  // 3.5. Gợi ý phim cá nhân hóa Stella AI
                  _buildRecommendationSection(),
                ],
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverAppBarDelegate(
                TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.amber,
                  indicatorWeight: 3,
                  labelColor: Colors.amber,
                  unselectedLabelColor: Colors.grey,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
                  tabs: const [
                    Tab(text: 'Đang Chiếu'),
                    Tab(text: 'Sắp Chiếu'),
                  ],
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildMovieGrid(isShowingNow: true),
            _buildMovieGrid(isShowingNow: false),
          ],
        ),
      ),
    );
  }

  Widget _buildMovieGrid({required bool isShowingNow}) {
    return ValueListenableBuilder<String>(
      valueListenable: _searchQuery,
      builder: (_, search, __) => ValueListenableBuilder<String>(
        valueListenable: _selectedCategory,
        builder: (_, category, __) => ref.watch(moviesProvider).when(
          data: (allMoviesList) {
            final filteredMovies = allMoviesList.where((data) {
              if (data['isDeleted'] == true) return false;
              final movieIsShowing = data['isShowingNow'] ?? true;
              if (movieIsShowing != isShowingNow) return false;
              final title = (data['title'] ?? '').toString().toLowerCase();
              final genre = (data['genre'] ?? '').toString().toLowerCase();
              final matchesSearch = title.contains(search.toLowerCase());
              final matchesCategory = category == 'Tất cả' || genre.contains(category.toLowerCase());
              return matchesSearch && matchesCategory;
            }).toList();

            if (filteredMovies.isEmpty) {
              return const Center(child: Text('Không tìm thấy phim phù hợp.', style: TextStyle(color: Colors.grey)));
            }

            return GridView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredMovies.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 20,
                crossAxisSpacing: 16,
                childAspectRatio: 0.58,
              ),
              itemBuilder: (context, index) {
                final movieData = filteredMovies[index];
                final title = movieData['title'] ?? 'Phim không tên';
                final genre = movieData['genre'] ?? 'Hành Động';
                final rating = movieData['rating'] ?? '9.8';
                final posterUrl = movieData['posterUrl'] ?? '';

                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => MovieDetailScreen(movieData: movieData)),
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0A0A),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 3))],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Hero(
                                  tag: 'movie-poster-$title',
                                  child: posterUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: posterUrl,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) => const Center(child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2)),
                                          errorWidget: (context, url, error) => const Icon(Icons.movie, size: 50, color: Colors.white24),
                                        )
                                      : const Icon(Icons.movie, size: 50, color: Colors.white24),
                                ),
                              ),
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)),
                                  child: const Text('2D | SUB', style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold)),
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.star_rounded, color: Colors.amber, size: 12),
                                      const SizedBox(width: 2),
                                      Text(rating, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                genre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.grey, fontSize: 11),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => ShowtimeSelectionScreen(movieData: movieData)),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.amber,
                                    foregroundColor: Colors.black,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                  child: const Text('Mua Vé', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: Colors.amber)),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _buildRecommendationSection() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF0A0A0A),
              const Color(0xFF121212).withValues(alpha: 0.8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.star_purple500_rounded, color: Colors.amber, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'GỢI Ý PHIM CHO BẠN',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Đăng nhập tài khoản Stella Cinema để chúng tôi phân tích gu điện ảnh của bạn và gợi ý những tựa phim phù hợp nhất!',
              style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 36,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'ĐĂNG NHẬP NGAY',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tickets')
          .where('email', isEqualTo: user.email)
          .snapshots(),
      builder: (context, ticketsSnapshot) {
        if (ticketsSnapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator(color: Colors.amber)),
          );
        }

        final tickets = ticketsSnapshot.data?.docs ?? [];

        return ref.watch(moviesProvider).when(
          data: (allMoviesList) {
            final allMovies = allMoviesList.where((d) => d['isDeleted'] != true).toList();
            if (allMovies.isEmpty) return const SizedBox.shrink();

            if (tickets.isEmpty) {
              final popularMovies = List<Map<String, dynamic>>.from(allMovies);
              popularMovies.sort((a, b) {
                final rA = double.tryParse(a['rating'] ?? '0') ?? 0.0;
                final rB = double.tryParse(b['rating'] ?? '0') ?? 0.0;
                return rB.compareTo(rA);
              });

              final recommendList = popularMovies.take(4).toList();

              return _buildRecommendedListWidget(
                movies: recommendList,
                reason: 'Khám phá ngay những siêu phẩm bom tấn được đánh giá cao nhất tại Stella!',
                title: 'PHIM NỔI BẬT DÀNH CHO BẠN',
              );
            }

            final Map<String, String> movieTitleToGenre = {};
            for (var data in allMovies) {
              final title = data['title'] as String? ?? '';
              final genre = data['genre'] as String? ?? 'Hành Động';
              if (title.isNotEmpty) {
                movieTitleToGenre[title.toLowerCase().trim()] = genre;
              }
            }

            final Map<String, int> genreCounts = {};
            for (var ticketDoc in tickets) {
              final ticketData = ticketDoc.data() as Map<String, dynamic>;
              final movieTitle = (ticketData['title'] as String? ?? '').toLowerCase().trim();
              final genre = movieTitleToGenre[movieTitle];
              if (genre != null) {
                final parts = genre.split(',').map((e) => e.trim()).toList();
                for (var part in parts) {
                  if (part.isNotEmpty) {
                    genreCounts[part] = (genreCounts[part] ?? 0) + 1;
                  }
                }
              }
            }

            String favoriteGenre = 'Hành Động';
            int maxCount = 0;
            genreCounts.forEach((genre, cnt) {
              if (cnt > maxCount) {
                maxCount = cnt;
                favoriteGenre = genre;
              }
            });

            final List<Map<String, dynamic>> matchingMovies = [];
            final List<Map<String, dynamic>> otherMovies = [];

            for (var data in allMovies) {
              final genre = (data['genre'] as String? ?? '').toLowerCase();
              if (genre.contains(favoriteGenre.toLowerCase())) {
                matchingMovies.add(data);
              } else {
                otherMovies.add(data);
              }
            }

            final watchedTitles = tickets
                .map((t) => (t.data() as Map<String, dynamic>)['title'] as String? ?? '')
                .map((e) => e.toLowerCase().trim())
                .toSet();

            final unwatchedMatchingMovies = matchingMovies.where((data) {
              final title = (data['title'] as String? ?? '').toLowerCase().trim();
              return !watchedTitles.contains(title);
            }).toList();

            final finalRecommendMovies = unwatchedMatchingMovies.isNotEmpty ? unwatchedMatchingMovies : matchingMovies;

            if (finalRecommendMovies.length < 2) {
              finalRecommendMovies.addAll(otherMovies.take(3 - finalRecommendMovies.length));
            }

            return _buildRecommendedListWidget(
              movies: finalRecommendMovies.take(5).toList(),
              reason: 'Vì bạn có niềm đam mê lớn với các tựa phim thuộc thể loại $favoriteGenre!',
              title: 'GỢI Ý CÁ NHÂN HÓA',
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _buildRecommendedListWidget({
    required List<Map<String, dynamic>> movies,
    required String reason,
    required String title,
  }) {
    if (movies.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A).withValues(alpha: 0.4),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
          top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.amber, Colors.orangeAccent],
                  ).createShader(bounds),
                  child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3), width: 0.5),
                  ),
                  child: const Text(
                    'Stella AI ✨',
                    style: TextStyle(
                      color: Colors.amber,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              reason,
              style: const TextStyle(
                color: Colors.amberAccent,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: movies.length,
              itemBuilder: (context, index) {
                final movieData = movies[index];
                final title = movieData['title'] ?? 'Phim không tên';
                final genre = movieData['genre'] ?? 'Hành Động';
                final rating = movieData['rating'] ?? '9.8';
                final posterUrl = movieData['posterUrl'] ?? '';

                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => MovieDetailScreen(movieData: movieData)),
                    );
                  },
                  child: Container(
                    width: 120,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF121212),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 4,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: posterUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: posterUrl,
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) => const Center(child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2)),
                                        errorWidget: (context, url, error) => const Icon(
                                          Icons.movie_creation_rounded,
                                          color: Colors.white24,
                                          size: 30,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.movie_creation_rounded,
                                        color: Colors.white24,
                                        size: 30,
                                      ),
                              ),
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.star_rounded, color: Colors.amber, size: 10),
                                      const SizedBox(width: 1),
                                      Text(
                                        rating,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(6.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                genre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 8,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: double.infinity,
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'ĐẶT NGAY',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);
  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: const Color(0xFF000000),
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}

enum _BannerAction { movie, combo, profile, voucher }

// ── Banner Carousel – widget độc lập, setState không lan lên HomeScreen ───────
class _BannerCarousel extends StatefulWidget {
  final List<_BannerItem> items;
  final void Function(_BannerItem) onTap;
  const _BannerCarousel({required this.items, required this.onTap});

  @override
  State<_BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<_BannerCarousel> {
  final PageController _ctrl = PageController();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _autoScroll();
  }

  void _autoScroll() {
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      _index = (_index + 1) % widget.items.length;
      if (_ctrl.hasClients) {
        _ctrl.animateToPage(_index,
            duration: const Duration(milliseconds: 800), curve: Curves.fastOutSlowIn);
      }
      _autoScroll();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: PageView.builder(
              controller: _ctrl,
              itemCount: widget.items.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, index) {
                final item = widget.items[index];
                return GestureDetector(
                  onTap: () => widget.onTap(item),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: item.imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: const Color(0xFF222232)),
                        errorWidget: (_, __, ___) => Container(
                          color: const Color(0xFF222232),
                          child: const Icon(Icons.movie_creation_rounded, color: Colors.white30, size: 48),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.3),
                              Colors.black.withValues(alpha: 0.85),
                            ],
                            stops: const [0.3, 0.6, 1.0],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16, right: 16, bottom: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: item.badgeColor, borderRadius: BorderRadius.circular(6)),
                              child: Text(item.badge,
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                            ),
                            const SizedBox(height: 6),
                            Text(item.title,
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 0.5,
                                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
                            const SizedBox(height: 4),
                            Text(item.subtitle,
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11, height: 1.3),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // Dots indicator
          Positioned(
            right: 12, bottom: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(widget.items.length, (i) {
                final active = i == _index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.only(left: 4),
                  width: active ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? Colors.amber : Colors.white38,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerItem {
  final String imageUrl;
  final String badge;
  final Color badgeColor;
  final String title;
  final String subtitle;
  final _BannerAction action;
  final String? movieTitle; // dùng khi action == movie
  final String? voucherCode; // dùng khi action == voucher

  const _BannerItem({
    required this.imageUrl,
    required this.badge,
    required this.badgeColor,
    required this.title,
    required this.subtitle,
    required this.action,
    this.movieTitle,
    this.voucherCode,
  });
}

// ── Pop-up quảng bá phim đang chiếu ─────────────────────────────────────────
class _PromoPopup extends StatefulWidget {
  final Map<String, dynamic> movieData;
  const _PromoPopup({required this.movieData});

  @override
  State<_PromoPopup> createState() => _PromoPopupState();
}

class _PromoPopupState extends State<_PromoPopup> {
  bool _dontShowAgain = false;

  Future<void> _close() async {
    if (_dontShowAgain) {
      final title = widget.movieData['title'] as String? ?? '';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('promo_dismissed_$title', true);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.movieData['title'] as String? ?? 'Phim đang chiếu';
    final genre = widget.movieData['genre'] as String? ?? '';
    final posterUrl = widget.movieData['posterUrl'] as String? ?? '';
    final rating = widget.movieData['rating']?.toString();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: posterUrl.isEmpty
                        ? Container(color: const Color(0xFF1E1E2A), child: const Icon(Icons.movie_rounded, color: Colors.white24, size: 60))
                        : CachedNetworkImage(
                            imageUrl: posterUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: const Color(0xFF1E1E2A)),
                            errorWidget: (_, __, ___) => Container(color: const Color(0xFF1E1E2A), child: const Icon(Icons.movie_rounded, color: Colors.white24, size: 60)),
                          ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: _close,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(6)),
                    child: const Text('ĐANG CHIẾU', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (rating != null) ...[
                        const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                        const SizedBox(width: 2),
                        Text(rating, style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(genre, style: const TextStyle(color: Colors.white54, fontSize: 12), overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Checkbox(
                    value: _dontShowAgain,
                    onChanged: (v) => setState(() => _dontShowAgain = v ?? false),
                    activeColor: Colors.amber,
                    side: const BorderSide(color: Colors.white38),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _dontShowAgain = !_dontShowAgain),
                      child: const Text('Không hiển thị lại thông báo này', style: TextStyle(color: Colors.white38, fontSize: 11)),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _close,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Để sau', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        if (_dontShowAgain) {
                          final title2 = widget.movieData['title'] as String? ?? '';
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('promo_dismissed_$title2', true);
                        }
                        if (!mounted) return;
                        navigator.pop(); // đóng pop-up
                        navigator.push(
                          MaterialPageRoute(builder: (_) => ShowtimeSelectionScreen(movieData: widget.movieData)),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('MUA NGAY', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
