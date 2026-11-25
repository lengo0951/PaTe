cask "pasteflow" do
  version "1.2.0"
  sha256 :no_check

  url "https://github.com/lengo0951/PasteFlow/releases/download/v#{version}/PasteFlow-#{version}.dmg"
  name "PasteFlow"
  desc "Ultra-lightweight native clipboard and credential manager"
  homepage "https://github.com/lengo0951/PasteFlow"

  depends_on macos: ">= :ventura"

  app "PasteFlow.app"

  zap trash: [
    "~/Library/Application Support/PasteFlow",
    "~/Library/Preferences/com.coolstar.PasteFlow.plist",
  ]
end
