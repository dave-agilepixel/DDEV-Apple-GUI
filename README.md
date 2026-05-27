# DDEVUI

A native macOS app that puts a friendlier visual front-end on [DDEV](https://ddev.com/). Built in Swift and SwiftUI.

## What this actually is

A fun side project. I'm using it as an excuse to learn Swift and SwiftUI, and to make my day-to-day DDEV juggling a bit nicer to look at than a terminal full of `ddev list` output.

That's it. It is not a polished product. It is not officially affiliated with DDEV. There is no roadmap, no support contract, no SLA, no release schedule.

## Can I use it?

Yes — anyone is welcome to. **You use it entirely at your own risk.** It manages local development projects, but it can still shell out to `ddev`, start and stop containers, and touch your project state. If it breaks something, that's on you. Back up anything you care about.

## Requirements

- macOS (see `Package.swift` for the current minimum)
- A working [DDEV](https://ddev.com/) install on your `PATH`
- Xcode if you want to build it yourself

## Building

Open `DDEVUI.xcodeproj` in Xcode and hit Run, or build the SwiftPM target:

```bash
swift build -c release
```

## Feedback

Feedback is welcome — open an issue, tell me what's broken, tell me what would make it nicer. **I don't promise to implement anything.** This is a learning project I work on when I feel like it, so PRs and suggestions may sit untouched for a long time, or forever. No hard feelings either way.

## Forks

Fork it, rip it apart, take it in a different direction — go for it. If you build something cool on top of it, I'd love to hear about it, but you're under no obligation to tell me.

## License

See [LICENSE](LICENSE) if present, otherwise treat this as "use at your own risk, no warranty of any kind."
