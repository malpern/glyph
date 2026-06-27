import Foundation
import SwiftData

/// Builds a configured `SwiftDataStore`. The composition root calls
/// `make()` once at launch; tests call `make(inMemory: true)`.
public enum ReaderStore {
    /// The entity schema. Centralized so the container and any future migration
    /// plan reference one list.
    static var schema: Schema {
        Schema([
            BookEntity.self,
            ReadingStateEntity.self,
            BookmarkEntity.self,
            HighlightEntity.self,
        ])
    }

    /// - Parameters:
    ///   - inMemory: ephemeral store for tests/previews.
    ///   - url: explicit on-disk location; defaults to SwiftData's app-support path.
    public static func make(inMemory: Bool = false, url: URL? = nil) throws -> SwiftDataStore {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let url {
            configuration = ModelConfiguration(schema: schema, url: url)
        } else {
            configuration = ModelConfiguration(schema: schema)
        }
        let container = try ModelContainer(for: schema, configurations: configuration)
        return SwiftDataStore(modelContainer: container)
    }
}
