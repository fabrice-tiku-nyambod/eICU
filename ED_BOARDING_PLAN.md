# Does prolonged ED boarding really protect patients? A target trial emulation

**Status:** plan drafted 2026-07-30. No data accessed. MIMIC-IV DUA not yet signed.
**Database:** MIMIC-IV v3.1 + MIMIC-IV-ED (BigQuery: `physionet-data.mimiciv_v3_1_hosp`,
`mimiciv_v3_1_icu`, and the MIMIC-IV-ED datasets).

> Written before any query. Frozen before the confirmatory analysis. Deviations go in
> `DEVIATIONS.md` with date and reason.

---

## 1. The problem

A 2025 BMJ Open analysis of MIMIC-IV (n=12,703) reported that **longer** ED-to-ICU
time was associated with **lower** in-hospital mortality: 17.6% in the shortest
quartile falling to 12.2% in the longest, adjusted OR 0.75 (95% CI 0.69-0.82).

Taken at face value this says boarding is protective. That conclusion is implausible
and, if acted on, harmful -- ED boarding is currently a live target for policy
intervention.

**The likely explanation is structural, not clinical.**

### 1.1 Survivor selection into the exposure

Cohort entry required admission to the ICU. Therefore:

- to fall in Q4 (5.65-34.55 h) a patient must survive >= 5.65 h in the ED
- to fall in Q1 (<= 2.83 h) a patient need only survive 2.83 h

A patient who deteriorates and dies at hour 3 **can** appear in Q1 and **cannot**
appear in Q4. The long-boarding group is purged of early deaths by construction.
This is immortal time operating through cohort entry rather than through follow-up.

### 1.2 Triage works, in the wrong direction for this analysis

The sickest patients are moved fastest. Short boarding is therefore a *marker* of
severity. Q1 is enriched for severity; Q4 is depleted of it.

### 1.3 Why propensity weighting does not fix either

Propensity methods balance *measured* covariates. Neither mechanism above is a
measured-covariate problem: 1.1 is a structural feature of who can enter which
exposure group, and 1.2 is partly driven by unrecorded clinical gestalt. Both
survive any amount of weighting.

## 2. Objectives

**Primary.** Estimate the effect of ED boarding duration on 30-day mortality using a
design that admits no immortal time, and compare it against the naive estimate
reproduced from the same data.

**Secondary.**
1. Reproduce the published inverse association to confirm the artifact is
   reconstructible, and quantify how much of it each correction removes.
2. Estimate the effect on 90-day mortality and on ICU length of stay.
3. Characterise the excluded population -- patients who died in the ED or were never
   admitted -- which prior work discarded.

## 3. Cohort

**Base population.** Adult ED presentations in MIMIC-IV-ED for whom a decision to
admit to ICU is identifiable, **including those who died in the ED**.

This is the central departure from prior work. MIMIC-IV contains 141,175 patients seen
in the ED who were never admitted to hospital; `edstays.disposition = 'EXPIRED'`
identifies ED deaths. Prior analyses excluded this group by construction.

**Exclusions**, each counted for a flow diagram:
1. Age < 18
2. No identifiable ICU-level disposition decision
3. Transfers in from another facility (different boarding process)
4. Missing `edregtime` / `edouttime`

**Exposure.** Boarding duration = time from ICU-disposition decision to ICU arrival.
Where the decision timestamp is unavailable, `admissions.edregtime` -> `icustays.intime`
is the fallback, with the difference in definitions reported as a sensitivity analysis.

**Outcome.** 30-day all-cause mortality from `patients.dod`, which captures
out-of-hospital death for up to one year. This replaces the in-hospital mortality used
previously and is immune to discharge-timing artifact -- a patient discharged to
hospice on day 4 is counted as a death, not silently as a survivor.

## 4. Design -- three analyses, reported side by side

The paper's contribution is the *contrast* between these, not any one estimate.

**A. Naive replication.** Quartiles of boarding time, ICU-admitted patients only,
in-hospital mortality, propensity weighting. Reproduces the published approach as
closely as the description allows. Expected to recover OR ~ 0.75.

**B. Denominator correction.** As A, but ED deaths returned to the cohort and assigned
to the exposure group they were on track for at the time of death. Isolates how much
of the effect is pure survivor selection.

**C. Target trial emulation (primary).** Sequential-landmark, clone-censor-weight:

- landmarks at 1, 2, 3, 4, 6, 8 h after the ICU-disposition decision
- at each landmark, among patients still alive and still boarding, contrast
  "transferred within the next hour" vs "still boarding"
- inverse-probability-of-censoring weights for informative censoring
- pooled across landmarks with patient-level cluster-robust variance

By construction no participant contributes immortal time: everyone is alive and
unexposed at each landmark.

**Instrumental-variable sensitivity analysis.** ED census and ICU occupancy at the time
of the disposition decision plausibly shift boarding duration without acting directly on
that patient's mortality. Reported as a secondary estimate with the exclusion
restriction stated as an assumption, not a fact.

## 5. Statistical detail

- Confounders: age, sex, triage acuity, arrival vitals, initial labs, Charlson
  comorbidity, admitting service, time of day, arrival mode
- Time-of-day and day-of-week are available in MIMIC-IV (dates are shifted but
  internally consistent), unlike eICU
- Absolute risk differences reported alongside odds ratios throughout
- E-value for unmeasured confounding on the primary estimate

## 6. Anticipated result and how it will be reported

Expected: the naive estimate reproduces the protective association; the corrected
estimate is null or harmful. **The result will be reported whichever way it comes out.**
If boarding remains protective under design C, that is a genuine and interesting
finding and gets published as such.

## 7. Framing

Positioned as a methodological hazard in ED boarding research, illustrated by
re-analysis -- not as a rebuttal of specific authors. The prior study is cited as
motivation and treated as a reasonable analysis with a subtle structural flaw, which is
what it is.

## 8. Threats to validity

1. **Disposition-decision timestamp may not exist** in usable form. This is the single
   biggest feasibility risk; if the decision time is unavailable, exposure is measured
   with error and design C weakens substantially. **Check this first.**
2. Single centre (BIDMC); boarding dynamics are institution-specific.
3. ED deaths may be too few to move the estimate, in which case survivor selection is
   not the explanation and mechanism 1.2 carries the result instead.
4. The IV analysis rests on an exclusion restriction that cannot be tested.
5. We cannot see the prior study's full methods; if it handled ED deaths in a way not
   described in the abstract, objective 1 needs restating.

## 9. Feasibility probes, in order

1. Does a usable ICU-disposition-decision timestamp exist in MIMIC-IV-ED?
   **If no, redesign before anything else.**
2. How many ED deaths occur among patients with an ICU-level disposition? Need enough
   to matter.
3. Can the published cohort be reconstructed -- roughly 15,246 screened, 12,703
   analysed? If our replication is far off, we are not analysing the same thing.
