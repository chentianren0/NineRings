# Nine rings

An Apple-native app, for iPhone, iPad and Mac, that shows how a Chinese nine linked rings puzzle (also known as the Baguenaudier) works.

## The approach: written motion, played back

Nothing in this app is simulated. The place of every part of the toy is a pure function of three things: the puzzle state, the move being made, and how far through that move it is (its progress, from 0 to 1). The same input always gives the same pose, nothing integrates over time, and a slider can drag a move either way.

- **We write the path of the ring that moves**, as a handful of smooth curves of the progress. Every turn of the ring is about an axis through its eye.
- **Every other part follows by rule.** A rod is a straight line from its eye, which sits on its ring's wire, through the middle of its own hole in the bar; it turns about its own axis so that its eye faces along the wire. The bead is at its lower end.
- **The bar stays still and level.** Rings and rods that the move does not involve stay still too.
- **The sword stays level and slides along its own length.** That is how its tip comes to the ring for the lift over it, and moves away again so that there is enough slot in front of the ring for its drop.

The toy is simplified on purpose. It keeps what explains the mechanism (what passes through what, that nothing passes through anything, that a ring leaves the rails only over the tip end, and the stages of a move in the order a person does them) and gives up gravity-true hanging, a swinging bar and the exact lean of each ring.

So far two moves are written, each coming off with every other ring on and going back on along the same path backwards:

- **Ring 1**, in six stages: flatten, over the tip, back over the slot, turn, down through the slot, hang.
- **Ring 2**, in five: ring 1 steps aside, ring 2 over the tip, down through the slot, ring 2 hangs, ring 1 back on. Going on, they read: ring 1 steps aside, ring 2 lifts, up through the slot, ring 2 over the tip, ring 1 back on.

Other states and moves come later; the code is shaped for them but does not fake them.

### How ring 2 comes off

Ring 2 can leave the rails only over the tip end, and ring 1, which is on, is in the way. Rod 1 runs down through ring 2 the whole time, and that is what lets ring 2 go down through the slot: rod 1 is in the slot too.

- **Ring 1 steps aside.** The sword is drawn back toward the grip while ring 1 lifts about its eye, and the tip passes out of ring 1: ring 1 is off the rails without its eye moving. It stands up on its eye and turns to stand along the sword, above the slot.
- **Ring 2 over the tip.** The sword goes on back until its tip is just short of rod 1, and ring 2 swings up about its wire through the eye until it lies nearly flat over the tip end. The tip passes out of ring 2. Rod 1 still runs down through it, just under eye 1.
- **Down through the slot.** The sword slides back toward the tip, under ring 2, to give ring 2 as much slot in front of it as ring 1 had for its own drop. Ring 2 swings to one side and tilts, so that its lower side goes down inside the slot. Then it slips through at a slant, partly over one rail and partly under the other, the way ring 1 does.
- **Ring 2 hangs.** It comes to hang across the sword in front of ring 3's lower arc, and its eye sinks below the rails last, just as ring 1's does in front of ring 2.
- **Ring 1 back on.** Ring 1 turns back and lies down over the tip as the sword goes home.

Ring 2 off rests exactly as ring 1 off does, one hole further on, with ring 1 on in front of it and rod 1 down through it. Ring 1's eye, and rings 3 to 9 with their rods, never move.

### What the geometry forced

With the nominal sizes, a few things are not free choices, and the checker found them:

- A ring that is on has to lean at least about 42.5° for the rod of the ring before it to pass inside its lower arc. The model uses 43°.
- When ring 1 is off, its eye must be wholly below the rails, and that is just inside ring 2's lower arc. Ring 2 then goes round rod 1 at the foot of its eye rather than round the straight shaft, and ring 2's lower arc wraps so closely under the eye that ring 1 can only hang across the sword there.
- So ring 1 cannot drop straight through the slot. Its eye goes down into the slot first; the ring tips over toward the tip, rolls nearly flat and swings from side to side, so that it slips through the slot at a slant, partly over one rail and partly under the other; and only when it hangs across the sword does the eye sink below the rails and the rod leave the slot.
- Ring 1's eye sits 32 mm from the tip's end with the sword at home: any further and rod 9 would meet the rails where they close; any nearer and the slot in front of ring 1 would be too short for the drop.

### Ring 3: blocked under the present rules

Ring 3's move (from ring 1 off) is not written yet: no path has been found that the checker passes, and the scans say why. Ring 2 has to step aside, as ring 1 does for ring 2, but ring 1 hangs from it with rod 1 through it, and ring 1 cannot get from the side of ring 2 it hangs on to the other: the two rings are the same size, so ring 1 cannot pass through ring 2's hole, and going round its rim would link them. So when ring 2 swings up out of the way, ring 1 ends up lying on top of it, and rod 1 has to reach above ring 2. Rod 1's bead rests under the bar, so its eye can rise no higher than the eye of a ring that is on. That stops ring 2 at about 80° from upright, still drooping toward the tip, and there ring 3 cannot lift far enough for the tip to pass out of it with 0.2 mm to spare: the best attempt comes within 0.08 mm of eye 2. `RingThreeOff` holds that attempt, and `HangingChain` the rule that carries a hanging ring, or a chain of them, along with the ring it hangs from.

## Layout

- `NineRingsKit/`: a Swift package with everything that does not depend on the interface.
  - `Puzzle`: which rings are on, the rule that says which ring can move, and the one path through all 512 states.
  - `Toy`: the toy's nominal dimensions, the sword's shape, and `ToyPose`, the place of every part. The toy's frame is fixed to the bar; the sword's pose is its slide along its length.
  - `Motion`: the written motion. `Layout` holds the fixed places and the few numbers the motion rests on; `HeldRing` is a ring as its rod holds it, with the rod rule; `RestPoses` places each ring by rule relative to its own hole; `Curve` is a smooth, never-overshooting curve through key values; `RingTurns` is the rule that turns a few angles and the eye's height into where a ring is; `Pacing` maps a move's progress onto its path so the move flows at an even pace; `RingOneOff` and `RingTwoOff` are the two written paths; `MoveMotion` is the public entry: the pose for a move at a progress, and the move's stages.
  - `Geometry`: the centrelines of the shapes (circles, straight pieces, the bar's sheet) and the search for where two of them come near. Only the checker uses it.
- `NineRings/` and `NineRings.xcodeproj`: the app, in SwiftUI and RealityKit. The project file is in Xcode's JSON format and `NineRings/` is a synchronized folder, so adding a file there does not change the project file.
  - `Model/Player.swift`: the move, its progress, playing and the speed.
  - `Scene`: the toy drawn in 3D, with meshes generated from `Dimensions`; `ToyScene.apply(_:)` places every part for a `ToyPose`.
  - `Views`: the 3D view with its orbit camera, and the controls: play or pause, full, half or quarter speed, and a scrubber with the stages marked and named. The layout follows the size of the window, never the device: the top row stacks when narrow, and stage names give way to stage numbers.
  - `Capture`: renders the move to image files, in debug builds only (see below).

## The checker

The package's tests sample each written move at 4000 progress values in each direction and check, at every sample:

- any two parts not joined by design keep at least 0.2 mm between their surfaces. Joined by design means only a ring and the eye that holds it, and a rod's shaft and the bar, which the rod rule below measures instead. Parts that rest against each other, such as a bead under the bar, are drawn 0.25 mm apart;
- no point of any part moves more than 0.25 mm from one sample to the next;
- ring k (k ≥ 2) has rod k−1 through it and no other rod; no two rings are linked; each eye is linked with its own ring and no other, and the ring's wire runs through the eye without cutting through it; each rod's shaft runs through its own hole without cutting into the hole's wall or rims, at any tilt, though it may touch them, since it slides there; each bead stays below the bar; the bar never moves;
- a ring goes round both rails or neither; only the rings a move takes off, and ring 1 when it steps aside, ever leave them; and any ring, from one sample to the next, leaves or joins the rails only over the tip's end: where it goes round them, the sword goes through it nowhere but near the tip's end. The sword's centreline ends at the tip's end and at the end of the neck, and this is what stops a ring leaving over the neck's end, where the grip is not checked;
- in ring 2's move, rings 3 to 9, their rods and ring 1's eye stay exactly where they rest;
- the two ends of the move are the two rest poses, and going on is coming off backwards;
- the stages come in order and each does what its name says;
- position and velocity are continuous, the move starts and ends at rest, and it does not stop between stages.

A pose takes well under a microsecond to compute in an optimized build.

Several tests are tools rather than checks, and run only when asked: `NINE_RINGS_PROFILE=1` (or `=2` for ring 2) prints the smallest gap and the fastest-moving part through the move; `NINE_RINGS_EXPLORE=1` maps where ring 1 can be with its eye at each height and searches that map for a way down; `NINE_RINGS_TUNE=1` searches the key values of the drop for the path with the most room. `NINE_RINGS_TUNE2=1` does the same for every key of ring 2's move. The key values in `RingOneOff` and `RingTwoOff` came from these searches, and are written there as plain numbers. For ring 3, `NINE_RINGS_TUNE3=1` (or `NINE_RINGS_REPORT3=1` to print the room along the path) tunes `RingThreeOff`; `NINE_RINGS_ASIDE=1` scans where ring 2 could step aside to, carrying ring 1, while ring 3 lifts over the tip; and `NINE_RINGS_REACH=1` scans whether rod 1 could reach through ring 2 at all there, whatever ring 1 does (with `NINE_RINGS_FRONT=1`, keeping its eye on the side of ring 2 that ring 1 hangs on).

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

A picker in the toolbar chooses which ring's move is shown. To open the app on ring 2's move, launch it with `-move 2`; to open it part way through the move, with `-start-progress 0.5`. Space plays or pauses; ⌘1, ⌘2 and ⌘3 show the toy from the side, from above and from the tip.

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

It writes one image per progress value and view, named `ring<n>-p<progress>-<view>-<appearance>.png`, prints each path and quits.

- `-capture-move 2`: ring 2's move rather than ring 1's.
- `-capture-frames 16`: that many frames evenly across the move, from every ring on (0) to its ring off (1). Or `-capture-progress 0,0.25,0.5` for given progress values.
- `-capture-views`: `side`, `top` and `tip` are the app's camera presets; `yaw:pitch` in degrees, as `25:18`, looks from any other direction.
- `-capture-sheet`: also lays out the frames of each view on one contact sheet, `ring<n>-sheet-<view>-<appearance>.png`, each frame labelled with its progress and stage.
- `-capture-focus x,y,z,size`: frames a cube of `size` millimetres around a point in the toy's frame instead of the whole move; `24,-8,0,62` shows ring 1 close up, and `36,0,0,62` rings 1 and 2.
- `-capture-size 1600x1000`: the image size in pixels.
- `-capture-appearance dark`: the dark background.

An unsigned build is not sandboxed, so it can write into the repository. A signed build is, and should be given a folder inside its container, or no `-capture-dir` for its temporary folder.
