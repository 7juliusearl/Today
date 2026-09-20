// Executed by osascript inside the local app. Never reads message bodies or writes mail.
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
  const since = new Date(Date.now() - 14 * 86400000);
  const matches = box.messages.whose({ _and: [{ readStatus: false }, { dateReceived: { _greaterThan: since } }] });
  const dates = matches.dateReceived();
  const indices = dates.map((date, index) => ({ date, index })).sort((a, b) => b.date - a.date).slice(0, 8);
  const items = indices.map(({date, index}) => {
    const message = matches[index];
    return { id: String(message.id()), messageID: message.messageId() || '',
      subject: String(message.subject() || '(No subject)').slice(0, 500),
      sender: String(message.sender() || '').slice(0, 300), receivedAt: date.toISOString() };
  });
  return JSON.stringify({ unreadCount: box.unreadCount(), items });
}
