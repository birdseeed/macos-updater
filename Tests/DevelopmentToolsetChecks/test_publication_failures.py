"""Late publication failures using only the existing finite inert fixture runner.

Importing this module during future discovery imports the original fixture module,
but exposes only this class's three tests to unittest discovery.
"""

import errno
import os
import unittest
from unittest.mock import patch

import test_development_toolset as fixtures


class PublicationFailureChecks(unittest.TestCase):
    # Reuse custody and cleanup guards without inheriting the original 29 tests.
    setUp = fixtures.DevelopmentToolsetChecks.setUp
    tearDown = fixtures.DevelopmentToolsetChecks.tearDown
    validate_fixture_identity = fixtures.DevelopmentToolsetChecks.validate_fixture_identity
    cleanup_fixtures = fixtures.DevelopmentToolsetChecks.cleanup_fixtures
    build = fixtures.DevelopmentToolsetChecks.build
    no_receipts = fixtures.DevelopmentToolsetChecks.no_receipts

    def assert_late_failure_preserves_inputs(self):
        self.assertEqual(self.runner.products, list(fixtures.PRODUCTS))
        self.assertEqual(len(self.runner.signs), 3)
        self.assertEqual(self.runner.verifies, self.runner.signs)
        for name, data in fixtures.SOURCE_BYTES.items():
            self.assertEqual((self.repo / name).read_bytes(), data)
        self.assertEqual((self.outside / "sentinel").read_bytes(), b"UNCHANGED OUTSIDE FIXTURE")
        self.no_receipts()
        for name in ("builder-receipt.json", "native-builder-receipt.json",
                     "development-toolset-manifest.json"):
            self.assertEqual(list(self.root.rglob(name)), [])
        self.validate_fixture_identity()

    def receipt_write_failure(self, target_name):
        real_open, real_write, real_close = os.open, os.write, os.close
        state = {"stage": None, "opened": [], "tracked": {}, "writes": 0,
                 "short_writes": 0, "failures": 0, "first_receipt_present": False}

        def verified(stage):
            self.assertEqual(len(self.runner.verifies), 3)
            state["stage"] = stage
            state["stage_identity"] = stage.lstat()

        def own_stage(fd):
            return (state["stage"] is not None and fd is not None
                    and fixtures.same_directory(os.fstat(fd), state["stage_identity"]))

        def tracked_open(path, flags, mode=0o777, *, dir_fd=None):
            fd = real_open(path, flags, mode, dir_fd=dir_fd)
            # os is process-global: every unrelated open passes through unchanged.
            if (path in ("builder-receipt.json", "native-builder-receipt.json")
                    and flags & os.O_EXCL and flags & os.O_WRONLY and own_stage(dir_fd)):
                state["opened"].append(path)
                state["tracked"][fd] = (path, os.fstat(fd))
                if path == "native-builder-receipt.json":
                    first = os.stat("builder-receipt.json", dir_fd=dir_fd,
                                    follow_symlinks=False)
                    state["first_receipt_present"] = first.st_size > 0
            return fd

        def tracked_close(fd):
            # Drop ownership before closing, so a reused descriptor cannot match.
            state["tracked"].pop(fd, None)
            return real_close(fd)

        def failing_write(fd, data):
            tracked = state["tracked"].get(fd)
            if (tracked is None or tracked[0] != target_name
                    or not fixtures.same_directory(os.fstat(fd), tracked[1])):
                return real_write(fd, data)
            state["writes"] += 1
            if state["writes"] == 1:
                self.assertEqual(len(self.runner.verifies), 3)
                self.assertGreater(len(data), 7)
                count = real_write(fd, data[:7])
                self.assertEqual(count, 7)
                state["short_writes"] += 1
                return count
            self.assertEqual(state["writes"], 2, "fault injection is finite")
            self.assertEqual(os.fstat(fd).st_size, 7)
            state["failures"] += 1
            raise OSError(errno.EIO, "FIXTURE receipt write failure")

        self.runner.after_verification = verified
        with patch.object(os, "open", tracked_open), patch.object(os, "write", failing_write), \
                patch.object(os, "close", tracked_close):
            with self.assertRaises(fixtures.BUILDER.BuildRefused) as refusal:
                self.build()
        self.assertIsInstance(refusal.exception.__cause__, OSError)
        self.assertEqual(refusal.exception.__cause__.errno, errno.EIO)
        self.assertEqual((state["writes"], state["short_writes"], state["failures"]), (2, 1, 1))
        expected = ["builder-receipt.json"]
        if target_name == "native-builder-receipt.json":
            expected.append(target_name)
            self.assertTrue(state["first_receipt_present"], "first receipt must precede second fault")
        self.assertEqual(state["opened"], expected)
        self.assertEqual(state["tracked"], {})
        self.assertIsNotNone(state["stage"])
        self.assertFalse((state["stage"].parent.parent / "toolset").exists())
        self.assert_late_failure_preserves_inputs()

    def test_partial_first_receipt_write_removes_its_exact_partial_file(self):
        self.receipt_write_failure("builder-receipt.json")

    def test_partial_second_receipt_write_also_rolls_back_completed_first_receipt(self):
        self.receipt_write_failure("native-builder-receipt.json")

    def test_run_fsync_failure_after_real_rename_removes_all_published_metadata(self):
        real_rename, real_fsync = os.rename, os.fsync
        state = {"stage": None, "renames": 0, "failures": 0, "renamed": False}
        receipt_names = ("builder-receipt.json", "native-builder-receipt.json",
                         "development-toolset-manifest.json")

        def verified(stage):
            self.assertEqual(len(self.runner.verifies), 3)
            state["stage"] = stage
            state["stage_identity"] = stage.lstat()
            state["stage_parent_identity"] = stage.parent.lstat()
            state["run"] = stage.parent.parent
            state["run_identity"] = state["run"].lstat()
            binary = stage / "patched-disposable-proof"
            state["binary_identity"] = binary.lstat()
            state["binary_bytes"] = binary.read_bytes()

        def publishing_rename(src, dst, *, src_dir_fd=None, dst_dir_fd=None):
            own_publication = (state["stage"] is not None and src == dst == "toolset"
                               and src_dir_fd is not None and dst_dir_fd is not None
                               and fixtures.same_directory(os.fstat(src_dir_fd), state["stage_parent_identity"])
                               and fixtures.same_directory(os.fstat(dst_dir_fd), state["run_identity"]))
            if not own_publication:
                return real_rename(src, dst, src_dir_fd=src_dir_fd, dst_dir_fd=dst_dir_fd)
            self.assertEqual(state["renames"], 0)
            for name in receipt_names:
                self.assertGreater((state["stage"] / name).lstat().st_size, 0)
            result = real_rename(src, dst, src_dir_fd=src_dir_fd, dst_dir_fd=dst_dir_fd)
            # Arm only after the actual descriptor-relative rename succeeded.
            state["renames"] += 1
            state["renamed"] = True
            published = os.stat("toolset", dir_fd=dst_dir_fd, follow_symlinks=False)
            self.assertTrue(fixtures.same_directory(published, state["stage_identity"]))
            return result

        def failing_fsync(fd):
            if (state["renamed"] and state["failures"] == 0
                    and fixtures.same_directory(os.fstat(fd), state["run_identity"])):
                state["failures"] += 1
                raise OSError(errno.EIO, "FIXTURE post-publication run fsync failure")
            return real_fsync(fd)

        self.runner.after_verification = verified
        with patch.object(os, "rename", publishing_rename), patch.object(os, "fsync", failing_fsync):
            with self.assertRaises(fixtures.BUILDER.BuildRefused) as refusal:
                self.build()
        self.assertIsInstance(refusal.exception.__cause__, OSError)
        self.assertEqual(refusal.exception.__cause__.errno, errno.EIO)
        self.assertEqual((state["renames"], state["failures"]), (1, 1))
        published = state["run"] / "toolset"
        self.assertTrue(fixtures.same_directory(published.lstat(), state["stage_identity"]))
        self.assertFalse(state["stage"].exists())
        binary = published / "patched-disposable-proof"
        self.assertTrue(fixtures.same_directory(binary.lstat(), state["binary_identity"]))
        self.assertEqual(binary.read_bytes(), state["binary_bytes"])
        self.assertEqual(binary.read_bytes(), b"UNSIGNED FIXTURE patched-disposable-proof SIGNED FIXTURE")
        self.assert_late_failure_preserves_inputs()


if __name__ == "__main__":
    unittest.main()
