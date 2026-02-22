class Canaryai < Formula
  include Language::Python::Virtualenv

  desc "AI agent security monitor — scan Claude Code session logs for suspicious behaviour"
  homepage "https://github.com/jx887/homebrew-canaryai"
  url "https://github.com/jx887/homebrew-canaryai/archive/refs/tags/v0.2.3.tar.gz"
  sha256 "887266564bae0fc337aba8e54273d1112197283b3fc691ec500ba0ec95877139"
  license "MIT"

  depends_on "python@3.13"

  resource "pyyaml" do
    url "https://files.pythonhosted.org/packages/54/ed/79a089b6be93607fa5cdaedf301d7dfb23af5f25c398d5ead2525b063e17/pyyaml-6.0.2.tar.gz"
    sha256 "887266564bae0fc337aba8e54273d1112197283b3fc691ec500ba0ec95877139"
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
