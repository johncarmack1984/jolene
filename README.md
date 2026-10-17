# Jolene

Jolene puts your apps' Dock badges in the menu bar, so you still see new messages with the Dock hidden or a window in full screen.

Why not just use Doll? It's done this since 2022, but it hasn't changed since December 2023, and macOS has. On Tahoe it cuts off two-digit counts. Its items jump around, which drops them into the hidden section of menu bar managers like Hidden Bar. It finds apps by the name on their Dock icon, so Messages goes missing on a Swedish Mac ("Meddelanden") and Outlook has to be added again after updates. And it reads badges by scraping the Dock through the Accessibility API, which means granting that permission again after every reinstall.

Jolene is a new app, not a fork. Doll has no license, so none of its code is here; its issue tracker was the spec.

## How it works

macOS keeps each running app's badge in LaunchServices, under a key called `StatusLabel`. Jolene reads that key directly and matches apps by bundle identifier, so names and languages don't matter. A read takes about 30 microseconds and needs no permission: nothing to approve in Privacy & Security.

macOS doesn't tell other apps when a badge changes, so Jolene checks: once a second while one of your apps is open, every ten seconds while none is, and not at all while the displays sleep.

## What it does

- One menu bar item per app, or a single Jolene item showing which apps have something new and their total (good for a crowded or notched menu bar).
- A red badge like the Dock's, the number in the menu bar's own text color, a red dot, or just the icon, which can dim when there's nothing new.
- The app's own icon, that icon in gray, or an SF Symbol that matches the rest of the menu bar.
- Show each app always, only while it's open, or only when it has a badge. Items are hidden in place rather than removed, so they come back where you put them.
- Click an item to open the app or bring it forward, and again to hide it. Right-click or Option-click for its menu.
- If Doll was set up on this Mac, Jolene offers to bring over its apps and settings.

## Limits

- Running apps only. LaunchServices holds badges for open apps, so a badge the Dock shows on a closed app's icon is invisible to Jolene.
- `StatusLabel` and the function that reads it are private API, which also rules out the Mac App Store. If a macOS release drops them, Jolene falls back to the slower `lsappinfo` tool, and CI should catch it first: the tests set a badge and read it back on the newest macOS every week.
- If an app's badges are off in Notifications settings, the Dock shows nothing and neither does Jolene. Each app's page in Jolene has a button that opens Notifications settings.

## Installing

Download the disk image from the [latest release](https://github.com/johncarmack1984/jolene/releases/latest) and open Jolene from it. It offers to move itself into `~/Applications`, the Applications folder in your home folder. Installing there needs no administrator password, and neither do updates, so it works on a work Mac where you aren't an admin. Dragging it onto the Applications shortcut in the disk image puts it in the main Applications folder instead, which does need one. It runs on macOS 14 or later, and it's signed and notarized by Apple.

From then on, Jolene updates itself. Once a day it checks for a new version, installs it in the background and relaunches, with your items back where they were. If you'd rather be asked first, or check by hand, there's a switch for each under Updates in its settings.

## Building

Jolene builds with Xcode 26 or later. Its one dependency is Sparkle, which handles updates, and Xcode fetches it on the first build.

```sh
just run      # build and open Jolene
just test     # run the tests
just release  # Developer ID build; set NOTARY_PROFILE to notarize it
```

`just badge 12` opens BadgeProbe, a small app that shows whatever Dock badge you give it, so you can try Jolene without waiting for email. `just badge` clears it.

CI runs the tests on macOS 26 and macOS 27 for every push and every Monday.

Releases come from release-please. Commit messages on main follow Conventional Commits (`feat:`, `fix:`), and release-please keeps a pull request open with the next version and its changelog. Merging it tags the release, and a workflow builds Jolene, has Apple notarize it, and attaches it to the release along with the feed installed copies check for updates.

## License

MIT
