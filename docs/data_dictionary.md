# CAA Regulatory Data — Data Dictionary

Field-level documentation for every raw source in this repository, verified against EPA's official
published data dictionaries. Each entry lists the source CSV, a one-line description, and every field
with its type/length (where EPA publishes them) and definition.

**Sources (EPA ECHO data downloads):**

- ICIS-Air — <https://echo.epa.gov/tools/data-downloads/icis-air-download-summary>
- Air Emissions — <https://echo.epa.gov/tools/data-downloads/air-emissions-download-summary>
- CAA Compliance Pipeline — <https://echo.epa.gov/tools/data-downloads/caa-pipeline-download-summary>
- AFS (Air Facility System, pre-2014) — *AFS Data Element Dictionary* PDF, dated **February 2015**,
  <https://echo.epa.gov/system/files/AFS_Data_Download.pdf>

Web summaries retrieved 2026-07-17. See the download index at <https://echo.epa.gov/tools/data-downloads/>.

> **Conventions.** Text in "quotation marks" is quoted **verbatim** from EPA's published dictionary for
> that field. A **data:** note marks a fact verified directly against the file as downloaded in this repo
> (`data/raw/…`). Field names, order, types, and lengths were checked against the actual CSV headers in
> this repo and against EPA's published tables; where the two diverge it is noted inline.

> **Provenance note:** this file was ported from the predecessor CAA_Project, then re-verified against the
> EPA sources above. The original generator script and source PDFs are **not yet ported into this repo** —
> until they are, treat this dictionary as a maintained-by-hand reference. Per-asset counts and
> institutional caveats live in `data/processed/README.md`.

---

## ICIS-Air

Raw files in `data/raw/ICIS-AIR_downloads/`. All join on `PGM_SYS_ID`.

### `ICIS-AIR_FACILITIES.csv`

Facility and source-level identification data for air pollution sources.

| Field | Type | Len | Description |
|---|---|---|---|
| `PGM_SYS_ID` | Char | 30 | "An alphanumeric program system identifier of varying length which uniquely identifies each air source" |
| `REGISTRY_ID` | Char | 12 | Facility Registry Service (FRS) ID linking regulatory records |
| `FACILITY_NAME` | Char | 80 | "Official or legal name of the plant" |
| `STREET_ADDRESS` | Char | 35 | "First line of the street address or other specific identifier" |
| `CITY` | Char | 60 | City where plant is physically located |
| `COUNTY_NAME` | Char | 100 | County where plant is physically located |
| `STATE` | Char | 2 | "Two-character postal abbreviation code to identify the state" |
| `ZIP_CODE` | Char | 14 | Five- or nine-digit zip code |
| `EPA_REGION` | Char | 2 | EPA Regional office code (01–10) |
| `SIC_CODES` | Char | 4000 | "Four-character Standard Industrial Classification code" (may hold several) |
| `NAICS_CODES` | Char | 4000 | "North American Industry Classification System code" (may hold several) |
| `FACILITY_TYPE_CODE` | Char | 3 | Government or private facility type code (COR, FDF, STF, …) |
| `AIR_POLLUTANT_CLASS_CODE` | Char | 3 | Source emissions classification (MAJ/SMI/MIN/UNK/OTH/NAP) |
| `AIR_POLLUTANT_CLASS_DESC` | Char | 100 | Description of pollutant classification |
| `AIR_OPERATING_STATUS_CODE` | Char | 5 | Operational condition code. **data:** the 6 values OPR/CLS/TMP/PLN/CNS/SEA appear |
| `AIR_OPERATING_STATUS_DESC` | Char | 100 | Description of operating status |
| `CURRENT_HPV` | Char | 80 | High Priority Violator status and enforcement information |
| `LOCAL_CONTROL_REGION_CODE` | Char | 3 | Local Control Region code with jurisdiction |
| `LOCAL_CONTROL_REGION_NAME` | Char | 100 | Local Control Region name |

> **Field-name note.** The repo's `ICIS-AIR_FACILITIES.csv` uses `LOCAL_CONTROL_REGION_CODE` /
> `LOCAL_CONTROL_REGION_NAME` (verified against the CSV header). EPA's *current* web summary now lists these
> as `AIR_LOCAL_CONTROL_REGION_CODE` / `AIR_LOCAL_CONTROL_REGION_NAME` — a newer schema than the download in
> this repo. The un-prefixed names above are authoritative for the files here.

### `ICIS-AIR_PROGRAMS.csv`

Air regulatory programs applicable to facilities.

| Field | Type | Len | Description |
|---|---|---|---|
| `PGM_SYS_ID` | Char | 30 | Program system identifier linking to facilities |
| `PROGRAM_CODE` | Char | 9 | "Nine-character code used to identify the regulatory air program" |
| `PROGRAM_DESC` | Char | 100 | Description of the air program |
| `AIR_OPERATING_STATUS_CODE` | Char | 5 | Operational condition for the air program |
| `AIR_OPERATING_STATUS_DESC` | Char | 100 | Description of program operating status |
| `BEGIN_DATE` | Date |  | "Date that data were entered in the program system" |
| `UPDATED_DATE` | Date |  | "Date the corresponding information was last updated" |

### `ICIS-AIR_PROGRAM_SUBPARTS.csv`

Air program subparts detailing specific regulatory requirements.

| Field | Type | Len | Description |
|---|---|---|---|
| `PGM_SYS_ID` | Char | 30 | Program system identifier |
| `PROGRAM_CODE` | Char | 9 | Air program code |
| `PROGRAM_DESC` | Char | 100 | Program description |
| `AIR_PROGRAM_SUBPART_CODE` | Char | 20 | "Field indicating applicable air program subparts" |
| `AIR_PROGRAM_SUBPART_DESC` | Char | 200 | Description of the subpart |

### `ICIS-AIR_POLLUTANTS.csv`

Pollutants tracked at the air program level.

| Field | Type | Len | Description |
|---|---|---|---|
| `PGM_SYS_ID` | Char | 30 | Program system identifier |
| `POLLUTANT_CODE` | Num |  | "Numeric code that identifies a pollutant tracked at the air program level" |
| `POLLUTANT_DESC` | Char | 2000 | Pollutant description |
| `SRS_ID` | Char | 9 | "Substance Registry Services ID of the pollutant" |
| `CHEMICAL_ABSTRACT_SERVICE_NMBR` | Char | 9 | "Chemical abstract service number (CAS) for the pollutant" |
| `AIR_POLLUTANT_CLASS_CODE` | Char | 3 | Pollutant emissions classification |
| `AIR_POLLUTANT_CLASS_DESC` | Char | 100 | Emissions classification description |

### `ICIS-AIR_FCES_PCES.csv`

Full Compliance Evaluations (FCEs) and Partial Compliance Evaluations (PCEs).

| Field | Type | Len | Description |
|---|---|---|---|
| `PGM_SYS_ID` | Char | 30 | Program system identifier |
| `ACTIVITY_ID` | Num |  | "Unique identifier for an activity performed at or related to a particular site" |
| `STATE_EPA_FLAG` | Char | 1 | Agency in charge (E = EPA, S = State, L = Local) |
| `ACTIVITY_TYPE_CODE` | Char | 3 | Activity type code; value is INS (inspection) in this table |
| `ACTIVITY_TYPE_DESC` | Char | 100 | Description of activity type |
| `COMP_MONITOR_TYPE_CODE` | Char | 3 | Compliance monitoring type (FCE: FOO/FFO; PCE: PCE/PFF/PFR/POC/POF/POI/POM/POR/POV) |
| `COMP_MONITOR_TYPE_DESC` | Char | 100 | Compliance monitoring type description |
| `ACTUAL_END_DATE` | Date | 10 | "Calendar date of the listed inspection (MM/DD/YYYY)" |
| `PROGRAM_CODES` | Char | 4000 | Applicable regulatory program codes |
| `ACTIVITY_PURPOSE_DESC` | Char | 100 | "Description of the purpose of the compliance evaluation" |

### `ICIS-AIR_STACK_TESTS.csv`

Stack test results and compliance monitoring data.

| Field | Type | Len | Description |
|---|---|---|---|
| `PGM_SYS_ID` | Char | 30 | Program system identifier |
| `ACTIVITY_ID` | Num |  | Activity identifier |
| `COMP_MONITOR_TYPE_CODE` | Char | 3 | Compliance monitoring type (value is CST in this table) |
| `COMP_MONITOR_TYPE_DESC` | Char | 100 | Monitoring type description |
| `STATE_EPA_FLAG` | Char | 1 | Responsible agency (E/S/L) |
| `ACTUAL_END_DATE` | Date | 7 | Test completion date |
| `POLLUTANT_CODES` | Char | 4000 | Numeric pollutant codes tested |
| `POLLUTANT_DESCS` | Char | 4000 | Descriptions of tested pollutants |
| `AIR_STACK_TEST_STATUS_CODE` | Char | 3 | Stack test result. **data:** FAI/PSS/PEN/INC/NA observed |
| `AIR_STACK_TEST_STATUS_DESC` | Char | 100 | Stack test status description |

### `ICIS-AIR_TITLEV_CERTS.csv`

Title V operating permit annual compliance certifications.

| Field | Type | Len | Description |
|---|---|---|---|
| `PGM_SYS_ID` | Char | 30 | Program system identifier |
| `ACTIVITY_ID` | Num |  | Activity identifier |
| `COMP_MONITOR_TYPE_CODE` | Char | 3 | Compliance monitoring type code |
| `COMP_MONITOR_TYPE_DESC` | Char | 100 | Monitoring type description |
| `STATE_EPA_FLAG` | Char | 1 | Responsible agency (E/S/L) |
| `ACTUAL_END_DATE` | Date | 7 | Certification date |
| `FACILITY_RPT_DEVIATION_FLAG` | Char | 1 | "Flag indicating whether the facility reported any deviations during Title V" |

### `ICIS-AIR_FORMAL_ACTIONS.csv`

Formal enforcement actions and penalties.

| Field | Type | Len | Description |
|---|---|---|---|
| `PGM_SYS_ID` | Char | 30 | Program system identifier |
| `ACTIVITY_ID` | Num |  | Activity identifier |
| `ENF_IDENTIFIER` | Char | 25 | "Number used to uniquely identify multiple occurrences of an enforcement action" |
| `ACTIVITY_TYPE_CODE` | Char | 3 | Civil enforcement activity type (AFR = Administrative Formal, JDC = Judicial) |
| `ACTIVITY_TYPE_DESC` | Char | 100 | Activity type description |
| `STATE_EPA_FLAG` | Char | 1 | Responsible agency (E/S/L) |
| `ENF_TYPE_CODE` | Char | 7 | "Code that identifies the type of action being taken" |
| `ENF_TYPE_DESC` | Char | 100 | Enforcement type description |
| `SETTLEMENT_ENTERED_DATE` | Date | 7 | "Date the settlement is signed and entered by the Clerk of the Court" |
| `PENALTY_AMOUNT` | Num |  | "Amount of the civil penalty assessed or agreed to by a facility" |

### `ICIS-AIR_INFORMAL_ACTIONS.csv`

Informal enforcement actions and compliance orders.

| Field | Type | Len | Description |
|---|---|---|---|
| `PGM_SYS_ID` | Char | 30 | Program system identifier |
| `ACTIVITY_ID` | Num |  | Activity identifier |
| `ENF_IDENTIFIER` | Char | 25 | Enforcement case identifier |
| `ACTIVITY_TYPE_CODE` | Char | 3 | Civil enforcement activity type (AIF = Administrative Informal) |
| `ACTIVITY_TYPE_DESC` | Char | 100 | Activity type description |
| `STATE_EPA_FLAG` | Char | 1 | Responsible agency (E/S/L) |
| `ENF_TYPE_CODE` | Char | 7 | Enforcement action type code (e.g., NOV, DAWL) |
| `ENF_TYPE_DESC` | Char | 100 | Enforcement type description |
| `ACHIEVED_DATE` | Date | 7 | "Date on which an Informal Enforcement Action is achieved" |
| `OFFICIAL_FLG` | Char | 1 | Official action flag (Y/N) |

### `ICIS-AIR_VIOLATION_HISTORY.csv`

High Priority Violations (HPVs) and Federally Reportable Violations (FRVs) case-file data.

| Field | Type | Len | Description |
|---|---|---|---|
| `PGM_SYS_ID` | Char | 30 | Program system identifier |
| `ACTIVITY_ID` | Num |  | Activity identifier |
| `AGENCY_TYPE_DESC` | Char | 100 | "Environmental agency responsible for CAA compliance and enforcement" |
| `STATE_CODE` | Char | 2 | State identifier |
| `AIR_LCON_CODE` | Char | 3 | Local Control Region code |
| `COMP_DETERMINATION_UID` | Char | 25 | "Unique identifier for the case file activity" |
| `ENF_RESPONSE_POLICY_CODE` | Char | 3 | Enforcement response policy type (HPV/FRV) |
| `PROGRAM_CODES` | Char | 4000 | Applicable program codes |
| `PROGRAM_DESCS` | Char | 4000 | Program descriptions |
| `POLLUTANT_CODES` | Char | 4000 | Associated pollutant codes |
| `POLLUTANT_DESCS` | Char | 4000 | Pollutant descriptions |
| `EARLIEST_FRV_DETERM_DATE` | Date | 7 | "Earliest determination date of a Federally Reportable Violation" |
| `HPV_DAYZERO_DATE` | Date | 7 | "Date facility entered High Priority Violator status (MM/DD/YYYY)" |
| `HPV_RESOLVED_DATE` | Date | 7 | "Date facility resolved High Priority Violator status (MM/DD/YYYY)" |
| `DSCV_PATHWAY_DATE` | Date |  | "Date the violation was discovered" |
| `NFTC_PATHWAY_DATE` | Date |  | "Date the facility was notified" |

---

## Air Emissions

Raw file in `data/raw/POLL_RPT_COMBINED_EMISSIONS.csv`. Facility-level emissions aggregates, organized by
pollutant and program. Per EPA, the dataset combines air emissions from four EPA programs: the National
Emissions Inventory (NEI), the Greenhouse Gas Reporting Program (GHGRP), the Toxics Release Inventory (TRI),
and Clean Air Markets (CAMD). Joins to the other sources on `REGISTRY_ID` (FRS) and/or `PGM_SYS_ID`.

### `POLL_RPT_COMBINED_EMISSIONS.csv`

| Field | Type | Len | Description |
|---|---|---|---|
| `REPORTING_YEAR` | Num |  | "The calendar year of the emission" (availability varies by program) |
| `REGISTRY_ID` | Varchar2 | 36 | "The Facility Registry Service (FRS) ID of the facility" |
| `PGM_SYS_ACRNM` | Varchar2 | 60 | Source emissions-program acronym (EIS / E-GGRT / TRIS / CAMDBS) |
| `PGM_SYS_ID` | Varchar2 | 90 | Program system identifier (format varies by air program) |
| `POLLUTANT_NAME` | Varchar2 | 100 | "The name of the pollutant being tracked for air emissions" |
| `ANNUAL_EMISSION` | Num |  | "The value of the pollutant emission for the facility and reporting year" |
| `UNIT_OF_MEASURE` | Varchar2 | 15 | Units of `ANNUAL_EMISSION` (pounds; MTCO2e/year for GHG data) |
| `NEI_TYPE` | Varchar2 | 10 | Pollutant classification (CAP / GHG / HAP / OTH) |
| `NEI_HAP_VOC_FLAG` | Varchar2 | 20 | "HAP-VOC" indicates the pollutant is a volatile organic compound |

**`PGM_SYS_ACRNM`** — source program:

| Code | Program |
|---|---|
| `EIS` | Emissions Inventory System (National Emissions Inventory, NEI) |
| `E-GGRT` | Greenhouse Gas Reporting Program (GHGRP) |
| `TRIS` | Toxics Release Inventory System (TRI) |
| `CAMDBS` | Clean Air Markets Division Business System (CAMD) |

**`NEI_TYPE`** — pollutant class: `CAP` criteria air pollutant · `GHG` greenhouse gas ·
`HAP` hazardous air pollutant · `OTH` other.

> **Coverage (per EPA):** reporting-year availability differs by program — CAMD and TRI from 2008, GHGRP
> from 2010, and NEI released on a triennial cycle. Verify actual year coverage in this repo against the file.

---

## AFS (Air Facility System — pre-2014)

Raw files in `data/raw/afs_downloads/`. Definitions, types, lengths, and code tables below are transcribed
from EPA's *AFS Data Element Dictionary* (February 2015). Per EPA, AFS "contains emissions, compliance, and
enforcement data on stationary sources of air pollution," and ECHO focuses on **plant-level** data (the whole
facility as one unit). Facility files join to program/action files on `AFS_ID` / `PLANT_ID`. Action data are
"rolled up" to plant level to avoid multi-counting an action entered under several air programs.

### `AFS_FACILITIES.csv`

One row per plant: identification, location, classification, operating, and compliance status.

| Field | Type | Len | Description |
|---|---|---|---|
| `PLANT_ID` | Num | 22 | Numeric plant identifier |
| `AFS_ID` | Char | 10 | Plant code (see definition below) |
| `PLANT_NAME` | Char | 45 | "The name associated with a plant at a given location" |
| `EPA_REGION` | Char | 2 | "A two-character code identifying the EPA Region in which the plant is located" (01–10) |
| `PLANT_STREET_ADDRESS` | Char | 35 | "Field that indicates the street address for the physical location of the plant" |
| `PLANT_CITY` | Char | 30 | "Field containing the name of the city or town where the plant is located" |
| `PLANT_COUNTY` | Char | 3 | "Field containing the code of the county where the plant is located" |
| `STATE` | Char | 2 | "Two-character postal abbreviation code to identify the state where the plant is located" |
| `STATE_NUMBER` | Char | 2 | "A two-digit number corresponding to the state, using the federal information processing system (FIPS) standard" |
| `ZIP_CODE` | Char | 9 | "Field that contains the five or nine-digit zip code for the plant address" |
| `PRIMARY_SIC_CODE` | Char | 4 | "The four-character Standard Industrial Classification code that classifies the main product produced or service performed at the plant" |
| `SECONDARY_SIC_CODE` | Char | 4 | Four-character SIC code for a product/service "other than the one described by the Primary SIC Code" |
| `NAICS_CODE` | Char | 6 | Primary NAICS code (NAICS "replaced the U.S. Standard Industrial Classification (SIC) system … in 1997") |
| `AFS_GOV_FACILITY_CODE` | Char | 1 | Government facility indicator (codes below) |
| `FEDERALLY_REPORTABLE` | Char | 1 | ECHO-generated Y/N (definition below) |
| `EPA_CLASSIFICATION_CODE` | Char | 2 | Emissions classification (codes below) |
| `OPERATING_STATUS` | Char | 1 | Operational condition (codes below) |
| `EPA_COMPLIANCE_STATUS` | Char | 1 | EPA compliance determination (codes below) |
| `CURRENT_HPV` | Char | 1 | Current High Priority Violator status (codes below) |
| `LOCAL_CONTROL_REGION` | Char | 2 | "A two character code identifying the Local Control Region Code with jurisdiction over a plant. Note: LCON codes have different meanings in each state" |
| `STATE_COMPLIANCE_STATUS` | Char | 1 | State agency compliance determination (same code set as `EPA_COMPLIANCE_STATUS`) |

**`AFS_ID`** — "A 10-character alphanumeric code which uniquely identifies each permitted plant. The AFSID is
composed of the Census FIPS state code, the FIPS county code and the unique AFS plant ID. Also known as SCSC
in AFS."

**`AFS_GOV_FACILITY_CODE`** — "A one-character code indicating if plant is government facility."

| Code | Description | | Code | Description |
|---|---|---|---|---|
| `0` | Privately owned/operated | | `4` | Owned/operated by municipality |
| `1` | Owned/operated by fed gov | | `5` | Owned/operated by district |
| `2` | Owned/operated by st gov | | `6` | Owned/operated by tribe |
| `3` | Owned/operated by county | | | |

**data:** all of `0`–`6` appear in this download.

**`FEDERALLY_REPORTABLE`** — "ECHO generates the Federally Reportable indicator. FEDERALLY_REPORTABLE displays
a "Y" if the facility is federally reportable and a "N" if the facility is not federally reportable. A facility
is federally reportable if it's emission classification is "major" or "synthetic minor", or it is subject to
NSPS or NESHAP requirements and it's source-level compliance status is not equal to "no applicable state
regulation" (AFS.EPA_CLASSIFICATION_CODE = A, A1, A2, SM OR (AFS.AIR_PROGRAM_CODE = 8, 9 and
AFS.EPA_COMPLIANCE_STATUS is not equal to 8))."

**`EPA_CLASSIFICATION_CODE`** — "A two-character code that categorizes a source's emission status according to
the Alabama Power Decision's definition of a Major Source, or the 1993 EPA Compliance Monitoring Branch
Classification Guidance. If there is no EPA Classification Code present, this field displays the State
Classification Code value. AFS generates a plant classification reflecting the highest emission level
classification of criteria pollutants regulated by an Air program." The same code set is used at the plant
level (`EPA_CLASSIFICATION_CODE`), pollutant level (`POLLUTANT_CLASSIFICATION`), and air-program level
(`EPA_STATE_CLASSIFICATION_CODE`).

| Code | Description |
|---|---|
| `A` | Actual or potential emissions are above the applicable major source thresholds. |
| `A1` | Actual or potential controlled emissions >100 tons/year as per Alabama Power Decision. |
| `A2` | Actual emissions <100 tons/year, but potential uncontrolled emissions >100 tons/year. |
| `B` | Potential uncontrolled emissions <100 tons/year |
| `C` | Class is unknown. |
| `E1` | Unregulated pollutant actual or potential controlled emissions >100 tons/year as per Alabama Power Decision. |
| `E2` | Unregulated pollutant actual emission <100 tons/year. |
| `ND` | Major Source thresholds are not defined. |
| `SM` | Potential emissions are below all applicable Major Source enforceable regulations or limitations. |
| `UK` | Unknown Pollutant Classification. |

> **data / interpretation note.** Observed plant-level values in this download are `{A, A1, A2, B, C, ND, SM,
> UK}` (`B` most common; `C` ≈ 5,280 rows). The unregulated-pollutant codes `E1`/`E2` **do not appear**.
> This table adopts EPA's Feb-2015 definitions, under which **`C` = "Class is unknown."** A prior draft of
> this dictionary instead defined `C` as "unregulated pollutant, actual/potential controlled emissions >100
> tons/year" (EPA's `E1` definition) and asserted "C is not Unknown." That earlier reading is superseded here:
> observed `C` values should now be read as *class unknown*. Flagged because it changes the meaning of a code
> present in the data — confirm against any downstream code that keyed on the old `C` definition.

**`OPERATING_STATUS`** — "A one-character code representing the operational condition of the plant. The
operating status for a plant is generated from the most significant operative value assigned to subordinate
Air programs (`AIR_PROGRAM_STATUS`)." Same code set as `AIR_PROGRAM_STATUS`:

| Code | Description | | Code | Description |
|---|---|---|---|---|
| `O` | Operating | | `D` | NESHAP Demolition |
| `C` | Under Construction | | `R` | NESHAP Renovation |
| `P` | Planned (Has Applied For A Construction Permit) | | `S` | NESHAP Spraying |
| `T` | Temporarily Closed | | `L` | Landfill |
| `X` | Permanently Closed | | | |
| `I` | Seasonal | | | |

**data:** observed values are `O, C, P, T, X, I`. The NESHAP/landfill statuses (`D, R, S, L`) are documented
but do not appear in this download.

**`EPA_COMPLIANCE_STATUS`** — "A one-character code reflecting EPA's determination of compliance for a facility
(or point within a facility) with regard to pollutants regulated by an Air program or by the procedural
requirements of a permit. (This corresponds to the AFS field DCS1 at the facility level, and DCA1 at the
program level. That is, it is the worst case of the EPA and State fields.)"

| Code | Description | | Code | Description |
|---|---|---|---|---|
| `0` | Unknown Compliance Status | | `A` | Unknown With Regard To Procedural Compliance |
| `1` | In Violation – No Schedule | | `B` | In Violation With Regard To Both Emissions And Procedural Compliance |
| `2` | In Compliance – Source Test | | `C` | In Compliance With Procedural Requirements |
| `3` | In Compliance – Inspection | | `D` | HPV Violation (Auto-Generated) |
| `4` | In Compliance – Certification | | `E` | FRV Violation (Auto-Generated) |
| `5` | Meeting Compliance Schedule | | `F` | HPV On Schedule (Auto-Generated) |
| `6` | In Violation – Not Meeting Schedule | | `G` | FRV On Schedule (Auto-Generated) |
| `7` | In Violation – Unknown With Regard To Schedule | | `H` | In Compliance (Auto-Generated) |
| `8` | No Applicable State Regulation | | `M` | In Compliance – CEMs |
| `9` | In Compliance – Shut Down | | `P` | Present, See Other Program(s) |
| | | | `U` | Unknown By Evaluation Calculation (Generated Value–Not Available For Input) |
| | | | `W` | In Violation With Regard To Procedural Compliance |
| | | | `Y` | Unknown With Regard To Both Emissions And Procedural Compliance |

**data:** all of `0`–`9` and `A, B, C, D, E, F, G, H, M, P, U, W, Y` appear at the facility level in this
download.

**`CURRENT_HPV`** — "A one-character code indicating if plant is currently categorized as a High Priority
Violator."

| Code | Description |
|---|---|
| `B` | Violation Unaddressed; EPA And State Share Lead Enforcement |
| `C` | Violation Addressed; EPA And State Share Lead Enforcement |
| `D` | Src W/Svil=B W/Changed Comp. Status Code From 1 Or 6 To 2,3,4,8 Or 9 (Obsolete) |
| `E` | Violation Unaddressed; EPA Has Lead Enforcement |
| `F` | Violation Addressed; EPA Has Lead Enforcement |
| `G` | Src W/Svil=E W/Changed Comp. Stat. Code from 1 Or 6 To 2,3,4,8 Or 9 (Obsolete) |
| `H` | EPA (Lead) Resolved In A Prior Fiscal Year (Obsolete) |
| `P` | Both (Lead) Resolved In A Prior Fiscal Year (Obsolete) |
| `S` | Violation Unaddressed; State/Local Has Lead Enforcement |
| `T` | Violation Addressed; State Has Lead Enforcement |
| `U` | Src W/Svil=S W/Changed Compliance Status from 1 Or 6 To 2,3,4,8, Or 9 (Obsolete) |
| `V` | State (Lead) Resolved in A Prior Year (Obsolete) |
| `X` | Violation Unaddressed; Enforcement Lead Unassigned |

**data:** observed values are `C, E, F, S, T` (plus blank for non-HPV plants). The remaining codes — including
all "(Obsolete)" ones — do not appear.

### `AIR_PROGRAM.csv`

One row per plant–program (with pollutant-level detail). Joins to facilities on `AFS_ID` / `PLANT_ID`.
Per EPA, Air Program data are "a repeating block of data addressing each regulatory area that a facility is
subject to (e.g., SIP, NSPS, NESHAP, PSD)."

| Field | Type | Len | Description |
|---|---|---|---|
| `PLANT_ID` | Num | 22 | Plant identifier |
| `AFS_ID` | Char | 10 | Plant identifier |
| `AIR_PROGRAM_CODE` | Char | 1 | Regulatory air program (codes below) |
| `AIR_PROGRAM_STATUS` | Char | 1 | Operating status within the program (same codes as `OPERATING_STATUS`) |
| `EPA_CLASSIFICATION_CODE` | Char | 2 | Emissions classification at the air-program level |
| `EPA_COMPLIANCE_STATUS` | Char | 1 | Compliance status at the air-program level |
| `AIR_PROGRAM_CODE_SUBPARTS` | Char | 71 | Applicable subparts; "Multiple subpart codes are delimited by a single blank space" |
| `POLLUTANT_CODE` | Char | 5 | "A five-character code that identifies a pollutant tracked at the air program level" (see Appendix 1) |
| `CHEMICAL_ABSTRACT_SERVICE_NMBR` | Char | 9 | "The chemical abstract number (CAS) for the pollutant if it exists" |
| `POLLUTANT_CLASSIFICATION` | Char | 2 | Emissions classification at the pollutant level (same codes as `EPA_CLASSIFICATION_CODE`) |
| `POLLUTANT_COMPLIANCE_STATUS` | Char | 1 | Compliance status at the pollutant level (same codes as `EPA_COMPLIANCE_STATUS`) |

**`AIR_PROGRAM_CODE`** — "A one-character code used to identify 1) the regulatory air program(s) that applies
to a particular plant or point, and 2) the regulatory air program(s) authorizing and associated with an
action taken by a local, state or federal regulatory agency."

| Code | Description | | Code | Description |
|---|---|---|---|---|
| `0` | SIP Source | | `A` | Acid Precipitation |
| `1` | SIP Source under federal jurisdiction | | `F` | FESOP (non-Title V) |
| `3` | Non-Federally Reportable Source | | `I` | Native American |
| `4` | CFC Tracking | | `M` | MACT (Section 63 NESHAPs) |
| `6` | PSD | | `T` | TIP (Tribal Implementation Plan) |
| `7` | NSR | | `V` | Title V Permits |
| `8` | NESHAP | | | |
| `9` | NSPS | | | |

> **data note:** the `AIR_PROGRAM_CODE` column in this download also contains the values **`G`** (≈313 rows)
> and **`R`** (≈310 rows), which are **not** in EPA's documented program-code list above; their meaning is not
> documented in the AFS download materials.

**`AIR_PROGRAM_CODE_SUBPARTS`** — "A field indicating applicable air program subparts. Multiple subpart codes
are delimited by a single blank space." The full subpart code list (≈90 values, e.g. `DA` = "Elec Util Steam
Gener After 9/18/78", `J` = "Petroleum Refineries") is given in EPA's AFS PDF; each is a source-category
subpart shared with the NSPS/NESHAP subpart numbering. Not reproduced here — see the AFS Data Element
Dictionary.

### `AFS_ACTIONS.csv`

Compliance-monitoring and enforcement events, rolled up to plant level. Per EPA, Action/Activity Data cover
inspections, enforcement actions, etc., **1978 to present**.

| Field | Type | Len | Description |
|---|---|---|---|
| `PLANT_ID` | Num | 22 | Plant identifier |
| `AFS_ID` | Char | 10 | Plant identifier |
| `ANU1` | Num | 22 | "The action number is a numeric field used to uniquely identify an action record" |
| `NATIONAL_ACTION_TYPE` | Char | 2 | Two-character action code (inspection/enforcement); see note below |
| `NATIONAL_ACTION_DESC` | Char | 50 | "Text description for value NATIONAL_ACTION_TYPE" |
| `DATE_ACHIEVED` | Char | 6 | "Field that indicates the date (YYYYMMDD) of a completed compliance action" |
| `ALL_AIR_PROGRAM_CODES` | Char | 4000 | "All air programs associated with a given National Action Type … delimited by a single blank space" |
| `PENALTY_AMOUNT` | Char | 9 | Civil penalty "assessed, or agreed to by a facility in the final agreement between the enforcement authority and the plant" |
| `RESULT_CODE` | Char | 2 | Result of stack tests / Title V reviews (codes below) |
| `POLLUTANT_CODE` | Char | 5 | Pollutant associated with the action (see Appendix 1) |
| `ALL_VIOLATING_POLL_CODES` | Char | 17 | "One or more five character code values that identifies pollutant(s) in violation by the related national action" |
| `ALL_VIOLATION_TYPE_CODES` | Char | 27 | "One or more three character codes that identify the types of violations cited" (codes below) |
| `KEY_ACTION_NUMBERS` | Char | 59 | Links an action to a violation-to-FCE pathway; "An action can be linked to a maximum of ten pathways" |
| `REGIONAL_DATA_ELEMENT_8` | Char | 2 | Title V Annual Compliance Certification result: In Compliance (MC), In Violation (MV), or Unknown (MU) |
| `DATE_RECORD_IS_UPDATED` | Char | 6 | "The last date the action record was updated" |
| `CREATION_DATE` | Char | 8 | "The date the action record was created in AFS … automatically generated when a new plant action record is created" |

**`NATIONAL_ACTION_TYPE`** — "A two-character code identifying a compliance activity including inspections and
enforcement actions. The National Action Type field translates region-specific action type codes to the
corresponding EPA national activity code. … The lead agency for a national action is indicated within its
description. The most commonly used codes for inspections are: FF, FS, FE, FZ, 1A, & 5C for full inspections,
and EM, EO, ES, EX, PC, PO, PP, PR, PS & PX for partial inspections. The most commonly used codes for formal
enforcement actions are: 1B, 2D, 6B, 7A, 7E, 7F, 8A, 8C, & 9A." The AFS PDF tabulates ≈100 national action
codes (a subset "limited to compliance monitoring and enforcement activities"); this download contains ~110
distinct values. Not reproduced here — each row carries its own `NATIONAL_ACTION_DESC`; see the AFS PDF for
the full list.

**`RESULT_CODE`** — "Code indicating results of Stack Test and Title V review."

| Code | Description | | Code | Description |
|---|---|---|---|---|
| `01` | Action Achieved | | `FR` | Fed Rept Viol |
| `02` | Not Achieved | | `MA` | QEER Adequate |
| `03` | Action Resched. | | `MC` | In Compliance |
| `97` | Approved | | `MI` | QEER Inadequate |
| `98` | Disapproved | | `MR` | Retest Req |
| `99` | Pending | | `MU` | Unknown CMST |
| `FF` | Stack Test Failed | | `MV` | In Violation |
| | | | `PP` | Stack Test Passed |

**`ALL_VIOLATION_TYPE_CODES`** — "One or more three character codes that identify the types of violations cited
for a violation or administrative penalty."

| Code | Description |
|---|---|
| `GC1` | Fail to Obtain PSD or NSR Permit and/or a Permit for Major Mods to Either |
| `GC2` | Viol. of Air Toxics Req. Resulting in Either EE or Viol. Op Parm Restricts |
| `GC3` | Viol. by SM of Emis Lim or Perm. Condition Effecting Srces PSD, NSR or T5 |
| `GC4` | Viol. of Substantive Term of any S/L or Fed Order, Consent Decree or AO |
| `GC5` | Substantial Viol. of T5 Cert. Obligation, e.g., Failure to Submit a Cert |
| `GC6` | Substantial Violation of Srces Obligation to Submit T5 Permit Application |
| `GC7` | Test/Monitor/Records/Reporting Viol. that Interfere w/Enf or Cmst |
| `GC8` | Viol. of Allw Emis. Limit Detected during a Reference Method Stack Test |
| `GC9` | Clean Air Act (CAA) Violations by Chronic or Recalcitrant Violators |
| `G10` | Substantial Violation of Clean Air Act Section 112(R) Requirements |
| `M1A` | Any Violation of Emission Limit Detected via Stack Testing |
| `M1B` | Violation of Emission Limits >15% via Sampling |
| `M1C` | Violation of Emission Limits > The SST (Supplemental Sig. Threshold) |
| `M2A` | Violation of Direct Surrogate For >5% of Limit For >3% of Operating Time |
| `M2B` | Violation of Direct Surrogate For >50% of Operating Time (OT) |
| `M2C` | Violation of Direct Surrogate of >25% For 2 Reporting Periods |
| `M3A` | Violation of Non-Opacity Standard via CEM of >15% For >5% of Operating Time |
| `M3B` | Violation of Non-Opacity Standard via CEM of the Supplement. Sig. Threshold |
| `M3C` | Viol. of Non-Opacity Std via CEM of >15% for 2 Reporting Periods |
| `M3D` | Viol. of Non-Opacity Std via CEM of >50% of the Oper Time during Report Per |
| `M3E` | Viol of Non-Opacity Std via CEM of >25% During 2 Consec. Reporting Periods |
| `M3F` | Any Violation of Non-Opacity Standard via CEM |
| `M4A` | Violation of Opacity Standards (0-20%) via Continuous Opacity Monitoring |
| `M4B` | Viols. of Opacity Stds >3% of Op Time via Com During 2 Consec. Rept Perds |
| `M4C` | Violation of Opacity Stds (>20%) via Com For >5% of Operating Time |
| `M4D` | Violation of Opacity Standards (>20%) via Com For 5% Operating Time |
| `M4E` | Violation of Opacity Standards (0-20%) via Method 9 VE Readings |
| `M4F` | Violation of Opacity Standards (>20%) via Method 9 VE Readings |

### `AFS_AIR_PRG_HIST_COMPLIANCE.csv`

Quarterly compliance status per plant–program (**FY2007 to present** per EPA). One row per plant–program–quarter.

| Field | Type | Len | Description |
|---|---|---|---|
| `AFS_ID` | Char | 10 | Plant identifier |
| `AIR_PROGRAM_CODE` | Char | 1 | Regulatory program (same codes as `AIR_PROGRAM`) |
| `HISTORICAL_COMPLIANCE_DATE` | Char | 4 | "The date (in YYQQ format) … Quarters are calendar year-quarters (not fiscal year), i.e., quarter one covers January 1 – March 31" |
| `HISTORICAL_COMPLIANCE_STATUS` | Char | 1 | "A compliance status associated with a year and quarter time frame" (same codes as `EPA_COMPLIANCE_STATUS`) |

### `AFS_HPV_HISTORY.csv`

Lifecycle of High Priority Violator designations. One row per HPV episode.

| Field | Type | Len | Description |
|---|---|---|---|
| `AFS_ID` | Char | 10 | Plant identifier |
| `HPV_DAYZERO_TYPE` | Char | 2 | Lead-agency code at day zero (codes below; carried with `HPV_DAYZERO_DESC`) |
| `HPV_DAYZERO_DESC` | Char | 50 | Text description of the day-zero type |
| `HPV_DAYZERO_DATE` | Date |  | Date the plant entered HPV status |
| `HPV_RESOLVED_TYPE` | Char | 2 | Resolution-action code (blank if unresolved; carried with `HPV_RESOLVED_DESC`) |
| `HPV_RESOLVED_DESC` | Char | 50 | Text description of the resolution type |
| `HPV_RESOLVED_DATE` | Date |  | Date the HPV was resolved |

**`HPV_DAYZERO_TYPE`** — "Code designating the lead agency for the high priority violator in AFS. These
correspond to the AFS national action types for "day zeroes", indicating the start of high priority violation
status."

| Code | Description |
|---|---|
| `2B` | Day Zero – Shared Enforcement Lead |
| `2E` | State Day Zero |
| `2Z` | Federal Day Zero |

**`HPV_RESOLVED_TYPE`** — "These correspond to AFS national action types which resolved the HPV pathway in
AFS. … If the HPV pathway was unresolved as of the data extract, this will be blank." Resolution codes in the
AFS PDF include `C3` (113D Pen Collected), `C7` (Closeout Memo Issued), `2K` (Compl By State, No Act Req),
`WD` (EPA 113D Withdrawn), `2L` (Proposed SIP Revision To Compliance), `7G` (Source Ret To Compl By USEPA
W/No Further Act Req), `2M` (Source Specific SIP Revision), and `VR` (Violation Resolved); each row carries
its meaning in `HPV_RESOLVED_DESC`.

### AFS pollutant codes (Appendix 1)

`POLLUTANT_CODE`, `ALL_VIOLATING_POLL_CODES`, and the `AIR_PROGRAM.csv` pollutant code use a shared ~300-value
code list (Appendix 1 of the AFS PDF) — e.g. `AB` Asbestos, `CO` Carbon Monoxide, `SO2` Sulfur Dioxide, `PB`
Lead, `PM25` "Particulate Matter < 2.5 Um", `VOC` Volatile Organic Compounds. Not reproduced here; each AFS
row also carries the pollutant's CAS number (`CHEMICAL_ABSTRACT_SERVICE_NMBR`) where one exists. See the AFS
Data Element Dictionary, Appendix 1, for the full mapping.

---

## CAA Compliance Pipeline

> **Repo note:** `PIPELINE_CAA_00_COMPLETE.csv` was added to `data/raw/` on 2026-07-23 (66,655 rows, matching
> the predecessor extract's count below). It is cleaned to `data/processed/pipeline.csv.gz` (spec in
> `code/02_cleaning/02_cleaning_parameters.R`) and built into the facility × year dataset 6, `pipeline`, by
> `code/04_datasets/07_pipeline.R` — see `briefs/datasets/dataset_construction_decisions.md` Part G for
> coding decisions and verification.

### `PIPELINE_CAA_00_COMPLETE.csv`

Source: <https://echo.epa.gov/tools/data-downloads/caa-pipeline-download-summary>. **What it is.** Per EPA, the
pipeline "shows links between Compliance Monitoring Activities (CMA) to any related violations and/or
enforcement actions" — i.e. it pre-joins, in a single row, a violation to its triggering evaluation and
resulting enforcement action, a linkage not available in the individual ICIS-Air tables. This file documents
the 35 columns. In the predecessor extract the file had **66,655 rows**, with `FOUND_VIOLATION = Y` for every
row (**data**).

**Identification and row-level flags**

| Field | Type | Len | Description |
|---|---|---|---|
| `SORT_ORDER` | Num |  | "A generated field to aid in the linkage creation" (EPA internal ordering) |
| `SORT_DATE` | Date |  | "A linkage creation helper field to help get the proper display order by date" |
| `SOURCE_ID` | Char | 30 | "The Clean Air Act facility identification number" (ICIS-Air `PGM_SYS_ID`) |
| `REGISTRY_ID` | Char | 50 | Facility Registry Service (FRS) ID (character, to preserve leading zeros) |
| `AIR_NAME` | Char | 200 | "The facility name" |
| `PIPELINE_FLAG` | Char | 1 | EPA: "an internally generated flag to indicate at least [one] violation (VIOL_ACTIVITY_ID) linked to an evaluation and/or enforcement action." **data:** values Y/N |
| `OFFICIAL_FLAG` | Char | 1 | EPA: "set to 'Y' when an entry is counted as compliance monitoring strategy activities" (null for programs without strategies) |

**Evaluation block (the compliance-monitoring activity)**

| Field | Type | Len | Description |
|---|---|---|---|
| `EVAL_FLAG` | Char | 1 | EPA: "an internally generated flag to indicate if there is at least one Compliance Monitoring Activity (CMA) (evaluation) [linked] to the violation activity id." |
| `EVAL_SORT_ORDER` | Num |  | Internal ordering of the evaluation within the row |
| `EVAL_ACTIVITY_ID` | Num |  | Evaluation activity identifier. **data:** a sentinel value `-9999` is used where no evaluation is linked |
| `EVAL_TYPE_DESC` | Char | 100 | Evaluation type (e.g. FCE/PCE variants, Investigation, Self-Disclosure). **data:** includes a "Self-Disclosure" category |
| `EVAL_LEAD_AGENCY` | Char | 5 | Lead agency for the evaluation (EPA / State / Local) |
| `EVAL_DATE` | Date |  | Date of the evaluation |

**Violation block**

| Field | Type | Len | Description |
|---|---|---|---|
| `VIOL_FLAG` | Char | 1 | Flag indicating a violation on the row |
| `VIOL_SORT_ORDER` | Num |  | Internal ordering of the violation |
| `FOUND_VIOLATION` | Char | 1 | "Flag indicating if violation was found." **data:** Y for all 66,655 rows |
| `VIOL_ACTIVITY_ID` | Num |  | Violation activity identifier (key linking violations to CMAs and/or EAs). **data + EPA:** some rows carry system-generated IDs (prefixes `9906`/`9913`) that "did not have an actual violation activity identification number" and were "system generated for purposes of creating the pipeline table" |
| `VIOL_TYPE` | Char | 40 | Violation type. **data:** HPV, FRV, plus placeholder values (blank, and "Linked to Viol. Below") on the system-generated rows |
| `VIOL_TYPE_SORT` | Num |  | Internal ordering by violation type |
| `VIOL_LEAD_AGENCY` | Char | 6 | Lead agency for the violation (EPA / State / Local; often blank on placeholder rows) |
| `VIOL_PROGRAMS` | Char | 4000 | Regulatory program(s) violated |
| `VIOL_POLLUTANT_CODES` | Char | 4000 | Pollutant code(s) of the violation |
| `VIOL_POLLUTANT_DESCS` | Char | 4000 | Pollutant description(s) of the violation |
| `VIOL_START_DATE` | Date |  | Violation start date |
| `VIOL_END_DATE` | Char | 40 | Violation end/resolution date (text field, mixed format) |
| `VIOL_END_DATE_DATE` | Date |  | Parsed date version of `VIOL_END_DATE` |

**Enforcement-action block**

| Field | Type | Len | Description |
|---|---|---|---|
| `EA_FLAG` | Char | 1 | Flag indicating an enforcement action on the row |
| `EA_SORT_ORDER` | Num |  | Internal ordering of the enforcement action |
| `EA_ACTIVITY_ID` | Num |  | Enforcement-action activity identifier |
| `EA_FEA_ACTIVITY_ID` | Num |  | Separate identifier for the formal enforcement action |
| `EA_TYPE` | Char | 100 | Enforcement-action type (e.g. Notice of Violation, Administrative – Formal, Judicial) |
| `EA_DATE` | Date |  | Date of the enforcement action |
| `FEA_ISSUE_DATE_FLAG` | Char | 1 | Flag for the formal-enforcement-action issue date |
| `EA_PENALTY_AMT` | Num |  | Monetary penalty. **data:** non-zero on 14,427 rows |
| `EA_COMP_ACTION_COST` | Num |  | Supplemental compliance / environmental-project cost. **data:** non-zero on 94 rows |

> **Lead-agency note (data).** There is no enforcement-action-level lead-agency field; the only lead-agency
> columns are `EVAL_LEAD_AGENCY` and `VIOL_LEAD_AGENCY`. Of the 94 non-zero `EA_COMP_ACTION_COST` rows, 83 have
> a blank `VIOL_LEAD_AGENCY`, so agency attribution via that field is incomplete.
