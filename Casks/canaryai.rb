cask "canaryai" do
  version "0.2.2"
  sha256 "211b7d0fdf7be7fac8450797521c6e7daee27f2568cca2f7db10cb930c84f480"

  url "https://github.com/jx887/homebrew-canaryai/releases/download/v#{version}/CanaryAI-#{version}.dmg"
  name "CanaryAI"
  desc "AI agent security monitor for Claude Code"
  homepage "https://github.com/jx887/homebrew-canaryai"

  # Installs the menu bar app
  app "CanaryAI.app"

  # Exposes the bundled canaryai CLI so it works from the terminal too
  binary "#{appdir}/CanaryAI.app/Contents/Resources/canaryai"
end
