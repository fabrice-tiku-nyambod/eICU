-- ===========================================================================
-- 00_access_probe.sql
-- Confirms BigQuery access and maps the vocabulary we need, at near-zero cost.
-- Run these ONE AT A TIME in the console. Check the "This query will process
-- N bytes" estimate in the top-right before every run.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- Q1. Access check.  COUNT(*) reads table metadata only -> 0 bytes scanned.
--     Expect roughly: demo 2,520 stays / full 200,859 stays.
-- ---------------------------------------------------------------------------
SELECT 'demo' AS src, COUNT(*) AS n_unit_stays FROM `physionet-data.eicu_crd_demo.patient`
UNION ALL
SELECT 'full', COUNT(*)                        FROM `physionet-data.eicu_crd.patient`;


-- ---------------------------------------------------------------------------
-- Q2. Row counts of the tables Study A depends on. Still 0 bytes.
--     Confirms the scale we are budgeting against.
-- ---------------------------------------------------------------------------
SELECT 'nursecharting'  AS tbl, COUNT(*) AS n FROM `physionet-data.eicu_crd.nursecharting`
UNION ALL SELECT 'vitalperiodic',  COUNT(*)   FROM `physionet-data.eicu_crd.vitalperiodic`
UNION ALL SELECT 'vitalaperiodic', COUNT(*)   FROM `physionet-data.eicu_crd.vitalaperiodic`
ORDER BY n DESC;


-- ---------------------------------------------------------------------------
-- Q3. What vital-sign vocabulary does nursecharting actually use?
--     DEMO ONLY -- this scans real columns, so keep it off the full table
--     until we know exactly which labels we want.
--     nursecharting is EAV/tall: category -> label -> name -> value.
-- ---------------------------------------------------------------------------
SELECT
    nursingchartcelltypecat   AS category,
    nursingchartcelltypevallabel AS label,
    nursingchartcelltypevalname  AS name,
    COUNT(*)                  AS n
FROM `physionet-data.eicu_crd_demo.nursecharting`
WHERE nursingchartcelltypecat = 'Vital Signs'
GROUP BY category, label, name
ORDER BY n DESC
LIMIT 100;


-- ---------------------------------------------------------------------------
-- Q4. Sanity-check the value format for the four parameters of interest.
--     nursingchartvalue is a STRING -- we need to know how dirty it is before
--     writing the cast. DEMO ONLY.
-- ---------------------------------------------------------------------------
SELECT
    nursingchartcelltypevallabel AS label,
    COUNTIF(SAFE_CAST(nursingchartvalue AS FLOAT64) IS NULL) AS n_uncastable,
    COUNT(*)                                                 AS n_total,
    MIN(SAFE_CAST(nursingchartvalue AS FLOAT64))             AS min_val,
    MAX(SAFE_CAST(nursingchartvalue AS FLOAT64))             AS max_val
FROM `physionet-data.eicu_crd_demo.nursecharting`
WHERE nursingchartcelltypecat = 'Vital Signs'
GROUP BY label
ORDER BY n_total DESC;


-- ---------------------------------------------------------------------------
-- Q5. Charting lag, straight away -- entryoffset minus offset.
--     This is Secondary Objective 3 and is cheap enough to peek at on demo.
--     A large positive lag means the value was typed in well after the time
--     it is attributed to (retrospective charting).
-- ---------------------------------------------------------------------------
SELECT
    APPROX_QUANTILES(nursingchartentryoffset - nursingchartoffset, 100)[OFFSET(10)] AS p10_min,
    APPROX_QUANTILES(nursingchartentryoffset - nursingchartoffset, 100)[OFFSET(50)] AS median_min,
    APPROX_QUANTILES(nursingchartentryoffset - nursingchartoffset, 100)[OFFSET(90)] AS p90_min,
    COUNTIF(nursingchartentryoffset - nursingchartoffset > 60) / COUNT(*)           AS frac_over_1h
FROM `physionet-data.eicu_crd_demo.nursecharting`
WHERE nursingchartcelltypecat = 'Vital Signs';
