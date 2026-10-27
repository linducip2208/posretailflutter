import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/s.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/app_snackbar.dart';
import '../outlet/outlet_selection_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  String? _localError;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _forgotPassword() {
    showAppSnackbar(
      context,
      S.tn(
        context,
        'Reset password mandiri belum tersedia. Hubungi admin untuk bantuan.',
      ),
      type: SnackType.warning,
    );
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _localError = email.isEmpty
            ? S.tn(context, 'Email wajib diisi.')
            : S.tn(context, 'Password wajib diisi.');
      });
      return;
    }
    setState(() => _localError = null);

    final auth = context.read<AuthProvider>();
    final ok = await auth.login(email, password);
    if (!mounted) return;
    if (ok) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const OutletGate()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    final error = _localError ?? auth.error;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/app_icon.png',
                    width: 72,
                    height: 72,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                      children: [
                        TextSpan(
                          text: 'POS',
                          style: TextStyle(color: AppColors.text),
                        ),
                        TextSpan(
                          text: 'Retail',
                          style: TextStyle(color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    S.t(context, 'Selamat Datang'),
                    style: theme.textTheme.titleLarge?.copyWith(fontSize: 19),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    S.t(context, 'Masuk untuk melanjutkan'),
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: S.t(context, 'Email'),
                      prefixIcon: const Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: S.t(context, 'Password'),
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        tooltip: S.t(context, 'Tampilkan/sembunyikan password'),
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    onSubmitted: (_) => _login(),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: auth.isLoading ? null : _login,
                      child: auth.isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                                strokeWidth: 2.4,
                              ),
                            )
                          : Text(
                              S.t(context, 'Login'),
                              style: const TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _forgotPassword,
                      child: Text(S.t(context, 'Lupa password?')),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.errorSoft,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: AppColors.error,
                            size: 20,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              error,
                              style: const TextStyle(
                                color: Color(0xFF991B1B),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    S.t(context, 'Belum punya akun? Hubungi admin'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
