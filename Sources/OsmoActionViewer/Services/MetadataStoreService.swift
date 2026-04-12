import Foundation
import SQLite3

/// Stores per-folder metadata in a SQLite file located directly inside the
/// video folder (`<folder>/.osmo-action-viewer-metadata.sqlite`). This layout
/// is shared with the Windows port so that cloud-synced folders round-trip
/// between platforms without any additional syncing layer.
///
/// Data safety notes (upgrades must not lose user edits):
///   * The DB file lives with the user's videos, never in the app bundle or
///     Application Support, so reinstalling / upgrading the app cannot touch
///     it.
///   * On first access of a folder, entries found in the legacy
///     `~/Library/Application Support/OsmoActionViewer/metadata.sqlite` DB
///     and/or `<folder>/.osmo-action-viewer-metadata.json` are copied into
///     the new per-folder DB. The legacy sources are **never** deleted, so a
///     downgrade or a botched migration can still be recovered.
final class MetadataStoreService {
    private let fileName = ".osmo-action-viewer-metadata.sqlite"
    private let schemaVersion = 1

    init() {}

    // MARK: - Public API

    func load(from folderURL: URL) -> [String: RecordingMetadata] {
        guard let db = openFolderDatabase(folderURL, createIfMissing: false) else {
            return tryMigrateAndLoad(folderURL: folderURL)
        }
        defer { sqlite3_close(db) }

        let current = loadAll(db: db)
        if !current.isEmpty {
            return current
        }
        // DB exists but is empty — still attempt legacy import (one-shot,
        // guarded by schema_meta flag) so users who open the folder with the
        // new build for the first time don't see missing data.
        return runMigrationIfNeeded(db: db, folderURL: folderURL) ?? current
    }

    func save(entries: [String: RecordingMetadata], to folderURL: URL) throws {
        guard let db = openFolderDatabase(folderURL, createIfMissing: true) else {
            throw MetadataStoreError.databaseUnavailable
        }
        defer { sqlite3_close(db) }
        try writeAll(db: db, entries: entries)
    }

    // MARK: - Migration

    private func tryMigrateAndLoad(folderURL: URL) -> [String: RecordingMetadata] {
        guard let db = openFolderDatabase(folderURL, createIfMissing: true) else {
            return [:]
        }
        defer { sqlite3_close(db) }
        return runMigrationIfNeeded(db: db, folderURL: folderURL) ?? loadAll(db: db)
    }

    /// Imports legacy data into the folder-local DB exactly once. Returns the
    /// imported entries if a migration happened, nil otherwise. Never deletes
    /// the legacy sources.
    private func runMigrationIfNeeded(db: OpaquePointer, folderURL: URL) -> [String: RecordingMetadata]? {
        if readMetaFlag(db: db, key: "migrated_from_appsupport") == "1" {
            return nil
        }

        var merged: [String: RecordingMetadata] = [:]

        // 1. Legacy per-folder JSON, if present.
        let legacy = loadLegacyJSON(from: folderURL)
        for (k, v) in legacy { merged[k] = v }

        // 2. Legacy ~/Library/Application Support SQLite DB, entries for this folder.
        let fromAppSupport = loadFromLegacyAppSupport(folderPath: folderURL.path)
        for (k, v) in fromAppSupport { merged[k] = v }

        // Mark the migration as done even if nothing was found, to avoid
        // repeatedly scanning the legacy sources on every folder open.
        writeMetaFlag(db: db, key: "migrated_from_appsupport", value: "1")

        guard !merged.isEmpty else { return nil }

        do {
            try writeAll(db: db, entries: merged)
            return merged
        } catch {
            return merged
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

    private func loadFromLegacyAppSupport(folderPath: String) -> [String: RecordingMetadata] {
        guard let url = legacyAppSupportDatabaseURL(),
              FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }

        var legacyDB: OpaquePointer?
        guard sqlite3_open_v2(url.path, &legacyDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let legacyDB else {
            if let legacyDB { sqlite3_close(legacyDB) }
            return [:]
        }
        defer { sqlite3_close(legacyDB) }

        let sql = """
        SELECT recording_key, title, note, location_text, google_maps_url, markers_json
        FROM recording_metadata
        WHERE folder_path = ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(legacyDB, sql, -1, &stmt, nil) == SQLITE_OK else {
            if let stmt { sqlite3_finalize(stmt) }
            return [:]
        }
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
            result[key] = RecordingMetadata(
                title: title,
                note: note,
                markers: Self.parseMarkers(markersJSON),
                locationText: locationText,
                googleMapsURL: googleMapsURL
            )
        }
        return result
    }

    private func legacyAppSupportDatabaseURL() -> URL? {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return nil
        }
        return appSupport
            .appendingPathComponent("OsmoActionViewer", isDirectory: true)
            .appendingPathComponent("metadata.sqlite")
    }

    // MARK: - DB primitives

    private func openFolderDatabase(_ folderURL: URL, createIfMissing: Bool) -> OpaquePointer? {
        let dbURL = folderURL.appendingPathComponent(fileName)
        let exists = FileManager.default.fileExists(atPath: dbURL.path)
        if !exists && !createIfMissing {
            return nil
        }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        if sqlite3_open_v2(dbURL.path, &db, flags, nil) != SQLITE_OK {
            if let db { sqlite3_close(db) }
            return nil
        }
        guard let db else { return nil }

        Self.createTableIfNeeded(db)
        writeMetaFlag(db: db, key: "schema_version", value: String(schemaVersion), onlyIfAbsent: true)
        return db
    }

    private func loadAll(db: OpaquePointer) -> [String: RecordingMetadata] {
        let sql = """
        SELECT recording_key, title, note, location_text, google_maps_url, markers_json
        FROM recording_metadata;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            if let stmt { sqlite3_finalize(stmt) }
            return [:]
        }
        defer { sqlite3_finalize(stmt) }

        var result: [String: RecordingMetadata] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let key = Self.textColumn(stmt, index: 0)
            let title = Self.textColumn(stmt, index: 1)
            let note = Self.textColumn(stmt, index: 2)
            let locationText = Self.textColumn(stmt, index: 3)
            let googleMapsURL = Self.textColumn(stmt, index: 4)
            let markersJSON = Self.textColumn(stmt, index: 5)
            result[key] = RecordingMetadata(
                title: title,
                note: note,
                markers: Self.parseMarkers(markersJSON),
                locationText: locationText,
                googleMapsURL: googleMapsURL
            )
        }
        return result
    }

    private func writeAll(db: OpaquePointer, entries: [String: RecordingMetadata]) throws {
        try Self.exec(db, sql: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            try Self.exec(db, sql: "DELETE FROM recording_metadata;")

            let insertSQL = """
            INSERT INTO recording_metadata (
                recording_key, title, note, location_text, google_maps_url, markers_json, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, strftime('%s','now'));
            """
            let stmt = try Self.prepare(db, sql: insertSQL)
            defer { sqlite3_finalize(stmt) }

            for (key, meta) in entries {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)

                let markersData = try JSONEncoder().encode(meta.markers)
                let markersJSON = String(data: markersData, encoding: .utf8) ?? "[]"

                sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, meta.title, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, meta.note, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 4, meta.locationText, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 5, meta.googleMapsURL, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 6, markersJSON, -1, SQLITE_TRANSIENT)

                if sqlite3_step(stmt) != SQLITE_DONE {
                    throw MetadataStoreError.sqlite(message: Self.lastError(db))
                }
            }

            try Self.exec(db, sql: "COMMIT;")
        } catch {
            _ = try? Self.exec(db, sql: "ROLLBACK;")
            throw error
        }
    }

    private func readMetaFlag(db: OpaquePointer, key: String) -> String? {
        let sql = "SELECT value FROM schema_meta WHERE key = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            if let stmt { sqlite3_finalize(stmt) }
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Self.textColumn(stmt, index: 0)
        }
        return nil
    }

    private func writeMetaFlag(db: OpaquePointer, key: String, value: String, onlyIfAbsent: Bool = false) {
        if onlyIfAbsent, readMetaFlag(db: db, key: key) != nil { return }
        let sql = "INSERT OR REPLACE INTO schema_meta (key, value) VALUES (?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            if let stmt { sqlite3_finalize(stmt) }
            return
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, value, -1, SQLITE_TRANSIENT)
        _ = sqlite3_step(stmt)
    }

    // MARK: - Helpers

    private static func parseMarkers(_ json: String) -> [Double] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([Double].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private static func createTableIfNeeded(_ db: OpaquePointer) {
        let recordingSQL = """
        CREATE TABLE IF NOT EXISTS recording_metadata (
            recording_key TEXT PRIMARY KEY,
            title TEXT NOT NULL DEFAULT '',
            note TEXT NOT NULL DEFAULT '',
            location_text TEXT NOT NULL DEFAULT '',
            google_maps_url TEXT NOT NULL DEFAULT '',
            markers_json TEXT NOT NULL DEFAULT '[]',
            updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
        );
        """
        _ = try? exec(db, sql: recordingSQL)

        let metaSQL = """
        CREATE TABLE IF NOT EXISTS schema_meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """
        _ = try? exec(db, sql: metaSQL)
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
