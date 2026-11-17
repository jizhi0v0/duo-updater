cask "duo-2055-var" do
  version "2.0"
  sha256 :no_check
  url "file:///tmp/duo-2055/duo-2055-var.tar.gz"
  name "Duo2055Var"
  desc "Disposable issue 2055 fixture"
  homepage "https://example.com"
  on_arm do
    version "1.0"
  end
  app "Duo2055Var.app"
end
