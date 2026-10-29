# BobcatBar

A menu-bar launcher for Texas State students: Canvas, CatsWeb, Navigate 360 and the other campus sites one click away, plus your student orgs and the apps you use for class.

## Install

Needs macOS 14 or later, on an Apple silicon or Intel Mac.

1. Download **BobcatBar-x.y.z.zip** from the [latest release](https://github.com/ee-james/BobcatBar/releases/latest).
2. Double-click the zip, then drag **BobcatBar** into your Applications folder.
3. Open it. The Supercat appears in the menu bar; there's no Dock icon.

To have it start when you log in, add it in System Settings → General → Login Items.

The app is signed and notarized by Apple, so it opens without security warnings.

### Building it yourself

Needs the Swift toolchain (Xcode or the command-line tools).

```sh
./build.sh --install      # builds BobcatBar.app and copies it to ~/Applications
open ~/Applications/BobcatBar.app
```

To install somewhere else, put `INSTALL_DIR="/path/to/folder"` in a `build.local` file next to `build.sh` (git ignores it). `./build.sh --release` makes the signed, notarized zip for a release (it needs a Developer ID certificate).

## Settings

Choose **Settings…** (⌘,) from the menu:

- **Checkboxes** turn the built-in campus links and apps on or off.
- **Bobcat Scores** (on by default) shows the latest Texas State result in the menu, e.g. `Bobcat Scores: 🏈 W 20–17 vs Utah State`. Hover it for every result from the past week in football, basketball, volleyball and baseball, live games first, plus the coming week's games. Click a game to open it on ESPN.
- **Orgs** holds your student organizations, each with a link (GroupMe, Instagram, a website). They appear under an "Orgs" heading in the menu.
- **Edit config.json…** opens the file itself (`~/.config/bobcatbar/config.json`) for anything else: your own links, sections with their own headings, a specific browser for a link (`"browser": "Google Chrome"`), or `"sortLinks": false` to keep your order. The menu picks up edits the next time it opens.

A new install starts with Canvas, CatsWeb and Navigate 360 pinned at the top, plus Campus Map, Degree Audit, Financial Aid, Registration and Student Balance.

## Scores

Scores come from ESPN's public schedule data (`site.api.espn.com`), fetched straight from your Mac: every 15 minutes, every minute while a game is live, and when you open the menu with data more than two minutes old. Nothing about you is sent. It's an unofficial feed, so if ESPN changes it the scores line may go quiet until BobcatBar is updated. Turn it off in Settings, or with `"scores": false` in config.json.

## License

MIT. See [LICENSE](LICENSE). The Supercat icon is a Texas State University trademark; it isn't covered by the license.
