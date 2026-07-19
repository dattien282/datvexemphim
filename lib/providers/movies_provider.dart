import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';

export '../models/movie.dart';

// Phim đã bị admin "xóa" (soft delete) vẫn giữ trong Firestore để không mồ
// côi các vé/đánh giá đã tham chiếu tới nó, chỉ ẩn khỏi mọi nơi hiển thị.
final moviesProvider = StreamProvider<List<Movie>>((ref) {
  return FirebaseFirestore.instance
      .collection('movies')
      .snapshots()
      .map((snap) => snap.docs.map((d) => Movie.fromDoc(d)).where((m) => !m.isDeleted).toList());
});

final nowShowingProvider = Provider<List<Movie>>((ref) {
  return ref.watch(moviesProvider).value?.where((m) => m.isShowingNow).toList() ?? [];
});

final comingSoonProvider = Provider<List<Movie>>((ref) {
  return ref.watch(moviesProvider).value?.where((m) => !m.isShowingNow).toList() ?? [];
});
