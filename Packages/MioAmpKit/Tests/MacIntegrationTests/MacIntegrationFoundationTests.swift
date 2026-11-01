import Contracts
import Foundation
import Library
import MacIntegration
import Testing

@Test func macIntegrationTargetLoads() {
    #expect(MacIntegrationModule.isPrototypeImplemented)
}

@Test func commandsPreparePlayTraverseAndPersist() async throws {
    let tracks = makeTracks(2)
    let entries = tracks.map { QueueEntry(trackID: $0.id) }
    let queue = ProductionQueueStore(snapshot: QueueSnapshot(entries: entries, tracks: Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) }), selectedEntryID: entries[0].id, repeatMode: .one))
    let engine = CoordinatorEngine()
    let sessions = MemorySessions()
    let coordinator = ProductionPlaybackCoordinator(queue: queue, importer: EmptyImporter(), access: GrantedAccess(), engine: engine, sessions: sessions, decoderFactory: { _ in SilenceDecoder() })

    await coordinator.send(.play)
    #expect(await engine.played.count == 1)
    #expect(await queue.snapshot().playingEntryID == entries[0].id)
    #expect(await coordinator.queueSnapshot().entries == entries)

    await coordinator.send(.next)
    #expect(await queue.snapshot().playingEntryID == entries[1].id)
    #expect(await engine.preparedEntries == [entries[0].id, entries[1].id])
    #expect(await sessions.saved?.currentEntryID == entries[1].id)
}

@Test func seekFinishesBeforeFollowingPauseAndPlayCommands() async throws {
    let track = makeTracks(1)[0]
    let entry = QueueEntry(trackID: track.id)
    let queue = ProductionQueueStore(snapshot: QueueSnapshot(
        entries: [entry],
        tracks: [track.id: track],
        selectedEntryID: entry.id
    ))
    let engine = BlockingSeekEngine()
    let coordinator = ProductionPlaybackCoordinator(
        queue: queue,
        importer: EmptyImporter(),
        access: GrantedAccess(),
        engine: engine,
        sessions: MemorySessions(),
        decoderFactory: { _ in SilenceDecoder() }
    )

    await coordinator.send(.play)
    let seek = Task { await coordinator.send(.seek(to: 1)) }
    while !(await engine.didStartSeek) { await Task.yield() }
    let pause = Task { await coordinator.send(.pause) }
    let play = Task { await coordinator.send(.play) }
    try await Task.sleep(for: .milliseconds(20))
    #expect(await engine.operations.suffix(1) == ["seek-start"])

    await engine.finishSeek()
    await seek.value
    await pause.value
    await play.value
    // Independent Tasks may reach the coordinator in either order. The contract
    // here is that neither command overtakes the seek, not Task launch ordering.
    let tail = Array(await engine.operations.suffix(3))
    #expect(tail.first == "seek-end")
    #expect(tail.dropFirst().sorted() == ["pause", "play"])
}

@Test func staleEventsCannotMutatePlaybackAndMatchingTransitionCommits() async throws {
    let tracks = makeTracks(2)
    let entries = tracks.map { QueueEntry(trackID: $0.id) }
    let queue = ProductionQueueStore(snapshot: QueueSnapshot(entries: entries, tracks: Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) }), selectedEntryID: entries[0].id))
    let engine = CoordinatorEngine()
    let coordinator = ProductionPlaybackCoordinator(queue: queue, importer: EmptyImporter(), access: GrantedAccess(), engine: engine, sessions: MemorySessions(), decoderFactory: { _ in SilenceDecoder() })
    var iterator = coordinator.snapshots.makeAsyncIterator()
    _ = await iterator.next()

    await coordinator.send(.play)
    let currentGeneration = try #require(await engine.current?.generation)
    let staged = try #require(await engine.next)
    await engine.emit(.position(99, generation: PlaybackGeneration(rawValue: currentGeneration.rawValue + 100)))
    await engine.emit(.transitioned(entryID: staged.entryID, generation: PlaybackGeneration(rawValue: staged.generation.rawValue + 100)))
    try await Task.sleep(for: .milliseconds(20))
    #expect(await queue.snapshot().playingEntryID == entries[0].id)

    await engine.emit(.transitioned(entryID: staged.entryID, generation: staged.generation))
    try await Task.sleep(for: .milliseconds(20))
    #expect(await queue.snapshot().playingEntryID == entries[1].id)
}

@Test func malformedQueueStopsAfterOneTraversal() async throws {
    let tracks = makeTracks(3)
    let entries = tracks.map { QueueEntry(trackID: $0.id) }
    let queue = ProductionQueueStore(snapshot: QueueSnapshot(entries: entries, tracks: Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) }), repeatMode: .all))
    let attempts = AttemptCounter()
    let coordinator = ProductionPlaybackCoordinator(queue: queue, importer: EmptyImporter(), access: GrantedAccess(), engine: CoordinatorEngine(), sessions: MemorySessions(), decoderFactory: { _ in
        await attempts.increment()
        throw PlaybackFailure(code: .corrupt, message: "bad fixture")
    })
    var iterator = coordinator.snapshots.makeAsyncIterator()
    _ = await iterator.next()
    await coordinator.send(.play)
    #expect(await attempts.value == 3)
    var latest: PlaybackSnapshot?
    while let snapshot = await iterator.next() {
        latest = snapshot
        if case .failed = snapshot.state { break }
    }
    guard case .failed(let failure) = latest?.state else { Issue.record("Expected terminal failure"); return }
    #expect(failure.code == .corrupt)
}

@Test func restoredSessionPublishesPausedAndDoesNotTouchEngine() async throws {
    let tracks = makeTracks(1)
    let entry = QueueEntry(trackID: tracks[0].id)
    let state = SessionState(queue: [entry], tracks: tracks, currentEntryID: entry.id, position: 17, volume: 0.4)
    let queue = ProductionQueueStore(snapshot: QueueSnapshot(entries: [entry], tracks: [tracks[0].id: tracks[0]], selectedEntryID: entry.id, playingEntryID: entry.id))
    let engine = CoordinatorEngine()
    let coordinator = ProductionPlaybackCoordinator(queue: queue, importer: EmptyImporter(), access: GrantedAccess(), engine: engine, sessions: MemorySessions(), restoredSession: state, decoderFactory: { _ in SilenceDecoder() })
    var iterator = coordinator.snapshots.makeAsyncIterator()
    let first = try #require(await iterator.next())
    #expect(first.state == .paused)
    #expect(first.position == 17)
    #expect(first.volume == 0.4)
    #expect(await engine.preparedEntries.isEmpty)
}

@Test func queueUndoAndPresentationChangesPersistThroughCoordinator() async throws {
    let tracks = makeTracks(2)
    let entries = tracks.map { QueueEntry(trackID: $0.id) }
    let snapshot = QueueSnapshot(
        entries: entries,
        tracks: Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) }),
        selectedEntryID: entries[1].id
    )
    let queue = ProductionQueueStore(snapshot: snapshot)
    let sessions = MemorySessions()
    let coordinator = ProductionPlaybackCoordinator(
        queue: queue,
        importer: EmptyImporter(),
        access: GrantedAccess(),
        engine: CoordinatorEngine(),
        sessions: sessions,
        decoderFactory: { _ in SilenceDecoder() }
    )

    await coordinator.send(.remove([entries[1].id]))
    #expect(await coordinator.queueSnapshot().entries.count == 1)
    #expect(await coordinator.undoLastQueueMutation())
    #expect(await coordinator.queueSnapshot().entries == entries)

    let layout = WindowLayout(scale: 1.25, isCompact: true)
    await coordinator.updatePresentationState(skinID: "terminal", windowLayout: layout)
    #expect(await sessions.saved?.skinID == "terminal")
    #expect(await sessions.saved?.windowLayout == layout)
}

@Test func partialImportPublishesNoticeAndKeepsValidTracks() async throws {
    let track = makeTracks(1)[0]
    let missing = URL(fileURLWithPath: "/tmp/missing-song.mp3")
    let queue = ProductionQueueStore()
    let coordinator = ProductionPlaybackCoordinator(
        queue: queue,
        importer: PartialImporter(track: track, failure: FileImportFailure(url: missing, reason: "Missing file")),
        access: GrantedAccess(),
        engine: CoordinatorEngine(),
        sessions: MemorySessions(),
        decoderFactory: { _ in SilenceDecoder() }
    )
    var notices = coordinator.notices.makeAsyncIterator()

    await coordinator.send(.append([track.lastKnownURL, missing]))

    #expect(await coordinator.queueSnapshot().entries.count == 1)
    let notice = try #require(await notices.next())
    #expect(notice.contains("Skipped 1 playlist item"))
    #expect(notice.contains("missing-song.mp3"))
}

@Test func clearQueueStopsPlaybackPersistsEmptyStateAndCanUndo() async throws {
    let tracks = makeTracks(2)
    let entries = tracks.map { QueueEntry(trackID: $0.id) }
    let queue = ProductionQueueStore(snapshot: QueueSnapshot(
        entries: entries,
        tracks: Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) }),
        selectedEntryID: entries[0].id
    ))
    let engine = CoordinatorEngine()
    let sessions = MemorySessions()
    let coordinator = ProductionPlaybackCoordinator(
        queue: queue,
        importer: EmptyImporter(),
        access: GrantedAccess(),
        engine: engine,
        sessions: sessions,
        decoderFactory: { _ in SilenceDecoder() }
    )
    await coordinator.send(.play)

    await coordinator.clearQueue()

    #expect(await coordinator.queueSnapshot().entries.isEmpty)
    #expect(await sessions.saved?.queue.isEmpty == true)
    #expect(await engine.stopped.count == 1)
    #expect(await coordinator.undoLastQueueMutation())
    #expect(await coordinator.queueSnapshot().entries == entries)
}

private func makeTracks(_ count: Int) -> [TrackReference] {
    (0..<count).map { TrackReference(lastKnownURL: URL(fileURLWithPath: "/tmp/coordinator-\($0).wav"), metadata: .loaded(TrackMetadata(duration: 60))) }
}

private actor SilenceDecoder: Decoder {
    var format: AudioFormatDescription { AudioFormatDescription(codec: "test", sampleRate: 48_000, channelCount: 2, frameCount: 2_880_000) }
    func seek(toFrame frame: Int64) throws { _ = frame }
    func read(maxFrames: Int) -> PCMChunk { PCMChunk(interleavedSamples: [], frameCount: 0, isEndOfStream: true) }
}

private actor TestLease: FileAccessLease {
    nonisolated let url: URL
    init(_ url: URL) { self.url = url }
    func release() {}
}

private struct GrantedAccess: FileAccessService {
    func bookmark(for url: URL) async throws -> Data { Data() }
    func resolve(_ track: TrackReference) async throws -> FileAccessResolution { .granted(TestLease(track.lastKnownURL)) }
}

private struct EmptyImporter: PlaybackURLImporting {
    func importURLs(_ urls: [URL]) async -> FileImportResult { FileImportResult(tracks: [], failures: []) }
}

private struct PartialImporter: PlaybackURLImporting {
    let track: TrackReference
    let failure: FileImportFailure
    func importURLs(_ urls: [URL]) async -> FileImportResult {
        FileImportResult(tracks: [track], failures: [failure])
    }
}

private actor MemorySessions: SessionStore {
    var saved: SessionState?
    func load() async throws -> SessionState? { saved }
    func save(_ state: SessionState) async throws { saved = state }
}

private actor AttemptCounter {
    var value = 0
    func increment() { value += 1 }
}

private actor CoordinatorEngine: AudioEngineClient {
    nonisolated let events: AsyncStream<AudioEngineEvent>
    private let continuation: AsyncStream<AudioEngineEvent>.Continuation
    var current: AudioTrackPreparation?
    var next: AudioTrackPreparation?
    var preparedEntries: [QueueEntryID] = []
    var played: [PlaybackGeneration] = []
    var stopped: [PlaybackGeneration] = []

    init() {
        let stream = AsyncStream.makeStream(of: AudioEngineEvent.self)
        events = stream.stream
        continuation = stream.continuation
    }
    func prepare(current: AudioTrackPreparation, next: AudioTrackPreparation?) async throws {
        self.current = current; self.next = next; preparedEntries.append(current.entryID)
    }
    func updateNext(_ next: AudioTrackPreparation?) async throws { self.next = next }
    func play(generation: PlaybackGeneration) async throws { played.append(generation) }
    func pause(generation: PlaybackGeneration) async {}
    func stop(generation: PlaybackGeneration) async { stopped.append(generation) }
    func seek(to time: TimeInterval, generation: PlaybackGeneration) async throws {}
    func setVolume(_ volume: Double) async {}
    func setEqualizer(_ settings: EQSettings) async {}
    func emit(_ event: AudioEngineEvent) { continuation.yield(event) }
}

private actor BlockingSeekEngine: AudioEngineClient {
    nonisolated let events: AsyncStream<AudioEngineEvent>
    nonisolated let visualizationFeatures = AsyncStream<VisualizationFeatures> { $0.finish() }
    private var seekContinuation: CheckedContinuation<Void, Never>?
    private(set) var operations: [String] = []
    private(set) var didStartSeek = false

    init() {
        events = AsyncStream { _ in }
    }

    func prepare(current: AudioTrackPreparation, next: AudioTrackPreparation?) async throws {
        _ = current; _ = next
        operations.append("prepare")
    }
    func updateNext(_ next: AudioTrackPreparation?) async throws { _ = next }
    func play(generation: PlaybackGeneration) async throws { _ = generation; operations.append("play") }
    func pause(generation: PlaybackGeneration) async { _ = generation; operations.append("pause") }
    func stop(generation: PlaybackGeneration) async { _ = generation; operations.append("stop") }
    func seek(to time: TimeInterval, generation: PlaybackGeneration) async throws {
        _ = time; _ = generation
        didStartSeek = true
        operations.append("seek-start")
        await withCheckedContinuation { seekContinuation = $0 }
        operations.append("seek-end")
    }
    func finishSeek() {
        seekContinuation?.resume()
        seekContinuation = nil
    }
    func setVolume(_ volume: Double) async { _ = volume }
    func setEqualizer(_ settings: EQSettings) async { _ = settings }
    func setVisualizationActive(_ active: Bool) async { _ = active }
}
