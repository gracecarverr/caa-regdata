<!-- Source: condensed from the pollutant-record fields already documented in briefs/database_overviews.md
     (ICIS-AIR_POLLUTANTS.csv, AFS AIR_PROGRAM.csv) and the classification-code note already in
     briefs/institutional_overview.md's "Facility Classification" section -- cross-references rather than
     restates content that already has its own brief. No numbers here are computed from data/raw; for a
     current count of facilities by classification, see docs/raw_data.html. -->

# Pollutants and Source Classification

CAA regulation runs on two pollutant vocabularies at once — NAAQS's criteria pollutants (see
[NAAQS](#naaqs)) and Section 112's hazardous air pollutants (see
[Stationary Source Programs](#stationary-source-programs)) — and the data records both the same way: as a
row in a pollutant-level table, not as a fact about a facility as a whole.

## The pollutant record

`ICIS-AIR_POLLUTANTS.csv` holds one row per facility × pollutant combination: a numeric pollutant code and
name, a Substance Registry Services (SRS) ID, a Chemical Abstract Service (CAS) number, and a
pollutant-specific classification code. A facility regulated for several pollutants appears once per
pollutant, not once overall — a facility-level count and a pollutant-record count are different things.
AFS's `AIR_PROGRAM.csv` carries the equivalent fields (pollutant code, CAS number, pollutant-level
classification) at the plant-program level.

## Two classification codes, two scopes

`AIR_POLLUTANT_CLASSIFICATION_CODE` appears in both the Facilities table and the Pollutants table, and it
means something different in each: in Facilities, it's the facility-level "worst case" across every
pollutant and program the facility is subject to (see
[Facility Classification](#facility-classification) for what major / synthetic minor / minor mean); in
Pollutants, the same field name is the classification for *that one pollutant specifically*. The two do not
have to agree — a facility can be facility-level major on the strength of one pollutant while most of its
individual pollutant records read minor.

## Not every emissions program covers the same pollutants

The four programs behind this project's combined Emissions dataset (see
[The Data Systems](#the-data-systems-icis-air-afs-and-the-compliance-pipeline)) don't share a pollutant
scope: NEI covers criteria pollutants and HAPs broadly, GHGRP covers only greenhouse gases, TRI covers a
fixed list of roughly 770 listed toxic chemicals under a different statute than the CAA, and CAMD covers
only SO2 and NOx from electric generating units. A pollutant present in one program's records for a
facility-year has no guarantee of appearing in another's.

> **Data implication.** Don't read a pollutant-record count, or a facility's absence from one emissions
> program, as a statement about what the facility actually emits — it may reflect which program's scope the
> pollutant falls under, not the facility's activity.
