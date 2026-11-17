import 'dart:math' as math;

import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:atomic_notes/ui/motion/entrance.dart';
import 'package:flutter/material.dart';

/// Terms (`/tcpage`, screens spec, App info and Terms): a reading layout at
/// most 640 wide, `bodyLarge` text, section headings in `titleLarge`, and
/// the last-updated date in `bodySmall`.
///
/// The copy is the existing legal text. Its literal `**` and ` - ` markers
/// are now clause headings and paragraphs (UX11).
class TCPage extends StatefulWidget {
  const TCPage({super.key});

  static const String title = 'Terms and conditions';

  /// The widest the text runs, for comfortable reading.
  static const double readingWidth = 640;

  @override
  State<TCPage> createState() => _TCPageState();
}

/// A titled clause: a bold lead and the paragraphs under it.
class _Clause {
  const _Clause(this.lead, this.lines);

  final String lead;
  final List<String> lines;
}

const String _lastUpdated = 'Last updated 14 Aug 2026';

const List<String> _agreement = [
  'Welcome to use Atomic Notes software and services! The software and services are provided by Atomic Notes Company Limited (hereinafter referred to as "we", "us", "our"). In order to use Atomic Notes software and services (hereinafter referred to as "the Software"), you should read and abide by the "Atomic Notes Terms of Use" (hereinafter referred to as "the Agreement") and the "Atomic Notes Privacy Policy". Please read carefully and fully understand the content of each clause, especially the clauses for exemption or limitation of liability, and the separate agreement for the use of a certain service, and choose to accept or not. Unless you have read and accepted all the terms of this agreement, you have no right to download, install or use this product and related services. Your download, installation, use, login and other actions shall be deemed to have read and agreed to the above agreement',
  "We operate the mobile application Atomic Notes (the 'App'), as well as any other related products and services that refer or link to these legal terms (the 'Legal Terms') (collectively, the 'Services').",
  'Atomic Notes is a local-first note-taking app with optional cloud sync. Notes are saved on your device first and sync to the cloud only when you choose. You can turn on end-to-end encryption, which seals your notes with AES-256-GCM using a recovery phrase that never leaves your device, so only you can read them. The app works fully offline, and you control cloud sync with the cloud sync button. A note contains a title, a body, and a creation date and time. Notes appear in a grid view.',
  "These Legal Terms constitute a legally binding agreement made between you, whether personally or on behalf of an entity ('you'), and Atomic Notes inc, concerning your access to and use of the Services. You agree that by accessing the Services, you have read, understood, and agreed to be bound by all of these Legal Terms. IF YOU DO NOT AGREE WITH ALL OF THESE LEGAL TERMS, THEN YOU ARE EXPRESSLY PROHIBITED FROM USING THE SERVICES AND YOU MUST DISCONTINUE USE IMMEDIATELY.",
  'The Services are intended for users who are at least 13 years of age. All users who are minors in the jurisdiction in which they reside (generally under the age of 18) must have the permission of, and be directly supervised by, their parent or guardian to use the Services. If you are a minor, you must have your parent or guardian read and agree to these Legal Terms prior to you using the Services.',
];

const List<_Clause> _scope = [
  _Clause('1.1 The scope of the Agreement', [
    'This agreement is an agreement between you and us regarding your download, installation, use, copying of this software, and use of Atomic Notes related services.',
  ]),
  _Clause('1.2 This license agreement points to content', [
    'The license content under this agreement refers to the Atomic Notes software license and services (hereinafter referred to as "the service") that we provide to users.The content of this agreement also includes relevant agreements and business rules that we may continue to publish on this service. Once the above content is officially released, it is an integral part of this agreement, and you should also abide by it.',
  ]),
];

const String _privacyIntro =
    'This Privacy Policy governs the collection, use, and protection of your information by our Note App with Cloud Sync. Please read this policy carefully to understand how we handle your data.';

const List<_Clause> _privacy = [
  _Clause('1. Information Collected', [
    'Your notes (their content), and the basic account information needed to sign in and sync: an email address and an authentication session. Note content is stored in your own Google Drive account, not on our servers. If you turn on end-to-end encryption, note content is stored only as ciphertext that neither Google Drive nor our servers can read.',
  ]),
  _Clause('2. Cloud Sync', [
    'Cloud sync is optional. When it is on, your note content is stored in your own Google Drive account, and account/sync metadata (note list, timestamps, settings) is stored on our servers, scoped to your signed-in session so only your account can read or write it. When sync is off, your notes stay on your device.',
  ]),
  _Clause('3. Data Security', [
    "Data is protected in transit by HTTPS. Note content at rest is protected by your own Google account's security, since it lives in your Drive; account metadata at rest is protected by session-scoped access control on our servers. With end-to-end encryption enabled, note content is additionally sealed with AES-256-GCM on your device before upload, and the recovery phrase and encryption key never leave your device.",
  ]),
  _Clause('4. No Analytics or Tracking', [
    'The app contains no analytics, no crash reporters, no advertising SDKs, and no third-party trackers, and it sets no tracking cookies.',
  ]),
  _Clause('5. No Advertising', [
    'The app does not display ads.',
  ]),
  _Clause('6. No AI Training', [
    'Your notes are never sent to an AI model and are never used as training data.',
  ]),
  _Clause('7. Third-Party Services', [
    "The app uses Google Sign-In for authentication and Google Drive to store your note content in your own Google account; account and sync metadata is stored on our own servers. Please review Google's privacy policy for details on how Sign-In and Drive handle data.",
  ]),
  _Clause('8. Your Controls', [
    'You can enable or disable cloud sync at any time, disconnect your Google account, and delete your synced data from the app, so you choose where your notes are stored.',
  ]),
  _Clause('9. Updates', [
    'This Privacy Policy may be updated to reflect changes in the app. Significant updates will be noted here.',
  ]),
  _Clause('10. Contact', [
    'For questions about this Privacy Policy, contact devbehindyou@gmail.com.',
  ]),
];

const List<String> _closing = [
  'Effective Date: 14-08-2026',
  'Thank you for trusting our Atomic Notes App with Cloud Sync. We prioritize the security and privacy of your data to provide you with a seamless note-taking experience.',
];

class _TCPageState extends State<TCPage> {
  final ScrollController _scroll = ScrollController();

  /// The collapsed header title shows once the large title has scrolled away.
  final ValueNotifier<bool> _titleAway = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => _titleAway.value =
        _scroll.hasClients && _scroll.offset > AtomicSpace.x10);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _titleAway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final width = MediaQuery.sizeOf(context).width;
    // The screen margin, widened so the text column is at most 640.
    final side = math.max(
        AtomicSpace.screenMargin(width), (width - TCPage.readingWidth) / 2);
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        bottom: false,
        child: EntranceGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: _titleAway,
                builder: (context, away, _) =>
                    AtomicPageHeader(title: TCPage.title, showTitle: away),
              ),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(side, 0, side,
                      AtomicSpace.x8 + MediaQuery.paddingOf(context).bottom),
                  children: [
                    const Entrance(index: 0, child: PageTitle(TCPage.title)),
                    Entrance(
                      index: 1,
                      child: Padding(
                        padding: const EdgeInsets.only(top: AtomicSpace.x2),
                        child: Text(
                          _lastUpdated,
                          key: const ValueKey('terms-last-updated'),
                          style: AtomicType.bodySmall
                              .copyWith(color: c.textSecondary),
                        ),
                      ),
                    ),
                    const SizedBox(height: AtomicSpace.x6),
                    Entrance(
                      index: 2,
                      child: _Section(children: [
                        const _Heading('Agreement to our legal terms'),
                        for (final p in _agreement) _Paragraph(p),
                      ]),
                    ),
                    Entrance(
                      index: 3,
                      child: _Section(children: [
                        const _Heading('1. The scope of the Agreement'),
                        for (final clause in _scope) _ClauseBlock(clause),
                      ]),
                    ),
                    Entrance(
                      index: 4,
                      child: _Section(children: [
                        const _Paragraph(_privacyIntro, lead: true),
                        for (final clause in _privacy) _ClauseBlock(clause),
                      ]),
                    ),
                    Entrance(
                      index: 5,
                      child: _Section(children: [
                        for (final p in _closing) _Paragraph(p),
                      ]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A block of the text, followed by the section gap.
class _Section extends StatelessWidget {
  const _Section({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AtomicSpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AtomicSpace.x3),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style:
              AtomicType.titleLarge.copyWith(color: context.colors.textPrimary),
        ),
      ),
    );
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text, {this.lead = false});

  final String text;

  /// The lead-in to a section: `titleMedium`, as it stood out before.
  final bool lead;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AtomicSpace.x4),
      child: Text(
        text,
        style: (lead ? AtomicType.titleMedium : AtomicType.bodyLarge)
            .copyWith(color: c.textPrimary),
      ),
    );
  }
}

class _ClauseBlock extends StatelessWidget {
  const _ClauseBlock(this.clause);

  final _Clause clause;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AtomicSpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              clause.lead,
              style: AtomicType.bodyLarge
                  .copyWith(color: c.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
          for (final line in clause.lines)
            Padding(
              padding: const EdgeInsets.only(top: AtomicSpace.x1),
              child: Text(
                line,
                style: AtomicType.bodyLarge.copyWith(color: c.textPrimary),
              ),
            ),
        ],
      ),
    );
  }
}
