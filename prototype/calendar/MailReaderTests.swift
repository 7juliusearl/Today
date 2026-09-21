import Foundation
import JavaScriptCore

@main struct MailReaderTests {
    static func main() throws {
        let context = JSContext()!
        var errors: [String] = []
        context.exceptionHandler = { _, error in errors.append(error?.toString() ?? "JavaScript error") }
        context.evaluateScript("""
        let queriedUnread = false;
        let queriedWindow = false;
        const today = new Date(); today.setHours(0, 0, 0, 0);
        const tomorrow = new Date(today); tomorrow.setDate(tomorrow.getDate() + 1);
        const rows = Array.from({length: 14}, (_, i) => ({
          date: i === 12 ? new Date(today.getTime() - 1000) : i === 13 ? tomorrow : new Date(today.getTime() + i * 60000),
          mailAttachments: {length: i < 3 ? 1 : 0},
          id: () => i, messageId: () => 'id-' + i + '@example.test',
          readStatus: () => i % 2 === 0,
          subject: () => '<script>Untrusted subject</script>', sender: () => 'Sender',
          get content() { throw Error('Must not read message body'); }
        }));
        const inbox = { name: () => 'INBOX', messages: {
          whose: predicate => {
            queriedUnread = predicate._and.some(p => p.readStatus !== undefined);
            const start = predicate._and[0].dateReceived._greaterThanEquals;
            const end = predicate._and[1].dateReceived._lessThan;
            queriedWindow = +start === +today && +end === +tomorrow;
            const matches = rows.filter(row => row.date >= start && row.date < end);
            matches.dateReceived = () => matches.map(row => row.date);
            return matches;
          }
        }};
        const boxes = () => [inbox];
        boxes.byName = name => { if (name !== 'INBOX') throw Error('Wrong mailbox'); return inbox; };
        const account = { enabled: () => true, id: () => 'account-one', name: () => 'Work', mailboxes: boxes };
        const accounts = () => [account];
        accounts.byId = id => { if (id !== 'account-one') throw Error('Wrong account'); return account; };
        function Application(name) { if(name !== 'Mail') throw Error('Wrong app'); return {accounts}; }
        """)
        let script = try String(contentsOfFile: "prototype/calendar/mail/read-mail.js", encoding: .utf8)
        context.evaluateScript(script)
        let choices = context.evaluateScript("JSON.parse(run(['mailboxes']))")!.toArray()!
        assert(choices.count == 1)
        let result = context.evaluateScript("JSON.parse(run(['read', JSON.stringify({account: 'account-one', mailbox: 'INBOX'})]))")!.toDictionary()!
        let items = result["items"] as! [[String: Any]]
        assert(items.count == 12 && items.first?["id"] as? String == "11", "Return all today’s messages newest first, including more than eight")
        assert(items.first?["subject"] as? String == "<script>Untrusted subject</script>", "Subjects are data, not executed scripts")
        assert(context.evaluateScript("!queriedUnread && queriedWindow")!.toBool(), "Include read and unread within local midnight boundaries")
        assert(items.last?["id"] as? String == "0", "Include midnight today, exclude yesterday and tomorrow")
        assert(items.first?["isRead"] as? Bool == false, "Preserve unread status from Mail")
        assert(items.last?["isRead"] as? Bool == true, "Preserve read status from Mail")
        context.evaluateScript("rows.length = 0")
        assert(context.evaluateScript("JSON.parse(run(['read', JSON.stringify({account: 'account-one', mailbox: 'INBOX'})])).items.length")!.toInt32() == 0)
        context.setObject(try String(contentsOfFile: "app.js", encoding: .utf8), forKeyedSubscript: "appSource" as NSString)
        context.evaluateScript("new Function(appSource)")
        context.evaluateScript("""
        eval(appSource.slice(appSource.indexOf('function groupMailThreads'), appSource.indexOf('function renderMail')));
        function mail(id, refs, day = 1) { return {id, messageID:id, threadReferences:refs, sender:'Same sender', subject:'Same subject', receivedAt:`2026-09-${20+day}T08:00:00Z`}; }
        function check(value, text) { if (!value) throw Error(text); }
        check(groupMailThreads([mail('a', []), mail('b', [])]).length === 2, 'Same sender/subject alone must not merge');
        check(groupMailThreads([mail('a', []), mail('b', ['a'])]).length === 1, 'Direct reply');
        check(groupMailThreads([mail('a', ['old']), mail('b', ['old'])]).length === 1, 'Shared ancestor outside today');
        check(groupMailThreads([mail('a', []), mail('c', ['b']), mail('b', ['a'])]).length === 1, 'Out-of-order chain');
        check(groupMailThreads([mail('a', []), mail('a', [])])[0].length === 1, 'Duplicate Message-ID');
        check(groupMailThreads([mail('', []), {...mail('', []), id:'other'}]).length === 2, 'Missing identifiers stay separate');
        check(groupMailThreads([mail('a', []), mail('b', ['a'], 2)])[0][0].id === 'b', 'Newest message leads');
        check(threadReferences('References: <a>\\r\\n <b>\\r\\nIn-Reply-To: <b>').join(',') === 'a,b', 'Folded reply headers');
        check(threadReferences('Subject: Same subject').length === 0, 'Ignore unrelated headers');
        """)

        assert(errors.isEmpty, errors.joined(separator: "\n"))
        print("PASS: mailbox selection, today-only boundaries, read and unread mail, newest-first order, no eight-message limit, header-only reads, reply-chain grouping and isolation, folded headers, and dashboard JavaScript syntax.")
    }
}
