cask "canaryai" do
  version "0.2.4"
  sha256 "9cb4a2c4216eeacbc6fac4707e92acb6bd4136142bf606df8baa91e2f3791fa4"

  url "https://github.com/jx887/homebrew-canaryai/releases/download/v#{version}/CanaryAI-#{version}.dmg"
  name "CanaryAI"
  desc "AI agent security monitor for Claude Code"
  homepage "https://github.com/jx887/homebrew-canaryai"

  # Installs the menu bar app
  app "CanaryAI.app"

  # Exposes the bundled canaryai CLI so it works from the terminal too
  binary "#{appdir}/CanaryAI.app/Contents/Resources/canaryai"
end
