import 'package:flutter/material.dart';
import '../widgets/banner_carousel.dart';
import '../widgets/promo_popup.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
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

  final List<BannerItem> bannerItems = const [
    BannerItem(
      imageUrl: 'https://images.unsplash.com/photo-1542204165-65bf26472b9b?w=800&q=80',
      badge: 'THỨ 4 VUI VẺ',
      badgeColor: Color(0xFFE91E63),
      title: 'HAPPY WEDNESDAY',
      subtitle: 'Giảm 10% toàn bộ giao dịch đặt vé vào Thứ 4 hàng tuần',
      action: BannerAction.combo,
    ),
    BannerItem(
      imageUrl: 'https://images.unsplash.com/photo-1557672172-298e090bd0f1?w=800&q=80',
      badge: 'VOUCHER',
      badgeColor: Color(0xFF00B0FF),
      title: 'MÙA HÈ SÔI ĐỘNG',
      subtitle: 'Nhập mã MUAHE2024 giảm ngay 20K. Bấm để sao chép!',
      action: BannerAction.voucher,
      voucherCode: 'MUAHE2024',
    ),
    BannerItem(
      imageUrl: 'https://media.themoviedb.org/t/p/w600_and_h900_face/z8OWDTR7pQuZi7jkEuR7yMXRrQt.jpg',
      badge: 'ĐANG CHIẾU',
      badgeColor: Color(0xFFE53935),
      title: 'MINIONS & QUÁI VẬT',
      subtitle: 'Phiêu Lưu, Hoạt Hình, Hài, Gia Đình',
      action: BannerAction.movie,
      movieTitle: 'Minions & Quái Vật',
    ),
    BannerItem(
      imageUrl: 'https://en.wikipedia.org/wiki/Special:FilePath/The_Odyssey_(2026_film)_poster.jpg',
      badge: 'SẮP CHIẾU',
      badgeColor: Color(0xFF1565C0),
      title: 'THE ODYSSEY',
      subtitle: 'Christopher Nolan • Sử Thi, Phiêu Lưu',
      action: BannerAction.movie,
      movieTitle: 'The Odyssey',
    ),
    BannerItem(
      imageUrl: 'https://en.wikipedia.org/wiki/Special:FilePath/Spider-Man_Brand_New_Day_poster.jpg',
      badge: 'HOT',
      badgeColor: Color(0xFFFF6F00),
      title: 'SPIDER-MAN: KHỞI ĐẦU MỚI',
      subtitle: 'Tom Holland • Hành Động, Siêu Anh Hùng',
      action: BannerAction.movie,
      movieTitle: 'Spider-Man: Khởi Đầu Mới',
    ),
    BannerItem(
      imageUrl: 'https://images.unsplash.com/photo-1585647347483-22b66260dfff?w=800&q=80',
      badge: 'KHUYẾN MÃI',
      badgeColor: Color(0xFF2E7D32),
      title: 'THỨ 4 VUI VẺ',
      subtitle: 'Đồng giá vé 70K toàn hệ thống (Áp dụng cho mọi khung giờ) 🥳',
      action: BannerAction.combo,
    ),
    BannerItem(
      imageUrl: 'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?w=800&q=80',
      badge: 'ƯU ĐÃI THÀNH VIÊN',
      badgeColor: Color(0xFF6A1B9A),
      title: 'STELLA MEMBER VIP',
      subtitle: 'Tích điểm mỗi vé • Đổi quà hấp dẫn • Ưu tiên chỗ ngồi',
      action: BannerAction.profile,
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
        builder: (_) => PromoPopup(movieData: movieData),
      );
    } catch (_) {
      // Không chặn màn hình chính nếu lỗi mạng/query - pop-up chỉ là gợi ý phụ.
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

  void _handleBannerTap(BannerItem item) async {
    switch (item.action) {
      case BannerAction.movie:
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

      case BannerAction.combo:
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

      case BannerAction.profile:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MembershipScreen()),
        );
        break;
      case BannerAction.voucher:
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
                  BannerCarousel(items: bannerItems, onTap: _handleBannerTap),

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
                          builder: (_, selected, _) {
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
      builder: (_, search, _) => ValueListenableBuilder<String>(
        valueListenable: _selectedCategory,
        builder: (_, category, _) => ref.watch(moviesProvider).when(
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
          // Hiện lỗi thật thay vì khoảng trống câm - trước đây lỗi đọc phim
          // (mạng/quyền/đầy bộ nhớ máy...) làm lưới phim trắng trơn không dấu
          // vết gì, không thể chẩn đoán được người dùng đang gặp chuyện gì.
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Không tải được danh sách phim:\n$e',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12, height: 1.5),
              ),
            ),
          ),
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
          error: (_, _) => const SizedBox.shrink(),
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

