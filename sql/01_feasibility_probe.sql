-- ===========================================================================
-- 01_feasibility_probe.sql
--
-- GO / NO-GO probes for the two surviving study designs.
--   Option A -- fluid accumulation velocity & AKI recovery in septic shock
--   Option B -- treatment limitation & score under-prediction in cancer
--
-- NOTE (2026-07-30): access confirmed to `physionet-data.eicu_crd` (full),
-- but NOT to `physionet-data.eicu_crd_demo` -- the demo is a separate
-- PhysioNet project with its own grant. All development therefore happens
-- against the full tables, which makes column discipline the ONLY cost
-- control we have. Consequences:
--   * never SELECT *  (note: LIMIT does NOT reduce bytes scanned in BigQuery;
--     `SELECT * ... LIMIT 10` on nursecharting would scan the whole table)
--   * name every column
--   * to sample cheaply, filter on hospitalid rather than using LIMIT
--
-- Run ONE AT A TIME -- press Ctrl+A before pasting so the previous query is
-- replaced rather than appended. Check the bytes-processed estimate (top
-- right of the console) before each run. Every query below names its columns
-- explicitly; none should exceed ~1 GB. COUNT(*)-only queries scan 0 bytes.
--
-- Each query states the DECISION it drives. If a probe fails its stated
-- threshold, that design is dead and we stop -- that is the point of probing
-- before writing an analysis plan.
-- ===========================================================================


-- ###########################################################################
-- OPTION A -- FLUID ACCUMULATION VELOCITY
-- ###########################################################################

-- ---------------------------------------------------------------------------
-- A1.  Scale check. 0 bytes.
-- ---------------------------------------------------------------------------
SELECT 'intakeoutput' AS tbl, COUNT(*) AS n FROM `physionet-data.eicu_crd.intakeoutput`
UNION ALL SELECT 'lab',      COUNT(*) FROM `physionet-data.eicu_crd.lab`
UNION ALL SELECT 'patient',  COUNT(*) FROM `physionet-data.eicu_crd.patient`;


-- ---------------------------------------------------------------------------
-- A2.  *** THE CRITICAL PROBE FOR OPTION A ***
--      What fraction of each hospital's unit stays have ANY I/O record?
--      eICU I/O completeness is known to vary hugely by site; the design
--      depends on there being enough high-completeness hospitals.
--
--      DECISION RULE: we need >= 30 hospitals with >= 70% stay-level I/O
--      coverage AND >= 200 septic stays among them. Fewer than that and
--      Option A dies here, because restricting to complete sites would
--      leave a cohort too small and too selected to defend.
-- ---------------------------------------------------------------------------
WITH stays AS (
    SELECT patientunitstayid, hospitalid
    FROM `physionet-data.eicu_crd.patient`
),
io_stays AS (
    SELECT DISTINCT patientunitstayid
    FROM `physionet-data.eicu_crd.intakeoutput`
)
SELECT
    s.hospitalid,
    COUNT(*)                                             AS n_stays,
    COUNTIF(i.patientunitstayid IS NOT NULL)             AS n_stays_with_io,
    ROUND(COUNTIF(i.patientunitstayid IS NOT NULL) / COUNT(*), 3) AS io_coverage
FROM stays s
LEFT JOIN io_stays i USING (patientunitstayid)
GROUP BY s.hospitalid
HAVING n_stays >= 100
ORDER BY io_coverage DESC;


-- ---------------------------------------------------------------------------
-- A3.  Is I/O recorded densely enough in the first 24h to compute a VELOCITY?
--      A cumulative total at one timepoint gives volume, not rate. We need
--      several timepoints per stay.
--
--      DECISION RULE: median >= 6 records in the first 24h. Below that,
--      "velocity" is not measurable and the whole premise (rate vs. total)
--      collapses into the already-published total-balance literature.
-- ---------------------------------------------------------------------------
WITH per_stay AS (
    SELECT
        patientunitstayid,
        COUNTIF(intakeoutputoffset BETWEEN 0 AND 1440) AS n_first24h
    FROM `physionet-data.eicu_crd.intakeoutput`
    GROUP BY patientunitstayid
)
SELECT
    COUNT(*)                                              AS n_stays_with_io,
    APPROX_QUANTILES(n_first24h, 100)[OFFSET(25)]         AS p25,
    APPROX_QUANTILES(n_first24h, 100)[OFFSET(50)]         AS median,
    APPROX_QUANTILES(n_first24h, 100)[OFFSET(75)]         AS p75,
    COUNTIF(n_first24h >= 6) / COUNT(*)                   AS frac_ge_6_records
FROM per_stay;


-- ---------------------------------------------------------------------------
-- A4.  Septic shock cohort size. apacheadmissiondx carries explicit sepsis
--      categories, which is cleaner than ICD mining in the diagnosis table.
-- ---------------------------------------------------------------------------
SELECT
    apacheadmissiondx,
    COUNT(*) AS n
FROM `physionet-data.eicu_crd.patient`
WHERE LOWER(apacheadmissiondx) LIKE '%sepsis%'
GROUP BY apacheadmissiondx
ORDER BY n DESC;


-- ---------------------------------------------------------------------------
-- A5.  Renal endpoint feasibility. Delayed renal recovery needs SERIAL
--      creatinine, and a baseline. eICU rarely has pre-admission creatinine,
--      so baseline is normally back-calculated -- but we still need enough
--      in-stay measurements to define a peak and a trajectory.
--
--      DECISION RULE: median >= 3 creatinine values per septic stay.
-- ---------------------------------------------------------------------------
WITH cr AS (
    SELECT patientunitstayid, COUNT(*) AS n_creat
    FROM `physionet-data.eicu_crd.lab`
    WHERE labname = 'creatinine'
      AND labresultoffset BETWEEN -1440 AND 10080   -- admission-1d to day 7
    GROUP BY patientunitstayid
)
SELECT
    COUNT(*)                                     AS n_stays_with_creat,
    APPROX_QUANTILES(n_creat, 100)[OFFSET(50)]   AS median_n_creat,
    COUNTIF(n_creat >= 3) / COUNT(*)             AS frac_ge_3
FROM cr;


-- ###########################################################################
-- OPTION B -- TREATMENT LIMITATION IN CRITICALLY ILL CANCER PATIENTS
-- ###########################################################################

-- ---------------------------------------------------------------------------
-- B1.  What does careplangeneral actually contain? Vocabulary first --
--      we must not assume the coding scheme. Small table, cheap.
-- ---------------------------------------------------------------------------
SELECT
    cplgroup,
    COUNT(*)                          AS n,
    COUNT(DISTINCT patientunitstayid) AS n_stays
FROM `physionet-data.eicu_crd.careplangeneral`
GROUP BY cplgroup
ORDER BY n DESC;


-- ---------------------------------------------------------------------------
-- B2.  The care-limitation vocabulary specifically. This defines the exposure.
-- ---------------------------------------------------------------------------
SELECT
    cplgroup,
    cplitemvalue,
    COUNT(*)                          AS n,
    COUNT(DISTINCT patientunitstayid) AS n_stays
FROM `physionet-data.eicu_crd.careplangeneral`
WHERE LOWER(cplgroup) LIKE '%care limitation%'
   OR LOWER(cplitemvalue) LIKE '%resuscitat%'
   OR LOWER(cplitemvalue) LIKE '%comfort%'
   OR LOWER(cplitemvalue) LIKE '%full therapy%'
   OR LOWER(cplitemvalue) LIKE '%no cpr%'
   OR LOWER(cplitemvalue) LIKE '%end of life%'
GROUP BY cplgroup, cplitemvalue
ORDER BY n DESC
LIMIT 200;


-- ---------------------------------------------------------------------------
-- B3.  Cancer cohort size, from validated APACHE comorbidity flags
--      (no ICD mining needed). This is the population.
-- ---------------------------------------------------------------------------
SELECT
    COUNT(*)                                                       AS n_with_apachepredvar,
    COUNTIF(metastaticcancer = 1)                                  AS n_metastatic,
    COUNTIF(leukemia = 1)                                          AS n_leukemia,
    COUNTIF(lymphoma = 1)                                          AS n_lymphoma,
    COUNTIF(immunosuppression = 1)                                 AS n_immunosuppressed,
    COUNTIF(metastaticcancer = 1 OR leukemia = 1 OR lymphoma = 1)  AS n_any_cancer
FROM `physionet-data.eicu_crd.apachepredvar`;


-- ---------------------------------------------------------------------------
-- B4.  *** THE CRITICAL PROBE FOR OPTION B ***
--      Is limitation documented consistently ACROSS hospitals, or is it a
--      handful of sites? The between-hospital design needs real spread in a
--      decent number of sites -- if only a few hospitals document it, the
--      variation we would be "discovering" is just documentation artifact.
--
--      DECISION RULE: >= 40 hospitals each with >= 100 stays AND a
--      limitation-documentation rate strictly between 5% and 95%.
--      Sites at 0% or 100% are documenting policy, not decisions.
-- ---------------------------------------------------------------------------
WITH stays AS (
    SELECT patientunitstayid, hospitalid
    FROM `physionet-data.eicu_crd.patient`
),
lim AS (
    SELECT DISTINCT patientunitstayid
    FROM `physionet-data.eicu_crd.careplangeneral`
    WHERE LOWER(cplgroup) LIKE '%care limitation%'
)
SELECT
    s.hospitalid,
    COUNT(*)                                     AS n_stays,
    COUNTIF(l.patientunitstayid IS NOT NULL)     AS n_with_limitation,
    ROUND(COUNTIF(l.patientunitstayid IS NOT NULL) / COUNT(*), 3) AS limitation_rate
FROM stays s
LEFT JOIN lim l USING (patientunitstayid)
GROUP BY s.hospitalid
HAVING n_stays >= 100
ORDER BY limitation_rate DESC;


-- ---------------------------------------------------------------------------
-- B4b. careplaneol as a SECOND source for end-of-life documentation.
--      Caution: this is one of the smallest tables in eICU and is expected
--      to be sparse. Probing it tells us whether it can support anything or
--      is only a corroborating signal for careplangeneral.
--
--      DECISION RULE: treat as primary only if it covers >= 5% of stays
--      across >= 20 hospitals. Otherwise it is a sensitivity check at best.
-- ---------------------------------------------------------------------------
SELECT
    COUNT(*)                                  AS n_rows,
    COUNT(DISTINCT patientunitstayid)         AS n_stays,
    COUNT(DISTINCT p.hospitalid)              AS n_hospitals
FROM `physionet-data.eicu_crd.careplaneol` e
JOIN `physionet-data.eicu_crd.patient` p USING (patientunitstayid);


-- ---------------------------------------------------------------------------
-- B4c. Cancer ascertainment: do the three available sources agree?
--      APACHE comorbidity flags are validated and structured, but they are
--      recorded for APACHE scoring purposes and may under-capture. diagnosis
--      and pasthistory are free-text/ICD and may over-capture (e.g. "history
--      of" vs active disease). Disagreement between them is itself a finding
--      worth reporting, and it decides which we use as primary.
-- ---------------------------------------------------------------------------
WITH apache_cancer AS (
    SELECT DISTINCT patientunitstayid
    FROM `physionet-data.eicu_crd.apachepredvar`
    WHERE metastaticcancer = 1 OR leukemia = 1 OR lymphoma = 1
),
dx_cancer AS (
    SELECT DISTINCT patientunitstayid
    FROM `physionet-data.eicu_crd.diagnosis`
    WHERE LOWER(diagnosisstring) LIKE '%oncolog%'
       OR LOWER(diagnosisstring) LIKE '%malignan%'
       OR LOWER(diagnosisstring) LIKE '%carcinom%'
       OR LOWER(diagnosisstring) LIKE '%leukemi%'
       OR LOWER(diagnosisstring) LIKE '%lymphom%'
       OR LOWER(diagnosisstring) LIKE '%metasta%'
),
ph_cancer AS (
    SELECT DISTINCT patientunitstayid
    FROM `physionet-data.eicu_crd.pasthistory`
    WHERE LOWER(pasthistorypath)  LIKE '%cancer%'
       OR LOWER(pasthistoryvalue) LIKE '%cancer%'
       OR LOWER(pasthistoryvalue) LIKE '%malignan%'
)
SELECT
    COUNTIF(a.patientunitstayid IS NOT NULL) AS n_apache_flag,
    COUNTIF(d.patientunitstayid IS NOT NULL) AS n_diagnosis,
    COUNTIF(h.patientunitstayid IS NOT NULL) AS n_pasthistory,
    COUNTIF(a.patientunitstayid IS NOT NULL
        AND d.patientunitstayid IS NOT NULL) AS n_apache_and_dx,
    COUNTIF(a.patientunitstayid IS NOT NULL
         OR d.patientunitstayid IS NOT NULL
         OR h.patientunitstayid IS NOT NULL) AS n_any_source
FROM `physionet-data.eicu_crd.patient` p
LEFT JOIN apache_cancer a USING (patientunitstayid)
LEFT JOIN dx_cancer     d USING (patientunitstayid)
LEFT JOIN ph_cancer     h USING (patientunitstayid);


-- ---------------------------------------------------------------------------
-- B5.  The headline cross-tab, in miniature. Does APACHE IVa under-predict
--      death in cancer patients, and does that gap differ by whether
--      treatment was limited? If the observed-minus-predicted gap is much
--      larger in the limited group, the mechanism hypothesis has legs.
--
--      This is a PEEK, not the analysis -- no adjustment, no clustering.
-- ---------------------------------------------------------------------------
WITH base AS (
    SELECT
        a.patientunitstayid,
        (v.metastaticcancer = 1 OR v.leukemia = 1 OR v.lymphoma = 1) AS cancer,
        a.predictedhospitalmortality,
        a.actualhospitalmortality
    FROM `physionet-data.eicu_crd.apachepatientresult` a
    JOIN `physionet-data.eicu_crd.apachepredvar` v USING (patientunitstayid)
    WHERE a.apacheversion = 'IVa'
      AND a.predictedhospitalmortality > 0
),
lim AS (
    SELECT DISTINCT patientunitstayid
    FROM `physionet-data.eicu_crd.careplangeneral`
    WHERE LOWER(cplgroup) LIKE '%care limitation%'
)
SELECT
    b.cancer,
    l.patientunitstayid IS NOT NULL         AS limitation_documented,
    COUNT(*)                                AS n,
    ROUND(AVG(b.predictedhospitalmortality), 4) AS mean_predicted,
    ROUND(AVG(b.actualhospitalmortality), 4)    AS mean_observed,
    ROUND(SAFE_DIVIDE(AVG(b.actualhospitalmortality),
                      AVG(b.predictedhospitalmortality)), 3) AS smr
FROM base b
LEFT JOIN lim l USING (patientunitstayid)
GROUP BY b.cancer, limitation_documented
ORDER BY b.cancer, limitation_documented;
