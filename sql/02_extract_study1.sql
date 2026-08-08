-- ===========================================================================
-- 02_extract_study1.sql
-- Study 1: treatment limitation in critically ill patients with metastatic
-- solid tumour or haematologic malignancy -- eICU-CRD v2.0, 208 US ICUs.
--
-- All output is AGGREGATE ONLY -- safe to save locally under the DUA.
-- Run one at a time (Ctrl+A before pasting). Watch the bytes estimate.
--
-- Cohort definition throughout:
--   cancer = apachepredvar.metastaticcancer=1 OR leukemia=1 OR lymphoma=1
--   NOTE: this excludes non-metastatic solid tumours and carries no primary
--   site. The paper must call this "metastatic solid tumour or haematologic
--   malignancy", not "cancer".
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- Q1. FLOW DIAGRAM counts. Every number re-derived, none hand-typed.
-- ---------------------------------------------------------------------------
SELECT 'all unit stays' AS step, COUNT(*) AS n
FROM `physionet-data.eicu_crd.patient`
UNION ALL
SELECT 'has apachepredvar', COUNT(*)
FROM `physionet-data.eicu_crd.apachepredvar`
UNION ALL
SELECT 'has APACHE IVa result', COUNT(*)
FROM `physionet-data.eicu_crd.apachepatientresult`
WHERE apacheversion = 'IVa'
UNION ALL
SELECT 'IVa with valid predicted mortality', COUNT(*)
FROM `physionet-data.eicu_crd.apachepatientresult`
WHERE apacheversion = 'IVa'
  AND SAFE_CAST(predictedhospitalmortality AS FLOAT64) > 0
UNION ALL
SELECT 'analysable (IVa + predvar + valid pred)', COUNT(*)
FROM `physionet-data.eicu_crd.apachepatientresult` a
JOIN `physionet-data.eicu_crd.apachepredvar` v USING (patientunitstayid)
WHERE a.apacheversion = 'IVa'
  AND SAFE_CAST(a.predictedhospitalmortality AS FLOAT64) > 0
UNION ALL
SELECT 'of those, cancer', COUNT(*)
FROM `physionet-data.eicu_crd.apachepatientresult` a
JOIN `physionet-data.eicu_crd.apachepredvar` v USING (patientunitstayid)
WHERE a.apacheversion = 'IVa'
  AND SAFE_CAST(a.predictedhospitalmortality AS FLOAT64) > 0
  AND (v.metastaticcancer = 1 OR v.leukemia = 1 OR v.lymphoma = 1);


-- ---------------------------------------------------------------------------
-- Q2. TABLE 1 -- cohort characteristics by cancer status.
--     age is a STRING in eICU with '> 89' for the top group -> mapped to 90.
-- ---------------------------------------------------------------------------
WITH base AS (
    SELECT
        p.patientunitstayid,
        p.hospitalid,
        (v.metastaticcancer = 1 OR v.leukemia = 1 OR v.lymphoma = 1) AS cancer,
        CASE WHEN p.age = '> 89' THEN 90 ELSE SAFE_CAST(p.age AS INT64) END AS age_num,
        p.gender,
        p.unittype,
        p.unitadmitsource,
        SAFE_CAST(a.apachescore AS FLOAT64) AS apachescore,
        SAFE_CAST(a.predictedhospitalmortality AS FLOAT64) AS pred,
        CASE WHEN UPPER(CAST(a.actualhospitalmortality AS STRING)) = 'EXPIRED'
             THEN 1 ELSE 0 END AS died,
        p.unitdischargeoffset / 1440.0 AS icu_los_days
    FROM `physionet-data.eicu_crd.patient` p
    JOIN `physionet-data.eicu_crd.apachepatientresult` a USING (patientunitstayid)
    JOIN `physionet-data.eicu_crd.apachepredvar` v USING (patientunitstayid)
    WHERE a.apacheversion = 'IVa'
)
SELECT
    cancer,
    COUNT(*)                                             AS n,
    COUNT(DISTINCT hospitalid)                           AS n_hospitals,
    ROUND(AVG(age_num), 1)                               AS mean_age,
    ROUND(COUNTIF(gender = 'Female') / COUNT(*), 3)      AS prop_female,
    ROUND(AVG(apachescore), 1)                           AS mean_apache_score,
    ROUND(AVG(pred), 4)                                  AS mean_predicted_mort,
    ROUND(AVG(died), 4)                                  AS observed_mort,
    ROUND(APPROX_QUANTILES(icu_los_days, 100)[OFFSET(50)], 2) AS median_icu_los_d
FROM base
WHERE pred > 0
GROUP BY cancer
ORDER BY cancer;


-- ---------------------------------------------------------------------------
-- Q3. Cancer subgroup breakdown -- the three APACHE flags are not exclusive.
-- ---------------------------------------------------------------------------
SELECT
    COUNTIF(v.metastaticcancer = 1)                       AS metastatic_solid,
    COUNTIF(v.leukemia = 1)                               AS leukemia,
    COUNTIF(v.lymphoma = 1)                               AS lymphoma,
    COUNTIF(v.immunosuppression = 1)                      AS immunosuppressed,
    COUNTIF(v.metastaticcancer = 1 AND (v.leukemia = 1 OR v.lymphoma = 1)) AS overlap,
    COUNTIF(v.metastaticcancer = 1 OR v.leukemia = 1 OR v.lymphoma = 1)    AS any_cancer
FROM `physionet-data.eicu_crd.apachepatientresult` a
JOIN `physionet-data.eicu_crd.apachepredvar` v USING (patientunitstayid)
WHERE a.apacheversion = 'IVa'
  AND SAFE_CAST(a.predictedhospitalmortality AS FLOAT64) > 0;


-- ---------------------------------------------------------------------------
-- Q4. TIMING -- how quickly does limitation appear, and does it differ by
--     cancer status? This is Secondary Aim 1 and is not yet in hand.
--     Offsets are minutes from unit admission; negatives are possible.
-- ---------------------------------------------------------------------------
WITH base AS (
    SELECT
        a.patientunitstayid,
        (v.metastaticcancer = 1 OR v.leukemia = 1 OR v.lymphoma = 1) AS cancer
    FROM `physionet-data.eicu_crd.apachepatientresult` a
    JOIN `physionet-data.eicu_crd.apachepredvar` v USING (patientunitstayid)
    WHERE a.apacheversion = 'IVa'
      AND SAFE_CAST(a.predictedhospitalmortality AS FLOAT64) > 0
),
firstlim AS (
    SELECT
        patientunitstayid,
        MIN(cplitemoffset) AS first_lim_offset
    FROM `physionet-data.eicu_crd.careplangeneral`
    WHERE LOWER(cplgroup) LIKE '%care limitation%'
      AND cplitemvalue != 'Full therapy'
    GROUP BY patientunitstayid
)
SELECT
    b.cancer,
    COUNT(*)                                                  AS n_with_limitation,
    APPROX_QUANTILES(f.first_lim_offset, 100)[OFFSET(25)]     AS p25_minutes,
    APPROX_QUANTILES(f.first_lim_offset, 100)[OFFSET(50)]     AS median_minutes,
    APPROX_QUANTILES(f.first_lim_offset, 100)[OFFSET(75)]     AS p75_minutes,
    ROUND(COUNTIF(f.first_lim_offset <= 1440) / COUNT(*), 3)  AS frac_within_24h,
    ROUND(COUNTIF(f.first_lim_offset <= 60) / COUNT(*), 3)    AS frac_within_1h
FROM base b
JOIN firstlim f USING (patientunitstayid)
GROUP BY b.cancer
ORDER BY b.cancer;


-- ---------------------------------------------------------------------------
-- Q5. Patient factors associated with early limitation, by age band.
--     Descriptive cross-tab, not a model.
-- ---------------------------------------------------------------------------
WITH base AS (
    SELECT
        a.patientunitstayid,
        (v.metastaticcancer = 1 OR v.leukemia = 1 OR v.lymphoma = 1) AS cancer,
        CASE
            WHEN p.age = '> 89' THEN '90+'
            WHEN SAFE_CAST(p.age AS INT64) < 50 THEN '<50'
            WHEN SAFE_CAST(p.age AS INT64) < 65 THEN '50-64'
            WHEN SAFE_CAST(p.age AS INT64) < 80 THEN '65-79'
            ELSE '80-89' END AS age_band
    FROM `physionet-data.eicu_crd.patient` p
    JOIN `physionet-data.eicu_crd.apachepatientresult` a USING (patientunitstayid)
    JOIN `physionet-data.eicu_crd.apachepredvar` v USING (patientunitstayid)
    WHERE a.apacheversion = 'IVa'
      AND SAFE_CAST(a.predictedhospitalmortality AS FLOAT64) > 0
),
lim AS (
    SELECT DISTINCT patientunitstayid
    FROM `physionet-data.eicu_crd.careplangeneral`
    WHERE LOWER(cplgroup) LIKE '%care limitation%'
      AND cplitemvalue != 'Full therapy'
      AND cplitemoffset <= 1440
)
SELECT
    b.cancer,
    b.age_band,
    COUNT(*)                                              AS n,
    ROUND(COUNTIF(l.patientunitstayid IS NOT NULL) / COUNT(*), 3) AS limitation_rate
FROM base b
LEFT JOIN lim l USING (patientunitstayid)
WHERE b.age_band IS NOT NULL
GROUP BY b.cancer, b.age_band
ORDER BY b.cancer, b.age_band;
