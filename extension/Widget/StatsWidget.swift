// The home screen widget: all-time, this week and today from the tweak's Stats store. The extension
// cannot read Spotify's Documents, so the tweak writes a small JSON into the App Group both sides
// share (extension/AppGroups puts them on a group the sideload signature really has) and reloads
// the timelines when it changes.
import SwiftUI
import WidgetKit

private let appGroup = "group.com.spotify.client.widget"
private let fileName = "spoti.pw-stats.json"

struct SGStatsSnapshot: Codable {
    var allMs: Int64
    var weekMs: Int64
    var todayMs: Int64
    var plays: Int
    var topArtist: String
    var topTrack: String
}

struct SGStatsEntry: TimelineEntry {
    let date: Date
    let snapshot: SGStatsSnapshot?
}

struct SGStatsProvider: TimelineProvider {
    func placeholder(in context: Context) -> SGStatsEntry {
        SGStatsEntry(date: Date(), snapshot: SGStatsSnapshot(allMs: 72600000, weekMs: 5400000, todayMs: 1800000, plays: 329228, topArtist: "Playboi Carti", topTrack: "xperiment"))
    }

    func getSnapshot(in context: Context, completion: @escaping (SGStatsEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SGStatsEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(3600))))
    }

    private func entry() -> SGStatsEntry {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        if let url = container?.appendingPathComponent(fileName),
           let data = try? Data(contentsOf: url),
           let snapshot = try? JSONDecoder().decode(SGStatsSnapshot.self, from: data) {
            return SGStatsEntry(date: Date(), snapshot: snapshot)
        }
        return SGStatsEntry(date: Date(), snapshot: nil)
    }
}

private func duration(_ ms: Int64) -> String {
    let minutes = ms / 60000
    if minutes < 60 { return "\(minutes) min" }
    return "\(minutes / 60)h \(minutes % 60)m"
}

extension View {
    // containerBackground is iOS 17; below it the widget draws its own black.
    @ViewBuilder func sgWidgetBackground() -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) { Color.black }
        } else {
            self.background(Color.black)
        }
    }
}

struct SGStatsWidgetView: View {
    var entry: SGStatsEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 4) {
                Text("LISTENING").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Text(duration(snapshot.allMs)).font(.system(size: 26, weight: .bold))
                Text("today \(duration(snapshot.todayMs)) · week \(duration(snapshot.weekMs))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                if !snapshot.topArtist.isEmpty {
                    Text("Top artist · \(snapshot.topArtist)").font(.system(size: 11)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(14)
            .sgWidgetBackground()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Listening stats").font(.headline)
                Text("Enable Stats in spoti.pw and play something.").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(14)
            .sgWidgetBackground()
        }
    }
}

struct SGStatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SGStatsWidget", provider: SGStatsProvider()) { entry in
            SGStatsWidgetView(entry: entry)
        }
        .configurationDisplayName("Listening stats")
        .description("Your all-time, this week and today listening.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct SGStatsWidgetBundle: WidgetBundle {
    var body: some Widget {
        SGStatsWidget()
    }
}
