#!/usr/bin/env python3
"""Explicit host operations only; importing performs no I/O or guest action.
Raw capture is evidence, not physical-proof validation. No interventions here.
"""
import argparse
import hashlib
import json
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

RUN = "firefox-native-20261011-a"
P = "/Users/andy/PatchedProof"
R = P + "/" + RUN
B = P + "/.bootstrap-" + RUN
N = P + "/.native-bootstrap-" + RUN
TARGET = "parallels-0A0A0A0A-0000-4000-8000-000000000001"
CHILD = B + "/patched-disposable-proof"
NATIVE = N + "/PatchedDisposableClientApp.app/Contents/MacOS/PatchedDisposableClientApp"
SSH_CONFIG = Path("/Users/andybridson/Development/Patched.im/.claude/linear-runs/evidence/pat2638-processfix/ssh-config")
EVIDENCE = Path("/Users/andybridson/Development/Patched.im/.claude/linear-runs/evidence/pat2602-native")
PAIRS = {
    "tampered-artifact": ("tampered-artifact",),
    "truncated-artifact": ("truncated-artifact",),
    "recorded-evidence": ("recorded-evidence",),
    "wrong-signer-target": ("wrong-signer-target",),
    "wrong-signer-staged": ("wrong-signer-staged",),
    "invalid-signature": ("invalid-catalogue",),
    "untrusted-key": ("invalid-catalogue",),
    "replayed-sequence": ("replayed-catalogue",),
    "expired-catalogue": ("replayed-catalogue",),
    "open-app": ("open-app",),
    "staging": ("staging-failure", "recover-after-staging"),
    "update": ("update", "restore-old"),
    "swap": ("interrupted-swap", "recover-after-swap"),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def pairs_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate receipt key")
        result[key] = value
    return result


def receipt(path, keys):
    raw = path.read_bytes()
    require(len(raw) <= 65536, "Oversized builder receipt")
    value = json.loads(raw, object_pairs_hook=pairs_object)
    require(isinstance(value, dict) and set(value) == set(keys), "Wrong builder receipt schema")
    for key, item in value.items():
        length = 40 if key == "sourceRevision" else 64
        require(isinstance(item, str) and re.fullmatch("[0-9a-f]{" + str(length) + "}", item), "Invalid builder receipt value")
    return raw, value


def bindings():
    tools = EVIDENCE / "merged-toolset"
    child_raw, child = receipt(tools / "builder-receipt.json", ("binarySHA256", "sourceRevision"))
    native_raw, native = receipt(tools / "native-builder-receipt.json", ("nativeBinarySHA256", "childBinarySHA256", "sourceRevision"))
    require(child["sourceRevision"] == native["sourceRevision"], "Source revisions differ")
    require(child["binarySHA256"] == native["childBinarySHA256"], "Child receipt hashes differ")
    require(sha((tools / "patched-disposable-proof").read_bytes()) == child["binarySHA256"], "Retained child hash differs")
    binary = tools / "PatchedDisposableClientApp.app/Contents/MacOS/PatchedDisposableClientApp"
    require(sha(binary.read_bytes()) == native["nativeBinarySHA256"], "Retained native hash differs")
    return {"sourceRevision": child["sourceRevision"], "childSHA256": child["binarySHA256"],
            "nativeSHA256": native["nativeBinarySHA256"], "childReceiptSHA256": sha(child_raw),
            "nativeReceiptSHA256": sha(native_raw)}


def child_prepare(root):
    require(root in PAIRS, "Unknown preparation root")
    return [CHILD, "--target-id", TARGET, "--run-id", RUN, "--case-root", root,
            "--case", "prepare-root", "--explicit-trigger"]


def native_launch(root, action):
    require(root in PAIRS and action in PAIRS[root], "Unsupported native root/action pair")
    return [NATIVE, "--run-id", RUN, "--case-root", root, "--action", action, "--proof-driver"]


def ssh_argv(script):
    return ["ssh", "-F", str(SSH_CONFIG), "-o", "BatchMode=yes", "mac-staging-parallels", script]



def guarded_script(argv, bound):
    """Enforce exact observed bootstrap bindings before a mutating dispatch."""
    checks = [(CHILD, "childSHA256"), (NATIVE, "nativeSHA256"),
              (B + "/builder-receipt.json", "childReceiptSHA256"),
              (N + "/native-builder-receipt.json", "nativeReceiptSHA256")]
    lines = ["set -eu", '[ "$(/usr/bin/id -ru)" = 501 ]',
             '[ "$(/usr/bin/id -u)" = 501 ]',
             '[ "$(/usr/bin/stat -f %u /dev/console)" = 501 ]']
    for path, key in checks:
        expected = bound[key]
        require(isinstance(expected, str) and re.fullmatch(r"[0-9a-f]{64}", expected), "Invalid guarded hash")
        # Every value is an argv element quoted by shlex, never shell code.
        lines.append(shlex.join(["/usr/bin/printf", "%s  %s\\n", expected, path]) +
                     " | " + shlex.join(["/usr/bin/shasum", "-a", "256", "-c", "-"]))
    lines.append(shlex.join(argv))
    return "\n".join(lines)


def preflight_script():
    # Read only; full GuestGuard authority is still independently observed by native code.
    argv = ["/usr/bin/id", "-ru"]
    lines = ["set -eu", shlex.join(argv), "/usr/bin/id -u",
             "/usr/bin/stat -f %u /dev/console", "/bin/hostname", "/usr/bin/sw_vers",
             "/usr/bin/uname -m", "/usr/sbin/sysctl -n kern.hv_vmm_present",
             shlex.join(["/bin/df", "-k", P])]
    for path in [CHILD, NATIVE, B + "/builder-receipt.json", N + "/native-builder-receipt.json"]:
        lines.append(shlex.join(["/usr/bin/shasum", "-a", "256", path]))
    for path in [B + "/builder-receipt.json", N + "/native-builder-receipt.json"]:
        lines.append(shlex.join(["/bin/cat", path]))
    return "\n".join(lines)


def capture(directory, label, argv, context):
    require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]{0,95}", label), "Unsafe evidence label")
    paths = {suffix: directory / (label + suffix) for suffix in (".stdout", ".stderr", "-receipt.json", "-lifecycle.json")}
    opened = {}
    try:
        # Reserve ALL destinations before dispatch; existing files are never touched.
        for suffix, path in paths.items():
            opened[suffix] = path.open("xb")
        process = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=opened[".stdout"],
                                   stderr=opened[".stderr"], start_new_session=True)
        life = {"runID": RUN, "label": label, "localPID": process.pid, "localSessionID": process.pid,
                "argv": argv, "operation": context["operation"], "bindings": context.get("bindings"),
                "statusScope": "local launcher/SSH only; native child status is separate guest evidence"}
        opened["-lifecycle.json"].write(json.dumps(life, sort_keys=True).encode() + b"\n")
        opened["-lifecycle.json"].flush()
        print(json.dumps({"event": "host-launcher-started", "label": label, "localPID": process.pid}), flush=True)
        try:
            # No timeout/kill/terminate path: authorised native operations may pause.
            status = process.wait()
        except KeyboardInterrupt:
            pending = {"state": "pending", "localPID": process.pid, "localSessionID": process.pid,
                       "exitCode": None, "remoteChildStatus": "not inferred", "automaticTermination": False}
            opened["-receipt.json"].write(json.dumps(pending, sort_keys=True).encode() + b"\n")
            print(json.dumps(pending), flush=True)
            return None
        opened[".stdout"].flush(); opened[".stderr"].flush()
        result = {"state": "completed", "exitCode": status,
                  "stdoutSHA256": sha(paths[".stdout"].read_bytes()), "stderrSHA256": sha(paths[".stderr"].read_bytes()),
                  "statusScope": life["statusScope"]}
        opened["-receipt.json"].write(json.dumps(result, sort_keys=True).encode() + b"\n")
        return result
    finally:
        for stream in opened.values():
            stream.close()


def self_check():
    require(len(PAIRS) == 13 and sum(map(len, PAIRS.values())) == 16, "Finite case mapping differs")
    for root, actions in PAIRS.items():
        require(shlex.split(shlex.join(child_prepare(root))) == child_prepare(root), "Child quote roundtrip")
        for action in actions:
            require(shlex.split(shlex.join(native_launch(root, action))) == native_launch(root, action), "Native quote roundtrip")
    for root, action in [("../escape", "update"), ("update", "update; false"), ("staging", "update")]:
        try:
            native_launch(root, action)
        except ValueError:
            pass
        else:
            raise AssertionError("Invalid pair accepted")
    test_bound = {key: str(index) * 64 for index, key in enumerate(
        ("childSHA256", "nativeSHA256", "childReceiptSHA256", "nativeReceiptSHA256"), start=1)}
    for argv in [child_prepare("update"), native_launch("update", "update")]:
        guarded = guarded_script(argv, test_bound)
        require(guarded.startswith("set -eu\n"), "Guard must fail closed")
        require(all(value in guarded for value in test_bound.values()), "Missing remote binding hash")
        require(guarded.count("/usr/bin/shasum -a 256 -c -") == 4, "Missing remote hash checks")
        require(all(command in guarded for command in ("/usr/bin/id -ru", "/usr/bin/id -u", "/usr/bin/stat -f %u /dev/console")), "Missing UID checks")
        require(shlex.split(guarded.splitlines()[-1]) == argv, "Guarded argv quote roundtrip")
    with tempfile.TemporaryDirectory(prefix="pat2602-host-self-check-") as temporary:
        directory = Path(temporary)
        command = [sys.executable, "-c", "import sys; print('raw-line'); sys.stderr.write('raw-error\\n'); sys.exit(7)"]
        result = capture(directory, "local-check", command, {"operation": "self-check"})
        require(result["exitCode"] == 7, "Actual local status lost")
        require((directory / "local-check.stdout").read_bytes() == b"raw-line\n", "Raw stdout changed")
        require(result["stdoutSHA256"] == sha((directory / "local-check.stdout").read_bytes()), "Stdout receipt hash differs")
        require(result["stderrSHA256"] == sha((directory / "local-check.stderr").read_bytes()), "Stderr receipt hash differs")
        require(json.loads((directory / "local-check-receipt.json").read_bytes()) == result, "Actual receipt differs")
        before = {p.name: p.read_bytes() for p in directory.iterdir()}
        try:
            capture(directory, "local-check", command, {"operation": "self-check"})
        except FileExistsError:
            pass
        else:
            raise AssertionError("Clobber accepted")
        require(before == {p.name: p.read_bytes() for p in directory.iterdir()}, "Clobber changed evidence")
    print("PASS local self-check: 13 roots/16 native pairs; argv quoting; invalid-pair refusal; four remote binding guards/UID checks; raw capture/status; exclusive no-clobber. No SSH invoked.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-check", action="store_true")
    sub = parser.add_subparsers(dest="operation")
    for name in ("preflight", "prepare", "native"):
        item = sub.add_parser(name)
        item.add_argument("--label", required=True)
        if name != "preflight":
            item.add_argument("--case-root", required=True, choices=sorted(PAIRS))
        if name == "native":
            item.add_argument("--action", required=True, choices=sorted({a for values in PAIRS.values() for a in values}))
    args = parser.parse_args()
    if args.self_check:
        require(args.operation is None, "Self-check cannot accompany a guest operation")
        self_check(); return 0
    require(args.operation is not None, "Explicit operation required")
    bound = bindings()  # Missing newly retained receipts/tools refuses BEFORE SSH.
    if args.operation == "preflight":
        script = preflight_script()
    else:
        argv = child_prepare(args.case_root) if args.operation == "prepare" else native_launch(args.case_root, args.action)
        script = guarded_script(argv, bound)
    result = capture(EVIDENCE, args.label, ssh_argv(script), {"operation": args.operation, "bindings": bound})
    if result is None:
        return 130
    print(json.dumps(result, sort_keys=True))
    return 0 if result["exitCode"] == 0 else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, json.JSONDecodeError) as error:
        print("Host helper refused: " + str(error), file=sys.stderr)
        sys.exit(2)
