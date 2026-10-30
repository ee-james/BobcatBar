# BobcatBar

A menu-bar launcher for Texas State students: Canvas, CatsWeb, Navigate 360 and the other campus sites one click away, plus your own links, your student orgs, the apps you use for class, and Bobcat scores.

Questions, ideas or bugs: **bobcatbar@zetsystems.com**, or [open an issue](https://github.com/ee-james/BobcatBar/issues).

## Install

Needs macOS 14 or later, on an Apple silicon or Intel Mac.

1. Download **BobcatBar-x.y.z.zip** from the [latest release](https://github.com/ee-james/BobcatBar/releases/latest).
2. Double-click the zip, then drag **BobcatBar** into your Applications folder.
3. Open it from Applications. The Supercat appears in the menu bar; there's no Dock icon.

It's signed and notarized by Apple, so it opens without security warnings. A new install opens itself at login (turn that off in Settings → General) and keeps itself up to date.

**Have 0.1.0?** It can't update itself. Download the latest release once and replace it; from then on updates are automatic.

## Settings

Choose **Settings…** (⌘,) from the menu.

- **General:** open at login; the menu-bar icon (the Supercat, a paw print, or your own image); updates; About.
- **Campus:** checkboxes for the built-in Texas State links and apps.
- **My Links:** add any site (pin it to keep it at the top) and your student orgs (a GroupMe, Instagram or website link each).
- **Scores:** Bobcat Scores in the menu, and notifications for the sports you follow.

Everything is saved in `~/.config/bobcatbar/config.json`, which you can also edit by hand (**Edit config.json…**): sections with their own headings, a specific browser for a link (`"browser": "Google Chrome"`), or `"sortLinks": false` to keep your order. The menu picks up edits the next time it opens. If the file has a mistake, BobcatBar says so and won't save over it, and every save keeps the previous version as `config.json.bak`.

### Your own menu-bar icon

Settings → General → Menu bar icon → **Your own…** takes any image. A logo with a transparent background works best; it follows the menu bar's light or dark look. An image on a solid background is turned into a shape from its dark parts, or switch on **Keep its colors** to show it as is. The image is copied to `~/.config/bobcatbar/` and never leaves your Mac.

## Scores

The menu shows the latest Texas State result, e.g. `Bobcat Scores: 🏈 W 20–17 vs Utah State`. Hover it for every result from the past week in football, basketball, volleyball and baseball, live games first, plus the coming week's games. Click a game to open it on ESPN.

**Notifications** (Settings → Scores) tell you 30 minutes before a game and give the final score, for the sports you pick. Click one to open the game.

Scores come from ESPN's public schedule data (`site.api.espn.com`): every 15 minutes, every minute while a game is live, and when you open the menu with data more than two minutes old. It's an unofficial feed, so if ESPN changes it the scores line may go quiet until BobcatBar is updated. Turn it off in Settings.

## What BobcatBar connects to

- **ESPN** for scores, if Bobcat Scores is on.
- **GitHub**, once a day, for new versions (`appcast.xml`) and campus link fixes (`catalog.json`). Both can be turned off in Settings → General.

These are plain downloads. BobcatBar doesn't send anything about you, your links or your settings, and has no analytics.

## Contributing

**Report a broken or missing campus link:** open an issue. Link changes are reviewed and approved by the maintainer, and BobcatBar only accepts addresses on Texas State sites and a few approved services built into the app.

**Code:** needs Xcode or the Swift command-line tools.

```sh
swift test                # run the tests
./build.sh --install      # build BobcatBar.app and copy it to ~/Applications (INSTALL_DIR in build.local to change)
```

Builds made this way don't update themselves. `./build.sh --release` makes a signed, notarized release zip and `appcast.xml`; it needs the maintainer's Developer ID certificate and update-signing key.

## License

MIT. See [LICENSE](LICENSE). Not affiliated with Texas State University. The Supercat is a Texas State University trademark and isn't covered by the license.
