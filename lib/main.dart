import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/member_dashboard.dart';
import 'screens/system_admin_dashboard.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'utils/firebase_initializer.dart';
import 'utils/firebase_auth_web_registrar_stub.dart'
    if (dart.library.html) 'utils/firebase_auth_web_registrar.dart';
import 'firebase_options.dart';
import 'utils/local_debug_file.dart';

// Set to true when Firebase successfully initialized.
bool firebaseInitialized = false;
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void returnToCleanLogin() {
  FirebaseAuth.instance.signOut();
  rootNavigatorKey.currentState?.pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    (_) => false,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFirebaseAuthWebPlugin();

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
      navigatorKey: rootNavigatorKey,
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
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _registrationPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _hideFirebaseWarning = false;
  bool _isRegistration = false;
  bool _obscureRegistrationPassword = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _lastNameController.dispose();
    _firstNameController.dispose();
    _nicknameController.dispose();
    _phoneController.dispose();
    _registrationPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _clearSensitiveInputs() {
    _passwordController.clear();
    _registrationPasswordController.clear();
    _confirmPasswordController.clear();
    FocusScope.of(context).unfocus();
    TextInput.finishAutofillContext(shouldSave: false);
  }

  bool get _canLogin =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
          .hasMatch(_emailController.text.trim()) &&
      _passwordController.text.isNotEmpty;

  bool get _canRegister {
    final phoneDigits =
        _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final password = _registrationPasswordController.text;
    final email = _emailController.text.trim();
    final isSecurePassword = password.length >= 8 &&
        RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password) &&
        RegExp(r'[0-9]').hasMatch(password) &&
        RegExp(r'[^A-Za-z0-9]').hasMatch(password);

    return _lastNameController.text.trim().isNotEmpty &&
        _firstNameController.text.trim().isNotEmpty &&
        _nicknameController.text.trim().isNotEmpty &&
        phoneDigits.length >= 8 &&
        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) &&
        isSecurePassword &&
        password == _confirmPasswordController.text;
  }

  Future<void> _submitRegistration() async {
    if (!_canRegister) return;
    if (Firebase.apps.isEmpty) {
      _showMessage('Firebase эхлүүлэгдээгүй байна.');
      return;
    }

    setState(() => _isSubmitting = true);
    final email = _emailController.text.trim().toLowerCase();
    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: email,
        password: _registrationPasswordController.text,
      );
      final user = credential.user;
      if (user == null) throw StateError('Account үүсгэж чадсангүй.');

      await user.updateDisplayName(_nicknameController.text.trim());
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'lastName': _lastNameController.text.trim(),
        'firstName': _firstNameController.text.trim(),
        'nickname': _nicknameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'email': email,
        'role': 'user',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      try {
        await user.sendEmailVerification();
      } on FirebaseAuthException catch (error) {
        await FirebaseAuth.instance.signOut();
        _clearSensitiveInputs();
        if (!mounted) return;
        setState(() => _isRegistration = false);
        _showMessage(
          'Account үүслээ, гэхдээ баталгаажуулах и-мэйл илгээхэд алдаа гарлаа (${error.code}). Firebase Console-ийн Authentication → Users хэсгээс $email account үүссэн эсэхийг шалгана уу.',
        );
        return;
      }
      await FirebaseAuth.instance.signOut();
      _clearSensitiveInputs();
      if (!mounted) return;
      setState(() => _isRegistration = false);
      _showMessage('Баталгаажуулах холбоосыг $email хаяг руу илгээлээ. И-мэйлээ баталгаажуулаад нэвтэрнэ үү.');
    } on FirebaseAuthException catch (error) {
      _showMessage(_authErrorText(error));
    } catch (_) {
      _showMessage('Бүртгэл хадгалах үед алдаа гарлаа. Дахин оролдоно уу.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showMessage(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _authErrorText(FirebaseAuthException error) {
    debugPrint('Firebase Auth error [${error.code}]: ${error.message}');
    switch (error.code) {
      case 'email-already-in-use':
        return 'Энэ и-мэйл хаягаар account аль хэдийн бүртгэгдсэн байна.';
      case 'weak-password':
        return 'Нууц үг шаардлагыг хангахгүй байна.';
      case 'invalid-email':
        return 'И-мэйл хаяг буруу байна.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'И-мэйл эсвэл нууц үг буруу байна.';
      case 'too-many-requests':
        return 'Олон удаа оролдсон байна. Түр хүлээгээд дахин оролдоно уу.';
      case 'operation-not-allowed':
        return 'Firebase дээр Email/Password нэвтрэх арга идэвхжээгүй байна.';
      case 'network-request-failed':
        return 'Сүлжээний алдаа гарлаа. Интернет холболтоо шалгаад дахин оролдоно уу.';
      case 'app-not-authorized':
        return 'Энэ веб домэйн Firebase Authentication-д зөвшөөрөгдөөгүй байна.';
      case 'captcha-check-failed':
        return 'Аюулгүй байдлын шалгалт амжилтгүй боллоо. Хуудсыг дахин ачааллаад оролдоно уу.';
      case 'channel-error':
        return 'Firebase веб сувгийн холболт амжилтгүй боллоо. Хуудсыг Ctrl+Shift+R-ээр бүрэн ачааллаад дахин оролдоно уу.';
      default:
        return 'Firebase бүртгэлийн алдаа гарлаа (${error.code}).';
    }
  }

  InputDecoration _authDecoration(String label) => InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      );

  Widget _authModeButton({required String label, required bool selected}) {
    return Expanded(
      child: OutlinedButton(
        onPressed: () {
          setState(() {
            _isRegistration = label == 'Бүртгүүлэх';
          });
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: selected ? Colors.white : Colors.deepPurple,
          backgroundColor: selected ? Colors.deepPurple : Colors.white,
          side: const BorderSide(color: Colors.deepPurple, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 15),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _authPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _authModeButton(label: 'Нэвтрэх', selected: !_isRegistration),
            const SizedBox(width: 12),
            _authModeButton(label: 'Бүртгүүлэх', selected: _isRegistration),
          ],
        ),
        const SizedBox(height: 24),
        if (!_isRegistration) ...[
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            onChanged: (_) => setState(() {}),
            decoration: _authDecoration('И-мэйл хаяг'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            autofillHints: const [AutofillHints.password],
            enableSuggestions: false,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _canLogin ? _login() : null,
            decoration: _authDecoration('Нууц үг'),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _canLogin && !_isSubmitting ? _login : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Нэвтрэх'),
            ),
          ),
          TextButton(
            onPressed: _isSubmitting ? null : _sendPasswordReset,
            child: const Text('Нууц үгээ мартсан уу?'),
          ),
          TextButton(
            onPressed: _isSubmitting ? null : _resendEmailVerification,
            child: const Text('Баталгаажуулах и-мэйл дахин илгээх'),
          ),
        ] else ...[
          TextField(
            controller: _lastNameController,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: _authDecoration('Овог'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _firstNameController,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: _authDecoration('Нэр'),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nicknameController,
                  onChanged: (_) => setState(() {}),
                  decoration: _authDecoration('Хоч'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => setState(() {}),
                  decoration: _authDecoration('Утасны дугаар'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
            decoration: _authDecoration('И-мэйл хаяг'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _registrationPasswordController,
            obscureText: _obscureRegistrationPassword,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            decoration: _authDecoration('Нууц үг').copyWith(
              helperText:
                  '8+ тэмдэгт, том/жижиг үсэг, тоо, тусгай тэмдэгт оруулна.',
              suffixIcon: IconButton(
                onPressed: () => setState(
                  () => _obscureRegistrationPassword = !_obscureRegistrationPassword,
                ),
                icon: Icon(
                  _obscureRegistrationPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _confirmPasswordController,
            obscureText: _obscureRegistrationPassword,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            decoration: _authDecoration('Нууц үг давтах'),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _canRegister && !_isSubmitting ? _submitRegistration : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Бүртгүүлэх'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _authCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF1B5E7A).withOpacity(0.22),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x260B2D3A),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: _authPanel(),
    );
  }

  Future<void> _login() async {
    if (!_canLogin || Firebase.apps.isEmpty) {
      _showMessage('И-мэйл, нууц үгээ зөв оруулна уу.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim().toLowerCase(),
        password: _passwordController.text,
      );
      final user = credential.user;
      await user?.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;
      if (refreshedUser == null) throw StateError('Нэвтрэх амжилтгүй боллоо.');
      if (!refreshedUser.emailVerified) {
        await FirebaseAuth.instance.signOut();
        _showMessage('И-мэйлээ баталгаажуулаагүй байна. И-мэйл дэх холбоосоор баталгаажуулаад дахин нэвтэрнэ үү.');
        return;
      }

      final isSystemAdmin = await _ensureSystemAdminClaim(refreshedUser);

      final profile = await FirebaseFirestore.instance
          .collection('users')
          .doc(refreshedUser.uid)
          .get();
      final nickname = (profile.data()?['nickname'] ??
              refreshedUser.displayName ??
              refreshedUser.email ??
              'Хэрэглэгч')
          .toString();
      final firstName = (profile.data()?['firstName'] ?? '').toString().trim();
      final lastName = (profile.data()?['lastName'] ?? '').toString().trim();
      final profileName = firstName.isEmpty
          ? nickname
          : lastName.isEmpty
              ? firstName
              : '${lastName.substring(0, 1)}. $firstName';
      final canManageGames = profile.data()?['canManageGames'] == true;
      final hasPaymentAccount = (profile.data()?['accountNumber'] ?? '')
          .toString()
          .trim()
          .isNotEmpty;
      _clearSensitiveInputs();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MemberDashboard(
            username: nickname,
            profileName: profileName,
            hasPaymentAccount: hasPaymentAccount,
            onLogout: returnToCleanLogin,
            canManageGames: canManageGames,
            isSystemAdmin: isSystemAdmin,
            onOpenSystemAdmin: isSystemAdmin
                ? (dashboardContext) => Navigator.of(dashboardContext).push(
                      MaterialPageRoute(
                        builder: (_) => SystemAdminDashboard(
                          onLogout: returnToCleanLogin,
                          onBack: () => Navigator.of(dashboardContext).pop(),
                        ),
                      ),
                    )
                : null,
          ),
        ),
      );
    } on FirebaseAuthException catch (error) {
      _showMessage(_authErrorText(error));
    } catch (_) {
      _showMessage('Профайлын мэдээлэл ачаалах үед алдаа гарлаа.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// The server silently returns false for ordinary users. For the one
  /// configured, verified account it sets a signed custom claim and we force a
  /// token refresh before deciding which controls to display.
  Future<bool> _ensureSystemAdminClaim(User user) async {
    final currentToken = await user.getIdTokenResult();
    if (currentToken.claims?['systemAdmin'] == true) return true;
    try {
      await FirebaseFunctions.instance
          .httpsCallable('bootstrapSystemAdmin')
          .call();
      final refreshedToken = await user.getIdTokenResult(true);
      return refreshedToken.claims?['systemAdmin'] == true;
    } on FirebaseFunctionsException catch (error) {
      // A permission error is the normal outcome for all non-admin accounts.
      debugPrint('System Admin claim was not assigned: ${error.code}');
      return false;
    } catch (error) {
      debugPrint('System Admin claim check failed: $error');
      return false;
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _showMessage('Нууц үг сэргээх и-мэйл хаягаа оруулна уу.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showMessage('Нууц үг сэргээх холбоосыг $email рүү илгээлээ.');
    } on FirebaseAuthException catch (error) {
      _showMessage(_authErrorText(error));
    }
  }

  Future<void> _resendEmailVerification() async {
    if (!_canLogin) {
      _showMessage('И-мэйл болон нууц үгээ оруулна уу.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim().toLowerCase(),
        password: _passwordController.text,
      );
      final user = credential.user;
      await user?.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;
      if (refreshedUser == null) throw StateError('Account олдсонгүй.');
      if (refreshedUser.emailVerified) {
        _showMessage('Энэ и-мэйл хаяг аль хэдийн баталгаажсан байна.');
      } else {
        await refreshedUser.sendEmailVerification();
        _showMessage('Баталгаажуулах холбоосыг дахин илгээлээ. Spam хавтсаа мөн шалгана уу.');
      }
      await FirebaseAuth.instance.signOut();
      _clearSensitiveInputs();
    } on FirebaseAuthException catch (error) {
      _showMessage(_authErrorText(error));
    } catch (_) {
      _showMessage('Баталгаажуулах и-мэйл дахин илгээх үед алдаа гарлаа.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF6FF),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFFEAF6FF),
        ),
        child: SafeArea(
            child: SingleChildScrollView(
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
                  final imageHeight = isSmallScreenLocal
                      ? min(
                          430.0,
                          MediaQuery.of(context).size.height * 0.45,
                        )
                      : MediaQuery.of(context).size.height - 64;

                  if (isSmallScreenLocal) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                            height: imageHeight,
                            child: Image.asset('assets/logo.jpg',
                                fit: BoxFit.contain)),
                        const SizedBox(height: 24),
                        _authCard(),
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
                                child: Image.asset('assets/logo.jpg',
                                    fit: BoxFit.contain)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 40),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _authCard(),
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
          ),
        ),
    );
  }
}
