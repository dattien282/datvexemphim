import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Movie {
  final String id;
  final String title;
  final String genre;
  final String rating;
  final String posterUrl;
  final String trailerUrl;
  final String director;
  final String cast;
  final String duration;
  final String releaseDate;
  final String description;
  final bool isShowingNow;

  const Movie({
    required this.id,
    required this.title,
    required this.genre,
    required this.rating,
    required this.posterUrl,
    required this.trailerUrl,
    required this.director,
    required this.cast,
    required this.duration,
    required this.releaseDate,
    required this.description,
    required this.isShowingNow,
  });

  factory Movie.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Movie(
      id: doc.id,
      title: d['title'] ?? '',
      genre: d['genre'] ?? '',
      rating: (d['rating'] ?? '0').toString(),
      posterUrl: d['posterUrl'] ?? '',
      trailerUrl: d['trailerUrl'] ?? '',
      director: d['director'] ?? '',
      cast: d['cast'] ?? '',
      duration: (d['duration'] ?? '').toString(),
      releaseDate: (d['releaseDate'] ?? '').toString(),
      description: d['description'] ?? '',
      isShowingNow: d['isShowingNow'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'genre': genre,
        'rating': rating,
        'posterUrl': posterUrl,
        'trailerUrl': trailerUrl,
        'director': director,
        'cast': cast,
        'duration': duration,
        'releaseDate': releaseDate,
        'description': description,
        'isShowingNow': isShowingNow,
      };
}

final moviesProvider = StreamProvider<List<Movie>>((ref) {
  return FirebaseFirestore.instance
      .collection('movies')
      .snapshots()
      .map((snap) => snap.docs.map((d) => Movie.fromDoc(d)).toList());
});

final nowShowingProvider = Provider<List<Movie>>((ref) {
  return ref.watch(moviesProvider).value?.where((m) => m.isShowingNow).toList() ?? [];
});

final comingSoonProvider = Provider<List<Movie>>((ref) {
  return ref.watch(moviesProvider).value?.where((m) => !m.isShowingNow).toList() ?? [];
});
