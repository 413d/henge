cask "henge" do
  version "0.2.0"
  sha256 "98cb527252198532a608dc57007c7bf050a2be539a32f9e10e305fbeb483dfdc"

  url "https://github.com/413d/henge/releases/download/v#{version}/Henge-v#{version}-universal.zip"
  name "Henge"
  desc "Menu bar utility for fixing text typed in the wrong RU/EN keyboard layout"
  homepage "https://413d.github.io/henge/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "Henge.app"

  if methods.include?(:postflight_steps)
    postflight_steps do
      run "/usr/bin/xattr",
          args:         ["-dr", "com.apple.quarantine", "{{appdir}}/Henge.app"],
          must_succeed: false
    end
  else
    postflight do
      system_command "/usr/bin/xattr",
                     args: ["-dr", "com.apple.quarantine", "#{appdir}/Henge.app"],
                     sudo: false
    end
  end

  uninstall quit: "io.github.413d.Henge"

  zap trash: "~/Library/Application Support/Henge"

  caveats <<~EOS
    After launching Henge, grant Accessibility access in:
      System Settings -> Privacy & Security -> Accessibility
  EOS
end
