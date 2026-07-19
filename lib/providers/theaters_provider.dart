import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/theater.dart';

export '../models/theater.dart';


/// Streams all theaters, ordered by name. Single source of truth replacing
/// the theater name lists that used to be hardcoded independently across
/// admin_users_screen.dart, showtime_selection_screen.dart, admin_revenue_screen.dart
/// and theater_maps_screen.dart.
final theatersProvider = StreamProvider<List<Theater>>((ref) {
  return FirebaseFirestore.instance
      .collection('theaters')
      .orderBy('name')
      .snapshots()
      .map((snap) => snap.docs.map((d) => Theater.fromMap(d.id, d.data())).toList());
});

/// Just the names, for simple dropdowns.
final theaterNamesProvider = Provider<List<String>>((ref) {
  final theaters = ref.watch(theatersProvider).valueOrNull ?? const [];
  return theaters.map((t) => t.name).toList();
});

/// Single-theater lookup by name (theaters.name is the join key used
/// everywhere else in this schema, e.g. users.assignedTheater).
final theaterByNameProvider = Provider.family<Theater?, String?>((ref, name) {
  if (name == null) return null;
  final theaters = ref.watch(theatersProvider).valueOrNull ?? const [];
  for (final t in theaters) {
    if (t.name == name) return t;
  }
  return null;
});
