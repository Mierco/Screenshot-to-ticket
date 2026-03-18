import UIKit

enum ImageCompression {
    static func compressedJPEG(_ data: Data, maxDimension: CGFloat = 1800, quality: CGFloat = 0.7) -> Data {
        guard let image = UIImage(data: data) else { return data }

        let size = image.size
        let longest = max(size.width, size.height)
        let scale = min(1.0, maxDimension / longest)

        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resized.jpegData(compressionQuality: quality) ?? data
    }
}
