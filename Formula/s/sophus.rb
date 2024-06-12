class Sophus < Formula
  desc "C++ implementation of Lie Groups using Eigen"
  homepage "https://strasdat.github.io/Sophus/latest/"
  url "https://github.com/strasdat/Sophus/archive/refs/tags/1.24.6.tar.gz"
  sha256 "0f3e46a98817f9841634c5ed85eda8597340e9e4b85b3d9ceb587ac56028f33a"
  license "MIT"
  version_scheme 1
  head "https://github.com/strasdat/Sophus.git", branch: "master"

  bottle do
    sha256 cellar: :any_skip_relocation, all: "e444266e8c7ead4969b894a4ed37b57dba375d1eea5ecce83695d4f47812eb68"
  end

  depends_on "cmake" => [:build, :test]
  depends_on "ceres-solver"
  depends_on "eigen"
  depends_on "fmt"

  fails_with gcc: "5" # C++17 (ceres-solver dependency)

  def install
    system "cmake", "-S", ".", "-B", "build", *std_cmake_args,
                    "-DBUILD_SOPHUS_EXAMPLES=OFF"
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
    (pkgshare/"examples").install "examples/hello_so3.cpp"
  end

  test do
    cp pkgshare/"examples/hello_so3.cpp", testpath
    (testpath/"CMakeLists.txt").write <<~EOS
      cmake_minimum_required(VERSION 3.5)
      project(HelloSO3)
      find_package(Sophus REQUIRED)
      add_executable(HelloSO3 hello_so3.cpp)
      target_link_libraries(HelloSO3 Sophus::Sophus)
    EOS

    system "cmake", "-DSophus_DIR=#{share}/Sophus", "."
    system "make"
    assert_match "The rotation matrices are", shell_output("./HelloSO3")
  end
end
