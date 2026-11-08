import XCTest
@testable import OpenfyCore

final class MetadataTests: XCTestCase {
    var dir: URL!

    override func setUp() { dir = Fixtures.tempDir() }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testFLAC24_96WithVorbisCommentsAndPicture() throws {
        let wav = dir.appendingPathComponent("src.wav")
        Fixtures.wav(at: wav, sampleRate: 96_000, bits: 24, seconds: 1)
        let flac = dir.appendingPathComponent("song.flac")
        Fixtures.convert(wav, to: flac, fileFormat: "flac", dataFormat: "flac")
        let png = Fixtures.png()
        Fixtures.tagFLAC(flac, comments: [
            "TITLE=Só Tu", "ARTIST=Artist A", "ARTIST=Artist B", "ALBUMARTIST=The Band",
            "ALBUM=Great Album", "TRACKNUMBER=3/12", "DISCNUMBER=2", "DISCTOTAL=2",
            "DATE=1999-04-01", "GENRE=Jazz",
        ], picture: png)

        let result = try XCTUnwrap(FLACReader.read(url: flac))
        let info = try XCTUnwrap(result.streamInfo)
        XCTAssertEqual(info.sampleRate, 96_000)
        XCTAssertEqual(info.bitsPerSample, 24)
        XCTAssertEqual(info.channels, 2)
        XCTAssertEqual(info.duration, 1, accuracy: 0.01)

        let t = result.tags
        XCTAssertEqual(t.title, "Só Tu")
        XCTAssertEqual(t.artist, "Artist A, Artist B")
        XCTAssertEqual(t.albumArtist, "The Band")
        XCTAssertEqual(t.album, "Great Album")
        XCTAssertEqual(t.trackNumber, 3)
        XCTAssertEqual(t.trackTotal, 12)
        XCTAssertEqual(t.discNumber, 2)
        XCTAssertEqual(t.discTotal, 2)
        XCTAssertEqual(t.year, 1999)
        XCTAssertEqual(t.genre, "Jazz")
        XCTAssertEqual(t.artwork, png)

        // Full pipeline: AudioToolbox must still decode the rewritten file.
        let (track, art) = try XCTUnwrap(MetadataReader.read(url: flac, fileSize: 1, modified: Date()))
        XCTAssertEqual(track.codec, .flac)
        XCTAssertEqual(track.sampleRate, 96_000)
        XCTAssertEqual(track.bitDepth, 24)
        XCTAssertEqual(track.quality, .hiRes)
        XCTAssertEqual(track.qualityLabel, "24-bit / 96 kHz")
        XCTAssertEqual(track.compactQuality, "FLAC 24/96")
        XCTAssertEqual(track.albumArtist, "The Band")
        XCTAssertNotNil(art)
    }

    func testCDQualityALACAndLossyAAC() throws {
        let wav = dir.appendingPathComponent("src.wav")
        Fixtures.wav(at: wav, sampleRate: 44_100, bits: 16, seconds: 1)

        let alac = dir.appendingPathComponent("a.m4a")
        Fixtures.convert(wav, to: alac, fileFormat: "m4af", dataFormat: "alac")
        let (t1, _) = try XCTUnwrap(MetadataReader.read(url: alac, fileSize: 1, modified: Date()))
        XCTAssertEqual(t1.codec, .alac)
        XCTAssertEqual(t1.bitDepth, 16)
        XCTAssertEqual(t1.sampleRate, 44_100)
        XCTAssertEqual(t1.quality, .cd)

        let aac = dir.appendingPathComponent("b.m4a")
        Fixtures.convert(wav, to: aac, fileFormat: "m4af", dataFormat: "aac")
        let (t2, _) = try XCTUnwrap(MetadataReader.read(url: aac, fileSize: 1, modified: Date()))
        XCTAssertEqual(t2.codec, .aac)
        XCTAssertNil(t2.bitDepth)
        XCTAssertEqual(t2.quality, .lossy)
        XCTAssertNotNil(t2.bitrate)
    }

    func testM4ATags() throws {
        let png = Fixtures.png()
        let bytes = Fixtures.syntheticM4A(items: [
            ("\u{A9}nam", Array("Track Title".utf8), 1),
            ("\u{A9}ART", Array("Some Artist".utf8), 1),
            ("aART", Array("Album Artist".utf8), 1),
            ("\u{A9}alb", Array("An Album".utf8), 1),
            ("\u{A9}day", Array("2012-01-01T00:00:00Z".utf8), 1),
            ("trkn", [0, 0, 0, 5, 0, 10, 0, 0], 0),
            ("disk", [0, 0, 0, 1, 0, 2], 0),
            ("gnre", [0, 18], 0), // ID3 genre index 17 + 1 = Rock
            ("covr", [UInt8](png), 14),
        ])
        let m4a = dir.appendingPathComponent("t.m4a")
        try Data(bytes).write(to: m4a)

        let t = try XCTUnwrap(MP4Reader.read(url: m4a))
        XCTAssertEqual(t.title, "Track Title")
        XCTAssertEqual(t.artist, "Some Artist")
        XCTAssertEqual(t.albumArtist, "Album Artist")
        XCTAssertEqual(t.album, "An Album")
        XCTAssertEqual(t.year, 2012)
        XCTAssertEqual(t.trackNumber, 5)
        XCTAssertEqual(t.trackTotal, 10)
        XCTAssertEqual(t.discNumber, 1)
        XCTAssertEqual(t.discTotal, 2)
        XCTAssertEqual(t.genre, "Rock")
        XCTAssertEqual(t.artwork, png)
    }

    func testID3v23UTF16() throws {
        let tag = Fixtures.id3Tag(major: 3, frames: [
            Fixtures.id3Text("TIT2", "Canção", v4: false),
            Fixtures.id3Text("TPE1", "Artista", v4: false),
            Fixtures.id3Text("TPE2", "Banda", v4: false),
            Fixtures.id3Text("TALB", "Álbum", v4: false),
            Fixtures.id3Text("TRCK", "07/14", v4: false),
            Fixtures.id3Text("TPOS", "1/2", v4: false),
            Fixtures.id3Text("TYER", "1987", v4: false),
            Fixtures.id3Text("TCON", "(17)", v4: false),
        ])
        let t = try XCTUnwrap(ID3Reader.parse(tag))
        XCTAssertEqual(t.title, "Canção")
        XCTAssertEqual(t.artist, "Artista")
        XCTAssertEqual(t.albumArtist, "Banda")
        XCTAssertEqual(t.album, "Álbum")
        XCTAssertEqual(t.trackNumber, 7)
        XCTAssertEqual(t.trackTotal, 14)
        XCTAssertEqual(t.discNumber, 1)
        XCTAssertEqual(t.year, 1987)
        XCTAssertEqual(t.genre, "Rock")
    }

    /// Remasters/reissues (e.g. a 2016 reissue of a 1993 album) keep the original year in a separate tag.
    func testOriginalReleaseYearWinsOverReissueDate() throws {
        var vorbis = TagData()
        FLACReader.applyVorbisFields(["DATE": ["2016-04-01"], "YEAR": ["2016"], "ORIGINALDATE": ["1993-02-22"]], to: &vorbis)
        XCTAssertEqual(vorbis.year, 1993)
        var vorbisYearOnly = TagData()
        FLACReader.applyVorbisFields(["DATE": ["2016-04-01"], "ORIGINALYEAR": ["1997"]], to: &vorbisYearOnly)
        XCTAssertEqual(vorbisYearOnly.year, 1997)
        var plain = TagData()
        FLACReader.applyVorbisFields(["DATE": ["2011-03-28"], "ORIGINALDATE": [""]], to: &plain)
        XCTAssertEqual(plain.year, 2011, "an empty original date falls back to DATE")
        var dupes = TagData()
        FLACReader.applyVorbisFields(["ARTIST": ["Radiohead", "RADIOHEAD"]], to: &dupes)
        XCTAssertEqual(dupes.artist, "Radiohead")

        // ID3: TDRC comes before TDOR in the file, the original date still wins.
        let v4 = try XCTUnwrap(ID3Reader.parse(Fixtures.id3Tag(major: 4, frames: [
            Fixtures.id3Text("TDRC", "2016-04-01", v4: true),
            Fixtures.id3Text("TDOR", "1994-11-29", v4: true),
        ])))
        XCTAssertEqual(v4.year, 1994)
        let v3 = try XCTUnwrap(ID3Reader.parse(Fixtures.id3Tag(major: 3, frames: [
            Fixtures.id3Text("TORY", "2003", v4: false),
            Fixtures.id3Text("TYER", "2016", v4: false),
        ])))
        XCTAssertEqual(v3.year, 2003)

        let m4a = dir.appendingPathComponent("reissue.m4a")
        try Data(Fixtures.syntheticM4A(items: [("\u{A9}day", Array("2017-06-23".utf8), 1)],
                                       freeform: [("ORIGINALDATE", "1997-05-21")])).write(to: m4a)
        XCTAssertEqual(try XCTUnwrap(MP4Reader.read(url: m4a)).year, 1997)
    }

    func testID3v24WithFrontCoverPreferred() throws {
        let back = Fixtures.png(red: 0.1), front = Fixtures.png(red: 0.9)
        func apic(_ type: UInt8, _ data: Data) -> [UInt8] {
            Fixtures.id3Frame("APIC", [3] + Array("image/png".utf8) + [0, type] + Array("d".utf8) + [0] + [UInt8](data), v4: true)
        }
        let tag = Fixtures.id3Tag(major: 4, frames: [
            Fixtures.id3Text("TIT2", "Title", v4: true),
            Fixtures.id3Text("TDRC", "2020-02-02", v4: true),
            Fixtures.id3Text("TCON", "Electronic", v4: true),
            apic(4, back),
            apic(3, front),
        ])
        let t = try XCTUnwrap(ID3Reader.parse(tag))
        XCTAssertEqual(t.title, "Title")
        XCTAssertEqual(t.year, 2020)
        XCTAssertEqual(t.genre, "Electronic")
        XCTAssertEqual(t.artwork, front)
    }

    func testID3v1() throws {
        var b = [UInt8](repeating: 0, count: 128)
        b[0...2] = [0x54, 0x41, 0x47]
        func put(_ s: String, _ at: Int) { for (i, c) in s.utf8.enumerated() { b[at + i] = c } }
        put("Old Song", 3); put("Old Artist", 33); put("Old Album", 63); put("1994", 93)
        b[126] = 4
        b[127] = 8 // Jazz
        let t = try XCTUnwrap(ID3Reader.parseV1(b))
        XCTAssertEqual(t.title, "Old Song")
        XCTAssertEqual(t.artist, "Old Artist")
        XCTAssertEqual(t.album, "Old Album")
        XCTAssertEqual(t.year, 1994)
        XCTAssertEqual(t.trackNumber, 4)
        XCTAssertEqual(t.genre, "Jazz")
    }

    func testWAVWithID3ChunkAndInfoList() throws {
        let id3 = Fixtures.id3Tag(major: 4, frames: [
            Fixtures.id3Text("TIT2", "Wave Title", v4: true),
            Fixtures.id3Text("TALB", "Wave Album", v4: true),
        ])
        var info: [UInt8] = Array("INFO".utf8)
        let artist = Array("Info Artist".utf8) + [0]
        info += Array("IART".utf8) + Fixtures.le32(artist.count) + artist
        let wav = dir.appendingPathComponent("x.wav")
        Fixtures.wav(at: wav, sampleRate: 48_000, bits: 24, extraChunks: [("LIST", info), ("id3 ", id3)])

        let (track, _) = try XCTUnwrap(MetadataReader.read(url: wav, fileSize: 1, modified: Date()))
        XCTAssertEqual(track.title, "Wave Title")
        XCTAssertEqual(track.album, "Wave Album")
        XCTAssertEqual(track.artist, "Info Artist") // from LIST/INFO
        XCTAssertEqual(track.codec, .wav)
        XCTAssertEqual(track.bitDepth, 24)
        XCTAssertEqual(track.quality, .hiRes) // 24-bit counts as Hi-Res
    }

    func testFilenameInference() {
        let t = FilenameInference.infer(url: URL(fileURLWithPath: "/m/Miles Davis/Kind of Blue (1959)/CD1/02 - Freddie Freeloader.flac"))
        XCTAssertEqual(t.title, "Freddie Freeloader")
        XCTAssertEqual(t.trackNumber, 2)
        XCTAssertEqual(t.discNumber, 1)
        XCTAssertEqual(t.album, "Kind of Blue")
        XCTAssertEqual(t.year, 1959)
        XCTAssertEqual(t.artist, "Miles Davis")

        let t2 = FilenameInference.infer(url: URL(fileURLWithPath: "/m/Downloads/Radiohead - 1997 - OK Computer/1-04 Exit Music.mp3"))
        XCTAssertEqual(t2.artist, "Radiohead")
        XCTAssertEqual(t2.album, "OK Computer")
        XCTAssertEqual(t2.year, 1997)
        XCTAssertEqual(t2.discNumber, 1)
        XCTAssertEqual(t2.trackNumber, 4)
        XCTAssertEqual(t2.title, "Exit Music")
    }

    func testQualityTiers() {
        XCTAssertEqual(QualityTier.classify(codec: .flac, sampleRate: 44_100, bitDepth: 16), .cd)
        XCTAssertEqual(QualityTier.classify(codec: .flac, sampleRate: 44_100, bitDepth: 24), .hiRes)
        XCTAssertEqual(QualityTier.classify(codec: .alac, sampleRate: 96_000, bitDepth: 16), .hiRes)
        XCTAssertEqual(QualityTier.classify(codec: .mp3, sampleRate: 48_000, bitDepth: nil), .lossy)
        XCTAssertEqual(Format.sampleRate(44_100), "44.1 kHz")
        XCTAssertEqual(Format.sampleRate(192_000), "192 kHz")
        XCTAssertEqual(Format.duration(3725), "1:02:05")
    }
}

final class LibraryTests: XCTestCase {
    var dir: URL!

    override func setUp() { dir = Fixtures.tempDir() }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func makeLibrary() -> URL {
        let lib = dir.appendingPathComponent("Music")
        let src = dir.appendingPathComponent("src16.wav")
        let srcHi = dir.appendingPathComponent("src24.wav")
        Fixtures.wav(at: src, sampleRate: 44_100, bits: 16, seconds: 0.3)
        Fixtures.wav(at: srcHi, sampleRate: 96_000, bits: 24, seconds: 0.3)

        // Album 1: tagged FLAC hi-res, embedded art, two discs in CD1/CD2 folders.
        for disc in 1...2 {
            for n in 1...2 {
                let f = lib.appendingPathComponent("Band/Hi Album/CD\(disc)/0\(n) Song.flac")
                try! FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
                Fixtures.convert(srcHi, to: f, fileFormat: "flac", dataFormat: "flac")
                Fixtures.tagFLAC(f, comments: ["TITLE=Song \(disc)-\(n)", "ARTIST=Band", "ALBUM=Hi Album",
                                               "TRACKNUMBER=\(n)", "DISCNUMBER=\(disc)", "DATE=2015", "GENRE=Rock"],
                                 picture: Fixtures.png(red: 0.5))
            }
        }
        // Album 2: untagged ALAC, CD quality, cover.jpg in folder → inferred from path.
        let a2 = lib.appendingPathComponent("Singer/Quiet Record (2003)")
        try! FileManager.default.createDirectory(at: a2, withIntermediateDirectories: true)
        for n in 1...3 {
            Fixtures.convert(src, to: a2.appendingPathComponent("0\(n) Track \(n).m4a"), fileFormat: "m4af", dataFormat: "alac")
        }
        try! Fixtures.png(red: 0.2).write(to: a2.appendingPathComponent("cover.png"))
        // Album 3: lossy AAC compilation with different track artists but the same folder.
        let a3 = lib.appendingPathComponent("Various/Hits")
        try! FileManager.default.createDirectory(at: a3, withIntermediateDirectories: true)
        Fixtures.convert(src, to: a3.appendingPathComponent("01 One.m4a"), fileFormat: "m4af", dataFormat: "aac")
        Fixtures.convert(src, to: a3.appendingPathComponent("02 Two.m4a"), fileFormat: "m4af", dataFormat: "aac")
        // Junk that must be ignored.
        try! Data("nope".utf8).write(to: a3.appendingPathComponent("broken.flac"))
        try! Data("x".utf8).write(to: a3.appendingPathComponent("notes.txt"))
        return lib
    }

    func testScanIndexFilterAndRescan() async throws {
        let lib = makeLibrary()
        let store = ArtworkStore(directory: dir.appendingPathComponent("Covers"))

        let tracks = await LibraryScanner.scan(folders: [lib], existing: [:], artwork: store) { _ in }
        XCTAssertEqual(tracks.count, 9, "broken.flac and notes.txt must be skipped")

        let index = LibraryIndex.build(tracks)
        XCTAssertEqual(index.albums.count, 3)

        let hi = try XCTUnwrap(index.albums.first { $0.title == "Hi Album" })
        XCTAssertEqual(hi.tracks.count, 4)
        XCTAssertEqual(hi.discCount, 2)
        XCTAssertEqual(hi.quality, .hiRes)
        XCTAssertEqual(hi.qualitySummary, "FLAC · 24/96")
        XCTAssertEqual(hi.tracks.map(\.title), ["Song 1-1", "Song 1-2", "Song 2-1", "Song 2-2"])
        let hiArt = try XCTUnwrap(hi.artworkKey)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: hiArt, size: .thumb).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: hiArt, size: .large).path))

        let quiet = try XCTUnwrap(index.albums.first { $0.title == "Quiet Record" })
        XCTAssertEqual(quiet.artist, "Singer")
        XCTAssertEqual(quiet.year, 2003)
        XCTAssertEqual(quiet.quality, .cd)
        XCTAssertEqual(quiet.tracks.map(\.trackNumber), [1, 2, 3])
        XCTAssertNotNil(quiet.artworkKey, "cover.png in the folder should be picked up")
        XCTAssertNotEqual(quiet.artworkKey, hi.artworkKey)

        let hits = try XCTUnwrap(index.albums.first { $0.title == "Hits" })
        XCTAssertEqual(hits.quality, .lossy)

        // Filters
        var f = LibraryFilter()
        f.qualities = [.hiRes]
        XCTAssertEqual(f.apply(index.albums).map(\.title), ["Hi Album"])
        f = LibraryFilter()
        f.codecs = [.alac, .aac]
        XCTAssertEqual(Set(f.apply(index.albums).map(\.title)), ["Quiet Record", "Hits"])
        f = LibraryFilter()
        f.search = "song 2-1"
        XCTAssertEqual(f.apply(index.albums).map(\.title), ["Hi Album"], "album search covers track titles")
        XCTAssertEqual(f.apply(tracks).map(\.title), ["Song 2-1"])
        f = LibraryFilter()
        f.search = "QUIET"
        XCTAssertEqual(f.apply(index.albums).count, 1)
        f = LibraryFilter()
        f.decade = 2010
        f.genre = "Rock"
        XCTAssertEqual(f.apply(index.albums).map(\.title), ["Hi Album"])

        XCTAssertEqual(index.codecs, [.flac, .alac, .aac])
        XCTAssertEqual(index.decades, [2010, 2000])

        // Rescan reuses unchanged entries (same added date) and drops deleted files.
        let existing = Dictionary(uniqueKeysWithValues: tracks.map { ($0.path, $0) })
        try FileManager.default.removeItem(at: lib.appendingPathComponent("Various/Hits/02 Two.m4a"))
        let reported = ProgressBox()
        let again = await LibraryScanner.scan(folders: [lib], existing: existing, artwork: store) { reported.total = $0.total }
        XCTAssertEqual(again.count, 8)
        XCTAssertEqual(reported.total, 1, "only the unreadable broken.flac is retried")
        for t in again { XCTAssertEqual(t.added, existing[t.path]?.added) }

        // Persistence round-trip
        let db = dir.appendingPathComponent("library.json")
        try LibraryDatabase.save(again, to: db)
        XCTAssertEqual(LibraryDatabase.load(from: db), again)

        // A cache written by an older version is kept (added dates survive) but every file is re-read.
        let old = try JSONSerialization.jsonObject(with: Data(contentsOf: db)) as! [String: Any]
        var downgraded = old; downgraded["version"] = 1
        try JSONSerialization.data(withJSONObject: downgraded).write(to: db)
        let stale = LibraryDatabase.load(from: db)
        XCTAssertEqual(stale.count, again.count)
        let reread = ProgressBox()
        let migrated = await LibraryScanner.scan(folders: [lib], existing: Dictionary(uniqueKeysWithValues: stale.map { ($0.path, $0) }),
                                                 artwork: store) { reread.total = $0.total }
        XCTAssertEqual(reread.total, 9, "every file is re-read after a format change")
        XCTAssertEqual(migrated.count, again.count)
        for t in migrated { XCTAssertEqual(t.added, existing[t.path]?.added) }
    }
}

final class ProgressBox: @unchecked Sendable {
    var total = -1
}
