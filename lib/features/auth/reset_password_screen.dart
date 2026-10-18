import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/validators.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';

/// Fig 7: "Reset Password?" YES -> "Password reset email sent".
/// Step 1 of 2: ask for the email. Step 2 is /reset/confirm.
/// Works for every role (patient, receptionist, doctor).
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  static const int _cooldownSeconds = 60;

  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _auth = AuthService();

  bool _loading = false;
  bool _sent = false; // "Password reset email sent"
  String? _error;
  String _sentTo = '';

  Timer? _timer;
  int _cooldown = 0; // seconds until "Resend" is allowed again

  @override
  void dispose() {
    _timer?.cancel();
    _emailCtrl.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _cooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _send({required String email}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _auth.resetPassword(email);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _sentTo = email;
      });
      _startCooldown();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    _send(email: _emailCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset Password'),
        leading: BackButton(onPressed: () => context.go('/login')),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _sent ? _buildSent() : _buildForm(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorBox() {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Forgot your password?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter the email of your account and we will send you a code '
            'to reset your password.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp(r'\s')),
              LengthLimitingTextInputFormatter(254),
            ],
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
            validator: Validators.email,
            onFieldSubmitted: (_) => _loading ? null : _submit(),
          ),
          _errorBox(),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send reset code'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go('/login'),
            child: const Text('Back to login'),
          ),
        ],
      ),
    );
  }

  Widget _buildSent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.mark_email_read, size: 72, color: Colors.green),
        const SizedBox(height: 16),
        const Text(
          'Password reset email sent',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'If an account exists for $_sentTo, a reset code is on its way. '
          'Check your inbox and spam folder. The code expires after a short '
          'time.',
          textAlign: TextAlign.center,
        ),
        _errorBox(),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => context.go('/reset/confirm', extra: _sentTo),
          child: const Text('I have the code'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: (_loading || _cooldown > 0)
              ? null
              : () => _send(email: _sentTo),
          child: Text(
            _cooldown > 0 ? 'Resend email (${_cooldown}s)' : 'Resend email',
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() {
            _sent = false;
            _error = null;
          }),
          child: const Text('Use a different email'),
        ),
      ],
    );
  }
}
