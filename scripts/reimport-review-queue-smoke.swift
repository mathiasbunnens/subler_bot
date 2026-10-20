import AppKit
import SwiftUI
import CryptoKit
@testable import AutomationCore

@main struct ReimportReviewQueueSmoke {
    @MainActor static func main() {
        setbuf(stdout, nil)
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SUBLER_AUTOMATION_TEST_ROOT"]!)
        precondition(root.path.hasPrefix(NSHomeDirectory() + "/.hermes/cache/scratch/"))
        var settings = AppSettings()
        settings.sourcePath = root.appendingPathComponent("Source").path
        settings.temporaryPath = root.appendingPathComponent("Temp").path
        settings.smb = SMBConfiguration(serverURL: "smb://fixture.invalid/Movies", username: "fixture", expectedMountPath: "/Volumes/Fixture")
        settings.watchFolder = true; settings.notifications = false; settings.paused = true
        try! settings.save()
        try! FileManager.default.createDirectory(atPath: settings.sourcePath, withIntermediateDirectories: true)
        // Exact reported identifier; .mkv is a synthetic fixture extension, not an
        // assertion about the user's real path or extension.
        let reportedName = "The.Super.Mario.Galaxy.Movie.2026.MULTI.VF2.2160p.WEBRip.iT.DV.HDR10+.x265.EAC3.5.1.Atmos2"
        let source = URL(fileURLWithPath: settings.sourcePath).appendingPathComponent(reportedName).appendingPathExtension("mkv")
        try! Data("synthetic inactive MKV fixture".utf8).write(to: source)
        let fingerprint = try! FileIdentity.fingerprint(source)
        var completed = MovieJob(sourcePath: source.path, fingerprint: fingerprint)
        completed.status = .completed
        var intervention = MovieJob(sourcePath: source.path, fingerprint: fingerprint)
        intervention.status = .paused; intervention.needsSelection = true
        let store = try! QueueStore(root: root)
        try! store.save([completed, intervention])
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let queue = JobQueueService()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            precondition(queue.activeID == nil && queue.settings.paused)
            // Completed history coexists with a removed intervention: old enqueue silently
            // rejected the explicit addition because of the completed fingerprint.
            queue.removeConfirmedIntervention(intervention.id)
            precondition(queue.jobs.map(\.id) == [completed.id])
            precondition(try! store.isDismissed(fingerprint: fingerprint))
            await queue.tick()
            precondition(queue.jobs.count == 1, "watcher must not resurrect a dismissed film")
            queue.enqueue([source])
            precondition(queue.jobs.count == 2 && queue.jobs[0].id == completed.id)
            precondition(!(try! store.isDismissed(fingerprint: fingerprint)))
            let addedID = queue.jobs[1].id
            queue.enqueue([source])
            precondition(queue.jobs.count == 2, "inactive/active duplicate must still be refused")
            precondition(queue.message!.contains("aucun second traitement"))
            queue.activeID = addedID
            queue.enqueue([source])
            precondition(queue.jobs.count == 2 && queue.activeID == addedID)
            queue.activeID = nil
            precondition((try! store.load()).map(\.id) == queue.jobs.map(\.id))
            // Model a metadata-confirmed server conflict without Apple Events/network I/O.
            let share = root.appendingPathComponent("FixtureShare")
            let directory = share.appendingPathComponent("Film (2024)")
            try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let final = directory.appendingPathComponent("Film (2024).mp4")
            try! Data("existing server fixture".utf8).write(to: final)
            let mount = VerifiedMount.fixture(root: share)
            let snapshot = try! DestinationSnapshot.capture(mount: mount, movieName: "Film (2024)")!
            queue.jobs[1].title = "Film"; queue.jobs[1].year = 2024
            queue.jobs[1].candidateIndex = 2; queue.jobs[1].candidateRaw = "Film|2024"
            queue.jobs[1].needsSelection = false; queue.jobs[1].conflict = true
            queue.jobs[1].status = .paused; queue.jobs[1].destinationSnapshot = snapshot
            queue.jobs[1].error = snapshot.summary
            try! store.save(queue.jobs)
            queue.retry(addedID)
            precondition(queue.jobs[1].status == .paused && queue.jobs[1].conflict)
            precondition(!queue.jobs[1].canEditMetadata, "do not ask for metadata again")
            precondition(try! queue.replacementReviewSnapshot(addedID, mount: mount, expected: snapshot) == snapshot)
            let before = try! Data(contentsOf: root.appendingPathComponent("jobs.json"))
            try! queue.acceptReplacement(addedID, mount: mount, reviewed: snapshot, confirmed: false)
            precondition((try! Data(contentsOf: root.appendingPathComponent("jobs.json"))) == before, "cancel must not authorize or mutate")
            precondition(queue.jobs[1].localPath == nil && queue.jobs[1].candidateIndex == 2)
            try! Data("changed server fixture".utf8).write(to: final, options: .atomic)
            precondition(try! queue.replacementReviewSnapshot(addedID, mount: mount, expected: snapshot) == nil)
            precondition(queue.jobs[1].error!.contains("changé"))
            do {
                try queue.acceptReplacement(addedID, mount: mount, reviewed: snapshot, confirmed: true)
                // A changed stored snapshot makes an obsolete modal action a no-op.
                precondition(queue.jobs[1].status == .paused && queue.jobs[1].conflict)
            } catch { preconditionFailure("Obsolete modal should be ignored: \(error)") }
            // Render the real conflict UI in both native appearances, off screen.
            queue.message = nil
            for name in [NSAppearance.Name.aqua, .darkAqua] {
                let host = NSHostingView(rootView: MenuBarView(queue: queue))
                host.appearance = NSAppearance(named: name)
                let size = host.fittingSize
                precondition(size.width > 0 && size.height > 0)
                print("REVIEW_UI_\(name.rawValue): \(size)")
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
                window.orderBack(nil)
                try? await Task.sleep(nanoseconds: 150_000_000)
                host.layoutSubtreeIfNeeded()
                let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: image)
                let path = root.appendingPathComponent("review-\(name.rawValue).png")
                try! image.representation(using: .png, properties: [:])!.write(to: path)
                print("REVIEW_UI_IMAGE: \(path.path)")
                window.orderOut(nil)
            }
            // Feed the actual validated-output executor used by runJob. No native
            // conversion is claimed: this is a digest-bound synthetic output.
            let folder = URL(fileURLWithPath: settings.temporaryPath).appendingPathComponent(addedID.uuidString)
            try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let output = folder.appendingPathComponent(UUID().uuidString + ".mp4")
            let bytes = Data(repeating: 0xBA, count: 1_100_000)
            try! bytes.write(to: output)
            queue.jobs[1].localPath = output.path; queue.jobs[1].workRoot = settings.temporaryPath
            queue.jobs[1].validated = true
            queue.jobs[1].validatedDigest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            let current = queue.jobs[1].destinationSnapshot!
            do {
                _ = try await queue.publishValidatedOutput(addedID, mount: mount, verify: {}, progress: { _ in })
                preconditionFailure("Cancellation/no consent must not publish")
            } catch TransferError.conflict {} catch { preconditionFailure("Unexpected refusal: \(error)") }
            // Same target but changed source: the old job identity cannot consent.
            try! Data("mutated fixture".utf8).write(to: source)
            do {
                try queue.acceptReplacement(addedID, mount: mount, reviewed: current, confirmed: true)
                preconditionFailure("Changed source inherited consent")
            } catch TransferError.destinationChanged {} catch { preconditionFailure("Unexpected source refusal: \(error)") }
            precondition(queue.jobs[1].conflict)
            try! Data("synthetic inactive MKV fixture".utf8).write(to: source)
            queue.jobs[1].fingerprint = try! FileIdentity.fingerprint(source)
            try! store.save(queue.jobs)
            try! queue.acceptReplacement(addedID, mount: mount, reviewed: current, confirmed: true)
            precondition(!queue.jobs[1].conflict && queue.jobs[1].status == .waitingForServer)
            precondition(queue.jobs[1].candidateIndex == 2, "confirmation must not ask for metadata again")
            precondition((try! Data(contentsOf: final)) == Data("changed server fixture".utf8), "confirmation alone must not write")
            queue.activeID = addedID; queue.jobs[1].status = .transferring
            let destination = try! await queue.publishValidatedOutput(addedID, mount: mount, verify: {}, progress: { sample in
                if sample.bytesCopied == 0 {
                    await MainActor.run {
                        queue.enqueue([source])
                        precondition(queue.jobs.count == 2 && queue.activeID == addedID)
                    }
                }
            })
            precondition(destination == final && (try! Data(contentsOf: final)) == bytes)
            precondition((try! Data(contentsOf: output)) == bytes)
            let backups = try! FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "backup" }
            precondition(backups.count == 1 && (try! Data(contentsOf: backups[0])) == Data("changed server fixture".utf8))
            queue.activeID = nil; queue.jobs[1].status = .paused
            queue.removeConfirmedIntervention(addedID)
            precondition(queue.jobs.map(\.id) == [completed.id])
            precondition((try! Data(contentsOf: source)) == Data("synthetic inactive MKV fixture".utf8))
            precondition((try! Data(contentsOf: final)) == bytes)
            queue.enqueue([source])
            precondition(queue.jobs.count == 2 && queue.activeID == nil && queue.settings.paused)
            print("REIMPORT_REVIEW_QUEUE_PASS: completed history retained, explicit reimport, watcher suppression, duplicate guard during actual transfer, cancel/no-consent refusal, stale modal, changed source refusal, confirmation -> production executor -> actual native replacement with preserved backup; metadata retained; real light/dark SwiftUI hosts; APFS scratch only, no SMB or Subler events")
            exit(0)
        }
        application.run()
    }
}
