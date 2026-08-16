import Foundation

enum MP3MetadataWriter {
    static func addTags(to audio: Data, song: Song, coverData: Data?) -> Data {
        var frames = Data()
        frames.append(frame(id: "TIT2", text: song.name))
        frames.append(frame(id: "TPE1", text: song.artist))
        frames.append(frame(id: "TALB", text: song.album))
        if let coverData, !coverData.isEmpty {
            var payload = Data([0])
            payload.append(contentsOf: Data("image/jpeg".utf8))
            payload.append(0)
            payload.append(3)
            payload.append(0)
            payload.append(contentsOf: Data("Cover".utf8))
            payload.append(0)
            payload.append(coverData)
            frames.append(frame(id: "APIC", payload: payload))
        }
        var header = Data("ID3".utf8)
        header.append(3)
        header.append(0)
        header.append(0)
        header.append(contentsOf: synchsafe(frames.count))
        header.append(frames)
        header.append(audio)
        return header
    }

    private static func frame(id: String, text: String) -> Data {
        var payload = Data([3])
        payload.append(contentsOf: Data(text.utf8))
        return frame(id: id, payload: payload)
    }

    private static func frame(id: String, payload: Data) -> Data {
        var result = Data(id.utf8)
        result.append(contentsOf: UInt32(payload.count).bigEndianBytes)
        result.append(contentsOf: [0, 0])
        result.append(payload)
        return result
    }

    private static func synchsafe(_ value: Int) -> [UInt8] {
        [UInt8((value >> 21) & 0x7F), UInt8((value >> 14) & 0x7F), UInt8((value >> 7) & 0x7F), UInt8(value & 0x7F)]
    }
}

private extension UInt32 {
    var bigEndianBytes: [UInt8] { [UInt8((self >> 24) & 0xFF), UInt8((self >> 16) & 0xFF), UInt8((self >> 8) & 0xFF), UInt8(self & 0xFF)] }
}

