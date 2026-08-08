-- ===========================================================================
-- 02_build_analytic_dataset.sql
--
-- Builds the one-row-per-unit-stay analytic dataset for the code-status /
-- calibration study. Run this, then "Save results -> CSV (local file)" and
-- drop it in the project folder as data_private/analytic.csv
--
-- DUA NOTE: this output is patient-level. It may live on your machine, it may
-- NOT be committed to git, shared, or uploaded anywhere. .gitignore already
-- blocks data_private/ and *.csv.
--
-- Cost: names every column explicitly, joins five modest tables. Well under
-- 1 GB. `careplangeneral` is ~30 MB compressed and is the only wide scan.
-- ===========================================================================

WITH
-- ---------------------------------------------------------------------------
-- Most restrictive care limitation documented in the first 24h.
-- MAX() over the ordinal tier gives "most restrictive", since the scale is
-- monotone in restrictiveness.
-- ---------------------------------------------------------------------------
lim24 AS (
    SELECT
        patientunitstayid,
        MAX(CASE
            WHEN cplitemvalue = 'Comfort measures only' THEN 4
            WHEN cplitemvalue IN ('No augmentation of care','No vasopressors/inotropes',
                                  'No blood products','No blood draws') THEN 3
            WHEN cplitemvalue IN ('Do not resuscitate','No CPR','No intubation',
                                  'No cardioversion') THEN 2
            WHEN cplitemvalue = 'Full therapy' THEN 1
            ELSE 0 END)                                   AS lim_tier_24h,
        MIN(cplitemoffset)                                AS first_cpl_offset,
        MIN(CASE WHEN cplitemvalue != 'Full therapy'
                 THEN cplitemoffset END)                  AS first_limitation_offset
    FROM `physionet-data.eicu_crd.careplangeneral`
    WHERE LOWER(cplgroup) LIKE '%care limitation%'
      AND cplitemoffset <= 1440
    GROUP BY patientunitstayid
),

-- ---------------------------------------------------------------------------
-- Most restrictive limitation at ANY point in the stay -- used to describe how
-- code status deepens after the first 24h (secondary aim 4).
-- ---------------------------------------------------------------------------
lim_any AS (
    SELECT
        patientunitstayid,
        MAX(CASE
            WHEN cplitemvalue = 'Comfort measures only' THEN 4
            WHEN cplitemvalue IN ('No augmentation of care','No vasopressors/inotropes',
                                  'No blood products','No blood draws') THEN 3
            WHEN cplitemvalue IN ('Do not resuscitate','No CPR','No intubation',
                                  'No cardioversion') THEN 2
            WHEN cplitemvalue = 'Full therapy' THEN 1
            ELSE 0 END)                                   AS lim_tier_ever
    FROM `physionet-data.eicu_crd.careplangeneral`
    WHERE LOWER(cplgroup) LIKE '%care limitation%'
    GROUP BY patientunitstayid
),

-- ---------------------------------------------------------------------------
-- Cancer ascertainment from the free-text diagnosis table, for the
-- concordance sensitivity analysis (Table S1). NOT the primary definition.
-- ---------------------------------------------------------------------------
dx_cancer AS (
    SELECT DISTINCT patientunitstayid, 1 AS dx_cancer_flag
    FROM `physionet-data.eicu_crd.diagnosis`
    WHERE LOWER(diagnosisstring) LIKE '%malignan%'
       OR LOWER(diagnosisstring) LIKE '%carcinom%'
       OR LOWER(diagnosisstring) LIKE '%leukemi%'
       OR LOWER(diagnosisstring) LIKE '%lymphom%'
       OR LOWER(diagnosisstring) LIKE '%metasta%'
       OR LOWER(diagnosisstring) LIKE '%oncolog%'
)

SELECT
    -- identifiers -----------------------------------------------------------
    p.patientunitstayid,
    p.patienthealthsystemstayid,
    p.hospitalid,

    -- hospital characteristics ----------------------------------------------
    h.numbedscategory                                     AS hosp_beds,
    h.teachingstatus                                      AS hosp_teaching,
    h.region                                              AS hosp_region,

    -- demographics ----------------------------------------------------------
    SAFE_CAST(p.age AS INT64)                             AS age_num,
    CASE WHEN p.age = '> 89' THEN 1 ELSE 0 END            AS age_over_89,
    p.gender,
    p.ethnicity,
    p.unittype,
    p.unitadmitsource,
    p.apacheadmissiondx,

    -- exposure --------------------------------------------------------------
    COALESCE(l.lim_tier_24h, 0)                           AS lim_tier_24h,
    COALESCE(la.lim_tier_ever, 0)                         AS lim_tier_ever,
    l.first_cpl_offset,
    l.first_limitation_offset,

    -- cancer ----------------------------------------------------------------
    v.metastaticcancer,
    v.leukemia,
    v.lymphoma,
    v.immunosuppression,
    CASE WHEN v.metastaticcancer = 1 OR v.leukemia = 1 OR v.lymphoma = 1
         THEN 1 ELSE 0 END                                AS cancer_apache,
    COALESCE(d.dx_cancer_flag, 0)                         AS cancer_dx,

    -- other comorbidity, as model covariates --------------------------------
    v.cirrhosis,
    v.hepaticfailure,
    v.aids,
    v.diabetes,
    v.electivesurgery,
    v.readmit,
    v.ventday1,

    -- severity and outcome --------------------------------------------------
    a.apachescore,
    a.acutephysiologyscore,
    SAFE_CAST(a.predictedhospitalmortality AS FLOAT64)    AS pred_hosp_mort,
    CASE WHEN UPPER(CAST(a.actualhospitalmortality AS STRING)) = 'EXPIRED'
         THEN 1 ELSE 0 END                                AS died_hosp,
    SAFE_CAST(a.predictediculos AS FLOAT64)               AS pred_icu_los,
    SAFE_CAST(a.actualiculos AS FLOAT64)                  AS actual_icu_los,
    p.unitdischargeoffset,
    p.unitdischargestatus,
    p.hospitaldischargestatus

FROM `physionet-data.eicu_crd.patient` p
JOIN `physionet-data.eicu_crd.apachepatientresult` a
       ON a.patientunitstayid = p.patientunitstayid
      AND a.apacheversion = 'IVa'
JOIN `physionet-data.eicu_crd.apachepredvar`  v USING (patientunitstayid)
LEFT JOIN `physionet-data.eicu_crd.hospital`  h USING (hospitalid)
LEFT JOIN lim24     l  USING (patientunitstayid)
LEFT JOIN lim_any   la USING (patientunitstayid)
LEFT JOIN dx_cancer d  USING (patientunitstayid)
WHERE SAFE_CAST(a.predictedhospitalmortality AS FLOAT64) > 0;


-- ===========================================================================
-- Companion query: exclusion cascade for the CONSORT-style flow diagram.
-- Every count re-derived here rather than hand-typed into the figure.
-- Run separately; scans 0 bytes for the first row, little for the rest.
-- ===========================================================================
/*
WITH steps AS (
  SELECT 'a. all unit stays in eICU-CRD v2.0' AS step, COUNT(*) AS n
  FROM `physionet-data.eicu_crd.patient`
  UNION ALL
  SELECT 'b. with an APACHE IVa result', COUNT(DISTINCT p.patientunitstayid)
  FROM `physionet-data.eicu_crd.patient` p
  JOIN `physionet-data.eicu_crd.apachepatientresult` a
       ON a.patientunitstayid = p.patientunitstayid AND a.apacheversion = 'IVa'
  UNION ALL
  SELECT 'c. with valid predicted mortality (>0)', COUNT(DISTINCT p.patientunitstayid)
  FROM `physionet-data.eicu_crd.patient` p
  JOIN `physionet-data.eicu_crd.apachepatientresult` a
       ON a.patientunitstayid = p.patientunitstayid AND a.apacheversion = 'IVa'
  WHERE SAFE_CAST(a.predictedhospitalmortality AS FLOAT64) > 0
  UNION ALL
  SELECT 'd. linked to apachepredvar (analytic cohort)', COUNT(DISTINCT p.patientunitstayid)
  FROM `physionet-data.eicu_crd.patient` p
  JOIN `physionet-data.eicu_crd.apachepatientresult` a
       ON a.patientunitstayid = p.patientunitstayid AND a.apacheversion = 'IVa'
  JOIN `physionet-data.eicu_crd.apachepredvar` v
       ON v.patientunitstayid = p.patientunitstayid
  WHERE SAFE_CAST(a.predictedhospitalmortality AS FLOAT64) > 0
)
SELECT * FROM steps ORDER BY step;
*/
