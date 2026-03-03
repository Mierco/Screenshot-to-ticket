import AVFoundation
import Foundation
import UIKit

enum VideoThumbnail {
    static func jpegPreview(from videoData: Data) -> Data? {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        do {
            try videoData.write(to: tmpURL)
            defer { try? FileManager.default.removeItem(at: tmpURL) }

            let asset = AVURLAsset(url: tmpURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true

            let cg = try generator.copyCGImage(at: .zero, actualTime: nil)
            let image = UIImage(cgImage: cg)
            guard let jpeg = image.jpegData(compressionQuality: 0.75) else { return nil }
            return ImageCompression.compressedJPEG(jpeg)
        } catch {
            return nil
        }
    }
}
