import AppKit
import Combine
import UniformTypeIdentifiers
import AutomationCore

@MainActor
final class JobQueueService: ObservableObject {
    @Published var jobs: [MovieJob] = []
    @Published var settings = AppSettings()
    @Published var activeID: UUID?
    @Published var progress: TransferProgress?
    @Published var message: String?
    @Published var candidates: [UUID: [MetadataCandidate]] = [:]
    @Published private(set) var hasCompletedThisSession = false
    @Published private(set) var batch = BatchCounter()
    let permissions: PermissionPreparationService
    private var permissionObserver: AnyCancellable?
    private var preparingPermissions = true
    private var permissionTask: Task<Void, Never>?
    private let subler = SublerService()
    private let smb = SMBService()
    private let transfer = TransferService()
    private let notifications = NotificationService()
    private var store: QueueStore?
    private var stability = FileStabilityTracker()
    private var timer: Timer?
    private var worker: Task<Void, Never>?
    private var ticking = false
    private var serverRetryAfter = Date.distantPast
    private var authenticationGate = SMBAuthenticationGate()
    private var replacements = Set<UUID>()
    private var fatalPersistenceError = false

    var currentJob: MovieJob? { jobs.first { $0.id == activeID } }
    var symbol: String {
        if jobs.contains(where: { $0.status == .failed }) || fatalPersistenceError { return "exclamationmark.triangle" }
        if currentJob?.status == .transferring { return "externaldrive.badge.wifi" }
        return activeID == nil ? "film" : "gearshape.2"
    }
    init(permissions: PermissionPreparationService? = nil) {
        self.permissions = permissions ?? .shared
        do {
            settings = try AppSettings.load()
            store = try QueueStore(root: AppSettings.file.deletingLastPathComponent())
            jobs = try store!.load()
            for index in jobs.indices { jobs[index].recover() }
            try store!.save(jobs)
            if ProcessInfo.processInfo.environment["SUBLER_AUTOMATION_TEST_ROOT"] != nil { try ensureLocalFolders() }
        } catch {
            fatalPersistenceError = true; settings.paused = true
            message = "Initialisation impossible : \(error.localizedDescription). Aucun état existant ne sera écrasé."
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        permissionObserver = self.permissions.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        Task { await prepareStartupPermissions(); await tick() }
    }
    private func permissionScopes() -> [PermissionScope] {
        var scopes = [PermissionScope(settings: settings)]
        for value in jobs where value.status != .completed {
            let scope = PermissionScope(settings: settings, job: value)
            if !scopes.contains(scope) { scopes.append(scope) }
        }
        return scopes
    }
    private func prepareStartupPermissions() async {
        defer { preparingPermissions = false }
        guard !fatalPersistenceError else { return }
        for scope in permissionScopes() {
            await permissions.startup(scope)
            guard permissions.isReady(for: scope) else { return }
        }
        do { try ensureLocalFolders() } catch { message = error.localizedDescription }
    }
    func preparePermissions() {
        guard worker == nil, permissionTask == nil, !preparingPermissions else { return }
        preparingPermissions = true
        permissionTask = Task {
            defer { preparingPermissions = false; permissionTask = nil }
            for scope in permissionScopes() {
                await permissions.prepare(scope)
                guard permissions.isReady(for: scope) else { return }
            }
            do { try ensureLocalFolders() } catch { message = error.localizedDescription; return }
        }
    }
    func ensureLocalFolders(_ configuration: AppSettings? = nil) throws {
        let configuration = configuration ?? settings
        for path in [configuration.sourcePath, configuration.temporaryPath] {
            guard path.hasPrefix("/"), !path.hasPrefix("/Volumes/"), !path.contains("/../") else {
                throw UserFacingError("Les dossiers source et temporaire doivent être locaux, avec un chemin absolu.")
            }
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            var existing = url
            while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" { existing.deleteLastPathComponent() }
            let values = try existing.resourceValues(forKeys: [.volumeIsLocalKey])
            guard !url.path.hasPrefix("/Volumes/"), values.volumeIsLocal == true else {
                throw UserFacingError("Conversion locale obligatoire : choisissez un dossier sur ce Mac.")
            }
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    func saveSettings() {
        guard !fatalPersistenceError else { return }
        do { try ensureLocalFolders(); try settings.save() }
        catch { message = error.localizedDescription; settings.paused = true }
    }
    func applySettings(_ draft: AppSettings) {
        guard !fatalPersistenceError else { return }
        do {
            guard let url = URL(string: draft.smb.serverURL), url.scheme == "smb", url.host != nil,
                  url.password == nil, url.user == nil, url.path.split(separator: "/").count == 1 else {
                throw UserFacingError("Adresse SMB attendue : smb://serveur/partage, sans identifiants intégrés.")
            }
            try ensureLocalFolders(draft); try draft.save(); settings = draft; message = nil
        } catch { message = error.localizedDescription }
    }
    private func persist() throws {
        guard !fatalPersistenceError, let store else { throw UserFacingError("Persistance indisponible.") }
        do { try store.save(jobs) }
        catch { fatalPersistenceError = true; settings.paused = true; message = "Sauvegarde impossible : \(error.localizedDescription)"; throw error }
    }
    private func update(_ id: UUID, _ change: (inout MovieJob) -> Void) throws {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { throw UserFacingError("Tâche absente.") }
        change(&jobs[index]); jobs[index].updatedAt = Date()
        try persist()
        store?.log("\(id): \(jobs[index].status.rawValue) \(jobs[index].error ?? "")")
    }
    private func job(_ id: UUID) throws -> MovieJob {
        guard let value = jobs.first(where: { $0.id == id }) else { throw UserFacingError("Tâche absente.") }
        return value
    }
    func addMovies() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "mkv") ?? .movie]
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        if panel.runModal() == .OK { enqueue(panel.urls) }
    }
    func enqueue(_ urls: [URL]) { enqueue(urls, explicit: true) }
    private func enqueue(_ urls: [URL], explicit: Bool) {
        guard !fatalPersistenceError, let store else { return }
        for url in urls where url.pathExtension.lowercased() == "mkv" {
            do {
                let fingerprint = try FileIdentity.fingerprint(url)
                if !explicit {
                    do { if try store.isDismissed(fingerprint: fingerprint) { continue } }
                    catch {
                        fatalPersistenceError = true; settings.paused = true
                        throw error
                    }
                }
                guard !jobs.contains(where: { $0.fingerprint == fingerprint || ($0.sourcePath == url.path && $0.status != .completed) }) else { continue }
                let updated = jobs + [MovieJob(sourcePath: url.path, fingerprint: fingerprint)]
                do { try store.save(updated, explicitlyAddedFingerprints: explicit ? [fingerprint] : []) }
                catch {
                    fatalPersistenceError = true; settings.paused = true
                    throw error
                }
                jobs = updated
            } catch {
                message = "Ajout impossible : \(error.localizedDescription)"
                if fatalPersistenceError { return }
            }
        }
    }
    private func scan() {
        guard settings.watchFolder else { return }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: settings.sourcePath), includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            enqueue(files.filter { $0.pathExtension.lowercased() == "mkv" }, explicit: false)
        } catch { message = "Surveillance : \(error.localizedDescription)" }
    }
    private func ready(_ job: MovieJob) async -> Bool {
        let url = URL(fileURLWithPath: job.sourcePath)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber, let date = attributes[.modificationDate] as? Date,
              let before = try? FileIdentity.fingerprint(url) else {
            stability.reset(path: url.path); return false
        }
        guard stability.observe(path: url.path, size: size.int64Value, modified: date, now: Date()) else { return false }
        // Copies can pause: reject writable descriptors and any mutation during the lsof await.
        let safe = await Task.detached {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            process.arguments = ["-F", "a", "--", url.path]
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let output = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                return FileReadinessPolicy.isSafe(before: before, after: try? FileIdentity.fingerprint(url),
                    lsofOutput: String(decoding: output, as: UTF8.self), exitStatus: process.terminationStatus)
            } catch { return false }
        }.value
        if !safe { stability.reset(path: url.path) }
        return safe
    }
    private func requireSourceForConversion(_ id: UUID) -> Bool {
        guard let value = try? job(id) else { return false }
        guard !value.validated else { return true }
        do {
            _ = try FileIdentity.fingerprint(URL(fileURLWithPath: value.sourcePath))
            return true
        } catch {
            try? update(id) {
                $0.status = .failed; $0.needsSelection = false
                $0.error = "Le fichier source est introuvable ou inaccessible : \(value.sourcePath). Remettez le MKV à cet emplacement puis Réessayer, ou supprimez cette tâche de la liste. \(error.localizedDescription)"
            }
            candidates.removeValue(forKey: id)
            stability.reset(path: value.sourcePath)
            return false
        }
    }
    func tick() async {
        guard !ticking, !fatalPersistenceError, !preparingPermissions else { return }
        ticking = true; defer { ticking = false }
        let scope = PermissionScope(settings: settings)
        await permissions.recheck(scope)
        guard permissions.isReady(for: scope), scope == PermissionScope(settings: settings) else { return }
        scan()
        guard worker == nil, !settings.paused else { return }
        for value in jobs where value.status == .pending && !value.needsSelection {
            let jobScope = PermissionScope(settings: settings, job: value)
            await permissions.recheck(jobScope)
            guard permissions.isReady(for: jobScope) else { return }
            guard requireSourceForConversion(value.id) else { continue }
            if await ready(value) {
                guard !settings.paused, !fatalPersistenceError, worker == nil, (try? job(value.id).status) == .pending else { return }
                start(value.id); return
            }
        }
        if Date() >= serverRetryAfter, let waiting = jobs.first(where: { $0.status == .waitingForServer }) {
            let jobScope = PermissionScope(settings: settings, job: waiting)
            await permissions.recheck(jobScope)
            guard permissions.isReady(for: jobScope), !settings.paused, worker == nil else { return }
            start(waiting.id)
        }
    }
    private func start(_ id: UUID) {
        if let value = try? job(id), value.status == .pending, value.localPath == nil,
           let currentIdentity = try? FileIdentity.fingerprint(URL(fileURLWithPath: value.sourcePath)) {
            do { try update(id) { $0.fingerprint = currentIdentity } }
            catch { return }
        }
        activeID = id; progress = nil
        batch.jobStarted()
        worker = Task { [weak self] in
            guard let self else { return }
            await self.process(id)
            self.activeID = nil; self.progress = nil; self.worker = nil
            self.batch.workerFinished(remaining: self.jobs)
        }
    }
    private func process(_ id: UUID) async {
        let runSettings = settings
        var openedDocument: SublerDocument?
        do {
            var value = try job(id)
            let permissionScope = PermissionScope(settings: runSettings, job: value)
            await permissions.recheck(permissionScope)
            guard permissions.isReady(for: permissionScope) else { return }
            let source = URL(fileURLWithPath: value.sourcePath)
            if !value.validated {
                if value.localPath != nil, try FileIdentity.fingerprint(source) != value.fingerprint {
                    throw UserFacingError("Le MKV a changé depuis la conversion interrompue. Son ancien MP4 ne peut pas être réutilisé. Conservez les fichiers, puis ajoutez la nouvelle version sous un autre nom.")
                }
                var expected: MetadataCandidate?
                if let index = value.candidateIndex, let title = value.title, let year = value.year, let raw = value.candidateRaw {
                    expected = MetadataCandidate(index: index, title: title, year: year, raw: raw)
                }
                // Recover our exact Subler queue item, never process a foreign item or infer success from bytes alone.
                var recovered = false
                if let path = value.localPath, expected != nil || value.manualMetadata != nil, let state = try await subler.queueState(destination: URL(fileURLWithPath: path)) {
                    if state.lowercased().contains("working") || state.lowercased().contains("ready") {
                        try update(id) { $0.status = .paused; $0.error = "Conversion Subler interrompue ou encore active. Attendez la fin dans Subler, puis Réessayer." }
                        return
                    }
                    recovered = state.lowercased().contains("completed")
                }
                if !recovered {
                    try update(id) { $0.status = .importing; $0.error = nil }
                    let document = try await subler.prepare(source: source)
                    openedDocument = document
                    try update(id) { $0.documentID = document.id; $0.status = .prettifying }
                    try update(id) { $0.status = .fetchingMetadata }
                    let found = value.manualMetadata == nil ? try await subler.candidates(document: document) : []
                    candidates[id] = found
                    let chosen: MetadataCandidate?
                    if let expected {
                        let matching = found.filter { $0.raw == expected.raw }
                        chosen = matching.count == 1 ? matching[0] : nil
                    }
                    else { chosen = MetadataMatching.best(sourceName: source.lastPathComponent, candidates: found) }
                    guard chosen != nil || value.manualMetadata != nil else {
                        await subler.close(document: document)
                        openedDocument = nil
                        try update(id) { $0.status = .paused; $0.needsSelection = true; $0.error = found.isEmpty ? "Aucune métadonnée trouvée. Vérifiez le nom du MKV et le fournisseur dans Subler." : "Sélectionnez le film correspondant." }
                        notify(id, "Une correspondance de métadonnées nécessite votre intervention.")
                        return
                    }
                    expected = chosen
                    try ensureLocalFolders(runSettings)
                    let folder = URL(fileURLWithPath: runSettings.temporaryPath).appendingPathComponent(id.uuidString)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let output = folder.appendingPathComponent("\(UUID().uuidString).mp4")
                    let sourceSize = (try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.int64Value ?? 0
                    let space = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
                    guard space > sourceSize + sourceSize / 2 else { await subler.close(document: document); throw UserFacingError("Espace disque local insuffisant (marge de sécurité 1,5 × MKV).") }
                    try update(id) { $0.title = value.manualMetadata?.title ?? chosen?.title; $0.year = value.manualMetadata?.year ?? chosen?.year; $0.candidateIndex = chosen?.index; $0.candidateRaw = chosen?.raw; $0.localPath = output.path; $0.workRoot = runSettings.temporaryPath; $0.smbConfiguration = runSettings.smb; $0.cleanupAfterTransfer = runSettings.cleanupTemporary; $0.status = .converting; $0.needsSelection = false }
                    if let manual = value.manualMetadata {
                        try await subler.convert(document: document, manual: manual, destination: output)
                    } else if let chosen {
                        try await subler.convert(document: document, candidate: chosen, destination: output)
                    }
                    await subler.close(document: document)
                    openedDocument = nil
                }
                value = try job(id)
                guard let path = value.localPath else { throw UserFacingError("Sortie manquante.") }
                try update(id) { $0.status = .validating }
                let media: ValidatedMedia
                if let manual = value.manualMetadata {
                    guard let root = value.workRoot else { throw OutputSafetyError.invalidOwnership }
                    try await ManualMetadataWriter.apply(manual, source: source, output: URL(fileURLWithPath: path), root: URL(fileURLWithPath: root), jobID: id)
                    media = try await MediaValidationService.validate(source: source, output: URL(fileURLWithPath: path), expected: manual)
                } else if let expected {
                    media = try await MediaValidationService.validate(source: source, output: URL(fileURLWithPath: path), expected: expected)
                } else { throw UserFacingError("Titre et année requis. Transfert refusé.") }
                guard try FileIdentity.fingerprint(source) == value.fingerprint else {
                    throw UserFacingError("Le MKV a été modifié pendant le traitement. MP4 non transféré ; réessayez lorsque la copie est terminée.")
                }
                guard let workRoot = value.workRoot else { throw OutputSafetyError.invalidOwnership }
                let digest = try await GeneratedOutput.verify(url: URL(fileURLWithPath: path), source: source, root: URL(fileURLWithPath: workRoot), jobID: id)
                try update(id) { $0.title = media.title; $0.year = media.year; $0.validatedDigest = digest; $0.validated = true; $0.status = .waitingForServer }
            }
            try Task.checkCancellation()
            value = try job(id)
            guard let localPath = value.localPath, let workRoot = value.workRoot, let digest = value.validatedDigest else { throw UserFacingError("MP4 local ou preuve de validation absente. Transfert refusé.") }
            let configuration = value.smbConfiguration ?? runSettings.smb
            let mount: VerifiedMount
            do {
                do { mount = try await smb.reconnect(configuration: configuration) }
                catch {
                    try Task.checkCancellation()
                    guard case SMBError.mountFailed = error,
                          authenticationGate.begin(job: try job(id), configuration: configuration, shareIsMounted: false) else { throw error }
                    try update(id) { $0.error = "Connexion au serveur : renseignez vos identifiants dans la fenêtre macOS." }
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    mount = try await smb.reconnect(configuration: configuration, allowAuthenticationUI: true)
                }
            }
            catch is CancellationError { throw CancellationError() }
            catch {
                serverRetryAfter = Date().addingTimeInterval(60)
                try update(id) { $0.status = .waitingForServer; $0.error = "Serveur indisponible : \(error.localizedDescription). MP4 conservé localement." }
                notify(id, "Serveur indisponible. Le MP4 reste sur ce Mac.")
                return
            }
            await permissions.recheck(permissionScope)
            guard permissions.isReady(for: permissionScope) else {
                try update(id) { $0.status = .waitingForServer; $0.error = "Préparez l’accès au partage monté dans Réglages → Autorisations. Le MP4 reste sur ce Mac." }
                return
            }
            _ = try await GeneratedOutput.verify(url: URL(fileURLWithPath: localPath), source: source, root: URL(fileURLWithPath: workRoot), jobID: id, expectedDigest: digest)
            try Task.checkCancellation()
            try update(id) { $0.status = .transferring; $0.error = nil }
            let server = smb
            let replace = replacements.remove(id) != nil
            let destination = try await transfer.copy(source: URL(fileURLWithPath: localPath), mount: mount, movieName: value.displayName, jobID: id, replaceExisting: replace, expectedDigest: digest, verify: {
                let current = try await server.mountedShare(configuration: configuration)
                guard current.root == mount.root, current.origin == mount.origin else { throw UserFacingError("Montage SMB modifié pendant la copie.") }
            }, progress: { sample in
                await self.setProgress(sample)
            })
            let backup = await transfer.preservedBackup(jobID: id)
            try update(id) { $0.status = .completed; $0.destinationPath = destination.path; $0.backupPath = backup?.path; $0.error = nil; $0.conflict = false }
            hasCompletedThisSession = true
            batch.recordCompletion()
            notify(id, "\(value.displayName) est disponible sur votre serveur.")
            if let backup { store?.log("\(id): ancien MP4 conservé dans \(backup.path)") }
            if value.cleanupAfterTransfer == true {
                // Only this job's generated output, after transfer's read-back integrity check and durable completion.
                _ = try await GeneratedOutput.verify(url: URL(fileURLWithPath: localPath), source: source, root: URL(fileURLWithPath: workRoot), jobID: id, expectedDigest: digest)
                try FileManager.default.removeItem(at: URL(fileURLWithPath: localPath))
                store?.log("\(id): MP4 temporaire nettoyé après transfert vérifié.")
            }
        } catch is CancellationError {
            if let openedDocument { await subler.close(document: openedDocument) }
            let backup = await transfer.preservedBackup(jobID: id)
            try? update(id) { $0.status = .paused; $0.backupPath = backup?.path; $0.error = "Traitement suspendu. Les fichiers sont conservés." + (backup.map { " Sauvegarde : \($0.path)" } ?? "") }
        } catch {
            if let openedDocument { await subler.close(document: openedDocument) }
            let backup = await transfer.preservedBackup(jobID: id)
            let text = error.localizedDescription + (backup.map { " Sauvegarde conservée : \($0.path)" } ?? "")
            var conflict = false
            if case TransferError.conflict = error { conflict = true }
            let value = try? job(id)
            if value?.status == .completed {
                message = "Film transféré, nettoyage local impossible : \(text)"
                return
            }
            let serverMissing = (try? await smb.mountedShare(configuration: value?.smbConfiguration ?? runSettings.smb)) == nil
            let waiting = value?.validated == true && serverMissing && !conflict && !(error is OutputSafetyError)
            if waiting { serverRetryAfter = Date().addingTimeInterval(60) }
            try? update(id) { $0.status = waiting ? .waitingForServer : .failed; $0.error = text; $0.backupPath = backup?.path; $0.conflict = conflict }
            notify(id, text)
        }
    }
    func select(_ candidate: MetadataCandidate, for id: UUID) {
        guard activeID != id, let value = try? job(id), !value.validated, value.localPath == nil, requireSourceForConversion(id) else { return }
        try? update(id) { $0.manualMetadata = nil; $0.title = candidate.title; $0.year = candidate.year; $0.candidateIndex = candidate.index; $0.candidateRaw = candidate.raw; $0.needsSelection = false; $0.status = .pending; $0.error = nil }
        Task { await tick() }
    }
    /// Return an error to the form; no automatic retry on invalid input or failed persistence.
    func applyManualMetadata(title: String, year: String, for id: UUID) -> String? {
        do {
            let metadata = try ManualMovieMetadata.parse(title: title, year: year)
            let value = try job(id)
            guard activeID != id, value.canEditMetadata else {
                throw UserFacingError("La saisie est réservée aux tâches en intervention avant conversion. Une sortie existante doit être examinée avant de modifier son identité.")
            }
            guard requireSourceForConversion(id) else { return (try? job(id).error) ?? "MKV source inaccessible." }
            var updated = try job(id)
            try updated.applyManualMetadata(metadata, isActive: activeID == id)
            try update(id) { $0 = updated }
            candidates.removeValue(forKey: id)
            Task { await tick() }
            return nil
        } catch { return error.localizedDescription }
    }
    func connectServer(for id: UUID) {
        guard worker == nil, let value = try? job(id), value.validated, value.status == .waitingForServer else { return }
        authenticationGate.allowRetry(configuration: value.smbConfiguration ?? settings.smb)
        retry(id)
    }
    func retry(_ id: UUID) {
        guard activeID != id, requireSourceForConversion(id) else { return }
        serverRetryAfter = .distantPast
        try? update(id) { $0.status = $0.validated ? .waitingForServer : .pending; $0.error = nil; $0.conflict = false; $0.needsSelection = false }
        Task { await tick() }
    }
    func removeIntervention(_ id: UUID) {
        guard !fatalPersistenceError, let store else {
            message = "Suppression de la liste impossible : persistance indisponible."; return
        }
        do { _ = try InterventionRemovalPolicy.validate(id, jobs: jobs, activeID: activeID) }
        catch { message = error.localizedDescription; return }
        guard let value = try? job(id) else { return }
        let alert = NSAlert()
        alert.messageText = "Supprimer \(value.displayName) de la liste ?"
        alert.informativeText = "Seule cette tâche sera retirée de la liste. Le MKV source, les MP4 locaux, les fichiers sur le serveur et la file Subler seront intégralement conservés. La surveillance ne rajoutera pas ce MKV tant qu’il reste inchangé, même après redémarrage. Pour le traiter à nouveau, modifiez le fichier ou utilisez Ajouter des MKV."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Annuler")
        alert.addButton(withTitle: "Supprimer de la liste")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        // Modal alerts run a nested event loop: revalidate eligibility and persistence after confirmation.
        guard !fatalPersistenceError else {
            message = "Suppression de la liste impossible : persistance indisponible."; return
        }
        do { _ = try InterventionRemovalPolicy.validate(id, jobs: jobs, activeID: activeID) }
        catch { message = error.localizedDescription; return }
        do {
            let remaining = try store.removeIntervention(id, jobs: jobs, activeID: activeID)
            jobs = remaining
            candidates.removeValue(forKey: id); replacements.remove(id)
            stability.reset(path: value.sourcePath)
            message = nil
            store.log("\(id): tâche retirée de la liste ; fichiers et file Subler conservés.")
        } catch {
            // Never publish the removal or resume scanning after an uncertain persistence result.
            fatalPersistenceError = true; settings.paused = true
            message = "Suppression de la liste impossible : \(error.localizedDescription). La tâche reste affichée ; aucun fichier ni élément Subler n’a été supprimé."
        }
    }
    func ignore(_ id: UUID) {
        guard activeID != id else { return }
        try? update(id) { $0.status = .paused; $0.error = "Ignoré. MKV et MP4 locaux conservés."; $0.conflict = false; $0.needsSelection = false }
    }
    func togglePause() {
        // New jobs recheck this flag after readiness awaits.
        settings.paused.toggle(); saveSettings()
        // Pause at the job boundary: never stop Subler's shared queue or discard an in-flight transfer.
        if !settings.paused { Task { await tick() } }
    }
    func confirmReplacement(_ id: UUID) {
        guard activeID != id, let value = try? job(id), value.conflict else { return }
        let alert = NSAlert()
        alert.messageText = "Remplacer \(value.displayName) sur le serveur ?"
        alert.informativeText = "Sur SMB, le dossier existant entier (MP4, sous-titres et autres fichiers) sera conservé dans un dossier .backup. Aucun original ne sera supprimé. Le nouveau dossier ne sera publié qu’après vérification complète."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Annuler")
        alert.addButton(withTitle: "Remplacer et conserver une sauvegarde")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        replacements.insert(id); retry(id)
    }
    /// Resets only the visible batch count; completed history is kept.
    func resetBatchCounter() { batch.reset() }
    func cancelTransfer() {
        guard currentJob?.status == .transferring else { return }
        worker?.cancel()
    }
    func requestNotifications() { notifications.requestPermission() }
    private func setProgress(_ sample: TransferProgress) { progress = sample }
    func openSource() { NSWorkspace.shared.open(URL(fileURLWithPath: settings.sourcePath)) }
    func openLogs() { NSWorkspace.shared.open(AppSettings.file.deletingLastPathComponent().appendingPathComponent("automation.log")) }
    func quit() { saveSettings(); worker?.cancel(); NSApplication.shared.terminate(nil) }
    private func notify(_ id: UUID, _ text: String) {
        let category = (try? job(id).status.rawValue) ?? "error"
        notifications.send(key: id.uuidString + category, text: text, enabled: settings.notifications)
    }
}

struct UserFacingError: LocalizedError, Sendable {
    let text: String
    init(_ text: String) { self.text = text }
    var errorDescription: String? { text }
}
