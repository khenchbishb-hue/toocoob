import 'dart:async';
import 'dart:math' show min;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'screens/user_home.dart';
import 'screens/player_selection_page.dart';
import 'screens/ios/user_home_ios.dart';
import 'screens/ios/player_selection_page_ios.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'utils/firebase_initializer.dart';
import 'firebase_options.dart';
import 'utils/local_debug_file.dart';

// Set to true when Firebase successfully initialized.
bool firebaseInitialized = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Windows дээр Firebase-ийг skip хийх (C++ SDK асуудлаас болж)
  if (!kIsWeb && Platform.isWindows) {
    print('Windows platform: Running without Firebase');
    await writeDebugFile(
      r'C:\toocoob\firebase_init_error.txt',
      'Windows platform: Firebase disabled due to C++ SDK compatibility issues',
    );
    runApp(const ToocoobApp());
    return;
  }

  try {
    // Initialize Firebase with platform-specific options generated
    // by the FlutterFire CLI (`flutterfire configure`). This works on
    // web and native platforms.
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    firebaseInitialized = true;
    // Write a short file for quick local verification that Firebase
    // initialized correctly when running the installed app.
    await writeDebugFile(r'C:\toocoob\firebase_init_ok.txt', 'ok');
  } catch (e) {
    // Don't crash the app — provide guidance for web users and log for debug.
    // Also write an error file for debugging installed runs.
    await writeDebugFile(
      r'C:\toocoob\firebase_init_error.txt',
      'Firebase initialization error: $e',
    );
    // ignore: avoid_print
    print('Firebase initialization warning: $e');
  }

  runApp(const ToocoobApp());
}

class ToocoobApp extends StatelessWidget {
  const ToocoobApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ToocooB',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      home: const LoginScreen(),
    );
  }
}

// ---------------- LOGIN SCREEN ----------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _hideFirebaseWarning = false;
  Timer? _searchDebounce;
  List<String> _userSuggestions = [];

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _searchUsers(String query) {
    _searchDebounce?.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _userSuggestions = [];
      });
      return;
    }

    if (Firebase.apps.isEmpty) {
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final prefix = query.trim().toLowerCase();
        print('[DEBUG] Searching for users with prefix: $prefix');
        // Try simple contains search without orderBy (no index required)
        final snapshot =
            await FirebaseFirestore.instance.collection('users').get();

        print('[DEBUG] Total users in collection: ${snapshot.docs.length}');

        final results = snapshot.docs
            .where((doc) {
              final username =
                  (doc.data()['username'] ?? '').toString().toLowerCase();
              print('[DEBUG] Checking user: $username');
              return username.startsWith(prefix);
            })
            .map((doc) => (doc.data()['username'] ?? '').toString())
            .take(5)
            .toList();

        print('[DEBUG] Found ${results.length} matching users: $results');

        if (mounted) {
          setState(() {
            _userSuggestions = results;
          });
        }
      } catch (e) {
        print('[ERROR] Search error: $e');
        if (mounted) {
          setState(() {
            _userSuggestions = [];
          });
        }
      }
    });
  }

  Widget _buildSuggestions() {
    if (_userSuggestions.isEmpty) {
      return const SizedBox.shrink();
    }
    return SingleChildScrollView(
      child: Column(
        children: _userSuggestions.map((suggestion) {
          return Material(
            child: InkWell(
              onTap: () {
                _usernameController.text = suggestion;
                setState(() {
                  _userSuggestions = [];
                });
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(suggestion),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    print('[LOGIN] Attempting login with username: $username');

    if (username == 'admin' && password == 'admin123') {
      print('[LOGIN] Admin credentials matched');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => !kIsWeb && Platform.isIOS
              ? const PlayerSelectionPageIOS(isAdmin: true)
              : const PlayerSelectionPage(isAdmin: true),
        ),
      );
    } else {
      if (username.isEmpty || password.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Нэвтрэх нэр болон нууц үгээ оруулна уу')),
        );
        return;
      }

      if (Firebase.apps.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Firebase эхлүүлэгдээгүй байна.')),
        );
        return;
      }

      try {
        print('[LOGIN] Querying Firestore for user...');

        // Эхлээд username-аар хайна
        final userQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('username', isEqualTo: username)
            .limit(1)
            .get();

        if (userQuery.docs.isEmpty) {
          print('[LOGIN] Username not found');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Хэрэглэгч олдсонгүй')),
          );
          return;
        }

        final userDoc = userQuery.docs.first;
        final userData = userDoc.data();
        final storedPassword = (userData['password'] ?? '').toString();

        print('[LOGIN] User found, checking password...');
        print('[LOGIN] Stored password: $storedPassword');
        print('[LOGIN] Entered password: $password');

        if (storedPassword != password) {
          print('[LOGIN] Password mismatch');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Нууц үг буруу байна')),
          );
          return;
        }

        final docId = userDoc.id;
        print('[LOGIN] User authenticated successfully with ID: $docId');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => !kIsWeb && Platform.isIOS
                ? UserHomeIOS(userId: docId, username: username)
                : UserHome(userId: docId, username: username),
          ),
        );
      } catch (e) {
        print('[LOGIN] Error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Алдаа гарлаа: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (kIsWeb && Firebase.apps.isEmpty && !_hideFirebaseWarning)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    color: Colors.amber.shade700,
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Firebase is not initialized for Web. Run `flutterfire configure` to generate `firebase_options.dart` and initialize Firebase, or paste web config below.',
                            style: TextStyle(color: Colors.black),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            // open helper dialog
                            final inited =
                                await showFirebaseInitializerDialog(context);
                            if (inited) setState(() {});
                          },
                          child: const Text('Initialize'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _hideFirebaseWarning = true;
                          }),
                        )
                      ],
                    ),
                  ),
                LayoutBuilder(builder: (context, constraints) {
                  final screenWidth = MediaQuery.of(context).size.width;
                  final isSmallScreenLocal = screenWidth < 600;
                  final imageHeight =
                      min(430.0, MediaQuery.of(context).size.height * 0.45);

                  if (isSmallScreenLocal) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                            height: imageHeight,
                            child: Image.asset('assets/logo.png',
                                fit: BoxFit.contain)),
                        const SizedBox(height: 16),
                        const Text(
                          'ToocooB',
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: _usernameController,
                          onChanged: _searchUsers,
                          decoration: const InputDecoration(
                            labelText: 'Нэвтрэх нэр',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        _buildSuggestions(),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _login(),
                          decoration: const InputDecoration(
                            labelText: 'Нууц үг',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _login,
                          child: const Text('Нэвтрэх'),
                        ),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                                height: imageHeight,
                                child: Image.asset('assets/logo.png',
                                    fit: BoxFit.contain)),
                            const SizedBox(height: 24),
                            const Text(
                              'ToocooB',
                              style: TextStyle(
                                fontSize: 56,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 40),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextField(
                              controller: _usernameController,
                              onChanged: _searchUsers,
                              decoration: const InputDecoration(
                                labelText: 'Нэвтрэх нэр',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            _buildSuggestions(),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _passwordController,
                              obscureText: true,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _login(),
                              decoration: const InputDecoration(
                                labelText: 'Нууц үг',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _login,
                              child: const Text('Нэвтрэх'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
