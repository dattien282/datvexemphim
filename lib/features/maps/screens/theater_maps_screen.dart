import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

class TheaterMapsScreen extends StatefulWidget {
  const TheaterMapsScreen({super.key});

  @override
  State<TheaterMapsScreen> createState() => _TheaterMapsScreenState();
}

class _TheaterMapsScreenState extends State<TheaterMapsScreen> {
  GoogleMapController? _mapController;
  Position? _userPosition;
  bool _isLoadingLocation = true;
  String _selectedCity = 'Tất cả';

  final List<String> _cities = ['Tất cả', 'Hồ Chí Minh', 'Hà Nội', 'Đà Nẵng', 'Cần Thơ'];

  // DANH SACH RAP STELLA DUOC DONG BO TOA DO THUC TE DE TEST GOOGLE MAPS
  final List<Map<String, dynamic>> _allTheaters = [
    {
      'id': 'stella_nguyen_du',
      'name': 'STELLA CINEMA NGUYỄN DU',
      'address': 'Số 116 Nguyễn Du, Phường Bến Thành, Quận 1, TP. Hồ Chí Minh',
      'city': 'Hồ Chí Minh',
      'lat': 10.77303,
      'lng': 106.69341,
      'image': 'https://images.unsplash.com/photo-1517604931442-7e0c8ed2963c?q=80&w=600&auto=format&fit=crop',
    },
    {
      'id': 'stella_van_hanh',
      'name': 'STELLA CINEMA VẠN HẠNH MALL',
      'address': 'Tầng 6, Vạn Hạnh Mall, 11 Sư Vạn Hạnh, Quận 10, TP. Hồ Chí Minh',
      'city': 'Hồ Chí Minh',
      'lat': 10.77055,
      'lng': 106.66954,
      'image': 'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?q=80&w=600&auto=format&fit=crop',
    },
    {
      'id': 'stella_mipec',
      'name': 'STELLA CINEMA MIPEC LONG BIÊN',
      'address': 'Tầng 5, TTTM Mipec Long Biên, số 2 Long Biên 2, Ngọc Lâm, Long Biên, Hà Nội',
      'city': 'Hà Nội',
      'lat': 21.04535,
      'lng': 105.86649,
      'image': 'https://images.unsplash.com/photo-1536440136628-849c177e76a1?q=80&w=600&auto=format&fit=crop',
    },
    {
      'id': 'stella_da_nang',
      'name': 'STELLA CINEMA ĐÀ NẴNG',
      'address': 'TTTM CoopMart, 478 Điện Biên Phủ, Thanh Khê, Đà Nẵng',
      'city': 'Đà Nẵng',
      'lat': 16.0620,
      'lng': 108.1885,
      'image': 'https://images.unsplash.com/photo-1574267432553-4b4628081c31?q=80&w=600&auto=format&fit=crop',
    },
    {
      'id': 'stella_can_tho',
      'name': 'STELLA CINEMA CẦN THƠ',
      'address': 'Tầng 2, TTTM Sense City, số 1 Đại Lộ Hòa Bình, Ninh Kiều, Cần Thơ',
      'city': 'Cần Thơ',
      'lat': 10.0355,
      'lng': 105.7836,
      'image': 'https://images.unsplash.com/photo-1440404653325-ab127d49abc1?q=80&w=600&auto=format&fit=crop',
    }
  ];

  List<Map<String, dynamic>> _processedTheaters = [];

  @override
  void initState() {
    super.initState();
    _processedTheaters = List.from(_allTheaters);
    _determineUserPosition();
  }

  // FIX DA XONG: Dung LocationSettings de diet triet de warning 'desiredAccuracy is deprecated'
  Future<void> _determineUserPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _isLoadingLocation = false);
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _isLoadingLocation = false);
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _isLoadingLocation = false);
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    _userPosition = position;
    _calculateDistancesAndSort();
  }

  void _calculateDistancesAndSort() {
    if (_userPosition == null) return;

    for (var theater in _allTheaters) {
      double distanceInMeters = Geolocator.distanceBetween(
        _userPosition!.latitude,
        _userPosition!.longitude,
        theater['lat'],
        theater['lng'],
      );
      double km = distanceInMeters / 1000;
      theater['distanceKM'] = km;
      theater['timeMins'] = (km * 2.5).ceil();
    }

    _filterAndSortTheaters();
  }

  void _filterAndSortTheaters() {
    List<Map<String, dynamic>> filtered = _allTheaters.where((theater) {
      if (_selectedCity == 'Tất cả') return true;
      return theater['city'] == _selectedCity;
    }).toList();

    if (_userPosition != null) {
      filtered.sort((a, b) => (a['distanceKM'] ?? 0).compareTo(b['distanceKM'] ?? 0));
    }

    setState(() {
      _processedTheaters = filtered;
      _isLoadingLocation = false;
    });

    if (_processedTheaters.isNotEmpty && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_processedTheaters[0]['lat'], _processedTheaters[0]['lng']),
          12,
        ),
      );
    }
  }

  Future<void> _launchDirections(double lat, double lng) async {
    final Uri url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFE53935),
            content: Text('Không thể mở Google Maps: $e', style: const TextStyle(color: Colors.white)),
          ),
        );
      }
    }
  }

  // FIX DA XONG: Tra ve hueOrange chuan ho phach, xoa bo hueAmber loi
  Set<Marker> _createMarkers() {
    return _processedTheaters.map((theater) {
      return Marker(
        markerId: MarkerId(theater['id']),
        position: LatLng(theater['lat'], theater['lng']),
        infoWindow: InfoWindow(title: theater['name'], snippet: theater['address']),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      );
    }).toSet();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'HỆ THỐNG RẠP STELLA',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Container(
            height: 55,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            color: const Color(0xFF16161F),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _cities.length,
              itemBuilder: (context, index) {
                final city = _cities[index];
                final isSelected = _selectedCity == city;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedCity = city;
                      _filterAndSortTheaters();
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.amber : const Color(0xFF222232),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: isSelected
                          ? [BoxShadow(color: Colors.amber.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      city,
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white70,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          Expanded(
            flex: 3,
            child: Stack(
              children: [
                GoogleMap(
                  onMapCreated: (controller) {
                    _mapController = controller;
                    if (_processedTheaters.isNotEmpty) {
                      _mapController!.animateCamera(
                        CameraUpdate.newLatLngZoom(LatLng(_processedTheaters[0]['lat'], _processedTheaters[0]['lng']), 11),
                      );
                    }
                  },
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(10.7745, 106.6942),
                    zoom: 11,
                  ),
                  markers: _createMarkers(),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                ),
                if (_isLoadingLocation)
                  Container(
                    color: Colors.black45,
                    child: const Center(child: CircularProgressIndicator(color: Colors.amber)),
                  ),
              ],
            ),
          ),

          Expanded(
            flex: 4,
            child: Container(
              color: const Color(0xFF0F0F13),
              child: _processedTheaters.isEmpty
                  ? const Center(child: Text('Không tìm thấy rạp Stella ở khu vực này.', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: _processedTheaters.length,
                itemBuilder: (context, index) {
                  final theater = _processedTheaters[index];
                  final distance = theater['distanceKM'];
                  final timeWalk = theater['timeMins'];

                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161F),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                          child: Image.network(
                            theater['image'],
                            height: 110,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => Container(
                              height: 110,
                              color: const Color(0xFF222232),
                              child: const Icon(Icons.movie_rounded, color: Colors.white24, size: 40),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(14.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        theater['name'],
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      theater['address'],
                                      style: const TextStyle(color: Colors.grey, fontSize: 11, height: 1.4),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 10),
                                    // FIX DA XONG: Thay the withOpacity bang withValues(alpha) hoan hao chong loi depecated
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.navigation_rounded, color: Colors.amber, size: 12),
                                              const SizedBox(width: 4),
                                              Text(
                                                distance != null ? '${distance.toStringAsFixed(1)} km' : '-- km',
                                                style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 11),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(color: Colors.lightGreenAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.motorcycle_rounded, color: Colors.lightGreenAccent, size: 13),
                                              const SizedBox(width: 4),
                                              Text(
                                                timeWalk != null ? '~$timeWalk phút đi xe' : 'Đang tính...',
                                                style: const TextStyle(color: Colors.lightGreenAccent, fontWeight: FontWeight.bold, fontSize: 11),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.near_me_rounded, color: Colors.amber, size: 26),
                                    tooltip: 'Định vị bản đồ',
                                    onPressed: () {
                                      if (_mapController != null) {
                                        _mapController!.animateCamera(
                                          CameraUpdate.newLatLngZoom(LatLng(theater['lat'], theater['lng']), 15),
                                        );
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 6),
                                  IconButton(
                                    icon: const Icon(Icons.directions_rounded, color: Colors.lightGreenAccent, size: 26),
                                    tooltip: 'Chỉ đường Google Maps',
                                    onPressed: () => _launchDirections(theater['lat'], theater['lng']),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}