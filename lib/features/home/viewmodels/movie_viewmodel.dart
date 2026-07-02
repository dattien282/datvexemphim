import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/movie_repository.dart';

final moviesProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final repository = ref.watch(movieRepositoryProvider);
  return repository.getMoviesStream();
});
