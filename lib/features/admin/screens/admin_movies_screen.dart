import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/movies_provider.dart';
import 'admin_audit_log.dart';

class AdminMoviesScreen extends ConsumerWidget {
  const AdminMoviesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moviesAsync = ref.watch(moviesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text('QUẢN LÝ PHIM',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: Colors.amber, size: 24),
            onPressed: () => _showMovieDialog(context, null),
            tooltip: 'Thêm phim mới',
          ),
        ],
      ),
      body: moviesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.amber)),
        error: (e, _) => Center(child: Text('Lỗi: $e', style: const TextStyle(color: Colors.white))),
        data: (movies) {
          if (movies.isEmpty) {
            return const Center(
              child: Text('Chưa có phim nào.', style: TextStyle(color: Colors.white38)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: movies.length,
            itemBuilder: (context, i) => _MovieTile(movie: movies[i]),
          );
        },
      ),
    );
  }

  static void _showMovieDialog(BuildContext context, Movie? existing) {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final genreCtrl = TextEditingController(text: existing?.genre ?? '');
    final ratingCtrl = TextEditingController(text: existing?.rating ?? '');
    final posterCtrl = TextEditingController(text: existing?.posterUrl ?? '');
    final directorCtrl = TextEditingController(text: existing?.director ?? '');
    final castCtrl = TextEditingController(text: existing?.cast ?? '');
    final durationCtrl = TextEditingController(text: existing?.duration ?? '');
    final releaseDateCtrl = TextEditingController(text: existing?.releaseDate ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final trailerCtrl = TextEditingController(text: existing?.trailerUrl ?? '');
    bool isShowingNow = existing?.isShowingNow ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: const Color(0xFF16161F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            existing == null ? 'THÊM PHIM MỚI' : 'CHỈNH SỬA PHIM',
            style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field(titleCtrl, 'Tên phim *'),
                  _field(genreCtrl, 'Thể loại (vd: Hành Động, Kịch Tính)'),
                  _field(ratingCtrl, 'Rating (vd: 8.5)', inputType: TextInputType.number),
                  _field(posterCtrl, 'URL Poster'),
                  _field(directorCtrl, 'Đạo diễn'),
                  _field(castCtrl, 'Diễn viên'),
                  _field(durationCtrl, 'Thời lượng (vd: 130 phút)'),
                  _field(releaseDateCtrl, 'Ngày khởi chiếu (vd: 10/02/2024)'),
                  _field(descCtrl, 'Nội dung phim', maxLines: 3),
                  _field(trailerCtrl, 'URL Trailer YouTube (vd: https://youtu.be/xxxx)'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Switch(
                        value: isShowingNow,
                        onChanged: (v) => setState(() => isShowingNow = v),
                        activeColor: Colors.amber,
                      ),
                      Text(isShowingNow ? 'Đang chiếu' : 'Sắp chiếu',
                          style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('HỦY', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                final data = {
                  'title': titleCtrl.text.trim(),
                  'genre': genreCtrl.text.trim(),
                  'rating': ratingCtrl.text.trim(),
                  'posterUrl': posterCtrl.text.trim(),
                  'director': directorCtrl.text.trim(),
                  'cast': castCtrl.text.trim(),
                  'duration': durationCtrl.text.trim(),
                  'releaseDate': releaseDateCtrl.text.trim(),
                  'description': descCtrl.text.trim(),
                  'isShowingNow': isShowingNow,
                  'trailerUrl': trailerCtrl.text.trim(),
                };
                final col = FirebaseFirestore.instance.collection('movies');
                if (existing == null) {
                  final ref = await col.add(data);
                  await logAdminAction(action: 'create_movie', targetCollection: 'movies', targetId: ref.id, after: data);
                } else {
                  await col.doc(existing.id).update(data);
                  await logAdminAction(action: 'update_movie', targetCollection: 'movies', targetId: existing.id, before: existing.toMap(), after: data);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              child: Text(
                existing == null ? 'THÊM' : 'CẬP NHẬT',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _field(TextEditingController ctrl, String hint,
      {TextInputType inputType = TextInputType.text, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: inputType,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
          filled: true,
          fillColor: const Color(0xFF1E1E2A),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }
}

class _MovieTile extends StatelessWidget {
  final Movie movie;
  const _MovieTile({required this.movie});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF16161F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: movie.posterUrl.isNotEmpty
                ? Image.network(movie.posterUrl, width: 54, height: 76, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _posterPlaceholder())
                : _posterPlaceholder(),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(movie.title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text(movie.genre, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: movie.isShowingNow
                            ? Colors.green.withOpacity(0.15)
                            : Colors.blue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: movie.isShowingNow
                              ? Colors.green.withOpacity(0.4)
                              : Colors.blue.withOpacity(0.4),
                        ),
                      ),
                      child: Text(
                        movie.isShowingNow ? 'Đang chiếu' : 'Sắp chiếu',
                        style: TextStyle(
                          color: movie.isShowingNow ? Colors.greenAccent : Colors.lightBlueAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.star_rounded, color: Colors.amber, size: 13),
                    const SizedBox(width: 2),
                    Text(movie.rating, style: const TextStyle(color: Colors.amber, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          Column(
            children: [
              IconButton(
                icon: const Icon(Icons.edit_rounded, color: Colors.amber, size: 20),
                onPressed: () => AdminMoviesScreen._showMovieDialog(context, movie),
                tooltip: 'Chỉnh sửa',
              ),
              IconButton(
                icon: const Icon(Icons.delete_rounded, color: Colors.redAccent, size: 20),
                onPressed: () => _confirmDelete(context),
                tooltip: 'Xóa',
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('XÓA PHIM', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: Text('Bạn có chắc muốn xóa phim "${movie.title}"? Vé/đánh giá cũ vẫn được giữ lại, phim chỉ bị ẩn khỏi ứng dụng.',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('HỦY', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Soft delete: giữ document lại (tránh vé/đánh giá cũ tham
              // chiếu tới phim không còn tồn tại), chỉ ẩn khỏi mọi danh sách.
              await FirebaseFirestore.instance.collection('movies').doc(movie.id).update({
                'isDeleted': true,
                'deletedAt': Timestamp.now(),
              });
              await logAdminAction(action: 'delete_movie', targetCollection: 'movies', targetId: movie.id, before: movie.toMap());
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('XÓA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _posterPlaceholder() {
    return Container(
      width: 54,
      height: 76,
      color: const Color(0xFF1E1E2A),
      child: const Icon(Icons.movie_rounded, color: Colors.white24, size: 24),
    );
  }
}
