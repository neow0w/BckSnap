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

  Future<void> _openAddProfile() async {
    final formKey = GlobalKey<FormState>();
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final professionController = TextEditingController();

    String role = 'doctor';
    DateTime? dateOfBirth;
    final selectedProfessions = <String>{};
    String? formError;
    bool saving = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final age = dateOfBirth == null
                ? null
                : DateTime.now().year -
                      dateOfBirth!.year -
                      (DateTime.now().month < dateOfBirth!.month ||
                              (DateTime.now().month == dateOfBirth!.month &&
                                  DateTime.now().day < dateOfBirth!.day)
                          ? 1
                          : 0);

            return AlertDialog(
              title: const Text('Add Staff Profile'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: role,
                          decoration: const InputDecoration(
                            labelText: 'Account role',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'doctor',
                              child: Text('Doctor'),
                            ),
                            DropdownMenuItem(
                              value: 'receptionist',
                              child: Text('Receptionist'),
                            ),
                          ],
                          onChanged: saving
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setDialogState(() {
                                    role = value;
                                    selectedProfessions.clear();
                                  });
                                },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: firstNameController,
                          decoration: const InputDecoration(
                            labelText: 'First name',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Enter first name'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: lastNameController,
                          decoration: const InputDecoration(
                            labelText: 'Last name',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Enter last name'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: saving
                              ? null
                              : () async {
                                  final today = DateTime.now();
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: DateTime(
                                      today.year - 25,
                                      today.month,
                                      today.day,
                                    ),
                                    firstDate: DateTime(1900),
                                    lastDate: today,
                                  );
                                  if (picked != null) {
                                    setDialogState(() {
                                      dateOfBirth = picked;
                                    });
                                  }
                                },
                          icon: const Icon(Icons.calendar_month),
                          label: Text(
                            dateOfBirth == null
                                ? 'Select date of birth'
                                : '${dateOfBirth!.month.toString().padLeft(2, '0')}/'
                                      '${dateOfBirth!.day.toString().padLeft(2, '0')}/'
                                      '${dateOfBirth!.year}'
                                      ' — Age: $age',
                          ),
                        ),

                        if (role == 'doctor') ...[
                          const SizedBox(height: 12),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Profession(s)',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: professionController,
                            decoration: const InputDecoration(
                              labelText: 'Enter a profession',
                              hintText: 'e.g. Physical Therapist',
                              border: OutlineInputBorder(),
                            ),
                            onFieldSubmitted: (value) {
                              final profession = value.trim();
                              if (profession.isEmpty) return;

                              setDialogState(() {
                                selectedProfessions.add(profession);
                                professionController.clear();
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              onPressed: saving
                                  ? null
                                  : () {
                                      final profession = professionController
                                          .text
                                          .trim();

                                      if (profession.isEmpty) return;

                                      setDialogState(() {
                                        selectedProfessions.add(profession);
                                        professionController.clear();
                                      });
                                    },
                              icon: const Icon(Icons.add),
                              label: const Text('Add Profession'),
                            ),
                          ),
                          if (selectedProfessions.isNotEmpty)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: selectedProfessions.map((profession) {
                                return InputChip(
                                  label: Text(profession),
                                  onDeleted: saving
                                      ? null
                                      : () {
                                          setDialogState(() {
                                            selectedProfessions.remove(
                                              profession,
                                            );
                                          });
                                        },
                                );
                              }).toList(),
                            ),
                        ],

                        const SizedBox(height: 12),
                        TextFormField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Enter email';
                            }
                            if (!value.contains('@') || !value.contains('.')) {
                              return 'Enter a valid email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password (minimum 8 characters)',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.length < 8) {
                              return 'Use at least 8 characters';
                            }
                            return null;
                          },
                        ),
                        if (formError != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            formError!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;

                          if (dateOfBirth == null) {
                            setDialogState(() {
                              formError = 'Please select a date of birth.';
                            });
                            return;
                          }

                          if (role == 'doctor' && selectedProfessions.isEmpty) {
                            setDialogState(() {
                              formError =
                                  'Select at least one doctor profession.';
                            });
                            return;
                          }

                          setDialogState(() {
                            saving = true;
                            formError = null;
                          });

                          try {
                            await _auth.createManagedStaff(
                              firstName: firstNameController.text,
                              lastName: lastNameController.text,
                              dateOfBirth: dateOfBirth!,
                              professions: role == 'doctor'
                                  ? selectedProfessions.toList()
                                  : [],
                              email: emailController.text,
                              password: passwordController.text,
                              role: role,
                            );

                            if (!dialogContext.mounted) return;
                            Navigator.of(
                              dialogContext,
                              rootNavigator: true,
                            ).pop(true);
                          } on ApiException catch (e) {
                            setDialogState(() {
                              saving = false;
                              formError = e.message;
                            });
                          } catch (_) {
                            setDialogState(() {
                              saving = false;
                              formError = 'Could not create the profile. Please try again.';
                            });
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create Profile'),
                ),
              ],
            );
          },
        );
      },
    );

    firstNameController.dispose();
    lastNameController.dispose();
    emailController.dispose();
    passwordController.dispose();

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            role == 'doctor'
                ? 'Doctor application submitted for receptionist approval.'
                : 'Receptionist profile created.',
          ),
        ),
      );
    }
  }

  Future<void> _openProfile({
    required String title,
    required String expectedRole,
  }) async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    List<String>? credentials;

    credentials = await showDialog<List<String>>(
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
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(
                  dialogContext,
                ).pop([emailController.text.trim(), passwordController.text]);
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 300));

    emailController.dispose();
    passwordController.dispose();

    // Cancel closes the dialog without attempting login.
    if (credentials == null || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    var navigated = false;

    try {
      await _auth.login(email: credentials[0], password: credentials[1]);

      final role = await _auth.getRole();

      if (role != expectedRole) {
        await _auth.logout();

        if (!mounted) return;

        setState(() {
          _error = expectedRole == 'receptionist'
              ? 'Please use a receptionist account.'
              : 'Please use a doctor account.';
        });
        return;
      }

      navigated = true;

      if (role == 'receptionist') {
        context.go('/reception');
      } else if (role == 'doctor') {
        context.go('/doctor');
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Unable to sign in. Please try again.';
        });
      }
    } finally {
      if (mounted && !navigated) {
        setState(() => _loading = false);
      }
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
                onPressed: _loading ? null : _openAddProfile,
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
