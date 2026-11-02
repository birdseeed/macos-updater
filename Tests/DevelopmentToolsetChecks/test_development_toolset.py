"""Independent mechanics checks. All executable bytes/signatures are FIXTURES.

No Swift, codesign, Git, shell or other child process is executed by this suite.
Positive results establish only local mechanics, never native/source authority.
"""

import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/build-development-toolset.py"
SPEC = importlib.util.spec_from_file_location("development_toolset_under_check", SCRIPT)
BUILDER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = BUILDER
SPEC.loader.exec_module(BUILDER)

REVISION = "0123456789abcdef0123456789abcdef01234567"
PRODUCTS = ("PatchedApp", "PatchedDisposableClientApp", "patched-disposable-proof")
SOURCE_BYTES = {"Package.swift": b"// FIXTURE package, never compiled\n",
                "Sources/Fixture.swift": b"// FIXTURE source, never compiled\n"}
LEGACY_PLIST = {
    "CFBundleExecutable": "PatchedDisposableClientApp",
    "CFBundleIdentifier": "im.patched.disposable.nativeproof",
    "CFBundleName": "Patched disposable native proof",
    "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "0.0.1",
    "CFBundleVersion": "1", "NSHighResolutionCapable": True,
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def fixture_parent(*, create):
    """Open the physical project-owned check root; never follow an ancestor link."""
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    project = SCRIPT.parent.parent
    descriptor = os.open(project.anchor, flags)
    try:
        for component in project.parts[1:]:
            child = os.open(component, flags, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        project_stat = os.fstat(descriptor)
        if project_stat.st_uid != os.getuid() or project_stat.st_mode & 0o022:
            raise RuntimeError("Unsafe check project ownership or permissions")
        for name, private in ((".build", False), ("development-toolset-checks", True)):
            if create:
                try:
                    os.mkdir(name, 0o700, dir_fd=descriptor)
                except FileExistsError:
                    pass
            child = os.open(name, flags, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
            observed = os.fstat(descriptor)
            mode = stat.S_IMODE(observed.st_mode)
            if observed.st_uid != os.getuid() or mode & 0o022 or (private and mode != 0o700):
                raise RuntimeError("Unsafe check storage ownership or permissions")
        return project / ".build/development-toolset-checks", os.fstat(descriptor)
    finally:
        os.close(descriptor)


def same_directory(first, second):
    return (first.st_dev, first.st_ino) == (second.st_dev, second.st_ino)


class FixtureRunner:
    """Finite fake protocol. Unknown commands are test failures, not successes."""

    def __init__(self, case):
        self.case = case
        self.calls = []
        self.products = []
        self.signs = []
        self.verifies = []
        self.fault = None
        self.source_change = None
        self.dirty = b""
        self.revision = REVISION
        self.product_shape = "regular"
        self.bin_override = None
        self.tracked = b"Package.swift\0Sources/Fixture.swift\0"
        self.after_verification = None

    def __call__(self, argv, *, cwd, timeout_seconds, max_output_bytes):
        argv = tuple(map(str, argv))
        self.calls.append((argv, Path(cwd), timeout_seconds, max_output_bytes))
        self.case.assertEqual(Path(cwd), self.case.repo)
        self.case.assertEqual(max_output_bytes, 1_048_576)
        result = BUILDER.ProcessResult
        if argv[0] == "/usr/bin/git":
            self.case.assertEqual(timeout_seconds, 30)
            tail = argv[1:]
            if tail == ("rev-parse", "--verify", "HEAD"):
                return result(0, (self.revision + "\n").encode())
            if tail == ("status", "--porcelain=v1", "--untracked-files=all"):
                return result(0, self.dirty)
            if tail == ("ls-files", "-z"):
                return result(0, self.tracked)
            self.case.fail("Unexpected git command: " + repr(argv))
        if argv[0] == "/usr/bin/swift":
            self.case.assertEqual(timeout_seconds, 1800)
            self.case.assertEqual(argv[:4], ("/usr/bin/swift", "build", "--package-path", str(self.case.repo)))
            self.case.assertEqual(argv[4], "--scratch-path")
            scratch = Path(argv[5])
            self.case.assertTrue(scratch.is_relative_to(self.case.repo / ".build/development-toolset"))
            self.case.assertEqual(argv[6:8], ("--jobs", "2"))
            if argv[8:] == ("--show-bin-path",):
                return result(0, (str(self.bin_override or scratch / "debug") + "\n").encode())
            self.case.assertEqual(argv[8], "--product")
            self.case.assertEqual(len(argv), 10)
            name = argv[9]
            self.case.assertEqual(name, PRODUCTS[len(self.products)])
            self.products.append(name)
            binary = scratch / "debug" / name
            binary.parent.mkdir(parents=True, exist_ok=True)
            if self.product_shape == "symlink":
                binary.symlink_to(self.case.outside / "sentinel")
            elif self.product_shape == "directory":
                binary.mkdir()
            elif self.product_shape == "missing":
                pass
            elif self.product_shape == "oversized":
                with binary.open("wb") as stream:
                    stream.truncate(64 * 1024 * 1024 + 1)
                binary.chmod(0o755)
            elif self.product_shape == "empty":
                binary.write_bytes(b"")
                binary.chmod(0o755)
            else:
                binary.write_bytes(b"UNSIGNED FIXTURE " + name.encode())
                binary.chmod(0o755)
            if self.source_change:
                self.source_change()
            if self.fault == "build":
                return result(1, stderr=b"FIXTURE compilation failure")
            if self.fault == "timeout":
                return result(0, timed_out=True)
            if self.fault == "overflow":
                return result(0, output_truncated=True)
            return result(0)
        if argv[0] == "/usr/bin/codesign":
            self.case.assertEqual(timeout_seconds, 60)
            target = Path(argv[-1])
            self.case.assertTrue(target.is_relative_to(self.case.repo / ".build/development-toolset"))
            self.case.assertIn("toolset", target.parts)
            binary = target / "Contents/MacOS" / target.stem if target.suffix == ".app" else target
            self.case.assertTrue(binary.is_file())
            self.case.assertFalse(binary.is_symlink())
            if argv[1:-1] == ("--force", "--sign", "-"):
                self.signs.append(target)
                if self.fault == "sign":
                    return result(1, stderr=b"FIXTURE signing failure")
                binary.write_bytes(binary.read_bytes() + b" SIGNED FIXTURE")
                return result(0)
            self.case.assertEqual(argv[1:-1], ("--verify", "--strict", "--verbose=2"))
            self.verifies.append(target)
            self.case.assertIn(target, self.signs)
            if self.fault == "verify":
                return result(1, stderr=b"FIXTURE verification failure")
            if len(self.verifies) == 3 and self.after_verification:
                self.after_verification(target.parent)
            return result(0)
        self.case.fail("Unexpected external process: " + repr(argv))


class DevelopmentToolsetChecks(unittest.TestCase):
    def setUp(self):
        parent, self.fixture_parent_identity = fixture_parent(create=True)
        self.tmp = tempfile.TemporaryDirectory(prefix="case-", dir=parent)
        self.root = Path(self.tmp.name)
        self.fixture_identity = self.root.lstat()
        self.addCleanup(self.cleanup_fixtures)
        self.validate_fixture_identity()
        self.repo = self.root / "repo"
        self.repo.mkdir(mode=0o700)
        self.outside = self.root / "outside"
        self.outside.mkdir(mode=0o700)
        (self.outside / "sentinel").write_bytes(b"UNCHANGED OUTSIDE FIXTURE")
        for name, data in SOURCE_BYTES.items():
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        self.runner = FixtureRunner(self)

    def tearDown(self):
        self.assertEqual((self.outside / "sentinel").read_bytes(), b"UNCHANGED OUTSIDE FIXTURE")

    def validate_fixture_identity(self):
        parent, observed_parent = fixture_parent(create=False)
        if self.root.parent != parent or not same_directory(self.fixture_parent_identity, observed_parent):
            raise RuntimeError("Check storage ancestry changed; preserve fixture evidence")
        descriptor = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            observed = os.fstat(descriptor)
            if not same_directory(self.fixture_identity, observed) or observed.st_uid != os.getuid() or stat.S_IMODE(observed.st_mode) != 0o700:
                raise RuntimeError("Check fixture identity or private permissions changed")
        finally:
            os.close(descriptor)

    def cleanup_fixtures(self):
        self.validate_fixture_identity()
        self.tmp.cleanup()

    def build(self):
        # Explicit no-elapsed fixture preserves original literal per-call caps.
        return BUILDER.build_toolset(self.repo, runner=self.runner, clock=lambda: 100.0)

    def no_receipts(self):
        for name in ("builder-receipt.json", "native-builder-receipt.json", "development-toolset-manifest.json"):
            self.assertEqual([p for p in self.root.rglob(name) if p.is_file()], [])

    def refuses(self):
        with self.assertRaises(BUILDER.BuildRefused):
            self.build()
        self.no_receipts()

    def test_import_has_no_process_or_filesystem_side_effects(self):
        isolated = importlib.util.module_from_spec(SPEC)
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch("subprocess.Popen", side_effect=AssertionError("import spawned")), \
                patch("pathlib.Path.mkdir", side_effect=AssertionError("import wrote")), \
                patch("builtins.open", side_effect=AssertionError("import opened file")), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            SPEC.loader.exec_module(isolated)
        self.assertEqual((stdout.getvalue(), stderr.getvalue()), ("", ""))

    def test_cli_default_and_unknown_options_refuse_without_calling_builder(self):
        for args in ([], ["--product", "Other"], ["--output", str(self.outside)],
                     ["--target", "guest"], ["--build", "--allow-dirty"],
                     ["--build", "--runner", "fake"], ["--build", "extra"]):
            with self.subTest(args=args), patch.object(BUILDER, "build_toolset") as build:
                with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                    self.assertNotEqual(BUILDER.main(args), 0)
                build.assert_not_called()

    def test_cli_explicit_build_routes_only_to_fixed_repository(self):
        with patch.object(BUILDER, "build_toolset", return_value=self.repo / "fixture-toolset") as build:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(BUILDER.main(["--build"]), 0)
            self.assertEqual(build.call_count, 1)
            self.assertEqual(Path(build.call_args.args[0]), SCRIPT.parent.parent)
            self.assertEqual(set(build.call_args.kwargs), {"runner"})
            self.assertTrue(callable(build.call_args.kwargs["runner"]))

    def test_success_is_exclusive_physical_private_output_and_preserves_sources(self):
        output = self.build()
        self.assertEqual(output.name, "toolset")
        self.assertEqual(output.parent.parent, self.repo / ".build/development-toolset")
        self.assertFalse(output.is_symlink())
        for path in (output.parent, output):
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o700)
            self.assertEqual(path.stat().st_uid, os.getuid())
        for name, data in SOURCE_BYTES.items():
            self.assertEqual((self.repo / name).read_bytes(), data)
        self.assertEqual(set(p.name for p in output.iterdir()), {
            "PatchedApp.app", "PatchedDisposableClientApp.app", "patched-disposable-proof",
            "builder-receipt.json", "native-builder-receipt.json", "development-toolset-manifest.json"})
        for path in output.rglob("*"):
            self.assertFalse(path.is_symlink())
            self.assertEqual(path.stat().st_uid, os.getuid())
            self.assertEqual(stat.S_IMODE(path.stat().st_mode),
                             0o700 if path.is_dir() else 0o700 if path.parent.name == "MacOS" or path.name == "patched-disposable-proof" else 0o600)

    def test_exact_order_commands_and_source_recheck(self):
        self.build()
        self.assertEqual(self.runner.products, list(PRODUCTS))
        self.assertEqual([p.name for p in self.runner.signs],
                         ["patched-disposable-proof", "PatchedApp.app", "PatchedDisposableClientApp.app"])
        self.assertEqual(self.runner.verifies, self.runner.signs)
        commands = [c[0] for c in self.runner.calls]
        first_swift = next(i for i, c in enumerate(commands) if c[0] == "/usr/bin/swift")
        last_swift = max(i for i, c in enumerate(commands) if c[0] == "/usr/bin/swift")
        self.assertTrue(all(c[0] == "/usr/bin/git" for c in commands[:first_swift]))
        self.assertTrue(all(c[0] != "/usr/bin/swift" for c in commands[last_swift + 1:]))
        for tail in (("rev-parse", "--verify", "HEAD"),
                     ("status", "--porcelain=v1", "--untracked-files=all"), ("ls-files", "-z")):
            positions = [i for i, c in enumerate(commands) if c == ("/usr/bin/git",) + tail]
            self.assertGreaterEqual(len(positions), 2)
            self.assertLess(positions[0], first_swift)
            self.assertGreater(positions[-1], last_swift)
        signing = [c for c in commands if c[0] == "/usr/bin/codesign"]
        expected = [("/usr/bin/codesign", "--force", "--sign", "-", str(p)) for p in self.runner.signs]
        expected += [("/usr/bin/codesign", "--verify", "--strict", "--verbose=2", str(p)) for p in self.runner.signs]
        self.assertEqual(signing, expected)
        first_sign = next(i for i, c in enumerate(commands) if c[0] == "/usr/bin/codesign")
        self.assertGreater(first_sign, last_swift)

    def test_legacy_metadata_and_honest_developer_identity(self):
        output = self.build()
        child = plistlib.loads((output / "PatchedDisposableClientApp.app/Contents/Info.plist").read_bytes())
        self.assertEqual(child, LEGACY_PLIST)
        ordinary = plistlib.loads((output / "PatchedApp.app/Contents/Info.plist").read_bytes())
        self.assertEqual(ordinary["CFBundleExecutable"], "PatchedApp")
        self.assertEqual(ordinary["CFBundleIdentifier"], "im.patched.private-development")
        self.assertEqual(ordinary["CFBundleName"], "Patched private development")
        self.assertEqual(ordinary["CFBundlePackageType"], "APPL")

    def test_strict_legacy_receipts_hash_signed_copied_bytes(self):
        output = self.build()
        child = output / "patched-disposable-proof"
        native = output / "PatchedDisposableClientApp.app/Contents/MacOS/PatchedDisposableClientApp"
        child_receipt = json.loads((output / "builder-receipt.json").read_bytes())
        native_receipt = json.loads((output / "native-builder-receipt.json").read_bytes())
        self.assertTrue(child.read_bytes().endswith(b" SIGNED FIXTURE"))
        self.assertTrue(native.read_bytes().endswith(b" SIGNED FIXTURE"))
        self.assertEqual(child_receipt, {"binarySHA256": digest(child.read_bytes()), "sourceRevision": REVISION})
        self.assertEqual(native_receipt, {"nativeBinarySHA256": digest(native.read_bytes()),
                         "childBinarySHA256": digest(child.read_bytes()), "sourceRevision": REVISION})
        for name in PRODUCTS:
            originals = list((output.parent / "swift").rglob(name))
            self.assertEqual(len(originals), 1)
            self.assertEqual(originals[0].read_bytes(), b"UNSIGNED FIXTURE " + name.encode())

    def test_separate_manifest_recomputes_every_source_and_product_hash(self):
        output = self.build()
        manifest = json.loads((output / "development-toolset-manifest.json").read_bytes())
        self.assertEqual(set(manifest), {"schemaVersion", "kind", "sourceRevision", "sourceFiles", "files",
                                        "signing", "sourceAttestation", "installationAuthority"})
        self.assertEqual(manifest["schemaVersion"], 1)
        self.assertEqual(manifest["kind"], "private-development-toolset")
        self.assertEqual(manifest["sourceRevision"], REVISION)
        self.assertEqual(manifest["sourceFiles"], {n: digest(d) for n, d in SOURCE_BYTES.items()})
        self.assertEqual(manifest["signing"], "ad-hoc")
        self.assertIs(manifest["sourceAttestation"], False)
        self.assertIs(manifest["installationAuthority"], False)
        expected = {str(p.relative_to(output)): digest(p.read_bytes()) for p in output.rglob("*")
                    if p.is_file() and p.name != "development-toolset-manifest.json"}
        self.assertEqual(manifest["files"], expected)

    def test_second_build_does_not_clobber_first(self):
        first = self.build()
        before = {str(p.relative_to(first)): p.read_bytes() for p in first.rglob("*") if p.is_file()}
        self.runner = FixtureRunner(self)
        second = self.build()
        self.assertNotEqual(first.parent, second.parent)
        self.assertEqual(before, {str(p.relative_to(first)): p.read_bytes() for p in first.rglob("*") if p.is_file()})

    def test_dirty_source_refuses_before_build_or_output_creation(self):
        self.runner.dirty = b"?? untracked-source.swift\n"
        self.refuses()
        self.assertEqual(self.runner.products, [])
        self.assertFalse((self.repo / ".build").exists())

    def test_malformed_or_missing_revision_refuses(self):
        for revision in ("", "A" * 40, "1" * 39, "1" * 41, REVISION + "\n" + REVISION):
            with self.subTest(revision=revision):
                self.runner.revision = revision
                self.refuses()
                self.assertEqual(self.runner.products, [])

    def test_source_bytes_changed_during_build_refuse_even_with_clean_git(self):
        self.runner.source_change = lambda: (self.repo / "Sources/Fixture.swift").write_bytes(b"CHANGED FIXTURE")
        self.refuses()
        self.assertTrue(self.runner.products, "must exercise the postbuild source guard")

    def test_revision_changed_during_build_refuses(self):
        self.runner.source_change = lambda: setattr(self.runner, "revision", "f" * 40)
        self.refuses()
        self.assertTrue(self.runner.products)

    def test_dirty_after_build_refuses(self):
        self.runner.source_change = lambda: setattr(self.runner, "dirty", b" M Package.swift\n")
        self.refuses()
        self.assertTrue(self.runner.products)

    def test_symlink_source_file_refuses_before_swift(self):
        source = self.repo / "Sources/Fixture.swift"
        source.unlink()
        source.symlink_to(self.outside / "sentinel")
        self.refuses()
        self.assertEqual(self.runner.products, [])

    def test_unsafe_tracked_file_lists_refuse_before_swift(self):
        for listing in (b"", b"Package.swift", b"../outside/sentinel\0", b"/etc/passwd\0",
                        b"Package.swift\0Package.swift\0", b".build/input\0", b"Sources/missing.swift\0"):
            with self.subTest(listing=listing):
                self.runner = FixtureRunner(self)
                self.runner.tracked = listing
                self.refuses()
                self.assertEqual(self.runner.products, [])

    def test_source_size_bound_refuses_before_swift(self):
        # Sparse physical file exceeds the source ceiling without a large fixture allocation.
        with (self.repo / "Sources/Fixture.swift").open("wb") as stream:
            stream.truncate(64 * 1024 * 1024 + 1)
        self.refuses()
        self.assertEqual(self.runner.products, [])

    def test_symlink_source_ancestor_refuses_before_swift(self):
        (self.repo / "Sources/Fixture.swift").unlink()
        (self.repo / "Sources").rmdir()
        (self.repo / "Sources").symlink_to(self.outside, target_is_directory=True)
        self.refuses()
        self.assertEqual(self.runner.products, [])

    def test_symlink_repo_alias_refuses(self):
        alias = self.root / "alias"
        alias.symlink_to(self.repo, target_is_directory=True)
        with self.assertRaises(BUILDER.BuildRefused):
            BUILDER.build_toolset(alias, runner=self.runner)
        self.assertEqual(self.runner.calls, [])
        self.no_receipts()

    def test_symlink_build_ancestry_refuses_without_touching_destination(self):
        (self.repo / ".build").symlink_to(self.outside, target_is_directory=True)
        self.refuses()
        self.assertEqual(sorted(p.name for p in self.outside.iterdir()), ["sentinel"])

    def test_nonprivate_or_nondirectory_owned_parent_refuses_without_chmod(self):
        for kind in ("public", "file", "symlink"):
            with self.subTest(kind=kind):
                base = self.repo / ".build"
                base.mkdir(exist_ok=True)
                base.chmod(0o700)
                path = base / "development-toolset"
                if kind == "public":
                    path.mkdir(mode=0o755)
                elif kind == "file":
                    path.write_bytes(b"existing do not clobber")
                else:
                    path.symlink_to(self.outside, target_is_directory=True)
                before = path.lstat()
                self.refuses()
                after = path.lstat()
                self.assertEqual((before.st_ino, before.st_mode), (after.st_ino, after.st_mode))
                if kind == "public":
                    path.rmdir()
                else:
                    path.unlink()

    def test_missing_directory_and_symlink_products_refuse_without_receipts(self):
        for kind in ("missing", "directory", "symlink", "empty", "oversized"):
            with self.subTest(kind=kind):
                self.runner = FixtureRunner(self)
                self.runner.product_shape = kind
                self.refuses()
                self.assertTrue(self.runner.products, "must inspect actual fake build output")

    def test_nonprivate_general_build_parent_refuses_without_chmod(self):
        base = self.repo / ".build"
        base.mkdir(mode=0o777)
        base.chmod(0o777)
        self.refuses()
        self.assertEqual(stat.S_IMODE(base.stat().st_mode), 0o777)

    def test_git_errors_and_malformed_process_results_refuse_before_swift(self):
        result = BUILDER.ProcessResult
        cases = (result(1), result(-9), result(0, timed_out=True),
                 result(0, output_truncated=True), result(0, stdout=b"x" * 1_048_577),
                 result(True), result(0, stdout="not bytes"), None)
        for value in cases:
            with self.subTest(value=repr(value)[:80]):
                called = []

                def malformed(argv, **kwargs):
                    called.append(argv)
                    return value

                with self.assertRaises(BUILDER.BuildRefused):
                    BUILDER.build_toolset(self.repo, runner=malformed)
                self.assertTrue(called, "must inspect the fake process result")
                self.no_receipts()

    def test_bin_path_outside_owned_scratch_refuses(self):
        self.runner.bin_override = self.outside
        self.refuses()
        self.assertFalse(self.runner.signs)

    def test_process_failure_timeout_and_overflow_do_not_publish_receipts(self):
        for fault in ("build", "timeout", "overflow", "sign", "verify"):
            with self.subTest(fault=fault):
                self.runner = FixtureRunner(self)
                self.runner.fault = fault
                self.refuses()
                self.assertTrue(self.runner.products, "must reach fake child process")
                if fault == "sign":
                    self.assertTrue(self.runner.signs)
                if fault == "verify":
                    self.assertTrue(self.runner.verifies)

    def test_hash_read_failure_does_not_publish_receipts(self):
        def unlink_final_child(output):
            (output / "patched-disposable-proof").unlink()

        self.runner.after_verification = unlink_final_child
        self.refuses()
        self.assertTrue(self.runner.verifies, "must reach post-verification hash phase")

    def test_receipt_write_failure_removes_all_publishable_receipts(self):
        def obstruct_receipt(output):
            (output / "native-builder-receipt.json").mkdir(mode=0o700)

        self.runner.after_verification = obstruct_receipt
        self.refuses()
        self.assertTrue(self.runner.verifies)

    def test_postverify_binary_symlink_is_not_hashed_or_followed(self):
        def replace_child(output):
            (output / "patched-disposable-proof").unlink()
            (output / "patched-disposable-proof").symlink_to(self.outside / "sentinel")

        self.runner.after_verification = replace_child
        self.refuses()
        self.assertTrue(self.runner.verifies)


class ManualDeadlineClock:
    """Explicit API fixture; wall time never controls these acceptance cases."""

    def __init__(self):
        self.now = 100.0

    def __call__(self):
        return self.now

    def expire(self):
        self.now = 1900.0  # Exactly 1800 elapsed, not an extra grace interval.


class DeadlineFixtureRunner(FixtureRunner):
    def __init__(self, case):
        super().__init__(case)
        self.allowances = []
        self.after_call = lambda number: None

    def __call__(self, argv, *, cwd, timeout_seconds, max_output_bytes):
        caps = {"/usr/bin/git": 30, "/usr/bin/swift": 1800, "/usr/bin/codesign": 60}
        cap = caps[str(argv[0])]
        self.case.assertIsInstance(timeout_seconds, (int, float))
        self.case.assertNotIsInstance(timeout_seconds, bool)
        self.case.assertGreater(timeout_seconds, 0)
        self.case.assertLessEqual(timeout_seconds, cap)
        self.allowances.append(timeout_seconds)
        # Preserve the original 32 cases' exact argv and per-tool assertions.
        # Only this adapter records the deadline allowance; no real runner runs.
        result = super().__call__(argv, cwd=cwd, timeout_seconds=cap,
                                  max_output_bytes=max_output_bytes)
        self.after_call(len(self.calls))
        return result


class DevelopmentToolsetDeadlineChecks(unittest.TestCase):
    # Reuse fixture custody only, without inheriting/duplicating the 32 cases.
    setUp = DevelopmentToolsetChecks.setUp
    tearDown = DevelopmentToolsetChecks.tearDown
    validate_fixture_identity = DevelopmentToolsetChecks.validate_fixture_identity
    cleanup_fixtures = DevelopmentToolsetChecks.cleanup_fixtures
    no_receipts = DevelopmentToolsetChecks.no_receipts

    def prepare(self):
        self.clock = ManualDeadlineClock()
        self.runner = DeadlineFixtureRunner(self)

    def build(self):
        return BUILDER.build_toolset(self.repo, runner=self.runner, clock=self.clock)

    def refuse(self):
        with self.assertRaises(BUILDER.BuildRefused):
            self.build()
        self.no_receipts()

    def test_complete_within_budget_keeps_literal_process_caps(self):
        self.prepare()
        output = self.build()
        self.assertTrue((output / "development-toolset-manifest.json").is_file())
        self.assertEqual(self.runner.allowances,
                         [30, 30, 30, 1800, 1800, 1800, 1800,
                          60, 60, 60, 60, 60, 60, 30, 30, 30])
        manifest = json.loads((output / "development-toolset-manifest.json").read_bytes())
        self.assertIs(manifest["sourceAttestation"], False)
        self.assertIs(manifest["installationAuthority"], False)

    def test_elapsed_git_time_reduces_swift_allowance(self):
        self.prepare()
        self.runner.after_call = lambda number: setattr(self.clock, "now", 100.0 + number * 10)
        output = self.build()
        self.assertTrue(output.is_dir())
        self.assertEqual(self.runner.allowances,
                         [30, 30, 30, 1770, 1760, 1750, 1740,
                          60, 60, 60, 60, 60, 60, 30, 30, 30])

    def test_expiry_after_first_git_refuses_next_spawn_and_output(self):
        self.prepare()
        self.runner.after_call = lambda number: self.clock.expire() if number == 1 else None
        self.refuse()
        self.assertEqual(len(self.runner.calls), 1)
        self.assertFalse((self.repo / ".build").exists())

    def test_serial_swift_calls_share_one_budget_and_preserve_fraction(self):
        self.prepare()

        def advance(number):
            if number == 4:
                self.clock.now = 1899.75
            elif number == 5:
                self.clock.expire()

        self.runner.after_call = advance
        self.refuse()
        self.assertEqual(self.runner.products, ["PatchedApp", "PatchedDisposableClientApp"])
        self.assertEqual(self.runner.allowances, [30, 30, 30, 1800, 0.25])
        self.assertEqual(self.runner.signs, [])

    def test_expiry_after_bin_lookup_prevents_first_product_copy(self):
        self.prepare()
        self.runner.after_call = lambda number: self.clock.expire() if number == 7 else None
        writes = []
        original = BUILDER._Directories.write

        def observe(directories, parent, name, *args, **kwargs):
            writes.append(name)
            return original(directories, parent, name, *args, **kwargs)

        with patch.object(BUILDER._Directories, "write", observe):
            self.refuse()
        self.assertEqual(len(self.runner.calls), 7)
        self.assertEqual(writes, [])
        self.assertEqual(self.runner.signs, [])

    def test_expiry_during_product_read_prevents_staging_that_product(self):
        self.prepare()
        original = BUILDER._Directories.read
        reached = []

        def expire_read(directories, parent, name, *args, **kwargs):
            value = original(directories, parent, name, *args, **kwargs)
            if name == "PatchedApp":
                reached.append(name)
                self.clock.expire()
            return value

        with patch.object(BUILDER._Directories, "read", expire_read):
            self.refuse()
        self.assertEqual(reached, ["PatchedApp"])
        self.assertEqual(list(self.repo.rglob("PatchedApp.app")), [])
        self.assertEqual(self.runner.signs, [])

    def test_expiry_during_copy_prevents_next_product_and_sign(self):
        self.prepare()
        original = BUILDER._Directories.write
        reached = []

        def expire_write(directories, parent, name, *args, **kwargs):
            value = original(directories, parent, name, *args, **kwargs)
            if name == "PatchedApp":
                reached.append(name)
                self.clock.expire()
            return value

        with patch.object(BUILDER._Directories, "write", expire_write):
            self.refuse()
        self.assertEqual(reached, ["PatchedApp"])
        self.assertEqual(list(self.repo.rglob("PatchedDisposableClientApp.app")), [])
        self.assertEqual(self.runner.signs, [])

    def test_sign_remaining_allowance_is_not_renewed_for_next_sign(self):
        self.prepare()

        def advance(number):
            if number == 7:
                self.clock.now = 1880.5
            elif number == 8:
                self.clock.expire()

        self.runner.after_call = advance
        self.refuse()
        self.assertEqual(len(self.runner.calls), 8)
        self.assertEqual(self.runner.allowances[-1], 19.5)
        self.assertEqual([p.name for p in self.runner.signs], ["patched-disposable-proof"])
        self.assertEqual(self.runner.verifies, [])

    def test_expiry_after_sign_prevents_verify_spawn(self):
        self.prepare()
        self.runner.after_call = lambda number: self.clock.expire() if number == 10 else None
        self.refuse()
        self.assertEqual(len(self.runner.signs), 3)
        self.assertEqual(len(self.runner.calls), 10)
        self.assertEqual(self.runner.verifies, [])

    def test_expiry_during_source_recheck_prevents_next_git(self):
        self.prepare()
        self.runner.after_call = lambda number: self.clock.expire() if number == 14 else None
        self.refuse()
        self.assertEqual(len(self.runner.verifies), 3)
        self.assertEqual(len(self.runner.calls), 14)
        self.assertEqual(self.runner.calls[-1][0], ("/usr/bin/git", "rev-parse", "--verify", "HEAD"))

    def test_expiry_during_inventory_prevents_receipt_publication(self):
        self.prepare()
        original = BUILDER._inventory
        reached = []

        def expire_inventory(*args, **kwargs):
            result = original(*args, **kwargs)
            reached.append(True)
            self.clock.expire()
            return result

        with patch.object(BUILDER, "_inventory", expire_inventory):
            self.refuse()
        self.assertEqual(reached, [True])
        self.assertEqual(len(self.runner.calls), 16)

    def test_expiry_after_first_receipt_removes_it_and_prevents_next_receipt(self):
        self.prepare()
        original = BUILDER._Directories.write
        receipts = []

        def expire_receipt(directories, parent, name, *args, **kwargs):
            value = original(directories, parent, name, *args, **kwargs)
            if name.endswith("receipt.json"):
                receipts.append(name)
                self.clock.expire()
            return value

        with patch.object(BUILDER._Directories, "write", expire_receipt):
            self.refuse()
        self.assertEqual(receipts, ["builder-receipt.json"])

    def test_expiry_after_manifest_removes_all_own_metadata_before_rename(self):
        self.prepare()
        original = BUILDER._Directories.write
        reached = []
        renamed = []

        def expire_manifest(directories, parent, name, *args, **kwargs):
            value = original(directories, parent, name, *args, **kwargs)
            if name == "development-toolset-manifest.json":
                reached.append(name)
                self.clock.expire()
            return value

        with patch.object(BUILDER._Directories, "write", expire_manifest), \
                patch.object(BUILDER.os, "rename", side_effect=lambda *a, **k: renamed.append(True)):
            self.refuse()
        self.assertEqual(reached, ["development-toolset-manifest.json"])
        self.assertEqual(renamed, [])

    def test_expiry_after_publication_rename_invalidates_own_receipts(self):
        self.prepare()
        original = BUILDER.os.rename
        renamed = []

        def expire_rename(*args, **kwargs):
            result = original(*args, **kwargs)
            renamed.append(True)
            self.clock.expire()
            return result

        with patch.object(BUILDER.os, "rename", expire_rename):
            self.refuse()
        self.assertEqual(renamed, [True])
        # Diagnostic artifacts may survive, but a published directory must not
        # retain any of this invocation's three authority-shaped metadata files.
        published = list((self.repo / ".build/development-toolset").glob("run-*/toolset"))
        self.assertEqual(len(published), 1)
        self.assertTrue((published[0] / "patched-disposable-proof").is_file())


if __name__ == "__main__":
    unittest.main()
