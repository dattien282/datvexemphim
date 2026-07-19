import 'package:cloud_firestore/cloud_firestore.dart';

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
  final String ageRating; // Phân loại độ tuổi: P, K, T13, T16, T18...
  final String country; // Quốc gia sản xuất
  final bool isShowingNow;
  final bool isDeleted;

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
    this.ageRating = '',
    this.country = '',
    required this.isShowingNow,
    this.isDeleted = false,
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
      ageRating: (d['ageRating'] ?? '').toString(),
      country: (d['country'] ?? '').toString(),
      isShowingNow: d['isShowingNow'] == true,
      isDeleted: d['isDeleted'] == true,
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
        'ageRating': ageRating,
        'country': country,
        'isShowingNow': isShowingNow,
        'isDeleted': isDeleted,
      };
}
