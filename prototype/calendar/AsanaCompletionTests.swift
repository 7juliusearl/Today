import Foundation

@main struct AsanaCompletionTests {
    @MainActor static func main() async {
        let child = AsanaBrief(title: "Assigned child", description: "Child instructions", url: "https://app.asana.com/0/0/10",
            parentTitle: "Parent", parentDescription: "Parent instructions", parentURL: "https://app.asana.com/0/0/20", message: nil)
        let cache = ["10": child]
        let parent = verifiedAsanaBrief("20", cache: cache, taskID: AsanaBriefs.taskID)
        assert(parent?.title == "Parent" && parent?.description == "Parent instructions")
        assert(parent?.parentURL == nil, "Parent popup must target the parent directly")
        assert(verifiedAsanaBrief("10", cache: cache, taskID: AsanaBriefs.taskID)?.title == "Assigned child")
        assert(verifiedAsanaBrief("30", cache: cache, taskID: AsanaBriefs.taskID) == nil)
        print("PASS: verified parent popups can load mentions and comments; unrelated tasks remain rejected.")
        var activity = AsanaCommentActivity(history: [:], unread: [])
        activity.record("parent", latest: "2026-10-28T09:00:00.000Z", viewed: false)
        assert(activity.unread.isEmpty, "Existing history is a baseline")
        activity.record("parent", latest: "2026-10-28T10:00:00.000Z", viewed: false)
        assert(activity.unread.contains("parent"), "New comment flagged")
        activity.record("child", latest: "", viewed: false)
        activity.record("child", latest: "2026-10-28T10:00:00.000Z", viewed: false)
        assert(activity.unread.contains("child"), "First new reply after empty baseline flagged")
        activity.record("parent", latest: "2026-10-28T09:00:00.000Z", viewed: true)
        assert(activity.unread.contains("parent"), "Viewing stale comments must not clear newer replies")
        activity.record("parent", latest: "2026-10-28T10:00:00.000Z", viewed: true)
        assert(!activity.unread.contains("parent") && activity.unread.contains("child"), "Only opened conversation cleared")
        print("PASS: comment baselines, new replies, independent parent/subtask read state, stale-read protection.")
        let briefs = AsanaBriefs()
        for url in ["https://example.com/task/123", "https://app.asana.com/0/0/123", "https://app.asana.com/1/1/project/2/task/3"] {
            do {
                _ = try await briefs.completeSubtask(taskURL: url)
                fatalError("Unverified tasks must be rejected before any write request")
            } catch {
                assert(error.localizedDescription.contains("Only your loaded assigned subtasks") || error.localizedDescription.contains("developer console"))
            }
        }
        print("PASS: arbitrary URLs, unloaded tasks, and unverified parents cannot be completed.")
    }
}
