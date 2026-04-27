import Foundation
import Combine

@MainActor
final class AppCollectionState: ObservableObject {
    static let shared = AppCollectionState()

    @Published private(set) var isReady = false
    @Published private(set) var errorMessage: String?

    private init() {}

    func markOpening() {
        isReady = false
        errorMessage = nil
    }

    func markReady() {
        isReady = true
        errorMessage = nil
    }

    func markFailed(_ message: String) {
        isReady = false
        errorMessage = message
    }
}
