<!-- Source: facility-identifier definitions and crosswalk mechanics condensed from briefs/database_overviews.md
     (itself transcribed verbatim from the project's Google Doc, "2026 Clean Air Act Project," pulled
     2026-07-20). AFS↔FRS coverage figures live in briefs/datasets/afs_crosswalk_feasibility.md and are
     deliberately NOT restated here -- that brief is explicit that a single national percentage is
     misleading (coverage swings from under 1% to 100% by state), so this brief links out to it instead of
     picking one number. -->

# Facility Identifiers and Crosswalks

A single physical facility can carry several different ID numbers, one per data system, because each
system was built independently and at a different time. Joining across systems means picking the right key
for the join, not assuming any one ID is universal.

## PGM_SYS_ID — the ICIS-Air key

`PGM_SYS_ID` is the spine of ICIS-Air: it uniquely identifies every regulated facility and can be used to
join any of the 10 ICIS-Air files to one another. It identifies a *regulated facility*, not necessarily a
*physical site* — ownership changes and permit restructuring can leave one physical site carrying more than
one `PGM_SYS_ID` over time.

## AFS_ID — the legacy key

`AFS_ID` plays the same spine role inside the retired Air Facility System (AFS), frozen as of October 2014.
`AFS_ID` and `PGM_SYS_ID` are different numbering schemes from different eras — neither dataset maps one
directly to the other. The only path between them runs through `REGISTRY_ID`, below.

## REGISTRY_ID — the cross-system key

`REGISTRY_ID` is the Facility Registry Service (FRS) ID, and it is the one key meant to identify a
*physical site* rather than a program-specific record. EPA's FRS Program Links file maps each
program-system ID — `AFS_ID`, an NPDES permit number, other cross-program identifiers — to a shared
`REGISTRY_ID`. Every non-ICIS-Air asset this project uses (the combined Emissions dataset, the CAA
Compliance Pipeline) joins to ICIS-Air through `REGISTRY_ID`, not `PGM_SYS_ID`.

Because `REGISTRY_ID` targets the physical site while `PGM_SYS_ID` targets the regulated-facility record,
the two can disagree in either direction: several `PGM_SYS_ID`s can point to one `REGISTRY_ID` (one site,
several permits over time), and "facility" is therefore ambiguous on its own — a distinct-facility count
differs depending on which ID you count by.

> **Data implication.** Any cross-system join in this project (ICIS-Air ↔ Emissions, ICIS-Air ↔ Pipeline)
> uses `REGISTRY_ID`. The AFS↔FRS crosswalk that would let a pre-2015 AFS record reach a modern
> `REGISTRY_ID` is incomplete, and its coverage varies by state far more than it varies around any national
> average. This project treats that crosswalk as an open, unresolved decision rather than a settled join —
> see
> [`afs_crosswalk_feasibility.md`](https://github.com/gracecarverr/caa-regdata/blob/main/briefs/datasets/afs_crosswalk_feasibility.md)
> for the current coverage figures and the state-by-state breakdown, rather than a single number here.
