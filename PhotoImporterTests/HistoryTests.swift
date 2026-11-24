import XCTest
import Darwin
@testable import PhotoImporter

@MainActor
final class HistoryTests: XCTestCase {
    func testListingPreservesValidAndLegacyRecordsWhileReportingCorruption() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let record = try await f.importAll()
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as! [String: Any]
        let legacyID = UUID()
        legacy["id"] = legacyID.uuidString
        legacy["schemaVersion"] = 1
        legacy["files"] = (legacy["files"] as! [[String: Any]]).enumerated().map { index, value in
            var file = value
            file.removeValue(forKey: "sourceSnapshot")
            file.removeValue(forKey: "temporarySnapshot")
            file["temporaryName"] = ".photoimporter-\(legacyID.uuidString)-\(index).partial"
            return file
        }
        try JSONSerialization.data(withJSONObject: legacy).write(to: f.journal.appendingPathComponent(legacyID.uuidString + ".json"))
        try Data("bad JSON".utf8).write(to: f.journal.appendingPathComponent(UUID().uuidString + ".json"))
        let listing = try await f.service.historyList()
        XCTAssertEqual(listing.entries.count, 2)
        XCTAssertEqual(listing.issues.count, 1)
        XCTAssertTrue(listing.entries.contains { $0.record.schemaVersion == 1 })
        XCTAssertTrue(listing.entries.contains { $0.record.schemaVersion == 2 })
    }

    func testUnfinishedRecordIsShownAsInterruptedAndActiveLeaseBlocksActions() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let record = try await f.interrupted()
        let listing = try await f.service.historyList()
        XCTAssertEqual(listing.entries.first?.title, "Importação interrompida")
        let lease = try ImportJournal(root: f.journal).lock(record.id)
        defer { lease.unlock() }
        let active = try await f.service.historyList()
        XCTAssertEqual(active.entries.first?.isActive, true)
        do {
            _ = try await f.service.inspectTemporaries(record.id, library: f.library)
            XCTFail("An active operation must be protected")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSPOSIXErrorDomain)
            XCTAssertEqual((error as NSError).code, Int(EWOULDBLOCK))
        }
    }

    func testReconciliationReportsMissingAndChangedWithoutRewritingRecordedOutcome() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let record = try await f.importAll()
        try FileManager.default.removeItem(at: f.final(record.files[0]))
        let raw = f.final(record.files[1])
        var bytes = try Data(contentsOf: raw)
        bytes[0] ^= 0xFF
        try bytes.write(to: raw)
        let checks = try await f.service.reconcile(record.id, library: f.library)
        XCTAssertEqual(checks.map(\.state), [.missing, .different])
        let saved = try ImportJournal(root: f.journal).load(record.id)
        XCTAssertEqual(saved.state, .completed)
        XCTAssertTrue(saved.files.allSatisfy { $0.status == .copied })
    }

    func testLegacyRunningWithoutActivityLockDoesNotAuthorizeRecoveryOrCleanup() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let record = try await f.interrupted()
        var raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as! [String: Any]
        raw["schemaVersion"] = 1
        try JSONSerialization.data(withJSONObject: raw).write(to: f.journal.appendingPathComponent(record.id.uuidString + ".json"))
        let listing = try await f.service.historyList()
        XCTAssertTrue(listing.entries[0].isActive)
        XCTAssertTrue(listing.issues.contains { $0.contains("sem trava") })
        do { _ = try await f.service.inspectTemporaries(record.id, library: f.library); XCTFail("Unknown legacy activity") }
        catch { XCTAssertTrue(error is ImportJournalError) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.temporary(record.files[0]).path))
    }

    func testPublishedFileCanVerifyEvenWhenRecordedOutcomeWasFailure() async throws {
        let f = try Fixture()
        defer { f.remove() }
        var record = try await f.importAll()
        record.state = .running
        record.finishedAt = nil
        record.files[0].status = .verified
        try ImportJournal(root: f.journal).save(record)
        let checks = try await f.service.reconcile(record.id, library: f.library)
        XCTAssertTrue(checks.allSatisfy { $0.state == .verified })
        let plan = try await f.service.prepareRecovery(record.id, source: f.source, library: f.library)
        XCTAssertTrue(plan.files.isEmpty)
        XCTAssertTrue(plan.blockers.contains { $0.contains("Nenhuma cópia necessária") })
    }

    func testPresenceWithoutRecordedChecksumIsNotVerification() async throws {
        let f = try Fixture()
        defer { f.remove() }
        var record = try await f.importAll()
        for index in record.files.indices { record.files[index].sha256 = nil }
        try ImportJournal(root: f.journal).save(record)
        let checks = try await f.service.reconcile(record.id, library: f.library)
        XCTAssertTrue(checks.allSatisfy { $0.state == .unknown })
    }

    func testRecoveryOfInterruptedPairKeepsPathsAndRecordsNewLinkedOperation() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let interrupted = try await f.interrupted()
        let before = try Data(contentsOf: f.source.appendingPathComponent("capture.JPG"))
        let plan = try await f.service.prepareRecovery(interrupted.id, source: f.source, library: f.library)
        XCTAssertFalse(plan.hasBlockingIssues, plan.blockers.joined(separator: "; "))
        XCTAssertEqual(plan.files.count, 2)
        XCTAssertEqual(plan.recoveryOf, interrupted.id)
        XCTAssertEqual(plan.files.compactMap(\.relativeDestination), interrupted.files.map(\.destinationRelativePath))
        let result = try await f.service.run(plan)
        XCTAssertEqual(result.state, .completed, result.error ?? "")
        XCTAssertEqual(result.copiedCount, 2)
        XCTAssertEqual(result.recoveryOf, interrupted.id)
        XCTAssertEqual(try Data(contentsOf: f.source.appendingPathComponent("capture.JPG")), before)
        let listing = try await f.service.historyList()
        XCTAssertEqual(listing.entries.count, 2)
        let assessment = try await f.service.assessImported(source: f.source, library: f.library, files: f.files(plan))
        XCTAssertEqual(assessment.verifiedIDs.count, 2)
        let checks = try await f.service.reconcile(interrupted.id, library: f.library)
        XCTAssertTrue(checks.allSatisfy { $0.state == .verified })
        XCTAssertTrue(try ImportJournal(root: f.journal).load(interrupted.id).files.allSatisfy { $0.sha256 == nil })
    }

    func testRecoveryExcludesIntactHalfAndCopiesOnlyMissingHalf() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let record = try await f.importAll()
        let intact = try Data(contentsOf: f.final(record.files[0]))
        try FileManager.default.removeItem(at: f.final(record.files[1]))
        let plan = try await f.service.prepareRecovery(record.id, source: f.source, library: f.library)
        XCTAssertEqual(plan.files.count, 1)
        XCTAssertEqual(plan.files[0].source.format, .raw)
        let result = try await f.service.run(plan)
        XCTAssertEqual(result.copiedCount, 1)
        XCTAssertEqual(try Data(contentsOf: f.final(record.files[0])), intact)
    }

    func testReconciliationFollowsSeveralInterruptedRecoveryAttempts() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let first = try await f.interrupted()
        let plan = try await f.service.prepareRecovery(first.id, source: f.source, library: f.library)
        let partialService = ImportService(journalRoot: f.journal, checkpoint: { point in
            if point.phase == .temporaryCreated && point.source.pathExtension == "RW2" { throw CancellationError() }
        })
        let second = try await partialService.run(plan)
        XCTAssertEqual(second.copiedCount, 1)
        XCTAssertEqual(second.state, .cancelled)
        let next = try await f.service.prepareRecovery(second.id, source: f.source, library: f.library)
        let third = try await f.service.run(next)
        XCTAssertEqual(third.copiedCount, 1)
        let checks = try await f.service.reconcile(first.id, library: f.library)
        XCTAssertTrue(checks.allSatisfy { $0.state == .verified })
    }

    func testChangedSourceAndConflictingDestinationBlockRecovery() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let record = try await f.interrupted()
        let source = f.source.appendingPathComponent("capture.JPG")
        var bytes = try Data(contentsOf: source)
        bytes[0] ^= 0xFF
        try bytes.write(to: source)
        let plan = try await f.service.prepareRecovery(record.id, source: f.source, library: f.library)
        XCTAssertTrue(plan.files.first { $0.source.format == .jpeg }!.state.isBlocked)
        let raw = f.final(record.files[1])
        try FileManager.default.createDirectory(at: raw.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("foreign file".utf8).write(to: raw)
        let conflict = try await f.service.prepareRecovery(record.id, source: f.source, library: f.library)
        XCTAssertTrue(conflict.files.allSatisfy { $0.state.isBlocked })
        XCTAssertEqual(try Data(contentsOf: raw), Data("foreign file".utf8))
    }

    func testLegacyUnhashedPendingFileRequiresNewDiscovery() async throws {
        let f = try Fixture()
        defer { f.remove() }
        var record = try await f.interrupted()
        for index in record.files.indices { record.files[index].sourceSnapshot = nil; record.files[index].sha256 = nil }
        try ImportJournal(root: f.journal).save(record)
        let plan = try await f.service.prepareRecovery(record.id, source: f.source, library: f.library)
        XCTAssertEqual(plan.blockedCount, 2)
        XCTAssertTrue(plan.files.allSatisfy { $0.state.detail.contains("Registro antigo") })
    }

    func testCleanupRemovesOnlyRegisteredOwnedTemporaryAndPreservesFinalAndUnknownFiles() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let record = try await f.interrupted()
        let temporary = f.temporary(record.files[0])
        let unknown = temporary.deletingLastPathComponent().appendingPathComponent(".photoimporter-unknown.partial")
        let final = f.final(record.files[0])
        try Data("user final".utf8).write(to: final)
        try Data("unknown temp".utf8).write(to: unknown)
        let candidates = try await f.service.inspectTemporaries(record.id, library: f.library)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertTrue(candidates[0].removable)
        let messages = try await f.service.cleanTemporaries(record.id, library: f.library, approved: candidates)
        XCTAssertEqual(messages.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
        XCTAssertEqual(try Data(contentsOf: final), Data("user final".utf8))
        XCTAssertEqual(try Data(contentsOf: unknown), Data("unknown temp".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.source.appendingPathComponent("capture.JPG").path))
    }

    func testStaleCleanupApprovalCannotDeleteReplacement() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let record = try await f.interrupted()
        let candidates = try await f.service.inspectTemporaries(record.id, library: f.library)
        let temporary = f.temporary(record.files[0])
        try FileManager.default.removeItem(at: temporary)
        let replacement = Data("replacement".utf8)
        try replacement.write(to: temporary)
        let messages = try await f.service.cleanTemporaries(record.id, library: f.library, approved: candidates)
        XCTAssertTrue(messages[0].contains("Preservado"))
        XCTAssertEqual(try Data(contentsOf: temporary), replacement)
    }

    func testLegacyTemporaryWithoutIdentityAndSymbolicLinkArePreserved() async throws {
        let f = try Fixture()
        defer { f.remove() }
        var record = try await f.interrupted()
        record.files[0].temporarySnapshot = nil
        try ImportJournal(root: f.journal).save(record)
        let legacy = try await f.service.inspectTemporaries(record.id, library: f.library)
        XCTAssertFalse(legacy[0].removable)
        let temporary = f.temporary(record.files[0])
        try FileManager.default.removeItem(at: temporary)
        try FileManager.default.createSymbolicLink(at: temporary, withDestinationURL: f.source.appendingPathComponent("capture.JPG"))
        let linked = try await f.service.inspectTemporaries(record.id, library: f.library)
        XCTAssertFalse(linked[0].removable)
        let before = try Data(contentsOf: f.source.appendingPathComponent("capture.JPG"))
        _ = try await f.service.cleanTemporaries(record.id, library: f.library, approved: linked)
        XCTAssertEqual(try Data(contentsOf: f.source.appendingPathComponent("capture.JPG")), before)
    }

    func testReusedFileIdentifierWithoutMatchingCreationTimeIsNotOwned() async throws {
        let f = try Fixture()
        defer { f.remove() }
        var record = try await f.interrupted()
        let temporary = f.temporary(record.files[0])
        try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 1_000_000_000)], ofItemAtPath: temporary.path)
        record.files[0].temporarySnapshot = try PlanningPaths.node(at: temporary)?.snapshot
        try FileManager.default.removeItem(at: temporary)
        let foreign = Data("replacement".utf8)
        try foreign.write(to: temporary)
        let actual = try XCTUnwrap(PlanningPaths.node(at: temporary)?.snapshot)
        var raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as! [String: Any]
        var files = raw["files"] as! [[String: Any]]
        var snapshot = files[0]["temporarySnapshot"] as! [String: Any]
        // Simulate a removable filesystem reusing an inode; retain the original birth time.
        snapshot["identity"] = ["device": actual.identity.device, "inode": actual.identity.inode]
        files[0]["temporarySnapshot"] = snapshot
        raw["files"] = files
        try JSONSerialization.data(withJSONObject: raw).write(to: f.journal.appendingPathComponent(record.id.uuidString + ".json"))
        let candidates = try await f.service.inspectTemporaries(record.id, library: f.library)
        XCTAssertFalse(candidates[0].removable)
        _ = try await f.service.cleanTemporaries(record.id, library: f.library, approved: candidates)
        XCTAssertEqual(try Data(contentsOf: temporary), foreign)
    }

    func testWrongFolderOrVolumeDoesNotAuthorizeReconciliationOrCleanup() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let record = try await f.interrupted()
        let another = f.base.appendingPathComponent("wrong")
        try FileManager.default.createDirectory(at: another, withIntermediateDirectories: true)
        do { _ = try await f.service.reconcile(record.id, library: another); XCTFail("Wrong folder") } catch {}
        do { _ = try await f.service.prepareRecovery(record.id, source: another, library: f.library); XCTFail("Wrong source") } catch {}
        do { _ = try await f.service.inspectTemporaries(record.id, library: another); XCTFail("Wrong folder") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.temporary(record.files[0]).path))
    }

    func testHardLinkedTemporaryCannotAuthorizeDeletingAnOriginal() async throws {
        let f = try Fixture()
        defer { f.remove() }
        var record = try await f.interrupted()
        let temporary = f.temporary(record.files[0])
        let original = f.source.appendingPathComponent("capture.JPG")
        let before = try Data(contentsOf: original)
        try FileManager.default.removeItem(at: temporary)
        try FileManager.default.linkItem(at: original, to: temporary)
        record.files[0].temporarySnapshot = try PlanningPaths.node(at: temporary)?.snapshot
        try ImportJournal(root: f.journal).save(record)
        let candidates = try await f.service.inspectTemporaries(record.id, library: f.library)
        XCTAssertFalse(candidates[0].removable)
        _ = try await f.service.cleanTemporaries(record.id, library: f.library, approved: candidates)
        XCTAssertEqual(try Data(contentsOf: original), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporary.path))
    }

    func testTamperedPathsAndTemporaryNamesAreRejectedBeforeDeletion() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let record = try await f.interrupted()
        var raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as! [String: Any]
        var files = raw["files"] as! [[String: Any]]
        files[0]["destinationRelativePath"] = "../outside.JPG"
        files[0]["temporaryName"] = "capture.JPG"
        raw["files"] = files
        try JSONSerialization.data(withJSONObject: raw).write(to: f.journal.appendingPathComponent(record.id.uuidString + ".json"))
        let listing = try await f.service.historyList()
        XCTAssertTrue(listing.entries.isEmpty)
        XCTAssertEqual(listing.issues.count, 1)
        do { _ = try await f.service.inspectTemporaries(record.id, library: f.library); XCTFail("Invalid record") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.temporary(record.files[0]).path))
    }

    func testNotImportedFilterHandlesPartialPairAndKeepsCaptureDateAndReport() async throws {
        let f = try Fixture()
        defer { f.remove() }
        _ = try await f.service.run(f.plan(format: .jpeg))
        let model = TestPhotoFixtures.model(importer: f.service)
        model.discover(f.source)
        try await TestPhotoFixtures.waitForDiscovery(model)
        model.setLibrary(f.library)
        model.filters.onlyNotImported = true
        try await wait { !model.isCheckingImported }
        XCTAssertEqual(model.verifiedImportedIDs, ["capture.JPG"])
        XCTAssertEqual(model.visibleCaptures.count, 1)
        model.selectVisible()
        XCTAssertEqual(model.selectedSummary.fileCount, 1)
        model.generatePlan()
        try await wait { !model.isPlanning }
        let plan = try XCTUnwrap(model.plan)
        XCTAssertEqual(plan.files.count, 1)
        XCTAssertEqual(plan.files[0].relativeDestination, "2026/2026-11-21/RAW/capture.RW2")
        model.startImport()
        try await wait { !model.isImporting && !model.isCheckingImported }
        XCTAssertEqual(model.importReport?.copiedCount, 1)
        XCTAssertTrue(model.isShowingPlan)
        XCTAssertTrue(model.visibleCaptures.isEmpty)
        XCTAssertEqual(model.selectedSummary.fileCount, 0)
    }

    func testRemovedOrChangedDestinationBecomesNotImportedAgain() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let record = try await f.importAll()
        let files = try await PhotoScanner().scan(root: f.source).captures.flatMap(\.files)
        let first = try await f.service.assessImported(source: f.source, library: f.library, files: files)
        XCTAssertEqual(first.verifiedIDs.count, 2)
        try FileManager.default.removeItem(at: f.final(record.files[0]))
        let raw = f.final(record.files[1])
        var bytes = try Data(contentsOf: raw)
        bytes[0] ^= 0xFF
        try bytes.write(to: raw)
        let next = try await f.service.assessImported(source: f.source, library: f.library, files: files)
        XCTAssertTrue(next.verifiedIDs.isEmpty)
    }

    func testHomonymousSourceWithDifferentContentsIsNeverHidden() async throws {
        let f = try Fixture()
        defer { f.remove() }
        _ = try await f.importAll()
        let jpeg = f.source.appendingPathComponent("capture.JPG")
        var bytes = try Data(contentsOf: jpeg)
        bytes[0] ^= 0xFF
        try bytes.write(to: jpeg)
        let files = try await PhotoScanner().scan(root: f.source).captures.flatMap(\.files)
        let assessment = try await f.service.assessImported(source: f.source, library: f.library, files: files)
        XCTAssertFalse(assessment.verifiedIDs.contains("capture.JPG"))
        XCTAssertTrue(assessment.verifiedIDs.contains("capture.RW2"))
    }

    func testCancelledCleanupLeavesTemporaryUntouched() async throws {
        let f = try Fixture()
        defer { f.remove() }
        let record = try await f.interrupted()
        let candidates = try await f.service.inspectTemporaries(record.id, library: f.library)
        let task = Task { try await f.service.cleanTemporaries(record.id, library: f.library, approved: candidates) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.temporary(record.files[0]).path))
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<800 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Operation did not finish")
    }

    private struct Fixture {
        let base: URL
        let source: URL
        let library: URL
        let journal: URL
        let service: ImportService

        init() throws {
            base = try TestPhotoFixtures.directory()
            source = base.appendingPathComponent("sd")
            library = base.appendingPathComponent("ssd")
            journal = base.appendingPathComponent("journal")
            service = ImportService(journalRoot: journal)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
            try TestPhotoFixtures.jpeg("capture.JPG", root: source, original: "2026:11:21 12:00:00")
            try TestPhotoFixtures.write("capture.RW2", root: source)
        }

        func plan(format: PhotoFormatFilter = .all) async throws -> ImportPlan {
            let captures = try await PhotoScanner().scan(root: source).captures
            return try await ImportPlanner().plan(source: source, library: library, captures: captures, format: format, event: "")
        }

        func importAll() async throws -> ImportRecord { try await service.run(plan()) }

        func interrupted() async throws -> ImportRecord {
            let plan = try await plan()
            let id = UUID()
            var record = ImportRecord(schemaVersion: 2, id: id, startedAt: .now, sourceRootPath: source.path,
                                      libraryRootPath: library.path, sourceIdentity: plan.sourceIdentity,
                                      libraryIdentity: plan.libraryIdentity, sourceVolumeID: plan.sourceVolumeID,
                                      libraryVolumeID: plan.libraryVolumeID,
                                      files: plan.files.enumerated().map { index, item in
                ImportFileRecord(id: item.id, sourceRelativePath: item.source.relativePath,
                                 destinationRelativePath: item.relativeDestination!, byteCount: item.source.byteCount,
                                 temporaryName: ".photoimporter-\(id.uuidString)-\(index).partial", sourceSnapshot: item.sourceSnapshot)
            })
            let url = temporary(record.files[0])
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try Data(contentsOf: source.appendingPathComponent(record.files[0].sourceRelativePath))
            try data.prefix(data.count / 2).write(to: url)
            record.files[0].status = .copying
            record.files[0].temporarySnapshot = try PlanningPaths.node(at: url)?.snapshot
            try ImportJournal(root: journal).save(record)
            return record
        }

        func final(_ file: ImportFileRecord) -> URL { library.appendingPathComponent(file.destinationRelativePath) }
        func temporary(_ file: ImportFileRecord) -> URL { final(file).deletingLastPathComponent().appendingPathComponent(file.temporaryName) }
        func files(_ plan: ImportPlan) -> [PhotoFile] { plan.files.map(\.source) }
        func remove() { try? FileManager.default.removeItem(at: base) }
    }
}
