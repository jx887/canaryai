cask "canaryai" do
  version "0.2.3"
  sha256 "FILL_IN_AFTER_RELEASE"

  url "https://github.com/jx887/homebrew-canaryai/releases/download/v#{version}/CanaryAI-#{version}.dmg"
  name "CanaryAI"
  desc "AI agent security monitor for Claude Code"
  homepage "https://github.com/jx887/homebrew-canaryai"

  # Installs the menu bar app
  app "CanaryAI.app"

  # Exposes the bundled canaryai CLI so it works from the terminal too
  binary "#{appdir}/CanaryAI.app/Contents/Resources/canaryai"
end
