import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class GitHubImageEntry {
  const GitHubImageEntry({
    required this.name,
    required this.rawUrl,
    required this.htmlUrl,
  });

  final String name;
  final String rawUrl;
  final String htmlUrl;
}

class GitHubProfileImageService {
  // Configure these securely at build/run time using --dart-define.
  static const String _owner = String.fromEnvironment('GITHUB_OWNER');
  static const String _repo = String.fromEnvironment('GITHUB_REPO');
  static const String _branch = String.fromEnvironment(
    'GITHUB_BRANCH',
    defaultValue: 'main',
  );
  static const String _folder = String.fromEnvironment(
    'GITHUB_PROFILE_IMAGE_FOLDER',
    defaultValue: 'player_profiles',
  );
  static const String _token = String.fromEnvironment('GITHUB_TOKEN');

  static bool get isConfigured =>
      _owner.isNotEmpty &&
      _repo.isNotEmpty &&
      _branch.isNotEmpty &&
      _folder.isNotEmpty &&
      _token.isNotEmpty;

  static String configHint() {
    return 'Missing GitHub config. Add --dart-define for '
        'GITHUB_OWNER, GITHUB_REPO, GITHUB_TOKEN '
        '(optional: GITHUB_BRANCH, GITHUB_PROFILE_IMAGE_FOLDER).';
  }

  static String repositoryFolderWebUrl() {
    return 'https://github.com/$_owner/$_repo/tree/$_branch/$_folder';
  }

  static Future<List<GitHubImageEntry>> listProfileImages() async {
    if (!isConfigured) {
      throw Exception(configHint());
    }

    final apiUrl =
        'https://api.github.com/repos/$_owner/$_repo/contents/$_folder?ref=$_branch';

    final res = await http.get(
      Uri.parse(apiUrl),
      headers: {
        'Authorization': 'Bearer $_token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
          'GitHub image list failed (${res.statusCode}): ${res.body}');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! List) {
      throw Exception('GitHub image list format is invalid.');
    }

    final items = <GitHubImageEntry>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      if (item['type'] != 'file') continue;

      final name = (item['name'] as String?) ?? '';
      if (name.isEmpty) continue;

      final lower = name.toLowerCase();
      final isImage = lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.png') ||
          lower.endsWith('.webp');
      if (!isImage) continue;

      final path = (item['path'] as String?) ?? '';
      if (path.isEmpty) continue;

      final htmlUrl = (item['html_url'] as String?) ?? repositoryFolderWebUrl();
      final rawUrl =
          'https://raw.githubusercontent.com/$_owner/$_repo/$_branch/$path';

      items.add(GitHubImageEntry(name: name, rawUrl: rawUrl, htmlUrl: htmlUrl));
    }

    items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return items;
  }

  static Future<String> uploadProfileImage({
    required String username,
    required Uint8List bytes,
  }) async {
    if (!isConfigured) {
      throw Exception(configHint());
    }

    final safeUsername = username.trim().isEmpty
        ? 'player'
        : username.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final filename =
        '${safeUsername}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final repoPath = '$_folder/$filename';

    final apiUrl =
        'https://api.github.com/repos/$_owner/$_repo/contents/$repoPath';

    final payload = <String, dynamic>{
      'message': 'upload profile image for $safeUsername',
      'branch': _branch,
      'content': base64Encode(bytes),
    };

    final res = await http.put(
      Uri.parse(apiUrl),
      headers: {
        'Authorization': 'Bearer $_token',
        'Accept': 'application/vnd.github+json',
        'Content-Type': 'application/json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
      body: jsonEncode(payload),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('GitHub upload failed (${res.statusCode}): ${res.body}');
    }

    return 'https://raw.githubusercontent.com/$_owner/$_repo/$_branch/$repoPath';
  }
}
