import Foundation

public struct ClassroomWorkItem: Identifiable, Sendable, Equatable {
    public var id: String
    public var courseId: String
    public var courseName: String
    public var title: String
    public var workType: String
    public var description: String?
    public var dueDate: Date?
    public var alternateLink: URL?
    /// Files, links, videos, and forms attached to this assignment (Drive
    /// attachments, a YouTube video, a plain link, a Google Form) -- shown
    /// in CourseworkDetailView so you can open them without leaving Omnibus
    /// for the Classroom website first.
    public var materials: [ClassroomMaterial] = []

    public var isOverdue: Bool {
        guard let dueDate else { return false }
        return dueDate < Date()
    }
}

/// One file/link/video/form attached to a piece of coursework.
public struct ClassroomMaterial: Identifiable, Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case driveFile
        case youtubeVideo
        case link
        case form
    }

    public var id: String
    public var title: String
    public var url: URL
    public var kind: Kind

    public var systemImage: String {
        switch kind {
        case .driveFile: return "doc.fill"
        case .youtubeVideo: return "play.rectangle.fill"
        case .link: return "link"
        case .form: return "list.bullet.clipboard.fill"
        }
    }
}

/// One of your Classroom courses -- the sidebar's "Classrooms" list is
/// built directly from these, independent of whether a course currently
/// has any coursework loaded.
public struct ClassroomCourse: Identifiable, Sendable, Equatable {
    public var id: String
    public var name: String
}

public enum GoogleClassroomError: LocalizedError {
    case notSignedIn
    case requestFailed(Int, String)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in with Google to see Classroom coursework."
        case .requestFailed(let code, let body):
            return "Classroom API request failed (\(code)): \(body)"
        }
    }
}

/// Talks to the Google Classroom REST API as the signed-in user (read-only).
/// See https://developers.google.com/workspace/classroom/reference/rest
public final class GoogleClassroomClient: Sendable {
    private let auth: GoogleAuthManager

    public init(auth: GoogleAuthManager) {
        self.auth = auth
    }

    /// Active courses, newest coursework first, capped to a reasonable
    /// number of courses/items for a dashboard glance rather than a full
    /// paginated browse.
    /// All your active courses, for the sidebar's "Classrooms" list --
    /// independent of fetchRecentCoursework, so a course with no coursework
    /// yet still shows up.
    public func fetchCourses(limit: Int = 12) async throws -> [ClassroomCourse] {
        let token = try await auth.validAccessToken()
        let courses = try await fetchActiveCourses(token: token, limit: limit)
        return courses.map { ClassroomCourse(id: $0.id, name: $0.name) }
    }

    public func fetchRecentCoursework(courseLimit: Int = 12, itemsPerCourse: Int = 8) async throws -> [ClassroomWorkItem] {
        let token = try await auth.validAccessToken()
        let courses = try await fetchActiveCourses(token: token, limit: courseLimit)

        let items: [[ClassroomWorkItem]] = try await withThrowingTaskGroup(of: [ClassroomWorkItem].self) { group in
            for course in courses {
                group.addTask {
                    (try? await self.fetchCourseWork(token: token, course: course, limit: itemsPerCourse)) ?? []
                }
            }
            var collected: [[ClassroomWorkItem]] = []
            for try await result in group { collected.append(result) }
            return collected
        }

        return items.flatMap { $0 }.sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (l?, r?): return l < r
            case (nil, nil): return false
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }

    // MARK: - Courses

    private struct CourseDTO: Decodable {
        var id: String
        var name: String
    }
    private struct CoursesResponse: Decodable {
        var courses: [CourseDTO]?
    }

    private func fetchActiveCourses(token: String, limit: Int) async throws -> [CourseDTO] {
        var components = URLComponents(string: "https://classroom.googleapis.com/v1/courses")!
        components.queryItems = [
            URLQueryItem(name: "courseStates", value: "ACTIVE"),
            URLQueryItem(name: "pageSize", value: String(limit))
        ]
        let response: CoursesResponse = try await get(components.url!, token: token)
        return Array((response.courses ?? []).prefix(limit))
    }

    // MARK: - Coursework

    private struct DateComponentsDTO: Decodable {
        var year: Int?
        var month: Int?
        var day: Int?
    }
    private struct TimeOfDayDTO: Decodable {
        var hours: Int?
        var minutes: Int?
    }
    private struct CourseWorkDTO: Decodable {
        var id: String
        var title: String
        var description: String?
        var workType: String?
        var state: String?
        var alternateLink: String?
        var dueDate: DateComponentsDTO?
        var dueTime: TimeOfDayDTO?
        var materials: [MaterialDTO]?
    }

    // A Classroom "Material" is a union type -- exactly one of these four
    // fields is present per entry, matching which kind of attachment it is.
    private struct MaterialDTO: Decodable {
        var driveFile: DriveFileMaterialDTO?
        var youtubeVideo: YoutubeVideoMaterialDTO?
        var link: LinkMaterialDTO?
        var form: FormMaterialDTO?
    }
    private struct DriveFileMaterialDTO: Decodable {
        var driveFile: DriveFileDTO?
    }
    private struct DriveFileDTO: Decodable {
        var id: String?
        var title: String?
        var alternateLink: String?
    }
    private struct YoutubeVideoMaterialDTO: Decodable {
        var id: String?
        var title: String?
        var alternateLink: String?
    }
    private struct LinkMaterialDTO: Decodable {
        var url: String?
        var title: String?
    }
    private struct FormMaterialDTO: Decodable {
        var formUrl: String?
        var title: String?
    }
    private struct CourseWorkResponse: Decodable {
        var courseWork: [CourseWorkDTO]?
    }

    private func fetchCourseWork(token: String, course: CourseDTO, limit: Int) async throws -> [ClassroomWorkItem] {
        var components = URLComponents(string: "https://classroom.googleapis.com/v1/courses/\(course.id)/courseWork")!
        components.queryItems = [
            URLQueryItem(name: "courseWorkStates", value: "PUBLISHED"),
            URLQueryItem(name: "orderBy", value: "dueDate desc"),
            URLQueryItem(name: "pageSize", value: String(limit))
        ]
        // Resolved to a plain (immutable, Sendable) URL before the
        // concurrent fetch below -- `components` itself is a `var`, and
        // Swift 6's strict concurrency checking doesn't allow a mutable
        // local to be captured by an `async let`'s concurrently-executing
        // initializer, even read-only.
        let courseWorkURL = components.url!

        // Run alongside the courseWork fetch: an assignment's *shared*
        // template lives in courseWork.materials (fetched below), but when
        // a teacher has Classroom "make a copy for each student," your own
        // personal copy is attached to your *submission* instead -- a
        // completely separate resource -- so without this you'd only ever
        // see the template and never your own file.
        async let courseWorkResponse: CourseWorkResponse = get(courseWorkURL, token: token)
        async let submissionAttachments = fetchSubmissionAttachments(token: token, courseId: course.id)

        let response = try await courseWorkResponse
        let attachmentsByCourseWork = (try? await submissionAttachments) ?? [:]

        return (response.courseWork ?? []).map { dto in
            ClassroomWorkItem(
                id: dto.id,
                courseId: course.id,
                courseName: course.name,
                title: dto.title,
                workType: dto.workType ?? "ASSIGNMENT",
                description: dto.description,
                dueDate: Self.combine(date: dto.dueDate, time: dto.dueTime),
                alternateLink: dto.alternateLink.flatMap(URL.init(string:)),
                materials: Self.materials(from: dto.materials, courseWorkId: dto.id)
                    + (attachmentsByCourseWork[dto.id] ?? [])
            )
        }
    }

    // MARK: - Submissions (for your own per-assignment file copies)

    private struct StudentSubmissionDTO: Decodable {
        var courseWorkId: String?
        var assignmentSubmission: AssignmentSubmissionDTO?
    }
    private struct AssignmentSubmissionDTO: Decodable {
        var attachments: [AttachmentDTO]?
    }
    // Shaped like Material, but not identically -- Attachment's driveFile is
    // the DriveFile itself (no extra wrapper), and YouTube is capitalized
    // "youTubeVideo" here vs. Material's "youtubeVideo". Both quirks are
    // straight from Google's own schema, not a typo.
    private struct AttachmentDTO: Decodable {
        var driveFile: DriveFileDTO?
        var youTubeVideo: YoutubeVideoMaterialDTO?
        var link: LinkMaterialDTO?
        var form: FormMaterialDTO?
    }
    private struct StudentSubmissionsResponse: Decodable {
        var studentSubmissions: [StudentSubmissionDTO]?
    }

    /// Your own submission attachments for every assignment in a course,
    /// keyed by courseWorkId -- one request per course (courseWorkId "-"
    /// lists submissions across all of a course's coursework at once)
    /// rather than one request per assignment.
    private func fetchSubmissionAttachments(token: String, courseId: String) async throws -> [String: [ClassroomMaterial]] {
        var components = URLComponents(string: "https://classroom.googleapis.com/v1/courses/\(courseId)/courseWork/-/studentSubmissions")!
        components.queryItems = [
            URLQueryItem(name: "userId", value: "me"),
            URLQueryItem(name: "pageSize", value: "100")
        ]
        let response: StudentSubmissionsResponse = try await get(components.url!, token: token)

        var result: [String: [ClassroomMaterial]] = [:]
        for submission in response.studentSubmissions ?? [] {
            guard let courseWorkId = submission.courseWorkId else { continue }
            let materials = Self.materials(fromAttachments: submission.assignmentSubmission?.attachments, courseWorkId: courseWorkId)
            guard !materials.isEmpty else { continue }
            result[courseWorkId, default: []].append(contentsOf: materials)
        }
        return result
    }

    private static func materials(fromAttachments dtos: [AttachmentDTO]?, courseWorkId: String) -> [ClassroomMaterial] {
        guard let dtos else { return [] }
        return dtos.enumerated().compactMap { index, dto in
            let id = "\(courseWorkId)-submission-\(index)"
            if let file = dto.driveFile,
               let link = file.alternateLink, let url = URL(string: link) {
                return ClassroomMaterial(id: id, title: file.title ?? "Your file", url: url, kind: .driveFile)
            }
            if let video = dto.youTubeVideo,
               let link = video.alternateLink, let url = URL(string: link) {
                return ClassroomMaterial(id: id, title: video.title ?? "Video", url: url, kind: .youtubeVideo)
            }
            if let link = dto.link,
               let urlString = link.url, let url = URL(string: urlString) {
                return ClassroomMaterial(id: id, title: link.title ?? url.absoluteString, url: url, kind: .link)
            }
            if let form = dto.form,
               let urlString = form.formUrl, let url = URL(string: urlString) {
                return ClassroomMaterial(id: id, title: form.title ?? "Form", url: url, kind: .form)
            }
            return nil
        }
    }

    private static func materials(from dtos: [MaterialDTO]?, courseWorkId: String) -> [ClassroomMaterial] {
        guard let dtos else { return [] }
        return dtos.enumerated().compactMap { index, dto in
            let id = "\(courseWorkId)-material-\(index)"
            if let file = dto.driveFile?.driveFile,
               let link = file.alternateLink, let url = URL(string: link) {
                return ClassroomMaterial(id: id, title: file.title ?? "Attached file", url: url, kind: .driveFile)
            }
            if let video = dto.youtubeVideo,
               let link = video.alternateLink, let url = URL(string: link) {
                return ClassroomMaterial(id: id, title: video.title ?? "Video", url: url, kind: .youtubeVideo)
            }
            if let link = dto.link,
               let urlString = link.url, let url = URL(string: urlString) {
                return ClassroomMaterial(id: id, title: link.title ?? url.absoluteString, url: url, kind: .link)
            }
            if let form = dto.form,
               let urlString = form.formUrl, let url = URL(string: urlString) {
                return ClassroomMaterial(id: id, title: form.title ?? "Form", url: url, kind: .form)
            }
            return nil
        }
    }

    private static func combine(date: DateComponentsDTO?, time: TimeOfDayDTO?) -> Date? {
        guard let date, let year = date.year, let month = date.month, let day = date.day else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = time?.hours ?? 23
        comps.minute = time?.minutes ?? 59
        return Calendar.current.date(from: comps)
    }

    // MARK: - Networking

    private func get<T: Decodable>(_ url: URL, token: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleClassroomError.requestFailed(-1, "No response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw GoogleClassroomError.requestFailed(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
