# MIMIC-IV validation cohort — design addendum

Companion to the eICU analysis. Purpose: turn a single-database description into a
pattern demonstrated across two health systems a decade apart.

**Status 2026-08-06:** MIMIC-IV DUA not signed. Nothing below has been verified against
data. Every claim about MIMIC-IV table contents is an expectation to be checked, not a
fact.

---

## 1. Why this raises the tier

Single-database descriptive studies are common and are judged as such. Two cohorts,
different health systems, different eras, different severity scores, same pattern —
that is a different kind of claim, and it is what separates *Journal of Critical Care*
from a real shot at *Annals ATS* or *CCM*.

The contrast is favourable on every axis:

| | eICU-CRD | MIMIC-IV |
|---|---|---|
| Centres | 208 | 1 (BIDMC) |
| Years | 2014-2015 | 2008-2022 |
| ICU stays | 200,859 | 94,458 |
| Severity score | APACHE IVa (supplied) | SAPS-II / APS-III (computed) |
| Strength | breadth | recency + depth |

Each covers the other's weakness. That is the argument for using both.

## 2. The design point that matters

**Do not attempt to replicate the same score.** MIMIC-IV has no APACHE IVa. Forcing a
match is impossible and would be the wrong move anyway.

Use each database's native severity score, and frame the replication at the level of the
*finding*, not the *number*:

> Does observed-to-predicted mortality vary systematically with code status, in two
> health systems, using two independently developed severity scores?

If the gradient appears with APACHE IVa in 208 hospitals in 2014-15 **and** with SAPS-II
at one hospital across 2008-22, the result is not an artifact of one score's
construction. That is a stronger claim than repeating APACHE IVa twice, and it should be
stated as a deliberate design choice, not excused as a limitation.

## 3. Harmonisation

### 3.1 Code status

- **eICU:** `careplangeneral`, `cplgroup = 'Care Limitation'`, values confirmed
  (full therapy / DNR / no CPR / no intubation / no cardioversion / comfort measures
  only / no vasopressors / no augmentation / no blood products / no blood draws /
  advance directives)
- **MIMIC-IV:** expected in `chartevents` via a "Code Status" item in `d_items`
  (MetaVision-sourced). Expected values along the lines of Full code / DNR / DNI /
  Comfort measures only / CPR not indicated. **Unverified — probe 1.**

Map both onto a single ordered scale, collapsing to the coarsest level both support:

| Tier | Meaning |
|---|---|
| 1 | Full therapy / full code |
| 2 | DNR-type (no CPR, no intubation, no cardioversion, DNI) |
| 3 | Partial withdrawal (no vasopressors, no augmentation, no blood products) |
| 4 | Comfort measures only |

Tier 3 may not exist in MIMIC-IV. If it doesn't, collapse to three tiers **in both
cohorts** rather than reporting different scales side by side.

### 3.2 Cancer

- **eICU:** APACHE flags — `metastaticcancer`, `leukemia`, `lymphoma`
- **MIMIC-IV:** `mimiciv_derived.charlson` carries `malignant_cancer` and
  `metastatic_solid_tumor`, derived from ICD-9/10. **Closest available analogue —
  probe 5.**

These are not identical instruments. The eICU definition is APACHE's comorbidity
assessment; the MIMIC one is ICD-derived. Report the difference explicitly and run a
sensitivity analysis using ICD codes in eICU's `diagnosis` table as a common
denominator.

### 3.3 Predicted mortality

- **eICU:** `apachepatientresult.predictedhospitalmortality`, APACHE IVa
- **MIMIC-IV:** `mimiciv_derived.sapsii.sapsii_prob`, with `apsiii_prob` and
  `oasis_prob` as sensitivity analyses. **Unverified — probe 6.**

## 4. Probes, in order — all cheap, run before any analysis

1. **Does a Code Status item exist in `d_items`?** Search `label` for 'code status',
   'DNR', 'resuscitat'. **If nothing usable exists, the validation cohort is dead —
   check this first.**
2. Distribution of code status values and their frequencies.
3. Coverage: proportion of ICU stays with any code status charted. eICU achieves ~86%.
   Below ~50% in MIMIC-IV weakens the comparison substantially.
4. Timing: proportion with code status documented within 24h of ICU admission.
5. Cancer cohort size from `charlson`. Expect roughly 3-8% of stays.
6. Confirm `mimiciv_derived` exists on BigQuery and that `sapsii_prob` is populated.

## 5. Cost

MIMIC-IV is smaller than eICU on the tables involved. `chartevents` is large (~430M
rows), so **filter on `itemid` early and never select all columns** — a code status
extraction touching three columns with an itemid filter should stay well under 5 GB.
Free tier is ample.

## 6. Risks

1. **Code status may not be structured in MIMIC-IV.** The single point of failure.
   Probe 1 settles it.
2. **Coverage may be far lower than eICU's 86%,** since documentation is a local
   practice. Low coverage means the MIMIC cohort is selected, not representative.
3. **Cancer ascertainment differs** between the two (APACHE assessment vs ICD).
4. **MIMIC-IV is one hospital.** It cannot validate the *between-hospital variation*
   finding at all — only the calibration gradient. Say so plainly; do not let the
   abstract imply otherwise.
5. **Era confounding.** MIMIC-IV spans 2008-2022; code status practice almost certainly
   drifted over that period. Worth stratifying by `anchor_year_group` — and that
   stratification is itself a finding eICU cannot produce.

## 7. What this adds to the paper

- Second cohort, different health system, different era, different severity score
- Temporal trend in code status documentation across 2008-2022 (MIMIC only)
- A demonstrated pattern rather than a single-database observation

## 8. What it does not fix

The between-hospital variation result stays eICU-only. MIMIC-IV has one hospital and
contributes nothing to it.
