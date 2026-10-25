import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static final RegExp _namePattern = RegExp(r"^[A-Za-z][A-Za-z\s'.-]{1,49}$");
  static final RegExp _flatPattern = RegExp(r'^[A-Z0-9][A-Z0-9\-\/]{0,11}$');
  static final RegExp _vehiclePattern =
      RegExp(r'^[A-Z]{2}[0-9]{1,2}[A-Z]{0,3}[0-9]{1,4}$');
  static final RegExp _passwordUpper = RegExp(r'[A-Z]');
  static final RegExp _passwordLower = RegExp(r'[a-z]');
  static final RegExp _passwordNumber = RegExp(r'[0-9]');
  static final RegExp _passwordSpecial =
      RegExp(r'[!@#\$%\^&\*\(\)_\+\-\=\[\]\{\};:,.<>\/?]');

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _flatController = TextEditingController();
  final TextEditingController _vehicleController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String _selectedWing = 'B1';
  bool _isRegister = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _flatController.dispose();
    _vehicleController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String email = _emailController.text.trim();
    final String password = _passwordController.text.trim();
    if (_isRegister && !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (email.isEmpty || password.isEmpty) {
      _toast('Email and password are required.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      if (_isRegister) {
        final String name = _nameController.text.trim();
        final String wing = _selectedWing;
        final String flat = _flatController.text.trim().toUpperCase();
        final String vehicle = _vehicleController.text
            .trim()
            .toUpperCase()
            .replaceAll(RegExp(r'[\s\-]'), '');
        final UserCredential cred = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
        final User user = cred.user!;
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          <String, dynamic>{
            'email': email,
            'name': name,
            'wing': wing,
            'flatNumber': flat,
            'vehicleNumber': vehicle,
            'vehicles': <String>[vehicle],
            'defaultVehicle': vehicle,
            'role': 'resident',
            'status': 'active',
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
        if (!mounted) {
          return;
        }
        _toast('Registered successfully. You can login now.');
      } else {
        await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);
      }
    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? e.code);
    } on FirebaseException catch (e) {
      _toast(e.message ?? e.code);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _forgotPassword() async {
    final String email = _emailController.text.trim();
    if (email.isEmpty) {
      _toast('Enter your email first.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _toast('Password reset email sent.');
    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? e.code);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool showRegister = _isRegister;
    return Scaffold(
      appBar: AppBar(title: Text(_isRegister ? 'Register' : 'Login')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (showRegister) ...<Widget>[
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  helperText: '2-50 chars, letters/spaces only',
                ),
                textInputAction: TextInputAction.next,
                validator: (String? value) {
                  final String text = (value ?? '').trim();
                  if (text.isEmpty) {
                    return 'Name is required.';
                  }
                  if (!_namePattern.hasMatch(text)) {
                    return 'Enter a valid name.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _selectedWing,
                decoration: const InputDecoration(labelText: 'Wing'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(value: 'B1', child: Text('B1')),
                  DropdownMenuItem<String>(value: 'B2', child: Text('B2')),
                ],
                onChanged: (String? value) {
                  if (value != null) {
                    setState(() => _selectedWing = value);
                  }
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _flatController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Flat Number',
                  helperText: 'Up to 12 chars: A-Z, 0-9, - or /',
                ),
                textInputAction: TextInputAction.next,
                validator: (String? value) {
                  final String text = (value ?? '').trim().toUpperCase();
                  if (text.isEmpty) {
                    return 'Flat number is required.';
                  }
                  if (!_flatPattern.hasMatch(text)) {
                    return 'Invalid flat number format.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _vehicleController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Primary Vehicle Number',
                  helperText: 'Example: MH12AB1234',
                ),
                textInputAction: TextInputAction.next,
                validator: (String? value) {
                  final String text = (value ?? '')
                      .trim()
                      .toUpperCase()
                      .replaceAll(RegExp(r'[\s\-]'), '');
                  if (text.isEmpty) {
                    return 'Vehicle number is required.';
                  }
                  if (!_vehiclePattern.hasMatch(text)) {
                    return 'Invalid vehicle number format.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
            ],
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              textInputAction: TextInputAction.next,
              validator: showRegister
                  ? (String? value) {
                      final String text = (value ?? '').trim();
                      if (text.isEmpty) {
                        return 'Email is required.';
                      }
                      final bool validEmail = RegExp(
                              r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
                          .hasMatch(text);
                      if (!validEmail) {
                        return 'Enter a valid email address.';
                      }
                      return null;
                    }
                  : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: showRegister
                    ? 'Min 8 chars with upper, lower, number and special char'
                    : null,
              ),
              validator: showRegister
                  ? (String? value) {
                      final String text = (value ?? '').trim();
                      if (text.length < 8) {
                        return 'Password must be at least 8 characters.';
                      }
                      if (!_passwordUpper.hasMatch(text) ||
                          !_passwordLower.hasMatch(text) ||
                          !_passwordNumber.hasMatch(text) ||
                          !_passwordSpecial.hasMatch(text)) {
                        return 'Use upper, lower, number and special character.';
                      }
                      return null;
                    }
                  : null,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isLoading ? null : _submit,
              child: Text(_isLoading
                  ? 'Please wait...'
                  : (_isRegister ? 'Create Account' : 'Login')),
            ),
            if (!_isRegister)
              TextButton(
                onPressed: _forgotPassword,
                child: const Text('Forgot Password?'),
              ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      setState(() => _isRegister = !_isRegister);
                    },
              child: Text(
                _isRegister
                    ? 'Already have account? Login'
                    : 'New user? Register',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
