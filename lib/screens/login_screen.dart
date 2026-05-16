import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/user_context.dart';
import 'force_password_change_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _melcoController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _melcoController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final melcoId = _melcoController.text.trim();
      if (melcoId.isEmpty || !RegExp(r'^\d+$').hasMatch(melcoId)) {
        throw Exception('Enter a valid numeric Melco ID.');
      }

      await AuthService.signInWithMelcoId(
        melcoId: melcoId,
        password: _passwordController.text,
      );

      final profile = await AuthService.currentUserProfile();
      if (profile == null || profile['active'] != true) {
        await AuthService.signOut();
        throw Exception('Account not authorized.');
      }

      UserContext.melcoId = profile['melcoId']?.toString();
      UserContext.role = profile['role']?.toString();
      UserContext.displayName =
          profile['displayName']?.toString() ?? profile['employeeName']?.toString();

      if (!mounted) return;

      final mustChange = profile['mustChangePassword'] == true ||
          profile['requirePasswordChange'] == true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => mustChange ? const ForcePasswordChangeScreen() : const HomeScreen(),
        ),
      );
    } catch (e) {
      setState(() => _error = 'Login failed. Check Melco ID and password.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: bottomInset > 0 ? 12 : 0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('HODW AQX Login', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 20),
                              TextField(
                                controller: _melcoController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Melco ID', border: OutlineInputBorder()),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _passwordController,
                                obscureText: true,
                                decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                              ),
                              const SizedBox(height: 12),
                              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                              if (_loading) const SizedBox(height: 12),
                              if (_loading) const LinearProgressIndicator(),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _loading ? null : _login,
                                  child: Text(_loading ? 'Signing in...' : 'Login'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
