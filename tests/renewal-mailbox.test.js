import assert from 'node:assert/strict';
import {
  applyMailboxRead,
  mailboxBadgeText,
  normalizeMailboxMessage,
  normalizeMailboxState,
} from '../src/renewal/mailbox.js';

const unreadId = '00000000-0000-4000-8000-000000000001';
const readId = '00000000-0000-4000-8000-000000000002';
const state = normalizeMailboxState({
  unreadCount: 1,
  messages: [
    {
      id: readId,
      category: 'SYSTEM',
      eventKey: 'system:test',
      title: '읽은 우편',
      body: '이미 확인했습니다.',
      points: 0,
      createdAt: '2026-07-27T09:00:00.000Z',
      readAt: '2026-07-27T09:10:00.000Z',
    },
    {
      id: unreadId,
      category: 'REWARD',
      eventKey: 'reward:test',
      title: '보상 지급 완료',
      body: '50,000 포인트가 반영되었습니다.',
      points: 50000,
      createdAt: '2026-07-27T10:00:00.000Z',
      readAt: null,
    },
  ],
});

assert.equal(state.messages[0].id, unreadId, 'newest mail must be first');
assert.equal(state.unreadCount, 1);
assert.equal(mailboxBadgeText(1), '1');
assert.equal(mailboxBadgeText(10), '9+');
assert.equal(mailboxBadgeText(0), '');
assert.equal(normalizeMailboxMessage({ id: 'bad' }), null);

const marked = applyMailboxRead(state, {
  ok: true,
  mailId: unreadId,
  readAt: '2026-07-27T10:05:00.000Z',
  unreadCount: 0,
});
assert.equal(marked.unreadCount, 0);
assert.equal(marked.messages.find((mail) => mail.id === unreadId).readAt, '2026-07-27T10:05:00.000Z');

const rejected = applyMailboxRead(state, {
  ok: false,
  mailId: unreadId,
});
assert.equal(rejected.unreadCount, 1, 'failed read must preserve unread state');

console.log('renewal mailbox tests passed: normalization, unread badge, idempotent read state');
