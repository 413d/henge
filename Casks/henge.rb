cask "henge" do
  version "0.2.1"
  sha256 "08c3fb62d4c220a71e667e12eb76401faf1cba905df1f3b22f6f8ecd0b544ac5"

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
