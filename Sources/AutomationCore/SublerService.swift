import Foundation

public struct MetadataCandidate: Codable, Identifiable, Equatable, Sendable {
    public let index: Int
    public var id: Int { index }
    public let title: String
    public let year: Int
    public let raw: String
    public init(index: Int, title: String, year: Int, raw: String) {
        self.index = index; self.title = title; self.year = year; self.raw = raw
    }
}

public struct SublerDocument: Codable, Sendable {
    /// Opaque native window ID: Subler 1.9.5 advertises a document ID whose uniqueID accessor is broken.
    public let id: Int
    public init(id: Int) { self.id = id }
}

public actor SublerService {
    private var sources: [Int: URL] = [:]
    private var converting = false
    public init() {}

    public func prepare(source: URL) async throws -> SublerDocument {
        guard source.isFileURL, FileManager.default.isReadableFile(atPath: source.path) else {
            throw AutomationServiceError.message("Source is not a readable local file: \(source.path)")
        }
        let path = AppleScriptService.literal(source.path)
        let result = try await AppleScriptService.run("""
        tell application id "org.galad.Subler"
            set ownedDoc to make new document
            try
                import file (POSIX file \(path)) into ownedDoc
                prettify audio track names into ownedDoc
                set windowIDs to id of every window
                repeat with ownedWindowID in windowIDs
                    if ownedWindowID > 0 then
                        try
                            if document of window id ownedWindowID is ownedDoc then return ownedWindowID as integer
                        end try
                    end if
                end repeat
                error "Imported document has no addressable window."
            on error messageText number errorNumber
                close document doc ownedDoc
                error messageText number errorNumber
            end try
        end tell
        """)
        guard let id = Int(result) else { throw AutomationServiceError.message("Subler did not return a document ID: \(result)") }
        sources[id] = source
        return SublerDocument(id: id)
    }

    public func candidates(document: SublerDocument) async throws -> [MetadataCandidate] {
        guard sources[document.id] != nil else { throw AutomationServiceError.message("Document is not owned by this service.") }
        let result = try await AppleScriptService.run("""
        tell application id "org.galad.Subler"
            set resultsList to fetch metadata candidates into (document of window id \(document.id)) limit 50
            set resultText to ""
            repeat with resultLine in resultsList
                set resultText to resultText & (resultLine as text) & linefeed
            end repeat
            return resultText
        end tell
        """, timeout: 300)
        return result.components(separatedBy: "\n").enumerated().compactMap { offset, line in
            MetadataMatching.parse(line, index: offset + 1)
        }
    }

    public func queueState(destination: URL) async throws -> String? {
        try await queueItem(destination: destination)?.state
    }

    private func queueItem(destination: URL) async throws -> (id: String, state: String)? {
        let result = try await AppleScriptService.run("""
        tell application id "org.galad.Subler"
            set matchingIndex to 0
            repeat with queueIndex from 1 to count of queue items
                if destinationPath of queue item queueIndex is \(AppleScriptService.literal(destination.path)) then
                    if matchingIndex is not 0 then error "More than one Subler queue item matches this destination."
                    set matchingIndex to queueIndex as integer
                end if
            end repeat
            if matchingIndex is 0 then return ""
            set stateText to (status of queue item matchingIndex) as text
            return (id of queue item matchingIndex) & tab & stateText
        end tell
        """, timeout: 30)
        if result.isEmpty { return nil }
        let fields = result.components(separatedBy: "\t")
        guard fields.count == 2 else { throw AutomationServiceError.message("Invalid Subler queue response: \(result)") }
        return (fields[0], fields[1])
    }

    public func convert(document: SublerDocument, candidate: MetadataCandidate, destination: URL) async throws {
        guard !converting else { throw AutomationServiceError.message("Another conversion is already owned by this service.") }
        guard let source = sources[document.id] else { throw AutomationServiceError.message("Document is not owned by this service.") }
        guard candidate.index > 0, destination.isFileURL, destination.pathExtension.lowercased() == "mp4",
              destination.standardizedFileURL != source.standardizedFileURL else {
            throw AutomationServiceError.message("Invalid metadata index or MP4 destination.")
        }
        converting = true
        defer { converting = false }
        var ownedItem = try await queueItem(destination: destination)
        if let existing = ownedItem {
            guard ["working", "completed"].contains(existing.state) else {
                throw AutomationServiceError.message("Existing queue item for this job is \(existing.state). Review it in Subler; it will not be restarted automatically.")
            }
        } else {
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw AutomationServiceError.message("Destination already exists and will not be overwritten: \(destination.path)")
            }
            _ = try await AppleScriptService.run("""
            tell application id "org.galad.Subler"
                repeat with queueIndex from 1 to count of queue items
                    if status of queue item queueIndex is ready or status of queue item queueIndex is working then error "Subler contains a foreign ready or working queue item. Leave it untouched and retry when the queue is idle."
                end repeat
                fetch and set metadata candidate \(candidate.index) into (document of window id \(document.id))
            end tell
            """, timeout: 300)
            // The native setter searches synchronously, then schedules its merge on the main queue.
            // A separate Apple Event follows it; actual persisted tags are checked before success.
            _ = try await AppleScriptService.run("""
            tell application id "org.galad.Subler"
                repeat with queueIndex from 1 to count of queue items
                    if status of queue item queueIndex is ready or status of queue item queueIndex is working then error "Subler contains a foreign ready or working queue item; enqueue aborted."
                    if destinationPath of queue item queueIndex is \(AppleScriptService.literal(destination.path)) then error "Destination was queued concurrently; enqueue aborted."
                end repeat
                send to queue (POSIX file \(AppleScriptService.literal(destination.path))) doc (document of window id \(document.id))
            end tell
            """, timeout: 60)
            ownedItem = try await queueItem(destination: destination)
            guard let item = ownedItem, item.state == "ready" else {
                throw AutomationServiceError.message("Subler did not create the expected ready queue item for \(destination.path).")
            }
            _ = try await AppleScriptService.run("""
            tell application id "org.galad.Subler"
                set ownedIndex to 0
                repeat with queueIndex from 1 to count of queue items
                    if (id of queue item queueIndex) is \(AppleScriptService.literal(item.id)) then
                        set ownedIndex to queueIndex as integer
                    else
                        if status of queue item queueIndex is ready or status of queue item queueIndex is working then error "Foreign active queue item detected; queue will not be started."
                    end if
                end repeat
                if ownedIndex is 0 then error "Owned queue item disappeared."
                if status of queue item ownedIndex is working then return "already working"
                if status of queue item ownedIndex is not ready then error "Owned queue item is no longer ready."
                start queue
            end tell
            """, timeout: 30)
        }
        guard let ownedItem else { throw AutomationServiceError.message("Owned queue item is missing.") }
        let deadline = Date().addingTimeInterval(24 * 60 * 60)
        while true {
            try Task.checkCancellation()
            guard let current = try await queueItem(destination: destination), current.id == ownedItem.id else {
                throw AutomationServiceError.message("The exact owned queue item disappeared or was replaced. Inspect Subler before retrying.")
            }
            switch current.state {
            case "completed":
                _ = try await MediaValidationService.validate(source: source, output: destination, expected: candidate)
                return
            case "failed", "cancelled", "editing":
                throw AutomationServiceError.message("Subler queue item \(current.id) is \(current.state): \(destination.path). See Subler's log for the conversion error.")
            case "ready", "working": break
            default: throw AutomationServiceError.message("Unknown Subler queue state: \(current.state)")
            }
            guard Date() < deadline else {
                throw AutomationServiceError.message("Conversion exceeded 24 hours. The owned item has not been stopped; inspect Subler before retrying.")
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    public func close(document: SublerDocument) async {
        guard sources.removeValue(forKey: document.id) != nil else { return }
        _ = try? await AppleScriptService.run("""
        tell application id "org.galad.Subler"
            if exists (window id \(document.id)) then close document doc (document of window id \(document.id))
            repeat 100 times
                if not (exists (window id \(document.id))) then return "closed"
                delay 0.02
            end repeat
            error "Owned document did not close."
        end tell
        """, timeout: 30)
    }
}

public enum MetadataMatching {
    internal static func normalized(_ title: String) -> String {
        title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    public static func best(sourceName: String, candidates: [MetadataCandidate]) -> MetadataCandidate? {
        let stem = (sourceName as NSString).deletingPathExtension
        guard let regex = try? NSRegularExpression(pattern: "(?<![0-9])(?:18|19|20|21)[0-9]{2}(?![0-9])") else { return nil }
        let years = regex.matches(in: stem, range: NSRange(stem.startIndex..., in: stem))
        guard years.count == 1, let range = Range(years[0].range, in: stem), let year = Int(stem[range]) else { return nil }
        let title = normalized(String(stem[..<range.lowerBound]))
        let matches = candidates.filter { $0.year == year && normalized($0.title) == title }
        return matches.count == 1 ? matches[0] : nil
    }

    public static func parse(_ raw: String, index: Int) -> MetadataCandidate? {
        guard index > 0, let regex = try? NSRegularExpression(pattern: "^Movie: (.+) \\(([0-9]{4})\\)$"),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let titleRange = Range(match.range(at: 1), in: raw),
              let yearRange = Range(match.range(at: 2), in: raw), let year = Int(raw[yearRange]) else { return nil }
        let title = String(raw[titleRange]).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return MetadataCandidate(index: index, title: title, year: year, raw: raw)
    }
}
