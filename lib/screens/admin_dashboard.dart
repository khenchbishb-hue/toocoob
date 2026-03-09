import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/firebase_initializer.dart';
import 'package:firebase_core/firebase_core.dart';
import '../utils/local_debug_file.dart';
import '../utils/github_profile_image_service.dart';

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
  final _photoUrlController = TextEditingController();
  bool _newUserCanManageGames = false;

  String? _generatedPassword;
  bool _isLoading = false;
  bool _isUploadingPhoto = false;
  final ImagePicker _imagePicker = ImagePicker();

  bool get _isWebUploadReady =>
      !kIsWeb || GitHubProfileImageService.isConfigured;

  String _normalizePhotoUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return trimmed;

    if (uri.host == 'github.com') {
      final segments = uri.pathSegments;
      if (segments.length >= 5 && segments[2] == 'blob') {
        final owner = segments[0];
        final repo = segments[1];
        final branch = segments[3];
        final filePath = segments.sublist(4).join('/');
        return 'https://raw.githubusercontent.com/$owner/$repo/$branch/$filePath';
      }
    }

    return trimmed;
  }

  bool _validateForm() {
    final username = _usernameController.text.trim();

    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нэвтрэх нэр заавал бөглөнө үү')));
      return false;
    }

    final photoUrl = _normalizePhotoUrl(_photoUrlController.text);
    if (photoUrl.isNotEmpty &&
        !photoUrl.startsWith('http://') &&
        !photoUrl.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Зургийн URL зөв холбоос байх ёстой')));
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
      if (_newUserCanManageGames) {
        final existingManagers = await FirebaseFirestore.instance
            .collection('users')
            .where('canManageGames', isEqualTo: true)
            .get();

        if (existingManagers.docs.length >= 5) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Дээд тал нь 5 хэрэглэгчид бүртгэл хөтлөгчийн эрх олгоно.',
                ),
              ),
            );
          }
          return;
        }
      }

      final phoneToSave =
          _phoneController.text.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
      final photoUrl = _normalizePhotoUrl(_photoUrlController.text);

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
        'photoUrl': photoUrl.isEmpty ? null : photoUrl,
        'canManageGames': _newUserCanManageGames,
        'password': _generatedPassword ?? '',
        'createdAt': Timestamp.now(),
      };

      print('[ADMIN] Document to save: $doc');

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
          _photoUrlController.clear();
          _newUserCanManageGames = false;
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

  Future<void> _pickAndUploadPhotoForNewUser() async {
    try {
      if (!GitHubProfileImageService.isConfigured) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(GitHubProfileImageService.configHint())),
          );
        }
        return;
      }

      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (picked == null) return;

      setState(() {
        _isUploadingPhoto = true;
      });

      final bytes = await picked.readAsBytes();
      final uploadedUrl = await GitHubProfileImageService.uploadProfileImage(
        username: _usernameController.text.trim(),
        bytes: bytes,
      );

      if (!mounted) return;
      setState(() {
        _photoUrlController.text = uploadedUrl;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Зураг GitHub дээр амжилттай хадгалагдлаа.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Зураг оруулахад алдаа гарлаа: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingPhoto = false;
        });
      }
    }
  }

  Future<String?> _pickAndUploadPhotoForEdit({
    required TextEditingController usernameCtrl,
  }) async {
    try {
      if (!GitHubProfileImageService.isConfigured) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(GitHubProfileImageService.configHint())),
          );
        }
        return null;
      }

      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (picked == null) return null;

      final bytes = await picked.readAsBytes();
      final uploadedUrl = await GitHubProfileImageService.uploadProfileImage(
        username: usernameCtrl.text.trim(),
        bytes: bytes,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Зураг GitHub дээр шинэчлэгдлээ.')),
        );
      }
      return uploadedUrl;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Зураг шинэчлэхэд алдаа гарлаа: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _openGitHubProfileFolder() async {
    final uri = Uri.parse(GitHubProfileImageService.repositoryFolderWebUrl());
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GitHub холбоос нээж чадсангүй.')),
      );
    }
  }

  Future<String?> _pickPhotoUrlFromGitHub() async {
    try {
      if (!GitHubProfileImageService.isConfigured) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(GitHubProfileImageService.configHint())),
          );
        }
        return null;
      }

      final images = await GitHubProfileImageService.listProfileImages();
      if (images.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('GitHub хавтсанд зураг олдсонгүй.')),
          );
        }
        return null;
      }

      if (!mounted) return null;
      return showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('GitHub-оос зураг сонгох'),
          content: SizedBox(
            width: 420,
            height: 420,
            child: ListView.separated(
              itemCount: images.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final image = images[index];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundImage: NetworkImage(image.rawUrl),
                  ),
                  title: Text(
                    image.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: const Text('Сонгоход URL автоматаар бөглөгдөнө'),
                  trailing: IconButton(
                    tooltip: 'GitHub дээр харах',
                    onPressed: () => launchUrl(
                      Uri.parse(image.htmlUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new),
                  ),
                  onTap: () => Navigator.pop(context, image.rawUrl),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Болих'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GitHub зураг ачаалахад алдаа гарлаа: $e')),
        );
      }
      return null;
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
    final photoUrlCtrl =
        TextEditingController(text: (userData['photoUrl'] ?? '').toString());
    final bool originalCanManageGames = userData['canManageGames'] == true;
    bool canManageGames = originalCanManageGames;

    String currentPhotoUrl = (userData['photoUrl'] ?? '').toString();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Хэрэглэгч засах'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.deepPurple[100],
                  backgroundImage: currentPhotoUrl.isNotEmpty
                      ? NetworkImage(currentPhotoUrl)
                      : null,
                  child: currentPhotoUrl.isEmpty
                      ? const Icon(Icons.person,
                          size: 50, color: Colors.deepPurple)
                      : null,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: photoUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Зургийн URL',
                    hintText: 'https://github.com/.../blob/.../avatar.jpg',
                  ),
                  onChanged: (value) {
                    setDialogState(() {
                      currentPhotoUrl = _normalizePhotoUrl(value);
                    });
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: !_isWebUploadReady
                        ? null
                        : () async {
                            final uploadedUrl =
                                await _pickAndUploadPhotoForEdit(
                              usernameCtrl: usernameCtrl,
                            );
                            if (uploadedUrl == null) return;
                            setDialogState(() {
                              photoUrlCtrl.text = uploadedUrl;
                              currentPhotoUrl = uploadedUrl;
                            });
                          },
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text(
                        'Gallery-с зураг сонгоод GitHub руу хадгалах'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openGitHubProfileFolder,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('GitHub хавтас нээх'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: !_isWebUploadReady
                            ? null
                            : () async {
                                final selectedUrl =
                                    await _pickPhotoUrlFromGitHub();
                                if (selectedUrl == null) return;
                                setDialogState(() {
                                  photoUrlCtrl.text = selectedUrl;
                                  currentPhotoUrl = selectedUrl;
                                });
                              },
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: const Text('GitHub-оос сонгох'),
                      ),
                    ),
                  ],
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
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Тоглоомын бүртгэл хөтлөх эрх'),
                  subtitle: const Text(
                    'Оноо оруулах болон тоглолтын урсгал руу орох эрх',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: canManageGames,
                  onChanged: (value) {
                    setDialogState(() {
                      canManageGames = value;
                    });
                  },
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
        if (canManageGames && !originalCanManageGames) {
          final existingManagers = await FirebaseFirestore.instance
              .collection('users')
              .where('canManageGames', isEqualTo: true)
              .get();

          final managerCountWithoutCurrent =
              existingManagers.docs.where((doc) => doc.id != docId).length;

          if (managerCountWithoutCurrent >= 5) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Дээд тал нь 5 хэрэглэгчид тоглоомын бүртгэл хөтлөх эрх олгоно.',
                  ),
                ),
              );
            }
            return;
          }
        }

        // Эхлээд мэдээлэл update хийх
        final updateData = {
          'username': usernameCtrl.text.trim(),
          'displayName': displayNameCtrl.text.trim(),
          'phone': phoneCtrl.text.trim(),
          'bank': bankCtrl.text.trim(),
          'password': passwordCtrl.text.trim(),
          'canManageGames': canManageGames,
          'photoUrl': _normalizePhotoUrl(photoUrlCtrl.text).isEmpty
              ? null
              : _normalizePhotoUrl(photoUrlCtrl.text),
        };

        print('[ADMIN] Updating user data: $updateData');

        await FirebaseFirestore.instance
            .collection('users')
            .doc(docId)
            .update(updateData);

        print('[ADMIN] User data updated successfully');

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
    photoUrlCtrl.dispose();
  }

  Future<void> _toggleGameManagerRoleFromCard({
    required String docId,
    required bool currentValue,
  }) async {
    try {
      if (!currentValue) {
        final existingManagers = await FirebaseFirestore.instance
            .collection('users')
            .where('canManageGames', isEqualTo: true)
            .get();
        final countWithoutCurrent =
            existingManagers.docs.where((doc) => doc.id != docId).length;
        if (countWithoutCurrent >= 5) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Дээд тал нь 5 хэрэглэгчид бүртгэл хөтлөгчийн эрх олгоно.',
                ),
              ),
            );
          }
          return;
        }
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(docId)
          .update({'canManageGames': !currentValue});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              !currentValue
                  ? 'Бүртгэл хөтлөгчийн эрх олголоо.'
                  : 'Бүртгэл хөтлөгчийн эрх цуцаллаа.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Эрх шинэчлэхэд алдаа гарлаа: $e')),
        );
      }
    }
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

            CircleAvatar(
              radius: 50,
              backgroundColor: Colors.deepPurple[100],
              backgroundImage: _normalizePhotoUrl(_photoUrlController.text)
                      .isNotEmpty
                  ? NetworkImage(_normalizePhotoUrl(_photoUrlController.text))
                  : null,
              child: _photoUrlController.text.trim().isEmpty
                  ? const Icon(Icons.person, size: 40)
                  : null,
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _photoUrlController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Зургийн URL',
                border: const OutlineInputBorder(),
                helperText: _isWebUploadReady
                    ? 'GitHub blob/raw URL оруулж болно (автоматаар raw болгож хадгална)'
                    : 'GitHub тохиргоо дутуу байна. GITHUB_OWNER, GITHUB_REPO, GITHUB_TOKEN define өгнө үү.',
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: (_isUploadingPhoto || !_isWebUploadReady)
                    ? null
                    : _pickAndUploadPhotoForNewUser,
                icon: _isUploadingPhoto
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_a_photo_outlined),
                label: Text(_isUploadingPhoto
                    ? 'GitHub руу оруулж байна...'
                    : (_isWebUploadReady
                        ? 'Gallery-с зураг сонгоод GitHub руу хадгалах'
                        : 'GitHub тохиргоо дутуу (URL оруулна)')),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openGitHubProfileFolder,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('GitHub хавтас нээх'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: !_isWebUploadReady
                        ? null
                        : () async {
                            final selectedUrl = await _pickPhotoUrlFromGitHub();
                            if (selectedUrl == null) return;
                            setState(() {
                              _photoUrlController.text = selectedUrl;
                            });
                          },
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('GitHub-оос сонгох'),
                  ),
                ),
              ],
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
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.keyboard,
                    color: _newUserCanManageGames ? Colors.green : Colors.grey,
                  ),
                  tooltip: 'Бүртгэл хөтлөгчийн эрх',
                  onPressed: () {
                    setState(() {
                      _newUserCanManageGames = !_newUserCanManageGames;
                    });
                  },
                ),
                Expanded(
                  child: Text(
                    _newUserCanManageGames
                        ? 'Энэ хэрэглэгчид бүртгэл хөтлөгчийн эрх өгнө'
                        : 'Энгийн хэрэглэгчээр бүртгэнэ',
                    style: TextStyle(
                      color: _newUserCanManageGames
                          ? Colors.green.shade700
                          : Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
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
                      final photoUrl = (data['photoUrl'] ?? '').toString();
                      final hasPhoto = photoUrl.isNotEmpty;
                      final password = data['password'] ?? '';
                      final canManageGames = data['canManageGames'] == true;

                      return Card(
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            children: [
                              // Зураг
                              CircleAvatar(
                                radius: 30,
                                backgroundImage:
                                    hasPhoto ? NetworkImage(photoUrl) : null,
                                child:
                                    !hasPhoto ? const Icon(Icons.person) : null,
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
                                    Text(
                                      canManageGames
                                          ? 'Эрх: Тоглоом бүртгэл'
                                          : 'Эрх: Энгийн',
                                      style: TextStyle(
                                        fontSize: 8,
                                        color: canManageGames
                                            ? Colors.green
                                            : Colors.grey,
                                        fontWeight: FontWeight.bold,
                                      ),
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
                                    icon: Icon(
                                      Icons.keyboard,
                                      color: canManageGames
                                          ? Colors.green
                                          : Colors.grey,
                                      size: 18,
                                    ),
                                    onPressed: () =>
                                        _toggleGameManagerRoleFromCard(
                                      docId: user.id,
                                      currentValue: canManageGames,
                                    ),
                                    tooltip: canManageGames
                                        ? 'Бүртгэл хөтлөгчийн эрхийг цуцлах'
                                        : 'Бүртгэл хөтлөгчийн эрх олгох',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
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
