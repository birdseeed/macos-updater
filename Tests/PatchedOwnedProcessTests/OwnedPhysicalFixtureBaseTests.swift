import Foundation
import Testing
import Darwin
@testable import PatchedDisposableProof

// Test-target internal private fixture setup; no product capability is added.
enum OwnedPhysicalFixtureBase {
    static func open(in parent: HeldDirectory, name: String = "owned-physical-fixtures") throws -> HeldDirectory {
        try parent.confirm()
        try parent.owned()
        try requirePrivateACL(parent)
        let opened: HeldDirectory
        do { opened = try parent.mkdir(name) }
        catch DisposableFailure.existingRoot { opened = try parent.child(name) }
        do {
            try parent.confirm()
            try opened.confirm()
            try opened.owned(privateMode: true)
            try requirePrivateACL(opened)
            return opened
        } catch {
            opened.closeDescriptor()
            throw error
        }
    }
}

@Suite("OwnedProcessLifecycleTests.OwnedPhysicalFixtureBaseTests", .serialized)
struct OwnedPhysicalFixtureBaseOwnedProcessLifecycleTests {
    private final class Scratch {
        let base: HeldDirectory
        let arena: HeldDirectory
        let name = "base-check-" + UUID().uuidString
        init() throws {
            let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            // The same seam handles the real base, so test ordering cannot require
            // parent provisioning on a genuinely clean checkout.
            let build = try HeldDirectory.absolute(project.appendingPathComponent(".build").path)
            base = try OwnedPhysicalFixtureBase.open(in: build)
            try base.owned(privateMode: true); try requirePrivateACL(base)
            arena = try base.mkdir(name)
            var complete = false
            defer {
                if !complete {
                    arena.closeDescriptor(); _ = unlinkat(base.fd, name, AT_REMOVEDIR)
                    base.closeOwnedChain()
                }
            }
            try requirePrivateACL(arena)
            complete = true
        }
        deinit {
            // Fixed bounded children of our unique arena; never recurse or follow links.
            for child in ["base", "prior"] {
                _ = unlinkat(arena.fd, child, 0)
                _ = unlinkat(arena.fd, child, AT_REMOVEDIR)
            }
            arena.closeDescriptor(); _ = unlinkat(base.fd, name, AT_REMOVEDIR)
            base.closeOwnedChain()
        }
    }
    private func valid(_ parent: HeldDirectory, _ name: String = "base") throws -> HeldDirectory {
        let opened = try OwnedPhysicalFixtureBase.open(in: parent, name: name)
        try opened.confirm(); try opened.owned(privateMode: true); try requirePrivateACL(opened)
        let info = try opened.status(), named = try #require(try parent.named(name))
        try #require(info.st_mode & S_IFMT == S_IFDIR)
        try #require(info.st_uid == getuid()); try #require(permissions(info) == 0o700)
        try #require(sameIdentity(info, named))
        return opened
    }
    private func positiveControl(_ s: Scratch) throws {
        try #require(s.arena.named("base") == nil)
        let first = try valid(s.arena), before = try first.status()
        let second = try valid(s.arena), after = try second.status()
        try #require(stable(before, after))
        first.closeDescriptor(); second.closeDescriptor()
        try #require(unlinkat(s.arena.fd, "base", AT_REMOVEDIR) == 0)
    }
    @Test func absentBaseCreatedPrivateWithoutACLAndReusedWithoutMutation() throws {
        let s = try Scratch(); try positiveControl(s)
    }
    @Test func independentlyExistingValidBaseReusedWithoutMutation() throws {
        let s = try Scratch()
        let prior = try s.arena.mkdir("base")
        try requirePrivateACL(prior)
        let before = try prior.status(), aclBefore = try aclText(prior.fd)
        let reused = try valid(s.arena)
        #expect(stable(before, try reused.status()))
        #expect(try aclText(reused.fd) == aclBefore)
        prior.closeDescriptor(); reused.closeDescriptor()
    }
    private func aclText(_ fd: Int32) throws -> String {
        errno = 0
        guard let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) else {
            try #require(errno == ENOENT); return "<no-acl>"
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        try #require(acl_valid(acl) == 0)
        var count = 0
        let text = try #require(acl_to_text(acl, &count))
        defer { acl_free(UnsafeMutableRawPointer(text)) }
        return String(cString: text)
    }
    private func addACL(_ fd: Int32) throws {
        var acl = acl_init(1)
        try #require(acl != nil)
        defer { if let acl { acl_free(UnsafeMutableRawPointer(acl)) } }
        var entry: acl_entry_t?
        try #require(acl_create_entry(&acl, &entry) == 0)
        let e = try #require(entry)
        try #require(acl_set_tag_type(e, ACL_EXTENDED_ALLOW) == 0)
        // Darwin's well-known everyone UUID. No account lookup or owner change.
        var everyone = UUID(uuidString: "ABCDEFAB-CDEF-ABCD-EFAB-CDEF0000000C")!.uuid
        try #require(acl_set_qualifier(e, &everyone) == 0)
        var permissions: acl_permset_t?
        try #require(acl_get_permset(e, &permissions) == 0)
        let p = try #require(permissions)
        try #require(acl_clear_perms(p) == 0)
        try #require(acl_add_perm(p, ACL_READ_DATA) == 0)
        let a = try #require(acl)
        try #require(acl_valid(a) == 0)
        try #require(acl_set_fd_np(fd, a, ACL_TYPE_EXTENDED) == 0)
    }
    enum PriorFault: CaseIterable { case symlink, regularFile, unsafeMode, extendedACL }
    @Test(arguments: PriorFault.allCases)
    func invalidPriorObjectRefusedWithoutMutation(_ fault: PriorFault) throws {
        let s = try Scratch(); try positiveControl(s) // Always-refusing stubs fail here.
        var held: HeldDirectory?
        var regularFD: Int32 = -1
        defer { held?.closeDescriptor(); if regularFD >= 0 { _ = close(regularFD) } }
        switch fault {
        case .symlink:
            held = try s.arena.mkdir("prior")
            try #require(symlinkat("prior", s.arena.fd, "base") == 0)
        case .regularFile:
            regularFD = openat(s.arena.fd, "base", O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            try #require(regularFD >= 0)
            try PhysicalIO.writeAll(regularFD, Data("preserve-prior-object".utf8))
        case .unsafeMode:
            held = try s.arena.mkdir("base")
            try #require(fchmod(held!.fd, 0o750) == 0)
        case .extendedACL:
            held = try s.arena.mkdir("base")
            try addACL(held!.fd)
        }
        let before = try #require(try s.arena.named("base"))
        let priorBefore = try s.arena.named("prior")
        let aclBefore = try held.map { try aclText($0.fd) }
        if case .extendedACL = fault {
            var entries = 0
            try aclEntries(held!) { _ in entries += 1 }
            try #require(entries == 1)
        }
        do {
            let unexpected = try OwnedPhysicalFixtureBase.open(in: s.arena, name: "base")
            unexpected.closeDescriptor(); Issue.record("Invalid prior fixture base accepted")
        } catch is DisposableFailure {
            // Type-specific safe-path/owner/mode refusals are intentionally permitted.
        } catch { Issue.record(Comment(rawValue: "Unexpected refusal type: \(error)")) }
        let after = try #require(try s.arena.named("base"))
        #expect(stable(before, after))
        if let priorBefore { #expect(stable(priorBefore, try #require(try s.arena.named("prior")))) }
        if let held { #expect(try aclText(held.fd) == aclBefore) }
        if regularFD >= 0 {
            var bytes = [UInt8](repeating: 0, count: 21)
            let count = pread(regularFD, &bytes, bytes.count, 0)
            #expect(count == 21); #expect(Data(bytes) == Data("preserve-prior-object".utf8))
        }
        if case .symlink = fault {
            var bytes = [UInt8](repeating: 0, count: 16)
            let count = readlinkat(s.arena.fd, "base", &bytes, bytes.count)
            #expect(count == 5); #expect(Array(bytes.prefix(5)) == Array("prior".utf8))
        }
    }
}
