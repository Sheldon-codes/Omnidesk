import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omnidesk_agent/pages/email_page/email_draft_repository.dart';
import 'package:omnidesk_agent/pages/email_page/email_page_model.dart';
import 'package:omnidesk_agent/pages/email_page/widgets/email_body_renderer.dart';

void main() {
  test('EmailStore keeps mailbox mutations and sent previews in one source',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final store = container.read(emailStoreProvider.notifier);

    final original = store.findById('school-management')!;
    expect(original.unread, isTrue);
    store.openThread(original.id);
    expect(store.findById(original.id)!.unread, isFalse);

    store.toggleStar(original.id);
    expect(store.findById(original.id)!.starred, isFalse);
    store.markUnread(original.id);
    expect(store.findById(original.id)!.unread, isTrue);
    store.archive(original.id);
    expect(
        store.findById(original.id)!.folders, contains(EmailFolder.archived));
    expect(store.findById(original.id)!.folders,
        isNot(contains(EmailFolder.inbox)));

    final before = store.findById('shipping-rates')!;
    store.appendOutgoing(
      before.id,
      EmailThreadMessage(
        id: 'local-outbound',
        from: const EmailAddress(address: agentMailbox),
        to: const [EmailAddress(address: 'customer@example.com')],
        sentAt: DateTime(2026, 8, 20),
        direction: EmailDirection.outbound,
        body: const EmailBody(plainText: 'A local reply'),
      ),
    );
    expect(store.findById(before.id)!.latestMessage.body.plainText,
        'A local reply');
  });

  test('in-memory draft repository preserves and clears a complete draft',
      () async {
    final repository = InMemoryEmailDraftRepository();
    final draft = EmailDraft(
      key: 'draft-1',
      threadId: 'shipping-rates',
      mode: EmailComposerMode.reply,
      deltaJson: const [
        {'insert': 'Hello\n'},
      ],
      updatedAt: DateTime(2026, 8, 20),
      to: const [EmailAddress(address: 'customer@example.com')],
      subject: 'Re: Rates',
      attachments: const [
        EmailAttachment(
          id: 'file-1',
          filename: 'rates.pdf',
          mimeType: 'application/pdf',
          byteCount: 42,
          localPath: '/drafts/file-1.pdf',
        ),
      ],
    );
    await repository.save(draft);
    final restored = await repository.load(draft.key);
    expect(restored!.attachments.single.localPath, '/drafts/file-1.pdf');
    expect(restored.deltaJson.single['insert'], 'Hello\n');
    await repository.delete(draft.key);
    expect(await repository.load(draft.key), isNull);
  });

  test('HTML sanitization removes executable content and blocks remote images',
      () {
    final blocked = sanitizeEmailHtml(
      '<script>alert(1)</script><a href="https://safe.example">safe</a><img src="https://tracker.example/pixel.gif"><img src="cid:logo">',
      allowRemoteImages: false,
    );
    expect(blocked.document.querySelector('script'), isNull);
    expect(blocked.document.querySelector('a')!.attributes['href'],
        'https://safe.example');
    expect(blocked.document.querySelectorAll('img'), hasLength(1));
    expect(blocked.hasBlockedRemoteImages, isTrue);
  });
}
