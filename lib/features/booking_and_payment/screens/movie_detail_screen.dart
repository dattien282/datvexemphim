import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
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

  void _showSimulatedTrailer(BuildContext context) {
    bool isPlaying = true;
    double progress = 0.08; 
    double volume = 0.8;
    bool isMuted = false;
    int currentSecs = 12;
    const int totalSecs = 150; 

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final minutes = (currentSecs ~/ 60).toString().padLeft(2, '0');
            final seconds = (currentSecs % 60).toString().padLeft(2, '0');
            
            final totalMinutes = (totalSecs ~/ 60).toString().padLeft(2, '0');
            final totalSeconds = (totalSecs % 60).toString().padLeft(2, '0');

            return Dialog(
              backgroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    title: Text(
                      'TRAILER: ${widget.movieData['title']}',
                      style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    automaticallyImplyLeading: false,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                  
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            image: DecorationImage(
                              image: NetworkImage(widget.movieData['posterUrl'] ?? ''),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Container(color: Colors.black.withValues(alpha: isMuted ? 0.9 : 0.6)),
                        
                        GestureDetector(
                          onTap: () {
                            setDialogState(() {
                              isPlaying = !isPlaying;
                            });
                          },
                          child: Icon(
                            isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                            color: Colors.amber,
                            size: 60,
                          ),
                        ),

                        Positioned(
                          bottom: 12,
                          left: 12,
                          right: 12,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('$minutes:$seconds', style: const TextStyle(color: Colors.white70, fontSize: 10)),
                                  Text('$totalMinutes:$totalSeconds', style: const TextStyle(color: Colors.white70, fontSize: 10)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  activeTrackColor: Colors.amber,
                                  inactiveTrackColor: Colors.white24,
                                  thumbColor: Colors.amber,
                                ),
                                child: Slider(
                                  value: progress,
                                  onChanged: (val) {
                                    setDialogState(() {
                                      progress = val;
                                      currentSecs = (val * totalSecs).toInt();
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                color: Colors.white70,
                                size: 20,
                              ),
                              onPressed: () {
                                setDialogState(() {
                                  isMuted = !isMuted;
                                });
                              },
                            ),
                            if (!isMuted)
                              SizedBox(
                                width: 60,
                                child: Slider(
                                  value: volume,
                                  activeColor: Colors.amber,
                                  inactiveColor: Colors.white24,
                                  onChanged: (val) {
                                    setDialogState(() {
                                      volume = val;
                                      if (val == 0) {
                                        isMuted = true;
                                      } else {
                                        isMuted = false;
                                      }
                                    });
                                  },
                                ),
                              )
                          ],
                        ),

                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.replay_10_rounded, color: Colors.white70, size: 22),
                              onPressed: () {
                                setDialogState(() {
                                  currentSecs = (currentSecs - 10 < 0) ? 0 : currentSecs - 10;
                                  progress = currentSecs / totalSecs;
                                });
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.amber,
                                size: 30,
                              ),
                              onPressed: () {
                                setDialogState(() {
                                  isPlaying = !isPlaying;
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.forward_10_rounded, color: Colors.white70, size: 22),
                              onPressed: () {
                                setDialogState(() {
                                  currentSecs = (currentSecs + 10 > totalSecs) ? totalSecs : currentSecs + 10;
                                  progress = currentSecs / totalSecs;
                                });
                              },
                            ),
                          ],
                        ),

                        const SizedBox(width: 40), 
                      ],
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
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
      await FirebaseFirestore.instance.collection('movie_reviews').add({
        'movieTitle': widget.movieData['title'],
        'email': user.email,
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
          backgroundColor: const Color(0xFF16161F),
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
            backgroundColor: const Color(0xFF1E1E2A),
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              background: GestureDetector(
                onTap: () => _showSimulatedTrailer(context),
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
                  Row(
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
                      const SizedBox(width: 16),
                      const Icon(Icons.star, color: Colors.amber, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        rating,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
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
                        color: const Color(0xFF16161F),
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
                                    dropdownColor: const Color(0xFF16161F),
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
                              fillColor: const Color(0xFF1E1E2A),
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
                        dropdownColor: const Color(0xFF16161F),
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
                              color: const Color(0xFF16161F),
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
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2A),
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                if (_checkLoginRequirement(context)) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ShowtimeSelectionScreen(movieData: widget.movieData),
                    ),
                  );
                }
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
}