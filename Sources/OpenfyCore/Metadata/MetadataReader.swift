import AudioToolbox
import Foundation

public struct AudioProperties: Sendable, Equatable {
    public var codec: AudioCodec
    public var sampleRate: Double
    public var bitDepth: Int?
    public var channels: Int
    public var duration: Double
    public var bitrate: Int?
}

public enum AudioPropertiesReader {
    /// Reads the stream format via AudioToolbox — the same decoder stack used for playback,
    /// so if this succeeds, the file is playable.
    public static func read(url: URL) -> AudioProperties? {
        var fileID: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &fileID) == noErr, let fileID else { return nil }
        defer { AudioFileClose(fileID) }

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileGetProperty(fileID, kAudioFilePropertyDataFormat, &size, &asbd) == noErr,
              asbd.mSampleRate > 0 else { return nil }

        var duration: Float64 = 0
        size = UInt32(MemoryLayout<Float64>.size)
        AudioFileGetProperty(fileID, kAudioFilePropertyEstimatedDuration, &size, &duration)

        var bitRate: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        AudioFileGetProperty(fileID, kAudioFilePropertyBitRate, &size, &bitRate)

        var sourceDepth: Int32 = 0
        size = UInt32(MemoryLayout<Int32>.size)
        let hasSourceDepth = AudioFileGetProperty(fileID, kAudioFilePropertySourceBitDepth, &size, &sourceDepth) == noErr

        let ext = url.pathExtension.lowercased()
        let codec: AudioCodec
        switch asbd.mFormatID {
        case kAudioFormatLinearPCM: codec = ["aif", "aiff", "aifc"].contains(ext) ? .aiff : .wav
        case kAudioFormatFLAC: codec = .flac
        case kAudioFormatAppleLossless: codec = .alac
        case kAudioFormatMPEGLayer3: codec = .mp3
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2,
             kAudioFormatMPEG4AAC_LD, kAudioFormatMPEG4AAC_ELD: codec = .aac
        case kAudioFormatOpus: codec = .opus
        default: codec = .other
        }

        var bitDepth: Int?
        if codec.isLossless {
            if asbd.mFormatID == kAudioFormatLinearPCM {
                bitDepth = Int(asbd.mBitsPerChannel)
            } else if hasSourceDepth, sourceDepth > 0 {
                bitDepth = Int(sourceDepth)
            } else {
                // FLAC / ALAC encode the source depth in the format flags.
                switch asbd.mFormatFlags {
                case 1: bitDepth = 16
                case 2: bitDepth = 20
                case 3: bitDepth = 24
                case 4: bitDepth = 32
                default: bitDepth = nil
                }
            }
        }

        return AudioProperties(
            codec: codec,
            sampleRate: asbd.mSampleRate,
            bitDepth: bitDepth,
            channels: Int(asbd.mChannelsPerFrame),
            duration: duration,
            bitrate: bitRate > 0 ? Int((Double(bitRate) / 1000).rounded()) : nil
        )
    }
}

public enum MetadataReader {
    public static let supportedExtensions: Set<String> = [
        "flac", "mp3", "m4a", "mp4", "aac", "wav", "wave", "aif", "aiff", "aifc", "caf",
    ]

    /// Reads tags, stream properties and embedded artwork. Returns nil if the file can't be decoded.
    public static func read(url: URL, fileSize: Int64, modified: Date) -> (track: Track, artwork: Data?)? {
        guard let props = AudioPropertiesReader.read(url: url) else { return nil }

        var sampleRate = props.sampleRate
        var bitDepth = props.bitDepth
        var channels = props.channels
        var duration = props.duration

        var tags = TagData()
        switch url.pathExtension.lowercased() {
        case "flac":
            if let flac = FLACReader.read(url: url) {
                tags = flac.tags
                if let info = flac.streamInfo {
                    // STREAMINFO is authoritative and sample-exact.
                    sampleRate = Double(info.sampleRate)
                    bitDepth = info.bitsPerSample
                    channels = info.channels
                    if info.totalSamples > 0 { duration = info.duration }
                }
            }
        case "mp3", "aac":
            tags = ID3Reader.read(url: url) ?? TagData()
        case "m4a", "mp4":
            tags = MP4Reader.read(url: url) ?? TagData()
        case "wav", "wave", "aif", "aiff", "aifc":
            tags = ChunkReader.read(url: url) ?? TagData()
        default:
            break
        }

        let inferred = FilenameInference.infer(url: url)
        tags.merge(fallback: inferred)

        let track = Track(
            path: url.path,
            title: tags.title ?? url.deletingPathExtension().lastPathComponent,
            artist: tags.artist ?? tags.albumArtist ?? "Unknown Artist",
            albumArtistTag: tags.albumArtist.nonEmpty,
            album: tags.album ?? "Unknown Album",
            trackNumber: tags.trackNumber,
            trackTotal: tags.trackTotal,
            discNumber: tags.discNumber,
            discTotal: tags.discTotal,
            year: tags.year,
            genre: tags.genre,
            duration: duration,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            channels: channels,
            bitrate: props.bitrate,
            codec: props.codec,
            fileSize: fileSize,
            modified: modified
        )
        return (track, tags.artwork)
    }
}

/// Guesses tags from the common "Artist/Album/01 Title.flac" layout when files have no tags.
public enum FilenameInference {
    public static func infer(url: URL) -> TagData {
        var tags = TagData()

        let name = url.deletingPathExtension().lastPathComponent
        if let m = name.firstMatch(of: #/^(\d)-(\d{1,3})[\s._-]+(.+)$/#) {
            tags.discNumber = Int(m.1)
            tags.trackNumber = Int(m.2)
            tags.title = String(m.3).trimmingCharacters(in: .whitespaces)
        } else if let m = name.firstMatch(of: #/^(\d{1,3})[\s._-]+(.+)$/#) {
            tags.trackNumber = Int(m.1)
            tags.title = String(m.2).trimmingCharacters(in: CharacterSet(charactersIn: " -._"))
        } else {
            tags.title = name
        }

        var albumDir = url.deletingLastPathComponent()
        if let m = albumDir.lastPathComponent.firstMatch(of: #/^(?i)(?:cd|disc|disk)\s*(\d+)$/#) {
            tags.discNumber = tags.discNumber ?? Int(m.1)
            albumDir = albumDir.deletingLastPathComponent()
        }

        var albumName = albumDir.lastPathComponent
        var artistName: String? = albumDir.deletingLastPathComponent().lastPathComponent

        // "Artist - 2001 - Album" or "Artist - Album"
        let parts = albumName.components(separatedBy: " - ")
        if parts.count >= 2 {
            artistName = parts.first
            if parts.count >= 3, let y = TagParsing.year(parts[1]), parts[1].count == 4 { tags.year = y }
            albumName = parts.last!
        }
        // "Album (2001)" or "[2001] Album"
        if let m = albumName.firstMatch(of: #/^(.+?)\s*[\(\[](\d{4})[\)\]]$/#) {
            albumName = String(m.1)
            tags.year = tags.year ?? Int(m.2)
        } else if let m = albumName.firstMatch(of: #/^[\(\[](\d{4})[\)\]]\s*(.+)$/#) {
            tags.year = tags.year ?? Int(m.1)
            albumName = String(m.2)
        }

        tags.album = albumName.isEmpty ? nil : albumName
        if let a = artistName, !a.isEmpty, a != "/", !["Music", "Downloads", "Desktop", "Users"].contains(a) {
            tags.artist = a
        }
        return tags
    }
}
