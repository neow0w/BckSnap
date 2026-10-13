import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_client.dart';
import '../../services/auth_service.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({this.nextRoute = '/home', super.key});

  final String nextRoute;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _lastNameCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _middleInitialCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _auth = AuthService();

  DateTime? _birthdate;
  String? _gender;
  bool _loading = false;
  bool _hidePassword = true;
  bool _hideConfirmation = true;
  String? _error;

  @override
  void dispose() {
    _lastNameCtrl.dispose();
    _firstNameCtrl.dispose();
    _middleInitialCtrl.dispose();
    _addressCtrl.dispose();
    _emailCtrl.dispose();
    _contactCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _selectBirthdate() async {
    final now = DateUtils.dateOnly(DateTime.now());
    final defaultDate = DateTime(now.year - 18, now.month, now.day);
    final selected = await showDatePicker(
      context: context,
      initialDate: _birthdate ?? (defaultDate.isAfter(now) ? now : defaultDate),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Select birthdate',
    );
    if (selected != null && mounted) {
      setState(() => _birthdate = DateUtils.dateOnly(selected));
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (_birthdate == null) {
      setState(() => _error = 'Please select your birthdate.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _auth.signUp(
        firstName: _firstNameCtrl.text.trim(),
        middleInitial: _middleInitialCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        birthdate: _formatDate(_birthdate!),
        address: _addressCtrl.text.trim(),
        gender: _gender!,
        email: _emailCtrl.text.trim(),
        contactNumber: _contactCtrl.text.trim(),
        password: _passwordCtrl.text,
        confirmPassword: _confirmCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created successfully.')),
      );
      context.go(widget.nextRoute);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      debugPrint('Account registration failed: $error');
      if (mounted) {
        setState(
          () => _error =
              'Unable to create the account right now. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String? _required(String? value, String field) =>
      value == null || value.trim().isEmpty ? '$field is required.' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(
                widget.nextRoute == '/screening/photo' ? '/' : '/login',
              );
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Create your BckSnap account',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle(context, 'Personal information'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _lastNameCtrl,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Last Name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => _required(value, 'Last name'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _firstNameCtrl,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'First Name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => _required(value, 'First name'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _middleInitialCtrl,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.next,
                      maxLength: 2,
                      decoration: const InputDecoration(
                        labelText: 'Middle Initial (optional)',
                        hintText: 'M or M.',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      validator: (value) {
                        final initial = value?.trim() ?? '';
                        if (initial.isNotEmpty &&
                            !RegExp(r'^[A-Za-z]\.?$').hasMatch(initial)) {
                          return 'Enter one letter, optionally followed by a period.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _selectBirthdate,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(
                        _birthdate == null
                            ? 'Select Birthdate'
                            : MaterialLocalizations.of(context)
                                  .formatMediumDate(_birthdate!),
                      ),
                    ),
                    if (_birthdate == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('Birthdate is required.'),
                      ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _addressCtrl,
                      textCapitalization: TextCapitalization.words,
                      keyboardType: TextInputType.streetAddress,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => _required(value, 'Address'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _gender,
                      decoration: const InputDecoration(
                        labelText: 'Gender',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'male', child: Text('Male')),
                        DropdownMenuItem(
                          value: 'female',
                          child: Text('Female'),
                        ),
                        DropdownMenuItem(
                          value: 'prefer_not_to_say',
                          child: Text('Prefer not to say'),
                        ),
                      ],
                      onChanged: _loading
                          ? null
                          : (value) => setState(() => _gender = value),
                      validator: (value) =>
                          value == null ? 'Please select your gender.' : null,
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle(context, 'Contact information'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email Address',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (email.isEmpty) return 'Email address is required.';
                        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                            .hasMatch(email)) {
                          return 'Enter a valid email address.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _contactCtrl,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Contact Number',
                        hintText: '09XXXXXXXXX or +639XXXXXXXXX',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final number = value?.trim() ?? '';
                        if (number.isEmpty) {
                          return 'Contact number is required.';
                        }
                        final compact = number.replaceAll(
                          RegExp(r'[\s()-]'),
                          '',
                        );
                        if (!RegExp(r'^(09\d{9}|\+639\d{9})$')
                            .hasMatch(compact)) {
                          return 'Enter a valid Philippine mobile number.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle(context, 'Account security'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _hidePassword,
                      maxLength: 72,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText: 'Use at least 8 characters.',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _hidePassword
                              ? 'Show password'
                              : 'Hide password',
                          icon: Icon(
                            _hidePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () =>
                              setState(() => _hidePassword = !_hidePassword),
                        ),
                      ),
                      validator: (value) => (value == null || value.length < 8)
                          ? 'Password must be at least 8 characters.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmCtrl,
                      obscureText: _hideConfirmation,
                      maxLength: 72,
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _hideConfirmation
                              ? 'Show confirmation'
                              : 'Hide confirmation',
                          icon: Icon(
                            _hideConfirmation
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () => setState(
                            () => _hideConfirmation = !_hideConfirmation,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please confirm your password.';
                        }
                        return value != _passwordCtrl.text
                            ? 'Passwords do not match.'
                            : null;
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Create Account'),
                    ),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => context.push(
                              Uri(
                                path: '/login',
                                queryParameters: {'next': widget.nextRoute},
                              ).toString(),
                            ),
                      child: const Text('Already have an account? Log In'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) => Text(
    title,
    style: Theme.of(context).textTheme.titleMedium
        ?.copyWith(fontWeight: FontWeight.bold),
  );
}
