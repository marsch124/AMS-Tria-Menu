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

    /// 0.2 (his pick C3): the name with the number right beside it, the small words at the right, and under
    /// them a wide curve of the day with the hours.
    private var bodyCard: some View {
        let shown = model.body
        let today = DayKey.of(model.now)
        let start = DayKey.start(of: today)?.timeIntervalSince1970 ?? 0
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("Body Battery").font(.caption.weight(.semibold))
                Text(Words.number(shown.latest)).font(.system(size: 24, weight: .bold)).monospacedDigit()
                    .accessibilityIdentifier("bodyNumber")
                Spacer(minLength: 4)
                Text(shown.smallWords(now: model.now)).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityIdentifier("bodyWords")
            }
            if !shown.today.isEmpty || !shown.yesterday.isEmpty {
                BodyCurveView(today: BodyCurve.spots(shown.today, dayStart: start),
                              yesterday: BodyCurve.spots(shown.yesterday, dayStart: start - 86_400),
                              plum: Palette.yesterday(scheme))
                    .frame(height: 74)
            }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 7)
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

/// The curve on the Body Battery card: today as a white line with a dot at the newest reading and a soft
/// fill under it, yesterday as a thin dark line with its word. Midnight to midnight with the hours 06, 12, 18
/// under it; 0 at the bottom line, 100 at the top.
struct BodyCurveView: View {
    let today: [BodyCurve.Spot]
    let yesterday: [BodyCurve.Spot]
    let plum: Color

    /// Room under the curve for the hour marks and their figures.
    private let foot: CGFloat = 14

    var body: some View {
        GeometryReader { room in
            let size = room.size
            ZStack(alignment: .topLeading) {
                area(today, in: size).fill(Color.white.opacity(0.28))
                line(yesterday, in: size).stroke(plum, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                line(today, in: size).stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                if let last = today.last {
                    Circle().fill(Color.white).frame(width: 6.6, height: 6.6)
                        .position(place(last, in: size))
                }
                if let spot = wordSpot {
                    Text("yesterday").font(.system(size: 9, weight: .semibold)).foregroundStyle(plum).fixedSize()
                        .position(x: min(max(place(spot, in: size).x, 24), size.width - 24),
                                  y: max(place(spot, in: size).y - 9, 6))
                }
                ForEach([6, 12, 18], id: \.self) { hour in
                    let x = 3 + CGFloat(hour) / 24 * (size.width - 6)
                    Path { path in
                        path.move(to: CGPoint(x: x, y: size.height - foot))
                        path.addLine(to: CGPoint(x: x, y: size.height - foot + 3))
                    }
                    .stroke(Color.white.opacity(0.75), lineWidth: 1)
                    Text(String(format: "%02d", hour)).font(.system(size: 8.5, weight: .medium)).monospacedDigit().foregroundStyle(Color.white)
                        .fixedSize()
                        .position(x: x, y: size.height - 4.5)
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
        let base = size.height - foot
        return CGPoint(x: 3 + spot.x * (size.width - 6), y: base - spot.y * (base - 5))
    }

    private func line(_ spots: [BodyCurve.Spot], in size: CGSize) -> Path {
        var path = Path()
        guard spots.count > 1 else { return path }
        path.move(to: place(spots[0], in: size))
        for spot in spots.dropFirst() { path.addLine(to: place(spot, in: size)) }
        return path
    }

    /// The ground under today's line, down to the bottom line.
    private func area(_ spots: [BodyCurve.Spot], in size: CGSize) -> Path {
        var path = line(spots, in: size)
        guard let first = spots.first, let last = spots.last, spots.count > 1 else { return Path() }
        let base = size.height - foot
        path.addLine(to: CGPoint(x: place(last, in: size).x, y: base))
        path.addLine(to: CGPoint(x: place(first, in: size).x, y: base))
        path.closeSubpath()
        return path
    }
}
