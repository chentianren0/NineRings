# How the motion is written and checked

This is for someone who wants to change the motion, or to know why it is the way it is. How each move goes, stage by stage, is in the doc comments of `RingOneOff` and `PairMoveOff`; how long a move takes is in `MoveTiming`; why the fixed numbers are what they are is in `Layout`. This page holds what the code does not say in one place: the rules every part follows, what the geometry forced, what the checker checks, and the tools.

## The rules

- **We write the path of the ring that moves**, as a handful of smooth curves of the move's progress, from 0 to 1. Every turn of the ring is about an axis through its eye.
- **Every other part follows by rule.** A rod is a straight line from its eye, which sits on its ring's wire, through the middle of its own hole in the bar; it turns about its own axis so that its eye faces along the wire. The bead is at its lower end.
- **The bar stays still and level.** Rings and rods that the move does not involve stay still too, except the rings that ride on the sword when it goes down.
- **The sword stays level.** It slides along its own length, and may go down and come up again, carrying the rings that ride on it, whose rods slide down and up through the bar. That is how its tip comes to the ring for the lift over it, and moves away again so that there is room for the drop.
- **A ring that is off rests the same way wherever it is and whatever its neighbours are**: below the sword, its eye just under the rails, leaning toward the tip, its rod down through the next ring. So every one of the 512 states has its rest.

## What the geometry forced

With the nominal sizes, a few things are not free choices, and the checker found them:

- A ring that is on has to lean at least about 42.5° for the rod of the ring before it to pass inside its lower arc. The model uses 43°.
- When ring 1 is off, its eye must be wholly below the rails, and that is just inside ring 2's lower arc. Ring 2 then goes round rod 1 at the foot of its eye rather than round the straight shaft, and ring 2's lower arc wraps so closely under the eye that ring 1 can only hang across the sword there.
- So ring 1 cannot drop straight through the slot. Its eye goes down into the slot first; the ring tips over toward the tip, rolls nearly flat and swings from side to side, so that it slips through the slot at a slant, partly over one rail and partly under the other; and only when it hangs across the sword does the eye sink below the rails and the rod leave the slot.
- Ring 1's eye sits 32 mm from the tip's end with the sword at home: any further and rod 9 would meet the rails where they close; any nearer and the slot in front of ring 1 would be too short for the drop.
- Ring k cannot leave the rails while ring k−1 is still on them. As ring k swings up, the places where its disc meets the rails move forward to the tip end, and on the way they would have to pass where ring k−1's disc meets them. There both discs hold the same two points, one on each rail, so both rings cross the line between those points, and each ring's crossing has to reach past both rails: at least 23.7 mm, with the wires and the 0.2 mm gap. Two rings whose discs cross along one line stay unlinked only if one ring's crossing lies inside the other's, with its wire clear at both ends, which needs at least 28.7 mm where a ring is 25.7 mm across. So ring k−1 must be off the rails first, with its rod still in the slot: the sword is drawn back out of it, and goes down so that ring k can pass under it.
- With ring k−1 still and the sword down, the rod of the ring in front of ring k−1 hangs through where the sword's tip would go: it stands 30 mm in front of ring k's eye and reaches down through the bar, so there is at most 27.85 mm of slot in front of the eye. The drop needs 30.5 mm with the eye above its hole. Moving the eye back 3.3 mm gives what the drop needs; moving it back for the whole drop would bring ring k against ring k+1, so it moves back only for the middle of the drop.
- The sword goes down 20 mm. With every ring behind on, the sword and what rides on it could go down 34 mm before anything came within 0.3 mm of the bar; with a ring hanging behind, 26.9 mm, set by the hanging ring's lowest point (`NINE_RINGS_ROOM_BELOW=1` measures it). The least that would let ring k pass under ring k−1 is about 17 mm, but that is an estimate, measured by hand for an earlier trial of this move; nothing measures it for this move.

## What the checker checks

The package's tests sample each written move at 4000 progress values in each direction and check, at every sample:

- Any two parts not joined by design keep at least 0.2 mm between their surfaces. Joined by design means only a ring and the eye that holds it, and a rod's shaft and the bar, which the rod rule below measures instead. Parts that rest against each other, such as a bead under the bar, are drawn 0.25 mm apart.
- No point of any part moves more than 0.25 mm from one sample to the next.
- Ring k (k ≥ 2) has rod k−1 through it and no other rod; no two rings are linked; each eye is linked with its own ring and no other, and the ring's wire runs through the eye without cutting through it; each rod's shaft runs through its own hole without cutting into the hole's wall or rims, at any tilt, though it may touch them, since it slides there; each bead stays below the bar; the bar never moves.
- A ring goes round both rails or neither. Every ring that is on goes round them, except the ring that moves and, in the second ring's move, ring k−1, which the sword leaves and comes back into; every other ring that is off goes round neither, so that no move can hide another. A ring leaves or joins the rails only over the tip's end: where it goes round them, the sword goes through it nowhere but near the tip's end. Each side of the sword's centreline has two ends, the tip's end, where the sides meet, and the end of its grip loop, which lies inside the side's own wire, so that a ring cannot pass over it without meeting the wire.
- In ring 1's move every other ring keeps still. In the second ring's move every ring in front of ring k keeps still, and every ring behind it moves only with the sword, by exactly its height.
- The two ends of the move are the two rest poses, and going on is coming off backwards.
- The stages come in order and each does what its name says.
- Position and velocity are continuous, the move starts and ends at rest, and it does not stop between stages.

The second ring's move is checked in full for ring 2, with ring 3 on and off behind it; for ring 3, with ring 1 off and with the rings behind on, off and mixed; and for ring 9. Ring 1's move is checked with ring 2 on and off behind it. Every one of the 512 states is checked at rest. On every run, all 511 moves, both ways, are checked at 801 progress values for the rings they must leave still and for no ring getting onto the rails or leaving them.

Every pose of every move at those 801 values, and the rest pose of every state, is also held to a fingerprint written in `MotionFingerprintTests`: a hash of their exact bits. A change that should leave the motion alone leaves the fingerprint alone; a change meant to change the motion changes the value there with it.

## Tools that run only when asked

Some tests are tools rather than checks. Each runs only when its environment variable is set, and says what it does in its own doc comment:

- `NINE_RINGS_EVERY_MOVE=1` runs all 511 moves through the full checker, both ways. It takes about an hour on a fast Mac.
- `NINE_RINGS_PROFILE=1` (or `2`, for ring 2) prints the smallest gap and the fastest-moving part through a move; `NINE_RINGS_PAIR=1` prints where the second ring's move is tightest, for the cases `NINE_RINGS_CASES` lists.
- `NINE_RINGS_FINGERPRINT_OUT=<file>` writes the fingerprint's line for each move and rest, to find which ones differ.
- `NINE_RINGS_ROOM_BELOW=1` measures how far the sword can go down.
- The search tools, in `Tests/MotionTests/Search`, find a move's key values: `NINE_RINGS_PAIR_TUNE=1` tunes the second ring's drop for the most room; `NINE_RINGS_SEARCH=1` (or `2`) proves the tuner by finding ring 1's drop (or the second ring's) again from a rough guess; `NINE_RINGS_PLAN=1` finds ring 1's drop again from its two ends alone; and `NINE_RINGS_MEASURE=1` times the pieces.

The search tools change nothing in the app. The key values in `RingOneOff` and `PairMoveOff` came from them and are written there as plain numbers, and the checker judges them as it judges everything else. To write a new kind of move with them: describe the moving parts as a `ConfigSpace`, plan a way between the poses each stage begins and ends at with `Planner.plan`, fit the legs with `CurveFit.keys(legs:)`, widen the room with `Tuner.run`, write the keys it prints into the move's path, and let the tests judge it. The tuner widens the room but does not make a move calmer, so look at the curves too.

A tool can also run on GitHub's machines, up to five copies side by side, so that a long one does not keep a Mac busy. Start it by hand on a pushed branch:

```bash
gh workflow run tools.yml --ref <branch> -f filter=RingSearchTests -f environment="NINE_RINGS_SEARCH=2" -f copies=3 -f minutes=120
```

Each copy gets `NINE_RINGS_COPY` set to its number, which the search tools use as their seed, and whatever a tool writes into `tool-output/` is kept with the run. Those machines are several times slower than a fast Mac, so a run of a few minutes is quicker at home; GitHub pays for a run longer than about twenty minutes, or for several seeds at once.
