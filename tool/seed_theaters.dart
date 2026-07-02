// One-off migration script: seeds the `theaters` Firestore collection from
// the theater lists that used to be hardcoded independently across several
// screens (admin_users_screen.dart, showtime_selection_screen.dart,
// admin_revenue_screen.dart, theater_maps_screen.dart).
//
// Run once with: dart run tool/seed_theaters.dart
// Requires Firebase to already be configured for this machine (uses the same
// google-services config the app uses via firebase_core, run inside a
// throwaway Flutter test harness is overkill for a script, so this uses the
// REST-free approach: run it as `flutter run -d <device>` is NOT needed;
// instead run it as a plain Dart script against the Firestore REST API is
// also overkill. Simplest: paste this data manually into the Firebase
// Console > Firestore > theaters collection, using the values below.
//
// Coordinates ported from lib/features/maps/screens/theater_maps_screen.dart.

// NOTE: names must match exactly what showtime_selection_screen.dart offers
// customers at booking time (that's what ends up in tickets.theaterName),
// so they include the parenthetical district/city suffix.
const theaters = [
  {
    'name': 'Stella Cinema Nguyễn Du (Quận 1)',
    'city': 'Hồ Chí Minh',
    'address': 'Nguyễn Du, Quận 1, TP. Hồ Chí Minh',
    'lat': 10.77303,
    'lng': 106.69341,
  },
  {
    'name': 'Stella Cinema Vạn Hạnh Mall (Quận 10)',
    'city': 'Hồ Chí Minh',
    'address': 'Vạn Hạnh Mall, Quận 10, TP. Hồ Chí Minh',
    'lat': 10.77055,
    'lng': 106.66954,
  },
  {
    'name': 'Stella Cinema Mipec Long Biên (Hà Nội)',
    'city': 'Hà Nội',
    'address': 'Mipec Long Biên, Hà Nội',
    'lat': 21.04535,
    'lng': 105.86649,
  },
  {
    'name': 'Stella Cinema Đà Nẵng (Thanh Khê)',
    'city': 'Đà Nẵng',
    'address': 'Thanh Khê, Đà Nẵng',
    'lat': 16.0620,
    'lng': 108.1885,
  },
  {
    'name': 'Stella Cinema Cần Thơ (Sense City)',
    'city': 'Cần Thơ',
    'address': 'Sense City, Cần Thơ',
    'lat': 10.0355,
    'lng': 105.7836,
  },
];

void main() {
  // ignore: avoid_print
  print('Copy the `theaters` list above into Firebase Console > Firestore > '
      'theaters collection (one document per entry), or wire this script to '
      'firebase_core/cloud_firestore + Firebase.initializeApp() if you want '
      'to run it programmatically inside a Flutter test harness.');
}
