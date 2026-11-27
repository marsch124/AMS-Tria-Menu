import ServiceManagement
import SwiftUI
import TriaMenuCore

/// "Open at login": remembers what you asked for and puts it right when the Mac has dropped it.
enum LoginItem {
    static let wantedKey = "wantsOpenAtLogin"

    /// Returns one line for the diary.
    static func checkAtStart() -> String {
        let store = UserDefaults.standard
        let status = SMAppService.mainApp.status
        // The first start with this check: what is set now is what you asked for.
        if store.object(forKey: wantedKey) == nil { store.set(status == .enabled, forKey: wantedKey) }
        guard store.bool(forKey: wantedKey) else { return "open at login: off" }
        switch status {
        case .enabled: return "open at login: on"
        case .requiresApproval: return "open at login: waits for your yes in System Settings, Login Items"
        default:
            try? SMAppService.mainApp.register()
            return SMAppService.mainApp.status == .enabled
                ? "open at login: the Mac had dropped it; switched on again"
                : "open at login: the Mac had dropped it and switching it on again did not work"
        }
    }

    static func set(_ wanted: Bool) {
        UserDefaults.standard.set(wanted, forKey: wantedKey)
        if wanted { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
        // The keeper follows the switch: its start order is written or removed with it.
        if wanted { KeeperJob.writeFile() } else { KeeperJob.remove() }
    }
}

/// Settings in three tabs: the settings themselves, How it works, What's new.
/// The header and the bottom line (version, Quit, Done) stay on every tab.
struct SettingsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case settings = "Settings", guide = "How it works", news = "What\u{2019}s new"
        var id: String { rawValue }
    }

    @ObservedObject var model: AppModel
    var close: () -> Void = {}
    /// False only for pictures, where a scrolling area cannot be drawn.
    var scrolls = true
    /// The tab shown first.
    var startTab: Tab = .settings
    /// For checks: open with the page scrolled to its end.
    var atEnd = false
    @State private var picked: Tab?
    @State private var openAtLogin = UserDefaults.standard.bool(forKey: LoginItem.wantedKey)
    @Environment(\.colorScheme) private var scheme

    private var tab: Tab { picked ?? startTab }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AppTile(size: 26)
                Text("AMS Tria Menu").font(.title3.weight(.semibold))
                Text(AppInfo.version).font(.callout).foregroundStyle(.secondary)
            }
            tabs

            Group {
                if scrolls {
                    ScrollViewReader { proxy in
                        ScrollView {
                            page.padding(.trailing, 6)
                            Color.clear.frame(height: 1).id("pageEnd")
                        }
                        .onAppear {
                            if atEnd {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { proxy.scrollTo("pageEnd", anchor: .bottom) }
                            }
                        }
                    }
                } else {
                    page.frame(maxHeight: .infinity, alignment: .top).clipped()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 8) {
                Text("Version \(AppInfo.version) (\(AppInfo.build))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settingsVersion")
                Spacer()
                bottomButton("Quit AMS Tria Menu", fill: nil, id: "quitButton") { NSApp.terminate(nil) }
                bottomButton("Done", fill: Palette.mainFill, id: "doneButton", action: close)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(width: 440, height: 520)
        .accessibilityIdentifier("settings")
    }

    /// Drawn by the app, so the main button keeps its full colour whatever window is in front.
    private func bottomButton(_ title: String, fill: Color?, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.callout.weight(.medium))
                .foregroundStyle(fill == nil ? Palette.today(scheme) : Color.white)
                .padding(.horizontal, 14)
                .frame(height: 26)
                .background(fill ?? Palette.pale(Palette.today(scheme), scheme), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier(id)
    }

    /// Three drawn tab buttons: the one in use is full colour, in the colour of its page.
    private var tabs: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases) { one in
                let selected = one == tab
                Button { picked = one } label: {
                    Text(one.rawValue)
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .lineLimit(1)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(selected ? fill(one) : Color.primary.opacity(0.07),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("tab-\(one.id)")
            }
        }
    }

    private func fill(_ tab: Tab) -> Color {
        switch tab {
        case .settings: return Palette.mainFill
        case .guide: return Color(hex: 0x1266C8)
        case .news: return Color(hex: 0x7C3AED)
        }
    }

    private func ink(_ tab: Tab) -> Color {
        switch tab {
        case .settings: return Palette.today(scheme)
        case .guide: return Palette.tomorrow(scheme)
        case .news: return Palette.week(scheme)
        }
    }

    @ViewBuilder private var page: some View {
        switch tab {
        case .settings: settingsPage
        case .guide: guidePage
        case .news: newsPage
        }
    }

    // MARK: Settings

    private func small(_ words: String) -> some View {
        Text(words).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Open at login", isOn: $openAtLogin)
                    .tint(Palette.mainFill)
                    .onChange(of: openAtLogin) { _, wanted in LoginItem.set(wanted) }
                    .accessibilityIdentifier("openAtLoginToggle")
                small("While this is on, the app also comes back by itself if it ever stops unexpectedly.")
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Open Triathlon quietly", isOn: $model.quietOn)
                    .tint(Palette.mainFill)
                    .accessibilityIdentifier("quietToggle")
                small("Triathlon writes today\u{2019}s note only when it opens. With this on, AMS Tria Menu opens Triathlon in the background, hidden and never in front, when there is no note for today, and again every \(Int(QuietOpen.refresh / 60)) minutes while a session is still to do. It closes it again once the note is written.")
                small("It never touches a Triathlon you opened yourself, and waits while the Mac sleeps. With this off, the wave stays grey until you open Triathlon yourself.")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Where the figures come from").font(.headline).foregroundStyle(Palette.today(scheme))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Today\u{2019}s note").font(.callout.weight(.semibold))
                    Text(model.noteLine).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("noteLine")
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Body Battery").font(.callout.weight(.semibold))
                    Text(model.bodyLine).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("bodyLine")
                }
                HStack(spacing: 8) {
                    bottomButton(model.busy ? "Refreshing\u{2026}" : "Refresh now", fill: nil, id: "refreshButton") { model.refreshNow() }
                }
                .padding(.top, 2)
                small("Nothing leaves this Mac. The app only reads: it never changes your plan, and it holds no Garmin key.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("settingsPage")
    }

    // MARK: How it works, with the signs

    private var guidePage: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Guide.howItWorks) { section in
                // Short paragraphs, a little air between them: a blank line in the text starts a new one.
                VStack(alignment: .leading, spacing: 5) {
                    Text(section.title).font(.subheadline.weight(.semibold)).foregroundStyle(ink(.guide))
                    ForEach(Array(section.body.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Signs in this app").font(.subheadline.weight(.semibold)).foregroundStyle(ink(.guide))
                ForEach(Guide.signs) { sign in
                    HStack(alignment: .center, spacing: 8) {
                        swatch(sign.kind).frame(width: 34, height: 18)
                        (Text(sign.name).fontWeight(.semibold) + Text(": " + sign.meaning))
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityIdentifier("signs")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("guidePage")
    }

    private func flatLine(_ colour: Color, width: CGFloat, dot: Bool = false) -> some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 3, y: 9))
                path.addLine(to: CGPoint(x: 31, y: 9))
            }
            .stroke(colour, style: StrokeStyle(lineWidth: width, lineCap: .round))
            if dot { Circle().fill(colour).frame(width: 6.4, height: 6.4).position(x: 31, y: 9) }
        }
        .frame(width: 34, height: 18)
    }

    /// The sign itself, drawn as it looks in the app.
    @ViewBuilder private func swatch(_ kind: SignKind) -> some View {
        let box = RoundedRectangle(cornerRadius: 5, style: .continuous)
        switch kind {
        case .waveGreen: MenuWaveView().foregroundStyle(Palette.wave(scheme))
        case .waveGrey: MenuWaveView().foregroundStyle(Color.secondary)
        case .markSport: MarkView(mark: .sport("run"), size: 18).foregroundStyle(Sport.ink("run", scheme))
        case .markMoon: MarkView(mark: .moon, size: 18).foregroundStyle(Sport.ink("rest", scheme))
        case .pillToDo:
            Text("to do").font(.system(size: 9, weight: .bold)).foregroundStyle(scheme == .dark ? Color.black.opacity(0.85) : Color.white)
                .padding(.horizontal, 5).padding(.vertical, 1).background(Sport.ink("run", scheme), in: Capsule()).fixedSize()
        case .tickDone:
            HStack(spacing: 1) {
                MarkView(mark: .tick, size: 11, stroke: 2.4)
                Text("done").font(.system(size: 9, weight: .bold)).fixedSize()
            }
            .foregroundStyle(Palette.today(scheme))
        case .wordMissed: Text("missed").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).fixedSize()
        case .bodyCard: box.fill(Palette.bodyFill(scheme)).frame(width: 28, height: 14)
        case .todayLine:
            flatLine(.white, width: 2.2, dot: true).background(Palette.bodyFill(scheme), in: box)
        case .yesterdayLine:
            flatLine(Palette.yesterday(scheme), width: 1.2).background(Palette.bodyFill(scheme), in: box)
        case .green: Circle().fill(Palette.today(scheme)).frame(width: 12, height: 12)
        case .blue: Circle().fill(Palette.tomorrow(scheme)).frame(width: 12, height: 12)
        case .purple: Circle().fill(Palette.week(scheme)).frame(width: 12, height: 12)
        case .weekBar:
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.pale(Palette.week(scheme), scheme)).frame(width: 28, height: 5)
                Capsule().fill(Palette.weekFill(scheme)).frame(width: 11, height: 5)
            }
        case .buttonFull: box.fill(Palette.mainFill).frame(width: 28, height: 14)
        }
    }

    private var newsPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Guide.whatsNew) { release in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(release.version) \u{00B7} \(release.date)").font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink(.news))
                    ForEach(release.items, id: \.self) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\u{2013}").foregroundStyle(.secondary)
                            Text(item).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.callout)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("newsPage")
    }
}
