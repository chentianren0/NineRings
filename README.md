# Nine rings

An Apple-native app, for iPhone, iPad and Mac, that shows how a Chinese nine linked rings puzzle (also known as the Baguenaudier) works.

## The approach: written motion, played back

Nothing in this app is simulated. The place of every part of the toy is a pure function of three things: the puzzle state, the move being made, and how far through that move it is (its progress, from 0 to 1). The same input always gives the same pose, nothing integrates over time, and a slider can drag a move either way.

- **We write the path of the ring that moves**, as a handful of smooth curves of the progress. Every turn of the ring is about an axis through its eye.
- **Every other part follows by rule.** A rod is a straight line from its eye, which sits on its ring's wire, through the middle of its own hole in the bar; it turns about its own axis so that its eye faces along the wire. The bead is at its lower end.
- **The bar stays still and level.** Rings and rods that the move does not involve stay still too, but for the rings that ride on the sword when it goes down.
- **The sword stays level.** It slides along its own length, and may go down and come up again, carrying with it the rings that ride on it, whose rods slide down and up through the bar. That is how its tip comes to the ring for the lift over it, and moves away again so that there is room for the drop.

The toy is simplified on purpose. It keeps what explains the mechanism (what passes through what, that nothing passes through anything, that a ring leaves the rails only over the tip end, and the stages of a move in the order a person does them) and gives up gravity-true hanging, a swinging bar and the exact lean of each ring.

Every move is written. The toy has two moves, each going back on along the same path backwards:

- **Ring 1**, in six stages: flatten, over the tip, back over the slot, turn, down through the slot, hang. It is the same whatever the rings behind it are; they keep still.
- **The second ring on the sword**, ring k for k from 2 to 9, in five: sword moves away, ring k over the tip, down through the slot, ring k hangs, sword comes back. Going on, they read: sword moves away, ring k lifts, up through the slot, ring k over the tip, sword comes back.

### One move for the second ring on the sword

The rule lets ring k move only when ring k−1 is on and every ring in front of it is off. The rings in front are off, so their rods are out of the slot and the sword can be drawn back past them; then ring k−1 and ring k are the first two rings on the sword, as rings 1 and 2 are when every ring is on. Ring k−1's rod stands in the slot and runs through ring k, and that is what lets ring k go down through the slot. So the move is written once, for ring 2 (`PairMoveOff` in `Motion/PairMove.swift`), and played for ring k one hole further along: the moving ring, the sword's slide and every key.

- **Sword moves away.** The sword slides back toward the grip, over the rings that are off, until its tip is just in front of rod k−1. It dips 3 mm as it nears ring k−1, so that the tip, which rises toward its end, passes under it; once the tip is behind the eye of the ring in front of ring k−1, the sword goes down 20 mm, taking ring k and every ring behind it with it, as one stiff piece. Going down, its tip leaves ring k−1, which is now off the rails without having moved.
- **Ring k over the tip.** Below ring k−1, ring k swings up about its wire through the eye until it lies nearly flat over the tip end. The tip passes out of ring k; rod k−1 still runs down through it.
- **Down through the slot.** The sword slides forward under ring k−1, but only until its tip is 2.4 mm short of where the rod of the ring in front of ring k−1 hangs. Ring k's eye moves back toward the grip by up to 3.3 mm, its rod leaning in its hole, so that the slot in front of the eye is as long as the drop needs; the ring swings to one side, tilts and slips through at a slant, and its eye comes back above its hole.
- **Ring k hangs.** It hangs below the sunk sword, and its eye sinks below the rails last.
- **Sword comes back.** The sword slides back from under ring k−1, comes up, its tip entering ring k−1 again, and slides home over the rings that are off.

What each ring does:

- Every ring in front of ring k, ring k−1 included, keeps exactly still, with its rod. The rings that are off in front do nothing at all.
- Every ring behind ring k, on or off, moves only straight down and up with the sword, by exactly its height. The move asks nothing of them.
- A ring that is off rests the same way wherever it is and whatever its neighbours are: below the sword, its eye just under the rails, leaning toward the tip, its rod down through the next ring whether that ring is on or off. Off rings next to one another lie like parallel plates one hole apart, and ring 9 off rests the same way with nothing to hang from. So every one of the 512 states has its rest.

### How long a move takes

The poses are a function of a move's progress, which the slider drags; the move's timing (`MoveTiming`) says how many seconds it takes at full speed and when it reaches each progress. Ring 1's move and ring 2's take three seconds. For every later ring, the stages in which the ring itself moves keep ring 2's seconds, moment for moment, and the sword's longer slide, one hole further out and home for each ring after ring 2, is covered at 60 mm a second, about ring 2's own pace on its first slide. So each ring after ring 2 adds half a second, and ring 9's move takes six and a half. The speed of every part stays continuous where the added slide meets the ring's own stages. Playing goes by time, at full, half or quarter speed.

### What the geometry forced

With the nominal sizes, a few things are not free choices, and the checker found them:

- A ring that is on has to lean at least about 42.5° for the rod of the ring before it to pass inside its lower arc. The model uses 43°.
- When ring 1 is off, its eye must be wholly below the rails, and that is just inside ring 2's lower arc. Ring 2 then goes round rod 1 at the foot of its eye rather than round the straight shaft, and ring 2's lower arc wraps so closely under the eye that ring 1 can only hang across the sword there.
- So ring 1 cannot drop straight through the slot. Its eye goes down into the slot first; the ring tips over toward the tip, rolls nearly flat and swings from side to side, so that it slips through the slot at a slant, partly over one rail and partly under the other; and only when it hangs across the sword does the eye sink below the rails and the rod leave the slot.
- Ring 1's eye sits 32 mm from the tip's end with the sword at home: any further and rod 9 would meet the rails where they close; any nearer and the slot in front of ring 1 would be too short for the drop.
- Ring k cannot leave the rails while ring k−1 is still on them. As ring k swings up, the places where its disc meets the rails move forward to the tip end, and on the way they would have to pass where ring k−1's disc meets them. There both discs hold the same two points, one on each rail, so both rings cross the line between those points, and each ring's crossing has to reach past both rails: at least 23.7 mm, with the wires and the 0.2 mm gap. Two rings whose discs cross along one line stay unlinked only if one ring's crossing lies inside the other's, with its wire clear at both ends, which needs at least 28.7 mm where a ring is 25.7 mm across. So ring k−1 must be off the rails first, with its rod still in the slot: the sword is drawn back out of it, and goes down so that ring k can pass under it.
- With ring k−1 still and the sword down, the rod of the ring in front of ring k−1 hangs through where the sword's tip would go: it stands 30 mm in front of ring k's eye and reaches down through the bar, so there is at most 27.85 mm of slot in front of the eye. The drop needs 30.5 mm with the eye above its hole. Moving the eye back 3.3 mm gives what the drop needs; moving it back for the whole drop would bring ring k against ring k+1, so it moves back only for the middle of the drop.
- The sword goes down 20 mm. With every ring behind on, the sword and what rides on it could go down 34 mm before anything came within 0.3 mm of the bar; with a ring hanging behind, 26.9 mm, set by the hanging ring's lowest point (`NINE_RINGS_ROOM_BELOW=1` measures it). How little would do for this move was not measured.

## Layout

- `NineRingsKit/`: a Swift package with everything that does not depend on the interface.
  - `Puzzle`: which rings are on, the rule that says which ring can move, and the one path through all 512 states.
  - `Toy`: the toy's nominal dimensions, the sword's shape, and `ToyPose`, the place of every part. `SwordShape` is the one centreline of the sword, bends and grip loops included: the app draws its tube along those points and the checker checks capsules round the same pieces, and a test holds the drawn sword inside the checked one. The toy's frame is fixed to the bar; the sword stays level, and its pose is its slide along its length and its height.
  - `Motion`: the written motion. `Layout` holds the fixed places and the few numbers the motion rests on; `HeldRing` is a ring as its rod holds it, with the rod rule; `RestPoses` places each ring by rule relative to its own hole; `Curve` is a smooth, never-overshooting curve through key values; `RingTurns` is the rule that turns a few angles and the eye's height into where a ring is; `Pacing` maps a move's progress onto its path so the move flows at an even pace; `MoveTiming` gives each move its length in seconds and maps its time to its progress; `RingOneOff` and `PairMoveOff` are the two written moves, ring 1's and the second ring's; `MoveMotion` is the public entry: the pose for a move at a progress, and the move's stages.
  - `Session`: a puzzle being played, with no interface and no clock in it: the state, the moves made, the move on the slider and its progress, the rings waiting their turn, undo, reset and solve, and why a request did not play. The app turns what it reports into words. It also holds the lesson that explains the puzzle (`Lesson`): twelve steps, each with the key of its text and what the toy shows while it is up, a state at rest, moves played, or a move held after a named stage. The steps play the first six moves of the shortest way, each starting where the last ended.
  - `Geometry`: the centrelines of the shapes (circles, straight pieces, the bar's sheet) and the search for where two of them come near. Only the checker uses it.
- `NineRings/` and `NineRings.xcodeproj`: the app, in SwiftUI and RealityKit. The project file is in Xcode's JSON format and `NineRings/` is a synchronized folder, so adding a file there does not change the project file.
  - `Model/Player.swift`: the session as the screen sees it, with a clock to play it and the speed.
  - `Scene`: the toy drawn in 3D, with meshes generated from `Dimensions`; `ToyScene.apply(_:)` places every part for a `ToyPose`; `OrbitCamera` frames a box in the part of the view nothing covers.
  - `Views`: the camera rig, which gestures move and presets fly, and the camera gestures.
  - `Interface`: the screen. `MainScreen` holds the player and the camera; `PuzzleScreen` lays out the toy, the floating controls and the toolbar; `ToyCanvas` is the 3D view, with the tap on a ring; `ControlPanel` and `RingButtons` are the controls; `Sentences` is every sentence the screen says about the puzzle; `Framing` is what the camera frames; `DesignChoices` holds the alternatives a debug build can switch between; `Placeholders` stands in for the lesson and settings until they are built.
  - `Localizable.xcstrings` holds every sentence, for translation. `Stages.xcstrings` holds the stages' names, which the motion code keys in English, with `%lld` where a ring's number goes ("Ring %lld hangs"), and the app looks up and fills in; a stage not listed there shows in English. Xcode adds new sentences to `Localizable.xcstrings` when it builds; a command-line build does not. `Lesson.xcstrings` holds the lesson's texts under stable keys, such as `lesson.rule`, each with a comment saying what the toy shows at that step; a package test checks that every step has its text there.
  - `Capture`: renders the move to image files, in debug builds only (see below).

## Playing the puzzle

The screen is the puzzle itself: the toy in 3D fills the window, and the controls float over it at the bottom, on Liquid Glass.

- **A line** says what is happening: the move and its stage while one plays. When a ring cannot move, the reason shows in a bubble above the controls until the next request.
- **Nine ring buttons**, ring 1 on the left, the tip's side as the toy is first seen. A filled disc is a ring that is on, an outline one that is off. A short bar under it marks a ring that can move now, and an orange outline the ring in the way of the ring just refused. Pressing one, or its number key, asks to move that ring; so does a tap on a ring, its rod or its bead in the 3D view. The row runs left to right in every language, since it mirrors the toy.
- **Undo** (⌘Z), **play or pause** (Space), **the slider** through the move that is playing or was played last, **the speed** (0.25× to 4×) and **solve**. At the slider's right end the move is made, at its left end it is not.
- **The toolbar** has the View menu (the standard view, and the toy from the side, from above and from the tip, ⌘0 to ⌘3), Reset, and the lesson, which opens beside the toy on a wide screen and as a sheet on a phone. Settings are in the toolbar's overflow menu on iPhone and iPad, and in the Settings window on the Mac.

How it behaves:

- A legal move plays, and the state and the buttons change when it ends.
- A move the rule forbids does not play. If a ring before it is on that should be off, the reason names the one nearest: "Ring 5 can’t move while ring 3 is on: ring 3’s rod stands in the slot between ring 5 and the tip." Otherwise the ring just before is off: "Ring 2 can’t move while ring 1 is off: ring 1’s rod runs through ring 2, and that rod is out of the slot, so ring 2 can’t pass through the slot."
- A tap while a move plays, or is stopped part way, waits its turn: the move in hand finishes, then the ring tapped is judged against the state at that point, and plays, or stops with its reason. Several taps queue up in order; the first that cannot play drops the rest.
- Solve plays the shortest way from where the toy is to all rings off, move after move. A tap while solving takes over: the rest of the way is dropped and the ring tapped comes next.
- Play runs the move on the slider forward; undo runs it backward, then the move before, one at a time. Undo drops anything waiting.
- Reset covers the toy for a moment, puts every ring back on and uncovers it.
- The layout follows the window's size, never the device. Where the controls are wide enough, the ring buttons and the rest share one row, so that a wide, short window keeps its height for the toy. The controls keep one height, so the toy, framed above them, never jumps. On a wide screen the room goes to the toy, and the lesson opens beside it. On a half-folded iPhone Duo the system puts the toy on one half and the controls on the other, where they spread out: larger buttons, and the reason a ring cannot move said in the line itself.

The camera frames the rings and the bar, and the sword's tip end, and keeps them clear of the bars and the controls; the picture stays still while moves play. For a later ring the sword is drawn back one hole further for each ring, and its grip leaves the picture for a while, unless the setting to follow the move is on (`settings.followsMove`, off at first; the launch argument `-settings.followsMove YES` turns it on). Then, while a move slides the sword, the camera keeps its direction and moves back and over just enough to keep in view the part of the sword the picture shows at rest; the picture depends on the point of the move alone, and at rest it is the still picture. It works the same from any view the person or the lesson has set, and in the toy's half of a half-folded iPhone Duo. A tall window shows the toy three-quarter from above, so that the long toy is seen larger with ring 1 still on the left; a wide one shows it from the side. When the window changes between the two, as when a phone turns, the camera flies to the other angle, until a gesture or the View menu has moved it.

For the owner's review, a debug build has a Design menu (the ladybug in the toolbar) that changes the first view in a tall window as the app runs: three-quarter from above, the standard, or from the side, or along the toy from above. A launch argument sets it too: `-design.tallView side` or `along`.

## The checker

The package's tests sample each written move at 4000 progress values in each direction and check, at every sample:

- any two parts not joined by design keep at least 0.2 mm between their surfaces. Joined by design means only a ring and the eye that holds it, and a rod's shaft and the bar, which the rod rule below measures instead. Parts that rest against each other, such as a bead under the bar, are drawn 0.25 mm apart;
- no point of any part moves more than 0.25 mm from one sample to the next;
- ring k (k ≥ 2) has rod k−1 through it and no other rod; no two rings are linked; each eye is linked with its own ring and no other, and the ring's wire runs through the eye without cutting through it; each rod's shaft runs through its own hole without cutting into the hole's wall or rims, at any tilt, though it may touch them, since it slides there; each bead stays below the bar; the bar never moves;
- a ring goes round both rails or neither; every ring that is on goes round them, but the ring that moves and, in the second ring's move, ring k−1, which the sword leaves and comes back into; every other ring that is off goes round neither, in front of the moving ring or behind it, so that no move can hide another; and any ring, from one sample to the next, leaves or joins the rails only over the tip's end: where it goes round them, the sword goes through it nowhere but near the tip's end. Each side of the sword's centreline has two ends: the tip's end, where the sides meet, and the end of its grip loop, which lies inside the side's own wire, so that a ring cannot pass over it without meeting the wire;
- in ring 1's move every other ring keeps still; in the second ring's move every ring in front of ring k keeps still and every ring behind it moves only with the sword, by exactly its height (this, and that no other ring gets onto the rails or leaves them, is also checked for every one of the 511 moves, both ways, at 801 progress values, on every run);
- the two ends of the move are the two rest poses, and going on is coming off backwards;
- the stages come in order and each does what its name says;
- position and velocity are continuous, the move starts and ends at rest, and it does not stop between stages.

A pose takes well under a microsecond to compute in an optimized build.

Every pose of every move, both ways at 801 progress values, and the rest pose of every state are also held to a fingerprint written in the tests (`MotionFingerprintTests`): a hash of their exact bits. A change to the code that should leave the motion alone leaves it alone; a change meant to change the motion changes the value there with it. `NINE_RINGS_FINGERPRINT_OUT=<file>` writes the line for each move and rest, to find which differ.

Some tests are tools rather than checks, and run only when asked: `NINE_RINGS_PROFILE=1` (or `=2` for ring 2) prints the smallest gap and the fastest-moving part through the move; `NINE_RINGS_PAIR_TUNE=1` searches the key values of the second ring's drop for the path with the most room (`PairMoveTuneTests`, beside the search tools), and `NINE_RINGS_SEARCH=1` does the same for ring 1's drop. The key values in `RingOneOff` and `PairMoveOff` came from such searches, and are written there as plain numbers.

The second ring's move is checked in full for ring 3 with ring 1 off, for ring 2 and for ring 9, for ring 3 with the rings behind on, off and mixed, for ring 2 with ring 3 off behind, and ring 1's for ring 1 with ring 2 off behind; every one of the 512 states is checked at rest. `NINE_RINGS_PAIR=1` sweeps the second ring's move for the cases `NINE_RINGS_CASES` lists and prints where it is tightest, and `NINE_RINGS_EVERY_MOVE=1` runs every one of the 511 moves through the checker, both ways, which takes about an hour on the Mac the project is developed on and is best run on GitHub as five copies (`-f filter=EveryMoveTests -f environment="NINE_RINGS_EVERY_MOVE=1" -f copies=5`).

## Building and testing

Run the package's tests, optimized (they also pass unoptimized, but take minutes rather than seconds):

```bash
swift test --package-path NineRingsKit -c release -Xswiftc -enable-testing
```

Open `NineRings.xcodeproj` in Xcode 27.2 or later and run the `NineRings` scheme on My Mac.

To compile from the command line without signing, for the Mac:

```bash
xcodebuild -project NineRings.xcodeproj -scheme NineRings -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

And for iPhone and iPad:

```bash
xcodebuild -project NineRings.xcodeproj -scheme NineRings -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
```

The app is built with pointer authentication. `NineRings.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings` makes Xcode build the package the same way.

To open the app where ring k first comes off on the way from every ring on to every ring off, with that move on the slider, launch it with `-move k`, such as `-move 3`; to open it part way through the move, with `-start-progress 0.5`. Space plays or pauses, ⌘Z undoes, the keys 1 to 9 tap the rings, ⌘0 shows the standard view, and ⌘1, ⌘2 and ⌘3 show the toy from the side, from above and from the tip.

## Writing a new kind of move with the search tools

`NineRingsKit/Tests/MotionTests/Search` holds tools for finding a move's key values. They change nothing in the app or in the written motion: a session uses them, then writes the keys they print into the move's path as plain numbers, and the checker judges that path as it judges every other.

- `FastRoom` measures one pose as the checker does, the smallest gap and the relations, but only for the pairs that can change in a move, and skips any pair whose cheap lower bound is already too far apart to matter. A test holds it to the checker's numbers on every run.
- `Tuner` searches a move's free key values for the path with the most room, with CMA-ES: a population of candidates drawn round a middle that moves toward the best, whose spread learns which numbers to change together.
- `Planner` finds a way between two poses of the moving parts that keeps a given room, with RRT-Connect, in the very numbers the move's curves write (for a drop: tip, tilt, swing and eye height). `CurveFit` turns the way it finds into curve keys.
- `FullCheck` runs the checker's own tests on a path given as keys: 4000 samples paced as the app paces them.

To write a new kind of move:

1. Describe the moving parts as a `ConfigSpace`: which numbers, their ranges, which part each belongs to, and a pose for each point, built with the same rules as the move will use (`RingTurns`, the rod rule, a hanging chain). Its `FastRoom` names the rings that move, whether the sword moves, and which rings may leave the rails.
2. Plan between the poses the stages begin and end at with `Planner.plan`, one leg per stage, asking for the most room first (0.4 mm, then less). In each leg it first holds still every part that is the same at both ends, and frees them only if no way is found so; that keeps a part the stage does not involve from wandering. If no room at all gives a way, the planner's failing room and the tightest pairs say where the move is blocked.
3. Fit the legs with `CurveFit.keys(legs:)`, make a move for the tuner with `ConfigSpace.keyedMove`, and run `Tuner.run`; it prints each better path as it finds it and ends with keys as Swift source. Check the curves by eye too: the tuner widens the room, and does not make the move calmer.
4. Write those keys into the move's path, and let the package's tests judge it.

`NINE_RINGS_PLAN=1` runs all of this for ring 1's drop from its two ends; `NINE_RINGS_SEARCH=1` (or `2`) runs the tuner alone on ring 1's drop (the second ring's drop, for ring 2) from a first guess; `NINE_RINGS_MEASURE=1` times the pieces. Each ends by finding a move we know again, which is how the tools prove themselves: from the rounded keys, the tuner finds the second ring's drop again with 0.40 mm of room in about 5 seconds, and the checker's full tests pass it. The seed is `NINE_RINGS_SEED`, or the copy's number on GitHub, and `NINE_RINGS_KEYS_OUT` (on GitHub, `tool-output/search-keys-<copy>.txt`) receives the best keys as they improve.

At home or on GitHub: compared with the Mac the project is developed on, one machine there is about three times slower on one core and about five times slower on a path score, which uses every core, and each copy spends half a minute building first. So a run that takes a few minutes at home, such as finding ring 1 or ring 2 again, stays at home. GitHub pays for several seeds of one search at once (each copy's planner and tuner start differently), or for a search that would take more than about twenty minutes at home.

## Checks on GitHub

A pull request that touches the package, the app or the project runs the package's tests and builds the app for the Mac and for iPhone and iPad (`.github/workflows/checks.yml`), on the Xcode the project is developed with. The same checks run again on `main` after each merge, because two pull requests that each pass alone can still fail together. They can also be started by hand from the Actions tab.

### Running a tool on GitHub

The tools that run only when asked, the searches and scans, can also run on GitHub's machines (`.github/workflows/tools.yml`), so that a long one does not keep a Mac busy and several can run side by side. It is started by hand, on any branch that has been pushed:

```
gh workflow run tools.yml --ref <branch> -f filter=RingSearchTests -f environment="NINE_RINGS_SEARCH=2" -f copies=3 -f minutes=120
```

- `filter` is the test to run, as for `swift test --filter`. `environment` is the tool's variables, as `NINE_RINGS_NAME=value` pairs separated by spaces.
- `copies` runs up to five side by side. Each copy gets `NINE_RINGS_COPY` set to its number and `NINE_RINGS_COPIES` to how many there are, so that a tool can start each from a different place.
- `minutes` stops the tool after that long, at most 340. A tool that may be stopped should write what it has found to a file in `tool-output/` as it goes, since the end of what it prints can be lost.
- What each copy printed, and everything in `tool-output/`, is kept with the run: `gh run watch` waits for it and `gh run download` fetches it.

One of these machines has 3 cores, and the full tests take about three times as long there as on an idle Mac. So a single short run is quicker at home. Running there pays for a tool that takes more than about twenty minutes, or for several variants at once.

## Seeing the app

A debug build of the Mac app can draw the move to PNG files without opening a window, so an agent can look at what the app renders. Each frame is posed exactly as the slider poses it: the app's own player is set to the progress, and the app's scene draws the pose it gives, framed as the app frames it.

Build without signing into `scratch/build` (the `scratch/` folder is ignored by git), then launch the app's binary with capture arguments:

```bash
xcodebuild -project NineRings.xcodeproj -scheme NineRings -destination 'platform=macOS' -derivedDataPath scratch/build build CODE_SIGNING_ALLOWED=NO
```

```bash
scratch/build/Build/Products/Debug/NineRings.app/Contents/MacOS/NineRings -capture-frames 16 -capture-views side,top,tip -capture-sheet -capture-dir "$PWD/scratch/captures"
```

It writes one image per progress value and view, named `ring<n>-p<progress>-<view>-<appearance>.png`, prints each path and quits.

- `-capture-move 3`: ring 3's move from where it first comes off, rather than ring 1's; any ring from 1 to 9.
- `-capture-frames 16`: that many frames evenly across the move, from every ring on (0) to its ring off (1). Or `-capture-progress 0,0.25,0.5` for given progress values.
- `-capture-views`: `side`, `top` and `tip` are the app's camera presets; `yaw:pitch` in degrees, as `25:18`, looks from any other direction.
- `-capture-sheet`: also lays out the frames of each view on one contact sheet, `ring<n>-sheet-<view>-<appearance>.png`, each frame labelled with its progress and stage.
- `-capture-focus x,y,z,size`: frames a cube of `size` millimetres around a point in the toy's frame instead of the whole move; `24,-8,0,62` shows ring 1 close up, and `36,0,0,62` rings 1 and 2.
- `-capture-size 1600x1000`: the image size in pixels.
- `-capture-appearance dark`: the dark background.

An unsigned build is not sandboxed, so it can write into the repository. A signed build is, and should be given a folder inside its container, or no `-capture-dir` for its temporary folder.
