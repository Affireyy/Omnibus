#!/bin/bash
# One-time setup for the GitHub Actions release workflow
# (.github/workflows/release.yml): exports the Sparkle private key from
# your Mac's Keychain and stores it as the SPARKLE_PRIVATE_KEY secret on
# this repo, so CI can sign releases without you doing it by hand.
#
# Run this yourself in Terminal on your Mac (needs Keychain access and
# your own GitHub login -- neither reachable from Claude's side):
#
#   chmod +x scripts/setup-github-actions-release.sh
#   ./scripts/setup-github-actions-release.sh
#
# Security notes:
#   - The private key is written to a single 0600 temp file just long
#     enough to hand it to `gh secret set`, then deleted immediately
#     (a `trap` guarantees the delete runs even if something fails
#     partway through). It is never printed to the terminal, never
#     logged, and never written anywhere inside this repo.
#   - `generate_keys -x` COPIES the key out of Keychain, it doesn't
#     remove it -- local signing with generate_keys/sign_update keeps
#     working exactly as before.
#   - Once this is set, anyone with admin on the GitHub repo can (like
#     any repo secret) use it in a workflow, but GitHub never lets it be
#     read back as plain text again, in the UI or via `gh`/the API.

set -euo pipefail
cd "$(dirname "$0")/.."

TOOLS_DIR=".sparkle-tools"
SECRET_NAME="SPARKLE_PRIVATE_KEY"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
die() { printf '\nERROR: %s\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------------------
step "Checking prerequisites"
# ---------------------------------------------------------------------------
command -v gh >/dev/null || die "GitHub CLI (gh) is required -- install it (brew install gh) and run \`gh auth login\` first."
gh auth status >/dev/null 2>&1 || die "Not logged in to gh -- run \`gh auth login\` first."

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) \
    || die "Couldn't determine the GitHub repo for this folder -- make sure 'origin' points at it (see AUTOUPDATE.md)."
echo "Target repo: $REPO"

# ---------------------------------------------------------------------------
step "Fetching Sparkle's generate_keys tool"
# ---------------------------------------------------------------------------
if [ -x "$TOOLS_DIR/bin/generate_keys" ]; then
    echo "Already downloaded, reusing $TOOLS_DIR."
else
    mkdir -p "$TOOLS_DIR"
    ASSET_URL=$(curl -sL https://api.github.com/repos/sparkle-project/Sparkle/releases/latest \
        | grep '"browser_download_url"' \
        | grep -v 'for-Swift-Package-Manager' \
        | grep -o 'https://[^"]*\.tar\.xz' \
        | head -n1)
    [ -n "$ASSET_URL" ] || die "Couldn't find a Sparkle release download -- check https://github.com/sparkle-project/Sparkle/releases manually."
    curl -sL "$ASSET_URL" -o "$TOOLS_DIR/sparkle.tar.xz"
    tar -xJf "$TOOLS_DIR/sparkle.tar.xz" -C "$TOOLS_DIR"
    rm -f "$TOOLS_DIR/sparkle.tar.xz"
    [ -x "$TOOLS_DIR/bin/generate_keys" ] || die "generate_keys not found after extracting."
fi

# ---------------------------------------------------------------------------
step "Exporting the private key to a one-time temp file"
# ---------------------------------------------------------------------------
# A key must already exist (from setup-autoupdate.sh) for there to be
# anything to export.
# generate_keys -x refuses to write to a file that already exists (it
# won't silently overwrite a previous export), so the target path itself
# must NOT exist yet -- only the containing directory does. mktemp -d
# creates that directory securely (0700, unique); the file path inside it
# is then guaranteed fresh for generate_keys to create.
KEY_DIR=$(mktemp -d)
KEY_FILE="$KEY_DIR/sparkle_private_key"
trap 'rm -rf "$KEY_DIR"' EXIT

"$TOOLS_DIR/bin/generate_keys" -x "$KEY_FILE" \
    || die "generate_keys -x failed -- do you have a key yet? Run scripts/setup-autoupdate.sh first if not."
[ -s "$KEY_FILE" ] || die "Export produced an empty file -- nothing to store as the secret."

# ---------------------------------------------------------------------------
step "Storing it as the $SECRET_NAME secret on $REPO"
# ---------------------------------------------------------------------------
gh secret set "$SECRET_NAME" --repo "$REPO" < "$KEY_FILE"
rm -rf "$KEY_DIR"
trap - EXIT
echo "Secret set. (Its value can't be viewed again -- by design, GitHub never returns a secret's contents, only that it exists.)"

step "Done"
cat <<SUMMARY

$REPO now has a $SECRET_NAME secret, and .github/workflows/release.yml
is already in this repo. To ship a release from here on:

  git tag v0.2.0
  git push origin v0.2.0

That's it -- CI builds, signs, creates the GitHub Release, and appends
the appcast.xml entry on its own. See AUTOUPDATE.md for the full flow.
SUMMARY
