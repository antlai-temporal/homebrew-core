class Deno < Formula
  desc "Secure runtime for JavaScript and TypeScript"
  homepage "https://deno.land/"
  url "https://github.com/denoland/deno/releases/download/v1.36.3/deno_src.tar.gz"
  sha256 "aac93b064dd5f9658184879542a9cad61f7cea599b85442563b86fd78da116d1"
  license "MIT"
  head "https://github.com/denoland/deno.git", branch: "main"

  bottle do
    rebuild 1
    sha256 cellar: :any_skip_relocation, arm64_ventura:  "a9f67b4695f760ad079dc130f08be53ee0a2f9a948d7181ee81f67d19a902a84"
    sha256 cellar: :any_skip_relocation, arm64_monterey: "c5cb3f47e5ec45ee095f7011796776c0ed87b0da9a7799b4e30477b576527f01"
    sha256 cellar: :any_skip_relocation, arm64_big_sur:  "76e7697e6ffb6cb2ea6dca9e9037f9c0ee3a008e68d3e02746b94211e062d80e"
    sha256 cellar: :any_skip_relocation, ventura:        "b787f1bae0122afe13b28e5224ed65ced9eb86913a9e8de3d12896d62ac1087a"
    sha256 cellar: :any_skip_relocation, monterey:       "b4f98cf3ee1aef6870c8e57cf99a04858f5a1b5d63cf36fce69738abbe895d8b"
    sha256 cellar: :any_skip_relocation, big_sur:        "4c551e4a04ed99c714a447a0f5066a77662e7d2ed71a2ac1e7a21347c05be5ed"
    sha256 cellar: :any_skip_relocation, x86_64_linux:   "52839e7e16a97e5165795cb4b8d528d2ae9fb23c41669276a842b8a85c767ad9"
  end

  depends_on "cmake" => :build
  depends_on "llvm" => :build
  depends_on "ninja" => :build
  depends_on "python@3.11" => :build
  depends_on "rust" => :build
  depends_on "sqlite" # needs `sqlite3_unlock_notify`

  uses_from_macos "libffi"
  uses_from_macos "xz"
  uses_from_macos "zlib"

  on_macos do
    depends_on xcode: ["10.0", :build] # required by v8 7.9+
  end

  on_linux do
    depends_on "pkg-config" => :build
    depends_on "glib"
  end

  fails_with gcc: "5"

  # Temporary resources to work around build failure due to files missing from crate
  # We use the crate as GitHub tarball lacks submodules and this allows us to avoid git overhead.
  # TODO: Remove this and `v8` resource when https://github.com/denoland/rusty_v8/issues/1065 is resolved
  # Use the version of `v8` crate at: https://github.com/denoland/deno/blob/v#{version}/Cargo.lock
  # Search for 'name = "v8"' (without single quotes).
  resource "rusty_v8" do
    url "https://static.crates.io/crates/v8/v8-0.74.3.crate"
    sha256 "2eedac634b8dd39b889c5b62349cbc55913780226239166435c5cf66771792ea"
  end

  # Find the v8 version from the last commit message at:
  # https://github.com/denoland/rusty_v8/commits/v#{rusty_v8_version}/v8
  # Then, use the corresponding tag found in https://github.com/denoland/v8/tags.
  resource "v8" do
    url "https://github.com/denoland/v8/archive/refs/tags/11.6.189.12-denoland-96bea5eafa4374f3c7ab.tar.gz"
    sha256 "56fd627eb19e219a88cf956a4b282fb567726c1e1b0ea2984754202f17e409f4"
  end

  # Use the version of `deno_core` crate at: https://github.com/denoland/deno/blob/v#{version}/Cargo.lock
  # Search for 'name = "deno_core"' (without single quotes).
  resource "deno_core" do
    url "https://github.com/denoland/deno_core/archive/refs/tags/0.204.0.tar.gz"
    sha256 "32946d1b5ac8b7e66a52ee3e6ae5b10a8e80046a0b3663a8050c0af23e371c8b"
  end

  # To find the version of gn used:
  # 1. Update the version for resource `rusty_v8` (see comment above).
  # 2. Find ninja_gn_binaries tag: https://github.com/denoland/rusty_v8/blob/v#{rusty_v8_version}/tools/ninja_gn_binaries.py#L21
  # 3. Find short gn commit hash from commit message: https://github.com/denoland/ninja_gn_binaries/tree/#{ninja_gn_binaries_tag}
  # 4. Find full gn commit hash: https://gn.googlesource.com/gn.git/+/#{gn_commit}
  resource "gn" do
    url "https://gn.googlesource.com/gn.git",
        revision: "70d6c60823c0233a0f35eccc25b2b640d2980bdc"
  end

  def install
    # Work around files missing from crate
    # TODO: Remove this at the same time as `rusty_v8` + `v8` resources
    (buildpath/"../rusty_v8").mkpath
    resource("rusty_v8").stage do |r|
      system "tar", "-C", buildpath/"../rusty_v8",
                    "--strip-components", "1", "-xzvf", "v8-#{r.version}.crate"
    end
    resource("v8").stage do
      cp_r "tools/builtins-pgo", buildpath/"../rusty_v8/v8/tools/builtins-pgo"
    end

    resource("deno_core").stage buildpath/"../deno_core"

    # Avoid vendored dependencies.
    inreplace "ext/ffi/Cargo.toml",
              /^libffi-sys = "(.+)"$/,
              'libffi-sys = { version = "\\1", features = ["system"] }'
    inreplace "ext/node/Cargo.toml",
              /^libz-sys = { version = "(.+)", features = \["static"\] }$/,
              'libz-sys = "\\1"'
    inreplace "Cargo.toml",
              /^rusqlite = { version = "(.+)", features = \["unlock_notify", "bundled"\] }$/,
              'rusqlite = { version = "\\1", features = ["unlock_notify"] }'

    if OS.mac? && (MacOS.version < :mojave)
      # Overwrite Chromium minimum SDK version of 10.15
      ENV["FORCE_MAC_SDK_MIN"] = MacOS.version
    end

    python3 = "python3.11"
    # env args for building a release build with our python3, ninja and gn
    ENV.prepend_path "PATH", Formula["python@3.11"].libexec/"bin"
    ENV["PYTHON"] = Formula["python@3.11"].opt_bin/python3
    ENV["GN"] = buildpath/"gn/out/gn"
    ENV["NINJA"] = Formula["ninja"].opt_bin/"ninja"
    # build rusty_v8 from source
    ENV["V8_FROM_SOURCE"] = "1"
    # Build with llvm and link against system libc++ (no runtime dep)
    ENV["CLANG_BASE_PATH"] = Formula["llvm"].prefix

    resource("gn").stage buildpath/"gn"
    cd "gn" do
      system python3, "build/gen.py"
      system "ninja", "-C", "out"
    end

    # cargo seems to build rusty_v8 twice in parallel, which causes problems,
    # hence the need for -j1
    # Issue ref: https://github.com/denoland/deno/issues/9244
    system "cargo", "--config", ".cargo/local-build.toml",
                    "install", "-vv", "-j1", *std_cargo_args(path: "cli")

    generate_completions_from_executable(bin/"deno", "completions")
  end

  def check_binary_linkage(binary, library)
    binary.dynamically_linked_libraries.any? do |dll|
      next false unless dll.start_with?(HOMEBREW_PREFIX.to_s)

      File.realpath(dll) == File.realpath(library)
    end
  end

  test do
    (testpath/"hello.ts").write <<~EOS
      console.log("hello", "deno");
    EOS
    assert_match "hello deno", shell_output("#{bin}/deno run hello.ts")
    assert_match "console.log",
      shell_output("#{bin}/deno run --allow-read=#{testpath} https://deno.land/std@0.50.0/examples/cat.ts " \
                   "#{testpath}/hello.ts")

    linked_libraries = [
      Formula["sqlite"].opt_lib/shared_library("libsqlite3"),
    ]
    unless OS.mac?
      linked_libraries += [
        Formula["libffi"].opt_lib/shared_library("libffi"),
        Formula["zlib"].opt_lib/shared_library("libz"),
      ]
    end
    linked_libraries.each do |library|
      assert check_binary_linkage(bin/"deno", library),
              "No linkage with #{library.basename}! Cargo is likely using a vendored version."
    end
  end
end
