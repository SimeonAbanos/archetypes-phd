-- Q2. Notices by disease: number in Annex 1 of Ordinance No 21, ICD-10 code (empty where the
-- disease has no reliable match) and number of notices.
SET time_zone = '+00:00';
SELECT COALESCE(TRIM(n.d_code), '') AS annex1_number,
       COALESCE(TRIM(d.icd), '')    AS icd10,
       COUNT(*)                     AS notices
FROM t_patient_notifications n
LEFT JOIN t_diseases d ON d.id = n.disease_id
GROUP BY annex1_number, icd10
ORDER BY annex1_number;
