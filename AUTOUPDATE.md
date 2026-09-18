# Setting up auto-update

Omnibus now uses [Sparkle](https://sparkle-project.org) to check for new
versions of itself and install them automatically -- same mechanism most
non-App-Store Mac apps use. The code side is already wired up (see
`App/OmnibusApp.swift` and `App/CheckForUpdatesView.swift`); what's left
is a one-time setup, plus a small routine every time you cut a new
release.

This needs the app **not** to be sandboxed -- `App/Omnibus.entitlements`
already has `com.apple.security.app-sandbox` set to `false`. Sparkle's
sandboxed installer needs extra helper processes that are a lot more
fragile to hand-wire outside Xcode's own Sparkle project template, and
since you're building and running this yourself rather than shipping
through the App Store, there's no real downside to leaving the sandbox
off.

## About the private key -- read this before running anything

Sparkle's signing key comes in a pair: a **public** key, which is safe to
ship inside the app (anyone can use it to verify a signature, not create
one), and a **private** key, which is what actually signs each update.
Whoever holds the private key can make every installed copy of Omnibus
auto-install whatever they sign -- so it must never be committed to the
repo, never leave your Mac's Keychain, and never be shared, even with a
private repo. `generate_keys` (below) puts it straight into Keychain and
prints only the public half; the script in step 1 follows that same rule
and never writes the private key to a file.

## 1. Run the setup script

```
./scripts/setup-autoupdate.sh
```

This does steps 2-4 below for you in one go: downloads Sparkle's key
tool, generates (or reuses) your keypair, creates a GitHub repo and
pushes this project to it (via `gh`, if it's installed and you're logged
in -- otherwise it skips that part and asks for your GitHub username just
to fill in the feed URL), and patches the `SUPublicEDKey`/`SUFeedURL`
placeholders in `project.yml` and `App/Info.plist`. It's safe to re-run.

If you'd rather do it by hand, or `gh` isn't set up, steps 2-4 below walk
through the same thing manually.

## 2. Doing it by hand instead (or checking what the script did)

If you skipped the script, or `gh` wasn't available so it left the GitHub
part to you, here's the same thing step by step.

### Regenerate the Xcode project

`project.yml` now declares Sparkle as a Swift Package dependency:

```
xcodegen generate
```

Open the project in Xcode once after this so it resolves the Sparkle
package (Xcode does this automatically, may take a few seconds the first
time).

### Generate your signing key

Every update Sparkle installs has to be signed, so a compromised or
spoofed feed can't push arbitrary code to your Mac. Sparkle's key tooling
isn't part of the Swift package -- download it separately (this is what
`scripts/setup-autoupdate.sh` automates):

1. Go to https://github.com/sparkle-project/Sparkle/releases and download
   the latest `Sparkle-x.y.z.tar.xz` (the plain release archive, not the
   source code zip).
2. Unpack it, then in Terminal run the `generate_keys` tool it contains:
   ```
   ./bin/generate_keys
   ```
3. This creates a private key **directly in your Mac's Keychain** and
   prints a **public key** string to your terminal. Copy that public key
   -- see "About the private key" above for why only the public one ever
   leaves your Mac.

### Fill in the placeholders

Two files currently have placeholder values -- replace both:

- `project.yml`, under the target's `info.properties`:
  - `SUPublicEDKey` -- paste the public key from above.
  - `SUFeedURL` -- the raw GitHub URL for `appcast.xml` (see below),
    e.g. `https://raw.githubusercontent.com/yourname/Omnibus/main/appcast.xml`.
- `App/Info.plist` -- same two keys, same values (kept in sync with
  `project.yml` so a build works even before you rerun `xcodegen
  generate`).
- `appcast.xml`'s own `<link>` -- same URL, cosmetic only.

Run `xcodegen generate` again after editing `project.yml`.

### Put the project on GitHub

Sparkle's feed (`appcast.xml`, at the repo root) is hosted as a raw file
in your GitHub repo, and each release's zipped build is attached to a
GitHub Release -- no separate hosting needed. This repo already has an
initial commit on `main` (made when this setup was first put together);
you just need a GitHub remote to push it to.

1. Create a new repo on GitHub (public is simplest, since raw file access
   without a token requires it -- note this also makes
   `Shared/GoogleOAuthConfig.swift`'s client ID visible, which is fine:
   Google's "iOS"-type OAuth client IDs aren't meant to be kept secret,
   unlike a client *secret*). **Never** make the private signing key part
   of this repo -- see "About the private key" above.
2. From this project folder:
   ```
   git remote add origin https://github.com/YOUR_GITHUB_USERNAME/Omnibus.git
   git push -u origin main
   ```
3. Double-check the `SUFeedURL` you set above actually matches your
   GitHub username/repo/branch.

## 3. Releasing a new version

Each time you want to ship an update:

1. Bump the version in `project.yml`: `MARKETING_VERSION` (the
   user-visible version, e.g. `0.2.0`) and `CURRENT_PROJECT_VERSION` (an
   internal build number that must strictly increase every release, e.g.
   `2`). Run `xcodegen generate`.
2. In Xcode: **Product > Archive**, then **Distribute App > Copy App**
   (or Export) to get a `.app` build.
3. Zip it: `ditto -c -k --sequesterRsrc --keepParent Omnibus.app Omnibus.zip`
4. Sign the zip with `sign_update` (from the same Sparkle tools download as `generate_keys`, or `.sparkle-tools/bin/sign_update` if the setup script fetched them for you):
   ```
   .sparkle-tools/bin/sign_update Omnibus.zip
   ```
   This prints an `sparkle:edSignature="..."` attribute -- copy the whole
   thing.
5. Edit `appcast.xml`: uncomment/copy the `<item>` template and fill in
   the new version, today's date, the GitHub Release download URL you're
   about to create, and the signature from step 4.
6. On GitHub, create a new Release (tag it e.g. `v0.2.0`) and attach
   `Omnibus.zip` as a release asset.
7. Commit and push the updated `appcast.xml`.

Once that's pushed, every running copy of Omnibus checks once a day (see
`SUScheduledCheckInterval` in Info.plist) and will offer the update --
and anyone can also trigger a check right away from the app menu's
**Check for Updates…** item.
