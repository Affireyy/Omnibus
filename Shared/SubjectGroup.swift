import Foundation

/// One entry in the sidebar's "Classrooms" list: a Google Classroom course,
/// with whatever SchoolSoft lessons and Chat messages could be confidently
/// matched to it folded in.
public struct SubjectGroup: Identifiable, Sendable, Equatable {
    public var id: String
    public var displayName: String
    public var lessons: [Lesson] = []
    public var coursework: [ClassroomWorkItem] = []
    public var messages: [ChatMessageItem] = []

    public var pendingCourseworkCount: Int {
        coursework.filter { !$0.isOverdue }.count
    }

    public var hasActivity: Bool {
        !lessons.isEmpty || !coursework.isEmpty || !messages.isEmpty
    }
}

public enum SubjectMatcher {
    /// Builds one group per Classroom course (`courses` is the source of
    /// truth for what shows up as a "Classroom" -- every course appears,
    /// whether or not it currently has coursework, lessons, or chat
    /// activity matched to it). Coursework attaches by its real courseId,
    /// which is exact. SchoolSoft lesson subjects and Chat space names have
    /// no shared identifier with Classroom, so those attach by best-effort
    /// normalized-name matching against the course's name -- a lesson or
    /// space that doesn't confidently match just doesn't show up under that
    /// classroom; it's still visible in the plain Schedule / Messages
    /// screens either way.
    public static func buildGroups(
        courses: [ClassroomCourse],
        lessons: [Lesson],
        coursework: [ClassroomWorkItem],
        messages: [ChatMessageItem]
    ) -> [SubjectGroup] {
        var groups: [SubjectGroup] = courses.map { SubjectGroup(id: $0.id, displayName: $0.name) }
        guard !groups.isEmpty else { return [] }

        for item in coursework {
            if let i = groups.firstIndex(where: { $0.id == item.courseId }) {
                groups[i].coursework.append(item)
            }
        }

        func matchIndex(for name: String) -> Int? {
            let key = normalize(name)
            guard !key.isEmpty else { return nil }
            return groups.firstIndex { candidate in
                let candidateKey = normalize(candidate.displayName)
                guard !candidateKey.isEmpty else { return false }
                if candidateKey == key { return true }
                // Only let a longer name absorb a shorter one when the
                // shorter one is a meaningful chunk, not just "1" or "a".
                if key.count >= 4 && candidateKey.contains(key) { return true }
                if candidateKey.count >= 4 && key.contains(candidateKey) { return true }
                return sharesFirstWord(candidateKey, key)
            }
        }

        let lessonsBySubject = Dictionary(grouping: lessons, by: \.subject)
        for (name, items) in lessonsBySubject {
            if let i = matchIndex(for: name) {
                groups[i].lessons.append(contentsOf: items)
            }
        }

        let messagesBySpace = Dictionary(grouping: messages, by: \.spaceDisplayName)
        for (name, items) in messagesBySpace {
            if let i = matchIndex(for: name) {
                groups[i].messages.append(contentsOf: items)
            }
        }

        return groups.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private static func normalize(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = raw.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : " " }
        return String(scalars)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func sharesFirstWord(_ a: String, _ b: String) -> Bool {
        guard let firstA = a.split(separator: " ").first, let firstB = b.split(separator: " ").first else { return false }
        guard firstA.count >= 4, firstB.count >= 4 else { return false }
        return firstA == firstB
    }
}
