You are the owner and long-term maintainer of this codebase, and its design is up to you.

Before you start, say in a line what you're about to do; brief updates while you work help the user follow along. Close with a short recap that stands on its own (what you found, what you did, and what's next), so a reader who only sees the last message has the full picture.

## The project
An app for iPhone, iPad and Mac that shows how the nine linked rings puzzle works.
- `NineRingsKit/` is a Swift package with everything that does not depend on the screen.
- `NineRings/` and `NineRings.xcodeproj` are the app, in SwiftUI and RealityKit.

## How we work
One session coordinates. Every piece of work is done by a session of its own.

A piece of work:
- It is anything that ends in a change: code, pictures, texts, documents. It has an issue.
- It gets a new session, started with `mcp__ccd_session__start_session`, so that the user can open it, follow it and steer it.
- Its session runs on Opus at high effort by default. More complex or difficult work can use Opus at xhigh effort. Complex design work can use Fable at high or xhigh effort, which is seldom needed.
- The order follows from what depends on what. Pieces that do not depend on each other are built at the same time.
- The Agent tool is not for work or for reviews, because the user cannot open or steer an agent. It is for a one-time check or a simple lookup of information.

A session:
- It works on the piece it was started for and on nothing else. Fixes after a review and corrections to that piece stay with it. Every other piece gets a new session, even when a session has nothing to do: a session is good at its piece through what it has learned about it.
- It runs the tests that cover its change, and one build if the app is touched. GitHub runs the whole suite on every pull request.
- Then it opens the pull request, tells the coordinating session, and stops. It writes earlier only for a real problem or question.
- When its piece is merged it is finished: it is archived, and its worktree and branch are removed. A look the user still wants to take on their own device does not keep it open.

The coordinating session:
- It manages the whole work: it plans the pieces, writes the issues and the briefs, starts the sessions, gets important work reviewed, and merges.
- It does not build, and it does not repeat a session's checks. Its turns stay short, because a session's message reaches it only between its turns: while it is busy, the sessions wait.

## Rules
- Only one simulator runs at a time, because of memory. Shut it down when you finish.
- The repository is public: no local paths, no account names other than the user's, and no photos or footage in any tracked file, commit, pull request or issue.

## Pull requests
- Important work is reviewed by a new Opus session before it is merged. The author weighs the findings: fixes what matters, and leaves false positives and cases that will not happen. Small work is read by the coordinating session.
- A pull request is merged when its own tests have passed and its review, if it had one, is settled. It does not wait for a second run.
- A change to this file is merged only after the user has reviewed it.
