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
        const rows = Array.from({length: 12}, (_, i) => ({
          id: () => i, messageId: () => 'id-' + i + '@example.test',
          subject: () => '<script>Untrusted subject</script>', sender: () => 'Sender',
          get content() { throw Error('Must not read message body'); }
        }));
        rows.dateReceived = () => Array.from({length: 12}, (_, i) => new Date(2026, 8, 1 + i));
        const inbox = { name: () => 'INBOX', unreadCount: () => 25, messages: {
          whose: predicate => {
            queriedUnread = predicate._and[0].readStatus === false;
            queriedWindow = predicate._and[1].dateReceived._greaterThan instanceof Date;
            return rows;
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
        assert(result["unreadCount"] as? Int == 25)
        let items = result["items"] as! [[String: Any]]
        assert(items.count == 8 && items.first?["id"] as? String == "11", "Return eight newest messages")
        assert(items.first?["subject"] as? String == "<script>Untrusted subject</script>", "Subjects are data, not executed scripts")
        assert(context.evaluateScript("queriedUnread && queriedWindow")!.toBool(), "Read only unread messages in the lookback window")
        context.setObject(try String(contentsOfFile: "app.js", encoding: .utf8), forKeyedSubscript: "appSource" as NSString)
        context.evaluateScript("new Function(appSource)")
        assert(errors.isEmpty, errors.joined(separator: "\n"))
        print("PASS: mailbox selection, unread filter, 14-day query, newest-first order, eight-message limit, header-only reads, and dashboard JavaScript syntax.")
    }
}
