# Nine rings

An Apple-native app, for iPhone, iPad and Mac, that shows how a Chinese nine linked rings puzzle (also known as the Baguenaudier) works.

## The approach: written motion, played back

Nothing in this app is simulated. The place of every part of the toy is a pure function of three things: the puzzle state, the move being made, and how far through that move it is (its progress, from 0 to 1). The same input always gives the same pose, nothing integrates over time, and a slider can drag a move either way.

- **We write the path of the ring that moves**, as a handful of smooth curves of the progress. Every turn of the ring is about an axis through its eye.
- **Every other part follows by rule.** A rod is a straight line from its eye, which sits on its ring's wire, through the middle of its own hole in the bar; it turns about its own axis so that its eye faces along the wire. The bead is at its lower end.
- **The bar stays still and level.** Rings and rods that the move does not involve stay still too.
- **The sword stays level and slides along its own length.** That is how its tip comes to the ring for the lift over it, and moves away again so that there is enough slot in front of the ring for its drop.

The toy is simplified on purpose. It keeps what explains the mechanism (what passes through what, that nothing passes through anything, that a ring leaves the rails only over the tip end, and the stages of a move in the order a person does them) and gives up gravity-true hanging, a swinging bar and the exact lean of each ring.

So far ring 1 is written: it comes off with every other ring on, in six stages (flatten, over the tip, back over the slot, turn, down through the slot, hang), and goes back on along the same path backwards. Other states and moves come later; the code is shaped for them but does not fake them.

### What the geometry forced

With the nominal sizes, a few things are not free choices, and the checker found them:

- A ring that is on has to lean at least about 42.5° for the rod of the ring before it to pass inside its lower arc. The model uses 43°.
- When ring 1 is off, its eye must be wholly below the rails, and that is just inside ring 2's lower arc. Ring 2 then goes round rod 1 at the foot of its eye rather than round the straight shaft, and ring 2's lower arc wraps so closely under the eye that ring 1 can only hang across the sword there.
- So ring 1 cannot drop straight through the slot. Its eye goes down into the slot first; the ring tips over toward the tip, rolls nearly flat and swings from side to side, so that it slips through the slot at a slant, partly over one rail and partly under the other; and only when it hangs across the sword does the eye sink below the rails and the rod leave the slot.
- Ring 1's eye sits 32 mm from the tip's end with the sword at home: any further and rod 9 would meet the rails where they close; any nearer and the slot in front of ring 1 would be too short for the drop.

## Layout

- `NineRingsKit/`: a Swift package with everything that does not depend on the interface.
  - `Puzzle`: which rings are on, the rule that says which ring can move, and the one path through all 512 states.
  - `Toy`: the toy's nominal dimensions, the sword's shape, and `ToyPose`, the place of every part. The toy's frame is fixed to the bar; the sword's pose is its slide along its length.
  - `Motion`: the written motion. `Layout` holds the fixed places and the few numbers the motion rests on; `HeldRing` is a ring as its rod holds it, with the rod rule; `RestPoses` places each ring by rule relative to its own hole; `Curve` is a smooth, never-overshooting curve through key values; `RingOneOff` is ring 1's path and its timing; `MoveMotion` is the public entry: the pose for a move at a progress, and the move's stages.
  - `Geometry`: the centrelines of the shapes (circles, straight pieces, the bar's sheet) and the search for where two of them come near. Only the checker uses it.
- `NineRings/` and `NineRings.xcodeproj`: the app, in SwiftUI and RealityKit. The project file is in Xcode's JSON format and `NineRings/` is a synchronized folder, so adding a file there does not change the project file.
  - `Model/Player.swift`: the move, its progress, playing and the speed.
  - `Scene`: the toy drawn in 3D, with meshes generated from `Dimensions`; `ToyScene.apply(_:)` places every part for a `ToyPose`.
  - `Views`: the 3D view with its orbit camera, and the controls: play or pause, full, half or quarter speed, and a scrubber with the stages marked and named. The layout follows the size of the window, never the device: the top row stacks when narrow, and stage names give way to stage numbers.
  - `Capture`: renders the move to image files, in debug builds only (see below).

## The checker

The package's tests sample ring 1's move at 4000 progress values in each direction and check, at every sample:

- any two parts not joined by design keep at least 0.2 mm between their surfaces. Joined by design means only a ring and the eye that holds it, and a rod and the bar at its own hole. Parts that rest against each other, such as a bead under the bar, are drawn 0.25 mm apart;
- no point of any part moves more than 0.25 mm from one sample to the next;
- ring k (k ≥ 2) has rod k−1 through it and no other rod; no two rings are linked; each eye is linked with its own ring and no other, and the ring's wire runs through the eye without cutting through it; each rod runs through its own hole; each bead stays below the bar; the bar never moves;
- a ring goes round both rails or neither, and ring 1 leaves them only over the tip's end;
- the two ends of the move are the two rest poses, and going on is coming off backwards;
- the stages come in order and each does what its name says;
- position and velocity are continuous, the move starts and ends at rest, and it does not stop between stages.

A pose takes well under a microsecond to compute in an optimized build.

Three tests are tools rather than checks, and run only when asked: `NINE_RINGS_PROFILE=1` prints the smallest gap and the fastest-moving part through the move; `NINE_RINGS_EXPLORE=1` maps where ring 1 can be with its eye at each height and searches that map for a way down; `NINE_RINGS_TUNE=1` searches the key values of the drop for the path with the most room. The drop's key values in `RingOneOff` came from the last of these, and are written there as plain numbers.

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

To open the app part way through the move, launch it with `-start-progress 0.5`. Space plays or pauses; ⌘1, ⌘2 and ⌘3 show the toy from the side, from above and from the tip.

## Checks on GitHub

A pull request that touches the package, the app or the project runs the package's tests and builds the app for the Mac and for iPhone and iPad (`.github/workflows/checks.yml`), on the Xcode the project is developed with. It can also be started by hand from the Actions tab.

## Seeing the app

A debug build of the Mac app can draw the move to PNG files without opening a window, so an agent can look at what the app renders. Each frame is posed exactly as the slider poses it: the app's own player is set to the progress, and the app's scene draws the pose it gives, framed as the app frames it.

Build without signing into `scratch/build` (the `scratch/` folder is ignored by git), then launch the app's binary with capture arguments:

```bash
xcodebuild -project NineRings.xcodeproj -scheme NineRings -destination 'platform=macOS' -derivedDataPath scratch/build build CODE_SIGNING_ALLOWED=NO
```

```bash
scratch/build/Build/Products/Debug/NineRings.app/Contents/MacOS/NineRings -capture-frames 16 -capture-views side,top,tip -capture-sheet -capture-dir "$PWD/scratch/captures"
```

It writes one image per progress value and view, named `ring1-p<progress>-<view>-<appearance>.png`, prints each path and quits.

- `-capture-frames 16`: that many frames evenly across the move, from every ring on (0) to ring 1 off (1). Or `-capture-progress 0,0.25,0.5` for given progress values.
- `-capture-views`: `side`, `top` and `tip` are the app's camera presets; `yaw:pitch` in degrees, as `25:18`, looks from any other direction.
- `-capture-sheet`: also lays out the frames of each view on one contact sheet, `sheet-<view>-<appearance>.png`, each frame labelled with its progress and stage.
- `-capture-focus x,y,z,size`: frames a cube of `size` millimetres around a point in the toy's frame instead of the whole move; `24,-8,0,62` shows ring 1 close up.
- `-capture-size 1600x1000`: the image size in pixels.
- `-capture-appearance dark`: the dark background.

An unsigned build is not sandboxed, so it can write into the repository. A signed build is, and should be given a folder inside its container, or no `-capture-dir` for its temporary folder.
