# Packaging Plan

## Goal

Distribute the oncoanalyser offline bundle through GitHub-only infrastructure, using a small bootstrap repository plus multiple payload repositories reachable through raw GitHub URLs.

## Size facts

- Normal GitHub repo files: warning above 50 MiB, blocked above 100 MiB.
- Recommended repo size: under 1 GiB, ideally under 5 GiB.

## Current bundle estimate

From the existing packed-up workspace, the non-sample-data payload is dominated by:

- `singularity_cache`: about 26 GiB
- `ref_cache`: about 55 GiB
- `ref_cache_extracted`: about 66 GiB
- `.nextflow`: about 88 MiB

That is roughly 147 GiB before any additional overhead.

## Implications

- With raw GitHub repo files at 50 MiB shards, the payload needs about 3000 parts.

## Recommended split

1. Bootstrap repo
   - scripts
   - manifest files
   - restore logic
2. Runtime repo
   - small runtime archive
   - `.nextflow` if desired
3. Singularity repo
   - container cache shards
4. Reference repo
   - `ref_cache` shards
5. Reference-extracted repo (optional)
   - `ref_cache_extracted` shards

## Restore model

The controlled environment downloads a manifest from the bootstrap repo, reads the per-artifact base URLs, downloads all parts, verifies SHA256, reassembles the tarballs, and extracts them to the local filesystem.

## Practical recommendation

Use normal repos only, keep shards <= 50 MiB, and distribute large payloads across multiple repositories. Skip `ref_cache_extracted` unless you need reproducible stub-only pre-extracted references.
