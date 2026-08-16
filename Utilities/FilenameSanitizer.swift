import Foundation

enum FilenameSanitizer {
    static func makeSongFilename(_ song: Song) -> String {
        let raw = "\(song.name) - \(song.artist).mp3"
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r")
        let cleaned = raw.unicodeScalars.map { invalid.contains($0) ? "_" : String($0) }.joined()
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "\(song.id).mp3" : cleaned
    }
}

