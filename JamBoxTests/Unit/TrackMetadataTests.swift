import XCTest
@testable import JamBox

/// Async `Track.loadMetadata(url:)` covers real AVFoundation metadata
/// extraction. Driven off the deterministic fixtures in
/// `JamBoxTests/Fixtures/` (see `generate.sh` for the exact tag values).
///
/// The Vorbis-from-FLAC test is the highest-value case: AVFoundation's
/// `commonMetadata` is EMPTY for FLAC files, so the loader has to fall
/// back to `vorb/TITLE` etc. We regressed on this once in production.
final class TrackMetadataTests: XCTestCase {

    // Tag values baked into the fixtures by generate.sh. Any change here
    // must be mirrored in generate.sh (and re-running it).
    private let expectedTitle = "JamBox Test Tone"
    private let expectedArtist = "JamBox Test Suite"
    private let expectedAlbum = "Fixture Album"
    private let expectedTrack = 3

    func testID3FromMP3() async throws {
        guard let url = FixtureLoader.url(named: "tone", extension: "mp3") else { return }
        let track = await Track.loadMetadata(url: url)
        XCTAssertEqual(track.displayName, expectedTitle)
        XCTAssertEqual(track.artist, expectedArtist)
        XCTAssertEqual(track.album, expectedAlbum)
        XCTAssertEqual(track.trackNumber, expectedTrack)
        XCTAssertGreaterThan(track.duration, 0)
    }

    /// REGRESSION TEST: FLAC metadata via Vorbis comments.
    /// AVFoundation returns an empty `commonMetadata` for FLAC, so the
    /// `vorb/TITLE`, `vorb/ARTIST`, `vorb/ALBUM` fallbacks in
    /// `Track.loadAllMetadata` are the only source of truth. If this test
    /// fails, check `Track.swift`'s `findVorbis` implementation first.
    func testVorbisFrom16BitFLAC() async throws {
        guard let url = FixtureLoader.url(named: "tone-16", extension: "flac") else { return }
        let track = await Track.loadMetadata(url: url)
        XCTAssertEqual(
            track.displayName,
            expectedTitle,
            "Vorbis TITLE fallback failed — commonMetadata is empty for FLAC, " +
            "so the loader must read vorb/TITLE."
        )
        XCTAssertEqual(track.artist, expectedArtist, "vorb/ARTIST fallback failed")
        XCTAssertEqual(track.album, expectedAlbum, "vorb/ALBUM fallback failed")
        XCTAssertEqual(track.trackNumber, expectedTrack, "vorb/TRACKNUMBER fallback failed")
        XCTAssertGreaterThan(track.duration, 0)
    }

    /// iTunes-style tags from the m4a fixture.
    ///
    /// Note: `trackNumber` is NOT asserted here. The ffmpeg version used to
    /// generate `tone.m4a` writes an empty `trkn` atom even when passed
    /// `-metadata track="3"` (verified via AVAssetReader: identifier
    /// `itsk/trkn` surfaces but both `stringValue` and `numberValue` are
    /// nil). This is a fixture-generation limitation, not a loader bug —
    /// the ID3 path is already exercised by `testID3FromMP3`, so the
    /// production trackNumber code has coverage regardless. If we ever get
    /// a proper MP4-atom writer (AtomicParsley, MP4Box) wired into
    /// `generate.sh` we can add the trackNumber assertion back here.
    func testITunesFromM4A() async throws {
        guard let url = FixtureLoader.url(named: "tone", extension: "m4a") else { return }
        let track = await Track.loadMetadata(url: url)
        XCTAssertEqual(track.displayName, expectedTitle)
        XCTAssertEqual(track.artist, expectedArtist)
        XCTAssertEqual(track.album, expectedAlbum)
        XCTAssertGreaterThan(track.duration, 0)
    }

    /// `tone.wav` is generated with `-map_metadata -1` so it carries no
    /// tags at all. `loadMetadata` should fall back to filename for
    /// displayName and leave artist/album empty / trackNumber nil.
    func testDefaultsWhenMetadataMissing() async throws {
        guard let src = FixtureLoader.url(named: "tone", extension: "wav") else { return }

        // Copy to a temp location with a known filename so the filename
        // fallback is predictable and doesn't assert against a bundle path.
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let dest = tmpDir.appendingPathComponent("silent-sample.wav")
        try FileManager.default.copyItem(at: src, to: dest)

        let track = await Track.loadMetadata(url: dest)
        XCTAssertEqual(
            track.displayName,
            "silent-sample",
            "With no tags, displayName should fall back to filename-without-extension"
        )
        XCTAssertEqual(track.artist, "")
        XCTAssertEqual(track.album, "")
        XCTAssertNil(track.trackNumber)
        XCTAssertGreaterThan(track.duration, 0, "Duration should still be extracted from container")
    }
}
