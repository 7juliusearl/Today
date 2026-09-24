// Only reply-chain identifiers leave this parser; other headers are discarded.
function threadReferences(headers) {
  const unfolded = String(headers || '').replace(/\r?\n[ \t]+/g, ' ');
  const ids = [];
  for (const line of unfolded.split(/\r?\n/)) {
    if (!/^(references|in-reply-to):/i.test(line)) continue;
    for (const match of line.matchAll(/<([^<>\s]+)>/g)) ids.push(match[1]);
  }
  return [...new Set(ids)];
}

// Executed by osascript inside the local app. Never reads message bodies. Only mark-read changes a message, after an explicit open.
function run(argv) {
  const mail = Application('Mail');
  const action = argv[0];
  if (action === 'mailboxes') {
    const options = [];
    for (const account of mail.accounts()) {
      if (!account.enabled()) continue;
      for (const box of account.mailboxes()) {
        options.push({ account: account.id(), mailbox: box.name(), label: account.name() + ' — ' + box.name() });
      }
    }
    options.sort((a, b) => {
      const ai = a.mailbox.toLowerCase() === 'inbox' ? 0 : 1;
      const bi = b.mailbox.toLowerCase() === 'inbox' ? 0 : 1;
      return ai - bi || a.label.localeCompare(b.label);
    });
    return JSON.stringify(options);
  }
  const choice = JSON.parse(argv[1]);
  const account = mail.accounts.byId(choice.account);
  const box = account.mailboxes.byName(choice.mailbox);
  if (action === 'mark-read') {
    const target = JSON.parse(argv[2]);
    if (!/^\d+$/.test(target.id) || !target.messageID) throw Error('Invalid message identity');
    const message = box.messages.byId(Number(target.id));
    if (String(message.messageId()) !== target.messageID) throw Error('Message identity changed');
    message.readStatus = true;
    if (!message.readStatus()) throw Error('Mail did not confirm read status');
    return JSON.stringify({ isRead: true });
  }
  if (action !== 'read') throw Error('Unknown Mail action');
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const end = new Date(start);
  end.setDate(end.getDate() + 1);
  const conditions = [{ dateReceived: { _greaterThanEquals: start } }, { dateReceived: { _lessThan: end } }];
  const matches = box.messages.whose({ _and: conditions });
  const dates = matches.dateReceived();
  const indices = dates.map((date, index) => ({ date, index })).sort((a, b) => b.date - a.date);
  const items = [];
  for (const {date, index} of indices) {
    const message = matches[index];
    const attachmentCount = message.mailAttachments.length;
    let references = [];
    try { references = threadReferences(message.allHeaders()); } catch (_) { /* Keep unthreaded if headers aren't available. */ }
    items.push({ threadReferences: references, attachmentCount, isRead: message.readStatus(), id: String(message.id()), messageID: message.messageId() || '',
      subject: String(message.subject() || '(No subject)').slice(0, 500),
      sender: String(message.sender() || '').slice(0, 300), receivedAt: date.toISOString() });
  }
  return JSON.stringify({ items });
}
