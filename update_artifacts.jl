# Copyright (c) 2025 Felix Kahle.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

using ArtifactUtils, Pkg.Artifacts, Base.BinaryPlatforms

if isempty(ARGS)
    error("Usage: julia update_artifacts.jl <tag_name>")
end

tag_name = ARGS[1]
repo_name = get(ENV, "GITHUB_REPOSITORY", "FelixKahle/Bollard.jl")
base_url = "https://github.com/$repo_name/releases/download/$tag_name"

println("Syncing Artifacts.toml with release: $tag_name")
println("Repository: $repo_name")

platforms = [
    # Linux
    (file="bollard-linux-x64.tar.gz", plat=Platform("x86_64", "linux")),
    (file="bollard-linux-arm64.tar.gz", plat=Platform("aarch64", "linux")),
    # Windows
    (file="bollard-windows-x64.tar.gz", plat=Platform("x86_64", "windows")),
    (file="bollard-windows-arm64.tar.gz", plat=Platform("aarch64", "windows")),
    # macOS
    (file="bollard-macos-x64.tar.gz", plat=Platform("x86_64", "macos")),
    (file="bollard-macos-arm64.tar.gz", plat=Platform("aarch64", "macos"))
]

for p in platforms
    url = "$base_url/$(p.file)"
    print("  - Processing $(p.file)... ")
    try
        add_artifact!(
            "Artifacts.toml",
            "bollard_ffi",
            url,
            force=true,
            platform=p.plat
        )
        println("Success")
    catch e
        println("Failed: $e")
        global any_failed = true
    end
end

if @isdefined(any_failed) && any_failed
    error("One or more artifacts failed to download/hash.")
end