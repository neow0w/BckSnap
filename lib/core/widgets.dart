import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// The BckSnap logo. Shows a simple stand-in until assets/images/logo.png exists.
class BrandLogo extends StatelessWidget {
  final double size;
  const BrandLogo({super.key, this.size = 160});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo.png',
      width: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) => SizedBox(
        width: size,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.accessibility_new,
              size: size * 0.5,
              color: AppColors.primary,
            ),
            const SizedBox(height: 8),
            Text(
              'BckSnap',
              style: TextStyle(
                fontSize: size * 0.16,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A text field with its label ABOVE it, like in the mockups.
class LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final Widget? suffixIcon;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const LabeledField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.suffixIcon,
    this.inputFormatters,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          validator: validator,
          inputFormatters: inputFormatters,
          autofillHints: autofillHints,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          decoration: InputDecoration(hintText: hint, suffixIcon: suffixIcon),
        ),
      ],
    );
  }
}

/// A password field with the show/hide eye.
class PasswordField extends StatefulWidget {
  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const PasswordField({
    super.key,
    this.label = 'Password',
    this.controller,
    this.hint = '••••••••••',
    this.validator,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return LabeledField(
      label: widget.label,
      controller: widget.controller,
      hint: widget.hint,
      obscureText: _hidden,
      validator: widget.validator,
      textInputAction: widget.textInputAction,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      autofillHints: const [AutofillHints.password],
      suffixIcon: IconButton(
        icon: Icon(_hidden ? Icons.visibility_off : Icons.visibility),
        color: AppColors.hint,
        onPressed: () => setState(() => _hidden = !_hidden),
      ),
    );
  }
}

/// A red message box for errors.
class ErrorBox extends StatelessWidget {
  final String message;
  const ErrorBox(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.high.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, style: const TextStyle(color: AppColors.high)),
    );
  }
}

/// "or continue with"
class OrDivider extends StatelessWidget {
  final String text;
  const OrDivider({super.key, this.text = 'or continue with'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

/// The Google and Facebook buttons. They are not connected yet: tapping one
/// only shows a message, so nobody thinks sign-in is broken.
class SocialSignInRow extends StatelessWidget {
  const SocialSignInRow({super.key});

  void _soon(BuildContext context, String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name sign-in is not available yet.')),
    );
  }

  Widget _circle(
    BuildContext context,
    String letter,
    Color color,
    String name,
  ) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => _soon(context, name),
      child: CircleAvatar(
        radius: 20,
        backgroundColor: color,
        child: Text(
          letter,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _circle(context, 'G', AppColors.google, 'Google'),
        const SizedBox(width: 16),
        _circle(context, 'f', AppColors.facebook, 'Facebook'),
      ],
    );
  }
}

/// "Don't have an account? Sign Up"
class LinkRow extends StatelessWidget {
  final String text;
  final String linkText;
  final VoidCallback onTap;
  const LinkRow({
    super.key,
    required this.text,
    required this.linkText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(text, style: Theme.of(context).textTheme.bodySmall),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(linkText),
        ),
      ],
    );
  }
}
