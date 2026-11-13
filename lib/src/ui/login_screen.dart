import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import 'mono.dart';
import 'theme.dart' show arconFontFamily;

part 'register_screen.dart';

/// Web paneliyle aynı hesap: kullanıcı adı veya e-posta + şifre.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.config, required this.session});

  final ArconAppConfig config;
  final SessionController session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 980),
  );
  final _form = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _enter.forward();
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

  /// Kayıt ekranı; kayıt başarılıysa kullanıcı adını giriş alanına yazar.
  Future<void> _openRegister() async {
    final username = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => RegisterScreen(session: widget.session),
      ),
    );
    if (!mounted || username == null) return;
    setState(() {
      _error = null;
      _login.text = username;
      _password.clear();
    });
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
          textSelectionTheme: const TextSelectionThemeData(
            cursorColor: Colors.white,
            selectionColor: Color(0x44FFFFFF),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0x14FFFFFF),
            labelStyle: const TextStyle(
              color: Color(0xB3FFFFFF),
              fontWeight: FontWeight.w500,
            ),
            floatingLabelStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
            prefixIconColor: const Color(0xD9FFFFFF),
            suffixIconColor: const Color(0xD9FFFFFF),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0x33FFFFFF)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0x2EFFFFFF)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Colors.white, width: 1.4),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFFFF8A80)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFFFF8A80)),
            ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 28,
                    ),
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
    final t = Curves.easeOutCubic.transform(
      ((_enter.value - start) / (1 - start)).clamp(0.0, 1.0),
    );
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
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                keyboardType: TextInputType.emailAddress,
                keyboardAppearance: Brightness.dark,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Kullanıcı adı veya e-posta',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Bu alan gerekli' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
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
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Şifre gerekli' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _ConnectButton(busy: _busy, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }

  /// ARCON Club girişi: uygulamanın siyah-beyaz dili (ARCON MAG / Akademi modülleri,
  /// üst menü hapları, siyah zemin + beyaz ikonlu modül kartları). Açık/koyu temaya uyar.
  Widget _buildClassic(BuildContext context) {
    final c = ArconMono.of(context);
    final pad = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: c.bg,
        body: Stack(
          children: [
            // Tek ekrana sığar (markalar alta yaslanır); klavye açılınca / küçük ekranda kayar
            CustomScrollView(
              physics: const ClampingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    // dolgu içeride: dışarıda olursa ekran yüksekliğine eklenip gereksiz kaydırma yapar
                    padding: EdgeInsets.fromLTRB(
                      24,
                      pad.top + 20,
                      24,
                      pad.bottom + 16,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: AnimatedBuilder(
                          animation: _enter,
                          builder: (context, _) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _rise(0, _MonoHero(c: c)),
                              const SizedBox(height: 24),
                              _rise(0.12, _monoForm(c)),
                              const Spacer(),
                              const SizedBox(height: 24),
                              _rise(0.24, _MonoModules(c: c)),
                              const SizedBox(height: 18),
                              _rise(0.34, _MonoBrandTicker(c: c)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // kaydırınca içerik durum çubuğunun altında okunmasın
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: pad.top,
              child: ColoredBox(color: c.bg),
            ),
          ],
        ),
      ),
    );
  }

  Widget _monoForm(ArconMono c) {
    return Form(
      key: _form,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              c.errorBox(_error!),
              const SizedBox(height: 18),
            ],
            c.label('Kullanıcı adı veya e-posta'),
            TextFormField(
              controller: _login,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
              keyboardType: TextInputType.emailAddress,
              keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              style: c.text(15, weight: FontWeight.w500),
              cursorColor: c.ink,
              decoration: c.input('örn. anilcan', Icons.person_outline_rounded),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Bu alan gerekli' : null,
            ),
            const SizedBox(height: 18),
            c.label('Şifre'),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              style: c.text(15, weight: FontWeight.w500),
              cursorColor: c.ink,
              decoration: c.input(
                '••••••••',
                Icons.lock_outline_rounded,
                suffix: IconButton(
                  tooltip: _obscure ? 'Şifreyi göster' : 'Şifreyi gizle',
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: c.muted,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Şifre gerekli' : null,
            ),
            const SizedBox(height: 26),
            c.primaryButton('Giriş Yap', busy: _busy, onPressed: _submit),
            const SizedBox(height: 20),
            c.linkRow('Hesabın yok mu? ', 'Kayıt ol', _openRegister),
          ],
        ),
      ),
    );
  }
}

/// Üst kart: ters renkli (açıkta siyah, koyuda beyaz) ARCON CLUB vitrini, ince ızgara dokulu.
class _MonoHero extends StatelessWidget {
  const _MonoHero({required this.c});
  final ArconMono c;

  @override
  Widget build(BuildContext context) {
    final fg = c.bg;
    final soft = fg.withValues(alpha: 0.62);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.ink,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(fg.withValues(alpha: 0.05)),
            ),
          ),
          // sağ üstte silik büyük "A" monogramı
          Positioned(
            right: -14,
            top: -38,
            child: Text(
              'A',
              style: c.text(
                170,
                weight: FontWeight.w800,
                color: fg.withValues(alpha: 0.06),
                height: 1,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ArconClubMark(c: c, color: fg),
                const SizedBox(height: 26),
                Text(
                  'Projelerin, ekibin ve\nmarkaların tek yerde.',
                  style: c.text(
                    21,
                    weight: FontWeight.w700,
                    color: fg,
                    height: 1.22,
                    spacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Hesabınla giriş yap, kaldığın yerden devam et.',
                  style: c.text(12.5, color: soft, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    const step = 22.0;
    for (var x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (var y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color;
}

/// Uygulamada seni bekleyenler: webdeki modül kartları gibi siyah kutu + beyaz ikon.
class _MonoModules extends StatelessWidget {
  const _MonoModules({required this.c});
  final ArconMono c;

  static const items = [
    (Icons.auto_awesome_outlined, 'ARCON AI', 'Akıllı asistanın'),
    (Icons.forum_outlined, 'ARCONNECT', 'Sohbet ve aramalar'),
    (Icons.newspaper_outlined, 'ARCON MAG', 'Marka içerikleri'),
    (Icons.school_outlined, 'AKADEMİ', 'Eğitim ve gelişim'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'UYGULAMADA',
              style: c.text(
                10.5,
                weight: FontWeight.w700,
                color: c.muted,
                spacing: 1.4,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 1, color: c.line)),
          ],
        ),
        const SizedBox(height: 12),
        // LayoutBuilder değil: SliverFillRemaining içerik yüksekliğini ölçer, LayoutBuilder bunu desteklemez
        for (var r = 0; r < items.length; r += 2) ...[
          if (r > 0) const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _tile(items[r].$1, items[r].$2, items[r].$3)),
              const SizedBox(width: 8),
              Expanded(
                child: _tile(items[r + 1].$1, items[r + 1].$2, items[r + 1].$3),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _tile(IconData icon, String title, String sub) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.field,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.ink,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: c.bg),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: c.text(
                    11.5,
                    weight: FontWeight.w700,
                    height: 1.2,
                    spacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: c.text(10.5, color: c.muted, height: 1.2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// En altta yavaşça kayan global marka şeridi.
class _MonoBrandTicker extends StatefulWidget {
  const _MonoBrandTicker({required this.c});
  final ArconMono c;

  @override
  State<_MonoBrandTicker> createState() => _MonoBrandTickerState();
}

class _MonoBrandTickerState extends State<_MonoBrandTicker>
    with SingleTickerProviderStateMixin {
  static const brands = [
    'Dior',
    'Hermès',
    'Jean Paul Gaultier',
    'Sensai',
    'Carolina Herrera',
    'Rabanne', //
    'Dolce&Gabbana',
    'La Prairie',
    'Givenchy',
    'Sisley Paris',
    'Paradis des Sens',
    'Dr. Barbara Sturm',
    "Penhaligon's",
    'Byredo',
    "L'Artisan Parfumeur",
    'Dries Van Noten',
    'Scentologia',
  ];

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 70),
  )..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${brands.length} GLOBAL PREMIUM MARKA · TEK PANEL',
          textAlign: TextAlign.center,
          style: c.text(
            9.5,
            weight: FontWeight.w600,
            color: c.faint,
            spacing: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        // şerit kenar dolgusunun dışına taşmasın
        ClipRect(
          child: _Marquee(
            names: [for (final b in brands) b.toUpperCase()],
            anim: _anim,
            leftToRight: false,
            opacity: 1,
            fontSize: 11.5,
            color: c.ink,
            fontFamily: arconFontFamily,
          ),
        ),
      ],
    );
  }
}

class _ConnectMark extends StatefulWidget {
  const _ConnectMark();

  @override
  State<_ConnectMark> createState() => _ConnectMarkState();
}

class _ConnectMarkState extends State<_ConnectMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

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
            style: TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
              height: 1,
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'ARCON hesabınla giriş yap',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xB3FFFFFF),
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
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

class _ConnectGlowState extends State<_ConnectGlow>
    with TickerProviderStateMixin {
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
  late final AnimationController _top = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  )..repeat();
  late final AnimationController _bottom = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 180),
  )..repeat();

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
            child: _Marquee(
              names: _brands.sublist(0, half + 1),
              anim: _top,
              leftToRight: true,
              opacity: 0.42,
              fontSize: 15,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: pad.bottom + 18,
            child: _Marquee(
              names: _brands.sublist(half),
              anim: _bottom,
              leftToRight: false,
              opacity: 0.22,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sonsuz kayan marka şeridi; kenarlarda yumuşakça kaybolur.
class _Marquee extends StatelessWidget {
  const _Marquee({
    required this.names,
    required this.anim,
    required this.leftToRight,
    required this.opacity,
    required this.fontSize,
    this.color = const Color(0xFFE7EDF2),
    this.fontFamily,
  });

  final List<String> names;
  final Animation<double> anim;
  final bool leftToRight;
  final double opacity;
  final double fontSize;
  final Color color;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: fontFamily,
            color: color.withValues(alpha: opacity),
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
    );
    final text = '${names.join('     ·     ')}     ·     ';
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final w = tp.width;
    return IgnorePointer(
      child: SizedBox(
        height: tp.height + 4,
        child: ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            colors: [
              Color(0x00FFFFFF),
              Color(0xFFFFFFFF),
              Color(0xFFFFFFFF),
              Color(0x00FFFFFF),
            ],
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
            child: Text(
              '$text$text$text',
              maxLines: 1,
              softWrap: false,
              style: style,
            ),
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

class _ConnectButtonState extends State<_ConnectButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

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
              colors: const [
                Color(0xFFE8EEF3),
                Color(0xFFFFFFFF),
                Color(0xFFC9D3DC),
                Color(0xFFFFFFFF),
              ],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 22,
                offset: Offset(0, 10),
              ),
            ],
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
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF0B0D10),
                      ),
                    )
                  : const Text(
                      'Giriş yap',
                      style: TextStyle(
                        color: Color(0xFF0B0D10),
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
