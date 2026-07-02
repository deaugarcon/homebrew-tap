class Trug < Formula
  desc "Privacy-first local iPhone backup and inspection CLI for macOS"
  homepage "https://github.com/deaugarcon/trug"
  url "https://github.com/deaugarcon/trug/archive/refs/tags/v0.1.1-alpha.tar.gz"
  sha256 "983b35d4dce8b4a09cd57633872e37f44971032e08ffeb69e70f09bfd198af05"
  license "MIT"

  depends_on "autoconf" => :build
  depends_on "automake" => :build
  depends_on "libtool" => :build
  depends_on "pkg-config" => :build
  depends_on :macos
  depends_on "openssl@3"

  on_macos do
    depends_on macos: :sonoma
  end

  def install
    # build-deps.sh drives dev builds through the `brew` CLI, which the
    # Homebrew build environment removes from PATH. Substitute the values
    # it would have asked brew for; the build deps it probes are declared
    # above, so the presence checks are safe to drop.
    inreplace "Scripts/build-deps.sh" do |s|
      s.gsub! "if ! command -v brew &>/dev/null; then", "if false; then"
      s.gsub! "if ! brew list openssl@3 &>/dev/null; then", "if false; then"
      s.gsub! "$(brew --repository)/Library/Homebrew/os/mac/pkgconfig",
              "#{HOMEBREW_LIBRARY}/Homebrew/os/mac/pkgconfig"
      s.gsub! "$(brew --prefix openssl@3)", formula_opt_prefix("openssl@3").to_s
    end

    # Build the pinned libimobiledevice stack into ./Vendor, then the CLI.
    system "./Scripts/build-deps.sh"

    # SwiftPM locates the vendored stack through pkg-config (Package.swift
    # declares the system libraries with pkgConfig names), so point it at
    # the .pc files build-deps.sh just installed.
    ENV.prepend_path "PKG_CONFIG_PATH", buildpath/"Vendor/lib/pkgconfig"
    system "swift", "build", "-c", "release", "--disable-sandbox"

    # The vendored dylibs are built with absolute install names rooted at the
    # (transient) build directory's Vendor/. Relocate the stack into libexec
    # and rewrite every install name — the binary's references and the libs'
    # own IDs and inter-dependencies — to the stable libexec location.
    (libexec/"lib").install Dir["Vendor/lib/*"]
    old = "#{buildpath}/Vendor/lib"
    new = "#{libexec}/lib"

    Dir["#{libexec}/lib/*.dylib"].each do |dylib|
      next if File.symlink?(dylib)

      MachO::Tools.change_dylib_id(dylib, "#{new}/#{File.basename(dylib)}")
      MachO.open(dylib).linked_dylibs.each do |dep|
        next unless dep.start_with?(old)

        MachO::Tools.change_install_name(dylib, dep, dep.sub(old, new))
      end
    end

    bin.install ".build/release/trug"
    MachO.open(bin/"trug").linked_dylibs.each do |dep|
      next unless dep.start_with?(old)

      MachO::Tools.change_install_name(bin/"trug", dep, dep.sub(old, new))
    end

    # Rewriting IDs/install names invalidates the ad-hoc signatures, and
    # arm64 macOS kills modified-signature binaries on launch — re-sign.
    Dir["#{libexec}/lib/*.dylib"].each do |dylib|
      next if File.symlink?(dylib)

      system "codesign", "--force", "--sign", "-", dylib
    end
    system "codesign", "--force", "--sign", "-", bin/"trug"
  end

  test do
    assert_match "0.1.1-alpha", shell_output("#{bin}/trug --version")
    # An unknown store is a usage error (exit 64) — exercises the CLI parser
    # without needing a paired device or a backup on the test machine.
    assert_match(/error|usage/i,
      shell_output("#{bin}/trug backup inspect 00000000-000000000000000 nosuchstore 2>&1", 64))
  end
end
