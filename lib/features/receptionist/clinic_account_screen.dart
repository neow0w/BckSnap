import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_client.dart';
import '../../services/auth_service.dart';

class ClinicAccountScreen extends StatefulWidget {
  const ClinicAccountScreen({super.key});

  @override
  State<ClinicAccountScreen> createState() => _ClinicAccountScreenState();
}

class _ClinicAccountScreenState extends State<ClinicAccountScreen> {
  final AuthService _auth = AuthService();

  bool _loading = false;
  String? _error;

  Future<void> _openProfile({
    required String title,
    required String expectedRole,
  }) async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final credentials = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$title Login'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'Staff email',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter the staff email'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Enter the password'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, [
                  emailController.text.trim(),
                  passwordController.text,
                ]);
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    emailController.dispose();
    passwordController.dispose();

    if (credentials == null || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _auth.login(email: credentials[0], password: credentials[1]);

      final role = await _auth.getRole();

      if (!mounted) return;

      if (role != expectedRole) {
        await _auth.logout();

        if (mounted) {
          setState(() {
            _error = expectedRole == 'receptionist'
                ? 'Please use a receptionist account.'
                : 'Please use a doctor account.';
          });
        }
        return;
      }

      if (role == 'receptionist') {
        context.go('/reception');
      } else if (role == 'doctor') {
        context.go('/doctor');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Unable to sign in. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _profileCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: _loading ? null : onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinic Accounts'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: _loading
                ? null
                : () async {
                    await _auth.logout();
                    if (context.mounted) context.go('/login');
                  },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Icon(Icons.local_hospital_outlined, size: 56),
              const SizedBox(height: 12),
              const Text(
                'Select a staff profile',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose a role and sign in with staff credentials.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
              ],
              if (_loading) const Center(child: CircularProgressIndicator()),
              _profileCard(
                icon: Icons.admin_panel_settings_outlined,
                title: 'Receptionist',
                subtitle: 'Appointment management',
                onTap: () => _openProfile(
                  title: 'Receptionist',
                  expectedRole: 'receptionist',
                ),
              ),
              const SizedBox(height: 8),
              ...List.generate(
                3,
                (index) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _profileCard(
                    icon: Icons.medical_services_outlined,
                    title: 'Doctor #${index + 1}',
                    subtitle: 'Doctor account',
                    onTap: () => _openProfile(
                      title: 'Doctor #${index + 1}',
                      expectedRole: 'doctor',
                    ),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Staff profile creation will be connected next.',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add Profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
