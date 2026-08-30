import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnidesk_agent/pages/tickets_page/ticket_store.dart';

void main() {
  test('ticket store creates, updates, resolves, and deletes local tickets',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);
    final store = container.read(ticketStoreProvider.notifier);
    final created = await store.create(const TicketCreateRequest(
      customerId: 'nana',
      customerLabel: 'Nana',
      contactIdentifier: '+254719106280',
      assignedAgent: 'Hillary',
      subject: 'New ticket',
      description: TicketDescription(plainText: 'A local fixture'),
      department: 'General',
      category: 'General inquiry',
      priority: TicketPriority.medium,
      status: TicketStatus.open,
    ));
    expect(container.read(ticketStoreProvider).findById(created.id), isNotNull);
    final resolved = await store.resolve(created.id, 'Solved locally');
    expect(resolved.status, TicketStatus.resolved);
    expect(resolved.resolution?.note, 'Solved locally');
    final reopened = await store.reopen(created.id);
    expect(reopened.status, TicketStatus.open);
    await store.delete(reopened.id, reopened.revision);
    expect(container.read(ticketStoreProvider).findById(created.id), isNull);
  });

  test('activity pagination keeps an explicit cursor seam', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);
    final store = container.read(ticketStoreProvider.notifier);
    final first = await store.loadActivity('DGKSL-388');
    expect(first.items, isNotEmpty);
    expect(first.nextCursor, isNotNull);
    final second =
        await store.loadActivity('DGKSL-388', cursor: first.nextCursor);
    expect(second.items, isNotEmpty);
  });
}
