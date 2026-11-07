import 'package:flutter/material.dart';

typedef CoachAuthenticate =
    Future<void> Function(String email, String password, {String? name});

/// Keeps editing and async state alive for the whole dialog route, including
/// its exit animation. The caller never disposes a still-mounted field.
class CoachAuthDialog extends StatefulWidget {
  final CoachAuthenticate authenticate;
  const CoachAuthDialog({super.key, required this.authenticate});

  @override
  State<CoachAuthDialog> createState() => _CoachAuthDialogState();
}

class _CoachAuthDialogState extends State<CoachAuthDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _register = false, _sending = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  void _close() {
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop();
  }

  Future<void> _submit() async {
    if (_sending) return;
    final email = _email.text.trim();
    final name = _name.text.trim();
    if (email.isEmpty || _password.text.isEmpty || _register && name.isEmpty) {
      setState(
        () => _error = _register
            ? 'Enter your name, email and password.'
            : 'Enter your email and password.',
      );
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.authenticate(
        email,
        _password.text,
        name: _register ? name : null,
      );
      if (mounted) _close();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_sending,
    child: AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      title: Text(_register ? 'Create coach account' : 'Welcome back'),
      content: SizedBox(
        width: 400,
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_register) ...[
                TextField(
                  key: const ValueKey('coach-auth-name'),
                  controller: _name,
                  enabled: !_sending,
                  autofillHints: const [AutofillHints.name],
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Name'),
                  maxLength: 60,
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                key: const ValueKey('coach-auth-email'),
                controller: _email,
                enabled: !_sending,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('coach-auth-password'),
                controller: _password,
                enabled: !_sending,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                autofillHints: [
                  _register
                      ? AutofillHints.newPassword
                      : AutofillHints.password,
                ],
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: _register ? 'At least 10 characters' : null,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const ValueKey('coach-auth-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              TextButton(
                key: const ValueKey('coach-auth-mode'),
                onPressed: _sending
                    ? null
                    : () {
                        FocusScope.of(context).unfocus();
                        setState(() {
                          _register = !_register;
                          _error = null;
                        });
                      },
                child: Text(
                  _register
                      ? 'Already have an account? Sign in'
                      : 'New here? Create an account',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('coach-auth-cancel'),
          onPressed: _sending ? null : _close,
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('coach-auth-submit'),
          onPressed: _sending ? null : _submit,
          child: Text(
            _sending
                ? 'Connecting…'
                : _register
                ? 'Create account'
                : 'Sign in',
          ),
        ),
      ],
    ),
  );
}
