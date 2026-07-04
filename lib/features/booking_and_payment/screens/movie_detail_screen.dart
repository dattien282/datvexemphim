import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'showtime_selection_screen.dart';
import '../../auth/screens/login_screen.dart';

class MovieDetailScreen extends StatefulWidget {
  final Map<String, dynamic> movieData;
  const MovieDetailScreen({Key? key, required this.movieData}) : super(key: key);

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  final _reviewController = TextEditingController();
  double _selectedRating = 10.0;
  bool _isSubmittingReview = false;
  String _selectedSort = 'Mới nhất';

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  // Map tên phim → YouTube video ID
  static const Map<String, String> _trailerIds = {
    'Mai': 'EX6clvId19s',
    'Dune: Hành Tinh Cát - Phần 2': 'kCO-RO3q7U4',
    'Deadpool & Wolverine': 'inIVdZSFfc0',
    'Kẻ Trộm Mặt Trăng 4': 'S1dnnQsY0QU',
    'Inside Out 2': 'AfOlW2OrzqE',
    'Kung Fu Panda 4': 'py1BMJedzEs',
    'Godzilla x Kong: Đế Chế Mới': '5XkgG_AAQs0',
    'Avatar 3': 'rZXmSgjxpdQ',
  };

  String? _getVideoId() {
    final title = widget.movieData['title'] ?? '';
    // Ưu tiên map cứng
    if (_trailerIds.containsKey(title)) return _trailerIds[title];
    // Fallback: trích từ trailerUrl trong Firestore
    final url = widget.movieData['trailerUrl'] ?? '';
    return YoutubePlayer.convertUrlToId(url);
  }

  void _showTrailer(BuildContext context) {
    final videoId = _getVideoId();
    if (videoId == null || videoId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có trailer cho phim này.')),
      );
      return;
    }
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: true,
        fullscreenDialog: true,
        barrierColor: Colors.black,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        pageBuilder: (context, animation, secondaryAnimation) => _TrailerFullscreenPage(
          videoId: videoId,
          title: widget.movieData['title'] ?? '',
        ),
      ),
    );
  }

  void _submitReview() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showLoginWarning();
      return;
    }
    final text = _reviewController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập nội dung đánh giá!'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    setState(() => _isSubmittingReview = true);
    try {
      // Chỉ cho phép đánh giá nếu tài khoản đã có vé COMPLETED cho đúng phim
      // này - trước đây bất kỳ ai đăng nhập cũng review được phim bất kỳ mà
      // chưa từng mua vé, dễ bị spam review ảo. ticketId được ghim vào review
      // để firestore.rules xác minh lại đúng điều kiện này ở server, không
      // chỉ chặn ở UI.
      final ticketSnap = await FirebaseFirestore.instance
          .collection('tickets')
          .where('userId', isEqualTo: user.uid)
          .where('movieTitle', isEqualTo: widget.movieData['title'])
          .where('paymentStatus', isEqualTo: 'COMPLETED')
          .limit(1)
          .get();
      if (ticketSnap.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bạn cần đã xem phim này (có vé đã thanh toán) mới được đánh giá.'), backgroundColor: Colors.orangeAccent),
          );
        }
        return;
      }

      await FirebaseFirestore.instance.collection('movie_reviews').add({
        'movieTitle': widget.movieData['title'],
        'email': user.email,
        'ticketId': ticketSnap.docs.first.id,
        'rating': _selectedRating,
        'comment': text,
        'created_at': Timestamp.now(),
        'likes': [],
      });
      _reviewController.clear();
      setState(() {
        _selectedRating = 10.0;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã gửi đánh giá của bạn thành công! ⭐'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi gửi đánh giá: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isSubmittingReview = false);
    }
  }

  void _toggleLikeReview(String reviewId, List<dynamic> currentLikes) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showLoginWarning();
      return;
    }
    final email = user.email;
    if (email == null) return;
    
    final docRef = FirebaseFirestore.instance.collection('movie_reviews').doc(reviewId);
    if (currentLikes.contains(email)) {
      await docRef.update({
        'likes': FieldValue.arrayRemove([email]),
      });
    } else {
      await docRef.update({
        'likes': FieldValue.arrayUnion([email]),
      });
    }
  }

  void _showLoginWarning() {
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
  }

  bool _checkLoginRequirement(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showLoginWarning();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.movieData['title'] ?? 'Không có tên';
    final genre = widget.movieData['genre'] ?? 'Chưa rõ';
    final rating = widget.movieData['rating'] ?? '0.0';
    final String ageRating = (widget.movieData['ageRating'] ?? '').toString();
    final String country = (widget.movieData['country'] ?? '').toString();
    final String cast = (widget.movieData['cast'] ?? '').toString();
    final posterUrl = widget.movieData['posterUrl'] ?? '';
    final description = widget.movieData['description'] ??
        'Bộ phim tâm lý kịch tính xuất sắc nhất năm, mang lại nhiều cung bậc cảm xúc cho khán giả với những cú twist bất ngờ và diễn xuất đỉnh cao của dàn diễn viên.';
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 400,
            pinned: true,
            backgroundColor: const Color(0xFF121212),
            iconTheme: const IconThemeData(color: Colors.white),
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: GestureDetector(
                onTap: () => _showTrailer(context),
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: Hero(
                        tag: 'movie-poster-$title',
                        child: posterUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: posterUrl,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => const Center(child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2)),
                                errorWidget: (context, url, error) => const Icon(Icons.movie, size: 100, color: Colors.white54),
                              )
                            : const Icon(Icons.movie, size: 100, color: Colors.white54),
                      ),
                    ),
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.amber, width: 2),
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.amber, size: 34),
                    ),
                    Positioned(
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                        child: const Text('Chạm để xem trailer', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    )
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 80.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          genre,
                          style: const TextStyle(color: Colors.blueAccent, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (ageRating.isNotEmpty && ageRating != 'Chưa rõ')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: _ageRatingColor(ageRating).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _ageRatingColor(ageRating)),
                          ),
                          child: Text(
                            ageRating,
                            style: TextStyle(color: _ageRatingColor(ageRating), fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 20),
                          const SizedBox(width: 4),
                          Text(
                            rating,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (country.isNotEmpty || cast.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (country.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.public_rounded, color: Colors.amber, size: 16),
                                  const SizedBox(width: 8),
                                  const Text('Quốc gia: ', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                                  Expanded(child: Text(country, style: const TextStyle(color: Colors.white, fontSize: 12))),
                                ],
                              ),
                            ),
                          if (cast.isNotEmpty)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.people_alt_rounded, color: Colors.amber, size: 16),
                                const SizedBox(width: 8),
                                const Text('Diễn viên: ', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                                Expanded(child: Text(cast, style: const TextStyle(color: Colors.white, fontSize: 12))),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'Nội dung phim',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: const TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
                  ),
                  
                  const Divider(color: Colors.white10, height: 40),

                  const Text(
                    'ĐÁNH GIÁ TỪ CỘNG ĐỒNG',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 16),

                  if (user != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0A0A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Số sao đánh giá:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                              Row(
                                children: [
                                  DropdownButton<double>(
                                    dropdownColor: const Color(0xFF0A0A0A),
                                    value: _selectedRating,
                                    style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                                    items: List.generate(10, (index) => (index + 1).toDouble()).map((val) {
                                      return DropdownMenuItem(value: val, child: Text('$val ⭐'));
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) setState(() => _selectedRating = val);
                                    },
                                  ),
                                ],
                              )
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _reviewController,
                            maxLines: 2,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Nhập bình luận của bạn về phim...',
                              hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                              filled: true,
                              fillColor: const Color(0xFF121212),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 38,
                            child: ElevatedButton(
                              onPressed: _isSubmittingReview ? null : _submitReview,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                elevation: 0,
                              ),
                              child: _isSubmittingReview
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                                  : const Text('GỬI ĐÁNH GIÁ', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ] else ...[
                    Center(
                      child: TextButton(
                        onPressed: _showLoginWarning,
                        child: const Text('🔒 Đăng nhập để bình luận về bộ phim này', style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'ĐÁNH GIÁ TỪ CỘNG ĐỒNG',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                      DropdownButton<String>(
                        dropdownColor: const Color(0xFF0A0A0A),
                        value: _selectedSort,
                        style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold),
                        underline: const SizedBox(),
                        icon: const Icon(Icons.sort_rounded, color: Colors.amber, size: 14),
                        items: ['Mới nhất', 'Đánh giá cao', 'Được thích nhiều'].map((sort) {
                          return DropdownMenuItem(value: sort, child: Text('$sort  '));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedSort = val);
                          }
                        },
                      )
                    ],
                  ),
                  const SizedBox(height: 10),

                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('movie_reviews')
                        .where('movieTitle', isEqualTo: title)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: Colors.amber));
                      }
                      final List<QueryDocumentSnapshot> reviews = snapshot.hasData ? snapshot.data!.docs : [];
                      if (reviews.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20.0),
                          child: Center(
                            child: Text('Chưa có đánh giá nào. Hãy là người đầu tiên đánh giá phim!', style: TextStyle(color: Colors.grey, fontSize: 11)),
                          ),
                        );
                      }

                      // Sắp xếp trong bộ nhớ để tránh lỗi Index Firestore
                      final List<QueryDocumentSnapshot> sortedReviews = List.from(reviews);
                      if (_selectedSort == 'Đánh giá cao') {
                        sortedReviews.sort((a, b) {
                          final aData = a.data() as Map<String, dynamic>;
                          final bData = b.data() as Map<String, dynamic>;
                          final double aVal = (aData['rating'] ?? 0).toDouble();
                          final double bVal = (bData['rating'] ?? 0).toDouble();
                          return bVal.compareTo(aVal);
                        });
                      } else if (_selectedSort == 'Được thích nhiều') {
                        sortedReviews.sort((a, b) {
                          final aData = a.data() as Map<String, dynamic>;
                          final bData = b.data() as Map<String, dynamic>;
                          final int aLikes = ((aData['likes'] as List?) ?? []).length;
                          final int bLikes = ((bData['likes'] as List?) ?? []).length;
                          return bLikes.compareTo(aLikes);
                        });
                      } else {
                        sortedReviews.sort((a, b) {
                          final aData = a.data() as Map<String, dynamic>;
                          final bData = b.data() as Map<String, dynamic>;
                          final Timestamp aTime = aData['created_at'] ?? Timestamp.now();
                          final Timestamp bTime = bData['created_at'] ?? Timestamp.now();
                          return bTime.compareTo(aTime);
                        });
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: sortedReviews.length,
                        itemBuilder: (context, index) {
                          final reviewData = sortedReviews[index].data() as Map<String, dynamic>;
                          final emailStr = reviewData['email'] ?? 'Ẩn danh';
                          final comment = reviewData['comment'] ?? '';
                          final ratingVal = reviewData['rating'] ?? 10.0;
                          final initials = emailStr.isNotEmpty ? emailStr.substring(0, 2).toUpperCase() : 'US';
                          final List<dynamic> likesList = reviewData['likes'] ?? [];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0A0A0A),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: Colors.amber.withValues(alpha: 0.1),
                                  child: Text(initials, style: const TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(emailStr, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              GestureDetector(
                                                onTap: () {
                                                  final reviewId = sortedReviews[index].id;
                                                  _toggleLikeReview(reviewId, likesList);
                                                },
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      likesList.contains(FirebaseAuth.instance.currentUser?.email)
                                                          ? Icons.favorite_rounded
                                                          : Icons.favorite_border_rounded,
                                                      color: Colors.redAccent,
                                                      size: 14,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '${likesList.length}',
                                                      style: const TextStyle(color: Colors.white60, fontSize: 10),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(4)),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.star, color: Colors.black, size: 10),
                                                    const SizedBox(width: 2),
                                                    Text('$ratingVal', style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold)),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(comment, style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.4)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          )
        ],
      ),
      // Phim "sắp chiếu" (isShowingNow == false) chỉ để xem thông tin, chưa
      // mở bán vé - ẩn nút đặt vé, thay bằng nhãn trạng thái để không tạo
      // cảm giác nút bị lỗi/không bấm được.
      bottomNavigationBar: (widget.movieData['isShowingNow'] == false)
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Text(
                      'PHIM SẮP CHIẾU - CHƯA MỞ BÁN VÉ',
                      style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                  ),
                ),
              ),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ShowtimeSelectionScreen(movieData: widget.movieData),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'ĐẶT VÉ NGAY',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  // Màu theo phân loại độ tuổi phim Việt Nam: P (mọi lứa tuổi) → K (dưới 13
  // cần người lớn đi kèm) → T13/T16/T18 tăng dần mức độ hạn chế.
  Color _ageRatingColor(String ageRating) {
    switch (ageRating.toUpperCase()) {
      case 'P':
        return Colors.greenAccent;
      case 'K':
        return Colors.lightBlueAccent;
      case 'T13':
        return Colors.amber;
      case 'T16':
        return Colors.orangeAccent;
      case 'T18':
        return Colors.redAccent;
      default:
        return Colors.white54;
    }
  }
}

// ── Trang trailer YouTube toàn màn hình (nền đen tuyền, không mờ/thấy trang
// phía sau) ─────────────────────────────────────────────────────────────
class _TrailerFullscreenPage extends StatefulWidget {
  final String videoId;
  final String title;
  const _TrailerFullscreenPage({required this.videoId, required this.title});

  @override
  State<_TrailerFullscreenPage> createState() => _TrailerFullscreenPageState();
}

class _TrailerFullscreenPageState extends State<_TrailerFullscreenPage> {
  late YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController(
      initialVideoId: widget.videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        // enableCaption:false chỉ gửi gợi ý cc_load_policy=0 lên YouTube -
        // với video nào nhà phát hành đặt phụ đề "luôn hiện" thì YouTube vẫn
        // tự bật bất kể cờ này. Bật enableCaption để hiện nút CC, cho người
        // xem tự tắt thủ công trong trình phát khi gặp trường hợp đó.
        enableCaption: true,
        forceHD: false,
        hideThumbnail: true,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.play_circle_rounded, color: Colors.amber, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title.toUpperCase(),
                      style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 22),
                    onPressed: () {
                      _controller.pause();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            // Player - căn giữa màn hình, chiếm trọn chiều rộng
            Expanded(
              child: Center(
                child: YoutubePlayer(
                  controller: _controller,
                  showVideoProgressIndicator: true,
                  progressIndicatorColor: Colors.amber,
                  progressColors: const ProgressBarColors(
                    playedColor: Colors.amber,
                    handleColor: Colors.amberAccent,
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white12,
                  ),
                  onReady: () => _controller.play(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
