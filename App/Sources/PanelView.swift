import SwiftUI
import TriaMenuCore

/// The panel under the menu bar item: today's sessions, tomorrow, this week, Body Battery.
struct PanelView: View {
    @ObservedObject var model: AppModel
    var openSettings: () -> Void = {}
    var close: () -> Void = {}
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            today
            if let tomorrow = model.note?.tomorrow { tomorrowBlock(tomorrow) }
            if let week = model.note?.week { weekBlock(week) }
            bodyCard
            mainButton
        }
        .padding(12)
        .frame(width: 300)
        // No keyboard ring around the first button: the panel is used with the pointer.
        .focusEffectDisabled()
        .accessibilityIdentifier("panel")
    }

    private var header: some View {
        HStack(spacing: 7) {
            AppTile(size: 22)
            Text("AMS Tria Menu").font(.headline)
            Text(AppInfo.version).font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("panelVersion")
            Spacer()
            Button(action: openSettings) {
                MarkView(mark: .gear, size: 19).foregroundStyle(.secondary).frame(width: 26, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .help("Settings")
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settingsButton")
        }
    }

    private func heading(_ words: String, _ colour: Color) -> some View {
        Text(words).font(.caption.weight(.semibold)).foregroundStyle(colour)
    }

    // MARK: Today

    private var today: some View {
        VStack(alignment: .leading, spacing: 5) {
            heading(model.note.map { $0.dayWords.isEmpty ? "Today" : "Today \u{00B7} \($0.dayWords)" } ?? "Today", Palette.today(scheme))
                .accessibilityIdentifier("todayHeading")
            if let note = model.note {
                if note.sessions.isEmpty {
                    Text("Nothing planned today").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(note.sessions) { session in sessionRow(session) }
                if note.sessions.contains(where: { $0.open != nil }) {
                    Text("Click a session to open it in Triathlon").font(.caption2).foregroundStyle(.secondary)
                        .padding(.leading, 2)
                        .accessibilityIdentifier("sessionHint")
                }
            } else {
                Text(model.noNote?.words ?? "").font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityIdentifier("noNote")
            }
        }
    }

    private func sessionRow(_ session: TodayNote.Session) -> some View {
        let rest = session.state == .rest
        let grey = session.state == .missed
        let ink = grey ? Color.secondary : Sport.ink(session.sport, scheme)
        return Button {
            model.openTriathlon(session)
            close()
        } label: {
            HStack(spacing: 8) {
                MarkView(mark: .sport(session.sport), size: 22).foregroundStyle(ink).frame(width: 24)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 7) {
                        Text(rest ? "Rest day" : Words.session(session)).font(.callout.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(Color.primary)
                        stateMark(session, ink: ink)
                    }
                    if !session.title.isEmpty {
                        Text(session.title).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Palette.pale(ink, scheme), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .help(session.title.isEmpty ? "Opens this session in Triathlon" : session.title)
        .accessibilityLabel("\(rest ? "Rest day" : Words.session(session)), \(Words.state(session.state)). \(session.title)")
        .accessibilityIdentifier("session-\(session.key)")
    }

    /// Right beside the session: a filled pill "to do" in the sport's colour, the green tick with "done", or grey "missed".
    @ViewBuilder private func stateMark(_ session: TodayNote.Session, ink: Color) -> some View {
        switch session.state {
        case .todo:
            Text("to do").font(.caption2.weight(.bold))
                .foregroundStyle(scheme == .dark ? Color.black.opacity(0.85) : Color.white)
                .padding(.horizontal, 7).padding(.vertical, 1)
                .background(ink, in: Capsule())
        case .done:
            HStack(spacing: 2) {
                MarkView(mark: .tick, size: 13, stroke: 2.4)
                Text("done").font(.caption.weight(.bold))
            }
            .foregroundStyle(Palette.today(scheme))
        case .missed:
            Text("missed").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        case .rest, .other:
            EmptyView()
        }
    }

    // MARK: Tomorrow and the week

    private func tomorrowBlock(_ words: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            heading("Tomorrow", Palette.tomorrow(scheme))
            Text(words).font(.callout).accessibilityIdentifier("tomorrowLine")
        }
    }

    private func weekBlock(_ words: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            heading("This week", Palette.week(scheme))
            Text(words).font(.callout).monospacedDigit().accessibilityIdentifier("weekLine")
            if let share = Week.share(done: model.note?.weekDoneMinutes, planned: model.note?.weekPlannedMinutes) {
                GeometryReader { room in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.pale(Palette.week(scheme), scheme))
                        Capsule().fill(Palette.weekFill(scheme)).frame(width: max(room.size.width * share, share > 0 ? 5 : 0))
                    }
                }
                .frame(height: 5)
                .padding(.top, 2)
                .accessibilityHidden(true)
            }
        }
    }

    // MARK: Body Battery

    private var bodyCard: some View {
        let shown = model.body
        let today = DayKey.of(model.now)
        let start = DayKey.start(of: today)?.timeIntervalSince1970 ?? 0
        return VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Body Battery").font(.caption.weight(.semibold))
                    Text(Words.number(shown.latest)).font(.system(size: 30, weight: .bold)).monospacedDigit()
                        .accessibilityIdentifier("bodyNumber")
                }
                Spacer(minLength: 0)
                if !shown.today.isEmpty || !shown.yesterday.isEmpty {
                    BodyCurveView(today: BodyCurve.spots(shown.today, dayStart: start),
                                  yesterday: BodyCurve.spots(shown.yesterday, dayStart: start - 86_400),
                                  plum: Palette.yesterday(scheme))
                        .frame(width: 168, height: 50)
                }
            }
            // Under the number, across the whole card: the words never push the card wider than the panel.
            Text(shown.smallWords(now: model.now)).font(.caption2).opacity(0.88).lineLimit(1)
                .accessibilityIdentifier("bodyWords")
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Palette.bodyFill(scheme), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .padding(.top, 3)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("bodyCard")
    }

    private var mainButton: some View {
        Button {
            model.openTriathlon()
            close()
        } label: {
            Text("Open Triathlon").font(.callout.weight(.semibold)).foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(Palette.mainFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!model.triathlonInstalled)
        .accessibilityIdentifier("openTriathlonButton")
    }
}

/// The small curve on the Body Battery card: today as a white line with a dot at the newest reading,
/// yesterday as a thin dark line with its word. Midnight to midnight, 0 at the bottom, 100 at the top.
struct BodyCurveView: View {
    let today: [BodyCurve.Spot]
    let yesterday: [BodyCurve.Spot]
    let plum: Color

    var body: some View {
        GeometryReader { room in
            let size = room.size
            ZStack(alignment: .topLeading) {
                line(yesterday, in: size).stroke(plum, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                line(today, in: size).stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                if let last = today.last {
                    Circle().fill(Color.white).frame(width: 6.4, height: 6.4)
                        .position(place(last, in: size))
                }
                if let spot = wordSpot {
                    Text("yesterday").font(.system(size: 9, weight: .semibold)).foregroundStyle(plum).fixedSize()
                        .position(x: min(max(place(spot, in: size).x, 24), size.width - 24),
                                  y: max(place(spot, in: size).y - 11, 6))
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Where the word sits: on yesterday's line, right of today's newest reading when there is room, else at its end.
    private var wordSpot: BodyCurve.Spot? {
        guard yesterday.count > 1 else { return nil }
        let after = (today.last?.x ?? 0) + 0.18
        return yesterday.first { $0.x >= after && $0.x <= 0.88 } ?? yesterday.last { $0.x <= 0.88 } ?? yesterday.last
    }

    private func place(_ spot: BodyCurve.Spot, in size: CGSize) -> CGPoint {
        CGPoint(x: 3 + spot.x * (size.width - 6), y: size.height - 4 - spot.y * (size.height - 10))
    }

    private func line(_ spots: [BodyCurve.Spot], in size: CGSize) -> Path {
        var path = Path()
        guard spots.count > 1 else { return path }
        path.move(to: place(spots[0], in: size))
        for spot in spots.dropFirst() { path.addLine(to: place(spot, in: size)) }
        return path
    }
}
