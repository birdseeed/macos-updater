# Explicit local application observation

PAT-2704 adds `LocalApplicationInventory` to the existing client library. Only an
explicit `scan()` reads the filesystem. The ordinary actor scans `/Applications`
and the effective user's account-database home plus `/Applications`; it does not
use environment `HOME`. The latter root must belong to that effective user. The
Testing SPI substitutes fixture roots and labels the result `.fixture`, while
using the same traversal and metadata code.

The scanner keeps directory descriptors and their ancestor namespace bindings,
refuses symlinks at every boundary, and reads only regular `Contents/Info.plist`
files with no-follow, nonblocking descriptors. It compares captured identities,
permissions, ownership, size and change times before and after reads and parsing.
The SPI read observer runs after bundle, Contents and plist capture and cannot
supply observation data. A detected race clears metadata claims and makes the
result incomplete. This is a bounded observation over time, not an atomic
filesystem snapshot or durable authority to act on an app.

Rows retain separate physical copies in UTF-8 byte order, even with duplicate
bundle identifiers. XML/binary plist names and versions are untrusted claims.
Missing, invalid or refused metadata does not erase a safely opened app row.
Publisher, product, edition, channel, architecture, running state, Homebrew
ownership, catalogue matching and update eligibility remain unknown;
`installationAllowed` is always false. Session UUID, generation and observed
timestamps identify immutable results; generation exhaustion refuses another scan.

Fixed bounds are 512 applications, 8192 directory entries including ordinary
files and hidden names, depth four below each root, 1 MiB per plist, 16 MiB of
aggregate reserved metadata reads, 512 issues, 1024 UTF-8 bytes per displayed
field and 4096 bytes per path. Hidden directories and app contents are never
recursively traversed. Invalid UTF-8 names, path traversal, controls and oversized
paths refuse without ambiguous replacement decoding. Limits and refusals make
results incomplete; issue overflow replaces the final slot with `issueLimit`.
Missing roots have an explicit `absent` status. Permission or identity failures
cannot become successful empty scans.

At the original PAT-2704 source stage, the app did not compose this scanner.
The later ordinary [native shell composition](native-shell-composition.md) now
retains the scanner through `LocalApplicationsController` and shares observations
between Applications, Updates and the menu. Bounded installed-icon observations
are described in [client flow](client-flow.md#installed-icon-observation-pat-2660-remaining-integration).
These are real local reads, distinct from verified release matching: availability
remains unknown, ready count zero and installation authority false. No productive
update dispatcher or consumer transaction follows from this integration.

CHECK-MODIFIED: the historical client-composition check had inspected every file
in `PatchedClient` for its earlier local-DMG-only boundary. PAT-2704 narrows that
check's source collection to the original `ClientController.swift` and
`ClientView.swift`, preserving its assertions and forbidden list. New scanner
checks independently cover its source boundaries and physical filesystem
behaviour. DTOs and acceptance cases were frozen after parent-observed meaningful
red and before this implementation. Verification, independent review and
publication remain parent-owned gates; this document claims no passing result.

## PAT-2705 interim Applications access

The reusable `LocalApplicationsController` now owns one ordinary scanner and
publishes its immutable observations only after explicit Scan or Scan again.
It allows one scan at a time, retaining the previous observation with a visible
scanning status during refresh. Its Testing SPI accepts only a concrete scanner;
fixture results are visibly labelled. Opening or painting `LocalApplicationsView`
does not scan. The view shows literal, unverified names/version/build claims,
separate physical locations, observation completion time, root statuses and
bounded explanations in a scrolling area. Missing metadata remains unavailable;
absent or refused roots never become successful empty-folder claims. Update
availability has not been checked.

Historical PAT-2705 integration stage (superseded by the native shell above): the existing client retains the Applications controller and exposes an
explicit Applications button and sheet, with Done/Escape closure. The original
disk-image inspector controls remain available. This sheet is interim access,
not completion of the approved native shell or its final navigation. The app's
scene composition remains unchanged. No installation, update, account, catalogue,
network, scheduling or app-launch authority is added. Parent verification,
offscreen visual inspection and independent review remain required; source and
rendering checks do not establish a native app launch or installed beta proof.
