import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Import your pages
import 'ui_screens/login.dart';
import 'ui_screens/register.dart';
import 'ui_screens/userpage.dart';
import 'ui_screens/pnppage.dart';
import 'ui_screens/bfppage.dart';
import 'ui_screens/mdrrmopage.dart';
import 'ui_screens/profile.dart';
import 'package:vibration/vibration.dart';
import 'dart:typed_data';


// Global notification plugin instance
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = 
    FlutterLocalNotificationsPlugin();

// CRITICAL: Background message handler - MUST be top-level function
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Handling background message: ${message.messageId}');
  print('Message data: ${message.data}');
  
  // Show notification based on department
  await _showBackgroundNotification(message);
}

Future<void> _showBackgroundNotification(RemoteMessage message) async {
  final notification = message.notification;
  if (notification == null) return;

  final data = message.data;
  final String severity = (data['severity'] ?? 'general').toLowerCase();

  String channelId;
  RawResourceAndroidNotificationSound? sound;
  bool playSoundAndVibrate = false;

  switch (severity) {
    case 'critical':
      channelId = 'critical_emergency_channel';
      sound = const RawResourceAndroidNotificationSound('alert2');
      playSoundAndVibrate = true;
      break;
    case 'high':
      channelId = 'high_emergency_channel';
      sound = const RawResourceAndroidNotificationSound('alert2');
      playSoundAndVibrate = true;
      break;
    case 'medium':
      channelId = 'medium_emergency_channel';
      sound = null; // No sound
      playSoundAndVibrate = false;
      break;
    case 'low':
      channelId = 'low_emergency_channel';
      sound = null; // No sound
      playSoundAndVibrate = false;
      break;
    default:
      channelId = 'general_emergency_channel';
      sound = null; // No sound
      playSoundAndVibrate = false;
  }

  // Only vibrate for critical/high
  if (playSoundAndVibrate && (await Vibration.hasVibrator() ?? false)) {
    Vibration.vibrate(pattern: [0, 1000, 500, 1000, 500, 1500]);
  }

  final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    channelId,
    '${severity[0].toUpperCase()}${severity.substring(1)} Emergency Alerts',
    channelDescription: 'Emergency notifications with $severity severity',
    importance: Importance.max,
    priority: Priority.high,
    playSound: playSoundAndVibrate,
    sound: sound,
    icon: '@mipmap/ic_launcher',
    styleInformation: BigTextStyleInformation(
      notification.body ?? '',
      contentTitle: notification.title ?? 'Emergency Alert',
    ),
  );

  final NotificationDetails details = NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.show(
    notification.hashCode,
    notification.title,
    notification.body,
    details,
  );
}


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Set background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  // Initialize local notifications for background messages
  await _initializeLocalNotifications();
  
  runApp(MyApp());
}



Future<void> _initializeLocalNotifications() async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initSettings = InitializationSettings(
    android: androidSettings,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      print('Notification tapped: ${response.payload}');
    },
  );
  

  final List<AndroidNotificationChannel> channels = [
     AndroidNotificationChannel(
      'critical_emergency_channel',
      'Critical Emergency Alerts',
      description: 'Critical level emergency notifications',
      importance: Importance.max,
      sound: RawResourceAndroidNotificationSound('alert'),
      playSound: true,
      enableVibration: true, // 👈 add this
  vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1500]),
    ),
     AndroidNotificationChannel(
      'high_emergency_channel',
      'High Emergency Alerts',
      description: 'High level emergency notifications',
      importance: Importance.max,
      sound: RawResourceAndroidNotificationSound('alert'),
      playSound: true,
      enableVibration: true, // 👈 add this
  vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1500]),
    ),
     AndroidNotificationChannel(
      'medium_emergency_channel',
      'Medium Emergency Alerts',
      description: 'Medium level emergency notifications',
      importance: Importance.high,
      sound: RawResourceAndroidNotificationSound('alert'),
      playSound: true,
      enableVibration: true, // 👈 add this
  vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1500]),
    ),
     AndroidNotificationChannel(
      'low_emergency_channel',
      'Low Emergency Alerts',
      description: 'Low level emergency notifications',
      importance: Importance.defaultImportance,
      sound: RawResourceAndroidNotificationSound('alert'),
      playSound: true,
      enableVibration: true, // 👈 add this
  vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1500]),
    ),
    AndroidNotificationChannel(
    'responder_updates_channel',
    'Responder Updates',
    description: 'Notifications when emergency responders take action on your reports',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1500]),
  ),
  ];

  final plugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  if (plugin != null) {
    for (final channel in channels) {
      await plugin.createNotificationChannel(channel);
    }
  }
}



class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeVictoria',
      theme: ThemeData(
        primarySwatch: Colors.red,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: AuthWrapper(), // Changed from initialRoute to home
      routes: {
        '/login': (context) => LoginPage(),
        '/register': (context) => RegisterPage(),
        '/user': (context) => HomePage(),
        '/pnppage': (context) => PnpPage(),
        '/bfppage': (context) => BFPPage(),
        '/mdrrmopage': (context) => MdrrmoPage(),
        '/profile': (context) => UserProfileSetupPage(isFirstTime: false),
        '/profile-setup': (context) => UserProfileSetupPage(isFirstTime: true),
      },
      onUnknownRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => LoginPage(),
        );
      },
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/profile-setup':
            final bool isFirstTime = settings.arguments as bool? ?? true;
            return MaterialPageRoute(
              builder: (context) =>
                  UserProfileSetupPage(isFirstTime: isFirstTime),
            );
          default:
            return null;
        }
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  @override
  _AuthWrapperState createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  User? _currentUser;
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _initializeAuth();
    _setupFirebaseMessaging();
  }

  void _initializeAuth() {
    // Check if user is already signed in
    _currentUser = FirebaseAuth.instance.currentUser;
    
    // Listen to auth state changes
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (mounted) {
        setState(() {
          _currentUser = user;
          _isLoading = false;
        });
      }
    });
    
    // Set loading to false after initial check
    setState(() {
      _isLoading = false;
    });
  }

  void _setupFirebaseMessaging() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // Request permission for notifications
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    print('User granted permission: ${settings.authorizationStatus}');

    // Get FCM token
    String? token = await messaging.getToken();
    print('FCM Token: $token');

    // Handle notification tap when app is terminated/background
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      print('App opened from notification: ${initialMessage.messageId}');
      // Handle navigation based on the notification
    }

    // Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Notification opened app: ${message.messageId}');
      // Handle navigation based on the notification
    });
  }

  @override
  Widget build(BuildContext context) {
    // Show loading screen while checking auth state
    if (_isLoading) {
      return _buildLoadingScreen();
    }

    // If user is logged in
    if (_currentUser != null) {
      return FutureBuilder<Map<String, dynamic>>(
        future: _checkUserProfile(_currentUser!),
        builder: (context, profileSnapshot) {
          if (profileSnapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingScreen();
          }

          if (profileSnapshot.hasError) {
            print('Error loading profile: ${profileSnapshot.error}');
            return _buildErrorScreen();
          }

          final result = profileSnapshot.data ??
              {'hasProfile': false, 'profileComplete': false, 'role': 'user'};
          
          final hasProfile = result['hasProfile'] as bool;
          final profileComplete = result['profileComplete'] as bool;
          final role = result['role'] as String;

          print('AuthWrapper - hasProfile: $hasProfile, profileComplete: $profileComplete, role: $role');

          // If user has no profile document at all, they need to set up profile
          if (!hasProfile) {
            return UserProfileSetupPage(isFirstTime: true);
          }

          // If profile exists but is not complete, go to profile setup
          if (!profileComplete) {
            return UserProfileSetupPage(isFirstTime: true);
          }

          // Profile exists and is complete - redirect based on role
          return _getPageForRole(role);
        },
      );
    }

    // No user logged in - show login page
    return LoginPage();
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/logo.png',
              width: 120,
              height: 120,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  Icons.shield,
                  size: 120,
                  color: Colors.red,
                );
              },
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(
              color: Colors.red,
              strokeWidth: 3,
            ),
            SizedBox(height: 16),
            Text(
              'Loading SafeVictoria...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Please restart the app',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                });
                _initializeAuth();
              },
              child: Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _getPageForRole(String role) {
    print('AuthWrapper - Navigating to page for role: $role');
    
    switch (role.toLowerCase()) {
      case 'pnp':
        return PnpPage();
      case 'bfp':
        return BFPPage();
      case 'mdrrmo':
        return MdrrmoPage();
      case 'user':
      default:
        return HomePage();
    }
  }

  Future<Map<String, dynamic>> _checkUserProfile(User user) async {
    try {
      print('Checking profile for user: ${user.email} (UID: ${user.uid})');
      
      // First try to get document by UID as document ID (your original approach)
      DocumentSnapshot docSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      Map<String, dynamic>? data;

      if (docSnapshot.exists) {
        data = docSnapshot.data() as Map<String, dynamic>?;
        print('Profile found by document ID');
      } else {
        // If not found by document ID, try querying by 'uid' field
        final query = await FirebaseFirestore.instance
            .collection('users')
            .where('uid', isEqualTo: user.uid)
            .limit(1)
            .get();

        if (query.docs.isNotEmpty) {
          data = query.docs.first.data();
          print('Profile found by uid field query');
        }
      }

      if (data != null) {
        final role = data['role'] ?? 'user';
        final profileComplete = data['profileComplete'] == true;

        print('Profile data - Role: $role, Complete: $profileComplete');

        // Validate role
        final validRoles = ['user', 'pnp', 'bfp', 'mdrrmo'];
        final finalRole = validRoles.contains(role.toLowerCase()) ? role : 'user';

        return {
          'hasProfile': true,
          'profileComplete': profileComplete,
          'role': finalRole,
        };
      } else {
        print('No profile found for UID: ${user.uid}');
        
        // No Firestore document found - user needs to complete profile
        return {
          'hasProfile': false,
          'profileComplete': false,
          'role': 'user', // default role
        };
      }
    } catch (e) {
      print('Error checking profile: $e');
      return {
        'hasProfile': false,
        'profileComplete': false,
        'role': 'user',
      };
    }
  }
}