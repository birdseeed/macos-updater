# Activity synthetic fixture

`events.json` is an independently specified canonical UTF8 record with one failed
manual-individual observation, revision 1, principal fixture-owner-A. It is inert.
No newline is part of its canonical bytes. It grants no native proof or authority.

Canonical wire: JSON sorted keys, without escaped slashes, no whitespace;
absent optional values are omitted. Fields and enum values are closed. UUIDs
are uppercase canonical 36-character form. UInt64 fields use unsigned integral
JSON tokens; no booleans, fractions, exponent notation, overflow or coercion.
Identity strings are 1...256 UTF8 bytes with no NUL/control characters. Optional
version/build text is 1...128 UTF8 bytes with no NUL/control characters and stays
literal. At most 2000 events and 2 MiB canonical bytes. Duplicate JSON fields,
unknown fields, null optionals and noncanonical encodings refuse. Re-encoding
must equal the exact input bytes. Principal/store binding is checked on decode.

The test-owned OwnedStore stores a private base64 wrapper below an exclusive
0700 `.build/patched-activity-fixture-*` directory and a 0600 single-link regular
record. Checks independently inspect persisted bytes. This wrapper is not the
product wire, an authenticated native store, or evidence of an app relaunch.
Offscreen PNGs remain in these owned directories for parent inspection. No
fixtures are opened in PatchedApp and no installed target/helper is launched.
