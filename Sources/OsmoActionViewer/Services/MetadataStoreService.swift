import Foundation
import SQLite3

final class MetadataStoreService {
    private let db: OpaquePointer?

    init() {
        self.db = Self.openDatabase()
        Self.createTableIfNeeded(db)
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func load(from folderURL: URL) -> [String: RecordingMetadata] {
        let folderPath = folderURL.path
        var loaded = loadFromDatabase(folderPath: folderPath)
        if !loaded.isEmpty {
            return loaded
        }

        let legacy = loadLegacyJSON(from: folderURL)
        if !legacy.isEmpty {
            do {
                try save(entries: legacy, to: folderURL)
                loaded = legacy
            } catch {
                return legacy
            }
        }
        return loaded
    }

    func save(entries: [String: RecordingMetadata], to folderURL: URL) throws {
        guard let db else { throw MetadataStoreError.databaseUnavailable }
        let folderPath = folderURL.path

        try Self.exec(db, sql: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            let deleteSQL = "DELETE FROM recording_metadata WHERE folder_path = ?;"
            let deleteStmt = try Self.prepare(db, sql: deleteSQL)
            defer { sqlite3_finalize(deleteStmt) }
            sqlite3_bind_text(deleteStmt, 1, folderPath, -1, SQLITE_TRANSIENT)
            if sqlite3_step(deleteStmt) != SQLITE_DONE {
                throw MetadataStoreError.sqlite(message: Self.lastError(db))
            }

            let insertSQL = """
            INSERT INTO recording_metadata (
                folder_path, recording_key, title, note, location_text, google_maps_url, markers_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            let insertStmt = try Self.prepare(db, sql: insertSQL)
            defer { sqlite3_finalize(insertStmt) }

            for (key, meta) in entries {
                sqlite3_reset(insertStmt)
                sqlite3_clear_bindings(insertStmt)

                let markersData = try JSONEncoder().encode(meta.markers)
                let markersJSON = String(data: markersData, encoding: .utf8) ?? "[]"

                sqlite3_bind_text(insertStmt, 1, folderPath, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insertStmt, 2, key, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insertStmt, 3, meta.title, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insertStmt, 4, meta.note, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insertStmt, 5, meta.locationText, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insertStmt, 6, meta.googleMapsURL, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insertStmt, 7, markersJSON, -1, SQLITE_TRANSIENT)

                if sqlite3_step(insertStmt) != SQLITE_DONE {
                    throw MetadataStoreError.sqlite(message: Self.lastError(db))
                }
            }

            try Self.exec(db, sql: "COMMIT;")
        } catch {
            _ = try? Self.exec(db, sql: "ROLLBACK;")
            throw error
        }
    }

    private func loadFromDatabase(folderPath: String) -> [String: RecordingMetadata] {
        guard let db else { return [:] }

        let sql = """
        SELECT recording_key, title, note, location_text, google_maps_url, markers_json
        FROM recording_metadata
        WHERE folder_path = ?;
        """

        do {
            let stmt = try Self.prepare(db, sql: sql)
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, folderPath, -1, SQLITE_TRANSIENT)

            var result: [String: RecordingMetadata] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                let key = Self.textColumn(stmt, index: 0)
                let title = Self.textColumn(stmt, index: 1)
                let note = Self.textColumn(stmt, index: 2)
                let locationText = Self.textColumn(stmt, index: 3)
                let googleMapsURL = Self.textColumn(stmt, index: 4)
                let markersJSON = Self.textColumn(stmt, index: 5)
                let markers = parseMarkers(markersJSON)

                result[key] = RecordingMetadata(
                    title: title,
                    note: note,
                    markers: markers,
                    locationText: locationText,
                    googleMapsURL: googleMapsURL
                )
            }
            return result
        } catch {
            return [:]
        }
    }

    private func loadLegacyJSON(from folderURL: URL) -> [String: RecordingMetadata] {
        let fileURL = folderURL.appendingPathComponent(".osmo-action-viewer-metadata.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(MetadataStore.self, from: data)
            return decoded.entries
        } catch {
            return [:]
        }
    }

    private func parseMarkers(_ json: String) -> [Double] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([Double].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private static func openDatabase() -> OpaquePointer? {
        let fm = FileManager.default
        do {
            let appSupport = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dir = appSupport.appendingPathComponent("OsmoActionViewer", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let dbURL = dir.appendingPathComponent("metadata.sqlite")

            var db: OpaquePointer?
            if sqlite3_open(dbURL.path, &db) == SQLITE_OK {
                return db
            }
            if let db { sqlite3_close(db) }
            return nil
        } catch {
            return nil
        }
    }

    private static func createTableIfNeeded(_ db: OpaquePointer?) {
        guard let db else { return }
        let sql = """
        CREATE TABLE IF NOT EXISTS recording_metadata (
            folder_path TEXT NOT NULL,
            recording_key TEXT NOT NULL,
            title TEXT NOT NULL DEFAULT '',
            note TEXT NOT NULL DEFAULT '',
            location_text TEXT NOT NULL DEFAULT '',
            google_maps_url TEXT NOT NULL DEFAULT '',
            markers_json TEXT NOT NULL DEFAULT '[]',
            updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            PRIMARY KEY (folder_path, recording_key)
        );
        """
        _ = try? exec(db, sql: sql)
    }

    private static func prepare(_ db: OpaquePointer, sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            return stmt
        }
        throw MetadataStoreError.sqlite(message: lastError(db))
    }

    private static func exec(_ db: OpaquePointer, sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw MetadataStoreError.sqlite(message: lastError(db))
        }
    }

    private static func lastError(_ db: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(db))
    }

    private static func textColumn(_ stmt: OpaquePointer?, index: Int32) -> String {
        guard let cString = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cString)
    }
}

enum MetadataStoreError: Error {
    case databaseUnavailable
    case sqlite(message: String)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
