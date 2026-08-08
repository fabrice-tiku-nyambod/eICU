# Six surviving project options

Consolidated 2026-08-04, after screening ~11 candidate ideas across eICU-CRD and
MIMIC-IV. Everything not listed here was killed on either feasibility or prior work;
reasons are in the session record, not repeated.

**Screening bar used from here on:** a meaningful contribution -- larger, better
designed, or a documented gap -- NOT "nobody has touched this." The stricter bar was
wrong for clinical research and killed at least two viable ideas (beta-blockers,
deresuscitation), both reinstated below.

---

## Summary

| # | Project | Dataset | Access | Effort | Risk | Already done |
|---|---------|---------|--------|--------|------|--------------|
| 1 | Treatment limitation in critically ill cancer patients | eICU-CRD | **working** | 2-3 wk | low | most of the analysis |
| 2 | Beta-blocker continuation in sepsis (TTE) | MIMIC-IV | DUA unsigned | 6-10 wk | moderate | nothing |
| 3 | ED boarding re-analysis | MIMIC-IV + ED | DUA unsigned | 6-8 wk | mod-high | plan written |
| 4 | Appendiceal neoplasm descriptive epidemiology | SEER | account needed | 4-6 wk | low-mod | nothing |
| 5 | Critical care oncology cohort 2008-2022 | MIMIC-IV | DUA unsigned | 4-6 wk | moderate | nothing |
| 6 | Early deresuscitation after shock (TTE) | MIMIC-IV | DUA unsigned | 8-12 wk | high | nothing |

---

## 1. Treatment limitation in critically ill cancer patients

Descriptive, multicentre. How is code status documented in cancer patients across
208 US ICUs, and how much does practice vary between hospitals?

**Results already in hand from this session:**
- 4,326 cancer ICU stays with APACHE IVa; 131,910 non-cancer comparators
- limitation documented <=24h: 19.4% cancer vs 9.6% non-cancer (2.02x)
- ordered scale with stay counts: full therapy 172,656 / DNR 27,058 / no intubation
  6,179 / no CPR 5,960 / no cardioversion 2,915 / comfort measures only 4,418 /
  no vasopressors 1,348 / no augmentation 1,468
- 175 hospitals, limitation rates ~1% to 27%
- observed vs APACHE-predicted mortality within every tier

**Gap:** the nearest prior work (Zhang 2021, eICU + MIMIC cancer subtypes,
PMC7859733) explicitly did not examine code status.

**Framed descriptively, none of the causal problems apply** -- describing practice,
not claiming it causes anything.

Target: *Supportive Care in Cancer*, *JCO Oncology Practice*, *Journal of Critical Care*.

**Fastest route to a submission. Recommended first.**

## 2. Beta-blocker continuation in septic shock -- target trial emulation

Among chronic beta-blocker users admitted with sepsis, continue within 24h vs hold.
Outcomes: 28-day mortality, vasopressor-free days, new arrhythmia.

Prior work: BJA 2017 (n=296, single centre secondary analysis), a 2023
propensity-matched study, a 2024 retrospective. **No RCT. No target trial emulation.**
A TTE in MIMIC-IV would be the largest and most rigorous evidence available.

Main threat: confounding by indication in its purest form -- hypotensive patients get
held. Needs grace period + clone-censor-weight.

Tables: `prescriptions` (home meds), `emar`/`emar_detail` (what was actually given and
when), `inputevents` (vasopressors).

## 3. ED boarding re-analysis

Full plan in `ED_BOARDING_PLAN.md`.

**Blocked on verification:** need the BMJ Open PDF (open access) to confirm the prior
study did not handle ED deaths. If its methods address survivor selection, the premise
collapses.

Second risk: needs an ICU-disposition-decision timestamp in MIMIC-IV-ED. If unusable,
redesign.

## 4. Appendiceal neoplasm descriptive epidemiology (SEER)

Pure oncology. SEER is built for rare-tumour descriptive work -- thousands of cases,
histology, stage, treatment, survival.

Open angles after the 2025 young-adult incidence paper: histology-specific survival
(LAMN / HAMN / goblet cell / adenocarcinoma), stage at presentation by race and
insurance, treatment-pattern drift.

**MIMIC-IV cannot carry this** -- incidence is 0.1-1.6 per 100,000 and MIMIC is one
hospital. Expect tens of cases, not hundreds.

Access: free SEER*Stat account, a few days.

## 5. Critical care oncology cohort, MIMIC-IV 2008-2022

Descriptive characterisation of cancer patients in ICU across 15 years including the
COVID era. Richer per patient than eICU, single centre.

Main risk: overlaps Zhang 2021 more than ideal. Differentiator is the 2020-2022 data
added in MIMIC-IV v3.0 and the 15-year span.

## 6. Early deresuscitation after shock resolution -- target trial emulation

Initiate diuresis within 24h of vasopressor discontinuation vs not. Outcomes:
ventilator-free days at 28d, AKI progression, mortality.

Prior: protocolised diuresis before/after study (Critical Care 2020, n=364);
REDUCE feasibility RCT published, full trial running.

**Highest risk of the six** -- the definitive RCT will supersede observational work.
Only worth doing if it can be finished well before the trial reports.

---

## Recommended sequence

1. **#1 now** -- access works, analysis largely done, 2-3 weeks to submission
2. **#4 or #2 next**, depending on whether the priority is oncology or critical care
3. **#3 only if the PDF confirms the flaw**

## Access blockers

- MIMIC-IV DUA: https://physionet.org/content/mimiciv/ (needed for 2, 3, 5, 6)
- MIMIC-IV-ED DUA: https://physionet.org/content/mimic-iv-ed/ (needed for 3)
- SEER*Stat account: https://seer.cancer.gov/ (needed for 4)
- eICU: **already working** -- BigQuery, sandbox, no billing

## Standing note on novelty

Public database + a question anyone could generate = racing thousands of groups.
Durable novelty comes from an asset: data others cannot get, a method others cannot
apply, a clinical question only an insider would ask, or being early to a newly
released dataset. Worth revisiting before committing to another database-first project.
