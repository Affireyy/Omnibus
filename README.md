# Omnibus

One native macOS dashboard for SchoolSoft (schedule + lunch), Google
Classroom, and Google Chat -- not three widgets side by side, but one app
where a subject's lessons, coursework, and chat messages show up together.
SwiftUI, styled with Liquid Glass on macOS 26+ (graceful Material fallback
on Sonoma/Sequoia).

## How it's organized

A single window: a sidebar (Today / Schedule / Coursework / Messages, plus
one entry per matched subject) and one glass panel as the detail area --
every screen is that same one panel, just showing different content, so
switching screens never feels like switching apps. A search field in the
toolbar filters Schedule, Coursework, and Messages at once.

**Subject matching** (`Shared/SubjectGroup.swift`) is the integration
piece: it groups a SchoolSoft lesson subject, a Classroom course, and a
Chat space together when their names reasonably match, so `Subjects >
Mathematics 4` shows this week's lessons, open coursework, and recent
messages for that class in one place, with a reply box right there.
Worth knowing: SchoolSoft, Classroom, and Chat have no shared ID for "this
is the same class," so this is a heuristic name match, not a guarantee --
a subject named very differently across services may not link up
automatically. Nothing is ever hidden because of this, though: every
lesson, coursework item, and message still shows in the plain Schedule /
Coursework / Messages screens regardless of whether it got grouped.

## Project structure

```
Omnibus/
├── App/
│   ├── OmnibusApp.swift      # App entry, windows, menu commands
│   ├── RootView.swift        # Sidebar + detail shell, toolbar, search
│   ├── SidebarView.swift     # Today/Schedule/Coursework/Messages + subjects
│   ├── TodayView.swift       # Home screen: now, subjects with activity, recent messages
│   ├── ScheduleView.swift    # Full week, lessons + lunch
│   ├── CourseworkView.swift  # Full coursework list
│   ├── MessagesView.swift    # Full message feed + compose
│   ├── SubjectView.swift     # One subject's lessons+coursework+messages together
│   ├── ComposeBar.swift      # Shared "send a Chat message" control
│   ├── Rows.swift            # Shared row views (lesson/coursework/message)
│   ├── GlassPanel.swift      # The one-panel-per-screen container + section header
│   └── GlassSurface.swift    # Liquid Glass modifier + pre-26 fallback
│
├── Shared/
│   ├── KeychainHelper.swift            # (ported) Keychain wrapper
│   ├── Schedule.swift                  # (ported) Schedule/Lesson models
│   ├── LunchMenu.swift                 # (ported) Lunch models
│   ├── SchoolSoftScheduleService.swift # (ported) Live + mock SchoolSoft client
│   ├── GoogleOAuthConfig.swift         # OAuth client ID/scopes
│   ├── GoogleAuthManager.swift         # PKCE OAuth + token refresh + Keychain
│   ├── GoogleClassroomClient.swift     # Classroom REST client
│   ├── GoogleChatClient.swift          # Chat REST client (read + send)
│   ├── SubjectGroup.swift              # Cross-service subject matching
│   └── OmnibusStore.swift              # Combined state, subject groups, disk cache
│
└── project.yml                   # XcodeGen spec (same pattern as SchoolSoftWidget)
```

## Build

```sh
cd Omnibus
xcodegen generate
open Omnibus.xcodeproj
```

Press **Cmd+R**. SchoolSoft sync works immediately from Settings; Google
sign-in needs one-time setup first -- see **SETUP.md**.
