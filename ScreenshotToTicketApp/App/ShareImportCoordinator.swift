import Combine
import Foundation

@MainActor
final class ShareImportCoordinator: ObservableObject {
    @Published private(set) var importToken = UUID()

    func requestImport() {
        importToken = UUID()
    }
}
