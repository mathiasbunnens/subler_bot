import SwiftUI
import AppKit
import ServiceManagement
import AutomationCore

// Remember only the exact Settings host; orderOut/rehosting must not lose its identity.
@MainActor
enum SettingsWindowFocus {
    private static weak var settingsWindow: NSWindow?
    private static var generation = 0

    static func register(_ window: NSWindow) {
        settingsWindow = window
        request()
    }
    static func restore(if window: NSWindow) {
        guard settingsWindow === window else { return }
        request()
    }

    static func request() {
        generation += 1
        let requestID = generation
        // SettingsLink and the menu window can both schedule a later key-window handoff.
        // Bound retries to this click; a newer click invalidates the old callbacks.
        for delay in [0.0, 0.1, 0.25] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard requestID == generation, let window = settingsWindow else { return }
                guard !window.isKeyWindow || !window.isVisible || !NSApplication.shared.isActive else { return }
                if window.isMiniaturized { window.deminiaturize(nil) }
                NSApplication.shared.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

private struct SettingsWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsHostView { SettingsHostView() }
    func updateNSView(_ nsView: SettingsHostView, context: Context) {}

    final class SettingsHostView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window = self.window else { return }
            SettingsWindowFocus.register(window)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var queue: JobQueueService
    @State private var draft = AppSettings()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var serviceError: String?
    init(queue: JobQueueService) {
        self.queue = queue
        _draft = State(initialValue: queue.settings)
    }
    private var hasChanges: Bool { draft.differsForEditing(from: queue.settings) }
    var body: some View {
        VStack(spacing: 0) {
            Text(AppVersion.current.label)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .help(AppVersion.current.details)
            TabView {
                general.tabItem { Label("Général", systemImage: "gearshape") }
                folders.tabItem { Label("Dossiers", systemImage: "folder") }
                server.tabItem { Label("Serveur", systemImage: "externaldrive.badge.wifi") }
                PermissionSettingsView(permissions: queue.permissions, retry: { queue.preparePermissions() })
                    .tabItem { Label("Autorisations", systemImage: "checkmark.shield") }
            }

            if let serviceError { Text(serviceError).font(.caption).foregroundStyle(.red).padding(.horizontal, 16) }
            if let message = queue.message { Text(message).font(.caption).foregroundStyle(.red).padding(.horizontal, 16) }
            if hasChanges {
                VStack(spacing: 0) { Divider(); saveFooter }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .clipped()
        .animation(.easeInOut(duration: 0.2), value: hasChanges)
        .frame(width: 590, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(SettingsWindowAccessor())
        .textFieldStyle(.roundedBorder)
        .buttonStyle(.borderless)
        .controlSize(.regular)
        .onAppear { draft = queue.settings }
    }

    private var general: some View {
        Form {
            Section {
                Picker("Présentation de l’application", selection: $draft.presentationMode) {
                    Text("Barre des menus uniquement").tag(AppPresentationMode.menuBar)
                    Text("Application normale (Dock et fenêtre)").tag(AppPresentationMode.normal)
                }
                Text("Après Enregistrer : soit Dock et fenêtre, soit barre des menus sans Dock. Les deux modes ne sont jamais affichés ensemble.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Label("Présentation", systemImage: "macwindow") }
            Section {
                Toggle("Notifications", isOn: $draft.notifications)
                HStack {
                    Text("Alertes de fin de traitement et interventions")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Préparer…") { queue.preparePermissions() }
                }
            } header: { Label("Notifications", systemImage: "bell") }
            Section {
                Toggle("Lancer à l’ouverture de session", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            serviceError = nil
                        } catch { serviceError = error.localizedDescription; launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
                Text("Cette option s’applique immédiatement. Gardez l’application au même emplacement.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Label("Démarrage", systemImage: "power") }
            Section {
                Toggle("Nettoyer les MP4 locaux après transfert vérifié", isOn: $draft.cleanupTemporary)
                Text("Les MKV originaux ne sont jamais supprimés. Le nettoyage reste désactivé par défaut.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Label("Stockage", systemImage: "internaldrive") }
        }.formStyle(.grouped)
    }

    private var folders: some View {
        Form {
            Section {
                folder("MKV surveillés", path: $draft.sourcePath)
                Toggle("Surveiller automatiquement le dossier", isOn: $draft.watchFolder)
            } header: { Label("Dossier source", systemImage: "folder.badge.plus") }
            Section {
                folder("MP4 temporaires", path: $draft.temporaryPath)
                Text("Un dossier local est conseillé pour éviter les allers-retours réseau. Un dossier sur le serveur reste autorisé ; les MP4 sont validés avant transfert.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Label("Conversion", systemImage: "film") }
            Section {
                Text("Les MKV doivent être stables pendant 10 secondes et ne plus être ouverts en écriture. Pour une copie susceptible de longues pauses, utilisez .part puis renommez en .mkv à la fin.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Label("Surveillance", systemImage: "eye") }
        }.formStyle(.grouped)
    }

    private var server: some View {
        Form {
            Section {
                TextField("Adresse SMB", text: $draft.smb.serverURL, prompt: Text("smb://serveur/partage"))
                TextField("Utilisateur", text: $draft.smb.username, prompt: Text(NSUserName()))
                TextField("Montage attendu", text: $draft.smb.expectedMountPath, prompt: Text("/Volumes/partage"))
                HStack {
                    Text(SMBConfiguration.mountedSMBShares().isEmpty
                         ? "Astuce : connectez-vous au partage dans le Finder (⌘K), puis détectez-le ici."
                         : "Un partage SMB est déjà monté sur ce Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Détecter le partage monté") {
                        let detected = SMBConfiguration.firstLaunchDefault()
                        if detected.isConfigured { draft.smb = detected }
                    }
                    .foregroundStyle(Color.accentColor)
                    .disabled(SMBConfiguration.mountedSMBShares().isEmpty)
                }
            } header: { Label("Connexion SMB", systemImage: "externaldrive.badge.wifi") }
            Section {
                Label("Identifiants dans le Trousseau macOS", systemImage: "key")
                    .font(.subheadline)
                Text("Lorsqu’un film est prêt à transférer, l’application tente une reconnexion automatique. Si nécessaire, macOS demande votre utilisateur et mot de passe. L’application ne stocke aucun mot de passe.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Le montage et son origine sont vérifiés avant le transfert. Aucun dossier de remplacement n’est créé sous /Volumes.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Label("Sécurité", systemImage: "lock.shield") }
        }.formStyle(.grouped)
    }

    private var saveFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 16) {
                Text("Les changements s’appliquent aux prochains films, pas au traitement en cours.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Enregistrer") {
                    draft.paused = queue.settings.paused
                    queue.applySettings(draft)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
                .fontWeight(.medium)
                .keyboardShortcut("s", modifiers: .command)
            }
        }.padding(16)
    }
    private func folder(_ title: String, path: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline)
            HStack(spacing: 8) {
                TextField(title, text: path).labelsHidden()
                Button("Choisir…", systemImage: "folder") {
                let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
                panel.title = title
                if FileManager.default.fileExists(atPath: path.wrappedValue) { panel.directoryURL = URL(fileURLWithPath: path.wrappedValue) }
                JobQueueService.activateForModal()
                if panel.runModal() == .OK, let url = panel.url {
                    path.wrappedValue = url.path; serviceError = nil
                }
                }
            }
            if let advice = LocalPathPolicy.performanceWarning(path.wrappedValue) {
                Label(advice, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
