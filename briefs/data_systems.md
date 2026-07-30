<!-- Source: condensed from briefs/database_overviews.md (itself transcribed verbatim from the project's
     Google Doc, "2026 Clean Air Act Project" -- Data Downloads Overview tab, pulled 2026-07-20). No
     numbers here are computed from data/raw; the raw-data summary tables (docs/raw_data.html) are the
     script-generated numeric source for counts. -->

# The Data Systems: ICIS-Air, AFS, and the Compliance Pipeline

This project draws on four EPA data systems that were never designed to be used together. Each has its own
facility key, its own coverage window, and its own idea of what a "record" is — see
[Facility Identifiers and Crosswalks](#facility-identifiers-and-crosswalks) for how they join.

## ICIS-Air — the current system

EPA's current compliance and enforcement database for stationary sources, in production since October
2014. Ten linked files, all keyed on `PGM_SYS_ID`: a facilities table (location, industry codes, emissions
classification), program and program-subpart assignments, a pollutants table, compliance-monitoring
records (Full and Partial Compliance Evaluations), stack tests, Title V certifications, and two enforcement
tables split by seriousness — Formal Actions (consent agreements, administrative orders, judicial actions,
with legal force) and Informal Actions (notices of violation, warning letters, phone calls, which often
precede a formal action). A separate violation-history table tracks High Priority Violations (HPVs) and
Federally Reportable Violations (FRVs) from discovery through resolution. What ICIS-Air does *not* carry:
emissions quantities — it tracks which pollutants a facility is associated with, not how much it emitted.

## AFS — the legacy system

The Air Facility System (AFS) is ICIS-Air's predecessor, replaced and frozen as of October 2014. ICIS-Air
back-loaded migrated AFS history, so pre-2014 ICIS-Air records themselves originate in AFS — but AFS also
survives as its own standalone frozen tables, keyed on `AFS_ID`: facility identification, an actions table
(inspections, enforcement, stack tests, and Title V reviews rolled up to the plant level), quarterly
historical compliance status by air program (beginning FY2007), and HPV history. That quarterly
compliance-status table is the one thing AFS offers that ICIS-Air does not — ICIS-Air's own Programs table
is a current snapshot, so AFS is the only source for tracking a facility's compliance status changing over
time before 2015.

## The combined Emissions dataset

Not a single EPA system but a facility-level combination of four separately reported programs, joined to
ICIS-Air via `REGISTRY_ID`: NEI (the broadest inventory, covering criteria pollutants and HAPs, but
triennial and estimate-based rather than measured), GHGRP (large emitters only, 25,000+ metric tons
CO2e/year, annual, self-reported, greenhouse gases only), TRI (facilities in specific industries with 10+
employees handling any of roughly 770 listed toxic chemicals above threshold quantities, annual, reported
under a different statute than the CAA), and CAMD (only electric generating units in the cap-and-trade
programs, annual, SO2/NOx directly measured by continuous emission monitors — the smallest universe but the
highest measurement quality). Reporting frequency and coverage differ by program, so a facility can appear
in one without appearing in another for the same year.

## The CAA Compliance Pipeline

A pre-joined, derived view — not an independent data source — linking each violation to the compliance
evaluation that triggered it and the enforcement action that resolved it, one row per
evaluation × violation × enforcement-action combination. It shares `REGISTRY_ID` with ICIS-Air but does not
carry facility characteristics (industry codes, classification) or emissions data of its own.

> **Data implication.** ICIS-Air is this project's primary source for anything current (2015 onward); AFS
> is used only for what ICIS-Air cannot provide before that date (quarterly historical compliance status).
> The Compliance Pipeline is a convenience join, not a substitute for the underlying ICIS-Air evaluation,
> violation, and enforcement tables — use it for tracing one enforcement pathway, not for facility-level
> counts, which should come from the underlying tables directly.
