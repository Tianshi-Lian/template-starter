WELCOME.

The concepts in this template are ideas I've been working with and tweaking for the last 5 years of trying to program a game without using an engine.

These days, I've landed on Odin + Sokol as the core tech. With a bunch of concepts added on top to make life easier.

## About
All the files marked with `core_` are designed to be updated, I'll push updates as needed.

The reason I've done this instead of making a standalone package that you interface with, is because games are really complicated.

Trying to make things "reusable" often leads to work that isn't really productive. Making things as generic as possible goes against the whole benefit of programming at the low level in the first place.

Take what you need, make it your own, and ship fast.

### What this is great for:
- arcade games & game jams
- a small to medium size singleplayer Steam game

This is more or less the structure I used to make [ARCANA](https://store.steampowered.com/app/2571560/ARCANA/) btw.

There are more advanced concepts you can attach, like a fixed update timestep & a growing entity arena. But honestly, I don't think it's worth the complexity unless you first observe you absolutely need it via playtesting.

## Building
1. [install Odin](https://odin-lang.org/docs/install/) if you haven't already
2. call `build.bat`
3. check `build/windows_debug`

note, it's currently windows-only. But it can be modified pretty easily to target linux or osx if needed. Feel free to PR if you get it working.

## Running
Needs to run from the root directory since it's accessing /res. (in future it'll also have `.dll`s that it needs)

I'd recommend setting up the [RAD Debugger](https://github.com/EpicGamesExt/raddebugger) for a great running & debugging experience. I always launch my game directly from there so it's easier to catch bugs on the fly.

## FAQ
### Why Odin?
Compared to C, it's a lot more fun to work in. Less overall typing, more safety by default, and great quality of life. Happy programming = more gameplay.

Compared to Jai, it has more users and is public (Jai is still in a closed beta). So that means more stability and a better ecosystem around packages, tooling etc, (because more people use it).

### Why Sokol?
Compared to Raylib:

I initially tried using Raylib for this template, it was going well... Right up until the point where I needed to do a specific shader effect on a single sprite. At that point, I would have had to do something hacky to single out the vertices in the shader, or just use the lower level RLGL to basically just write a custom renderer so I could modify the verts and have more power with the shaders.

... at that point, Sokol just becomes a way better option because it lets you do native targets like DirectX11 and Metal with a simple abstraction.
