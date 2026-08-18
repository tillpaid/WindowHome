import Foundation

enum ProfileStoreError: LocalizedError {
    case applicationSupportDirectoryUnavailable
    case readFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .applicationSupportDirectoryUnavailable: "WindowHome could not find its Application Support directory."
        case .readFailed: "WindowHome could not read saved home positions."
        case .writeFailed: "WindowHome could not save the home position."
        }
    }
}

final class ProfileStore {
    static let maximumHistoryCount = 20

    private var profiles: [WindowProfile] = []
    private let fileManager: FileManager
    private let fileURL: URL

    init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        guard let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ProfileStoreError.applicationSupportDirectoryUnavailable
        }
        fileURL = applicationSupportURL.appendingPathComponent("WindowHome", isDirectory: true).appendingPathComponent("profiles.json")
        try load()
    }

    init(fileURL: URL, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.fileURL = fileURL
        try load()
    }

    func profile(bundleIdentifier: String, displayFingerprint: DisplayFingerprint) -> WindowProfile? {
        profileIndex(bundleIdentifier: bundleIdentifier, displayFingerprint: displayFingerprint).map { profiles[$0] }
    }

    func upsert(_ profile: WindowProfile) throws {
        let previousProfiles = profiles
        if let index = profileIndex(bundleIdentifier: profile.bundleIdentifier, displayFingerprint: profile.displayFingerprint) {
            let current = profiles[index]
            var history = current.history
            var future = current.future
            if current.geometry != profile.geometry {
                history.append(HomePositionRevision(geometry: current.geometry, savedAt: current.updatedAt))
                history = Array(history.suffix(Self.maximumHistoryCount))
                future = []
            }
            profiles[index] = WindowProfile(
                id: profile.id,
                bundleIdentifier: profile.bundleIdentifier,
                applicationName: profile.applicationName,
                displayFingerprint: profile.displayFingerprint,
                displayName: profile.displayName,
                geometry: profile.geometry,
                updatedAt: profile.updatedAt,
                history: history,
                future: future
            )
        } else {
            profiles.append(profile)
        }
        do {
            try persist()
        } catch {
            profiles = previousProfiles
            throw error
        }
    }

    func undoProfile(bundleIdentifier: String, displayFingerprint: DisplayFingerprint) throws -> WindowProfile? {
        guard let index = profileIndex(bundleIdentifier: bundleIdentifier, displayFingerprint: displayFingerprint),
              let revision = profiles[index].history.last else {
            return nil
        }

        let previousProfiles = profiles
        let current = profiles[index]
        var future = current.future
        future.append(HomePositionRevision(geometry: current.geometry, savedAt: current.updatedAt))
        future = Array(future.suffix(Self.maximumHistoryCount))
        profiles[index] = WindowProfile(
            id: current.id,
            bundleIdentifier: current.bundleIdentifier,
            applicationName: current.applicationName,
            displayFingerprint: current.displayFingerprint,
            displayName: current.displayName,
            geometry: revision.geometry,
            updatedAt: revision.savedAt,
            history: Array(current.history.dropLast()),
            future: future
        )
        do {
            try persist()
        } catch {
            profiles = previousProfiles
            throw error
        }
        return profiles[index]
    }

    func redoProfile(bundleIdentifier: String, displayFingerprint: DisplayFingerprint) throws -> WindowProfile? {
        guard let index = profileIndex(bundleIdentifier: bundleIdentifier, displayFingerprint: displayFingerprint),
              let revision = profiles[index].future.last else {
            return nil
        }

        let previousProfiles = profiles
        let current = profiles[index]
        var history = current.history
        history.append(HomePositionRevision(geometry: current.geometry, savedAt: current.updatedAt))
        history = Array(history.suffix(Self.maximumHistoryCount))
        profiles[index] = WindowProfile(
            id: current.id,
            bundleIdentifier: current.bundleIdentifier,
            applicationName: current.applicationName,
            displayFingerprint: current.displayFingerprint,
            displayName: current.displayName,
            geometry: revision.geometry,
            updatedAt: revision.savedAt,
            history: history,
            future: Array(current.future.dropLast())
        )
        do {
            try persist()
        } catch {
            profiles = previousProfiles
            throw error
        }
        return profiles[index]
    }

    private func profileIndex(bundleIdentifier: String, displayFingerprint: DisplayFingerprint) -> Int? {
        if let exactMatch = profiles.firstIndex(where: {
            $0.bundleIdentifier == bundleIdentifier && $0.displayFingerprint == displayFingerprint
        }) {
            return exactMatch
        }

        return profiles.indices
            .filter {
                profiles[$0].bundleIdentifier == bundleIdentifier
                    && profiles[$0].displayFingerprint.identifiesSameHomeDisplay(as: displayFingerprint)
            }
            .max { profiles[$0].updatedAt < profiles[$1].updatedAt }
    }

    private func load() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        guard let decoded = try? JSONDecoder().decode([WindowProfile].self, from: Data(contentsOf: fileURL)) else {
            throw ProfileStoreError.readFailed
        }
        profiles = decoded
        if mergeBuiltInDisplayProfiles() {
            try persist()
        }
    }

    /// Older versions keyed every display mode independently. Collapse only the
    /// built-in display's mode variants so Say No to Notch has one shared Home.
    /// The newest position wins; previous positions remain reachable through Undo.
    private func mergeBuiltInDisplayProfiles() -> Bool {
        var mergedProfiles: [WindowProfile] = []
        var processedProfileIDs = Set<UUID>()
        var didMerge = false

        for profile in profiles {
            guard processedProfileIDs.insert(profile.id).inserted else { continue }
            guard profile.displayFingerprint.isBuiltIn else {
                mergedProfiles.append(profile)
                continue
            }

            let relatedProfiles = profiles.filter {
                $0.bundleIdentifier == profile.bundleIdentifier
                    && $0.displayFingerprint.identifiesSameHomeDisplay(as: profile.displayFingerprint)
            }
            processedProfileIDs.formUnion(relatedProfiles.map(\.id))

            guard relatedProfiles.count > 1,
                  let newestProfile = relatedProfiles.max(by: { $0.updatedAt < $1.updatedAt }) else {
                mergedProfiles.append(profile)
                continue
            }

            let historicalPositions = relatedProfiles.flatMap { candidate -> [HomePositionRevision] in
                let ownPosition = candidate.id == newestProfile.id
                    ? []
                    : [HomePositionRevision(geometry: candidate.geometry, savedAt: candidate.updatedAt)]
                return candidate.history + ownPosition
            }
            .filter { $0.geometry != newestProfile.geometry }
            .sorted { $0.savedAt < $1.savedAt }

            let mergedHistory = Array(historicalPositions.suffix(Self.maximumHistoryCount))
            mergedProfiles.append(WindowProfile(
                id: newestProfile.id,
                bundleIdentifier: newestProfile.bundleIdentifier,
                applicationName: newestProfile.applicationName,
                displayFingerprint: newestProfile.displayFingerprint,
                displayName: newestProfile.displayName,
                geometry: newestProfile.geometry,
                updatedAt: newestProfile.updatedAt,
                history: mergedHistory,
                future: []
            ))
            didMerge = true
        }

        if didMerge {
            profiles = mergedProfiles
        }
        return didMerge
    }

    private func persist() throws {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(profiles).write(to: fileURL, options: .atomic)
        } catch {
            throw ProfileStoreError.writeFailed
        }
    }
}
