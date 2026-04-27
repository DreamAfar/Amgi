public import Dependencies
import DependenciesMacros
public import Foundation

@DependencyClient
public struct StatsClient: Sendable {
    public var fetchGraphs: @Sendable (_ search: String, _ days: UInt32) throws -> Data
    public var fetchCardStats: @Sendable (_ cardId: Int64) throws -> Data
}

extension StatsClient: TestDependencyKey {
    public static let testValue = StatsClient()
}

extension DependencyValues {
    public var statsClient: StatsClient {
        get { self[StatsClient.self] }
        set { self[StatsClient.self] = newValue }
    }
}
