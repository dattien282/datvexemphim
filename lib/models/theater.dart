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
