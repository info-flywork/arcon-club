import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../config.dart';

/// Web paneliyle aynı hesap: kullanıcı adı veya e-posta + şifre.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.config, required this.session});

  final ArconAppConfig config;
  final SessionController session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 980));
  final _form = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.config.appKey == 'arconnect') _enter.forward();
  }

  @override
  void dispose() {
    _enter.dispose();
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.login(
        _login.text,
        _password.text,
        deviceName: '${Platform.operatingSystem} · ${widget.config.title}',
      );
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.config.appKey == 'arconnect') return _buildConnect();
    return _buildClassic(context);
  }

  Widget _buildConnect() {
    final theme = Theme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Theme(
        data: theme.copyWith(
          brightness: Brightness.dark,
          textSelectionTheme: const TextSelectionThemeData(cursorColor: Colors.white, selectionColor: Color(0x44FFFFFF)),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0x14FFFFFF),
            labelStyle: const TextStyle(color: Color(0xB3FFFFFF), fontWeight: FontWeight.w500),
            floatingLabelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            prefixIconColor: const Color(0xD9FFFFFF),
            suffixIconColor: const Color(0xD9FFFFFF),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0x33FFFFFF))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0x2EFFFFFF))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Colors.white, width: 1.4)),
            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFFF8A80))),
            focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFFF8A80))),
          ),
        ),
        child: Scaffold(
          backgroundColor: const Color(0xFF050608),
          body: Stack(
            children: [
              const Positioned.fill(child: _ConnectGlow()),
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: AnimatedBuilder(
                        animation: _enter,
                        builder: (context, _) {
                          return Form(
                            key: _form,
                            child: AutofillGroup(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _rise(0, const _ConnectMark()),
                                  const SizedBox(height: 28),
                                  _rise(0.12, _glassCard(theme)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rise(double start, Widget child) {
    final t = Curves.easeOutCubic.transform(((_enter.value - start) / (1 - start)).clamp(0.0, 1.0));
    return Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, (1 - t) * 22), child: child),
    );
  }

  Widget _glassCard(ThemeData theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          decoration: BoxDecoration(
            color: const Color(0x1AFFFFFF),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0x33FFFFFF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _login,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                autofillHints: const [AutofillHints.username, AutofillHints.email],
                keyboardType: TextInputType.emailAddress,
                keyboardAppearance: Brightness.dark,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Kullanıcı adı veya e-posta',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Bu alan gerekli' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                obscureText: _obscure,
                keyboardAppearance: Brightness.dark,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Şifre',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Şifreyi göster' : 'Şifreyi gizle',
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Şifre gerekli' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 16),
              _ConnectButton(busy: _busy, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }

  /// ARCON Club girişi: webdeki giriş sayfasının (index.php) telefondaki hali
  Widget _buildClassic(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _Web.bottom,
        body: Stack(children: [
          const Positioned.fill(child: _WebBackdrop()),
          SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(18, pad.top + 28, 18, pad.bottom + 40),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _webCard(),
                  const SizedBox(height: 36),
                  const _WebBrands(),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _webCard() {
    InputDecoration field(String hint, {Widget? suffix}) => InputDecoration(
          hintText: hint,
          hintStyle: _Web.text(15, color: const Color(0xFF6B7785)),
          filled: true,
          fillColor: _Web.paper,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
          suffixIcon: suffix,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _Web.line)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _Web.line)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _Web.accent, width: 1.4)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0x80EF4444))),
          focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFEF4444))),
          errorStyle: _Web.text(12, color: const Color(0xFFFCA5A5)),
        );
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(t, style: _Web.text(13, weight: 600, color: _Web.inkSoft)),
        );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _Web.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _Web.line),
        boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 60, offset: Offset(0, 24))],
      ),
      child: Stack(children: [
        // kartın altındaki yeşil parıltı (.login-card::before)
        Positioned(
          left: -60,
          right: -60,
          bottom: -120,
          height: 260,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 0.75,
                  colors: [_Web.accent.withValues(alpha: 0.22), _Web.accent.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
          child: Form(
            key: _form,
            child: AutofillGroup(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 5, 12, 5),
                    decoration: BoxDecoration(
                      color: _Web.accent.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _Web.accent.withValues(alpha: 0.35)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF34D399),
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Color(0x3334D399), spreadRadius: 4)],
                        ),
                      ),
                      const SizedBox(width: 9),
                      Text('ARCON AI • AI Project System', style: _Web.text(11.5, weight: 600, color: const Color(0xFFA7F3D0))),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Kurumsal Proje Yönetimine Giriş', style: _Web.text(25, weight: 700, height: 1.2, spacing: -0.75)),
                const SizedBox(height: 8),
                Text(
                  'ARCON AI paneline giriş yaparak projeleri, görevleri ve marka modüllerini tek ekrandan kontrol edin.',
                  style: _Web.text(14.5, color: _Web.muted, height: 1.5),
                ),
                const SizedBox(height: 22),
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0x1FEF4444),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0x4DEF4444)),
                    ),
                    child: Text(_error!, style: _Web.text(13, color: const Color(0xFFFCA5A5))),
                  ),
                  const SizedBox(height: 16),
                ],
                label('Kullanıcı adı veya e-posta'),
                TextFormField(
                  controller: _login,
                  autofillHints: const [AutofillHints.username, AutofillHints.email],
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  style: _Web.text(15),
                  cursorColor: _Web.green,
                  decoration: field('örn. anilcan'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Bu alan gerekli' : null,
                ),
                const SizedBox(height: 14),
                label('Şifre'),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  style: _Web.text(15),
                  cursorColor: _Web.green,
                  decoration: field(
                    '••••••••',
                    suffix: IconButton(
                      tooltip: _obscure ? 'Şifreyi göster' : 'Şifreyi gizle',
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: _Web.muted, size: 20),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Şifre gerekli' : null,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _Web.accent,
                      disabledBackgroundColor: _Web.accent.withValues(alpha: 0.6),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _busy
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text('Giriş Yap', style: _Web.text(15.5, weight: 600, color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('Hesabın yok mu? ', style: _Web.text(13.5, color: _Web.muted)),
                  GestureDetector(
                    onTap: () => launchUrl(Uri.parse('${widget.config.apiBase}register'), mode: LaunchMode.externalApplication),
                    child: Text('Kayıt ol', style: _Web.text(13.5, weight: 600, color: _Web.green)),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Webin giriş sayfasının renkleri ve yazısı (index.php :root)
abstract final class _Web {
  static const ink = Color(0xFFE8EEF5);
  static const inkSoft = Color(0xFFB6C2D1);
  static const muted = Color(0xFF8B98A8);
  static const line = Color(0x1AFFFFFF);
  static const paper = Color(0xFF0F141B);
  static const card = Color(0xFF161D27);
  static const accent = Color(0xFF0F6E56);
  static const green = Color(0xFF6EE7B7);
  static const top = Color(0xFF171B21);
  static const bottom = Color(0xFF101317);

  static TextStyle text(double size, {double weight = 400, Color color = ink, double? height, double spacing = 0}) => TextStyle(
        fontFamily: 'DMSans',
        package: 'arcon_core',
        fontSize: size,
        fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
        fontVariations: [FontVariation('wght', weight)],
        color: color,
        height: height,
        letterSpacing: spacing,
      );
}

/// Sayfa zemini: koyu degrade, sol üstte yeşil, sağ üstte mavi ışık
class _WebBackdrop extends StatelessWidget {
  const _WebBackdrop();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_Web.top, Color(0xFF13171C), _Web.bottom],
            stops: [0, 0.45, 1],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.85, -1.15),
              radius: 1.1,
              colors: [Color(0x2E0F6E56), Color(0x000F6E56)],
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(1, -1),
                radius: 0.9,
                colors: [Color(0x1A1D4E89), Color(0x001D4E89)],
              ),
            ),
          ),
        ),
      );
}

/// "Global premium markalar tek panelde buluşuyor." ve cam marka kartları
class _WebBrands extends StatelessWidget {
  const _WebBrands();

  static const brands = [
    'Dior', 'Hermès', 'Jean Paul Gaultier', 'Sensai', 'Carolina Herrera', 'Rabanne', //
    'Dolce&Gabbana', 'La Prairie', 'Givenchy', 'Sisley Paris', 'Paradis des Sens', 'Dr. Barbara Sturm',
    "Penhaligon's", 'Byredo', "L'Artisan Parfumeur", 'Dries Van Noten', 'Scentologia',
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      // kartların arkasındaki bulanık yeşil ışıklar (.brands-section::before / ::after)
      Positioned(left: -60, top: 120, child: _glow(260, const Color(0x590F6E56))),
      Positioned(right: -70, bottom: -40, child: _glow(300, const Color(0x2E6EE7B7))),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Global premium markalar '),
            TextSpan(text: 'tek panelde buluşuyor.', style: _Web.text(23, weight: 700, color: _Web.green, height: 1.2, spacing: -0.7)),
          ]),
          style: _Web.text(23, weight: 700, height: 1.2, spacing: -0.7),
        ),
        const SizedBox(height: 8),
        Text(
          'Dior’dan Hermès’e, La Prairie’den Byredo’ya kadar global markalar için içerik, proje ve görevleri ARCON AI üzerinden koordine edebilirsiniz.',
          style: _Web.text(14, color: _Web.muted, height: 1.5),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, box) {
          final cols = box.maxWidth >= 600 ? 3 : 2;
          final w = (box.maxWidth - 10 * (cols - 1)) / cols;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final b in brands) SizedBox(width: w, child: _BrandCard(name: b)),
          ]);
        }),
      ]),
    ]);
  }

  static Widget _glow(double size, Color color) => IgnorePointer(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        ),
      );
}

/// Cam marka kartı (.brand-card)
class _BrandCard extends StatelessWidget {
  const _BrandCard({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            constraints: const BoxConstraints(minHeight: 66),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0x26000000),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x73FFFFFF)),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment(0, -0.6),
                colors: [Color(0x14FFFFFF), Color(0x00FFFFFF)],
              ),
            ),
            child: Text(name, textAlign: TextAlign.center, style: _Web.text(15, weight: 600, height: 1.25)),
          ),
        ),
      );
}

class _ConnectMark extends StatefulWidget {
  const _ConnectMark();

  @override
  State<_ConnectMark> createState() => _ConnectMarkState();
}

class _ConnectMarkState extends State<_ConnectMark> with SingleTickerProviderStateMixin {
  late final AnimationController _shine = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));

  @override
  void initState() {
    super.initState();
    _shine.repeat();
  }

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset(
          'assets/arcon_logo_dark.png',
          package: 'arcon_core',
          height: 22,
          semanticLabel: 'ARCON',
        ),
        const SizedBox(height: 22),
        AnimatedBuilder(
          animation: _shine,
          builder: (context, child) {
            final dx = -1.3 + _shine.value * 2.6;
            return ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (rect) => LinearGradient(
                begin: Alignment(dx, -0.3),
                end: Alignment(dx + 0.55, 0.3),
                colors: const [Colors.white, Color(0xFFC5D0DA), Colors.white],
                stops: const [0.2, 0.5, 0.8],
              ).createShader(rect),
              child: child,
            );
          },
          child: const Text(
            'ARCONNECT',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: 1.6, height: 1),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'ARCON hesabınla giriş yap',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _ConnectGlow extends StatefulWidget {
  const _ConnectGlow();

  @override
  State<_ConnectGlow> createState() => _ConnectGlowState();
}

class _ConnectGlowState extends State<_ConnectGlow> with TickerProviderStateMixin {
  static const _brands = [
    'Dior',
    'Hermès',
    'Jean Paul Gaultier',
    'Sensai',
    'Carolina Herrera',
    'Rabanne',
    'Dolce&Gabbana',
    'La Prairie',
    'Givenchy',
    'Sisley Paris',
    'Paradis des Sens',
    'Dr. Barbara Sturm',
    'Penhaligon\'s',
    'Byredo',
    'L\'Artisan Parfumeur',
    'Dries Van Noten',
    'Scentologia',
  ];

  // üst şerit soldan sağa, alt şerit sağdan sola ve daha yavaş/soluk
  late final AnimationController _top = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  late final AnimationController _bottom = AnimationController(vsync: this, duration: const Duration(seconds: 180))..repeat();

  @override
  void dispose() {
    _top.dispose();
    _bottom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final half = _brands.length ~/ 2;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF050608)),
          // sabit, hafif ışık (dönen / kayan parıltı yok)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.6, -0.95),
                radius: 1.05,
                colors: [Color(0xCC3A4352), Color(0x00050608)],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: pad.top + 18,
            child: _Marquee(names: _brands.sublist(0, half + 1), anim: _top, leftToRight: true, opacity: 0.42, fontSize: 15),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: pad.bottom + 18,
            child: _Marquee(names: _brands.sublist(half), anim: _bottom, leftToRight: false, opacity: 0.22, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Sonsuz kayan marka şeridi; kenarlarda yumuşakça kaybolur.
class _Marquee extends StatelessWidget {
  const _Marquee({required this.names, required this.anim, required this.leftToRight, required this.opacity, required this.fontSize});

  final List<String> names;
  final Animation<double> anim;
  final bool leftToRight;
  final double opacity;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: const Color(0xFFE7EDF2).withValues(alpha: opacity),
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
    );
    final text = '${names.join('     ·     ')}     ·     ';
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, maxLines: 1)..layout();
    final w = tp.width;
    return IgnorePointer(
      child: SizedBox(
        height: tp.height + 4,
        child: ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
            stops: [0, 0.14, 0.86, 1],
          ).createShader(r),
          blendMode: BlendMode.dstIn,
          child: AnimatedBuilder(
            animation: anim,
            builder: (context, child) {
              final dx = leftToRight ? -w + anim.value * w : -anim.value * w;
              return OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: double.infinity,
                child: Transform.translate(offset: Offset(dx, 0), child: child),
              );
            },
            child: Text('$text$text$text', maxLines: 1, softWrap: false, style: style),
          ),
        ),
      ),
    );
  }
}

class _ConnectButton extends StatefulWidget {
  const _ConnectButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  State<_ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<_ConnectButton> with SingleTickerProviderStateMixin {
  late final AnimationController _sheen = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void initState() {
    super.initState();
    _sheen.repeat();
  }

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _sheen,
      builder: (context, child) {
        final dx = -1.5 + _sheen.value * 3;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment(dx, -0.4),
              end: Alignment(dx + 0.9, 0.5),
              colors: const [Color(0xFFE8EEF3), Color(0xFFFFFFFF), Color(0xFFC9D3DC), Color(0xFFFFFFFF)],
            ),
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 22, offset: Offset(0, 10))],
          ),
          child: child,
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.busy ? null : widget.onPressed,
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 54,
            child: Center(
              child: widget.busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0B0D10)),
                    )
                  : const Text(
                      'Giriş yap',
                      style: TextStyle(color: Color(0xFF0B0D10), fontWeight: FontWeight.w800, fontSize: 16),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
