# =========================================================================================================
# code/03_datasets/hap_list_112b.R -- static reference table: the CAA section 112(b) list of
#   Hazardous Air Pollutants (HAPs), 188 substances currently in force. Sourced (not typed from memory) and
#   validated below; used by code/03_datasets/01_regulatory.R to replace the old
#   grepl("HAZARDOUS AIR POLLUTANT", POLLUTANT_DESC) rule, which only matched pollutant rows literally
#   labeled with that umbrella phrase and missed the large majority of HAPs that ICIS-AIR records by
#   specific chemical name (Benzene, Formaldehyde, Lead, Mercury, ...) -- see panel_construction_decisions.md
#   and dataset_construction_decisions.md for the before/after facility counts that motivated this.
#
#   PROVENANCE:
#   - Base list (189 substances, as enacted): 42 U.S.C. 7412(b)(1), fetched 2026-07-28 from the Cornell
#     Legal Information Institute mirror of the U.S. Code (https://www.law.cornell.edu/uscode/text/42/7412),
#     parsed programmatically from its CAS-number/name HTML table (not hand-transcribed).
#   - Modifications codified at 40 CFR Part 63 Subpart C (fetched 2026-07-28 via the eCFR versioner API,
#     https://www.ecfr.gov/api/versioner/v1/full/2024-01-01/title-40.xml?part=63):
#       * 40 CFR 63.60 -- Caprolactam (CAS 105602) DELETED
#       * 40 CFR 63.61 -- Methyl ethyl ketone (CAS 78933) DELETED
#       * 40 CFR 63.64 -- 1-Bromopropane (CAS 106945) ADDED [87 FR 396, Jan. 5, 2022]
#     (63.62/63.63 narrow the "Glycol ethers" class definition rather than remove a table row -- no row
#     change from those two sections.)
#     Net: 189 - 2 + 1 = 188 current entries. (Public EPA summaries citing "187" predate the Jan 2022
#     1-Bromopropane addition -- 187 was correct 1996-2022, after Caprolactam/MEK were delisted and before
#     1-Bromopropane was added; 188 is current.)
#
#   VALIDATION PERFORMED (2026-07-28, at construction time): exactly 188 rows; zero duplicate real
#   (non-"0") CAS numbers; spot-checked against an independently-fetched EPA archived summary page for
#   Benzene (71432), Formaldehyde (50000), Vinyl chloride (75014), Asbestos (1332214) -- all matched.
#
#   CAS "0" marks the 17 compound-class entries (e.g. "Chromium Compounds") that have no single CAS
#   number -- this is EPA's own convention, not a missing-data placeholder. "Polycylic Organic Matter"
#   (sic) is not a typo introduced here -- it is how 42 U.S.C. 7412(b)(1) itself spells it; matching below
#   accounts for the more common "Polycyclic" spelling as well, since ICIS-AIR likely uses that spelling.
# =========================================================================================================
library(tibble); library(dplyr)

HAP_112B <- tribble(
  ~cas_number, ~hap_name,
  "75070", "Acetaldehyde",
  "60355", "Acetamide",
  "75058", "Acetonitrile",
  "98862", "Acetophenone",
  "53963", "2-Acetylaminofluorene",
  "107028", "Acrolein",
  "79061", "Acrylamide",
  "79107", "Acrylic acid",
  "107131", "Acrylonitrile",
  "107051", "Allyl chloride",
  "92671", "4-Aminobiphenyl",
  "62533", "Aniline",
  "90040", "o-Anisidine",
  "1332214", "Asbestos",
  "71432", "Benzene (including benzene from gasoline)",
  "92875", "Benzidine",
  "98077", "Benzotrichloride",
  "100447", "Benzyl chloride",
  "92524", "Biphenyl",
  "117817", "Bis(2-ethylhexyl)phthalate (DEHP)",
  "542881", "Bis(chloromethyl)ether",
  "75252", "Bromoform",
  "106990", "1,3-Butadiene",
  "156627", "Calcium cyanamide",
  "133062", "Captan",
  "63252", "Carbaryl",
  "75150", "Carbon disulfide",
  "56235", "Carbon tetrachloride",
  "463581", "Carbonyl sulfide",
  "120809", "Catechol",
  "133904", "Chloramben",
  "57749", "Chlordane",
  "7782505", "Chlorine",
  "79118", "Chloroacetic acid",
  "532274", "2-Chloroacetophenone",
  "108907", "Chlorobenzene",
  "510156", "Chlorobenzilate",
  "67663", "Chloroform",
  "107302", "Chloromethyl methyl ether",
  "126998", "Chloroprene",
  "1319773", "Cresols/Cresylic acid (isomers and mixture)",
  "95487", "o-Cresol",
  "108394", "m-Cresol",
  "106445", "p-Cresol",
  "98828", "Cumene",
  "94757", "2,4-D, salts and esters",
  "3547044", "DDE",
  "334883", "Diazomethane",
  "132649", "Dibenzofurans",
  "96128", "1,2-Dibromo-3-chloropropane",
  "84742", "Dibutylphthalate",
  "106467", "1,4-Dichlorobenzene(p)",
  "91941", "3,3-Dichlorobenzidene",
  "111444", "Dichloroethyl ether (Bis(2-chloroethyl)ether)",
  "542756", "1,3-Dichloropropene",
  "62737", "Dichlorvos",
  "111422", "Diethanolamine",
  "121697", "N,N-Diethyl aniline (N,N-Dimethylaniline)",
  "64675", "Diethyl sulfate",
  "119904", "3,3-Dimethoxybenzidine",
  "60117", "Dimethyl aminoazobenzene",
  "119937", "3,3′-Dimethyl benzidine",
  "79447", "Dimethyl carbamoyl chloride",
  "68122", "Dimethyl formamide",
  "57147", "1,1-Dimethyl hydrazine",
  "131113", "Dimethyl phthalate",
  "77781", "Dimethyl sulfate",
  "534521", "4,6-Dinitro-o-cresol, and salts",
  "51285", "2,4-Dinitrophenol",
  "121142", "2,4-Dinitrotoluene",
  "123911", "1,4-Dioxane (1,4-Diethyleneoxide)",
  "122667", "1,2-Diphenylhydrazine",
  "106898", "Epichlorohydrin (l-Chloro-2,3-epoxypropane)",
  "106887", "1,2-Epoxybutane",
  "140885", "Ethyl acrylate",
  "100414", "Ethyl benzene",
  "51796", "Ethyl carbamate (Urethane)",
  "75003", "Ethyl chloride (Chloroethane)",
  "106934", "Ethylene dibromide (Dibromoethane)",
  "107062", "Ethylene dichloride (1,2-Dichloroethane)",
  "107211", "Ethylene glycol",
  "151564", "Ethylene imine (Aziridine)",
  "75218", "Ethylene oxide",
  "96457", "Ethylene thiourea",
  "75343", "Ethylidene dichloride (1,1-Dichloroethane)",
  "50000", "Formaldehyde",
  "76448", "Heptachlor",
  "118741", "Hexachlorobenzene",
  "87683", "Hexachlorobutadiene",
  "77474", "Hexachlorocyclopentadiene",
  "67721", "Hexachloroethane",
  "822060", "Hexamethylene-1,6-diisocyanate",
  "680319", "Hexamethylphosphoramide",
  "110543", "Hexane",
  "302012", "Hydrazine",
  "7647010", "Hydrochloric acid",
  "7664393", "Hydrogen fluoride (Hydrofluoric acid)",
  "123319", "Hydroquinone",
  "78591", "Isophorone",
  "58899", "Lindane (all isomers)",
  "108316", "Maleic anhydride",
  "67561", "Methanol",
  "72435", "Methoxychlor",
  "74839", "Methyl bromide (Bromomethane)",
  "74873", "Methyl chloride (Chloromethane)",
  "71556", "Methyl chloroform (1,1,1-Trichloroethane)",
  "60344", "Methyl hydrazine",
  "74884", "Methyl iodide (Iodomethane)",
  "108101", "Methyl isobutyl ketone (Hexone)",
  "624839", "Methyl isocyanate",
  "80626", "Methyl methacrylate",
  "1634044", "Methyl tert butyl ether",
  "101144", "4,4-Methylene bis(2-chloroaniline)",
  "75092", "Methylene chloride (Dichloromethane)",
  "101688", "Methylene diphenyl diisocyanate (MDI)",
  "101779", "4,4′-Methylenedianiline",
  "91203", "Naphthalene",
  "98953", "Nitrobenzene",
  "92933", "4-Nitrobiphenyl",
  "100027", "4-Nitrophenol",
  "79469", "2-Nitropropane",
  "684935", "N-Nitroso-N-methylurea",
  "62759", "N-Nitrosodimethylamine",
  "59892", "N-Nitrosomorpholine",
  "56382", "Parathion",
  "82688", "Pentachloronitrobenzene (Quintobenzene)",
  "87865", "Pentachlorophenol",
  "108952", "Phenol",
  "106503", "p-Phenylenediamine",
  "75445", "Phosgene",
  "7803512", "Phosphine",
  "7723140", "Phosphorus",
  "85449", "Phthalic anhydride",
  "1336363", "Polychlorinated biphenyls (Aroclors)",
  "1120714", "1,3-Propane sultone",
  "57578", "beta-Propiolactone",
  "123386", "Propionaldehyde",
  "114261", "Propoxur (Baygon)",
  "78875", "Propylene dichloride (1,2-Dichloropropane)",
  "75569", "Propylene oxide",
  "75558", "1,2-Propylenimine (2-Methyl aziridine)",
  "91225", "Quinoline",
  "106514", "Quinone",
  "100425", "Styrene",
  "96093", "Styrene oxide",
  "1746016", "2,3,7,8-Tetrachlorodibenzo-p-dioxin",
  "79345", "1,1,2,2-Tetrachloroethane",
  "127184", "Tetrachloroethylene (Perchloroethylene)",
  "7550450", "Titanium tetrachloride",
  "108883", "Toluene",
  "95807", "2,4-Toluene diamine",
  "584849", "2,4-Toluene diisocyanate",
  "95534", "o-Toluidine",
  "8001352", "Toxaphene (chlorinated camphene)",
  "120821", "1,2,4-Trichlorobenzene",
  "79005", "1,1,2-Trichloroethane",
  "79016", "Trichloroethylene",
  "95954", "2,4,5-Trichlorophenol",
  "88062", "2,4,6-Trichlorophenol",
  "121448", "Triethylamine",
  "1582098", "Trifluralin",
  "540841", "2,2,4-Trimethylpentane",
  "108054", "Vinyl acetate",
  "593602", "Vinyl bromide",
  "75014", "Vinyl chloride",
  "75354", "Vinylidene chloride (1,1-Dichloroethylene)",
  "1330207", "Xylenes (isomers and mixture)",
  "95476", "o-Xylenes",
  "108383", "m-Xylenes",
  "106423", "p-Xylenes",
  "0", "Antimony Compounds",
  "0", "Arsenic Compounds (inorganic including arsine)",
  "0", "Beryllium Compounds",
  "0", "Cadmium Compounds",
  "0", "Chromium Compounds",
  "0", "Cobalt Compounds",
  "0", "Coke Oven Emissions",
  "0", "Cyanide Compounds",
  "0", "Glycol ethers",
  "0", "Lead Compounds",
  "0", "Manganese Compounds",
  "0", "Mercury Compounds",
  "0", "Fine mineral fibers",
  "0", "Nickel Compounds",
  "0", "Polycylic Organic Matter",
  "0", "Radionuclides (including radon)",
  "0", "Selenium Compounds",
  "106945", "1-Bromopropane (1-BP, n-propyl bromide, nPB) [added by 40 CFR 63.64]",
) |>
  mutate(is_compound_class = cas_number == "0")

stopifnot(                                              # fail loudly rather than silently shipping a bad list
  "HAP_112B: expected exactly 188 current CAA 112(b) entries" = nrow(HAP_112B) == 188,
  "HAP_112B: duplicate real CAS number" =
    !anyDuplicated(HAP_112B$cas_number[HAP_112B$cas_number != "0"]),
  "HAP_112B: spot-check failed" = all(
    HAP_112B$cas_number[grepl("^Benzene", HAP_112B$hap_name)] == "71432",
    HAP_112B$cas_number[HAP_112B$hap_name == "Formaldehyde"] == "50000",
    HAP_112B$cas_number[HAP_112B$hap_name == "Vinyl chloride"] == "75014",
    HAP_112B$cas_number[HAP_112B$hap_name == "Asbestos"] == "1332214"))

# regex patterns for the 17 CAS-"0" compound-class entries -- the only part of emits_hap that still relies
# on name matching (there's no CAS to join on for a compound class). Each pattern is the class name up to
# any parenthetical qualifier (e.g. "Arsenic Compounds (inorganic including arsine)" -> "Arsenic Compounds"),
# case-insensitive substring match against POLLUTANT_DESC. "Polyc(y|i)?lic" covers both the statute's
# "Polycylic" spelling and the more common "Polycyclic".
HAP_COMPOUND_CLASS_PATTERNS <- HAP_112B |> filter(is_compound_class) |>
  mutate(pattern = trimws(sub("\\s*\\(.*$", "", hap_name)),
         pattern = sub("Polycylic", "Polyc(y|i)?lic", pattern, fixed = FALSE)) |>
  pull(pattern)
