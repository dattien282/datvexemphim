# Lab 5 – Notifications Screen and Local Services

## 1. Objective
This lab guide provides step-by-step instructions to implement a general, interactive Notifications Screen and a Local Notification Service in Flutter. Students will learn the concepts of:
*   **Interactive List Views:** Building custom notification card layouts using `ListView.builder`.
*   **State Management (Read/Unread):** Toggling read status dynamically, updating card aesthetics, and displaying unread indicator dots.
*   **Swipe-to-Dismiss Gesture:** Utilizing the `Dismissible` widget to delete items from lists with animations and background color changes.
*   **Local Notifications Triggering:** Configuring and triggering local heads-up dropdown alerts using the `flutter_local_notifications` plugin.

---

## 2. Requirements & Required Tools
Ensure your local development environment has the following tools set up:
*   **Editor / IDE:** Visual Studio Code (with Dart & Flutter extensions) or Android Studio.
*   **Software Development Kit:** Flutter SDK (version 3.11.5 or newer) and Dart SDK.
*   **Device Environment:** An Android Emulator (via AVD Manager) or a physical Android Device with USB Debugging enabled for testing notification overlays.

Add the following package dependencies to your `pubspec.yaml` file:
```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_local_notifications: ^22.0.1
```
Declare notification system permissions in `android/app/src/main/AndroidManifest.xml` for Android 13+ (API 33):
```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

---

## 3. Guided Steps

### Exercise 1 – Build the Notification Model and Screen UI
Define a Notification data model and display a basic list of mock notifications in a dark-themed UI.

*   **Step 1:** Create a new Flutter file named `notification_lab_demo.dart`.
*   **Step 2:** Define the `NotificationModel` class and implement a Stateful Widget with a hardcoded list of notifications:

```dart
import 'package:flutter/material.dart';

class NotificationModel {
  final String id;
  final String title;
  final String body;
  final String time;
  bool isRead;

  NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.time,
    this.isRead = false,
  });
}

class NotificationLabScreen extends StatefulWidget {
  const NotificationLabScreen({super.key});

  @override
  State<NotificationLabScreen> createState() => _NotificationLabScreenState();
}

class _NotificationLabScreenState extends State<NotificationLabScreen> {
  List<NotificationModel> notifications = [
    NotificationModel(id: '1', title: 'Welcome!', body: 'Thank you for installing our app.', time: '2 min ago'),
    NotificationModel(id: '2', title: 'Special Promo', body: 'Get 50% discount on concessions today.', time: '1 hour ago'),
    NotificationModel(id: '3', title: 'System Alert', body: 'Server maintenance scheduled at midnight.', time: 'Yesterday', isRead: true),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Notifications', style: TextStyle(color: Colors.white)),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: notifications.length,
        itemBuilder: (context, index) {
          final item = notifications[index];
          return Card(
            color: item.isRead ? const Color(0xFF1E1E1E) : const Color(0xFF2D2D2D),
            child: ListTile(
              title: Text(item.title, style: TextStyle(color: Colors.white, fontWeight: item.isRead ? FontWeight.normal : FontWeight.bold)),
              subtitle: Text(item.body, style: const TextStyle(color: Colors.grey)),
              trailing: Text(item.time, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ),
          );
        },
      ),
    );
  }
}
```

---

### Exercise 2 – Implement Read Status Toggle & Indicators
Add a TabController to filter notifications and display unread indicators (Amber dots). Tapping a notification will toggle its `isRead` state.

*   **Step 1:** Modify your screen state class to include a TabController (or DefaultTabController).
*   **Step 2:** Add TabBar in AppBar. Build list filters. Bind ListTile `onTap` event to change read status:

```dart
// Inside build method of NotificationLabScreen...
return DefaultTabController(
  length: 2,
  child: Scaffold(
    backgroundColor: const Color(0xFF121212),
    appBar: AppBar(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text('Notifications Center'),
      bottom: const TabBar(
        indicatorColor: Colors.amber,
        tabs: [
          Tab(text: 'All'),
          Tab(text: 'Unread'),
        ],
      ),
    ),
    body: TabBarView(
      children: [
        _buildList(showAll: true),
        _buildList(showAll: false),
      ],
    ),
  ),
);

// Build method helper to filter notifications dynamically
Widget _buildList({required bool showAll}) {
  final list = showAll ? notifications : notifications.where((n) => !n.isRead).toList();
  if (list.isEmpty) {
    return const Center(child: Text('Hộp thư trống.', style: TextStyle(color: Colors.grey)));
  }
  return ListView.builder(
    padding: const EdgeInsets.all(16),
    itemCount: list.length,
    itemBuilder: (context, index) {
      final item = list[index];
      return Card(
        color: item.isRead ? const Color(0xFF1E1E1E) : const Color(0xFF2A2A2A),
        child: ListTile(
          onTap: () {
            setState(() {
              item.isRead = true;
            });
          },
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(item.title, style: TextStyle(color: Colors.white, fontWeight: item.isRead ? FontWeight.normal : FontWeight.bold)),
              if (!item.isRead)
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle)),
            ],
          ),
          subtitle: Text(item.body, style: const TextStyle(color: Colors.grey)),
        ),
      );
    },
  );
}
```

---

### Exercise 3 – Implement Swipe-to-Dismiss Gesture
Learn to swipe left on notification cards to dismiss and delete them from the memory list with exit animations.

*   **Step 1:** Wrap the Card item inside a `Dismissible` widget.
*   **Step 2:** Define the dismiss direction, background colors, and the `onDismissed` callback:

```dart
// Inside your ListView.builder...
return Dismissible(
  key: Key(item.id),
  direction: DismissDirection.endToStart, // Swipe right to left
  background: Container(
    color: Colors.redAccent.withOpacity(0.2),
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: 20),
    child: const Icon(Icons.delete_sweep, color: Colors.redAccent),
  ),
  onDismissed: (direction) {
    setState(() {
      notifications.removeWhere((n) => n.id == item.id);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted notification: ${item.title}')),
    );
  },
  child: Card( ... ),
);
```

---

### Exercise 4 – Initialize and Trigger Local Notifications
Configure the local notification plugin and add a Floating Action Button that triggers an instant dropdown popup alert on the screen.

*   **Step 1:** Define the Local Notification service helper class and configure Android settings:

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationHelper {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static void initialize() async {
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: null,
    );
    await _plugin.initialize(settings: initializationSettings);
    
    // Request permission for Android 13+ (API 33+)
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static void showNotification() async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'demo_channel_id',
        'Demo Alerts',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
      ),
    );
    await _plugin.show(
      id: 101, // Notification ID
      title: '🔔 TEST ALERT SUCCESS!',
      body: 'This is a local dropdown notification triggered from your app code.',
      notificationDetails: details,
    );
  }
}
```

> [!IMPORTANT]
> **Android 13+ (API 33+) Permission Requirement:**
> Starting from Android 13, applications must request runtime notification permissions. If you run the app and clicking the button does not show a notification:
> 1. Grant permission via the runtime prompt dialog when the app launches.
> 2. Alternatively, manually enable notifications: Go to **Settings > Apps > [Your App Name] > Notifications > Toggle ON (Allow Notifications)**.


*   **Step 2:** Call initialize in `main()` or `initState()`, and add a trigger button to your screen:

```dart
// In main():
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LocalNotificationHelper.initialize();
  runApp(const MaterialApp(home: NotificationLabScreen()));
}

// In Scaffold of NotificationLabScreen:
floatingActionButton: FloatingActionButton(
  backgroundColor: Colors.amber,
  onPressed: () => LocalNotificationHelper.showNotification(),
  child: const Icon(Icons.notifications_active, color: Colors.black),
),
```

---

## 4. Expected Results
By completing this lab, you should have a working, standalone notification screen:
*   A tabbed layout filters notifications between 'All' and 'Unread'.
*   Tapping an unread card updates its status and removes the Amber dot instantly.
*   Swiping any card left triggers a red sweep background and deletes the card.
*   Tapping the floating button fires a local dropdown banner popup on top of the screen.

---

## 5. Submission
Submit the following deliverables to complete this lab assignment:
*   The complete Dart source code file: `notification_lab_demo.dart`.
*   Screenshots showing:
    1.  The list view screen showing unread notifications (with Amber dots) under the 'All' and 'Unread' tabs.
    2.  Tapping a notification card, causing the Amber unread dot indicator to disappear.
    3.  Swiping left on a notification card to dismiss it with a red warning background.
    4.  Clicking the floating action button to fire the local notification dropdown popup banner.
*   Answers to the 10 Review Quiz questions (in Section 6) written in a text file or in your report.

---

## 6. Review Quiz / Câu hỏi kiểm tra ôn tập
Complete the following 10 multiple-choice questions to test your understanding of notifications in Flutter:

**Question 1: Trường dữ liệu nào giúp sắp xếp thông báo mới nhất lên đầu trong Firestore?**
*   A. title
*   B. isRead
*   **C. created_at (Timestamp) [Correct]**
*   D. type
*   *Explain:* Firestore sắp xếp theo thời gian thực dựa trên trường created_at kiểu Timestamp. Thiếu trường này, tài liệu sẽ bị Firestore tự động lọc và ẩn khỏi giao diện.

**Question 2: Widget nào dùng đồng bộ giao diện thời gian thực trực tiếp với Firestore?**
*   A. FutureBuilder
*   **B. StreamBuilder [Correct]**
*   C. SharedPreferences
*   D. StatefulWidget
*   *Explain:* StreamBuilder kết nối liên tục (socket) đến database Firestore, giúp tự động vẽ lại UI ngay lập tức khi database có thay đổi.

**Question 3: Khác biệt lớn nhất giữa thông báo từ xa (FCM) và thông báo cục bộ (Local Notification) là gì?**
*   A. FCM: cục bộ | Local: từ server đám mây.
*   **B. FCM: từ server | Local: tự phát trên máy [Correct]**
*   C. FCM: khi mở app | Local: khi đóng app.
*   D. Hai công nghệ hoàn toàn giống hệt nhau.
*   *Explain:* FCM là remote push gửi từ server Firebase. Local Notification do code Flutter tự kích hoạt ngay trên thiết bị.

**Question 4: Từ Android 13 trở lên, quyền nào bắt buộc phải khai báo để hiển thị thông báo ra màn hình?**
*   A. INTERNET
*   B. ACCESS_FINE_LOCATION
*   **C. POST_NOTIFICATIONS [Correct]**
*   D. CAMERA
*   *Explain:* POST_NOTIFICATIONS là quyền bắt buộc mới từ Android 13 (API 33+) để ngăn ứng dụng tự ý gửi thông báo làm phiền người dùng.

**Question 5: Widget Flutter nào được sử dụng để tạo hiệu ứng vuốt ngang để xóa thẻ thông báo?**
*   **A. Dismissible [Correct]**
*   B. GestureDetector
*   C. SlideTransition
*   D. AnimatedContainer
*   *Explain:* Dismissible là widget chuyên dụng của Flutter hỗ trợ vuốt ngang phần tử kèm theo hiệu ứng kéo mượt mà và xóa khỏi danh sách.

**Question 6: Kênh thông báo (Notification Channel) của ứng dụng Stella Cinema đăng ký với hệ điều hành Android có ID mặc định là gì?**
*   **A. stella_cinema_channel_2026 [Correct]**
*   B. notification_channel_default
*   C. firebase_push_channel
*   D. cinema_booking_alerts
*   *Explain:* stella_cinema_channel_2026 là ID duy nhất giúp Android đăng ký kênh thông báo riêng biệt của ứng dụng trên thiết bị.

**Question 7: Widget TweenAnimationBuilder trong danh sách thông báo dùng để làm gì?**
*   A. Lưu trữ dữ liệu thông báo vào cache máy.
*   **B. Tạo hiệu ứng trượt nhẹ thẻ từ phải sang trái khi hiển thị [Correct]**
*   C. Kết nối với API bản đồ Google Maps.
*   D. Tự động đồng bộ hóa hóa đơn đặt vé.
*   *Explain:* TweenAnimationBuilder là widget hoạt họa giúp chuyển đổi mượt mà thuộc tính vị trí và độ mờ khi danh sách xuất hiện.

**Question 8: Nút 'Xóa tất cả' (Clear All) trên app sẽ thực hiện hành động nào dưới database Firestore?**
*   A. Ẩn tạm thời thông báo trên màn hình điện thoại.
*   **B. Chạy vòng lặp xóa sạch dữ liệu của collection trên Firestore [Correct]**
*   C. Khởi động lại ứng dụng và xóa cache máy.
*   D. Gỡ bỏ hoàn toàn quyền nhận thông báo của app.
*   *Explain:* Chạy vòng lặp xóa hàng loạt (bulk-delete) tất cả tài liệu thông báo của người dùng trên Cloud Firestore.

**Question 9: Thông báo chưa đọc được biểu thị bằng ký hiệu trực quan gì trên app?**
*   A. Thẻ thông báo tự nhấp nháy liên tục.
*   **B. Chấm tròn vàng hổ phách (Amber dot) cạnh tiêu đề [Correct]**
*   C. Biểu tượng hình chiếc chìa khóa đỏ nhấp nháy.
*   D. Điện thoại tự động rung nhẹ liên tục.
*   *Explain:* Chấm tròn Amber báo hiệu tin nhắn mới, tự động ẩn đi khi người dùng nhấn xem (cập nhật isRead thành true).

**Question 10: Biểu tượng (Icon) trạng thái của một thông báo giao dịch mua vé thành công là gì?**
*   A. Quả chuông màu xanh ngọc.
*   B. Hộp quà màu xanh lá cây.
*   **C. Vé xem phim màu vàng hổ phách [Correct]**
*   D. Bản đồ Google Maps màu xanh lam.
*   *Explain:* Hàm _getNotiIcon lọc theo thuộc tính type == 'ticket' để hiển thị biểu tượng vé xem phim màu vàng hổ phách đặc trưng.
