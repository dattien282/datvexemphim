import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final movieRepositoryProvider = Provider<MovieRepository>((ref) {
  return MovieRepository();
});

class MovieRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _cacheKey = 'movies_cache';

  // Lấy dữ liệu với cơ chế Cache (Đọc từ đĩa trước, sau đó fetch mạng)
  Stream<List<Map<String, dynamic>>> getMoviesStream() async* {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Đọc từ Cache (Load tức thì)
    final cachedData = prefs.getString(_cacheKey);
    if (cachedData != null) {
      try {
        final List<dynamic> decodedList = jsonDecode(cachedData);
        final List<Map<String, dynamic>> cachedMovies = List<Map<String, dynamic>>.from(decodedList);
        yield cachedMovies;
      } catch (e) {
        // Lỗi parse json, bỏ qua cache
      }
    }

    // 2. Fetch dữ liệu thật từ Firebase và cập nhật Cache
    yield* _firestore.collection('movies').snapshots().map((snapshot) {
      final movies = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id; // Lưu lại ID vào map
        return data;
      }).toList();
      
      // Lưu vào cache để lần sau dùng
      prefs.setString(_cacheKey, jsonEncode(movies));
      return movies;
    });
  }
}
