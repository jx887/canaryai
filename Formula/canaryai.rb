class Canaryai < Formula
  include Language::Python::Virtualenv

  desc "AI agent security monitor — scan Claude Code session logs for suspicious behaviour"
  homepage "https://github.com/jx887/canaryai"
  url "https://github.com/jx887/canaryai/archive/refs/tags/v0.2.5.tar.gz"
  sha256 "df98a266dfb298ba2c88fb4ce1e08ef967718c3ccfc46d675f8fd7d9cf718c99"
  license "Apache-2.0"

  depends_on "python@3.13"

  resource "pyyaml" do
    url "https://files.pythonhosted.org/packages/54/ed/79a089b6be93607fa5cdaedf301d7dfb23af5f25c398d5ead2525b063e17/pyyaml-6.0.2.tar.gz"
    sha256 "d584d9ec91ad65861cc08d42e834324ef890a082e591037abe114850ff7bbc3e"
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
