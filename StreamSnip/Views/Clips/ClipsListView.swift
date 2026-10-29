//
//  ClipsListView.swift
//  StreamSnip
//
//  Clip library: saved clips, collections filter, sharing and playback.
//

import SwiftUI

struct ClipsListView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var clips: [Clip] = []
    @State private var collections: [ClipCollection] = []
    @State private var selectedCollectionID: UUID?
    @State private var searchText = ""
    @State private var editingClip: Clip?

    private var dataManager: DataManager? { appEnvironment?.dataManager }

    private var filteredClips: [Clip] {
        var result = clips
        if let selectedCollectionID {
            result = result.filter { clip in
                (clip.collections ?? []).contains { $0.id == selectedCollectionID }
            }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { clip in
                clip.displayTitle.lowercased().contains(query)
                    || clip.videoTitle.lowercased().contains(query)
                    || clip.authorName.lowercased().contains(query)
            }
        }
        return result
    }

    var body: some View {
        Group {
            if filteredClips.isEmpty {
                emptyView
            } else {
                List {
                    ForEach(filteredClips, id: \.id) { clip in
                        ClipRowView(clip: clip) {
                            play(clip)
                        }
                        #if !os(tvOS)
                        .swipeActions {
                            Button(role: .destructive) {
                                delete(clip)
                            } label: {
                                Label(String(localized: "common.delete"), systemImage: "trash")
                            }
                            Button {
                                editingClip = clip
                            } label: {
                                Label(String(localized: "common.edit"), systemImage: "pencil")
                            }
                        }
                        #endif
                    }
                }
            }
        }
        .navigationTitle(String(localized: "clips.title", defaultValue: "Clips"))
        #if !os(tvOS)
        .toolbarTitleDisplayMode(.inlineLarge)
        .searchable(text: $searchText, prompt: Text(String(localized: "clips.search.placeholder", defaultValue: "Search clips")))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                collectionMenu
            }
        }
        .sheet(item: $editingClip) { clip in
            ClipEditSheet(clip: clip, collections: collections) {
                loadData()
            }
        }
        #endif
        .onAppear(perform: loadData)
        .onReceive(NotificationCenter.default.publisher(for: .clipsDidChange)) { _ in
            loadData()
        }
    }

    @ViewBuilder
    private var emptyView: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            ContentUnavailableView {
                Label(String(localized: "clips.title", defaultValue: "Clips"), systemImage: "scissors")
            } description: {
                Text(String(localized: "clips.empty", defaultValue: "Mark in and out points while playing to snip a moment."))
            }
        }
    }

    private var collectionMenu: some View {
        Menu {
            Button {
                selectedCollectionID = nil
            } label: {
                Label(String(localized: "clips.collections.all", defaultValue: "All Clips"), systemImage: selectedCollectionID == nil ? "checkmark" : "")
            }
            ForEach(collections, id: \.id) { collection in
                Button {
                    selectedCollectionID = collection.id
                } label: {
                    Label(collection.name, systemImage: selectedCollectionID == collection.id ? "checkmark" : "")
                }
            }
            Divider()
            Button {
                newCollection()
            } label: {
                Label(String(localized: "clips.collections.new", defaultValue: "New Collection"), systemImage: "plus")
            }
        } label: {
            Label(String(localized: "clips.collections.filter", defaultValue: "Collections"), systemImage: "folder")
        }
    }

    private func play(_ clip: Clip) {
        appEnvironment?.playerService.openVideo(clip.toVideo(), startTime: clip.startSeconds)
    }

    private func delete(_ clip: Clip) {
        dataManager?.removeClip(clip)
        loadData()
    }

    private func newCollection() {
        dataManager?.addClipCollection(name: String(localized: "clips.collections.untitled", defaultValue: "New Collection"))
        loadData()
    }

    private func loadData() {
        clips = dataManager?.clips() ?? []
        collections = dataManager?.clipCollections() ?? []
    }
}

// MARK: - Row

struct ClipRowView: View {
    let clip: Clip
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                AsyncImage(url: clip.thumbnailURL) { image in
                    image
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fill)
                } placeholder: {
                    Color.secondary.opacity(0.2)
                }
                .frame(width: 120, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(clip.displayTitle)
                        .font(.headline)
                        .lineLimit(2)
                    Text(clip.videoTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("\(clip.formattedStart) – \(clip.formattedEnd) · \(clip.formattedDuration)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Edit Sheet

#if !os(tvOS)
struct ClipEditSheet: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.dismiss) private var dismiss

    let clip: Clip
    let collections: [ClipCollection]
    let onSave: () -> Void

    @State private var title: String = ""
    @State private var note: String = ""
    @State private var startText: String = ""
    @State private var endText: String = ""
    @State private var isExportingSegment = false

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                rangeSection
                collectionsSection
                shareSection
                #if !os(tvOS)
                exportSection
                #endif
            }
            .navigationTitle(String(localized: "clips.edit.title.navigation", defaultValue: "Edit Clip"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done")) {
                        save()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            title = clip.title
            note = clip.note ?? ""
            startText = String(Int(clip.startSeconds))
            endText = String(Int(clip.endSeconds))
        }
    }

    private var detailsSection: some View {
        Section(String(localized: "clips.edit.details", defaultValue: "Clip")) {
            TextField(String(localized: "clips.edit.title", defaultValue: "Title"), text: $title)
            TextField(String(localized: "clips.edit.note", defaultValue: "Note"), text: $note, axis: .vertical)
        }
    }

    private var rangeSection: some View {
        Section(String(localized: "clips.edit.range", defaultValue: "Range (seconds)")) {
            TextField(String(localized: "clips.edit.in", defaultValue: "In"), text: $startText)
            #if os(iOS)
                .keyboardType(.decimalPad)
            #endif
            TextField(String(localized: "clips.edit.out", defaultValue: "Out"), text: $endText)
            #if os(iOS)
                .keyboardType(.decimalPad)
            #endif
        }
    }

    private var collectionsSection: some View {
        Section(String(localized: "clips.edit.collections", defaultValue: "Collections")) {
            ForEach(collections, id: \.id) { collection in
                let isMember = (clip.collections ?? []).contains { $0.id == collection.id }
                Button {
                    toggleMembership(collection)
                } label: {
                    Label(collection.name, systemImage: isMember ? "checkmark.circle.fill" : "circle")
                }
            }
        }
    }

    private var shareSection: some View {
        Section(String(localized: "clips.edit.share", defaultValue: "Share")) {
            if let link = ClipShare.videoTimestampLink(for: clip) {
                ShareLink(item: link) {
                    Label(String(localized: "clips.share.timestampLink", defaultValue: "Share Timestamp Link"), systemImage: "link")
                }
                Button {
                    copyTimestampLink(link)
                } label: {
                    Label(String(localized: "clips.share.copyLink", defaultValue: "Copy Timestamp Link"), systemImage: "doc.on.doc")
                }
            }
            ShareLink(item: ClipShare.shareText(for: clip)) {
                Label(String(localized: "clips.share.text", defaultValue: "Share as Text"), systemImage: "text.quote")
            }
        }
    }

    #if !os(tvOS)
    private var exportSection: some View {
        Section(String(localized: "clips.edit.export", defaultValue: "Export")) {
            Button {
                guard let appEnvironment else { return }
                isExportingSegment = true
                Task {
                    await appEnvironment.clipSegmentDownloader.download(clip: clip, appEnvironment: appEnvironment)
                    isExportingSegment = false
                }
            } label: {
                Label(String(localized: "clips.export.segment", defaultValue: "Download Segment (Beta)"), systemImage: "arrow.down.circle")
            }
            .disabled(isExportingSegment)
        } footer: {
            Text(String(localized: "clips.export.segment.footer", defaultValue: "Exports the clip's range from a direct video file. Adaptive streams (HLS/DASH) and sources without partial-download support can't be exported."))
        }
    }
    #endif

    private func copyTimestampLink(_ link: URL) {
        #if os(iOS)
        UIPasteboard.general.string = link.absoluteString
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.absoluteString, forType: .string)
        #endif
        appEnvironment?.toastManager.showSuccess(
            String(localized: "clips.share.copied", defaultValue: "Link Copied")
        )
    }

    private func save() {
        let start = TimeInterval(startText) ?? clip.startSeconds
        let end = TimeInterval(endText) ?? clip.endSeconds
        guard Clip.validate(start: start, end: end) == nil else { return }
        appEnvironment?.dataManager.updateClip(
            clip,
            title: title,
            note: note.isEmpty ? nil : note,
            startSeconds: start,
            endSeconds: end
        )
        onSave()
    }

    private func toggleMembership(_ collection: ClipCollection) {
        guard let dataManager = appEnvironment?.dataManager else { return }
        let isMember = (clip.collections ?? []).contains { $0.id == collection.id }
        if isMember {
            dataManager.removeClip(clip, from: collection)
        } else {
            dataManager.addClip(clip, to: collection)
        }
    }
}
#endif

// MARK: - Deep Link Opener

/// Destination for `streamsnip://clip/<uuid>`: resolves the clip and starts
/// playback at its in-point, then shows a compact summary page.
struct ClipOpenerView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    let clipID: UUID

    @State private var clip: Clip?
    @State private var didAttemptPlay = false

    var body: some View {
        Group {
            if let clip {
                ClipRowView(clip: clip) {
                    play(clip)
                }
                .padding()
            } else if didAttemptPlay {
                ContentUnavailableView {
                    Label(String(localized: "clips.notFound.title", defaultValue: "Clip Not Found"), systemImage: "scissors")
                } description: {
                    Text(String(localized: "clips.notFound.description", defaultValue: "This clip isn't in your library."))
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(String(localized: "clips.title", defaultValue: "Clips"))
        .onAppear {
            clip = appEnvironment?.dataManager.clip(forID: clipID)
            if let clip, !didAttemptPlay {
                didAttemptPlay = true
                play(clip)
            }
            didAttemptPlay = true
        }
    }

    private func play(_ clip: Clip) {
        appEnvironment?.playerService.openVideo(clip.toVideo(), startTime: clip.startSeconds)
    }
}
