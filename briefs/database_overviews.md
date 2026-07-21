<!-- Source: transcribed verbatim from the project's Google Doc ("2026 Clean Air Act Project" —
     Data Downloads Overview / ICIS-Air Datasets / AFS Datasets tabs), pulled 2026-07-20. Content only;
     no numbers here are computed from data/raw — the raw-data summary tables (docs/raw_data.html) are the
     script-generated numeric source. This brief describes what each database is, not what it measures. -->

# Database Overviews

## Air Stationary Source Data Downloads

### ICIS-Air Datasets

Tracks compliance and enforcement data on stationary sources. Facility level. 10 different files associated
with ICIS-Air.

**Key information includes:**

- Facility identification and classification (location, ID number, SIC/NAICS, high priority violation (HPV)
  status)
- Violation/enforcement history
- Program/subpart identification (which regulatory regimes a facility is subject to)
- Pollutant information for each facility
- Title V certification information

Includes data files with static characteristics (location, programs, pollutants, etc.) and also time-varying
"events" (evaluations, violations, enforcement actions).

The Facility/Source Level Identifying Data (`ICIS-AIR_FACILITIES.csv`) could be a good "spine," with:

- One row per air source
- FRS ID information
- Location
- Industry classification (SIC/NAICS)
- Emissions classification (major/synthetic minor/minor)

All other ICIS files can join with it via `PGM_SYS_ID`. Non-ICIS ECHO files can connect via `REGISTRY_ID`
(Facility Registry Service (FRS) code).

*What's missing:* emissions (tracks pollutants, but not amount); historical status for programs/pollutants
(offered in AFS).

### Air Emissions Dataset

Facility-level aggregate data from four EPA programs (NEI, GHGRP, TRI, CAMD). Facility-pollutant-program-year
combinations.

**Key information includes:**

- Annual emission quantities by facility, pollutant, and reporting program
- Pollutant category classification (criteria pollutants, HAPs, greenhouse gases)
- Units of measure (NEI/TRI/CAMD report in pounds, GHGRP reports in metric tons of CO2e)

Reporting frequency differs between programs: CAMD, TRI, and GHGRP report annually, NEI is triennial.

- **NEI:** most comprehensive. Attempts to inventory all stationary source emissions of criteria pollutants
  and HAPs. State-submitted estimates, not direct measurement. Broadest coverage but least frequent.
- **GHGRP:** only large emitters (25,000+ metric tons CO2e/year). Annual, greenhouse gases only.
  Self-reported by facilities.
- **TRI:** facilities in specific industries with 10+ employees that manufacture, process, or use listed
  toxic chemicals above threshold quantities. Annual. Covers ~770 chemicals. TRI comes from a different
  statute (not CAA).
- **CAMD:** only electric generating units in the cap-and-trade programs (Acid Rain, CSAPR). Annual. SO2 and
  NOx, directly measured by continuous emission monitors. Smallest universe but highest data quality.

Connects to ICIS-Air via `REGISTRY_ID`.

*What's missing:* facility characteristics; NEI gaps (due to reporting frequency); TRI has different
reporting requirements.

### AFS Dataset

EPA's legacy database for air stationary source compliance/enforcement information. Replaced by ICIS-Air and
frozen as of 2014. Follows a similar structure to ICIS-Air:

**Key information includes:**

- Facility identification/classification (location, SIC/NAICS, emissions class)
- Violation/enforcement history (inspections, enforcement actions, stack tests, penalties)
- Air program assignments with compliance status
- Quarterly historical compliance status
- Pollutant information
- HPV history

Compliance status over time could be valuable. To merge into ICIS data, use FRS information from the
[EPA FRS download summary](https://echo.epa.gov/tools/data-downloads/frs-download-summary).

*What's missing:* no emissions quantities.

### CAA Pipeline Dataset

Associations between compliance monitoring, violations, and enforcement. Records organized by enforcement
pathway. Helps trace which inspection led to which violation led to which enforcement action.

**Key information includes:**

- Facility identification (registry ID, facility name)
- Evaluation data
- Violation data
- Enforcement action data
- Indicators for which stages (evaluation, violation, enforcement action) are present in the "pipeline" for
  each record

Evaluation (inspection) ↔ Violation ↔ Enforcement Action. Shares `REGISTRY_ID` with ICIS-Air.

*What's missing:* facility characteristics (`ICIS-AIR_FACILITIES.csv`); emissions data.

---

## ICIS-Air Datasets

The ICIS-Air datasets have information describing general plant characteristics, compliance, and enforcement
data on stationary sources of air pollution. The data is presented at the plant/facility level, meaning the
entire facility is treated as one unit (not individual stacks/emission points).

**Potential join codes:** `PGM_SYS_ID` is the spine — it uniquely identifies all facilities and can be used
to join any ICIS-Air files. `REGISTRY_ID` is the FRS ID, which can link facilities to non-ICIS data (like
emissions).

#### Facility/Source Level Identifying Data (`ICIS-AIR_FACILITIES.csv`)

Universe of regulated stationary air sources. Base identification table. One row per source. Could be a good
"spine," with: one row per source, FRS ID, location, industry classification (SIC/NAICS), emissions
classification (major/synthetic minor/minor), current HPV status. All other ICIS files can be joined to it
via `PGM_SYS_ID` (which uniquely identifies each air source). Non-ICIS ECHO files can connect via
`REGISTRY_ID` (Facility Registry Service (FRS) code).

*What's missing:* emissions information.

#### Air Programs (`ICIS-AIR_PROGRAMS.csv`)

Facilities subject to at least one CAA program. Lists the regulatory programs that a facility is subject to.
One facility could be associated with multiple programs (e.g. Title V and NSPS). Each row is a
facility-program combination.

**Key information includes:** program code and description; operational condition (a facility can be
operating under one program and closed under another); date the facility entered program; date program
record was last modified.

#### Air Program Subparts (`ICIS-AIR_PROGRAM_SUBPARTS.csv`)

One level deeper than programs. Identifies the specific regulatory subparts within a program that apply to a
facility.

**Key information includes:** parent program; regulatory subpart.

#### Air Pollutants (`ICIS-AIR_POLLUTANTS.csv`)

Facilities with at least one tracked pollutant. Specific pollutants associated with each facility.

**Key information includes:** numeric code and name of pollutant; Substance Registry Services ID; Chemical
Abstract Service (CAS) number; pollutant class code (major/synthetic minor/minor).

#### Air Full Compliance Evaluations (FCEs) and Partial Compliance Evaluations (PCEs)

Only facilities that have been inspected. Records of compliance monitoring activities. FCEs are more
comprehensive; PCEs focus more on particular aspects.

**Key information includes:** activity ID for specific evaluation events; which agency conducted the
evaluation (state/local agency or EPA); what kind of compliance monitoring was done (FCE on site/off site,
PCE monitoring/sampling…); date of inspection/review; which regulatory programs the evaluation covered.

#### Air Stack Tests (`ICIS-AIR_STACK_TESTS.csv`)

Only facilities that have had a stack test. Results of emissions testing at facility stacks.

**Key information includes:** activity ID; type of compliance monitoring; responsible agency; date of test;
which pollutants were tested; result (pass, fail, pending, incomplete…).

#### Air Title V Certifications (`ICIS-AIR_TITLEV_CERTS.csv`)

Only sources required to hold Title V permits. Record of operating permit/annual compliance certification
certificates.

**Key information includes:** activity ID; responsible agency; date of certification; whether the facility
self-reported deviations from permit requirements.

#### ICIS-Air Formal Actions (`ICIS-AIR_FORMAL_ACTIONS.csv`)

Only facilities that have received enforcement. Formal enforcement responses to violations. Actions with
legal force (consent agreements, administrative orders, and judicial actions).

**Key information includes:** activity ID; identifier to group multiple activities that belong to the same
case; type of enforcement activity (administrative formal, judicial…); responsible agency; date settlement
was signed by a judge (marks formal resolution); penalty amount.

#### ICIS-Air Informal Actions (`ICIS-AIR_INFORMAL_ACTIONS.csv`)

Only facilities that have received enforcement. Informal enforcement responses (actions without direct legal
force). Notices of violations (NOVs), warning letters, phone calls. Often precede formal actions.

**Key information includes:** activity ID; identifier to group multiple activities that belong to the same
case; type of informal action; responsible agency; date the informal action was completed; indicator for
whether the action was an official agency action.

#### Case File High Priority Violations (HPVs) and Federally Reportable Violations (FRVs) (`ICIS-AIR_VIOLATION_HISTORY.csv`)

Only facilities with HPV/FRV violations. Holds all Federally Reportable Violations, including the HPV
subset. Tracks the lifecycle of each violation from discovery to resolution.

**Key information includes:** activity ID; which level of government is handling enforcement; identifier for
case file activity; violation severity (HPV, FRV); which regulatory programs were violated; pollutants
involved; date the violation was deemed federally reportable; date facility entered HPV status; date HPV was
resolved; date violation was discovered; date facility was notified of violation.

---

## AFS Datasets

#### Facility/Source Level Identifying Data (`AFS_FACILITIES.csv`)

Universe of regulated stationary air sources tracked in the legacy Air Facility System. One row per plant.
Treats the entire facility as one unit rather than looking at individual emission points.

**Key information includes:** AFS ID; location; industry classification; emissions classification
(major/synthetic minor/minor); operating status; EPA and state compliance status; HPV status; government
facility indicator (federal/state/county…); federally reportable flag. Other AFS files join via `AFS_ID`.

*What's missing:* emissions data, historical statuses, enforcement history.

#### Air Program (`AIR_PROGRAM.csv`)

Plants subject to at least one CAA program. Lists regulatory programs that a plant is subject to. One plant
could be associated with multiple programs. Plant-program combinations.

**Key information includes:** air program code; operating status within the program; applicable subparts;
pollutant code, CAS number, pollutant-level classification.

*What's missing:* detailed facility information; emissions information.

#### Actions (`AFS_ACTIONS.csv`)

Plants associated with actions. Compliance monitoring and enforcement activity rolled up to plant level.
Inspections (FCE/PCEs), enforcement actions (NOVs, administrative orders, consent decrees), stack tests, and
Title V certification reviews.

**Key information includes:** national action type and description; date achieved; all air programs
addressed by the action; penalty amount; result code (pass/fail for stack tests, compliance status for Title
V reviews); violation type codes; linkage to violation/FCE pathways.

*What's missing:* detailed facility information; emissions information; no state vs. EPA flag (embedded in
action type code).

#### Historical Compliance — Air Program Level (`AFS_AIR_PRG_HIST_COMPLIANCE.csv`)

Quarterly compliance status for each air program at each plant. Beginning in FY2007.

**Key information includes:** air program code; quarter (YYQQ format, calendar year quarters); compliance
status for that quarter.

*What's missing:* detailed facility information; emissions information.

#### Historical HPV Status (`AFS_HPV_HISTORY.csv`)

HPV plants. Tracks the lifecycle of HPV designations. Each row is one HPV episode.

**Key information includes:** lead enforcement agency at day 0; day-zero date (start of HPV status);
resolution type (how the HPV was resolved); resolution date (gap between day 0 and resolution measures
enforcement speed — blank if unresolved).

*What's missing:* detailed facility information; emissions information; no FRVs; no pollutants involved.
Essentially gives a timeline with minimal detail.
