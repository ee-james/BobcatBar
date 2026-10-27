# BobcatBar

A menu-bar launcher for Texas State students: Canvas, CatsWeb, Navigate 360 and the other campus sites one click away, plus your student orgs and the apps you use for class.

## Install

Needs macOS 14 or later and the Swift toolchain (Xcode or the command-line tools).

```sh
./build.sh --install      # builds BobcatBar.app and copies it to ~/Applications
open ~/Applications/BobcatBar.app
```

To install somewhere else, put `INSTALL_DIR="/path/to/folder"` in a `build.local` file next to `build.sh` (git ignores it).

## Settings

Choose **Settings…** (⌘,) from the menu:

- **Checkboxes** turn the built-in campus links and apps on or off.
- **Orgs** holds your student organizations, each with a link (GroupMe, Instagram, a website). They appear under an "Orgs" heading in the menu.
- **Edit config.json…** opens the file itself (`~/.config/bobcatbar/config.json`) for anything else: your own links, sections with their own headings, a specific browser for a link (`"browser": "Google Chrome"`), or `"sortLinks": false` to keep your order. The menu picks up edits the next time it opens.

A new install starts with Canvas, CatsWeb and Navigate 360 pinned at the top, plus Campus Map, Degree Audit, Financial Aid, Registration and Student Balance.
