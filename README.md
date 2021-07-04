# Ninjamite

Ninjamite is a ninjafile emitter helper which helps you to easily create build scripts in Lua to speed up development process.

# Usage

You'll need the following:
- [https://github.com/ninja-build/ninja](ninja) in your `PATH`
- [https://sourceforge.net/projects/luabinaries/files/5.1.5/Tools%20Executables/](Lua 5.1.5) in your `PATH` aliased as `lua`
- the `tools/` directory in this repo in your `PATH`

See `examples/example.lua` on a simple C compile example.

Every time the working tree changes (new file. deleted file, new included added to a C file, etc.) run the following in this order:
- `lua example.lua` where `example.lua` is your build script
- `ninja clean` (optional) to clean up unused object files from clogging up the disk and causing problems

Then once you only edit code which does not involve adding new dependencies, you can just run `ninja` to build those changes.

# License

See `LICENSE.txt`. You may use this build system in any setting, including personal and commercial uses too.

You may however not do any of the following, or anything which even remotely closely resembles the desribed behavior:
- claim the projects as yours
- misrepresent its source
- sell or otherwise profit off of the project (except where the profit is caused by the use of the unmodified project)
- remove copyright or the license

# Contributing

Contributions are welcome, however contributing does not grant any ownership over the project.
