import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/user_context.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class ForcePasswordChangeScreen extends StatefulWidget {
  const ForcePasswordChangeScreen({super.key});

  @override
  State<ForcePasswordChangeScreen> createState() =>
      _ForcePasswordChangeScreenState();
}

class _ForcePasswordChangeScreenState
    extends State<ForcePasswordChangeScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p1 = _passwordController.text;
      final p2 = _confirmController.text;
      if (p1.length < 8 ||
          !RegExp(r'[A-Za-z]').hasMatch(p1) ||
          !RegExp(r'\d').hasMatch(p1)) {
        throw Exception(
          'Password must contain letters and numbers and be at least 8 characters.',
        );
      }
      if (p1 == 'Welcome2026') {
        throw Exception(
          'New password cannot be the default temporary password Welcome2026.',
        );
      }
      if (p1 != p2) throw Exception('Passwords do not match.');
      await AuthService.changeCurrentPassword(p1);
      final profile = await AuthService.currentUserProfile();
      UserContext.melcoId = profile?['melcoId']?.toString();
      UserContext.role = profile?['role']?.toString();
      UserContext.displayName = profile?['displayName']?.toString() ??
          profile?['employeeName']?.toString();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _backToLogin() async {
    UserContext.clear();
    await AuthService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
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
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Change Password',
                                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 10),
                              if ((UserContext.displayName ?? '').trim().isNotEmpty) ...[
                                Text(
                                  'Welcome, ${UserContext.displayName!}',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 8),
                              ],
                              const Text(
                                'You must change your temporary password before using the system.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              TextField(
                                controller: _passwordController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'New Password',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _confirmController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'Confirm Password',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_error != null)
                                Text(_error!, style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _loading ? null : _submit,
                                  child: Text(_loading ? 'Saving...' : 'Save Password'),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _loading ? null : _backToLogin,
                                child: const Text('Back to Login'),
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
