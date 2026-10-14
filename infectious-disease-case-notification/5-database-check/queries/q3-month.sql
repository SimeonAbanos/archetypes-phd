-- Q3. Pertussis (number 30 in Annex 1) in 2025: notices by month of classification and by
-- class of the case. Dates are read in UTC, as the instances were exported.
SET time_zone = '+00:00';
SELECT MONTH(n.field_created) AS month,
       n.degree_id            AS class_code,
       COUNT(*)               AS notices
FROM t_patient_notifications n
WHERE n.d_code = '30'
  AND YEAR(n.field_created) = 2025
GROUP BY MONTH(n.field_created), n.degree_id
ORDER BY month, class_code;
