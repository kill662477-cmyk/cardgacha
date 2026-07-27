const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CATEGORY_SET = new Set(['SYSTEM', 'REWARD', 'EVENT']);

function cleanText(value, maximum) {
  return typeof value === 'string' ? value.trim().slice(0, maximum) : '';
}

export function normalizeMailboxMessage(value = {}) {
  if (!value || typeof value !== 'object' || !UUID_PATTERN.test(String(value.id ?? ''))) return null;
  const title = cleanText(value.title, 160);
  const body = cleanText(value.body, 2000);
  if (!title || !body) return null;
  const category = CATEGORY_SET.has(value.category) ? value.category : 'SYSTEM';
  const points = Number.isSafeInteger(value.points) && value.points >= 0 ? value.points : 0;
  const createdAt = Number.isFinite(Date.parse(value.createdAt)) ? value.createdAt : new Date(0).toISOString();
  const readAt = value.readAt && Number.isFinite(Date.parse(value.readAt)) ? value.readAt : null;
  return {
    id: String(value.id),
    eventKey: cleanText(value.eventKey, 160),
    category,
    title,
    body,
    points,
    createdAt,
    readAt,
  };
}

export function normalizeMailboxState(value = {}) {
  const messages = (Array.isArray(value.messages) ? value.messages : [])
    .map(normalizeMailboxMessage)
    .filter(Boolean)
    .sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt));
  const actualUnread = messages.filter((message) => !message.readAt).length;
  const serverUnread = Number.isSafeInteger(value.unreadCount) && value.unreadCount >= 0
    ? value.unreadCount
    : actualUnread;
  return {
    messages,
    unreadCount: Math.max(actualUnread, serverUnread),
  };
}

export function applyMailboxRead(mailbox, result = {}) {
  const current = normalizeMailboxState(mailbox);
  if (result.ok === false || !UUID_PATTERN.test(String(result.mailId ?? ''))) return current;
  const readAt = result.readAt && Number.isFinite(Date.parse(result.readAt))
    ? result.readAt
    : new Date().toISOString();
  const messages = current.messages.map((message) => (
    message.id === result.mailId ? { ...message, readAt } : message
  ));
  const unreadCount = Number.isSafeInteger(result.unreadCount) && result.unreadCount >= 0
    ? result.unreadCount
    : messages.filter((message) => !message.readAt).length;
  return { messages, unreadCount };
}

export function mailboxBadgeText(unreadCount) {
  const count = Math.max(0, Number(unreadCount) || 0);
  if (count <= 0) return '';
  return count > 9 ? '9+' : String(count);
}

