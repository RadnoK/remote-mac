import Foundation

/// Every user-facing string in the app, as a type. A typo is a compile error
/// rather than a key rendered raw at runtime.
public enum LocKey: String, CaseIterable, Sendable {
    // Menu — window titles
    case menuQuickSwitcherTitle = "menu.quick_switcher_title"

    // Menu — header
    case menuHeaderTitle = "menu.header.title"
    /// Takes two arguments: total machine count, then the count available now.
    case menuHeaderSummary = "menu.header.summary"

    // Menu — states
    case menuNoHosts = "menu.no_hosts"
    case menuLoading = "menu.loading"

    // Menu — pane
    case menuSectionMachines = "menu.section.machines"

    // Menu — actions
    case menuQuickConnect = "menu.quick_connect"
    case menuRefresh = "menu.refresh"
    case menuSettings = "menu.settings"
    case menuQuit = "menu.quit"

    // Menu — quick switcher
    case menuQuickSwitcherSearch = "menu.quick_switcher_search"

    // Row actions
    case rowConnect = "row.connect"
    case rowOpenSSH = "row.open_ssh"
    case rowOpenFiles = "row.open_files"
    case rowCopyAddress = "row.copy_address"

    // Status labels (HostStatus.label)
    case statusUnknown = "status.unknown"
    case statusOffline = "status.offline"
    case statusOnline = "status.online"
    case statusScreenSharingOff = "status.screen_sharing_off"
    case statusNotFound = "status.not_found"

    // Login item state labels
    case loginItemEnabled = "login_item.enabled"
    case loginItemDisabled = "login_item.disabled"
    case loginItemRequiresApproval = "login_item.requires_approval"
    case loginItemUnavailable = "login_item.unavailable"

    // Settings — tabs
    case settingsTabGeneral = "settings.tab.general"
    case settingsTabHosts = "settings.tab.hosts"
    case settingsTabAbout = "settings.tab.about"

    // Settings — general
    case settingsGeneralSection = "settings.general.section"
    case settingsTerminalField = "settings.general.terminal_field"
    case settingsSSHUsernameField = "settings.general.ssh_username_field"
    case settingsLaunchAtLogin = "settings.general.launch_at_login"
    case settingsLaunchAtLoginHelp = "settings.general.launch_at_login_help"
    case settingsOpenSystemSettings = "settings.general.open_system_settings"
    case settingsWarpClipboardHint = "settings.general.warp_clipboard_hint"
    case settingsTerminalAutomationHint = "settings.general.terminal_automation_hint"
    case settingsLaunchAtLoginError = "settings.general.launch_at_login_error"
    case settingsAppearanceSection = "settings.appearance.section"
    case settingsLanguage = "settings.appearance.language"
    case settingsLanguageSystem = "settings.appearance.language_system"
    case settingsLanguagePolish = "settings.appearance.language_polish"
    case settingsLanguageEnglish = "settings.appearance.language_english"

    // Settings — hosts
    case settingsManualHostsHeader = "settings.hosts.manual_header"
    case settingsHostNameField = "settings.hosts.name_field"
    case settingsHostAddressField = "settings.hosts.address_field"
    case settingsHostAdd = "settings.hosts.add"
    case settingsHostRemove = "settings.hosts.remove"
    case settingsHostRemoveConfirm = "settings.hosts.remove_confirm"
    case settingsHostsEmpty = "settings.hosts.empty"
    case settingsHostsListSection = "settings.hosts.list_section"
    case settingsHostDetailSection = "settings.hosts.detail_section"

    // Settings — about
    case settingsAboutSection = "settings.about.section"
    case settingsVersion = "settings.about.version"
    case settingsAboutWebsite = "settings.about.website"
    case settingsAboutContact = "settings.about.contact"
    case settingsAboutSendEmail = "settings.about.send_email"

    // Errors
    case errorHostListFailed = "error.host_list_failed"
    case errorTailscaleNotFound = "error.tailscale_not_found"
    case errorTailscaleNotResponding = "error.tailscale_not_responding"
    case errorTailscaleCLIUnavailable = "error.tailscale_cli_unavailable"
    /// Takes one argument: the raw Tailscale backend state.
    case errorTailscaleDisconnected = "error.tailscale_disconnected"
    case errorSettingsSaveFailed = "error.settings_save_failed"
    /// Takes one argument: the terminal's display name.
    case errorLaunchFailed = "error.launch_failed"
    /// Takes one argument: the terminal's display name.
    case errorLaunchFailedAutomation = "error.launch_failed_automation"

    // Subtitle
    case subtitleLocked = "subtitle.locked"
}
