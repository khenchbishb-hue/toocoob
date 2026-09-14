import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../utils/avatar_upload.dart';
import '../utils/bank_details.dart';
import '../utils/statistics_repository.dart';
import '../utils/demo_players.dart';
import 'player_selection_page.dart';

/// The member home intentionally shows useful structure before game data is
/// connected. Every card has an empty state instead of made-up statistics.
class MemberDashboard extends StatelessWidget {
  const MemberDashboard({
    super.key,
    required this.username,
    required this.profileName,
    required this.hasPaymentAccount,
    required this.onLogout,
    this.canManageGames = false,
    this.isSystemAdmin = false,
    this.onOpenSystemAdmin,
  });

  final String username;
  final String profileName;
  final bool hasPaymentAccount;
  final VoidCallback onLogout;
  final bool canManageGames;
  final bool isSystemAdmin;
  final ValueChanged<BuildContext>? onOpenSystemAdmin;

  Future<void> _confirmSystemAdminAccess(BuildContext context) async {
    if (!isSystemAdmin || onOpenSystemAdmin == null) return;
    final password = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Админ эрх баталгаажуулах'),
        content: TextField(
          controller: password,
          autofocus: true,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Нууц үг',
            hintText: 'Нууц үгээ дахин оруулна уу',
          ),
          onSubmitted: (_) => Navigator.of(dialogContext).pop(true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Болих')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Баталгаажуулах')),
        ],
      ),
    );
    if (approved != true) {
      password.dispose();
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email;
      if (user == null || email == null || password.text.isEmpty) {
        throw StateError('Нууц үгээ оруулна уу.');
      }
      final credential =
          EmailAuthProvider.credential(email: email, password: password.text);
      await user.reauthenticateWithCredential(credential);
      final token = await user.getIdTokenResult(true);
      if (token.claims?['systemAdmin'] != true) {
        throw StateError('System Admin эрх баталгаажаагүй байна.');
      }
      if (context.mounted) onOpenSystemAdmin!(context);
    } on FirebaseAuthException catch (error) {
      if (context.mounted) {
        final message =
            error.code == 'wrong-password' || error.code == 'invalid-credential'
                ? 'Нууц үг буруу байна.'
                : 'Баталгаажуулж чадсангүй. Дахин оролдоно уу.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', ''))));
      }
    } finally {
      password.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF061B28),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF061B28),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        centerTitle: true,
        titleSpacing: 0,
        title: SizedBox(
          width: MediaQuery.sizeOf(context).width * .7,
          height: kToolbarHeight * .86,
          child: const FittedBox(
            fit: BoxFit.contain,
            child: _ToocooBWordmark(),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Гарах',
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, _) {
          final compact = MediaQuery.sizeOf(context).width < 760;
          return ListView(
            padding: EdgeInsets.fromLTRB(
                compact ? 16 : 28, 12, compact ? 16 : 28, 36),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: _DashboardLayout(
                    username: username,
                    profileName: profileName,
                    hasPaymentAccount: hasPaymentAccount,
                    canManageGames: canManageGames,
                    isSystemAdmin: isSystemAdmin,
                    onAdmin: isSystemAdmin && onOpenSystemAdmin != null
                        ? () => _confirmSystemAdminAccess(context)
                        : null,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ToocooBWordmark extends StatelessWidget {
  const _ToocooBWordmark();

  @override
  Widget build(BuildContext context) => const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('ТОО',
              style: TextStyle(
                  color: Color(0xFF55D7E8),
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .2)),
          Text('Ц',
              style: TextStyle(
                  color: Color(0xFFF05252),
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .2)),
          Text('ОО',
              style: TextStyle(
                  color: Color(0xFF6ACB78),
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .2)),
          _MirroredB(),
        ],
      );
}

class _MirroredB extends StatelessWidget {
  const _MirroredB();
  @override
  Widget build(BuildContext context) => Transform(
        alignment: Alignment.center,
        transform: Matrix4.rotationY(3.141592653589793),
        child: const Text('Б',
            style: TextStyle(
                color: Color(0xFF6ACB78),
                fontSize: 48,
                fontWeight: FontWeight.w900,
                letterSpacing: .2)),
      );
}

class _DashboardLayout extends StatefulWidget {
  const _DashboardLayout({
    required this.username,
    required this.profileName,
    required this.hasPaymentAccount,
    required this.canManageGames,
    required this.isSystemAdmin,
    this.onAdmin,
  });

  final String username;
  final String profileName;
  final bool hasPaymentAccount;
  final bool canManageGames;
  final bool isSystemAdmin;
  final VoidCallback? onAdmin;

  @override
  State<_DashboardLayout> createState() => _DashboardLayoutState();
}

class _DashboardLayoutState extends State<_DashboardLayout> {
  bool _settingsOpen = false;
  bool _qrOpen = false;
  BankDetails _bankDetails = const BankDetails();
  late bool _hasPaymentAccount;
  Color _profileBackground = const Color(0xFF0A3342);
  Color _cardBorder = const Color(0xFFF4C96B);
  Uint8List? _avatarBytes;

  @override
  void initState() {
    super.initState();
    _hasPaymentAccount = widget.hasPaymentAccount;
    _loadPreviousAvatar();
  }

  Future<void> _loadPreviousAvatar() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final profile = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (mounted) {
          setState(() {
            _bankDetails = BankDetails.fromMap(profile.data()?['bankDetails']);
            _hasPaymentAccount = _bankDetails.complete;
          });
        }
        final url = profile.data()?['photoUrl'];
        if (url is String && url.startsWith('https://res.cloudinary.com/pkrbzrqh/image/upload/')) {
          final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
          if (response.statusCode == 200) {
            if (mounted && _avatarBytes == null) setState(() => _avatarBytes = response.bodyBytes);
            return;
          }
        }
        final encoded = profile.data()?['avatarBase64'];
        if (encoded is String && encoded.isNotEmpty) {
          final bytes = base64Decode(encoded);
          if (mounted && _avatarBytes == null) {
            setState(() => _avatarBytes = bytes);
          }
          return;
        }
      } catch (_) {
        // Keep the bundled legacy avatar available when offline.
      }
    }
    // Confirmed legacy profile: Б. Хэнчбиш / Чоно.
    // Match both fields so another account sharing the nickname is unaffected.
    final name = widget.profileName.toLowerCase().replaceAll(RegExp(r'[\s.]'), '');
    final nickname = widget.username.trim().toLowerCase();
    if (name != 'бхэнчбиш' || nickname != 'чоно') return;
    final image = await rootBundle.load('assets/players/chono.jpg');
    if (!mounted || _avatarBytes != null) return;
    setState(() {
      _avatarBytes = image.buffer.asUint8List(image.offsetInBytes, image.lengthInBytes);
    });
  }

  Widget _profileColumn() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProfileHero(
            username: widget.username,
            profileName: widget.profileName,
            hasPaymentAccount: _hasPaymentAccount,
            canManageGames: widget.canManageGames,
            isSystemAdmin: widget.isSystemAdmin,
            profileBackground: _profileBackground,
            cardBorder: _cardBorder,
            avatarBytes: _avatarBytes,
            onProfile: () => setState(() => _settingsOpen = true),
            onQr: _hasPaymentAccount
                ? () => setState(() => _qrOpen = true)
                : null,
            onAdmin: widget.onAdmin,
          ),
          const SizedBox(height: 10),
          SizedBox(width: 330, child: ValueListenableBuilder<int>(
            valueListenable: StatsRepository.revision,
            builder: (context, revision, child) => FutureBuilder<List<StatsSession>>(
              future: StatsRepository().loadSessions(),
              builder: (context, snapshot) {
                final uid = FirebaseAuth.instance.currentUser?.uid;
                final sessions = (snapshot.data ?? <StatsSession>[])
                    .where((s) => s.players.any((p) => p.userId == uid)).toList()
                  ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
                if (sessions.isEmpty) return const _LatestGameCard();
                final latest = sessions.first;
                return _LatestGameCard(gameName: latest.gameLabel,
                  playerCount: latest.players.length,
                  netAmount: latest.players.firstWhere((p) => p.userId == uid).money,
                  isTrial: latest.players.any((p) => DemoPlayers.isDemoId(p.userId)));
              },
            ),
          )),
        ],
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 860;
          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _profileColumn(),
                const SizedBox(height: 18),
                SizedBox(
                  height: 430,
                  child: _DashboardArea(
                    settingsOpen: _settingsOpen,
                    canManageGames: widget.canManageGames,
                    profileBackground: _profileBackground,
                    cardBorder: _cardBorder,
                    avatarBytes: _avatarBytes,
                    hasPaymentAccount: _hasPaymentAccount,
                    qrOpen: _qrOpen,
                    bankDetails: _bankDetails,
                    onCloseSettings: () =>
                        setState(() => _settingsOpen = false),
                    onCloseQr: () => setState(() => _qrOpen = false),
                    onSaveSettings: _saveSettings,
                  ),
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 330, child: _profileColumn()),
              const SizedBox(width: 18),
              Expanded(
                child: SizedBox(
                  height: 550,
                  child: _DashboardArea(
                    settingsOpen: _settingsOpen,
                    canManageGames: widget.canManageGames,
                    profileBackground: _profileBackground,
                    cardBorder: _cardBorder,
                    avatarBytes: _avatarBytes,
                    hasPaymentAccount: _hasPaymentAccount,
                    qrOpen: _qrOpen,
                    bankDetails: _bankDetails,
                    onCloseSettings: () =>
                        setState(() => _settingsOpen = false),
                    onCloseQr: () => setState(() => _qrOpen = false),
                    onSaveSettings: _saveSettings,
                  ),
                ),
              ),
            ],
          );
        },
      );

  Future<void> _saveSettings(_ProfileSettings settings) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Дахин нэвтэрнэ үү.');
    final changes = <String, dynamic>{
      'bankDetails': settings.bankDetails.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (settings.avatarBytes != null && !identical(settings.avatarBytes, _avatarBytes)) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('Дахин нэвтэрнэ үү.');
      final url = await uploadAvatar(settings.avatarBytes!);
      changes['photoUrl'] = url;
    }
    await FirebaseFirestore.instance.collection('users').doc(uid).update(changes);
    if (!mounted) return;
    setState(() {
      _profileBackground = settings.profileBackground;
      _cardBorder = settings.cardBorder;
      _avatarBytes = settings.avatarBytes;
      _hasPaymentAccount = settings.hasPaymentAccount;
      _bankDetails = settings.bankDetails;
      if (!_hasPaymentAccount) _qrOpen = false;
      _settingsOpen = false;
    });
  }
}

class _DashboardArea extends StatefulWidget {
  const _DashboardArea({
    required this.settingsOpen,
    required this.canManageGames,
    required this.profileBackground,
    required this.cardBorder,
    required this.avatarBytes,
    required this.hasPaymentAccount,
    required this.qrOpen,
    required this.bankDetails,
    required this.onCloseSettings,
    required this.onCloseQr,
    required this.onSaveSettings,
  });

  final bool settingsOpen;
  final bool canManageGames;
  final Color profileBackground;
  final Color cardBorder;
  final Uint8List? avatarBytes;
  final bool hasPaymentAccount;
  final bool qrOpen;
  final BankDetails bankDetails;
  final VoidCallback onCloseSettings;
  final VoidCallback onCloseQr;
  final Future<void> Function(_ProfileSettings) onSaveSettings;

  @override
  State<_DashboardArea> createState() => _DashboardAreaState();
}

class _DashboardAreaState extends State<_DashboardArea> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    if (_selected != null && !widget.settingsOpen && !widget.qrOpen) {
      if (_selected == 'Яг одоо') {
        return _NowDashboardDetail(
          onBack: () => setState(() => _selected = null),
          canManageGames: widget.canManageGames,
        );
      }
      return _DashboardDetail(
        title: _selected!,
        onBack: () => setState(() => _selected = null),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 14.0;
        final blockWidth = (box.maxWidth - gap) / 2;
        final blockHeight = (box.maxHeight - gap) / 2;
        return Stack(
          fit: StackFit.expand,
          children: [
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: gap,
              mainAxisSpacing: gap,
              childAspectRatio: blockWidth / blockHeight,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _NowOverviewBlock(
                  isLive: false,
                  onOpen: () => setState(() => _selected = 'Яг одоо'),
                ),
                _RankingOverviewBlock(
                    onOpen: () => setState(() => _selected = 'Чансаа')),
                _ReportOverviewBlock(
                    onOpen: () => setState(() => _selected = 'Тайлан')),
                _OtherOverviewBlock(
                    onOpen: () => setState(() => _selected = 'Бусад')),
              ],
            ),
            if (widget.settingsOpen) ...[
              Positioned.fill(
                child: _SettingsPanel(
                  profileBackground: widget.profileBackground,
                  cardBorder: widget.cardBorder,
                  avatarBytes: widget.avatarBytes,
                  hasPaymentAccount: widget.hasPaymentAccount,
                  bankDetails: widget.bankDetails,
                  onClose: widget.onCloseSettings,
                  onSave: widget.onSaveSettings,
                ),
              ),
            ],
            if (widget.qrOpen) ...[
              const Positioned.fill(
                  child: ColoredBox(color: Color(0x99061B28))),
              Center(
                child: SizedBox(
                  width: box.maxHeight < box.maxWidth
                      ? box.maxHeight
                      : box.maxWidth - 32,
                  height: box.maxHeight < box.maxWidth
                      ? box.maxHeight
                      : box.maxWidth - 32,
                  child: _PaymentQrPanel(onClose: widget.onCloseQr, bankDetails: widget.bankDetails),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _NowOverviewBlock extends StatefulWidget {
  const _NowOverviewBlock(
      {required this.isLive,
      required this.onOpen,
      this.gameName,
      this.playerInitials = const []});

  final bool isLive;
  final String? gameName;
  final List<String> playerInitials;
  final VoidCallback onOpen;

  @override
  State<_NowOverviewBlock> createState() => _NowOverviewBlockState();
}

class _NowOverviewBlockState extends State<_NowOverviewBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 850));
    if (widget.isLive) _pulseController.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _NowOverviewBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLive && !oldWidget.isLive) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isLive && oldWidget.isLive) {
      _pulseController.stop();
      _pulseController.value = 1;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liveColor =
        widget.isLive ? const Color(0xFFFF5C5C) : const Color(0xFF7B949C);
    return Material(
      color: const Color(0xFF0A2735),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: widget.onOpen,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF1B4250))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) => Opacity(
                  opacity:
                      widget.isLive ? .45 + _pulseController.value * .55 : 1,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                              color: liveColor, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text('LIVE',
                          style: TextStyle(
                              color: liveColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .8)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (widget.isLive) ...[
                Text(widget.gameName ?? 'Тоглолт',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                _LivePlayerAvatars(initials: widget.playerInitials),
                const SizedBox(height: 10),
              ],
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Яг одоо',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900)),
                  SizedBox(width: 6),
                  Text('(Идэвхтэй тоглолт, ширээ)',
                      style: TextStyle(color: Color(0xFFA9C2C9), fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LivePlayerAvatars extends StatelessWidget {
  const _LivePlayerAvatars({required this.initials});
  final List<String> initials;

  @override
  Widget build(BuildContext context) {
    final shown = initials.take(4).toList();
    final extra = initials.length - shown.length;
    return SizedBox(
      height: 30,
      width: 35 + shown.length * 23 + (extra > 0 ? 30 : 0),
      child: Stack(
        children: [
          for (var index = 0; index < shown.length; index++)
            Positioned(
              left: index * 23,
              child: CircleAvatar(
                radius: 15,
                backgroundColor: const Color(0xFF59D5C3),
                child: Text(shown[index],
                    style: const TextStyle(
                        color: Color(0xFF082431),
                        fontSize: 11,
                        fontWeight: FontWeight.w900)),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * 23,
              child: CircleAvatar(
                radius: 15,
                backgroundColor: const Color(0xFF1B4250),
                child: Text('+$extra',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800)),
              ),
            ),
        ],
      ),
    );
  }
}

class _RankingOverviewBlock extends StatelessWidget {
  const _RankingOverviewBlock({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF0A2735),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF1B4250))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Center(
                    child: _RankingShiftTable(),
                  ),
                ),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Чансаа',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w900)),
                    SizedBox(width: 6),
                    Text('(Чансааны өөрчлөлт, онцгой амжилт)',
                        style:
                            TextStyle(color: Color(0xFFA9C2C9), fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _RankingShiftTable extends StatelessWidget {
  const _RankingShiftTable();

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF103342),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1B4250)),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RankShiftRow(initial: 'А', from: '1', to: '1', improved: null),
            Divider(height: 12, color: Color(0xFF1B4250)),
            _RankShiftRow(initial: 'Б', from: '3', to: '2', improved: true),
            Divider(height: 12, color: Color(0xFF1B4250)),
            _RankShiftRow(initial: 'Т', from: '2', to: '3', improved: false),
          ],
        ),
      );
}

class _RankShiftRow extends StatelessWidget {
  const _RankShiftRow(
      {required this.initial,
      required this.from,
      required this.to,
      required this.improved});
  final String initial;
  final String from;
  final String to;
  final bool? improved;

  @override
  Widget build(BuildContext context) {
    final color = improved == null
        ? const Color(0xFFF4C96B)
        : improved!
            ? const Color(0xFF35C98D)
            : const Color(0xFFFF6F6F);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
            radius: 13,
            backgroundColor: const Color(0xFF2B5B68),
            child: improved == null
                ? const Icon(Icons.workspace_premium_rounded,
                    color: Color(0xFFF4C96B), size: 17)
                : Text(initial,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900))),
        const SizedBox(width: 16),
        Text('#$from',
            style: const TextStyle(
                color: Color(0xFFA9C2C9), fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Icon(
            improved == null
                ? Icons.remove_rounded
                : improved!
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
            color: color,
            size: 20),
        const SizedBox(width: 8),
        Text('#$to',
            style: TextStyle(color: color, fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _OtherOverviewBlock extends StatelessWidget {
  const _OtherOverviewBlock({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF0A2735),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF1B4250))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Center(
                    child: SizedBox(
                      width: 118,
                      height: 118,
                      child: GridView.count(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        physics: NeverScrollableScrollPhysics(),
                        children: [
                          _OtherQuickIcon(
                              icon: Icons.groups_2_outlined,
                              color: Color(0xFF59D5C3)),
                          _OtherQuickIcon(
                              icon: Icons.mail_outline_rounded,
                              color: Color(0xFFF4C96B)),
                          _OtherQuickIcon(
                              icon: Icons.notifications_none_rounded,
                              color: Color(0xFF7CB8FF)),
                          _OtherQuickIcon(
                              icon: Icons.help_outline_rounded,
                              color: Color(0xFFEAA6FF)),
                        ],
                      ),
                    ),
                  ),
                ),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Бусад',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w900)),
                    SizedBox(width: 6),
                    Text('(Бүлгийн удирдлага болон бусад…)',
                        style:
                            TextStyle(color: Color(0xFFA9C2C9), fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _OtherQuickIcon extends StatelessWidget {
  const _OtherQuickIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
            color: color.withOpacity(.14),
            borderRadius: BorderRadius.circular(14)),
        child: Center(child: Icon(icon, color: color, size: 29)),
      );
}

class _ReportOverviewBlock extends StatelessWidget {
  const _ReportOverviewBlock({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF0A2735),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF1B4250))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: CustomPaint(
                        painter: _TrendChartPainter(),
                        child: const SizedBox.expand())),
                const SizedBox(height: 10),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Тайлан',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w900)),
                    SizedBox(width: 6),
                    Text('(Үр дүн, хожил, статистик)',
                        style:
                            TextStyle(color: Color(0xFFA9C2C9), fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _TrendChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFF1B4250)
      ..strokeWidth = 1;
    for (var fraction = .25; fraction < 1; fraction += .25) {
      canvas.drawLine(Offset(0, size.height * fraction),
          Offset(size.width, size.height * fraction), gridPaint);
    }

    final points = [
      Offset(size.width * .04, size.height * .72),
      Offset(size.width * .23, size.height * .46),
      Offset(size.width * .42, size.height * .62),
      Offset(size.width * .63, size.height * .25),
      Offset(size.width * .88, size.height * .40),
    ];
    final trendPaint = Paint()
      ..color = const Color(0xFF59D5C3)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(line, trendPaint);

    final pointPaint = Paint()..color = const Color(0xFFF4C96B);
    for (final point in points) {
      canvas.drawCircle(point, 4, pointPaint);
    }

    final end = points.last;
    final arrow = Path()
      ..moveTo(end.dx + 12, end.dy - 8)
      ..lineTo(end.dx + 12, end.dy + 8)
      ..lineTo(end.dx + 25, end.dy)
      ..close();
    canvas.drawPath(arrow, Paint()..color = const Color(0xFF35C98D));
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) => false;
}

class _DashboardDetail extends StatelessWidget {
  const _DashboardDetail({required this.title, required this.onBack});
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final statistics = [
      ('Нийт тоглолт', '—', Icons.casino_outlined),
      ('Хожил', '—', Icons.emoji_events_outlined),
      ('Хожигдол', '—', Icons.trending_down_outlined),
      ('Хожлын хувь', '— %', Icons.percent_rounded),
      ('Нийт ашиг / алдагдал', '— ₮', Icons.account_balance_wallet_outlined),
      ('Дундаж дүн', '— ₮', Icons.analytics_outlined),
    ];
    final items = title == 'Тайлан'
        ? statistics
        : [('Одоогоор мэдээлэл алга', '—', Icons.hourglass_empty_rounded)];
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0A2735),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1B4250)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                  tooltip: 'Буцах',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white)),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900)),
            ],
          ),
          const Divider(color: Color(0xFF1B4250)),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.count(
              crossAxisCount: title == 'Тайлан' ? 3 : 1,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: title == 'Тайлан' ? 1.4 : 3.5,
              physics: const NeverScrollableScrollPhysics(),
              children: items
                  .map((item) => _DetailMetric(
                      label: item.$1, value: item.$2, icon: item.$3))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _NowDashboardDetail extends StatelessWidget {
  const _NowDashboardDetail({
    required this.onBack,
    required this.canManageGames,
  });

  final VoidCallback onBack;
  final bool canManageGames;

  void _startNewGame(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerSelectionPage(
          currentUserId: FirebaseAuth.instance.currentUser?.uid,
          canManageGames: canManageGames,
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, BoxConstraints constraints) {
    final title = Row(
      children: [
        IconButton(
          tooltip: 'Буцах',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
        const SizedBox(width: 6),
        const Text(
          'Яг одоо',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
    final startButton = FilledButton.icon(
      onPressed: () => _startNewGame(context),
      style: FilledButton.styleFrom(
        foregroundColor: const Color(0xFF06202D),
        backgroundColor: const Color(0xFFF4C96B),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      ),
      icon: const Icon(Icons.add_circle_outline_rounded),
      label: const Text(
        'Шинэ тоглолт эхлүүлэх',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
    );

    if (constraints.maxWidth < 600) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          const SizedBox(height: 10),
          startButton,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: title),
        startButton,
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF0A2735),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF1B4250)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
                builder: (context, box) => _buildHeader(context, box)),
            const Divider(color: Color(0xFF1B4250)),
            const SizedBox(height: 12),
            const Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _GameTableSection(
                      title: 'Идэвхтэй тоглолтууд',
                      icon: Icons.play_circle_outline_rounded,
                      columns: ['Бүлэг', 'Тоглоом', 'Тоглогчид', 'Төлөв'],
                      emptyMessage: 'Одоогоор идэвхтэй тоглолт алга байна.',
                    ),
                    SizedBox(height: 16),
                    _GameTableSection(
                      title: 'Хадгалсан тоглолтууд',
                      icon: Icons.bookmark_border_rounded,
                      columns: ['Бүлэг', 'Тоглоом', 'Хадгалсан', 'Төлөв'],
                      emptyMessage: 'Одоогоор хадгалсан тоглолт алга байна.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _GameTableSection extends StatelessWidget {
  const _GameTableSection({
    required this.title,
    required this.icon,
    required this.columns,
    required this.emptyMessage,
  });

  final String title;
  final IconData icon;
  final List<String> columns;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF103342),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1B4250)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Row(
                children: [
                  Icon(icon, color: const Color(0xFF59D5C3), size: 21),
                  const SizedBox(width: 9),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF1B4250)),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 760,
                child: Column(
                  children: [
                    Container(
                      color: const Color(0xFF0D2D3B),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          for (final column in columns)
                            Expanded(
                              child: Text(
                                column,
                                style: const TextStyle(
                                  color: Color(0xFFA9C2C9),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 20,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.inbox_outlined,
                            color: Color(0xFF7B949C),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            emptyMessage,
                            style: const TextStyle(
                              color: Color(0xFFA9C2C9),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _DetailMetric extends StatelessWidget {
  const _DetailMetric(
      {required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFF103342),
            borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: const Color(0xFF59D5C3)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(color: Color(0xFFA9C2C9), fontSize: 12)),
        ]),
      );
}

class _ProfileSettings {
  const _ProfileSettings({
    required this.profileBackground,
    required this.cardBorder,
    required this.avatarBytes,
    required this.hasPaymentAccount,
    required this.bankDetails,
  });

  final Color profileBackground;
  final Color cardBorder;
  final Uint8List? avatarBytes;
  final bool hasPaymentAccount;
  final BankDetails bankDetails;
}

class _SettingsPanel extends StatefulWidget {
  const _SettingsPanel({
    required this.profileBackground,
    required this.cardBorder,
    required this.avatarBytes,
    required this.hasPaymentAccount,
    required this.bankDetails,
    required this.onClose,
    required this.onSave,
  });

  final Color profileBackground;
  final Color cardBorder;
  final Uint8List? avatarBytes;
  final bool hasPaymentAccount;
  final BankDetails bankDetails;
  final VoidCallback onClose;
  final Future<void> Function(_ProfileSettings) onSave;

  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel> {
  bool _saving = false;

  Future<void> _save() async {
    final details = _addAccount ? BankDetails(bank: _bankController.text,
      iban: _ibanController.text, account: _accountController.text) : const BankDetails();
    if (_addAccount && !details.complete) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Банкны нэр, IBAN, дансны дугаараа бүрэн оруулна уу.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(_ProfileSettings(
        profileBackground: _background, cardBorder: _border,
        avatarBytes: _avatarBytes, hasPaymentAccount: details.complete, bankDetails: details));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Профайлыг хадгалж чадсангүй. Холболтоо шалгаад дахин оролдоно уу.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
  static const _colorPalette = [
    Color(0xFF0A3342),
    Color(0xFF17616D),
    Color(0xFF24365D),
    Color(0xFF315B3C),
    Color(0xFF55334E),
    Color(0xFF6B3C2D),
    Color(0xFF3D4655),
    Color(0xFF111827),
    Color(0xFF2A6F97),
    Color(0xFF00796B),
    Color(0xFF5B5FC7),
    Color(0xFF7B1E3A),
    Color(0xFF8A4B08),
    Color(0xFF6B7A14),
    Color(0xFF455A64),
    Color(0xFFF4C96B),
    Color(0xFF55D7E8),
    Color(0xFFEAA6FF),
    Color(0xFF6ACB78),
    Color(0xFFFF7A7A),
    Color(0xFFFFA94D),
    Color(0xFFFFE066),
    Color(0xFFB5E48C),
    Color(0xFFA5D8FF),
    Color(0xFFCDB4DB),
    Color(0xFFFFC8DD),
  ];

  late Color _background;
  late Color _border;
  Uint8List? _avatarBytes;
  late bool _addAccount;
  final _bankController = TextEditingController();
  final _ibanController = TextEditingController();
  final _accountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _background = widget.profileBackground;
    _border = widget.cardBorder;
    _avatarBytes = widget.avatarBytes;
    _addAccount = widget.hasPaymentAccount;
    _bankController.text = widget.bankDetails.bank;
    _ibanController.text = widget.bankDetails.iban;
    _accountController.text = widget.bankDetails.account;
  }

  @override
  void dispose() {
    _bankController.dispose();
    _ibanController.dispose();
    _accountController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 900,
      maxHeight: 900,
      imageQuality: 88,
    );
    if (image == null || !mounted) return;
    Uint8List bytes;
    try {
      bytes = await prepareAvatar(await image.readAsBytes());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Зураг боловсруулах боломжгүй байна. Өөр зураг сонгоно уу.')));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _avatarBytes = bytes);
  }

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFFF7F4EC),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                      child: Text('Профайлын тохиргоо',
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                              color: Color(0xFF082431)))),
                  IconButton(
                      onPressed: widget.onClose,
                      tooltip: 'Гарах',
                      icon: const Icon(Icons.close_rounded)),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 132,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      onTap: _saving ? null : _pickAvatar,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 132,
                        decoration: BoxDecoration(
                            color: _background,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _border, width: 3)),
                        child: _avatarBytes == null
                            ? const Icon(Icons.add_a_photo_outlined,
                                color: Colors.white, size: 42)
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(11),
                                child: Image.memory(_avatarBytes!,
                                    fit: BoxFit.cover)),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: _ColorChoice(
                                  title: 'Дэвсгэр өнгө',
                                  selected: _background,
                                  unavailable: _border,
                                  colors: _colorPalette,
                                  onSelected: (color) =>
                                      setState(() => _background = color))),
                          const SizedBox(height: 10),
                          Expanded(
                              child: _ColorChoice(
                                  title: 'Хүрээний өнгө',
                                  selected: _border,
                                  unavailable: _background,
                                  colors: _colorPalette,
                                  onSelected: (color) =>
                                      setState(() => _border = color))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 28),
              Row(
                children: [
                  const Expanded(
                      child: Text('Дансны мэдээлэл нэмэх үү?',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF082431)))),
                  Tooltip(
                      message:
                          'Дансны мэдээлэл хадгалагдсаны дараа мэдээллийн QR код идэвхжинэ.',
                      child: Icon(Icons.info_outline_rounded,
                          color: Colors.blueGrey.shade600, size: 19)),
                  Switch(
                      value: _addAccount,
                      onChanged: (value) =>
                          setState(() => _addAccount = value)),
                ],
              ),
              if (_addAccount) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                        child: _CompactField(
                            controller: _bankController, label: 'Банкны нэр')),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _CompactField(
                            controller: _ibanController, label: 'IBAN')),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _CompactField(
                            controller: _accountController,
                            label: 'Дансны дугаар',
                            keyboardType: TextInputType.number)),
                  ],
                ),
              ],
              const Spacer(),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 160,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Хадгалж байна…' : 'Хадгалах'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice(
      {required this.title,
      required this.selected,
      required this.unavailable,
      required this.colors,
      required this.onSelected});
  final String title;
  final Color selected;
  final Color unavailable;
  final List<Color> colors;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF082431))),
          const SizedBox(height: 4),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: colors.map((color) {
              final isUnavailable = color == unavailable;
              return Opacity(
                opacity: isUnavailable ? .22 : 1,
                child: InkWell(
                  onTap: isUnavailable ? null : () => onSelected(color),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: selected == color
                              ? const Color(0xFF082431)
                              : Colors.transparent,
                          width: 3),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      );
}

class _CompactField extends StatelessWidget {
  const _CompactField(
      {required this.controller, required this.label, this.keyboardType});
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );
}

class _PaymentQrPanel extends StatelessWidget {
  const _PaymentQrPanel({required this.onClose, required this.bankDetails});
  final VoidCallback onClose;
  final BankDetails bankDetails;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFFF7F4EC),
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                      child: Text('Дансны мэдээллийн QR',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF082431)))),
                  IconButton(
                      onPressed: onClose,
                      tooltip: 'Хаах',
                      icon: const Icon(Icons.close_rounded)),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, box) => Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.white,
                      child: QrImageView(
                        data: bankDetails.qrText,
                        size: (box.maxWidth < box.maxHeight
                            ? box.maxWidth
                            : box.maxHeight) - 32,
                        eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Color(0xFF082431)),
                        dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Color(0xFF082431)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.username,
    required this.profileName,
    required this.hasPaymentAccount,
    required this.canManageGames,
    required this.isSystemAdmin,
    required this.profileBackground,
    required this.cardBorder,
    required this.avatarBytes,
    required this.onProfile,
    this.onQr,
    this.onAdmin,
  });
  final String username;
  final String profileName;
  final bool hasPaymentAccount;
  final bool canManageGames;
  final bool isSystemAdmin;
  final Color profileBackground;
  final Color cardBorder;
  final Uint8List? avatarBytes;
  final VoidCallback onProfile;
  final VoidCallback? onQr;
  final VoidCallback? onAdmin;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 330,
          child: AspectRatio(
            // Keep the avatar square while making the lower card area compact.
            aspectRatio: .73,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F0E4),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cardBorder, width: 3),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black45,
                      blurRadius: 24,
                      offset: Offset(0, 15))
                ],
              ),
              child: Column(
                children: [
                  Expanded(
                    flex: 11,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const ColoredBox(color: Colors.white),
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.all(30),
                            child: avatarBytes == null
                                ? Container(
                                    color: profileBackground,
                                    child: Center(
                                      child: Text(
                                        profileName.isEmpty
                                            ? '?'
                                            : profileName
                                                .substring(0, 1)
                                                .toUpperCase(),
                                        style: const TextStyle(
                                            color: Color(0xFFF4C96B),
                                            fontSize: 112,
                                            fontWeight: FontWeight.w900),
                                      ),
                                    ),
                                  )
                                : Image.memory(avatarBytes!, fit: BoxFit.cover),
                          ),
                        ),
                        const Positioned.fill(
                          child: Padding(
                            padding: EdgeInsets.all(26),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.fromBorderSide(BorderSide(
                                    color: Colors.white, width: 1.5)),
                              ),
                            ),
                          ),
                        ),
                        const Positioned.fill(child: _SuitFrame()),
                        if (isSystemAdmin)
                          Positioned(
                            top: 38,
                            right: 38,
                            child: IconButton(
                              tooltip: 'Системийн удирдлага',
                              onPressed: onAdmin,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                  width: 38, height: 38),
                              icon: SizedBox(
                                width: 32,
                                height: 32,
                                child: Image.asset(
                                    'assets/system_admin_shield.png',
                                    fit: BoxFit.contain),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 90,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.center,
                                    child: Text(
                                        username.isEmpty ? '—' : username,
                                        maxLines: 1,
                                        style: const TextStyle(
                                            color: Color(0xFF082431),
                                            fontSize: 36,
                                            fontWeight: FontWeight.w900)),
                                  ),
                                  const SizedBox(height: 6),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.center,
                                    child: Text(
                                        profileName.isEmpty ? '—' : profileName,
                                        maxLines: 1,
                                        style: const TextStyle(
                                            color: Color(0xFF46616A),
                                            fontSize: 20,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _ProfileActionGrid(
                              hasPaymentAccount: hasPaymentAccount,
                              onSettings: onProfile,
                              onQr: onQr),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _CardSuit extends StatelessWidget {
  const _CardSuit({required this.symbol, required this.color});
  final String symbol;
  final Color color;
  @override
  Widget build(BuildContext context) => Text(symbol,
      style:
          TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.bold));
}

/// Repeats the four suits around the exact center of the white border band.
/// It measures the avatar panel at runtime so the frame stays complete if the
/// card is resized for a smaller screen.
class _SuitFrame extends StatelessWidget {
  const _SuitFrame();

  static const _symbols = ['♠', '♦', '♣', '♥'];
  static const _colors = [Colors.black, Colors.red, Colors.black, Colors.red];

  _CardSuit _suit(int index) =>
      _CardSuit(symbol: _symbols[index % 4], color: _colors[index % 4]);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          const count = 9;
          const bandCenter = 15.0;
          const symbolHalf = 8.5;
          final horizontalStep = (box.maxWidth - 80) / (count - 1);
          final verticalStep = (box.maxHeight - 90) / (count - 1);
          return Stack(
            children: [
              for (var i = 0; i < count; i++)
                Positioned(
                  top: bandCenter - symbolHalf,
                  left: 40 + horizontalStep * i - symbolHalf,
                  child: _suit(i),
                ),
              for (var i = 0; i < count; i++)
                Positioned(
                  bottom: bandCenter - symbolHalf,
                  left: 40 + horizontalStep * i - symbolHalf,
                  child: _suit(i + 2),
                ),
              for (var i = 0; i < count; i++)
                Positioned(
                  left: bandCenter - symbolHalf,
                  top: 45 + verticalStep * i - symbolHalf,
                  child: _suit(i + 3),
                ),
              for (var i = 0; i < count; i++)
                Positioned(
                  right: bandCenter - symbolHalf,
                  top: 45 + verticalStep * i - symbolHalf,
                  child: _suit(i + 1),
                ),
            ],
          );
        },
      );
}

class _ProfileActionGrid extends StatelessWidget {
  const _ProfileActionGrid(
      {required this.hasPaymentAccount, required this.onSettings, this.onQr});
  final bool hasPaymentAccount;
  final VoidCallback onSettings;
  final VoidCallback? onQr;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 90,
        height: 90,
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _ProfileActionIcon(
                icon: Icons.settings_outlined,
                tooltip: 'Тохиргоо',
                onPressed: onSettings),
            _ProfileActionIcon(
                icon: Icons.qr_code_2_rounded,
                tooltip: 'Төлбөрийн QR',
                muted: !hasPaymentAccount,
                onPressed: onQr),
            const _ProfileActionIcon(
                icon: Icons.keyboard_alt_rounded, tooltip: 'Бүртгэгчийн эрх'),
            const _ProfileActionIcon(
                icon: Icons.groups_2_outlined, tooltip: 'Бүлэг'),
          ],
        ),
      );
}

class _ProfileActionIcon extends StatelessWidget {
  const _ProfileActionIcon(
      {required this.icon,
      required this.tooltip,
      this.muted = false,
      this.onPressed});
  final IconData icon;
  final String tooltip;
  final bool muted;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: muted ? .28 : 1,
        child: Material(
          color: const Color(0xFFD8E2DD),
          borderRadius: BorderRadius.circular(12),
          child: IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            padding: EdgeInsets.zero,
            iconSize: 26,
            color: const Color(0xFF17616D),
            icon: Icon(icon),
          ),
        ),
      );
}

class _LatestGameCard extends StatelessWidget {
  const _LatestGameCard(
      {this.gameName, this.playerCount, this.netAmount, this.rankImproved, this.isTrial = false});
  final bool isTrial;

  final String? gameName;
  final int? playerCount;
  final int? netAmount;
  final bool? rankImproved;

  @override
  Widget build(BuildContext context) {
    final amountColor = netAmount == null
        ? const Color(0xFFA9C2C9)
        : netAmount! >= 0
            ? const Color(0xFF35C98D)
            : const Color(0xFFFF6F6F);
    final amountText = netAmount == null
        ? '— ₮'
        : '${netAmount! >= 0 ? '+' : ''}${netAmount!} ₮';
    final rankIcon = rankImproved == null
        ? Icons.remove_rounded
        : rankImproved!
            ? Icons.arrow_upward_rounded
            : Icons.arrow_downward_rounded;
    final rankColor = rankImproved == null
        ? const Color(0xFFA9C2C9)
        : rankImproved!
            ? const Color(0xFF35C98D)
            : const Color(0xFFFF6F6F);

    return Container(
      height: 88,
      decoration: BoxDecoration(
        color: const Color(0xFF0A2735),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFF1B4250)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 32,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(isTrial ? 'Таны сүүлийн тоглолт · Туршилт' : 'Таны сүүлийн тоглолт',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFF1B4250)),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _LatestGameCell(value: gameName ?? '—'),
                _LatestGameCell(value: playerCount?.toString() ?? '—'),
                _LatestGameCell(value: amountText, valueColor: amountColor),
                _LatestGameCell(
                    icon: rankIcon, iconColor: rankColor, last: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LatestGameCell extends StatelessWidget {
  const _LatestGameCell(
      {this.value,
      this.valueColor,
      this.icon,
      this.iconColor,
      this.last = false});
  final String? value;
  final Color? valueColor;
  final IconData? icon;
  final Color? iconColor;
  final bool last;

  @override
  Widget build(BuildContext context) => Flexible(
        fit: FlexFit.loose,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 96),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: last
              ? null
              : const BoxDecoration(
                  border: Border(right: BorderSide(color: Color(0xFF1B4250)))),
          child: Center(
            child: icon != null
                ? Icon(icon, color: iconColor, size: 22)
                : Text(
                    value ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: valueColor ?? Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800),
                  ),
          ),
        ),
      );
}
