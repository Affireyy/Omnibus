import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: OmnibusStore
    @EnvironmentObject var auth: GoogleAuthManager

    @State private var schoolURL = UserDefaults.standard.string(forKey: "schoolURL") ?? ""
    @State private var username = UserDefaults.standard.string(forKey: "username") ?? ""
    @State private var password = ""
    @State private var isSyncingSchoolSoft = false
    @State private var schoolSoftStatus: String?
    @State private var isSigningIn = false
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("SchoolSoft Account") {
                TextField("School URL", text: $schoolURL, prompt: Text("https://sms.schoolsoft.se/yourschool"))
                    .textContentType(.URL)
                    .autocorrectionDisabled()

                TextField("Username", text: $username)
                    .textContentType(.username)
                    .autocorrectionDisabled()

                SecureField("Password", text: $password)
                    .textContentType(.password)

                HStack(spacing: 12) {
                    Button(isSyncingSchoolSoft ? "Connecting…" : "Save & Sync") {
                        saveSchoolSoft()
                    }
                    .disabled(isSyncingSchoolSoft || schoolURL.isEmpty || username.isEmpty || password.isEmpty)
                    .keyboardShortcut(.defaultAction)

                    if store.hasSchoolSoftAccount {
                        Button("Remove Account", role: .destructive) {
                            store.clearSchoolSoftAccount()
                            username = ""
                            schoolURL = ""
                            password = ""
                            schoolSoftStatus = "Account removed."
                        }
                    }
                }

                if let schoolSoftStatus {
                    Text(schoolSoftStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("Your password is encrypted and stored exclusively in macOS Keychain.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Google Account") {
                if !GoogleOAuthConfig.isConfigured {
                    Text("Google sign-in isn't configured yet. Add your OAuth client ID in Shared/GoogleOAuthConfig.swift -- see SETUP.md at the project root for the walkthrough.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if auth.isSignedIn {
                    LabeledContent("Signed in as", value: auth.accountEmail ?? "Google account")

                    Button("Sign Out", role: .destructive) {
                        auth.signOut()
                        Task {
                            await store.refreshClassroom()
                            await store.refreshChat()
                        }
                    }
                } else {
                    Button(isSigningIn ? "Signing in…" : "Sign in with Google") {
                        signIn()
                    }
                    .disabled(isSigningIn)
                }

                if let error = auth.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Text("Grants read-only access to Classroom coursework and Chat messages. Omnibus never posts, submits, or changes anything on your behalf.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
    }

    private func saveSchoolSoft() {
        isSyncingSchoolSoft = true
        schoolSoftStatus = "Connecting to SchoolSoft…"
        store.saveSchoolSoftAccount(url: schoolURL, username: username, password: password)

        Task {
            await store.refreshSchoolSoft()
            isSyncingSchoolSoft = false
            if let error = store.schoolSoftError {
                schoolSoftStatus = error
            } else {
                schoolSoftStatus = "Synced (\(store.schedule?.lessons.count ?? 0) lessons found)."
            }
        }
    }

    private func signIn() {
        isSigningIn = true
        Task {
            do {
                try await auth.signIn()
                await store.refreshClassroom()
                await store.refreshChat()
            } catch {
                // auth.lastError is already set by GoogleAuthManager; nothing else to do here.
            }
            isSigningIn = false
        }
    }
}
