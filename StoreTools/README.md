# Store tools: the App Store pictures, made with one command

```bash
scripts/store-assets.sh
```

builds the Mac app (debug, unsigned), launches it once per moment of the series in the store-capture mode, captures its
window, composes each store picture at Apple's exact size, checks it, and renders the product page header. Pictures go to
`scratch/store/out/` in the main checkout: `<language>/<device>/01.png` to `06.png`, and `header/header-light.png` and
`header-dark.png`. It runs in about two minutes. After any change to the interface, run it again. `--help` lists the
options: languages, captions on or off, a bezel, light or dark for all, another folder, compose again without capturing.

The Mac's pictures come from the app's own window. The iPhone, iPad and iPhone Duo pictures come from the `StoreShots`
UI tests on each simulator (`--devices iphone-6.3,ipad-13,…`); see `StoreShots.md`. The preview videos come from
`scripts/store-preview.sh`, also described there.

## The parts

| Part | Where | What it does |
|---|---|---|
| Store-capture mode | `NineRings/Store/` (debug builds only) | `-store-capture` and the options in `StoreLaunch.swift` set the app up for one picture, hold it, and say when it is ready |
| The series | `Shots.json` | The six moments, in order, each with its launch arguments, caption key and appearance; the devices and their store sizes; the header |
| Captions | `Captions.xcstrings` | The captions' texts, a String Catalog for the translators, outside the app so it does not ship |
| Composer | `Sources/StoreComposer`, `Sources/store-compose` | Draws each picture (background, caption, capture, optional bezel), removes transparency, refuses wrong sizes, checks the result |
| The script | `scripts/store-assets.sh` | Runs it all |
| Achievement pictures | `Sources/AchievementPictures`, `Sources/achievement-pictures`, `AchievementPictures/` | Draws the four Game Center achievement pictures in the Bauhaus style, All Nine Off and The Far End in `Bauhaus.swift`, The Shortest Way and All Nine Back On in `ShortestWayAndBackOn.swift`: `swift run --package-path StoreTools achievement-pictures` |

Nothing here is part of the app: the Xcode project does not refer to this package. The tests check the composer, the
app's own reading of the launch arguments (its files are linked into `Sources/StoreLaunch`), and that every moment is a
state the rules allow:

```bash
swift test --package-path StoreTools
```

## The store-capture mode

`-store-capture` with, for a moment: `-state 000111111`, `-move 5`, `-start-progress 0.55`, `-refuse 5`,
`-lesson-step 7 -paused`, `-congratulation`, `-view side|top|tip|yaw:pitch`, and on the Mac `-window-size 1280x800`.
The mode keeps the welcome page away, makes no sound, takes the release build's design choices, hides the debug Design
menu, and prints `store-capture: ready window <number>` once the toy has been drawn and nothing has moved for 1.5 s; a UI
test waits for the element `store-capture-ready`. All for its own process only: nothing is written to stored settings.
Put the options without a value last.

On the Mac the window is made exactly the size asked for even on a screen too small to show it whole, and
`screencapture -l` captures all of it. The window is drawn as the window in front, although it is launched behind.

## Choices the composer leaves open

- **Captions**: `--caption on|off`. On, a caption is one line in a band across the top, never over the app; a long one
  gets smaller, then takes two lines. The type is the system font, semibold.
- **Bezels**: `--bezel bezel.json`, none by default. Apple allows only its own bezels, unmodified (Apple Design
  Resources). None is kept here. Describe one as `{"image": "frame.png", "screen": [x, y, width, height],
  "screenCornerRadius": r}`, the image's path relative to the JSON file and the screen's rectangle in its pixels.
- **Light or dark**: `--appearance plan` takes each moment's own (moment 5 dark, the rest light); `light` or `dark`
  takes one for all.

## For translators

The captions are in `Captions.xcstrings`, each with a comment that says where it shows. Three use the welcome page's
words, and say so. `store-compose captions --captions StoreTools/Captions.xcstrings --languages fr,ja` lists what a
language still lacks. A missing caption falls back to English, as the store does.
