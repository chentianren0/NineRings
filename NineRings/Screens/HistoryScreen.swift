import Records
import Session
import SwiftUI

/// The history of finished plays, newest first: for each, when it was finished, its moves, the time spent, its undos,
/// the moves played for the person, and a mark when it went the shortest way. With no play yet, it says how a play gets
/// there. The history can be cleared, after the person confirms.
///
/// It opens from the menu, beside Game Center, since both are the person's record of their plays: a window of its own
/// on the Mac (``HistoryWindow``), a sheet from the toolbar's More menu on iPhone and iPad.
///
/// It uses the keeper's four things for a screen and nothing else: the plays and how many this build cannot read, read
/// as they are at each moment, never copied, so that the screen follows the records while it is open; the call that
/// clears; and whether clearing reaches the person's other devices, which the confirmation's words follow as it shows.
struct HistoryScreen: View {
    /// The history's symbol, on its menu item and on the page with no play.
    static let symbol = "clock.arrow.trianglehead.counterclockwise.rotate.90"

    @Environment(Keeper.self) private var keeper
    @State private var confirmsClearing = ScreenLaunchOptions.confirmsClearing
    #if DEBUG
    /// `-unreadable-plays`, in a debug build: plays this build cannot read, added to the keeper's until the history is
    /// cleared.
    @State private var unreadableForTrying = ScreenLaunchOptions.unreadablePlays
    #endif
    #if os(iOS)
    @Environment(\.dismiss) private var dismiss
    #endif

    private var plays: [PlayRecord] { keeper.history.plays }

    private var unreadable: Int {
        #if DEBUG
        keeper.history.unreadable + unreadableForTrying
        #else
        keeper.history.unreadable
        #endif
    }

    private var clearingReachesOtherDevices: Bool {
        #if DEBUG
        keeper.clearingReachesOtherDevices || ScreenLaunchOptions.clearingReachesOtherDevices
        #else
        keeper.clearingReachesOtherDevices
        #endif
    }

    var body: some View {
        content
            .navigationTitle(Text("history.title", tableName: "Screens"))
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            #endif
    }

    /// The plays, or with none, the system's page for nothing to show. Clearing comes after what it clears, and only
    /// when there is something to clear; the line for the plays this build cannot read comes under what is shown.
    @ViewBuilder
    private var content: some View {
        if plays.isEmpty {
            ContentUnavailableView {
                Label {
                    Text("history.empty.title", tableName: "Screens")
                } icon: {
                    Image(systemName: Self.symbol)
                }
            } description: {
                VStack(spacing: 12) {
                    Text("history.empty.text", tableName: "Screens")
                    if unreadable > 0 { unreadableLine }
                }
            } actions: {
                if unreadable > 0 { clearButton }
            }
        } else {
            Form {
                Section {
                    ForEach(plays, id: \.playID) { play in
                        PlayRow(play: play)
                    }
                } footer: {
                    if unreadable > 0 { unreadableLine }
                }
                Section {
                    clearButton
                }
            }
            .formStyle(.grouped)
        }
    }

    /// How many plays are kept that this build cannot read: a quiet line, since only a newer version of the app leaves
    /// them.
    private var unreadableLine: some View {
        Text("history.unreadable \(unreadable)", tableName: "Screens")
    }

    /// Clear History, which asks first. The confirmation says what goes: the plays on this device, or on every device
    /// when clearing reaches them. It is anchored to the button, as a popover on iPad is.
    private var clearButton: some View {
        Button(role: .destructive) {
            confirmsClearing = true
        } label: {
            Text("history.clear", tableName: "Screens")
        }
        .confirmationDialog(Text("history.clear.title", tableName: "Screens"), isPresented: $confirmsClearing, titleVisibility: .visible) {
            Button(role: .destructive) {
                clear()
            } label: {
                Text("history.clear", tableName: "Screens")
            }
        } message: {
            if clearingReachesOtherDevices {
                Text("history.clear.everyDevice", tableName: "Screens")
            } else {
                Text("history.clear.thisDevice", tableName: "Screens")
            }
        }
    }

    private func clear() {
        keeper.clearHistory()
        #if DEBUG
        unreadableForTrying = 0
        #endif
    }
}

/// One finished play. When it was finished is the headline, its numbers are under it, and the mark of the shortest way
/// is beside the date, or under it where the two do not fit side by side. VoiceOver reads the play as one sentence.
private struct PlayRow: View {
    let play: PlayRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if play.isShortestWay {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        date
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ShortestWayMark()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        date
                        ShortestWayMark()
                    }
                }
            } else {
                date
            }
            Text(verbatim: figures)
                .font(.subheadline)
                .supportingTextStyle()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: sentence))
        .accessibilityAddTraits(.isStaticText)
    }

    private var date: some View {
        Text(play.finishedAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
            .font(.headline)
    }

    /// The play's numbers in a line that breaks only between them, never inside one: a figure's own spaces do not
    /// break, and the dot after a figure stays with it.
    private var figures: String {
        [moves, time(width: .abbreviated), undos, playedForThePerson]
            .map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }
            .joined(separator: "\u{00A0}· ")
    }

    private var moves: String {
        String(localized: "history.moves \(play.moves)", table: "Screens")
    }

    private var undos: String {
        String(localized: "history.undos \(play.undos)", table: "Screens")
    }

    private var playedForThePerson: String {
        String(localized: "history.playedForYou \(play.movesPlayedForThePerson)", table: "Screens")
    }

    /// The time spent, to the second: "20 min, 35 sec", or in full words for VoiceOver.
    private func time(width: Duration.UnitsFormatStyle.UnitWidth) -> String {
        Duration.seconds(play.secondsSpent).formatted(.units(allowed: [.hours, .minutes, .seconds], width: width))
    }

    /// The play in one sentence, with the date and the time spent in full words.
    private var sentence: String {
        let date = play.finishedAt.formatted(date: .long, time: .shortened)
        let time = time(width: .wide)
        return play.isShortestWay
            ? String(localized: "history.play.spoken.shortestWay \(date) \(moves) \(time) \(undos) \(playedForThePerson)", table: "Screens")
            : String(localized: "history.play.spoken \(date) \(moves) \(time) \(undos) \(playedForThePerson)", table: "Screens")
    }
}

/// The mark of a play that went the shortest way: its words, which carry it, and a star in the tint. The words are in
/// the primary colour, since the tint, at this text size, is under the contrast text needs.
private struct ShortestWayMark: View {
    var body: some View {
        // Not a Label: in a form's row a label's icon takes a column of its own, far from its words.
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "star.fill")
                .foregroundStyle(.tint)
            Text("history.shortestWay", tableName: "Screens")
        }
        .font(.subheadline)
    }
}

#if os(macOS)
/// The Mac's history window, a window of its own, opened by History in the Puzzle menu. Its item is there alone, not in
/// the Window menu as well.
struct HistoryWindow: View {
    static let id = "history"

    var body: some View {
        HistoryScreen()
            .frame(minWidth: 360, minHeight: 300)
            .accessibilitySettings()
    }
}
#endif
