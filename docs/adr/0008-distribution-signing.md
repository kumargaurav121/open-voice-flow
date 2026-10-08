# 8. Distribution and signing

Status: Accepted · 2026-10-08

## Context
TCC grants are tied to the signing identity; ad-hoc rebuilds lose them. Notarization requires the paid Apple Developer Program, regardless of language/framework.

## Decision
Now: build from source, sign with a free Apple ID Personal Team (Apple Development cert), fixed bundle ID. Team testing: self-build or "Open Anyway"/`xattr` instructions. Public release: buy the $99/yr membership, Developer ID + notarization, Sparkle, Homebrew cask.

## Consequences
Zero cost until public launch; teammates face some friction in the meantime.
