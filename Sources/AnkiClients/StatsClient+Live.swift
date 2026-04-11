import AnkiBackend
import AnkiProto
public import Dependencies
import DependenciesMacros
import Foundation
import SwiftProtobuf

extension StatsClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend

        return Self(
            fetchGraphs: { search, days in
                var req = Anki_Stats_GraphsRequest()
                req.search = search
                req.days = days
                let response: Anki_Stats_GraphsResponse = try backend.invoke(
                    service: AnkiBackend.Service.stats,
                    method: AnkiBackend.StatsMethod.graphs,
                    request: req
                )
                return try response.serializedData()
            },
            fetchCardStats: { cardId in
                var req = Anki_Cards_CardId()
                req.cid = cardId
                let response: Anki_Stats_CardStatsResponse = try backend.invoke(
                    service: AnkiBackend.Service.stats,
                    method: AnkiBackend.StatsMethod.cardStats,
                    request: req
                )
                return try response.serializedData()
            }
        )
    }()
}
