import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

/// Shows a dialog where the developer can paste Firebase Web config JSON
/// (the object you get in the Firebase Console) and attempts to initialize
/// the default Firebase app using those values. Returns true on success.
Future<bool> showFirebaseInitializerDialog(BuildContext context) async {
  final TextEditingController controller = TextEditingController();
  bool isLoading = false;
  String? error;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return StatefulBuilder(builder: (context, setState) {
        Future<void> tryInit() async {
          setState(() {
            isLoading = true;
            error = null;
          });

          try {
            final jsonString = controller.text.trim();
            if (jsonString.isEmpty) {
              throw Exception('Please paste Firebase web config JSON.');
            }

            final Map<String, dynamic> map = jsonDecode(jsonString);

            String? apiKey = map['apiKey'] ?? map['api_key'] ?? map['api-key'];
            String? appId = map['appId'] ?? map['app_id'];
            String? messagingSenderId =
                map['messagingSenderId'] ?? map['messaging_sender_id'];
            String? projectId = map['projectId'] ?? map['project_id'];
            String? authDomain = map['authDomain'] ?? map['auth_domain'];
            String? storageBucket =
                map['storageBucket'] ?? map['storage_bucket'];
            String? measurementId =
                map['measurementId'] ?? map['measurement_id'];

            if (apiKey == null ||
                appId == null ||
                messagingSenderId == null ||
                projectId == null) {
              throw Exception(
                  'Missing required fields. Ensure the JSON contains apiKey, appId, messagingSenderId and projectId.');
            }

            final options = FirebaseOptions(
              apiKey: apiKey,
              appId: appId,
              messagingSenderId: messagingSenderId,
              projectId: projectId,
              authDomain: authDomain,
              storageBucket: storageBucket,
              measurementId: measurementId,
            );

            await Firebase.initializeApp(options: options);

            // success
            Navigator.of(context).pop(true);
          } catch (e) {
            setState(() {
              error = e.toString();
            });
          } finally {
            setState(() {
              isLoading = false;
            });
          }
        }

        return AlertDialog(
          title: const Text('Firebase тохируулга (Web)'),
          content: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                    'Firebase Console → Project settings → Your apps (Web) → copy config object and paste here.'),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  minLines: 6,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '{"apiKey": "...", "authDomain": "...", ... }',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ]
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  isLoading ? null : () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isLoading ? null : tryInit,
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Initialize'),
            ),
          ],
        );
      });
    },
  );

  return result == true;
}
