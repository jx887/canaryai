class Canaryai < Formula
  include Language::Python::Virtualenv

  desc "AI agent security monitor — scan Claude Code session logs for suspicious behaviour"
  homepage "https://github.com/jx887/homebrew-canaryai"
  url "https://github.com/jx887/homebrew-canaryai/archive/refs/tags/v0.2.2.tar.gz"
  sha256 "ec9dc4701cb25bbeed864d2fa3237e7946864b6ae804372f1071820635ad8420"
  license "MIT"

  depends_on "python@3.13"

  resource "pyyaml" do
    url "https://files.pythonhosted.org/packages/54/ed/79a089b6be93607fa5cdaedf301d7dfb23af5f25c398d5ead2525b063e17/pyyaml-6.0.2.tar.gz"
    sha256 "ec9dc4701cb25bbeed864d2fa3237e7946864b6ae804372f1071820635ad8420"
  end

  def install
    venv = virtualenv_create(libexec, "python3")
    venv.pip_install resources
    venv.pip_install_and_link buildpath/"canaryai"
  end

  test do
    system bin/"canaryai", "--version"
  end
end
