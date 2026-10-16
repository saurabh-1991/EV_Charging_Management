import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _wingController =
      TextEditingController(text: 'B1');
  final TextEditingController _flatController = TextEditingController();
  final TextEditingController _vehicleController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isRegister = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _wingController.dispose();
    _flatController.dispose();
    _vehicleController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String email = _emailController.text.trim();
    final String password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      _toast('Email and password are required.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      if (_isRegister) {
        final String name = _nameController.text.trim();
        final String wing = _wingController.text.trim().toUpperCase();
        final String flat = _flatController.text.trim().toUpperCase();
        final String vehicle = _vehicleController.text.trim().toUpperCase();
        if (name.isEmpty || wing.isEmpty || flat.isEmpty || vehicle.isEmpty) {
          _toast('Enter name, wing, flat and vehicle.');
          return;
        }
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
            'role': 'resident',
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
        if (!mounted) {
          return;
        }
        _toast('Registered. Waiting for admin approval.');
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
    return Scaffold(
      appBar: AppBar(title: Text(_isRegister ? 'Register' : 'Login')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (_isRegister) ...<Widget>[
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _wingController,
              decoration: const InputDecoration(labelText: 'Wing (B1/B2)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _flatController,
              decoration: const InputDecoration(labelText: 'Flat Number'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _vehicleController,
              decoration: const InputDecoration(labelText: 'Vehicle Number'),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
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
    );
  }
}
