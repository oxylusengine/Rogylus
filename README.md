# Rogylus

[![Build](https://img.shields.io/github/actions/workflow/status/oxylusengine/Rogylus/xmake.yaml?&style=for-the-badge&logo=cmake&logoColor=orange&labelColor=black)](https://github.com/oxylusengine/Rogylus/actions/workflows/xmake.yaml)

A vehicular delivery roguelike set in an unstable, shifting anomaly zone. Players pilot a customizable, heavy-duty cargo rig across harsh, procedurally assembled terrain to deliver unstable payloads, manage vehicle physics, and upgrade their vehicle between runs. Made in Oxylus Engine.

## Playing

Grab the zip for your platform from [Releases](https://github.com/oxylusengine/Rogylus/releases),
extract it anywhere and run `Rogylus`. Everything the game needs is inside the folder.

On macOS the build is unsigned, so clear the quarantine flag once with
`xattr -dr com.apple.quarantine Rogylus-macos-arm64`. On Linux you need a Vulkan driver for your GPU.

## How it works

TODO

### Networking

TODO

## Building

Requires [xmake](https://xmake.io), the [Vulkan SDK](https://vulkan.lunarg.com/sdk/home) and a C++23
compiler. Oxylus is pulled in as an xmake package, so there is no engine checkout to manage.

```bash
xmake f --toolchain=clang --runtimes=c++_static -m debug
xmake build
xmake r Rogylus
```

Pick the toolchain for your platform (`clang-cl` on Windows, `mac-clang` on macOS, `nix-clang` on
NixOS) — see `xmake/toolchains.lua`. Modes are `debug`, `release` and `dist`.

Scripts and assets are copied next to the binary by the build, so iterating on gameplay is a plain
`xmake build` with no C++ to recompile. Pressing <kbd>R</kbd> in game reloads the RmlUI document and
clears the style cache.

## Releases

Pushing a `v*` tag builds the release configuration for Windows, Linux and macOS and publishes the
three playable zips to GitHub Releases. Pushes to `main` build and upload the same zips as workflow
artifacts without publishing a release.
