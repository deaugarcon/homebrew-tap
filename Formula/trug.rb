class Trug < Formula
  desc "Privacy-first local iPhone backup and inspection CLI for macOS"
  homepage "https://github.com/deaugarcon/trug"
  url "https://github.com/deaugarcon/trug/archive/refs/tags/v0.1.0-alpha.tar.gz"
  sha256 "2727e22beed386cb046241f043765937752e78c697de43753c520af10a68eda4"
  license "MIT"

  depends_on "autoconf" => :build
  depends_on "automake" => :build
  depends_on "libtool" => :build
  depends_on "pkg-config" => :build
  depends_on "openssl@3"
  depends_on :macos
  depends_on macos: :sonoma

  def install
    # Build the pinned libimobiledevice stack into ./Vendor, then the CLI.
    system "./Scripts/build-deps.sh"
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
  end

  test do
    assert_match "0.1.0-alpha", shell_output("#{bin}/trug --version")
    # An unknown store is a usage error (exit 64) — exercises the CLI parser
    # without needing a paired device or a backup on the test machine.
    assert_match(/error|usage/i,
      shell_output("#{bin}/trug backup inspect 00000000-000000000000000 nosuchstore 2>&1", 64))
  end
end
