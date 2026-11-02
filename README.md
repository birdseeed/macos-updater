# Patched macOS Updater

Patched was a native Swift app for keeping a Mac's third party applications up to date, aimed at individuals and households rather than IT departments. The idea was that it would find what you had installed, compare it with a curated catalogue, download the new version, check that the download really was the signed and notarised app it claimed to be, and then install it, without anyone needing to learn Homebrew. It was the original idea behind Patched, and I came back to it in October 2026 after retiring the [Endpoint Assurance](https://github.com/birdseeed/endpoint-assurance) platform. I stopped development on 1 November 2026 and have published the source here as a portfolio piece.

## What got built

The project is a Swift package with a SwiftUI app on top, kept in separate modules so that trust decisions never depended on the interface:

| Area | What it does | Where to look |
| --- | --- | --- |
| Catalogue trust | Verifies a signed catalogue with a strict JSON parser and replay protection, so a catalogue entry only ever authorises the exact bytes it describes | [CatalogueVerifier.swift](Sources/PatchedCore/CatalogueVerifier.swift), [StrictJSON.swift](Sources/PatchedCore/StrictJSON.swift), [core checks](Tests/PatchedCoreChecks) |
| Artifact inspection | Checks a downloaded app's checksum, bundle identity, code signature, notarisation and architectures before it is trusted | [Sources/PatchedCore](Sources/PatchedCore) |
| Transactions and recovery | Journals every update step so an interrupted update can be picked up and recovered safely | [UpdateTransaction.swift](Sources/PatchedCore/UpdateTransaction.swift), [TransactionJournal.swift](Sources/PatchedCore/TransactionJournal.swift) |
| The app | SwiftUI shell with installed app discovery, preferences, network settings, local history and a menu bar entry | [Sources/PatchedApp](Sources/PatchedApp) |
| Services | A licensing service in TypeScript on Cloudflare Workers and D1, and catalogue service prototypes | [service/licensing](service/licensing), [services/catalogue](services/catalogue) |

The rule I held to throughout was that a signed catalogue record is never a substitute for inspecting the actual file. When I tested it against two official Firefox releases, the apps inside passed their signature and notarisation checks while both DMG containers turned out to be unsigned, and the code records those as separate results rather than letting one stand in for the other.

The code was written with AI assistance, while I owned the product, the architecture, the security boundaries and every acceptance decision. The [case study](docs/portfolio-case-study.md) goes through the design, three implementation examples worth reading and what testing actually established.

## Where it stopped

When I stopped, the app could see and inspect what was installed but did not yet update anything on its own, and no apps had been added to the catalogue as ready to update. Catalogue matching, update coordination and scheduled checks were still unfinished.

I stopped because the macOS updater market had become crowded, including at least two open source alternatives, and I could not see a lasting advantage for Patched. The Mac community's preference for one off lifetime licences also did not fit the ongoing cost of curating a catalogue, so further time no longer looked justified.

## Status and limitations

This is a snapshot of the original repository with a fresh Git history. Historical test results are recorded with their dates and scope in the case study, but nothing here has been rebuilt as a whole, so do not run its install, update or scheduling scripts. See [SECURITY.md](SECURITY.md) for the security scope.

## Licence

Copyright 2026 Patched.im Ltd. All rights reserved. The source is published so it can be read and reviewed; no licence to reuse it is granted. Third party material keeps its own terms, including Installomator under [Apache 2.0](ThirdParty/Installomator/LICENSE), and these are listed in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
