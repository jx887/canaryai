#!/usr/bin/env bash
set -euo pipefail

REPO="jx887/homebrew-canaryai"
VERSION="${1:-0.1.0}"
TAG="v${VERSION}"
DMG="CanaryAI-${VERSION}.dmg"

echo "==> Releasing CanaryAI ${TAG}"

# --- Preflight checks ---
command -v gh >/dev/null || { echo "Error: gh CLI not installed"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Error: not logged in — run 'gh auth login'"; exit 1; }

if git rev-parse "${TAG}" >/dev/null 2>&1; then
    echo "Error: tag ${TAG} already exists locally"
    exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Error: uncommitted changes — commit or stash first"
    exit 1
fi

# Check repo is public (brew tap won't work on private repos)
VISIBILITY=$(gh repo view "${REPO}" --json visibility --jq '.visibility' 2>/dev/null || echo "unknown")
if [ "${VISIBILITY}" != "PUBLIC" ]; then
    echo "Error: repo is ${VISIBILITY} — make it public first:"
    echo "  gh repo edit ${REPO} --visibility public"
    exit 1
fi

# --- Bump version in all files ---
echo "==> Bumping version to ${VERSION}..."
sed -i '' "s/^VERSION=.*/VERSION=\"${VERSION}\"/" CanaryAIApp/build.sh
sed -i '' "s/version \"[0-9]*\.[0-9]*\.[0-9]*\"/version \"${VERSION}\"/" Casks/canaryai.rb
sed -i '' "s|refs/tags/v[0-9]*\.[0-9]*\.[0-9]*.tar.gz|refs/tags/${TAG}.tar.gz|" Formula/canaryai.rb
sed -i '' "s/sha256 \"[a-f0-9]\{64\}\"/sha256 \"FILL_IN_AFTER_RELEASE\"/" Casks/canaryai.rb
sed -i '' "s/sha256 \"[a-f0-9]\{64\}\"/sha256 \"FILL_IN_AFTER_RELEASE\"/" Formula/canaryai.rb

git add CanaryAIApp/build.sh Casks/canaryai.rb Formula/canaryai.rb
git diff --cached --quiet || git commit -m "Bump version to ${VERSION}"
git push

# --- Build DMG (also patches SettingsView.swift) ---
echo "==> Building DMG..."
(cd "$(dirname "$0")/CanaryAIApp" && ./build.sh)

# --- Tag and push ---
echo "==> Tagging ${TAG}..."
git tag "${TAG}"
git push origin "${TAG}"

# --- Create GitHub release and upload DMG ---
echo "==> Creating GitHub release..."
gh release create "${TAG}" \
    --repo "${REPO}" \
    --title "CanaryAI ${VERSION}" \
    --notes "## Install

\`\`\`bash
brew tap jx887/canaryai
brew install --cask canaryai
\`\`\`

Or download the DMG below." \
    "CanaryAIApp/${DMG}"

# --- Compute SHA256 checksums ---
echo "==> Computing SHA256 checksums..."

DMG_SHA=$(shasum -a 256 "CanaryAIApp/${DMG}" | awk '{print $1}')
echo "  DMG:     ${DMG_SHA}"

TARBALL_SHA=$(gh api "repos/${REPO}/tarball/${TAG}" | shasum -a 256 | awk '{print $1}')
echo "  Tarball: ${TARBALL_SHA}"

# --- Update formula files with checksums ---
echo "==> Updating formula checksums..."
sed -i '' "s/FILL_IN_AFTER_RELEASE/${DMG_SHA}/" Casks/canaryai.rb
sed -i '' "s/FILL_IN_AFTER_RELEASE/${TARBALL_SHA}/" Formula/canaryai.rb

# Commit SettingsView.swift (patched by build.sh) + formula checksums
git add CanaryAIApp/Sources/SettingsView.swift Casks/canaryai.rb Formula/canaryai.rb
git commit -m "Release ${TAG}: checksums"
git push

echo ""
echo "==> Done! CanaryAI ${TAG} is live."
echo "    https://github.com/${REPO}/releases/tag/${TAG}"
