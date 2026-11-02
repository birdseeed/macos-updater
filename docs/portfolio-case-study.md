# macOS Updater case study

## The idea

I wanted an updater for ordinary Mac users that did the work itself, had a clear native interface and did not expect anyone to learn a package manager. It would find what was installed, match it against a curated catalogue, download the update, check the download thoroughly, and then install it, refusing cleanly or recovering if anything went wrong. This was the original idea behind the Patched name, and I came back to it on 6 October 2026 after retiring the Endpoint Assurance service, with a small budget set aside to prove the core of it.

## Architecture

The Swift package keeps artifact inspection, catalogue trust, transaction state, the interface and the native macOS adapters in separate modules. The SwiftUI app only shows what it has observed locally and acts on explicit user requests; it never treats an app's name, its icon or a passing inspection as permission to install anything.

Trust is checked in layers, because each layer answers a different question. The catalogue signature says the catalogue is genuine, the checksum says these are exactly the bytes the catalogue described, the bundle identity says it is the app we expected, and the macOS signature and notarisation checks say Apple is happy with it. A valid catalogue record never substitutes for inspecting the actual file, and any path that lacks the evidence it needs refuses to act.

The licensing service was written in TypeScript for Cloudflare Workers and D1, separately from the app, and existing Homebrew users could optionally keep managing individual apps that way without it being required.

## Three pieces of code worth reading

**Catalogue verification.** [CatalogueVerifier.swift](../Sources/PatchedCore/CatalogueVerifier.swift) and [StrictJSON.swift](../Sources/PatchedCore/StrictJSON.swift), with [the core checks](../Tests/PatchedCoreChecks), cover exact payload handling, Ed25519 signature verification, field limits and replay protection. The [fixture notes](../Fixtures/Catalogue/README.md) explain why the test keys carry no real trust.

**Transactions and recovery.** [UpdateTransaction.swift](../Sources/PatchedCore/UpdateTransaction.swift) and [TransactionJournal.swift](../Sources/PatchedCore/TransactionJournal.swift), journal every step of an update so an interrupted one can be picked up safely. The tests inject interruptions and process restarts, working inside a disposable folder rather than on real applications.

**An interface that does not overclaim.** [PatchedApp](../Sources/PatchedApp) treats installed apps and their icons as observations rather than confirmed catalogue matches, and leaves the update count at zero until a match is verified.

## What testing found

On 7 October I downloaded two official Firefox releases and ran them through the inspector. The checksums matched the published lists, the bundle and signing identities were as expected, both were universal binaries, and the apps inside were validly signed and notarised. Both DMG containers, however, were unsigned and failed their own checks. The inspector recorded the container and the app as separate results, which is exactly the distinction an updater needs to make, and nothing was installed or launched during that inspection.

Across the components, the dated test records show 179 artifact cases, 236 catalogue cases plus 13 regressions, 260 transaction cases, 51 interface cases and 19 operator session cases, with source CI green on 27 October.

## How I worked

I was the only engineer and owned the requirements, architecture, security boundaries and user experience, and decided what was accepted. The code was written with AI assistance, with each piece of work tracked as a ticket, reviewed for correctness and security by a second model, and checked locally and in CI before it was closed.

## Why it stopped

When I stopped on 1 November 2026, the app could discover and inspect installed applications but did not yet update them, no apps had been marked ready in the catalogue, and catalogue matching, update coordination, scheduled checks and live licensing were unfinished.

Over the months I worked on Patched the macOS updater market had become much more crowded, including at least two open source alternatives, and some earlier commercial competitors had been acquired and then released as open source. I could no longer see a lasting advantage, because the core features could be reproduced fairly easily. The economics did not work either, as Mac users tend to expect a one off lifetime licence, which is hard to square with the ongoing cost of curating a catalogue and maintaining the product. So I stopped rather than keep putting time into it.

## About this snapshot

This repository is a snapshot of the original with a fresh history. Old GitHub Actions workflows are kept in `ci-archive` so they do not run, and some older docs still refer to the original layout. Installomator material is included under its [Apache 2.0 licence](../ThirdParty/Installomator/LICENSE) and is not my original work.
