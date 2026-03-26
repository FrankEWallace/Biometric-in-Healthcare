import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/primary_button.dart';
import 'home_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey           = GlobalKey<FormState>();
  final _emailController   = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    context.read<AuthProvider>().clearError();
    if (!_formKey.currentState!.validate()) return;

    final success = await context.read<AuthProvider>().login(
          _emailController.text.trim(),
          _passwordController.text,
        );

    if (success && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeDashboard()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final headerH = size.height * 0.38;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ── Blue gradient header ────────────────────────────────────────
          Container(
            height: headerH + 40,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primaryDark, AppColors.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          // ── Header content ──────────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: SizedBox(
              height: headerH,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo ring
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.15),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                          width: 1.5),
                    ),
                    child: const Icon(
                      Icons.fingerprint,
                      size: 44,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'BiH Biometric System',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Secure Patient Identification',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── White form card ─────────────────────────────────────────────
          Positioned(
            top: headerH,
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Welcome back',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Sign in to your account',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Form ──────────────────────────────────────────────
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          CustomTextField(
                            label: 'Email Address',
                            hint: 'nurse@hospital.ba',
                            controller: _emailController,
                            prefixIcon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Email is required';
                              }
                              if (!val.contains('@')) {
                                return 'Enter a valid email address';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          CustomTextField(
                            label: 'Password',
                            hint: '••••••••',
                            controller: _passwordController,
                            prefixIcon: Icons.lock_outline,
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _handleLogin(),
                            validator: (val) {
                              if (val == null || val.isEmpty) {
                                return 'Password is required';
                              }
                              if (val.length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),

                    // ── API error ─────────────────────────────────────────
                    Consumer<AuthProvider>(
                      builder: (context, auth, child) {
                        if (auth.errorMessage == null) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: _AlertBanner(
                            message: auth.errorMessage!,
                            onDismiss: auth.clearError,
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 28),

                    // ── Login button ──────────────────────────────────────
                    Consumer<AuthProvider>(
                      builder: (context, auth, child) => PrimaryButton(
                        label: 'Sign In',
                        icon: Icons.login_rounded,
                        onPressed: _handleLogin,
                        isLoading: auth.isLoading,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Footer ────────────────────────────────────────────
                    Center(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.primaryTint,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.local_hospital_outlined,
                                    size: 14,
                                    color: AppColors.primary),
                                SizedBox(width: 6),
                                Text(
                                  'Hospital Staff Access Only',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Smartphone Biometric Verification System',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _AlertBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: AppColors.error.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close, color: AppColors.error, size: 16),
          ),
        ],
      ),
    );
  }
}
