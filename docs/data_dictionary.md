# CAA Regulatory Data — Data Dictionary

Field-level documentation for every raw source in this repository, transcribed from EPA's official
published data dictionaries. Each entry lists the source CSV, a one-line description, and every field
with its type/length (where EPA publishes them) and definition.

**Sources:** EPA ECHO data downloads — ICIS-Air, AFS (the pre-2014 Air Facility System), and the CAA
Compliance Pipeline. See <https://echo.epa.gov/tools/data-downloads/>. Source PDFs are in
`docs/data_dictionaries/`; regenerate this file with `python3 scripts/build_data_dictionary.py`.

> A few descriptions inherit run-together words (missing spaces) from the source PDFs; field names,
> types, and lengths are exact.

---

## ICIS-Air

### `ICIS-AIR_FACILITIES.csv`

Facility and source-level identification data for air pollution sources.

| Field | Type | Len | Description |
|---|---|---|---|
| `PGM_SYS_ID` | Char | 30 | Alphanumeric program system identifier; uniquely identifies each air source |
| `REGISTRY_ID` | Char | 12 | FacilityRegistryService(FRS)IDlinkingregulatory records |
| `FACILITY_NAME` | Char | 80 | Official or legal name of the plant |
| `STREET_ADDRESS` | Char | 35 | First line of street address or site entrance identifier |
| `CITY` | Char | 60 | City where plant is physically located |
| `COUNTY_NAME` | Char | 100 | County where plant is physically located |
| `STATE` | Char | 2 | Two-character postal abbreviation |
| `ZIP_CODE` | Char | 14 | Five- or nine-digit zip code |
| `EPA_REGION` | Char | 2 | EPA Regional office code (01–10) |
| `SIC_CODES` | Char | 4000 | Standard Industrial Classification codes |
| `NAICS_CODES` | Char | 4000 | North American Industry Classification System codes |
| `FACILITY_TYPE_CODE` | Char | 3 | Government or private facility type code |
| `AIR_POLLUTANT_CLASS_CODE` | Char | 3 | Source emissions classification (MAJ/SMI/MIN/UNK/OTH/NAP) |
| `AIR_POLLUTANT_CLASS_DESC` | Char | 100 | Description of pollutant classification |
| `AIR_OPERATING_STATUS_CODE` | Char | 5 | Operational condition code (OPR/SEA/TMP/CNS/PLN/CLS; data uses these 6) |
| `AIR_OPERATING_STATUS_DESC` | Char | 100 | Description of operating status |
| `CURRENT_HPV` | Char | 80 | HighPriorityViolatorstatusandenforcementinformation |
| `LOCAL_CONTROL_REGION_CODE` | Char | 3 | Local Control Region code with jurisdiction |
| `LOCAL_CONTROL_REGION_NAME` | Char | 100 | Local Control Region name 1 |

### `ICIS-AIR_PROGRAMS.csv`

Air regulatory programs applicable to facilities.

| Field | Type | Len | Description |
|---|---|---|---|
| `PGM_SYS_ID` | Char | 30 | Program system identifier linking to facilities |
| `PROGRAM_CODE` | Char | 9 | Nine-character code identifying the regulatory air program |
| `PROGRAM_DESC` | Char | 100 | Description of the air program |
| `AIR_OPERATING_STATUS_CODE` | Char | 5 | Operational condition for the air program |
| `AIR_OPERATING_STATUS_DESC` | Char | 100 | Description of program operating status |
| `BEGIN_DATE` | Date |  | Date data were entered in the program system |
| `UPDATED_DATE` | Date |  | Date information was last updated |

### `ICIS-AIR_PROGRAM_SUBPARTS.csv`

Air program subparts detailing specific regulatory requirements.

| Field | Type | Len | Description |
|---|---|---|---|
| `PGM_SYS_ID` | Char | 30 | Program system identifier |
| `PROGRAM_CODE` | Char | 9 | Air program code |
| `PROGRAM_DESC` | Char | 100 | Program description |
| `AIR_PROGRAM_SUBPART_CODE` | Char | 20 | Code indicating applicable air program subparts |
| `AIR_PROGRAM_SUBPART_DESC` | Char | 200 | Description of the subpart |

### `ICIS-AIR_POLLUTANTS.csv`

Pollutants tracked at the air program level.

| Field | Type | Len | Description |
|---|---|---|---|
| `PGM_SYS_ID` | Char | 30 | Program system identifier |
| `POLLUTANT_CODE` | Num |  | Numeric code that identifies a pollutant |
| `POLLUTANT_DESC` | Char | 2000 | Pollutant description |
| `SRS_ID` | Char | 9 | Substance Registry Services ID |
| `CHEMICAL_ABSTRACT_SERVICE_NMBR` | Char | 9 | Chemical Abstract Service (CAS) number |
| `AIR_POLLUTANT_CLASS_CODE` | Char | 3 | Pollutant emissions classification |
| `AIR_POLLUTANT_CLASS_DESC` | Char | 100 | Emissions classification description |

### `ICIS-AIR_FCES_PCES.csv`

Full Compliance Evaluations (FCEs) and Partial Compliance Evaluations (PCEs).

| Field | Type | Len | Description |
|---|---|---|---|
| `PGM_SYS_ID` | Char | 30 | Program system identifier |
| `ACTIVITY_ID` | Num |  | Unique identifier for an activity at/related to a site |
| `STATE_EPA_FLAG` | Char | 1 | Agency in charge (E = EPA, S = State, L = Local) |
| `ACTIVITY_TYPE_CODE` | Char | 3 | Activity type code; value is INS (inspection) in this table |
| `ACTIVITY_TYPE_DESC` | Char | 100 | Description of activity type |
| `COMP_MONITOR_TYPE_CODE` | Char | 3 | Compliance monitoring type (FCE: FOO/FFO; PCE: PCE/PFF/PFR/POC/POF/POI/POM/POR/POV) |
| `COMP_MONITOR_TYPE_DESC` | Char | 100 | Compliance monitoring type description |
| `ACTUAL_END_DATE` | Date | 10 | Calendar date of inspection |
| `PROGRAM_CODES` | Char | 4000 | Applicable regulatory program codes |
| `ACTIVITY_PURPOSE_DESC` | Char | 100 | Description of compliance evaluation purpose |

### `ICIS-AIR_STACK_TESTS.csv`

Stack test results and compliance monitoring data.

| Field | Type | Len | Description |
|---|---|---|---|
| `PGM_SYS_ID` | Char | 30 | Program system identifier |
| `ACTIVITY_ID` | Num |  | Activity identifier |
| `COMP_MONITOR_TYPE_CODE` | Char | 3 | Compliancemonitoringtype(valueisCSTinthistable) |
| `COMP_MONITOR_TYPE_DESC` | Char | 100 | Monitoring type description |
| `STATE_EPA_FLAG` | Char | 1 | Responsible agency (E/S/L) |
| `ACTUAL_END_DATE` | Date | 7 | Test completion date |
| `POLLUTANT_CODES` | Char | 4000 | Numeric pollutant codes tested |
| `POLLUTANT_DESCS` | Char | 4000 | Descriptions of tested pollutants |
| `AIR_STACK_TEST_STATUS_CODE` | Char | 3 | Stack test result (FAI/PSS/PEN/INC observed) |
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
| `FACILITY_RPT_DEVIATION_FLAG` | Char | 1 | Y/N flag for facility-reported deviations during review 3 |

### `ICIS-AIR_FORMAL_ACTIONS.csv`

Formal enforcement actions and penalties.

| Field | Type | Len | Description |
|---|---|---|---|
| `PGM_SYS_ID` | Char | 30 | Program system identifier |
| `ACTIVITY_ID` | Num |  | Activity identifier |
| `ENF_IDENTIFIER` | Char | 25 | Identifiesmultipleoccurrencesofanenforcementcase |
| `ACTIVITY_TYPE_CODE` | Char | 3 | Civilenforcementactivitytype(AFR=Administrative Formal, JDC = Judicial) |
| `ACTIVITY_TYPE_DESC` | Char | 100 | Activity type description |
| `STATE_EPA_FLAG` | Char | 1 | Responsible agency (E/S/L) |
| `ENF_TYPE_CODE` | Char | 7 | Code identifying the action type against the plant |
| `ENF_TYPE_DESC` | Char | 100 | Enforcement type description |
| `SETTLEMENT_ENTERED_DATE` | Date | 7 | Datesettlementsignedbyjudgeandenteredbyclerk |
| `PENALTY_AMOUNT` | Num |  | Civil penalty amount assessed or agreed upon |

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
| `ACHIEVED_DATE` | Date | 7 | Date informal action achieved |
| `OFFICIAL_FLG` | Char | 1 | Official action flag (Y/N) |

### `ICIS-AIR_VIOLATION_HISTORY.csv`

High Priority Violations (HPVs) and Federally Reportable Violations (FRVs) case-file data.

| Field | Type | Len | Description |
|---|---|---|---|
| `PGM_SYS_ID` | Char | 30 | Program system identifier |
| `ACTIVITY_ID` | Num |  | Activity identifier |
| `AGENCY_TYPE_DESC` | Char | 100 | Environmental agency responsible for enforcement |
| `STATE_CODE` | Char | 2 | State identifier |
| `AIR_LCON_CODE` | Char | 3 | Local Control Region code |
| `COMP_DETERMINATION_UID` | Char | 25 | Unique identifier for the case-file activity 4 |
| `ENF_RESPONSE_POLICY_CODE` | Char | 3 | Enforcement response policy type (HPV/FRV) |
| `PROGRAM_CODES` | Char | 4000 | Applicable program codes |
| `PROGRAM_DESCS` | Char | 4000 | Program descriptions |
| `POLLUTANT_CODES` | Char | 4000 | Associated pollutant codes |
| `POLLUTANT_DESCS` | Char | 4000 | Pollutant descriptions |
| `EARLIEST_FRV_DETERM_DATE` | Date | 7 | Earliest Federally Reportable Violation determination date |
| `HPV_DAYZERO_DATE` | Date | 7 | Date facility entered HPV status |
| `HPV_RESOLVED_DATE` | Date | 7 | Date facility resolved HPV status |
| `DSCV_PATHWAY_DATE` | Date |  | Date violation was discovered |
| `NFTC_PATHWAY_DATE` | Date |  | Date facility was notified 5 |

---

## AFS (Air Facility System — pre-2014)

### `AFS_FACILITIES.csv`

One row per plant: identification, location, classification, operating, and compliance status.

| Field | Description |
|---|---|
| `PLANT_ID` | Numeric plant identifier |
| `AFS_ID` | 10-character plant code (state FIPS + county FIPS + AFS plant number); also “SCSC” |
| `PLANT_NAME` | Plant name |
| `EPA_REGION` | EPA region (01–10) |
| `PLANT_STREET_ADDRESS /` | Location fields PLANT_CITY / PLANT_COUNTY / STATE / STATE_NUMBER / ZIP_CODE |
| `PRIMARY_SIC_CODE /` | Four-character Standard Industrial Classification codes SECONDARY_SIC_CODE |
| `NAICS_CODE` | Six-character NAICS code |
| `AFS_GOV_FACILITY_CODE` | Government facility indicator (see codes below) |
| `FEDERALLY_REPORTABLE` | Y/N; ECHO-generated (see definition below) |
| `EPA_CLASSIFICATION_CODE` | Emissions classification (see codes below) |
| `OPERATING_STATUS` | Operational condition (see codes below) |
| `EPA_COMPLIANCE_STATUS` | EPA compliance determination (see codes below) |
| `CURRENT_HPV` | Current High Priority Violator status (see codes below) |
| `LOCAL_CONTROL_REGION` | Two-character local control region code (meanings vary by state) |
| `STATE_COMPLIANCE_STATUS` | State agency compliance determination (same code set as EPA_COMPLIANCE_STATUS) EPA_CLASSIFICATION_CODE (Alabama Power decision / 1993 EPA guidance) 1 Code Description |
| `A` | Actual or potential emissions above the applicable major-source thresholds |
| `A1` | Actual or potential controlled emissions >100 tons/year |
| `A2` | Actual emissions <100 tons/year, but potential uncontrolled emissions >100 tons/year |
| `B` | Potential uncontrolled emissions <100 tons/year |
| `C` | Unregulated pollutant, actual or potential controlled emissions >100 tons/year |
| `ND` | Major-source thresholds not defined |
| `SM` | Synthetic minor: potential emissions below all applicable major-source limits |
| `UK` | Unknown classification Correction: C is not “Unknown” (only UK is). Observed in the data: A, A1, A2, B, C, ND, SM, UK. OPERATING_STATUS Code Description |
| `O` | Operating |
| `C` | Under Construction |
| `P` | Planned (applied for a construction permit) |
| `T` | Temporarily Closed |
| `X` | Permanently Closed |
| `I` | Seasonal |
| `D` | NESHAP Demolition |
| `R` | NESHAP Renovation |
| `S` | NESHAP Spraying |
| `L` | Landfill Observed in the data: O, C, P, T, X, I (the NESHAP/landfill statuses D, R, S, L are documented but do not appear in this download). EPA_COMPLIANCE_STATUS (worst case across EPA and state fields) Code Description 0 Unknown compliance status 1 In Violation – No Schedule 2 In Compliance – Source Test 3 In Compliance – Inspection 4 In Compliance – Certification 5 Meeting Compliance Schedule 6 In Violation – Not Meeting Schedule 7 In Violation – Unknown With Regard To Schedule 8 No Applicable State Regulation 9 In Compliance – Shut Down |
| `A` | Unknown With Regard To Procedural Compliance |
| `B` | In Violation With Regard To Both Emissions And Procedural Compliance 2 Code Description |
| `C` | In Compliance With Procedural Requirements |
| `D` | HPV Violation (auto-generated) |
| `E` | FRV Violation (auto-generated) |
| `F` | HPV On Schedule (auto-generated) |
| `G` | FRV On Schedule (auto-generated) |
| `H` | In Compliance (auto-generated) |
| `M` | In Compliance – CEMs |
| `P` | Present, See Other Program(s) |
| `U` | Unknown By Evaluation Calculation |
| `W` | In Violation With Regard To Procedural Compliance |
| `Y` | Unknown With Regard To Both Emissions And Procedural Compliance Codes A, B, C, P, U, W, Y appear in the data and are defined in EPA’s AFS documentation; a prior draft listed only 0–9, D, E, F, G, H, M. CURRENT_HPV Code Description |
| `S` | Violation Unaddressed; State/Local has lead enforcement |
| `T` | Violation Addressed; State has lead enforcement |
| `E` | Violation Unaddressed; EPA has lead enforcement |
| `F` | Violation Addressed; EPA has lead enforcement |
| `B` | Violation Unaddressed; EPA and State share lead enforcement |
| `C` | Violation Addressed; EPA and State share lead enforcement |
| `X` | Violation Unaddressed; enforcement lead unassigned Observed in the data: C, E, F, S, T (B and X are documented but do not appear). AFS_GOV_FACILITY_CODE 0 Privately owned/operated \| 1 Federal \| 2 State \| 3 County \| 4 Municipality \| 5 District \| 6 Tribe. (All 0–6 observed.) FEDERALLY_REPORTABLE ECHO-generated Y/N. Per EPA documentation, “Y” if EPA_CLASSIFICATION_CODE ∈ {A, A1, A2, SM}, OR (AIR_PROGRAM_CODE ∈ {8, 9} and EPA_COMPLIANCE_STATUS ̸= 8). |

### `AIR_PROGRAM.csv`

One row per plant–program (with pollutant-level detail). Joins to facilities on AFS_ID/PLANT_ID.

| Field | Description |
|---|---|
| `AFS_ID / PLANT_ID` | Plant identifiers |
| `AIR_PROGRAM_CODE` | One-character regulatory air program (see codes below) |
| `AIR_PROGRAM_STATUS` | Operating status within the program (same codes as OPERATING_STATUS) |
| `EPA_CLASSIFICATION_CODE` | Emissions classification at the air-program level |
| `EPA_COMPLIANCE_STATUS` | Compliance status at the air-program level |
| `AIR_PROGRAM_CODE_SUBPARTS` | Applicable subparts, space-delimited |
| `POLLUTANT_CODE` | Pollutant code at the air-program level |
| `CHEMICAL_ABSTRACT_SERVICE_NMBR` | CAS number for the pollutant, if any |
| `POLLUTANT_CLASSIFICATION` | Emissions classification at the pollutant level |
| `POLLUTANT_COMPLIANCE_STATUS` | Compliance status at the pollutant level AIR_PROGRAM_CODE (per EPA AFS documentation) 0 SIP \| 1 SIP under federal jurisdiction (FIP) \| 3 Non-Federally Reportable \| 4 CFC Tracking \| 6 PSD \| 7 NSR \| 8 NESHAP (Part 61) \| 9 NSPS \| A Acid Precipitation \| F FESOP (non-Title V) \| I Native American \| M MACT (Part 63) \| T TIP (Tribal Implementation Plan) \| V Title V. Data note: the AIR_PROGRAM_CODE column also contains the values G and R, which are not in EPA’s documented program-code list above; their meaning is not documented in the AFS download materials. |

### `AFS_ACTIONS.csv`

Compliance-monitoring and enforcement events, rolled up to plant level (1978–present).

| Field | Description |
|---|---|
| `AFS_ID / PLANT_ID` | Plant identifiers |
| `ANU1` | Action number; uniquely identifies an action within a plant |
| `NATIONAL_ACTION_TYPE` | Two-characteractioncode(inspection/enforcement). Seenotebelow |
| `NATIONAL_ACTION_DESC` | Text description of the action type |
| `DATE_ACHIEVED` | Date the action was completed (YYYYMMDD) |
| `ALL_AIR_PROGRAM_CODES` | All air programs associated with the action, space-delimited |
| `PENALTY_AMOUNT` | Civil penalty assessed or agreed, in dollars |
| `RESULT_CODE` | Result of stack tests / Title V reviews / actions |
| `POLLUTANT_CODE` | Pollutant associated with the action |
| `ALL_VIOLATING_POLL_CODES` | Pollutant(s) in violation, space-delimited |
| `ALL_VIOLATION_TYPE_CODES` | Violation type code(s) |
| `KEY_ACTION_NUMBERS` | Links to violation / FCE pathways (up to ten) |
| `REGIONAL_DATA_ELEMENT_8` | Region-specific data element |
| `CREATION_DATE /` | Record metadata dates DATE_RECORD_IS_UPDATED NATIONAL_ACTION_TYPEtranslatesregion-specificcodestoEPAnationalactivitycodes; the lead agency is indicated within each code’s description. Per EPA, the most common codes are 4 FF, FS, FE, FZ, 1A, 5C (full inspections); EM, EO, ES, EX, PC, PO, PP, PR, PS, PX (partial inspections); and 1B, 2D, 6B, 7A, 7E, 7F, 8A, 8C, 9A (formal enforcement). The download contains 110 distinct NATIONAL_ACTION_TYPE values and over 130 RESULT_CODE values; the full codelistsaregiveninEPA’sAFSdocumentation,andeachrowalsocarriesitsownNATIONAL_ACTION_DESC. |

### `AFS_AIR_PRG_HIST_COMPLIANCE.csv`

Quarterly compliance status per plant–program (FY2007–present). One row per plant–program– quarter.

| Field | Description |
|---|---|
| `AFS_ID` | Plant identifier |
| `AIR_PROGRAM_CODE` | Regulatory program (same codes as AIR_PROGRAM) |
| `HISTORICAL_COMPLIANCE_DATE` | Quarter, YYQQ (Q1 = Jan–Mar, ..., Q4 = Oct–Dec) |
| `HISTORICAL_COMPLIANCE_STATUS` | Compliance status for the quarter (same codes as EPA_COMPLIANCE_STATUS) |

### `AFS_HPV_HISTORY.csv`

Lifecycle of High Priority Violator designations. One row per HPV episode.

| Field | Description |
|---|---|
| `AFS_ID` | Plant identifier |
| `HPV_DAYZERO_TYPE` | Lead-agency code at day zero (carried with HPV_DAYZERO_DESC) |
| `HPV_DAYZERO_DESC` | Text description of the day-zero type |
| `HPV_DAYZERO_DATE` | Date the plant entered HPV status |
| `HPV_RESOLVED_TYPE` | Resolution-action code (blank if unresolved; carried with HPV_RESOLVED_DESC) |
| `HPV_RESOLVED_DESC` | Text description of the resolution type |
| `HPV_RESOLVED_DATE` | Date the HPV was resolved The *_TYPE code meanings are carried in the adjacent *_DESC columns in the data itself, and are listed in EPA’s AFS documentation. 5 |

---

## CAA Compliance Pipeline

### `PIPELINE_CAA_00_COMPLETE.csv`

https://echo.epa.gov/tools/data-downloads/caa-pipeline-download-summary. What it is. Per EPA, the pipeline “shows links between Compliance Monitoring Activities (CMA) to any related violations and/or enforcement actions” — i.e. it pre-joins, in a single row, a violation to its triggering evaluation and resulting enforcement action, a linkage not available in the individual ICIS-Air tables. The narrative structure and caveats are documented separately in pipeline_brief.tex; this file documents the 35 columns. Conventions used below. “EPA” marks a definition quoted from EPA’s pipeline documentation; “data” marks a fact verified directly against the file. The file has 66,655 rows; FOUND_VIOLATION = Y for every row (data). Identification and row-level flags

| Field | Description |
|---|---|
| `SORT_ORDER` | EPA internal ordering of pipeline rows |
| `SORT_DATE` | Date used for EPA’s internal ordering |
| `SOURCE_ID` | Facility identifier (ICIS-Air PGM_SYS_ID) |
| `REGISTRY_ID` | Facility Registry Service (FRS) ID |
| `AIR_NAME` | Facility name |
| `PIPELINE_FLAG` | EPA: “an internally generated flag to indicate at least [one] violation (VIOL_ACTIVITY_ID) linked to an evaluation and/or enforcement action.” Data: values Y/N |
| `OFFICIAL_FLAG` | EPA: “this flag is set to ‘Y’ when an entry is counted as compliance monitoring strategy activities.” Evaluation block (the compliance-monitoring activity) |
| `EVAL_FLAG` | EPA: “an internally generated flag to indicate if there is at least one Compliance Monitoring Activity (CMA) (evaluation) [linked] to the violation activity id.” |
| `EVAL_SORT_ORDER` | Internal ordering of the evaluation within the row |
| `EVAL_ACTIVITY_ID` | Evaluation activity identifier. Data: a sentinel value -9999 is used where no evaluation is linked 1 |
| `EVAL_TYPE_DESC` | Evaluation type (e.g. FCE/PCE variants, Investigation, SelfDisclosure). Data: includes a “Self-Disclosure” category |
| `EVAL_LEAD_AGENCY` | Lead agency for the evaluation (EPA / State / Local) |
| `EVAL_DATE` | Date of the evaluation |
| `VIOL_FLAG` | Flag indicating a violation on the row |
| `VIOL_SORT_ORDER` | Internal ordering of the violation |
| `FOUND_VIOLATION` | Data: Y for all 66,655 rows |
| `VIOL_ACTIVITY_ID` | Violation activity identifier. Data + EPA: some rows carry systemgenerated IDs (prefixes 9906/9913) that, per EPA, “did not have an actualviolationactivityidentificationnumber” andwere“systemgenerated for purposes of creating the pipeline table” |
| `VIOL_TYPE` | Violation type. Data: HPV, FRV, plus placeholder values (blank, and “Linked to Viol. Below”) on the system-generated rows |
| `VIOL_TYPE_SORT` | Internal ordering by violation type |
| `VIOL_LEAD_AGENCY` | Lead agency for the violation (EPA / State / Local; often blank on placeholder rows) |
| `VIOL_PROGRAMS` | Regulatory program(s) violated |
| `VIOL_POLLUTANT_CODES /` | Pollutant code(s) and description(s) VIOL_POLLUTANT_DESCS |
| `VIOL_START_DATE` | Violation start date |
| `VIOL_END_DATE` | Violation end/resolution date (text field, mixed format) |
| `VIOL_END_DATE_DATE` | Parsed date version of VIOL_END_DATE Enforcement-action block |
| `EA_FLAG` | Flag indicating an enforcement action on the row |
| `EA_SORT_ORDER` | Internal ordering of the enforcement action |
| `EA_ACTIVITY_ID` | Enforcement-action activity identifier |
| `EA_FEA_ACTIVITY_ID` | Separate identifier for the formal enforcement action |
| `EA_TYPE` | Enforcement-action type (e.g. Notice of Violation, Administrative – Formal, Judicial) |
| `EA_DATE` | Enforcement-action date |
| `FEA_ISSUE_DATE_FLAG` | Flag for the formal-enforcement-action issue date |
| `EA_PENALTY_AMT` | Monetary penalty. Data: non-zero on 14,427 rows |
| `EA_COMP_ACTION_COST` | Supplemental compliance / environmental-project cost. Data: nonzero on 94 rows Lead-agency note (data). There is no enforcement-action-level lead-agency field; the only leadagencycolumnsareEVAL_LEAD_AGENCYandVIOL_LEAD_AGENCY.Ofthe94non-zeroEA_COMP_ACTION_COST 2 rows, 83 have a blank VIOL_LEAD_AGENCY, so agency attribution via that field is incomplete. 3 |
