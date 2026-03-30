import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class GameRegistrarTransfer {
  const GameRegistrarTransfer._();

  static Future<String?> resolveAtGameEnd(
    BuildContext context, {
    required String? originalRegistrarUserId,
    required String? currentRegistrarUserId,
    required List<String> playerUserIds,
    required String Function(String userId) displayNameForUserId,
    required String Function(String userId) usernameForUserId,
  }) async {
    final original = originalRegistrarUserId ?? '';
    final current = currentRegistrarUserId ?? '';
    if (original.isEmpty || current.isEmpty || original == current) {
      return currentRegistrarUserId;
    }

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Бүртгэл хөтлөгчийн эрх'),
          content: Text(
            'Та бүртгэл хөтлөх эрхээ буцааж авах уу?\n'
            'Одоогийн хөтлөгч: ${displayNameForUserId(current)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'no'),
              child: const Text('Үгүй'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'transfer'),
              child: const Text('Өөр хөтлөгч рүү шилжүүлэх'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, 'yes'),
              child: const Text('Тийм'),
            ),
          ],
        );
      },
    );

    if (action == null) return currentRegistrarUserId;

    try {
      if (action == 'yes') {
        await _persistGameManagerRole(
          originalRegistrarUserId: original,
          previousRegistrarUserId: current,
          newManagerUserId: original,
        );
        return original;
      }

      if (action == 'no') {
        await _persistGameManagerRole(
          originalRegistrarUserId: original,
          previousRegistrarUserId: current,
          newManagerUserId: current,
        );
        return current;
      }

      if (action == 'transfer') {
        final uniquePlayerIds = playerUserIds.toSet().toList(growable: false);
        final candidateIds = uniquePlayerIds
            .where((id) => id.isNotEmpty && id != original)
            .toList(growable: false);

        final candidates = <_RegistrarCandidate>[];
        for (final userId in candidateIds) {
          final canManageGames = await _canManageGames(userId);
          if (!canManageGames && userId != current) continue;

          candidates.add(_RegistrarCandidate(
            userId: userId,
            title: displayNameForUserId(userId),
            subtitle: usernameForUserId(userId),
          ));
        }

        if (candidates.isEmpty) {
          _showSnackBar(
            context,
            'Шилжүүлэх боломжтой эрх бүхий тоглогч олдсонгүй.',
          );
          return currentRegistrarUserId;
        }

        final selectedUserId = await _showTargetSelectionDialog(
          context,
          candidates: candidates,
        );
        if (selectedUserId == null || selectedUserId.isEmpty) {
          return currentRegistrarUserId;
        }

        await _persistGameManagerRole(
          originalRegistrarUserId: original,
          previousRegistrarUserId: current,
          newManagerUserId: selectedUserId,
        );
        return selectedUserId;
      }
    } catch (_) {
      _showSnackBar(context, 'Эрхийн шийдвэр хадгалахад алдаа гарлаа.');
      return currentRegistrarUserId;
    }

    return currentRegistrarUserId;
  }

  static Future<String?> transfer(
    BuildContext context, {
    required String currentRegistrarUserId,
    required List<String> playerUserIds,
  }) async {
    final uniquePlayerIds = playerUserIds.toSet().toList(growable: false);

    final candidateIds = uniquePlayerIds
        .where((id) => id.isNotEmpty && id != currentRegistrarUserId)
        .toList(growable: false);
    if (candidateIds.isEmpty) {
      _showSnackBar(context, 'Эрх шилжүүлэх боломжтой тоглогч алга.');
      return null;
    }

    final candidates = <_RegistrarCandidate>[];
    for (final userId in candidateIds) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();
        final data = snapshot.data();
        if (data == null) continue;

        final canManageGames = data['canManageGames'] == true;
        if (!canManageGames) continue;

        final username = (data['username'] as String?)?.trim() ?? '';
        final displayName = (data['displayName'] as String?)?.trim() ?? '';
        final label = displayName.isNotEmpty
            ? displayName
            : (username.isNotEmpty ? username : 'Хэрэглэгч');

        candidates.add(_RegistrarCandidate(
          userId: userId,
          title: label,
          subtitle: username,
        ));
      } catch (_) {
        // Ignore failed user reads and continue with other candidates.
      }
    }

    if (candidates.isEmpty) {
      _showSnackBar(
        context,
        'Эрх шилжүүлэх боломжтой (canManageGames=true) тоглогч олдсонгүй.',
      );
      return null;
    }

    String selectedUserId = candidates.first.userId;
    final pickedUserId = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Тоглолт бүртгэх эрх шилжүүлэх'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final candidate in candidates)
                        RadioListTile<String>(
                          value: candidate.userId,
                          groupValue: selectedUserId,
                          onChanged: (value) {
                            if (value == null) return;
                            setLocalState(() => selectedUserId = value);
                          },
                          title: Text(candidate.title),
                          subtitle: candidate.subtitle.isEmpty
                              ? null
                              : Text('@${candidate.subtitle}'),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Болих'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, selectedUserId),
                  child: const Text('Шилжүүлэх'),
                ),
              ],
            );
          },
        );
      },
    );

    if (pickedUserId == null || pickedUserId.isEmpty) {
      return null;
    }

    try {
      final users = FirebaseFirestore.instance.collection('users');
      await users.doc(currentRegistrarUserId).update({'canManageGames': false});
      await users.doc(pickedUserId).update({'canManageGames': true});
      _showSnackBar(context, 'Тоглолт бүртгэх эрх амжилттай шилжлээ.');
      return pickedUserId;
    } catch (_) {
      _showSnackBar(context, 'Эрх шилжүүлэх үед алдаа гарлаа.');
      return null;
    }
  }

  static void _showSnackBar(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  static Future<bool> _canManageGames(String userId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      final data = snapshot.data();
      return data?['canManageGames'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _showTargetSelectionDialog(
    BuildContext context, {
    required List<_RegistrarCandidate> candidates,
  }) {
    String selectedUserId = candidates.first.userId;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Өөр хөтлөгч сонгох'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final candidate in candidates)
                        RadioListTile<String>(
                          value: candidate.userId,
                          groupValue: selectedUserId,
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() => selectedUserId = value);
                          },
                          title: Text(candidate.title),
                          subtitle: candidate.subtitle.isEmpty
                              ? null
                              : Text('@${candidate.subtitle}'),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Цуцлах'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, selectedUserId),
                  child: const Text('Хадгалах'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static Future<void> _persistGameManagerRole({
    required String originalRegistrarUserId,
    required String previousRegistrarUserId,
    required String newManagerUserId,
  }) async {
    final users = FirebaseFirestore.instance.collection('users');
    final batch = FirebaseFirestore.instance.batch();

    batch.update(users.doc(newManagerUserId), {'canManageGames': true});

    if (newManagerUserId == originalRegistrarUserId) {
      batch
          .update(users.doc(originalRegistrarUserId), {'canManageGames': true});
    } else {
      batch.update(
          users.doc(originalRegistrarUserId), {'canManageGames': false});
    }

    if (previousRegistrarUserId != newManagerUserId) {
      batch.update(
          users.doc(previousRegistrarUserId), {'canManageGames': false});
    }

    await batch.commit();
  }
}

class _RegistrarCandidate {
  const _RegistrarCandidate({
    required this.userId,
    required this.title,
    required this.subtitle,
  });

  final String userId;
  final String title;
  final String subtitle;
}
