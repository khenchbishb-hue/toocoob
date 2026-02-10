import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../utils/firebase_initializer.dart';
import 'package:firebase_core/firebase_core.dart';
import '../utils/local_debug_file.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _phoneController = TextEditingController();

  final _bankController = TextEditingController();

  String? _generatedPassword;
  Uint8List? _selectedImageBytes;
  bool _isLoading = false;

  final ImagePicker _picker = ImagePicker();

  bool _validateForm() {
    final username = _usernameController.text.trim();

    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нэвтрэх нэр заавал бөглөнө үү')));
      return false;
    }
    return true;
  }

  Future<void> _addUser() async {
    if (!_validateForm()) return;

    // Prevent Firebase operations if not initialized (e.g. web without firebase_options)
    if (Firebase.apps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Firebase эхлүүлэгдээгүй байна. Web дээр ашиглах бол `flutterfire configure` ашиглан `firebase_options.dart` үүсгэн Firebase.initializeApp(...) хийнэ үү.'),
      ));
      return;
    }

    setState(() {
      _generatedPassword = _generatePassword(8);
      _isLoading = true;
    });

    try {
      final phoneToSave =
          _phoneController.text.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');

      final username = _usernameController.text.trim();

      print('[ADMIN] Adding user: $username');

      final doc = {
        'username': username,
        'displayName': _displayNameController.text.trim().isEmpty
            ? null
            : _displayNameController.text.trim(),
        'phone': phoneToSave.isEmpty ? null : phoneToSave,
        'bank': _bankController.text.trim().isEmpty
            ? null
            : _bankController.text.trim(),
        'password': _generatedPassword ?? '',
        'createdAt': Timestamp.now(),
      };

      print('[ADMIN] Document to save: $doc');

      // Save quickly without blocking UI; handle completion in background.
      final imageBytes = _selectedImageBytes;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Хадгалалт эхэллээ...')),
        );
      }

      final addFuture = FirebaseFirestore.instance.collection('users').add(doc);

      print('[ADMIN] Firestore add request sent');

      unawaited(addFuture.then((docRef) async {
        print('[ADMIN] User added successfully with ID: ${docRef.id}');

        await writeDebugFile(
          r'C:\toocoob\firestore_add_ok.txt',
          'added user $username id=${docRef.id} time=${DateTime.now().toIso8601String()}',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Хэрэглэгч амжилттай бүртгэгдлээ!\nUsername: $username\nPassword: $_generatedPassword')),
          );

          _usernameController.clear();
          _displayNameController.clear();
          _phoneController.clear();
          _bankController.clear();
          setState(() {
            _selectedImageBytes = null;
          });
        }

        if (imageBytes != null) {
          unawaited(_uploadPhotoAndUpdate(docRef.id, username, imageBytes));
        }
      }).catchError((e) async {
        print('[ADMIN] Error adding user: $e');

        await writeDebugFile(
          r'C:\toocoob\firestore_add_error.txt',
          'error adding user $username: $e',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Алдаа гарлаа: $e')),
          );
        }
      }));
    } catch (e) {
      print('[ADMIN] Exception: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Алдаа гарлаа: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _uploadPhotoAndUpdate(
    String docId,
    String username,
    Uint8List imageBytes,
  ) async {
    try {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('users')
          .child(username)
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

      final uploadTask = await storageRef.putData(
        imageBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      if (uploadTask.state == TaskState.success) {
        final photoUrl = await storageRef.getDownloadURL();
        await FirebaseFirestore.instance
            .collection('users')
            .doc(docId)
            .update({'photoUrl': photoUrl});
      }
    } catch (_) {
      // Ignore photo upload errors to keep user creation fast.
    }
  }

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _selectedImageBytes = bytes;
      });
    }
  }

  String _generatePassword(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(
      length,
      (index) =>
          chars[(DateTime.now().millisecondsSinceEpoch + index) % chars.length],
    ).join();
  }

  Future<void> _editUser(String docId, Map<String, dynamic> userData) async {
    final usernameCtrl = TextEditingController(text: userData['username']);
    final displayNameCtrl =
        TextEditingController(text: userData['displayName']);
    final phoneCtrl = TextEditingController(text: userData['phone']);
    final bankCtrl = TextEditingController(text: userData['bank']);
    final passwordCtrl = TextEditingController(text: userData['password']);

    Uint8List? newImageBytes;
    String? currentPhotoUrl = userData['photoUrl'];

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Хэрэглэгч засах'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Зураг харуулах хэсэг
                GestureDetector(
                  onTap: () async {
                    final pickedFile = await _picker.pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 70,
                      maxWidth: 1024,
                      maxHeight: 1024,
                    );
                    if (pickedFile != null) {
                      final bytes = await pickedFile.readAsBytes();
                      print(
                          '[ADMIN] Image picked, size: ${bytes.length} bytes');
                      setDialogState(() {
                        newImageBytes = bytes;
                      });
                      print('[ADMIN] newImageBytes set in dialog state');
                    } else {
                      print('[ADMIN] No image picked');
                    }
                  },
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.deepPurple[100],
                        backgroundImage: newImageBytes != null
                            ? MemoryImage(newImageBytes!)
                            : (currentPhotoUrl != null
                                ? NetworkImage(currentPhotoUrl)
                                : null) as ImageProvider?,
                        child: newImageBytes == null && currentPhotoUrl == null
                            ? const Icon(Icons.person,
                                size: 50, color: Colors.deepPurple)
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Зураг солихын тулд дарна уу',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: usernameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Нэвтрэх нэр (username)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: displayNameCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Хоч (display name)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Утасны дугаар'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bankCtrl,
                  decoration: const InputDecoration(labelText: 'Дансны дугаар'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordCtrl,
                  decoration: const InputDecoration(labelText: 'Нууц үг'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Цуцлах'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Хадгалах'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      try {
        // Эхлээд мэдээлэл update хийх
        final updateData = {
          'username': usernameCtrl.text.trim(),
          'displayName': displayNameCtrl.text.trim(),
          'phone': phoneCtrl.text.trim(),
          'bank': bankCtrl.text.trim(),
          'password': passwordCtrl.text.trim(),
        };

        print('[ADMIN] Updating user data: $updateData');

        await FirebaseFirestore.instance
            .collection('users')
            .doc(docId)
            .update(updateData);

        print('[ADMIN] User data updated successfully');

        // Зураг солигдсон бол Firebase Storage-д хадгалах
        if (newImageBytes != null && newImageBytes!.isNotEmpty) {
          try {
            print('[ADMIN] Uploading new photo...');
            final username = usernameCtrl.text.trim();
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final fileName = 'photo_$timestamp.jpg';

            print('[ADMIN] Storage path: users/$username/$fileName');

            final storageRef = FirebaseStorage.instance
                .ref()
                .child('users')
                .child(username)
                .child(fileName);

            print('[ADMIN] Starting upload...');

            await storageRef.putData(
              newImageBytes!,
              SettableMetadata(contentType: 'image/jpeg'),
            );

            print('[ADMIN] Upload completed, getting download URL...');

            final photoUrl = await storageRef.getDownloadURL();
            print('[ADMIN] Photo URL: $photoUrl');

            print('[ADMIN] Updating Firestore with photoUrl...');

            await FirebaseFirestore.instance
                .collection('users')
                .doc(docId)
                .update({'photoUrl': photoUrl});

            print('[ADMIN] Photo URL updated in Firestore successfully');
          } catch (photoError) {
            print('[ADMIN] Photo upload error: $photoError');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Зураг хадгалах алдаа: $photoError')),
              );
            }
          }
        } else {
          print('[ADMIN] No new image to upload');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Амжилттай засагдлаа!')),
          );
        }
      } catch (e) {
        print('[ADMIN] Error updating user: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Алдаа гарлаа: $e')),
          );
        }
      }
    }

    // Dialog хаагдсаны дараа контроллерүүдийг dispose хийх
    usernameCtrl.dispose();
    displayNameCtrl.dispose();
    phoneCtrl.dispose();
    bankCtrl.dispose();
    passwordCtrl.dispose();
  }

  Future<void> _deleteUser(String docId, String username) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Устгах'),
        content: Text('$username хэрэглэгчийг устгах уу?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Үгүй'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Устгах'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(docId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Амжилттай устгагдлаа!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Алдаа гарлаа: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Админ хяналтын самбар'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Шинэ хэрэглэгч нэмэх',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            if (Firebase.apps.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Анхаар: Firebase эхлүүлэгдээгүй байна. Web дээр ашиглах бол `flutterfire configure` ажиллуулж `firebase_options.dart` үүсгэн `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` ашиглана уу.',
                        style: TextStyle(color: Colors.black87),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final ok = await showFirebaseInitializerDialog(context);
                        if (ok) setState(() {});
                      },
                      child: const Text('Тоциолдол'),
                    )
                  ],
                ),
              ),

            // Зураг сонгох хэсэг
            GestureDetector(
              onTap: _pickImage,
              child: CircleAvatar(
                radius: 50,
                backgroundImage: _selectedImageBytes != null
                    ? MemoryImage(_selectedImageBytes!)
                    : null,
                child: _selectedImageBytes == null
                    ? const Icon(Icons.camera_alt, size: 40)
                    : null,
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Нэвтрэх нэр (username) *',
                border: OutlineInputBorder(),
                helperText: 'Заавал',
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _displayNameController,
              decoration: const InputDecoration(
                labelText: 'Хоч (display name)',
                border: OutlineInputBorder(),
                helperText: 'Сонголтоор',
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Утасны дугаар',
                border: OutlineInputBorder(),
                helperText: 'Сонголтоор',
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _bankController,
              decoration: const InputDecoration(
                labelText: 'Дансны дугаар',
                border: OutlineInputBorder(),
                helperText: 'Сонголтоор',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),

            ElevatedButton.icon(
              onPressed:
                  (_isLoading || Firebase.apps.isEmpty) ? null : _addUser,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.person_add),
              label: Text(_isLoading
                  ? 'Нэмэгдэж байна...'
                  : (Firebase.apps.isEmpty
                      ? 'Firebase байхгүй'
                      : 'Хэрэглэгч нэмэх')),
            ),

            const SizedBox(height: 24),
            if (_generatedPassword != null)
              Text(
                'Системийн үүсгэсэн нууц үг: $_generatedPassword',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),

            const SizedBox(height: 32),
            const Divider(thickness: 2),
            const SizedBox(height: 16),

            // Хэрэглэгчдийн жагсаалт
            const Text(
              'Бүртгэлтэй хэрэглэгчид',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            if (Firebase.apps.isEmpty)
              const Text(
                'Firebase эхлүүлэгдээгүй байна.',
                style: TextStyle(color: Colors.red),
              )
            else
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  print(
                      '[STREAM] Connection state: ${snapshot.connectionState}');
                  print('[STREAM] Has data: ${snapshot.hasData}');
                  print('[STREAM] Has error: ${snapshot.hasError}');
                  if (snapshot.hasError) {
                    print('[STREAM] Error: ${snapshot.error}');
                    return Text('Алдаа: ${snapshot.error}');
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    print('[STREAM] No users found');
                    return const Text('Хэрэглэгч олдсонгүй.');
                  }

                  print('[STREAM] Found ${snapshot.data!.docs.length} users');

                  final users = snapshot.data!.docs;

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 3.5,
                    ),
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];
                      final data = user.data() as Map<String, dynamic>;
                      final username = data['username'] ?? '';
                      final displayName = data['displayName'] ?? '';
                      final phone = data['phone'] ?? '';
                      final bank = data['bank'] ?? '';
                      final photoUrl = data['photoUrl'];
                      final password = data['password'] ?? '';

                      return Card(
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            children: [
                              // Зураг
                              CircleAvatar(
                                radius: 30,
                                backgroundImage: photoUrl != null
                                    ? NetworkImage(photoUrl)
                                    : null,
                                child: photoUrl == null
                                    ? const Icon(Icons.person)
                                    : null,
                              ),
                              const SizedBox(width: 10),
                              // Текст
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '$displayName (@$username)',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      'Утас: $phone',
                                      style: const TextStyle(fontSize: 9),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      'Данс: $bank',
                                      style: const TextStyle(fontSize: 9),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      'Нууц: $password',
                                      style: const TextStyle(fontSize: 8),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              // Товч
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit,
                                        color: Colors.blue, size: 18),
                                    onPressed: () => _editUser(user.id, data),
                                    tooltip: 'Засах',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red, size: 18),
                                    onPressed: () =>
                                        _deleteUser(user.id, username),
                                    tooltip: 'Устгах',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
