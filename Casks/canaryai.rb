cask "canaryai" do
  version "0.2.5"
  sha256 "4d4aca0d51d72eee1c825d350ce46640e2fc870750e0e6e8b2f8fcfe1ac2a64a"

  url "https://github.com/jx887/homebrew-canaryai/releases/download/v#{version}/CanaryAI-#{version}.dmg"
  name "CanaryAI"
  desc "AI agent security monitor for Claude Code"
  homepage "https://github.com/jx887/homebrew-canaryai"

  # Installs the menu bar app
  app "CanaryAI.app"

  # Exposes the bundled canaryai CLI so it works from the terminal too
  binary "#{appdir}/CanaryAI.app/Contents/Resources/canaryai"
end
