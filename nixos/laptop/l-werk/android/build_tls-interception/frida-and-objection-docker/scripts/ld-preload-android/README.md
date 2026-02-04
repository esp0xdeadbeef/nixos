# Android LD_PRELOAD (Zygote wrap)

This technique uses Android's `wrap.<package>` mechanism to inject a shared
library into a target app at Zygote spawn time via `LD_PRELOAD`.

## Important constraints

This only works if:

- The process loads native code (dynamic linker is involved)
- You have:
  - root on emulator, or
  - a debuggable build, or
  - Magisk / Zygisk / similar
- SELinux is permissive or allows `wrap.*`

This **will NOT work** for:

- Fully Java-only apps (no native linker involvement)
- Non-debuggable apps on stock non-rooted devices
- System services protected by SELinux domains

## What this actually hooks

You are not hooking `am`.  
You are wrapping the **zygote-spawned app process** itself:


