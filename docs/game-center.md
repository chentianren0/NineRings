# Game Center

Nine Rings has four Game Center achievements. This page says what each one is, how the app decides it is earned, what
can be tried without App Store Connect, and what the user does to turn it on.

## The achievements

The identifier is what the code reports and what Game Center knows the achievement by. It must be entered exactly as
written here, and it can never change once the achievement is live.

| Identifier | Name | Before it is earned | Once it is earned | Points |
|---|---|---|---|---|
| `all_nine_off` | All Nine Off | Take every ring off the sword. | You took all nine rings off the sword. | 20 |
| `shortest_way` | The Shortest Way | From every ring on, take every ring off in 341 moves, with no Undo and no help. | You took every ring off the shortest way: 341 moves. | 40 |
| `all_nine_back_on` | All Nine Back On | From every ring off, put every ring back on. | You put all nine rings back on the sword. | 20 |
| `far_end` | The Far End | Reach the arrangement with only ring 9 on: the far end of the puzzle's one path. | You reached the far end, 511 moves from every ring off. | 20 |

None is hidden, and none can be earned again: each says something about the puzzle, and the locked ones show what
there is to find. Each needs a picture (step 4 below).

## How the app decides

The rules are in the package, in `Session/Achievement.swift`, and its tests are `AchievementTests`. They follow the
person's own toy, as the congratulation does:

- **All Nine Off** is earned at the moment the congratulation is due: a play from every ring on, ended by the
  person's own move. The two share one rule, so they never disagree.
- **All Nine Back On** and **The Far End** are journeys along the puzzle's one path, made by the person's own moves:
  from every ring off to every ring on, and from every ring on or every ring off to only ring 9 on. The journey's last
  move must be made forward and leave the toy resting there. An undo arriving there does not count, and neither do
  Solve or the lesson.
- Resting at a journey's end some other way, such as by Reset, means the journey starts again. Rings set by hand
  start a journey only from its start, so setting the rings next to the far end and moving one ring does not count.
- **The Shortest Way** waits for the record of a finished play (issue 70), which counts undos and moves played for
  the person. Until that lands, nothing earns it. Where that record is written, at the moment the congratulation is
  due, its "shortest way" adds this achievement to what that change earns.

What is earned is kept on the device and reported when a player is signed in: at once, when a player signs in later,
or at the next launch if reporting failed. Each one is reported once, with Apple's banner. The app reads no player
identifier, so an achievement earned with nobody signed in goes to whoever signs in first on that device.

Game Center signs in when the window first appears, as Apple advises. Without a player the app works the same, and
the Game Center menu item is disabled. That is also what happens on a device in Lockdown Mode, where Game Center is
off for every app. That item opens Game Center's dashboard, through `GKAccessPoint`; the floating
access point is never shown. The menu item is at the end of the Puzzle menu. On iPhone and iPad it is also in the
toolbar's More menu.

Debug builds have launch switches for trying it. `-game-center off` leaves Game Center out of a launch: scripted runs
on this Mac use it so as not to earn anything for the person signed in. `-game-center reset` forgets what this device
has earned and reported. `-earn far_end,all_nine_back_on` earns those achievements at launch, so that reporting and the
banner can be tried without hundreds of moves.

## What can be tried without App Store Connect

Since Xcode 16.3 the achievements can live in the project, in a GameKit configuration file. Xcode can push that file
to App Store Connect and pull it back. With the scheme's **GameKit Configuration › Enable Debug Mode** on, Xcode's
**Game Progress Manager** (Debug › GameKit › Manage Game Progress) shows and resets progress on a real device
(iOS 18.4 or macOS 15.4 and later). A Mac counts as one, but not a device in Lockdown Mode, where Game Center is off. Nothing reaches App Store Connect while Debug Mode is on.
The simulator cannot do this.

The file is Xcode's own format: a package that holds the pictures too. Like the String Catalogs, it is written by
Xcode's editor, not by hand.

## What the user does, in order

1. **Sign in to Xcode.** In Xcode › Settings › Accounts, sign in to the account of the team that signs the app. The
   first signed build after the capability lands uses it to turn Game Center on for the App ID
   `com.chentianren.PlayNineRings` and to make the profiles.
2. **The capability.** The Game Center entitlement and the Mac sandbox's two network keys are on their own branch,
   `claude/game-center-capability`. A session builds it once for the Mac and once for iPhone and iPad through Xcode,
   checks Game Center on this Mac, and the branch merges right after, so that `main` never carries an entitlement
   with no profile behind it. Until then the app works as before: Game Center refuses it, the menu item stays
   disabled, and what is earned waits on the device.
3. **Add the achievements in App Store Connect.** In **Apps**, choose Nine Rings, then **Game Center** in the sidebar.
   For each row of the table above, in that order:
   1. In **Achievements**, click **Add Achievement** (or **+** once there is one).
   2. **Reference Name**: the English name. **Achievement ID**: the identifier, exactly as written. It can never be
      changed. Click **Create**.
   3. **Point Value**: from the table. Leave **Hidden** and **Achievable More Than Once** off.
   4. In **Achievement Localization**, click **Add Localization** and choose English. **Display Name**: the name.
      **Pre-earned Description** and **Earned Description**: the two texts. **Image**: the achievement's picture.
      Click **Save**, then **Save** again.

   Once an achievement is live, it can't be deleted and its points can't be changed.
4. **The pictures** are ready in `StoreTools/AchievementPictures/`, one for each achievement, named by its
   identifier: `all_nine_off.png`, `shortest_way.png`, `all_nine_back_on.png` and `far_end.png`. Upload each as its
   achievement's **Image**. They are what App Store Connect asks for: 1024 × 1024 pixels, PNG, RGB, 72 ppi, with no
   transparency. They use the ring buttons' language: a filled disc is a ring that is on, an outline a ring that is off,
   ring 1 on the left, on a bar for the sword; The Shortest Way is one straight arrow from a filled ring to an outline.
   Everything stays well inside the circle Game Center cuts them to. They are drawn by
   `swift run --package-path StoreTools achievement-pictures` (the drawing is
   `StoreTools/Sources/StoreComposer/AchievementPictures.swift`), so a change is made there and they are made again.
5. **Turn Game Center on for the version.** In **Apps**, choose Nine Rings, then the version that will ship this, in
   the sidebar. Scroll down, tick **Game Center**, and add the four achievements to the version. They are reviewed
   with it, and players see them only once they are approved.
6. **Try it on a device that is not in Lockdown Mode**, since Game Center is off there. On iPhone or iPad, sign in to
   Game Center in Settings; on a Mac, in System Settings › Game Center. Run the app from Xcode. Game Center greets you, and Puzzle › Game Center (on iPhone, the toolbar's
   More menu) opens the dashboard, with the achievements marked as prerelease. To see the banners without hundreds of
   moves, run with the arguments `-game-center reset -earn all_nine_off,all_nine_back_on,far_end`. Each banner should
   show once, and a second launch with only `-earn …` shows none. All Nine Off also comes with the congratulation,
   in play.
7. **If you like, keep the achievements in the project too.** In Xcode, File › New › File from Template, then iOS ›
   Other › GameKit Bundle, added to the NineRings target, then **Pull from App Store Connect** from its More (…)
   button. With the scheme's Run › Options › GameKit Configuration › Enable Debug Mode on, Debug › GameKit › Manage
   Game Progress shows and resets progress on a device without touching App Store Connect.
8. **Translations.** The names and texts in French, Japanese and both Chinese scripts are added as further
   localizations of each achievement, with the other new texts (issue 74).

## Privacy

What Apple's pages say, and what follows from them:

- Apple's [App privacy details](https://developer.apple.com/app-store/app-privacy-details/) page says a developer is
  "not responsible for disclosing data collected by Apple". "Collect" there means sending data off the device where
  the developer or their partners can reach it. Game Center is Apple's service, and the app sends nothing to anyone
  else.
- GameKit's "Protecting the player's privacy using scoped identifiers" asks for privacy details in App Store Connect
  only from games that use `teamPlayerID` or the old `playerID`. The app reads no player identifier at all.
- So the App Store's privacy answers stay **Data Not Collected**. The privacy manifest needs no change: the app keeps
  what was earned in its own UserDefaults, which the manifest already declares (reason CA92.1).
- The Mac app keeps its sandbox. Game Center needs the sandbox's incoming and outgoing network connections, as Apple's
  "Initializing and configuring Game Center" says. Those are build settings, next to the entitlement.

What `docs/privacy.md` should say once this ships (issue 74 rewrites it):

- The line "It does not use the network" is no longer true for Game Center. Say instead that the app itself talks to
  no server; with Game Center on, the system's Game Center service sends the achievements you earn to Apple.
- Add a paragraph, in the page's own voice: *If you are signed in to Game Center, the app reports the achievements you
  earn to Game Center, Apple's service, which shows them in your Game Center profile. It sends nothing else, it reads
  no identifier of yours, and nothing reaches us. An achievement earned while you are not signed in waits on your
  device and is reported when you sign in. Apple's privacy policy covers Game Center, and you can sign out of it in
  Settings.*
- Add to what the app keeps on the device: which achievements you have earned, and which Game Center has taken.
