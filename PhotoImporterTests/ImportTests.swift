import XCTest
import CryptoKit
import Darwin
@testable import PhotoImporter

@MainActor
final class ImportTests: XCTestCase {
    func testCopyPairVerifiesSHA256AndPreservesReadOnlyOriginals() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: fixture.source.appendingPathComponent("capture.JPG").path)
        let before = try snapshot(fixture.source)
        let plan = try await fixture.plan()
        let record = try await fixture.service().run(plan)
        XCTAssertEqual(record.state, .completed, record.error ?? "")
        XCTAssertEqual(record.copiedCount, 2)
        for file in record.files {
            let sourceData = try Data(contentsOf: fixture.source.appendingPathComponent(file.sourceRelativePath))
            let destinationData = try Data(contentsOf: fixture.library.appendingPathComponent(file.destinationRelativePath))
            XCTAssertEqual(destinationData, sourceData)
            XCTAssertEqual(file.sha256, SHA256.hash(data: sourceData).map { String(format: "%02x", $0) }.joined())
            XCTAssertEqual(file.status, .copied, file.error ?? "")
        }
        XCTAssertEqual(try snapshot(fixture.source), before)
        XCTAssertTrue(try partials(fixture.library).isEmpty)
        let saved = try ImportJournal(root: fixture.journal).load(record.id)
        XCTAssertEqual(saved.state, .completed)
        XCTAssertEqual(saved.files.map(\.sha256), record.files.map(\.sha256))
    }

    func testRetryUsesHashesAndNeedsNoExtraSpaceForVerifiedExistingFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plan = try await fixture.plan()
        let first = try await fixture.service().run(plan)
        XCTAssertEqual(first.copiedCount, 2)
        let before = try snapshot(fixture.library)
        let second = try await fixture.service(capacity: 0).run(plan)
        XCTAssertEqual(second.state, .completed, second.error ?? "")
        XCTAssertEqual(second.copiedCount, 0)
        XCTAssertEqual(second.existingCount, 2)
        XCTAssertEqual(try snapshot(fixture.library), before)
        XCTAssertNotEqual(first.id, second.id)
    }

    func testDifferentContentWithSameSizeIsConflictAndPairCanBeRetried() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let destination = fixture.library.appendingPathComponent("2026/2026-11-21/JPEG/capture.JPG")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let count = try Data(contentsOf: fixture.source.appendingPathComponent("capture.JPG")).count
        let other = Data(repeating: 0, count: count)
        try other.write(to: destination)
        let plan = try await fixture.plan()
        let first = try await fixture.service().run(plan)
        XCTAssertEqual(first.state, .partial)
        XCTAssertEqual(first.failedCount, 1)
        XCTAssertEqual(first.copiedCount, 1)
        XCTAssertEqual(try Data(contentsOf: destination), other)
        try FileManager.default.removeItem(at: destination)
        let retry = try await fixture.service().run(plan)
        XCTAssertEqual(retry.state, .completed, retry.error ?? "")
        XCTAssertEqual(retry.copiedCount, 1)
        XCTAssertEqual(retry.existingCount, 1)
    }

    func testCorruptedTemporaryNeverBecomesAFinalFile() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plan = try await fixture.plan(format: .jpeg)
        let service = fixture.service { point in
            if point.phase == .beforeVerification {
                let handle = try FileHandle(forWritingTo: point.temporary)
                try handle.write(contentsOf: Data([0]))
                try handle.close()
            }
        }
        let report = try await service.run(plan)
        XCTAssertEqual(report.failedCount, 1)
        XCTAssertTrue(report.files[0].error?.contains("SHA-256") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.finalJPEG.path))
        XCTAssertTrue(try partials(fixture.library).isEmpty)
    }

    func testCancellationDuringCopyCleansTemporaryAndKeepsOriginal() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = fixture.source.appendingPathComponent("capture.RW2")
        let data = Data(repeating: 0xAB, count: 3 * 1_024 * 1_024)
        try data.write(to: url)
        let plan = try await fixture.plan(format: .raw)
        let service = fixture.service { point in
            if point.phase == .chunkCopied { throw CancellationError() }
        }
        let report = try await service.run(plan)
        XCTAssertEqual(report.state, .cancelled)
        XCTAssertEqual(report.files[0].status, .cancelled)
        XCTAssertEqual(try Data(contentsOf: url), data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.finalRAW.path))
        XCTAssertTrue(try partials(fixture.library).isEmpty)
        let retry = try await fixture.service().run(plan)
        XCTAssertEqual(retry.copiedCount, 1)
    }

    func testCancellationBeforePublicationDoesNotPublishVerifiedTemporary() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plan = try await fixture.plan(format: .jpeg)
        let report = try await fixture.service { point in
            if point.phase == .beforePublication { throw CancellationError() }
        }.run(plan)
        XCTAssertEqual(report.state, .cancelled)
        XCTAssertNotNil(report.files[0].sha256)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.finalJPEG.path))
        XCTAssertTrue(try partials(fixture.library).isEmpty)
    }

    func testAtomicPublicationRefusesFileCreatedAtRenameBoundary() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plan = try await fixture.plan(format: .jpeg)
        let competing = Data("concurrent file".utf8)
        let report = try await fixture.service { point in
            if point.phase == .willRename { try competing.write(to: point.destination) }
        }.run(plan)
        XCTAssertEqual(report.failedCount, 1)
        XCTAssertEqual(try Data(contentsOf: fixture.finalJPEG), competing)
        XCTAssertTrue(try partials(fixture.library).isEmpty)
    }

    func testSourceChangedWithSameSizeSincePreviewIsRejected() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plan = try await fixture.plan(format: .jpeg)
        let url = fixture.source.appendingPathComponent("capture.JPG")
        var data = try Data(contentsOf: url)
        data[0] ^= 0xFF
        try data.write(to: url)
        let report = try await fixture.service().run(plan)
        XCTAssertEqual(report.failedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.finalJPEG.path))
    }

    func testSourceChangeDuringCopyIsDetectedBeforePublication() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plan = try await fixture.plan(format: .jpeg)
        let report = try await fixture.service { point in
            if point.phase == .beforePublication {
                let handle = try FileHandle(forWritingTo: point.source)
                try handle.write(contentsOf: Data([0]))
                try handle.close()
            }
        }.run(plan)
        XCTAssertEqual(report.failedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.finalJPEG.path))
        XCTAssertTrue(try partials(fixture.library).isEmpty)
    }

    func testDestinationParentSwappedForSymlinkCannotRedirectPublication() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = try TestPhotoFixtures.directory()
        defer { try? FileManager.default.removeItem(at: outside) }
        let plan = try await fixture.plan(format: .jpeg)
        let moved = outside.appendingPathComponent("moved")
        let report = try await fixture.service { point in
            if point.phase == .beforePublication {
                let parent = point.destination.deletingLastPathComponent()
                try FileManager.default.moveItem(at: parent, to: moved)
                try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: outside)
            }
        }.run(plan)
        XCTAssertEqual(report.failedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("capture.JPG").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: moved.appendingPathComponent("capture.JPG").path))
        XCTAssertTrue(try partials(moved).isEmpty)
    }

    func testRemovedOrReplacedLibraryCannotUseStalePlan() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plan = try await fixture.plan()
        let moved = fixture.base.appendingPathComponent("old-library")
        try FileManager.default.moveItem(at: fixture.library, to: moved)
        try FileManager.default.createDirectory(at: fixture.library, withIntermediateDirectories: true)
        let report = try await fixture.service().run(plan)
        XCTAssertEqual(report.state, .failed)
        XCTAssertEqual(report.copiedCount, 0)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.library.path).isEmpty)
    }

    func testCapacityRevalidatedBeforeAnyLibraryWrite() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plan = try await fixture.plan()
        let report = try await fixture.service(capacity: 0).run(plan)
        XCTAssertEqual(report.state, .failed)
        XCTAssertTrue(report.error?.contains("Espaço") == true)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.library.path).isEmpty)
    }

    func testVolumeIdentityMismatchPreventsCopyEvenAtSamePath() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var plan = try await fixture.plan()
        plan.libraryVolumeID = UUID().uuidString
        let report = try await fixture.service().run(plan)
        XCTAssertEqual(report.state, .failed)
        XCTAssertTrue(report.error?.contains("identidade do volume") == true)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.library.path).isEmpty)
    }

    func testDiskFullDuringWriteLeavesNoFinalOrTemporary() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plan = try await fixture.plan()
        let report = try await fixture.service { point in
            if point.phase == .chunkCopied { throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)) }
        }.run(plan)
        XCTAssertEqual(report.state, .failed)
        XCTAssertEqual(report.failedCount, 1)
        XCTAssertEqual(report.files.filter { $0.status == .pending }.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.finalJPEG.path))
        XCTAssertTrue(try partials(fixture.library).isEmpty)
    }

    func testDeviceDisconnectionDuringCopyStopsRemainingFilesAndPreservesSource() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let before = try snapshot(fixture.source)
        let plan = try await fixture.plan()
        let report = try await fixture.service { point in
            if point.phase == .chunkCopied {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENODEV))
            }
        }.run(plan)
        XCTAssertEqual(report.state, .failed)
        XCTAssertEqual(report.failedCount, 1)
        XCTAssertEqual(report.files.filter { $0.status == .pending }.count, 1)
        XCTAssertEqual(try snapshot(fixture.source), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.finalJPEG.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.finalRAW.path))
        XCTAssertTrue(try partials(fixture.library).isEmpty)
        let retry = try await fixture.service().run(plan)
        XCTAssertEqual(retry.state, .completed)
        XCTAssertEqual(retry.copiedCount, 2)
    }

    func testJournalFailurePreventsLibraryWrites() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plan = try await fixture.plan()
        try Data("not a directory".utf8).write(to: fixture.journal)
        do {
            _ = try await fixture.service().run(plan)
            XCTFail("The journal must be durable before copying")
        } catch { XCTAssertTrue(error is ImportJournalError) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.library.path).isEmpty)
    }

    func testVerifiedPhaseIsPersistedBeforeFinalPublication() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plan = try await fixture.plan(format: .jpeg)
        let journalRoot = fixture.journal
        let report = try await fixture.service { point in
            if point.phase == .beforePublication {
                let records = try FileManager.default.contentsOfDirectory(at: journalRoot, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "json" }
                let record = try JSONDecoder().decode(ImportRecord.self, from: Data(contentsOf: records[0]))
                XCTAssertEqual(record.state, .running)
                XCTAssertEqual(record.files[0].status, .verified)
                XCTAssertNotNil(record.files[0].sha256)
                XCTAssertFalse(FileManager.default.fileExists(atPath: point.destination.path))
                XCTAssertTrue(FileManager.default.fileExists(atPath: point.temporary.path))
            }
        }.run(plan)
        XCTAssertEqual(report.copiedCount, 1)
    }

    func testFailureAfterPublicationIsRecoveredByContentOnRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plan = try await fixture.plan(format: .jpeg)
        let report = try await fixture.service { point in
            if point.phase == .afterPublication { throw NSError(domain: NSPOSIXErrorDomain, code: Int(EIO)) }
        }.run(plan)
        XCTAssertEqual(report.state, .failed)
        XCTAssertNotNil(report.files[0].sha256)
        XCTAssertEqual(try Data(contentsOf: fixture.finalJPEG), try Data(contentsOf: fixture.source.appendingPathComponent("capture.JPG")))
        let retry = try await fixture.service().run(plan)
        XCTAssertEqual(retry.existingCount, 1)
        XCTAssertEqual(retry.copiedCount, 0)
    }

    func testModelStartsImportAndFreezesOriginAndSelectionUntilCancelled() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = TestPhotoFixtures.model(importer: fixture.service())
        model.discover(fixture.source)
        try await TestPhotoFixtures.waitForDiscovery(model)
        model.setLibrary(fixture.library)
        model.selectVisible()
        model.generatePlan()
        for _ in 0..<500 {
            if !model.isPlanning { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(model.plan)
        let selected = model.selectedIDs
        model.startImport()
        XCTAssertTrue(model.isImporting)
        model.discover(fixture.library)
        model.setLibrary(fixture.source)
        model.clearSelection()
        XCTAssertEqual(model.root, fixture.source)
        XCTAssertEqual(model.libraryRoot, fixture.library)
        XCTAssertEqual(model.selectedIDs, selected)
        model.cancelImport()
        for _ in 0..<500 {
            if !model.isImporting { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.isImporting)
        XCTAssertNotNil(model.importError)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.library.path).isEmpty)
    }

    private struct Fixture {
        let base: URL
        let source: URL
        let library: URL
        let journal: URL
        var finalJPEG: URL { library.appendingPathComponent("2026/2026-11-21/JPEG/capture.JPG") }
        var finalRAW: URL { library.appendingPathComponent("2026/2026-11-21/RAW/capture.RW2") }

        init() throws {
            base = try TestPhotoFixtures.directory()
            source = base.appendingPathComponent("sd")
            library = base.appendingPathComponent("ssd")
            journal = base.appendingPathComponent("local-journal")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
            try TestPhotoFixtures.jpeg("capture.JPG", root: source, original: "2026:11:21 12:00:00")
            try TestPhotoFixtures.write("capture.RW2", root: source)
        }

        func plan(format: PhotoFormatFilter = .all) async throws -> ImportPlan {
            let captures = try await PhotoScanner().scan(root: source).captures
            let result = try await ImportPlanner().plan(source: source, library: library, captures: captures, format: format, event: "")
            XCTAssertFalse(result.hasBlockingIssues, result.blockers.joined(separator: "; "))
            return result
        }

        func service(capacity: Int64? = nil, checkpoint: @escaping @Sendable (CopyCheckpoint) throws -> Void = { _ in }) -> ImportService {
            ImportService(journalRoot: journal, volumeReader: { url in
                var actual = try LibraryVolumeInfo.read(at: url)
                if let capacity { actual.availableBytes = capacity }
                return actual
            }, checkpoint: checkpoint)
        }

        func remove() { try? FileManager.default.removeItem(at: base) }
    }

    private struct Snapshot: Equatable {
        let bytes: Data
        let modified: Date?
        let created: Date?
        let mode: Int
    }

    private func snapshot(_ root: URL) throws -> [String: Snapshot] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var result: [String: Snapshot] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .creationDateKey, .contentModificationDateKey])
            guard values.isRegularFile == true else { continue }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            result[url.path] = Snapshot(bytes: try Data(contentsOf: url), modified: values.contentModificationDate,
                                        created: values.creationDate, mode: (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0)
        }
        return result
    }

    private func partials(_ root: URL) throws -> [URL] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        return (enumerator.allObjects as? [URL] ?? []).filter { $0.pathExtension == "partial" }
    }
}
