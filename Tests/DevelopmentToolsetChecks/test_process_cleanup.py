"""Independent synthetic cleanup contracts; no process or signal is real.

These exercise _real_runner, not a proposed cleanup helper. The only permitted
inspection is a bounded /bin/ps snapshot in the trusted supervisor's row format.
"""
import contextlib
import errno
import importlib.util
from pathlib import Path
import signal
import subprocess
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/build-development-toolset.py'
SPEC = importlib.util.spec_from_file_location('cleanup_builder_under_check', SCRIPT)
BUILDER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = BUILDER
SPEC.loader.exec_module(BUILDER)


class Pipe:
    def __init__(self, fd, events):
        self.fd, self.events, self.closed = fd, events, False

    def fileno(self):
        return self.fd

    def close(self):
        self.closed = True
        self.events.append(('close', self.fd))


class Child:
    pid = 42042  # Synthetic identity, never sent to a system call.

    def __init__(self, events, wait_error=False):
        self.events = events
        self.stdout, self.stderr = Pipe(701, events), Pipe(702, events)
        self.returncode, self.reaped = None, False
        self.wait_error = wait_error

    def poll(self):
        # poll may reap the leader and release the PID before group cleanup.
        self.reaped = True
        self.returncode = 0
        self.events.append(('poll',))
        return 0

    def wait(self, timeout=None):
        if not isinstance(timeout, (int, float)) or not 0 < timeout <= 5:
            raise AssertionError('Reap must use a positive bounded timeout <=5s')
        self.events.append(('wait', timeout))
        if self.wait_error:
            raise subprocess.TimeoutExpired('synthetic child', timeout)
        self.reaped, self.returncode = True, 0
        return 0


class Selector:
    def __init__(self, events):
        self.events, self.keys, self.closed = events, {}, False

    def register(self, stream, mask, data):
        self.keys[stream.fd] = SimpleNamespace(fd=stream.fd, fileobj=stream, data=data)

    def unregister(self, stream):
        del self.keys[stream.fd]

    def get_map(self):
        return self.keys

    def select(self, timeout):
        if not 0 < timeout <= .1:
            raise AssertionError('Selector wait is unbounded')
        self.events.append(('select', timeout))
        return [(key, 1) for key in list(self.keys.values())]

    def close(self):
        self.closed = True
        self.events.append(('selector-close',))


class World:
    def __init__(self, case, *, signal_error=None, inspection='zombie',
                 mode='normal', wait_error=False):
        self.case, self.events = case, []
        self.child = Child(self.events, wait_error)
        self.selector = Selector(self.events)
        self.signal_error, self.inspection, self.mode = signal_error, inspection, mode
        self.signals, self.snapshots, self.ticks = 0, [], 0
        self.chunks = {701: [b'hello', b''], 702: [b'warning', b'']}
        if mode == 'truncated':
            self.chunks[701] = [b'x' * 65536] * 17
            self.chunks[702] = [b'']

    def monotonic(self):
        self.ticks += 1
        if self.ticks > 100:
            raise AssertionError('Synthetic clock exhausted: runner did not finish')
        return self.ticks * (20 if self.mode == 'timeout' else .001)

    def spawn(self, argv, **kwargs):
        self.case.assertEqual(tuple(argv), ('/usr/bin/git', 'status'))
        self.case.assertIs(kwargs.get('start_new_session'), True)
        self.case.assertIs(kwargs.get('shell'), False)
        self.case.assertIs(kwargs.get('close_fds'), True)
        return self.child

    def killpg(self, pgid, sig):
        self.case.assertEqual(pgid, self.child.pid)
        self.case.assertEqual(sig, signal.SIGKILL)
        self.case.assertFalse(self.child.reaped, 'Group signalled after PID reservation released')
        self.signals += 1
        self.events.append(('signal', sig))
        if self.signal_error is not None:
            raise self.signal_error

    def inspect(self, argv, **kwargs):
        self.case.assertEqual(tuple(argv), ('/bin/ps', '-axo', 'pid=,pgid=,stat='))
        self.case.assertIsNot(kwargs.get('shell'), True)
        self.case.assertGreater(kwargs.get('timeout', 0), 0)
        self.case.assertLessEqual(kwargs['timeout'], 2)
        self.case.assertFalse(self.child.reaped, 'Inspection lost unreaped leader identity')
        self.snapshots.append(self.signals)
        self.events.append(('inspect', self.signals))
        # Before EPERM there is a live owned member. A stale pre-signal
        # snapshot cannot establish the post-signal Darwin disposition.
        rows = '42042 42042 S\n'
        if self.signals:
            rows = {
                'zombie': '42042 42042 Z\n42043 42042 Z+\n999 999 S\n',
                'dead': '999 999 S\n',
                'live': '42042 42042 Z\n42043 42042 S\n',
                'malformed': '42042 42042\n',
                'invalid_state': '42042 42042 ???\n',
                'changed': '42042 77777 S\n',
                'oversized': '9 9 Z\n' * 180000,
            }.get(self.inspection, '')
            if self.inspection == 'failed':
                raise subprocess.CalledProcessError(1, argv)
            if self.inspection == 'timeout':
                raise subprocess.TimeoutExpired(argv, kwargs['timeout'])
        return rows if kwargs.get('text') or kwargs.get('universal_newlines') else rows.encode()

    def run_inspection(self, argv, **kwargs):
        result = self.inspect(argv, **kwargs)
        return subprocess.CompletedProcess(argv, 0, result, '' if isinstance(result, str) else b'')

    def read(self, fd, amount):
        self.case.assertEqual(amount, 65536)
        return self.chunks[fd].pop(0)

    @contextlib.contextmanager
    def installed(self):
        # Every process/signal/descriptor operation reachable by this runner
        # is replaced. Unknown commands fail; no passthrough is available.
        with contextlib.ExitStack() as stack:
            replacements = (
                ('subprocess.Popen', self.spawn),
                ('subprocess.check_output', self.inspect),
                ('subprocess.run', self.run_inspection),
                ('os.killpg', self.killpg),
                ('os.kill', lambda *a, **k: self.case.fail('Unexpected individual signal')),
                ('os.set_blocking', lambda *a: None),
                ('os.read', self.read),
                ('selectors.DefaultSelector', lambda: self.selector),
                ('time.monotonic', self.monotonic),
                ('sys.platform', 'darwin'),
            )
            for name, replacement in replacements:
                stack.enter_context(patch(name, replacement))
            yield

    def invoke(self):
        with self.installed():
            return BUILDER._real_runner(('/usr/bin/git', 'status'), cwd=SCRIPT.parent.parent,
                                        timeout_seconds=10, max_output_bytes=1_048_576)

    def assert_cleanup(self):
        self.case.assertLessEqual(self.signals, 1, 'Cleanup retried an unsuccessful signal')
        self.case.assertTrue(any(e[0] == 'wait' for e in self.events),
                             'Signal refusal skipped mandatory bounded reap attempt')
        self.case.assertTrue(self.selector.closed, 'Selector leaked on cleanup failure')
        self.case.assertTrue(self.child.stdout.closed, 'stdout leaked on cleanup failure')
        self.case.assertTrue(self.child.stderr.closed, 'stderr leaked on cleanup failure')
        waits = [i for i, e in enumerate(self.events) if e[0] in ('wait', 'poll')]
        signals = [i for i, e in enumerate(self.events) if e[0] == 'signal']
        if signals and waits:
            self.case.assertLess(max(signals), min(waits), 'Signal occurred after possible reap')


class ProcessCleanupChecks(unittest.TestCase):
    def test_normal_output_and_owned_session_cleanup(self):
        world = World(self)
        result = world.invoke()
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, b'hello', b'warning'))
        self.assertFalse(result.timed_out)
        self.assertFalse(result.output_truncated)
        self.assertEqual(world.signals, 1)
        world.assert_cleanup()

    def test_timeout_remains_flagged_and_cleans_up_before_reap(self):
        world = World(self, mode='timeout')
        result = world.invoke()
        self.assertTrue(result.timed_out)
        self.assertFalse(result.output_truncated)
        self.assertEqual(world.signals, 1)
        world.assert_cleanup()

    def test_output_bound_remains_flagged_and_cleans_up_before_reap(self):
        world = World(self, mode='truncated')
        result = world.invoke()
        self.assertTrue(result.output_truncated)
        self.assertFalse(result.timed_out)
        self.assertEqual(len(result.stdout) + len(result.stderr), 1_048_576)
        self.assertEqual(world.signals, 1)
        world.assert_cleanup()

    def test_darwin_eperm_requires_fresh_zombie_only_evidence(self):
        world = World(self, signal_error=PermissionError(errno.EPERM, 'synthetic'), inspection='zombie')
        result = world.invoke()
        self.assertEqual(result.returncode, 0)
        self.assertIn(1, world.snapshots, 'No fresh inspection after EPERM')
        world.assert_cleanup()

    def test_darwin_eperm_requires_fresh_dead_group_evidence(self):
        world = World(self, signal_error=PermissionError(errno.EPERM, 'synthetic'), inspection='dead')
        self.assertEqual(world.invoke().stdout, b'hello')
        self.assertIn(1, world.snapshots)
        world.assert_cleanup()

    def test_zombie_eperm_does_not_clear_timeout_flag(self):
        world = World(self, mode='timeout', signal_error=PermissionError(errno.EPERM, 'synthetic'))
        result = world.invoke()
        self.assertTrue(result.timed_out)
        self.assertFalse(result.output_truncated)
        self.assertIn(1, world.snapshots)
        world.assert_cleanup()

    def test_zombie_eperm_does_not_clear_output_truncation_flag(self):
        world = World(self, mode='truncated', signal_error=PermissionError(errno.EPERM, 'synthetic'))
        result = world.invoke()
        self.assertTrue(result.output_truncated)
        self.assertEqual(len(result.stdout) + len(result.stderr), 1_048_576)
        self.assertIn(1, world.snapshots)
        world.assert_cleanup()

    def assert_refusal_cleans(self, world):
        with self.assertRaises((OSError, BUILDER.BuildRefused, subprocess.SubprocessError)):
            world.invoke()
        world.assert_cleanup()

    def test_live_descendant_eperm_refuses_even_with_zombie_leader(self):
        world = World(self, signal_error=PermissionError(errno.EPERM, 'synthetic'), inspection='live')
        self.assert_refusal_cleans(world)
        self.assertIn(1, world.snapshots)

    def test_failed_inspection_refuses_and_cleans(self):
        self.assert_refusal_cleans(World(self, signal_error=PermissionError(errno.EPERM, 'synthetic'), inspection='failed'))

    def test_timed_out_inspection_refuses_and_cleans(self):
        self.assert_refusal_cleans(World(self, signal_error=PermissionError(errno.EPERM, 'synthetic'), inspection='timeout'))

    def test_malformed_inspection_refuses_and_cleans(self):
        self.assert_refusal_cleans(World(self, signal_error=PermissionError(errno.EPERM, 'synthetic'), inspection='malformed'))

    def test_unknown_process_state_refuses_and_cleans(self):
        self.assert_refusal_cleans(World(self, signal_error=PermissionError(errno.EPERM, 'synthetic'), inspection='invalid_state'))

    def test_changed_leader_group_refuses_and_cleans(self):
        self.assert_refusal_cleans(World(self, signal_error=PermissionError(errno.EPERM, 'synthetic'), inspection='changed'))

    def test_oversized_inspection_refuses_and_cleans(self):
        self.assert_refusal_cleans(World(self, signal_error=PermissionError(errno.EPERM, 'synthetic'), inspection='oversized'))

    def test_non_eperm_permission_error_is_not_accepted_as_zombie_race(self):
        self.assert_refusal_cleans(World(self, signal_error=PermissionError(errno.EACCES, 'synthetic')))

    def test_other_signal_error_refuses_but_cannot_skip_cleanup(self):
        self.assert_refusal_cleans(World(self, signal_error=OSError(errno.EIO, 'synthetic')))

    def test_eperm_during_timeout_cannot_skip_cleanup(self):
        self.assert_refusal_cleans(World(self, mode='timeout', signal_error=PermissionError(errno.EPERM, 'synthetic'), inspection='live'))

    def test_eperm_during_truncation_cannot_skip_cleanup(self):
        self.assert_refusal_cleans(World(self, mode='truncated', signal_error=PermissionError(errno.EPERM, 'synthetic'), inspection='live'))

    def test_wait_timeout_still_closes_selector_and_both_pipes(self):
        self.assert_refusal_cleans(World(self, wait_error=True))

    def test_missing_group_is_harmless_and_never_signalled_after_reap(self):
        world = World(self, signal_error=ProcessLookupError(errno.ESRCH, 'synthetic'))
        self.assertEqual(world.invoke().returncode, 0)
        self.assertEqual(world.signals, 1)
        world.assert_cleanup()


if __name__ == '__main__':
    unittest.main()
