import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/credentials.dart';
import '../shared/theme.dart';
import '../shared/widgets.dart';
import '../state/session.dart';

/// Sign in, in the Stream look: browser sign-in where the platform allows
/// it, CLI credentials when another client left some, an API key anywhere,
/// and a demo for poking around offline.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});

  final Session session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _key = TextEditingController();
  final _server = TextEditingController(text: kDefaultServer);
  bool _showKey = false;
  bool _advanced = false;

  Session get _session => widget.session;
  String get _serverValue => normalizeServer(_server.text);

  @override
  void dispose() {
    _key.dispose();
    _server.dispose();
    super.dispose();
  }

  void _connect() {
    if (_key.text.trim().isEmpty) return;
    _session.signInWithApiKey(_key.text, server: _serverValue);
  }

  Future<void> _getKey() async {
    await launchUrl(Uri.parse('$_serverValue/dashboard#keys'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Rq.bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(-0.7, -1.1), radius: 1.5, colors: [Color(0xFF4A2D2A), Rq.bg]),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: ListenableBuilder(listenable: _session, builder: (context, _) => _form()),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form() {
    final busy = _session.signingIn;
    final oauthBlocked = _session.oauthUnavailable;
    final cli = _session.cliCandidate;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Center(child: ReqallMark(size: 72, radius: 16, glow: true)),
      const SizedBox(height: 18),
      const Center(child: Wordmark(size: 34)),
      const SizedBox(height: 6),
      Text('Your project memory, as one stream.', textAlign: TextAlign.center, style: Rq.body(color: Rq.textSoft)),
      const SizedBox(height: 28),
      if (_session.signInError != null) ...[
        _Banner(_session.signInError!),
        const SizedBox(height: 16),
      ],
      FilledButton.icon(
        onPressed: busy || oauthBlocked != null ? null : () => _session.signInWithOAuth(server: _serverValue),
        icon: const Icon(Icons.login_rounded, size: 18),
        label: const Text('Sign in with Reqall'),
        style: FilledButton.styleFrom(
          backgroundColor: Rq.accent,
          foregroundColor: Rq.bg,
          disabledBackgroundColor: Rq.surface,
          disabledForegroundColor: Rq.muted,
          minimumSize: const Size.fromHeight(48),
          textStyle: Rq.body(size: 15, weight: FontWeight.w600),
        ),
      ),
      if (oauthBlocked != null) ...[
        const SizedBox(height: 6),
        Text(oauthBlocked, textAlign: TextAlign.center, style: Rq.mono(size: 11, color: Rq.muted)),
      ],
      if (cli != null) ...[
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: busy ? null : _session.continueWithCli,
          icon: const Icon(Icons.terminal_rounded, size: 18),
          label: Text('Continue with CLI login · ${cli.host}'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Rq.text,
            side: const BorderSide(color: Rq.border),
            minimumSize: const Size.fromHeight(46),
          ),
        ),
      ],
      const SizedBox(height: 22),
      Row(children: [
        const Expanded(child: Divider(color: Rq.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text('or use an API key', style: Rq.mono(size: 11, color: Rq.muted)),
        ),
        const Expanded(child: Divider(color: Rq.border)),
      ]),
      const SizedBox(height: 14),
      TextField(
        controller: _key,
        obscureText: !_showKey,
        autocorrect: false,
        enableSuggestions: false,
        style: Rq.mono(size: 13),
        onSubmitted: (_) => _connect(),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Paste your API key',
          hintStyle: Rq.mono(size: 13, color: Rq.muted),
          filled: true,
          fillColor: Rq.bgDeep.withValues(alpha: 0.6),
          prefixIcon: const Icon(Icons.key_rounded, size: 18, color: Rq.muted),
          suffixIcon: IconButton(
            tooltip: _showKey ? 'Hide' : 'Show',
            icon: Icon(_showKey ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: Rq.muted),
            onPressed: () => setState(() => _showKey = !_showKey),
          ),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Rq.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Rq.accent)),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _getKey,
              child: Text('Get an API key ↗',
                  style: Rq.mono(size: 12, color: Rq.accent), overflow: TextOverflow.ellipsis, softWrap: false),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: busy || _key.text.trim().isEmpty ? null : _connect,
          style: FilledButton.styleFrom(
            backgroundColor: Rq.accent.withValues(alpha: 0.16),
            foregroundColor: Rq.accent,
            side: BorderSide(color: Rq.accent.withValues(alpha: 0.4)),
          ),
          child: busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Rq.accent))
              : const Text('Connect'),
        ),
      ]),
      const SizedBox(height: 18),
      if (!kIsWeb) ...[
        InkWell(
          onTap: () => setState(() => _advanced = !_advanced),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Icon(_advanced ? Icons.expand_less : Icons.expand_more, size: 18, color: Rq.muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text('Server · ${Uri.tryParse(_serverValue)?.host ?? _serverValue}',
                    style: Rq.mono(size: 11, color: Rq.muted), overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
        ),
        if (_advanced)
          TextField(
            controller: _server,
            style: Rq.mono(size: 13),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Rq.bgDeep.withValues(alpha: 0.6),
              enabledBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Rq.border)),
              focusedBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Rq.accent)),
            ),
          ),
      ] else
        Text('Requests go through this page\'s host to ${Uri.parse(kDefaultServer).host}.',
            textAlign: TextAlign.center, style: Rq.mono(size: 11, color: Rq.muted)),
      const SizedBox(height: 22),
      Center(
        child: TextButton.icon(
          onPressed: busy ? null : _session.startDemo,
          icon: const Icon(Icons.auto_awesome_outlined, size: 16, color: Rq.textSoft),
          label: Text('Try the demo', style: Rq.body(size: 13, color: Rq.textSoft)),
        ),
      ),
    ]);
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Rq.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Rq.danger.withValues(alpha: 0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.error_outline, color: Rq.danger, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: Rq.body(size: 13, color: Rq.textSoft))),
      ]),
    );
  }
}
