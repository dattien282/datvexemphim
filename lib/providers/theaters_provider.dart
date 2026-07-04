import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Theater {
  final String id;
  final String name;
  final String city;
  final String address;
  final double lat;
  final double lng;
  final String size;

  const Theater({
    required this.id,
    required this.name,
    required this.city,
    required this.address,
    required this.lat,
    required this.lng,
    this.size = 'Medium',
  });

  factory Theater.fromMap(String id, Map<String, dynamic> data) {
    return Theater(
      id: id,
      name: data['name'] ?? '',
      city: data['city'] ?? '',
      address: data['address'] ?? '',
      lat: (data['lat'] as num? ?? 0).toDouble(),
      lng: (data['lng'] as num? ?? 0).toDouble(),
      size: data['size'] as String? ?? 'Medium',
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'city': city,
        'address': address,
        'lat': lat,
        'lng': lng,
        'size': size,
      };
}

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
