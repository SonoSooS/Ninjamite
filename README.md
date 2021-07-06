# Ninjamite

Ninjamite is a framework which lets you create robust build scripts by writing rules in Lua, and emitting a `build.ninja` file with the configured rules.

Basically, Ninjamite aims to be a CMake-like alternative, while the build scripts using Ninjamite can act like `./configure` scripts.

However, since the build scripts are still Lua scripts, you don't need to just simply limit the build script to act like `./configure`. If using LuaJIT instead of plain old Lua 5.1, you can even use the flexibility of LuaJIT, and from there the possibilities are endless.

# Usage

You'll need the following:
- [ninja](https://github.com/ninja-build/ninja) in your `PATH`
- [Lua 5.1.5](https://sourceforge.net/projects/luabinaries/files/5.1.5/Tools%20Executables/) or LuaJIT in your `PATH` aliased as `lua`
- the `tools/` directory in this repo added to `PATH`

See `examples/example.lua` for a simple C compiling and linking example.

Every time the working tree changes (new file. deleted file, new included added to a C file, etc.) run the following in this order:
- `lua example.lua` where `example.lua` is your build script
- `ninja clean` (optional) to clean up unused object files from clogging up the disk and causing problems

Then once you only edit code which does not involve adding new dependencies, you can just run `ninja` to build those changes.

In the end, the build script has to be invoked similarly like when you would invoke `./configure`.

# License

See `LICENSE.txt`. You may use this build system in any setting, including personal and commercial uses too.

You may however not do any of the following, or anything which even remotely closely resembles the desribed behavior:
- claim the projects as yours
- misrepresent its source
- sell or otherwise profit off of the project (except where the profit is caused by the use of the unmodified project)
- remove copyright or the license

# Contributing

Contributions are welcome, however contributing does not grant any (neither partial, nor full) ownership over the project.
