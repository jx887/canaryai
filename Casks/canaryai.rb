cask "canaryai" do
  version "0.2.3"
  sha256 "31e3e13a36f13777d64dfe4f18f90e382c20877655121a06e0c7c95a062eba07"

  url "https://github.com/jx887/homebrew-canaryai/releases/download/v#{version}/CanaryAI-#{version}.dmg"
  name "CanaryAI"
  desc "AI agent security monitor for Claude Code"
  homepage "https://github.com/jx887/homebrew-canaryai"

  # Installs the menu bar app
  app "CanaryAI.app"

  # Exposes the bundled canaryai CLI so it works from the terminal too
  binary "#{appdir}/CanaryAI.app/Contents/Resources/canaryai"
end
