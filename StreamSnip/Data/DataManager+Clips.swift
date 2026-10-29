//
//  DataManager+Clips.swift
//  StreamSnip
//
//  Clip and clip collection operations for DataManager.
//

import Foundation
import SwiftData

extension DataManager {
    // MARK: - Clips

    /// Saves a captured clip.
    func addClip(_ clip: Clip) {
        modelContext.insert(clip)
        save()

        cloudKitSync?.queueClipSave(clip)
        NotificationCenter.default.post(name: .clipsDidChange, object: nil)
    }

    /// Deletes a clip and queues the CloudKit deletion.
    func removeClip(_ clip: Clip) {
        let clipID = clip.id
        modelContext.delete(clip)
        save()

        cloudKitSync?.queueClipDelete(id: clipID)
        NotificationCenter.default.post(name: .clipsDidChange, object: nil)
    }

    /// Deletes a clip without queueing a CloudKit deletion.
    /// Used by CloudKitSyncEngine when applying remote deletions.
    func deleteClip(_ clip: Clip) {
        modelContext.delete(clip)
        save()
    }

    /// Inserts a clip into the database.
    /// Used by CloudKitSyncEngine for applying remote clips.
    func insertClip(_ clip: Clip) {
        let clipID = clip.id
        let descriptor = FetchDescriptor<Clip>(
            predicate: #Predicate { $0.id == clipID }
        )
        do {
            if try modelContext.fetch(descriptor).isEmpty {
                modelContext.insert(clip)
                save()
            }
        } catch {
            modelContext.insert(clip)
            save()
        }
    }

    /// Gets all clips, most recent first.
    func clips(limit: Int = 1000) -> [Clip] {
        var descriptor = FetchDescriptor<Clip>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            LoggingService.shared.logCloudKitError("Failed to fetch clips", error: error)
            return []
        }
    }

    /// Gets all clips for a video, ordered by in-point.
    func clips(forVideoID videoID: String) -> [Clip] {
        let descriptor = FetchDescriptor<Clip>(
            predicate: #Predicate { $0.videoID == videoID },
            sortBy: [SortDescriptor(\.startSeconds)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Gets a clip by its stable ID.
    func clip(forID id: UUID) -> Clip? {
        let descriptor = FetchDescriptor<Clip>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// Updates clip metadata (title, note, range) and queues a sync.
    func updateClip(_ clip: Clip, title: String, note: String?, startSeconds: Double, endSeconds: Double) {
        clip.title = title
        if clip.note != note {
            clip.note = note
            clip.noteModifiedAt = Date()
        }
        clip.startSeconds = startSeconds
        clip.endSeconds = endSeconds
        save()

        cloudKitSync?.queueClipSave(clip)
        NotificationCenter.default.post(name: .clipsDidChange, object: nil)
    }

    // MARK: - Clip Collections

    /// Creates a clip collection.
    @discardableResult
    func addClipCollection(name: String) -> ClipCollection {
        let collection = ClipCollection(name: name)
        modelContext.insert(collection)
        save()

        cloudKitSync?.queueClipCollectionSave(collection)
        NotificationCenter.default.post(name: .clipsDidChange, object: nil)
        return collection
    }

    /// Deletes a collection. Clips in it are kept.
    func removeClipCollection(_ collection: ClipCollection) {
        let collectionID = collection.id
        modelContext.delete(collection)
        save()

        cloudKitSync?.queueClipCollectionDelete(id: collectionID)
        NotificationCenter.default.post(name: .clipsDidChange, object: nil)
    }

    /// Deletes a collection without queueing a CloudKit deletion.
    func deleteClipCollection(_ collection: ClipCollection) {
        modelContext.delete(collection)
        save()
    }

    /// Inserts a collection into the database.
    /// Used by CloudKitSyncEngine for applying remote collections.
    func insertClipCollection(_ collection: ClipCollection) {
        let collectionID = collection.id
        let descriptor = FetchDescriptor<ClipCollection>(
            predicate: #Predicate { $0.id == collectionID }
        )
        do {
            if try modelContext.fetch(descriptor).isEmpty {
                modelContext.insert(collection)
                save()
            }
        } catch {
            modelContext.insert(collection)
            save()
        }
    }

    /// Gets all collections, alphabetical.
    func clipCollections() -> [ClipCollection] {
        let descriptor = FetchDescriptor<ClipCollection>(
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Gets a collection by its stable ID.
    func clipCollection(forID id: UUID) -> ClipCollection? {
        let descriptor = FetchDescriptor<ClipCollection>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// Adds a clip to a collection and queues a sync for both sides.
    func addClip(_ clip: Clip, to collection: ClipCollection) {
        var collections = clip.collections ?? []
        guard !collections.contains(where: { $0.id == collection.id }) else { return }
        collections.append(collection)
        clip.collections = collections
        save()

        cloudKitSync?.queueClipSave(clip)
        NotificationCenter.default.post(name: .clipsDidChange, object: nil)
    }

    /// Removes a clip from a collection and queues a sync.
    func removeClip(_ clip: Clip, from collection: ClipCollection) {
        clip.collections = (clip.collections ?? []).filter { $0.id != collection.id }
        save()

        cloudKitSync?.queueClipSave(clip)
        NotificationCenter.default.post(name: .clipsDidChange, object: nil)
    }
}
