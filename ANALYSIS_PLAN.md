# Code status, not malignancy, explains apparent severity-score miscalibration in critically ill cancer patients

**Status:** plan v2, 2026-08-06. Supersedes the earlier plan for the vitals
measurement study, which was abandoned.
**Database:** eICU-CRD v2.0 (208 US ICUs, 2014-2015) via BigQuery
`physionet-data.eicu_crd`. MIMIC-IV validation cohort planned separately
(`MIMIC_VALIDATION_PLAN.md`).

---

## 1. Question

> Is the reported miscalibration of severity-of-illness scores in critically ill
> patients with cancer attributable to malignancy itself, or to differences in
> treatment-limitation (code status) documentation?

## 2. Positioning against prior work

| Study | What it did | What it leaves open |
|---|---|---|
| Zhang 2021, *Front Med* | eICU + MIMIC-III cancer subtypes, mortality prediction, APACHE IVa vs SAPS-II calibration | states explicitly that **code status was not examined** |
| Feng & Dubin 2021, *Sci Rep* | eICU, Lasso, variables associated with APACHE IVa **classification errors**; care limitation entered as *frequency of change* | **calibration** not analysed; no cancer subgroup; limitation level not used |
| Systematic review 2024, *Med Intensiva* | scores under-predict mortality in ICU cancer patients | attributes miscalibration to malignancy; code-status composition never tested |
| JAMA Intern Med (Hart et al.) | US ICUs vary in managing patients with pre-existing treatment limits | not eICU, not cancer, not calibration |

Feng & Dubin also report APACHE IVa predicting 11.96% mortality against 9.91%
observed (implied SMR ~0.83) in eICU. This **independently corroborates the
over-prediction observed here** and pre-empts the objection that our sub-1 SMRs
contradict the cancer literature.

**The gap:** nobody has decomposed severity-score miscalibration in cancer patients
into malignancy vs code-status contributions.

## 3. Cohort

Unit stays in eICU-CRD v2.0 with a valid APACHE IVa predicted mortality
(`apacheversion = 'IVa'`, `predictedhospitalmortality > 0`) linked to `apachepredvar`.

**Cancer** (primary definition): APACHE IVa comorbidity flags --
`metastaticcancer = 1 OR leukemia = 1 OR lymphoma = 1`.

This captures metastatic solid tumour and haematologic malignancy only. Localised
solid tumours are **not** captured, and primary site is unavailable. The cohort is
therefore labelled *metastatic solid tumour or haematologic malignancy*, not "cancer",
throughout the manuscript.

**Sensitivity:** ICD/free-text ascertainment from `diagnosis` and `pasthistory`,
reported as a concordance analysis.

## 4. Exposure -- ordered code-status tier

From `careplangeneral` where `cplgroup = 'Care Limitation'`, the most restrictive
value documented within 24h of unit admission (`cplitemoffset <= 1440`):

| Tier | Values | Stays (whole DB) |
|---|---|---|
| 1 | Full therapy | 172,656 |
| 2 | Do not resuscitate; No CPR; No intubation; No cardioversion | 27,058 / 5,960 / 6,179 / 2,915 |
| 3 | No vasopressors/inotropes; No augmentation of care; No blood products; No blood draws | 1,348 / 1,468 / 208 / 117 |
| 4 | Comfort measures only | 4,418 |
| 0 | No documentation | -- |

Code status is documented for ~86% of the database, so this is a systematically
recorded field rather than sparse ad-hoc notes.

**Cancer tiers 3 and 4 are n=48 and n=60 and will be collapsed with tier 2** for
inference; the four-tier gradient is reported for the full cohort only.

## 5. Outcome

In-hospital mortality (`actualhospitalmortality = 'EXPIRED'`) against APACHE IVa
`predictedhospitalmortality`.

## 6. Analysis

### 6.1 Primary -- logistic recalibration with interaction

```
logit(P(death)) = b0 + b1*logit(predicted) + b2*Cancer + b3*CodeStatus
                     + b4*(Cancer x CodeStatus)
```

- **b2 is the primary estimand**: does cancer independently alter calibration after
  adjusting for code status?
- b1 is the calibration slope (1.0 = perfect); b0 the calibration intercept
- random intercept for hospital, or cluster-robust SE at hospital level
- pre-specified hypothesis: **b2 attenuates towards null once b3 is included**

This replaces crude SMR entirely. Crude SMR is unreliable across strata whose mean
predicted risk ranges 0.10-0.43 -- an aggregation artifact, not a finding -- and is
reported only descriptively in Table 2.

### 6.2 Secondary

1. **Flexible calibration curves** -- restricted cubic splines of observed on
   predicted, by tier and cancer status; **Integrated Calibration Index** and E-max
2. **Decomposition** -- indirect standardisation of the cancer SMR to the non-cancer
   code-status distribution. Preliminary: crude 0.869 -> standardised 0.798 against
   non-cancer 0.743, i.e. **56.2% of the cancer excess is composition**
3. **Between-hospital variation** -- limitation rates across 162 hospitals with >=100
   stays; ICC from the random-intercept model
4. **Timing** -- distribution of `cplitemoffset` for first limitation; how tier
   deepens over the stay
5. **Patient factors** -- age, sex, APACHE score, admission source, unit type

### 6.3 Interpretation -- fixed in advance

The result is framed as a **prognostic information shift**: clinicians encode
prognostic information into care plans that APACHE IVa does not capture. It is
**not** a causal claim that code status changes mortality. Confounding by
indication is unresolvable here and is stated as such.

## 7. Preliminary results (obtained 2026-07-30)

- 136,236 analysable stays: 4,326 cancer, 131,910 comparator
- limitation <=24h: **19.3% cancer vs 9.6% non-cancer** (2.02x)
- SMR by tier, non-cancer: 0.612 / 1.170 / 1.215 / 1.888
- SMR by tier, cancer: 0.736 / 1.163 / 1.266 / 1.701
- **tier 2 cancer:non-cancer ratio 0.994** -- indistinguishable within DNR stratum
- crude SMR cancer 0.869 vs non-cancer 0.743
- 162 hospitals, limitation rates ~0% to 27%

## 8. Limitations, stated up front

1. Retrospective; 2014-2015 data; US ICUs participating in a tele-ICU programme
2. Documentation is not practice -- we observe charting, not decisions or actions
3. Cancer definition excludes localised solid tumours; no primary site
4. Confounding by indication cannot be resolved: clinicians limit care *because* of
   prognosis, so code status is partly a marker of unmeasured severity
5. Tier 0 (no documentation) behaves anomalously in cancer (SMR 0.446, n=100) and is
   reported but not interpreted
6. eICU is a sample of participating ICUs, not a census of any hospital

## 9. Outputs

**Tables.** 1: cohort characteristics by cancer status. 2: code-status distribution
and crude SMR by tier and cancer. 3: logistic recalibration models. S1: concordance of
cancer ascertainment across three sources.

**Figures.** 1: CONSORT-style exclusion flow. 2: calibration curves by tier.
3: hospital-level limitation rates, ordered, with CIs. 4: decomposition.

## 10. Target journals

Stretch *Annals ATS*; realistic *Journal of Critical Care* or *JCO Oncology Practice*;
safe *Supportive Care in Cancer*. MIMIC-IV validation makes *Annals ATS* reachable.
Top-tier general journals (AJRCCM, Lancet Digital Health) are not realistic for a
retrospective descriptive database study and are not targets.
