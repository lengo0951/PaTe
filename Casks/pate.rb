cask "pate" do
  version "1.2.0"
  sha256 :no_check

  url "https://github.com/lengo0951/PaTe/releases/download/v#{version}/PATE-#{version}.dmg"
  name "PATE"
  desc "Ultra-lightweight native clipboard and encrypted account manager"
  homepage "https://github.com/lengo0951/PaTe"

  depends_on macos: ">= :ventura"

  app "PATE.app"

  zap trash: [
    "~/Library/Application Support/PATE",
    "~/Library/Preferences/com.quocngo.PATE.plist",
  ]
end
