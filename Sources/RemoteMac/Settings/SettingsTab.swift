import RemoteMacCore

/// The settings window's tabs, in display order. A plain model rather than
/// an inline list so the toolbar and the content switch cannot drift apart.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case machines
    case about

    var id: String { rawValue }

    /// SF Symbol shown above the tab's title.
    var symbolName: String {
        switch self {
        case .general:  return "gearshape"
        case .machines: return "display.2"
        case .about:    return "info.circle"
        }
    }

    var titleKey: LocKey {
        switch self {
        case .general:  return .settingsTabGeneral
        case .machines: return .settingsTabHosts
        case .about:    return .settingsTabAbout
        }
    }
}
