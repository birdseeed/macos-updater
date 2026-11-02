import Foundation
import Darwin
@_spi(Testing) import PatchedCore

@MainActor func registerAuthorityChecks() {
    check("fixture authority exclusively creates a private marked root beneath this build directory") {
        try withRoot { authority, layout in
            try expect(authority.root == layout.root.path, "Authority reported a different root")
            let info = try status(layout.root)
            try expect(info.st_mode & S_IFMT == S_IFDIR && info.st_mode & 0o7777 == 0o700 && info.st_uid == geteuid(), "Fixture root is not a private owned directory")
            try expect(try layout.root.deletingLastPathComponent().path == buildDirectory(), "Fixture root is not directly beneath .build")
            try expect(try topLevel(layout.root) == ["fixture-root.json"], "A fresh root must hold only its marker")
            let file = layout.root.appendingPathComponent("fixture-root.json"), marker = try object(Data(contentsOf: file))
            try expect(Set(marker.keys) == ["schemaVersion", "kind", "device", "inode"], "Marker fields differ from the contract")
            try expect(unsigned(marker["schemaVersion"]) == 1 && marker["kind"] as? String == "patched-transaction-fixture-root-v1" &&
                       unsigned(marker["device"]) == UInt64(UInt32(bitPattern: info.st_dev)) && unsigned(marker["inode"]) == UInt64(info.st_ino),
                       "Marker does not record the physically observed root identity")
            let markerInfo = try status(file)
            try expect(markerInfo.st_mode & S_IFMT == S_IFREG && markerInfo.st_mode & 0o7777 == 0o600 && markerInfo.st_nlink == 1, "Marker is not a private single-link file")
        }
    }
    let refusals: [(String, TransactionFailure, (URL) throws -> String)] = [
        ("outside any build directory", .notAuthorized, { _ in
            guard let physical = realpath(NSTemporaryDirectory(), nil) else { throw CheckFailure(description: "No temporary directory") }
            defer { free(physical) }
            return String(cString: physical) + "/" + Sample.rootPrefix + UUID().uuidString }),
        ("beneath a foreign package build directory", .notAuthorized, { scratch in
            let package = scratch.appendingPathComponent("foreign"); try makeDirectory(package, mode: 0o700)
            try writeFile(Data("// swift-tools-version: 6.0\n".utf8), package.appendingPathComponent("Package.swift"))
            try makeDirectory(package.appendingPathComponent(".build"), mode: 0o700)
            return package.path + "/.build/" + Sample.rootPrefix + UUID().uuidString }),
        ("nested below the build directory", .notAuthorized, { $0.path + "/" + Sample.rootPrefix + UUID().uuidString }),
        ("with an unexpected name", .unsafePath, { _ in try buildDirectory() + "/core-fixture-" + UUID().uuidString }),
        ("by relative path", .unsafePath, { _ in ".build/" + Sample.rootPrefix + UUID().uuidString }),
        ("by traversal", .unsafePath, { _ in try buildDirectory() + "/../.build/" + Sample.rootPrefix + UUID().uuidString }),
        ("through a symlinked build alias", .symlink, { scratch in
            try symlinkTo(URL(fileURLWithPath: try buildDirectory()), at: scratch.appendingPathComponent(".build"))
            return scratch.path + "/.build/" + Sample.rootPrefix + UUID().uuidString })
    ]
    for (name, reason, location) in refusals {
        check("fixture authority refuses a root \(name)") {
            try withScratch { scratch in
                let path = try location(scratch), leaf = URL(fileURLWithPath: path).lastPathComponent
                defer { rmdir(path); if let build = try? buildDirectory() { removeFixture(build + "/" + leaf) } }
                try refuses(reason) { _ = try FixtureAuthority.createFreshRoot(path: path) }
                try expect(!exists(URL(fileURLWithPath: path)) && !exists(URL(fileURLWithPath: try buildDirectory() + "/" + leaf)),
                           "A refused root was created")
            }
        }
    }
    for existing in ["authority-created", "test-created empty"] {
        check("fixture authority never adopts an existing \(existing) root") {
            let path = try freshRootPath()
            defer { removeFixture(path) }
            if existing == "authority-created" { _ = try FixtureAuthority.createFreshRoot(path: path) }
            else { try makeDirectory(URL(fileURLWithPath: path), mode: 0o700) }
            let before = try walk(path)
            try refuses(.existingRoot) { _ = try FixtureAuthority.createFreshRoot(path: path) }
            try expectSame(before, try walk(path), "Refused creation changed the existing directory")
        }
    }
    check("a fresh authority reopens only the root whose physical identity its marker records") {
        try withRoot { _, layout in
            try expect(try FixtureAuthority.reopenRoot(path: layout.root.path).root == layout.root.path, "Reopened a different root")
            let copy = URL(fileURLWithPath: try freshRootPath())
            defer { removeFixture(copy.path) }
            try makeDirectory(copy, mode: 0o700)
            try refuses(.notAuthorized) { _ = try FixtureAuthority.reopenRoot(path: copy.path) }
            try writeFile(Data(contentsOf: layout.root.appendingPathComponent("fixture-root.json")), copy.appendingPathComponent("fixture-root.json"), mode: 0o600)
            try refuses(.notAuthorized) { _ = try FixtureAuthority.reopenRoot(path: copy.path) }
            try setMode(layout.root, 0o755)
            try refuses(.unsafeMode) { _ = try FixtureAuthority.reopenRoot(path: layout.root.path) }
        }
    }

    check("default production entry refuses a complete valid fixture request and touches nothing") {
        try withRoot { _, layout in
            let prepared = try seeded(layout)
            try expect(!prepared.candidate.installationAuthorized && !prepared.candidate.freshOSValidation, "Fixture candidate carried authority")
            let before = try walk(layout.root.path)
            try refuses(.notAuthorized) { _ = try UpdateTransaction.perform(prepared.request) }
            try expectSame(before, try walk(layout.root.path), "Unauthorised default entry changed the fixture")
        }
    }
    check("default production recovery refuses beside a real committed fixture transaction") {
        try withRoot { authority, layout in
            let prepared = try seeded(layout)
            _ = try authority.perform(prepared.request, hooks: idle())
            let before = try walk(layout.root.path)
            try refuses(.notAuthorized) { _ = try UpdateTransaction.recover(transactionDirectory: layout.transaction.path) }
            try refuses(.notAuthorized) { _ = try UpdateTransaction.perform(prepared.request) }
            try expectSame(before, try walk(layout.root.path), "Unauthorised default entry changed a committed fixture")
        }
    }

    // Request-shape refusals are decided from the named strings and the authority's own layout.
    let requests: [(String, TransactionFailure, (Prepared, Layout) -> UpdateRequest)] = [
        ("background trigger", .userTriggerRequired, { p, _ in p.requesting(trigger: .background) }),
        ("relative target", .unsafePath, { p, _ in p.requesting(target: "Applications/" + Sample.bundleName) }),
        ("target traversal", .unsafePath, { p, l in p.requesting(target: l.root.path + "/Applications/../Applications/" + Sample.bundleName) }),
        ("target with a trailing slash", .unsafePath, { p, l in p.requesting(target: l.target.path + "/") }),
        ("target with an empty component", .unsafePath, { p, l in p.requesting(target: l.applications.path + "//" + Sample.bundleName) }),
        ("target with a dot component", .unsafePath, { p, l in p.requesting(target: l.applications.path + "/./" + Sample.bundleName) }),
        ("relative source", .unsafePath, { p, _ in p.requesting(source: "Incoming/" + Sample.bundleName) }),
        ("source traversal", .unsafePath, { p, l in p.requesting(source: l.incoming.path + "/../Incoming/" + Sample.bundleName) }),
        ("transaction directory traversal", .unsafePath, { p, l in p.requesting(transaction: l.root.path + "/Transaction/../Transaction") }),
        ("source aliased to the target", .aliasedPath, { p, l in p.requesting(source: l.target.path) }),
        ("target aliased to the source", .aliasedPath, { p, l in p.requesting(target: l.source.path) }),
        ("target in the ordinary applications directory", .notAuthorized, { p, _ in p.requesting(target: "/Applications/" + Sample.bundleName) }),
        ("existing unrelated app as target", .notAuthorized, { p, l in p.requesting(target: l.other.path) }),
        ("target nested below the applications directory", .notAuthorized, { p, l in p.requesting(target: l.applications.path + "/Nested/" + Sample.bundleName) }),
        ("target outside the applications directory", .notAuthorized, { p, l in p.requesting(target: l.profile.path + "/" + Sample.bundleName) }),
        ("source outside the incoming directory", .notAuthorized, { p, l in p.requesting(source: l.profile.path + "/" + Sample.bundleName) }),
        ("artifact outside the incoming directory", .notAuthorized, { p, l in p.requesting(artifact: l.profile.path + "/prefs.js") }),
        ("transaction directory at another name", .notAuthorized, { p, l in p.requesting(transaction: l.root.path + "/Elsewhere") }),
        ("transaction directory inside the applications directory", .notAuthorized, { p, l in p.requesting(transaction: l.applications.path + "/Transaction") })
    ]
    for (name, reason, request) in requests {
        check("request with \(name) refuses \(reason.rawValue) and changes nothing") {
            try withRoot { authority, layout in
                let prepared = try seeded(layout)
                let before = try walk(layout.root.path)
                try refuses(reason) { _ = try authority.perform(request(prepared, layout), hooks: idle()) }
                try expectSame(before, try walk(layout.root.path), "Refused request changed the fixture root")
            }
        }
    }
    check("request naming a second authority's root is refused by both without changes") {
        try withRoot { first, firstLayout in
            try withRoot { second, secondLayout in
                let a = try seeded(firstLayout), b = try seeded(secondLayout)
                let before = try walk(firstLayout.root.path) + walk(secondLayout.root.path)
                try refuses(.notAuthorized) { _ = try first.perform(a.requesting(target: secondLayout.target.path), hooks: idle()) }
                try refuses(.notAuthorized) { _ = try second.perform(a.request, hooks: idle()) }
                try refuses(.notAuthorized) { _ = try first.perform(b.requesting(source: firstLayout.source.path, artifact: firstLayout.artifact.path), hooks: idle()) }
                try expectSame(before, try walk(firstLayout.root.path) + walk(secondLayout.root.path), "Cross-root request changed a fixture")
            }
        }
    }
}
