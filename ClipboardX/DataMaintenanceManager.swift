import Foundation
import SQLite3

enum DataMaintenanceManager {
    nonisolated static func vacuum(files: [URL]) -> Int {
        var optimizedCount = 0
        for fileURL in files {
            var db: OpaquePointer?
            if sqlite3_open(fileURL.path, &db) == SQLITE_OK {
                defer { sqlite3_close(db) }
                if sqlite3_exec(db, "VACUUM;", nil, nil, nil) == SQLITE_OK {
                    optimizedCount += 1
                }
            } else if db != nil {
                sqlite3_close(db)
            }
        }
        return optimizedCount
    }
}
