# Setting up Google sign-in

Omnibus needs its own Google OAuth client ID before "Sign in with Google"
will work. This is a one-time, free setup in Google Cloud Console -- about
5 minutes.

## 1. Create a Google Cloud project

1. Go to https://console.cloud.google.com/ and create a new project (or
   reuse an existing personal one). Name it anything, e.g. "Omnibus".

## 2. Enable the APIs

In the project, go to **APIs & Services > Library** and enable:
- **Google Classroom API**
- **Google Chat API**
- **People API** (used to look up a DM partner's real name/photo)

## 3. Configure the OAuth consent screen

**APIs & Services > OAuth consent screen**:
- User type: **External** (unless you're on a Workspace org and want Internal).
- Fill in the required app name / support email fields.
- Add scopes: search for and add all of these --
  `.../auth/classroom.courses.readonly`,
  `.../auth/classroom.coursework.me.readonly`,
  `.../auth/classroom.announcements.readonly`,
  `.../auth/chat.spaces.readonly`,
  `.../auth/chat.spaces.create` (lets Messages' "Add Chat" button start a
  new direct message with someone who hasn't messaged you before),
  `.../auth/chat.messages` (full read/write -- lets Omnibus send messages and file attachments, not just read them; if attaching a file ever comes back with a scope error specifically, Google's docs list the narrower `chat.messages.create` for just the upload step, but the full scope above should already cover it),
  `.../auth/chat.memberships.readonly` (finds who a direct message is with),
  `.../auth/directory.readonly` (looks up that person's real name/photo --
  see the note below, this one's more likely to be blocked on a school account).
- Under **Test users** (while the app is in "Testing" publishing status),
  add your own Google account email. Until you add yourself here, Google
  will refuse to let your own account sign in.

## 4. Create the OAuth client ID

**APIs & Services > Credentials > Create Credentials > OAuth client ID**:
- Application type: **iOS** (yes, even though this is a Mac app -- the
  iOS client type is what lets Google redirect back via a custom URL
  scheme instead of requiring a local web server).
- Bundle ID: `com.dessimondi.Omnibus` (must match `PRODUCT_BUNDLE_IDENTIFIER`
  in `project.yml`).
- Create it. Google shows you a **Client ID** like
  `123456789-abc123xyz.apps.googleusercontent.com`.

## 5. Plug the client ID into the app

You need it in **two places**, and they must match exactly:

1. `Shared/GoogleOAuthConfig.swift`:
   ```swift
   public static let clientID = "123456789-abc123xyz.apps.googleusercontent.com"
   public static let redirectURIScheme = "com.googleusercontent.apps.123456789-abc123xyz"
   ```
   (`redirectURIScheme` is the client ID with the parts reversed and
   `.apps.googleusercontent.com` dropped -- Google shows this exact string
   on the credential's details page too, just copy it from there.)

2. `project.yml`, under the `Omnibus` target's `info.properties.CFBundleURLTypes`:
   ```yaml
   CFBundleURLSchemes:
     - com.googleusercontent.apps.123456789-abc123xyz
   ```

Then regenerate the Xcode project so the Info.plist change takes effect:
```sh
xcodegen generate
```

## 6. Sign in

Build and run, open **Settings** (gear icon), click **Sign in with
Google**. A system browser sheet opens; after you approve, it redirects
back into Omnibus automatically.

## 7. GIFs in Chat (optional)

The paperclip menu in the compose bar's "GIFs" option searches
[GIPHY](https://developers.giphy.com). Without a key it just shows an
error when you open it -- everything else in the app works fine without
this step.

1. Go to https://developers.giphy.com, sign in, **Create an App**.
2. Choose **API** (not SDK) when asked what kind of app.
3. Copy the key it gives you and paste it into `Shared/GiphyConfig.swift`:
   ```swift
   public static let apiKey = "your-key-here"
   ```

That's it -- no redirect URI or bundle ID matching needed, it's a plain
API key sent with each request.

(Why GIPHY and not Tenor, Google's own GIF API? Tenor stopped accepting
new API clients in January 2026, so it's not an option for a new app
anymore.)

## About your school Google account

If your Classroom/Chat account is a school-managed Google Workspace
account (not a personal Gmail), a Workspace admin can restrict which
third-party apps and API scopes are allowed. If sign-in works but every
Classroom or Chat request comes back with a 403, that's very likely a
domain-level restriction outside this app's control -- nothing to debug
in the code at that point.

`directory.readonly` (real names/photos for direct messages) is the scope
most likely to hit this, since browsing the org directory is a more
sensitive permission than reading your own Classroom/Chat data. If it's
blocked, Messages still works fine -- a DM just keeps a generic "Direct
message" label and an initials-only avatar instead of the other person's
real name and photo.

## SchoolSoft

No setup needed beyond your normal SchoolSoft login -- enter your school's
SchoolSoft URL, username, and password in Settings. It talks to the same
SchoolSoft mobile API the SchoolSoftWidget project already uses.
