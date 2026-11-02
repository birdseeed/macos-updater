#!/usr/bin/env python3
"""Build a private, ad-hoc signed development toolset on explicit request.

Import is inert. Injected runners belong to unit checks only; the CLI always
selects the bounded real runner. Receipts describe custody, never install trust.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Callable, Sequence
import ctypes
import errno
import hashlib
import json
import math
import os
import plistlib
import re
import secrets
import selectors
import signal
import stat
import subprocess
import sys
import time


class BuildRefused(RuntimeError):
    """The toolset was not produced; no valid builder receipts are available."""


@dataclass(frozen=True)
class ProcessResult:
    returncode: int
    stdout: bytes = b""
    stderr: bytes = b""
    timed_out: bool = False
    output_truncated: bool = False


_OUTPUT_LIMIT = 1_048_576
_FILE_LIMIT = 64 * 1024 * 1024
_TOTAL_LIMIT = 256 * 1024 * 1024
_PRODUCTS = ("PatchedApp", "PatchedDisposableClientApp", "patched-disposable-proof")
_RECEIPTS = ("builder-receipt.json", "native-builder-receipt.json",
             "development-toolset-manifest.json")
_DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
_FILE_FLAGS = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK


def _identity(value):
    return value.st_dev, value.st_ino


def _no_granting_acl(fd):
    """Reject extended grants; macOS deny-only home ACLs are harmless here."""
    if sys.platform == "darwin":
        library = ctypes.CDLL("/usr/lib/libSystem.B.dylib", use_errno=True)
        library.acl_get_fd_np.argtypes = (ctypes.c_int, ctypes.c_int)
        library.acl_get_fd_np.restype = ctypes.c_void_p
        library.acl_get_entry.argtypes = (ctypes.c_void_p, ctypes.c_int,
                                          ctypes.POINTER(ctypes.c_void_p))
        library.acl_get_tag_type.argtypes = (ctypes.c_void_p, ctypes.POINTER(ctypes.c_int))
        library.acl_free.argtypes = (ctypes.c_void_p,)
        library.acl_valid.argtypes = (ctypes.c_void_p,)
        acl = library.acl_get_fd_np(fd, 0x100)  # ACL_TYPE_EXTENDED
        if not acl:
            # ENOENT means no extended ACL. Other errors cannot establish safety.
            if ctypes.get_errno() == 2:
                return
            raise BuildRefused("Cannot inspect filesystem ACL")
        try:
            if library.acl_valid(acl) != 0:
                raise BuildRefused("Invalid filesystem ACL")
            entry = ctypes.c_void_p()
            selector = 0  # ACL_FIRST_ENTRY
            for _ in range(129):
                ctypes.set_errno(0)
                result = library.acl_get_entry(acl, selector, ctypes.byref(entry))
                if result == -1 and ctypes.get_errno() == 22:
                    break  # Darwin uses EINVAL for end of this valid ACL.
                if result != 0:
                    raise BuildRefused("Cannot enumerate filesystem ACL")
                tag = ctypes.c_int()
                if library.acl_get_tag_type(entry, ctypes.byref(tag)) != 0 or tag.value != 2:
                    raise BuildRefused("Filesystem ACL contains a grant or unknown entry")
                selector = -1  # ACL_NEXT_ENTRY on Darwin
            else:
                raise BuildRefused("Filesystem ACL exceeds entry bound")
        finally:
            library.acl_free(acl)
    else:
        if any(name in ("system.posix_acl_access", "system.posix_acl_default")
               for name in os.listxattr(fd)):
            raise BuildRefused("Extended filesystem ACL is unsupported")


class _Budget:
    """One cooperative deadline for the complete invocation, never per stage."""
    def __init__(self, clock):
        if not callable(clock):
            raise BuildRefused("Invalid deadline clock")
        self.clock = clock
        self.last = None
        self.start = self._sample()

    def _sample(self):
        value = self.clock()
        try:
            valid = type(value) in (int, float) and math.isfinite(value)
        except (OverflowError, TypeError):
            valid = False
        if not valid or (self.last is not None and value < self.last):
            raise BuildRefused("Invalid or backward deadline clock")
        self.last = value
        return value

    def remaining(self):
        elapsed = self._sample() - self.start
        if elapsed >= 1800 or not math.isfinite(elapsed):
            raise BuildRefused("Development toolset deadline expired")
        return 1800 - elapsed

    def check(self):
        self.remaining()


class _Directories:
    """Retain directory descriptors and recheck their physical parent links."""
    def __init__(self, budget):
        self.budget = budget
        self.entries = {}
        self.acl_states = {}

    def close(self):
        for fd, _, _, _ in reversed(list(self.entries.values())):
            os.close(fd)
        self.entries.clear()

    def check(self):
        self.budget.check()
        for path, (fd, original, parent, private) in self.entries.items():
            self.budget.check()
            observed = os.fstat(fd)
            if _identity(observed) != _identity(original):
                raise BuildRefused("Directory descriptor changed")
            if parent is not None:
                linked = os.stat(path.name, dir_fd=self.entries[parent][0], follow_symlinks=False)
                if not stat.S_ISDIR(linked.st_mode) or _identity(linked) != _identity(original):
                    raise BuildRefused("Directory ancestry changed")
            self._safe(fd, private, owned=parent is not None and path == self.repo or path.is_relative_to(self.repo))
        self.budget.check()

    def _safe(self, fd, private, *, owned):
        value = os.fstat(fd)
        if not stat.S_ISDIR(value.st_mode) or value.st_mode & 0o022:
            raise BuildRefused("Unsafe directory permissions")
        if value.st_uid not in ((os.getuid(),) if owned else (0, os.getuid())):
            raise BuildRefused("Foreign directory owner")
        if private and stat.S_IMODE(value.st_mode) != 0o700:
            raise BuildRefused("Directory is not private")
        acl_state = (_identity(value), value.st_ctime_ns)
        if self.acl_states.get(fd) != acl_state:
            _no_granting_acl(fd)
            self.acl_states[fd] = acl_state

    def open_repo(self, repo):
        self.budget.check()
        if not isinstance(repo, Path) or not repo.is_absolute() or ".." in repo.parts or repo == Path("/"):
            raise BuildRefused("Repository must be a physical absolute path")
        self.repo = repo
        current = Path(repo.anchor)
        fd = os.open(current, _DIR_FLAGS)
        self.entries[current] = (fd, os.fstat(fd), None, False)
        self._safe(fd, False, owned=False)
        for component in repo.parts[1:]:
            current = self.directory(current, component, create=False, private=False)
        self.check()
        return current

    def directory(self, parent, name, *, create, private, exclusive=False):
        if not name or name in (".", "..") or "/" in name:
            raise BuildRefused("Invalid directory component")
        self.check()
        path = parent / name
        if path in self.entries:
            if exclusive:
                raise BuildRefused("Directory already exists")
            return path
        parent_fd = self.entries[parent][0]
        if create:
            try:
                self.budget.check()
                os.mkdir(name, 0o700, dir_fd=parent_fd)
                self.budget.check()
                os.fsync(parent_fd)
                self.budget.check()
            except FileExistsError:
                if exclusive:
                    raise BuildRefused("Refusing existing output")
        fd = os.open(name, _DIR_FLAGS, dir_fd=parent_fd)
        try:
            self._safe(fd, private, owned=path == self.repo or path.is_relative_to(self.repo))
            original = os.fstat(fd)
            self.entries[path] = (fd, original, parent, private)
            self.check()
        except BaseException:
            if path not in self.entries:
                os.close(fd)
            raise
        return path

    def descend(self, root, parts, *, create=False, private=False):
        for name in parts:
            root = self.directory(root, name, create=create, private=private)
        return root

    def read(self, root, relative, *, limit, private=False, executable=False):
        pieces = PurePosixPath(relative).parts
        parent = self.descend(root, pieces[:-1])
        self.check()
        fd = os.open(pieces[-1], _FILE_FLAGS, dir_fd=self.entries[parent][0])
        try:
            before = os.fstat(fd)
            if (not stat.S_ISREG(before.st_mode) or before.st_uid != os.getuid()
                    or before.st_nlink != 1 or before.st_mode & 0o022 or before.st_size > limit):
                raise BuildRefused("Unsafe or oversized regular file")
            if private and stat.S_IMODE(before.st_mode) != (0o700 if executable else 0o600):
                raise BuildRefused("Output file permissions changed")
            _no_granting_acl(fd)
            chunks, count = [], 0
            while True:
                self.budget.check()
                chunk = os.read(fd, min(65536, limit + 1 - count))
                if not chunk:
                    break
                count += len(chunk)
                if count > limit:
                    raise BuildRefused("File exceeded byte limit")
                chunks.append(chunk)
            after = os.fstat(fd)
            linked = os.stat(pieces[-1], dir_fd=self.entries[parent][0], follow_symlinks=False)
            signature = lambda s: (_identity(s), s.st_mode, s.st_uid, s.st_nlink, s.st_size,
                                   s.st_mtime_ns, s.st_ctime_ns)
            if signature(before) != signature(after) or signature(after) != signature(linked):
                raise BuildRefused("File changed while reading")
            self.check()
            return b"".join(chunks), signature(after)
        finally:
            os.close(fd)

    def write(self, parent, name, data, *, executable=False):
        self.check()
        fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                     0o700 if executable else 0o600, dir_fd=self.entries[parent][0])
        try:
            original = os.fstat(fd)
            self.budget.check()
            os.fchmod(fd, 0o700 if executable else 0o600)
            view = memoryview(data)
            while view:
                self.budget.check()
                count = os.write(fd, view)
                if count <= 0:
                    raise BuildRefused("Incomplete file write")
                view = view[count:]
            self.budget.check()
            os.fsync(fd)
            self.check()
            linked = os.stat(name, dir_fd=self.entries[parent][0], follow_symlinks=False)
            if _identity(original) != _identity(linked) or not stat.S_ISREG(linked.st_mode):
                raise BuildRefused("Output changed during write")
            self.budget.check()
            os.fsync(self.entries[parent][0])
            self.budget.check()
            return _identity(linked)
        except BaseException:
            # Even a partially written receipt is not retained. Only this exact
            # exclusively created inode is eligible for removal.
            linked = os.stat(name, dir_fd=self.entries[parent][0], follow_symlinks=False)
            if stat.S_ISREG(linked.st_mode) and _identity(linked) == _identity(original):
                os.unlink(name, dir_fd=self.entries[parent][0])
            raise
        finally:
            os.close(fd)


def _environment(cwd, argv):
    """Do not inherit tool, loader, Git or signing redirections from the caller."""
    environment = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": str(cwd),
                   "LANG": "C", "LC_ALL": "C", "GIT_CONFIG_NOSYSTEM": "1",
                   "GIT_CONFIG_SYSTEM": "/dev/null", "GIT_CONFIG_GLOBAL": "/dev/null",
                   "GIT_OPTIONAL_LOCKS": "0", "GIT_NO_REPLACE_OBJECTS": "1",
                   "GIT_TERMINAL_PROMPT": "0", "GIT_WORK_TREE": str(cwd),
                   "GIT_DIR": str(cwd / ".git")}
    if argv[0] == "/usr/bin/swift":
        # This path comes only from the fixed builder command, never the caller's
        # environment. Keep Swift's user caches and temporary writes in our run.
        scratch = str(argv[5])
        environment.update(HOME=scratch, TMPDIR=scratch,
                           CLANG_MODULE_CACHE_PATH=scratch + "/clang-module-cache",
                           SWIFTPM_MODULECACHE_OVERRIDE=scratch + "/swift-module-cache")
    overrides = (("core.fsmonitor", "false"), ("core.hooksPath", "/dev/null"),
                 ("core.untrackedCache", "false"), ("core.excludesFile", "/dev/null"),
                 ("core.attributesFile", "/dev/null"))
    environment["GIT_CONFIG_COUNT"] = str(len(overrides))
    for index, (key, value) in enumerate(overrides):
        environment["GIT_CONFIG_KEY_" + str(index)] = key
        environment["GIT_CONFIG_VALUE_" + str(index)] = value
    return environment


def _real_runner(argv, *, cwd, timeout_seconds, max_output_bytes):
    """Bound retained output, wall time and only our child's new process group."""
    if (not argv or argv[0] not in ("/usr/bin/git", "/usr/bin/swift", "/usr/bin/codesign")
            or type(timeout_seconds) not in (int, float)
            or not 0 < timeout_seconds <= 1800 or not math.isfinite(timeout_seconds)
            or max_output_bytes != _OUTPUT_LIMIT):
        raise BuildRefused("Unsupported process request")
    deadline = time.monotonic() + timeout_seconds
    child = subprocess.Popen(tuple(map(str, argv)), cwd=cwd, env=_environment(Path(cwd), argv),
                             stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, shell=False, start_new_session=True,
                             close_fds=True)
    selector = None
    output = {"stdout": bytearray(), "stderr": bytearray()}
    timed_out = truncated = False
    group_signal_attempted = False

    def owned_group_is_inactive():
        # Only a fresh post-EPERM snapshot can explain Darwin's zombie-only
        # group result. This is observational, not an atomic process-table lock.
        snapshot = subprocess.check_output(
            ("/bin/ps", "-axo", "pid=,pgid=,stat="), timeout=2,
            stdin=subprocess.DEVNULL, stderr=subprocess.DEVNULL, shell=False,
            close_fds=True, env=_environment(Path(cwd), argv))
        # check_output captures before this acceptance bound is checked; it is
        # not a bound on the inspection subprocess's transient memory usage.
        if type(snapshot) is not bytes or len(snapshot) > _OUTPUT_LIMIT:
            raise BuildRefused("Process inspection exceeded accepted byte bound")
        if not snapshot or not snapshot.endswith(b"\n"):
            raise BuildRefused("Incomplete process inspection")
        seen = set()
        inactive = True
        for row in snapshot.split(b"\n")[:-1]:
            match = re.fullmatch(
                rb"[ \t]*(0|[1-9][0-9]{0,9})[ \t]+(0|[1-9][0-9]{0,9})"
                rb"[ \t]+([IRSTUZ][+<>AELNSTVWXs]*)[ \t]*", row)
            if match is None:
                raise BuildRefused("Malformed process inspection")
            pid, pgid = int(match[1]), int(match[2])
            if pid > 2_147_483_647 or pgid > 2_147_483_647 or pid in seen:
                raise BuildRefused("Invalid process inspection identity")
            seen.add(pid)
            if pid == child.pid and pgid != child.pid:
                raise BuildRefused("Owned process leader changed group")
            if pgid == child.pid and not match[3].startswith(b"Z"):
                inactive = False
        return inactive

    def kill_owned_group():
        # The unreaped leader reserves this PID/group identity until our one
        # cleanup signal. Never signal again after wait could permit PID reuse.
        nonlocal group_signal_attempted
        if group_signal_attempted:
            return
        # Record the attempt before any syscall can fail. Cleanup must never
        # retry a failed signal, including after a reap releases the identity.
        group_signal_attempted = True
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        except PermissionError as error:
            if (sys.platform != "darwin" or error.errno != errno.EPERM
                    or not owned_group_is_inactive()):
                raise

    try:
        selector = selectors.DefaultSelector()
        for name, stream in (("stdout", child.stdout), ("stderr", child.stderr)):
            os.set_blocking(stream.fileno(), False)
            selector.register(stream, selectors.EVENT_READ, name)
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                timed_out = True
                kill_owned_group()
                break
            for key, _ in selector.select(min(remaining, 0.1)):
                chunk = os.read(key.fd, 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                retained = sum(map(len, output.values()))
                room = max_output_bytes - retained
                output[key.data].extend(chunk[:room])
                if len(chunk) > room:
                    truncated = True
                    kill_owned_group()
                    break
            if truncated:
                break
        # Also terminate descendants after the session leader exits normally.
        # A daemonised descendant escaping this session is outside this boundary.
        kill_owned_group()
    finally:
        try:
            kill_owned_group()
        finally:
            try:
                child.wait(timeout=5)
            finally:
                try:
                    if selector is not None:
                        selector.close()
                finally:
                    try:
                        child.stdout.close()
                    finally:
                        child.stderr.close()
    return ProcessResult(child.returncode, bytes(output["stdout"]), bytes(output["stderr"]),
                         timed_out, truncated)


def _command(runner, directories, repo, argv, timeout):
    directories.check()
    allowance = min(timeout, directories.budget.remaining())
    result = runner(argv, cwd=repo, timeout_seconds=allowance, max_output_bytes=_OUTPUT_LIMIT)
    directories.check()
    if (not isinstance(result, ProcessResult) or type(result.returncode) is not int
            or type(result.stdout) is not bytes or type(result.stderr) is not bytes
            or type(result.timed_out) is not bool or type(result.output_truncated) is not bool
            or result.returncode != 0 or result.timed_out or result.output_truncated
            or len(result.stdout) + len(result.stderr) > _OUTPUT_LIMIT):
        raise BuildRefused("Process failed or returned incomplete output")
    return result.stdout


def _source(runner, directories, repo):
    revision = _command(runner, directories, repo, ("/usr/bin/git", "rev-parse", "--verify", "HEAD"), 30)
    if not re.fullmatch(rb"[0-9a-f]{40}\n", revision):
        raise BuildRefused("Source revision is not an exact lowercase Git SHA")
    if _command(runner, directories, repo,
                ("/usr/bin/git", "status", "--porcelain=v1", "--untracked-files=all"), 30):
        raise BuildRefused("Source tree is dirty")
    listing = _command(runner, directories, repo, ("/usr/bin/git", "ls-files", "-z"), 30)
    if not listing or not listing.endswith(b"\0"):
        raise BuildRefused("Missing tracked source list")
    paths = []
    for raw in listing[:-1].split(b"\0"):
        directories.budget.check()
        name = raw.decode("utf-8", errors="strict")
        parts = name.split("/")
        if (not name or any(p in ("", ".", "..") for p in parts)
                or parts[0] in (".build", ".git") or "\\" in name
                or any(ord(c) < 32 or ord(c) == 127 for c in name) or name in paths):
            raise BuildRefused("Unsafe or duplicate tracked source path")
        paths.append(name)
    hashes, signatures, total = {}, {}, 0
    for name in sorted(paths):
        data, signature = directories.read(repo, name, limit=_FILE_LIMIT - total)
        total += len(data)
        hashes[name] = hashlib.sha256(data).hexdigest()
        signatures[name] = signature
        directories.budget.check()
    return revision[:-1].decode("ascii"), hashes, signatures


def _json(value):
    return (json.dumps(value, sort_keys=True, indent=2) + "\n").encode("utf-8")



def _signature_metadata(directories, bundle):
    directories.budget.check()
    contents = bundle / "Contents"
    fd = directories.entries[contents][0]
    if "_CodeSignature" not in os.listdir(fd):
        return
    directories.check()
    child_fd = os.open("_CodeSignature", _DIR_FLAGS, dir_fd=fd)
    try:
        original = os.fstat(child_fd)
        if original.st_uid != os.getuid() or original.st_mode & 0o022:
            raise BuildRefused("Unsafe signing metadata directory")
        _no_granting_acl(child_fd)
        if os.listdir(child_fd) != ["CodeResources"]:
            raise BuildRefused("Unexpected signing metadata")
        resource_fd = os.open("CodeResources", _FILE_FLAGS, dir_fd=child_fd)
        try:
            resource = os.fstat(resource_fd)
            if (not stat.S_ISREG(resource.st_mode) or resource.st_uid != os.getuid()
                    or resource.st_nlink != 1 or resource.st_mode & 0o022 or resource.st_size > _FILE_LIMIT):
                raise BuildRefused("Unsafe signing resource seal")
            _no_granting_acl(resource_fd)
            directories.budget.check()
            os.fchmod(resource_fd, 0o600)
            directories.budget.check()
            os.fsync(resource_fd)
            directories.budget.check()
            linked = os.stat("CodeResources", dir_fd=child_fd, follow_symlinks=False)
            if _identity(linked) != _identity(resource):
                raise BuildRefused("Signing resource seal changed")
        finally:
            os.close(resource_fd)
        directories.budget.check()
        os.fchmod(child_fd, 0o700)
        directories.budget.check()
        os.fsync(child_fd)
        directories.budget.check()
        linked = os.stat("_CodeSignature", dir_fd=fd, follow_symlinks=False)
        if _identity(linked) != _identity(original):
            raise BuildRefused("Signing metadata directory changed")
        directories.budget.check()
        os.fsync(fd)
        directories.check()
    finally:
        os.close(child_fd)
    directories.directory(contents, "_CodeSignature", create=False, private=True)


def _inventory(directories, root):
    hashes, total = {}, 0
    allowed_dirs = {p + suffix for p in ("PatchedApp.app", "PatchedDisposableClientApp.app")
                    for suffix in ("", "/Contents", "/Contents/MacOS", "/Contents/_CodeSignature")}
    allowed_files = {"patched-disposable-proof", *_RECEIPTS}
    for product in _PRODUCTS[:2]:
        allowed_files.update((product + ".app/Contents/Info.plist",
                              product + ".app/Contents/MacOS/" + product,
                              product + ".app/Contents/_CodeSignature/CodeResources"))
    executable_names = {"patched-disposable-proof", "PatchedApp", "PatchedDisposableClientApp"}

    def walk(directory, prefix):
        nonlocal total
        directories.check()
        fd = directories.entries[directory][0]
        names = sorted(os.listdir(fd))
        if len(names) > 64:
            raise BuildRefused("Unexpected output file count")
        for name in names:
            directories.budget.check()
            if name in (".", "..") or "/" in name:
                raise BuildRefused("Unsafe output entry")
            relative = prefix + name
            value = os.stat(name, dir_fd=fd, follow_symlinks=False)
            if stat.S_ISDIR(value.st_mode):
                if relative not in allowed_dirs:
                    raise BuildRefused("Unexpected output directory")
                child = directories.directory(directory, name, create=False, private=True)
                walk(child, relative + "/")
            elif stat.S_ISREG(value.st_mode):
                if relative not in allowed_files:
                    raise BuildRefused("Unexpected output file")
                if len(hashes) >= 128:
                    raise BuildRefused("Unexpected output file count")
                data, _ = directories.read(root, relative, limit=min(_FILE_LIMIT, _TOTAL_LIMIT - total),
                                           private=True, executable=name in executable_names)
                if name in executable_names and not data:
                    raise BuildRefused("Empty signed executable")
                total += len(data)
                hashes[relative] = hashlib.sha256(data).hexdigest()
                directories.budget.check()
            else:
                raise BuildRefused("Nonregular output entry")
    walk(root, "")
    directories.budget.check()
    return hashes


def build_toolset(repo: Path, *, runner: Callable, clock: Callable | None = None) -> Path:
    """Return an exclusive physical run/toolset only after complete publication."""
    # Clock injection is an explicit inert-check API only; main uses real time.
    budget = _Budget(time.monotonic if clock is None else clock)
    directories = _Directories(budget)
    written_receipts = {}
    staging = None
    try:
        directories.open_repo(repo)
        source = _source(runner, directories, repo)
        base = directories.directory(repo, ".build", create=True, private=False)
        owned = directories.directory(base, "development-toolset", create=True, private=True)
        run = directories.directory(owned, "run-" + secrets.token_hex(16), create=True,
                                    private=True, exclusive=True)
        scratch = directories.directory(run, "swift", create=True, private=True, exclusive=True)
        stage_parent = directories.directory(run, ".staging", create=True, private=True, exclusive=True)
        staging = directories.directory(stage_parent, "toolset", create=True, private=True, exclusive=True)
        prefix = ("/usr/bin/swift", "build", "--package-path", str(repo),
                  "--scratch-path", str(scratch), "--jobs", "2")
        for product in _PRODUCTS:
            _command(runner, directories, repo, prefix + ("--product", product), 1800)
        raw_bin = _command(runner, directories, repo, prefix + ("--show-bin-path",), 1800)
        bin_text = raw_bin.decode("utf-8", errors="strict")
        if not bin_text.endswith("\n") or "\n" in bin_text[:-1] or "\r" in bin_text:
            raise BuildRefused("Malformed Swift bin path")
        bin_path = Path(bin_text[:-1])
        if (not bin_path.is_absolute() or ".." in bin_path.parts
                or not bin_path.is_relative_to(scratch) or bin_path == scratch):
            raise BuildRefused("Swift bin path escapes scratch")
        directories.descend(scratch, bin_path.relative_to(scratch).parts)
        destinations = {}
        total = 0
        for product in _PRODUCTS:
            data, _ = directories.read(bin_path, product, limit=_FILE_LIMIT)
            budget.check()
            total += len(data)
            if not data or total > _TOTAL_LIMIT:
                raise BuildRefused("Empty or oversized product")
            if product == "patched-disposable-proof":
                target_parent = staging
                destinations[product] = staging / product
            else:
                bundle = directories.directory(staging, product + ".app", create=True, private=True, exclusive=True)
                contents = directories.directory(bundle, "Contents", create=True, private=True, exclusive=True)
                target_parent = directories.directory(contents, "MacOS", create=True, private=True, exclusive=True)
                destinations[product] = bundle
                disposable = product == "PatchedDisposableClientApp"
                plist = {"CFBundleExecutable": product,
                         "CFBundleIdentifier": "im.patched.disposable.nativeproof" if disposable else "im.patched.private-development",
                         "CFBundleName": "Patched disposable native proof" if disposable else "Patched private development",
                         "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "0.0.1",
                         "CFBundleVersion": "1", "NSHighResolutionCapable": True}
                directories.write(contents, "Info.plist", plistlib.dumps(plist, sort_keys=True))
            directories.write(target_parent, product, data, executable=True)
            budget.check()
        targets = [destinations[name] for name in ("patched-disposable-proof", "PatchedApp", "PatchedDisposableClientApp")]
        for target in targets:
            _command(runner, directories, repo, ("/usr/bin/codesign", "--force", "--sign", "-", str(target)), 60)
        for target in targets[1:]:
            _signature_metadata(directories, target)
        for target in targets:
            _command(runner, directories, repo, ("/usr/bin/codesign", "--verify", "--strict", "--verbose=2", str(target)), 60)
        if _source(runner, directories, repo) != source:
            raise BuildRefused("Source changed during build")
        files = _inventory(directories, staging)
        budget.check()
        required_files = {"patched-disposable-proof"}
        for product in _PRODUCTS[:2]:
            required_files.update((product + ".app/Contents/Info.plist",
                                   product + ".app/Contents/MacOS/" + product))
        if not required_files.issubset(files):
            raise BuildRefused("Missing verified toolset product or metadata")
        artifact_files = files
        child_hash = files["patched-disposable-proof"]
        native_hash = files["PatchedDisposableClientApp.app/Contents/MacOS/PatchedDisposableClientApp"]
        # An obstruction is never adopted, chmodded, followed or removed.
        if any(name in os.listdir(directories.entries[staging][0]) for name in _RECEIPTS):
            raise BuildRefused("Receipt path already exists")
        receipts = {"builder-receipt.json": {"binarySHA256": child_hash, "sourceRevision": source[0]},
                    "native-builder-receipt.json": {"nativeBinarySHA256": native_hash,
                                                    "childBinarySHA256": child_hash, "sourceRevision": source[0]}}
        for name, receipt in receipts.items():
            budget.check()
            written_receipts[name] = directories.write(staging, name, _json(receipt))
            budget.check()
        files = _inventory(directories, staging)
        budget.check()
        if {k: v for k, v in files.items() if k not in _RECEIPTS} != artifact_files:
            raise BuildRefused("Signed output changed during receipt publication")
        for name, receipt in receipts.items():
            if files.get(name) != hashlib.sha256(_json(receipt)).hexdigest():
                raise BuildRefused("Receipt changed during publication")
        manifest = {"schemaVersion": 1, "kind": "private-development-toolset", "sourceRevision": source[0],
                    "sourceFiles": source[1], "files": files, "signing": "ad-hoc",
                    "sourceAttestation": False, "installationAuthority": False}
        budget.check()
        written_receipts[_RECEIPTS[2]] = directories.write(staging, _RECEIPTS[2], _json(manifest))
        budget.check()
        # Re-read all bytes and permissions after metadata writes, before visibility.
        final_files = _inventory(directories, staging)
        budget.check()
        if (final_files.get(_RECEIPTS[2]) != hashlib.sha256(_json(manifest)).hexdigest()
                or {k: v for k, v in final_files.items() if k != _RECEIPTS[2]} != files):
            raise BuildRefused("Output changed before publication")
        directories.check()
        run_fd = directories.entries[run][0]
        if "toolset" in os.listdir(run_fd):
            raise BuildRefused("Final toolset already exists")
        budget.check()
        os.fsync(directories.entries[staging][0])
        budget.check()
        os.rename("toolset", "toolset", src_dir_fd=directories.entries[stage_parent][0], dst_dir_fd=run_fd)
        # Keep rollback descriptor-relative even after the publication rename.
        try:
            budget.check()
            os.fsync(run_fd)
            budget.check()
            published = os.stat("toolset", dir_fd=run_fd, follow_symlinks=False)
            if (not stat.S_ISDIR(published.st_mode)
                    or _identity(published) != _identity(os.fstat(directories.entries[staging][0]))):
                raise BuildRefused("Published toolset identity changed")
        except BaseException:
            _remove_receipts(directories.entries[staging][0], written_receipts)
            raise
        budget.check()
        return run / "toolset"
    except (OSError, ValueError, UnicodeError, KeyError, TypeError, subprocess.SubprocessError) as error:
        raise BuildRefused("Development toolset refused: " + type(error).__name__) from error
    finally:
        # This also runs on typed refusals. Delete only exact regular files this
        # invocation created. Unknown obstructions and diagnostic bytes survive.
        if staging is not None and sys.exc_info()[0] is not None:
            _remove_receipts(directories.entries[staging][0], written_receipts)
        directories.close()


def _remove_receipts(fd, written):
    for name, identity in written.items():
        try:
            value = os.stat(name, dir_fd=fd, follow_symlinks=False)
            if stat.S_ISREG(value.st_mode) and _identity(value) == identity and value.st_uid == os.getuid():
                os.unlink(name, dir_fd=fd)
        except FileNotFoundError:
            pass
    os.fsync(fd)


def main(argv: Sequence[str] | None = None) -> int:
    """Only --build may select the fixed repository and real bounded runner."""
    if list(sys.argv[1:] if argv is None else argv) != ["--build"]:
        print("Explicit --build is required; no other options are accepted.", file=sys.stderr)
        return 2
    try:
        output = build_toolset(Path(__file__).resolve().parent.parent, runner=_real_runner)
    except BuildRefused as error:
        print(str(error), file=sys.stderr)
        return 1
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
