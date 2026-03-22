#!/usr/bin/env bash
set -euo pipefail

# Deploy a new CanaryAI release (two-repo pattern):
# 1. Bumps version in build.sh
# 2. Builds the DMG
# 3. Creates a GitHub release on jx887/canaryai with the DMG
# 4. Updates the Homebrew tap (jx887/homebrew-canaryai) with new version + checksums

APP_REPO="jx887/canaryai"
TAP_REPO="jx887/homebrew-canaryai"
VERSION="${1:?Usage: ./release.sh 0.x.x}"
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

# Check app repo is public
VISIBILITY=$(gh repo view "${APP_REPO}" --json visibility --jq '.visibility' 2>/dev/null || echo "unknown")
if [ "${VISIBILITY}" != "PUBLIC" ]; then
    echo "Error: repo ${APP_REPO} is ${VISIBILITY} — make it public first:"
    echo "  gh repo edit ${APP_REPO} --visibility public"
    exit 1
fi

# --- Bump version in build.sh ---
echo "==> Bumping version to ${VERSION}..."
sed -i '' "s/^VERSION=.*/VERSION=\"${VERSION}\"/" CanaryAIApp/build.sh

git add CanaryAIApp/build.sh
git diff --cached --quiet || git commit -m "Bump version to ${VERSION}"
git push

# --- Build DMG (also patches SettingsView.swift) ---
echo "==> Building DMG..."
(cd "$(dirname "$0")/CanaryAIApp" && ./build.sh)

# --- Tag and push ---
echo "==> Tagging ${TAG}..."
git tag "${TAG}"
git push origin "${TAG}"

# --- Create GitHub release on the app repo and upload DMG ---
echo "==> Creating GitHub release on ${APP_REPO}..."
gh release create "${TAG}" \
    --repo "${APP_REPO}" \
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

TARBALL_SHA=$(gh api "repos/${APP_REPO}/tarball/${TAG}" | shasum -a 256 | awk '{print $1}')
echo "  Tarball: ${TARBALL_SHA}"

# --- Commit SettingsView.swift (patched by build.sh) ---
git add CanaryAIApp/Sources/SettingsView.swift
git diff --cached --quiet || git commit -m "Release ${TAG}: version sync"
git push

# --- Update Homebrew tap repo ---
echo "==> Updating Homebrew tap (${TAP_REPO})..."
TAP_DIR=$(mktemp -d)
gh repo clone "${TAP_REPO}" "${TAP_DIR}" -- -q

# Update Cask
CASK_FILE="${TAP_DIR}/Casks/canaryai.rb"
if [ -f "${CASK_FILE}" ]; then
    sed -i '' "s/version \"[0-9]*\.[0-9]*\.[0-9]*\"/version \"${VERSION}\"/" "${CASK_FILE}"
    sed -i '' "s/sha256 \"[a-f0-9]*\"/sha256 \"${DMG_SHA}\"/" "${CASK_FILE}"
else
    echo "Warning: Cask file not found at ${CASK_FILE}"
fi

# Update Formula (careful: two sha256 lines — only replace the tarball one, not PyYAML's)
FORMULA_FILE="${TAP_DIR}/Formula/canaryai.rb"
if [ -f "${FORMULA_FILE}" ]; then
    sed -i '' "s|refs/tags/v[0-9]*\.[0-9]*\.[0-9]*.tar.gz|refs/tags/${TAG}.tar.gz|" "${FORMULA_FILE}"
    awk -v new_sha="${TARBALL_SHA}" 'BEGIN{done=0} /sha256/ && !done {sub(/sha256 "[a-f0-9]+"/, "sha256 \"" new_sha "\""); done=1} {print}' "${FORMULA_FILE}" > "${FORMULA_FILE}.tmp" && mv "${FORMULA_FILE}.tmp" "${FORMULA_FILE}"
else
    echo "Warning: Formula file not found at ${FORMULA_FILE}"
fi

cd "${TAP_DIR}"
git add -A
git diff --cached --quiet || git commit -m "Update to v${VERSION}"
git push
cd - >/dev/null

rm -rf "${TAP_DIR}"

echo ""
echo "==> Done! CanaryAI ${TAG} is live."
echo "  App:  https://github.com/${APP_REPO}/releases/tag/${TAG}"
echo "  Tap:  https://github.com/${TAP_REPO}"
echo ""
echo "Users can update with: brew update && brew upgrade --cask canaryai"
