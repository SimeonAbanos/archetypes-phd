-- Q5. Notices by class of the case and by age group of the person at the date of
-- classification (full years): 00-04, 05-14, 15-24, 25-44, 45-64, 65+. A birth date the
-- database cannot turn into an age shows as 'unknown', so that it is not hidden in a group.
SET time_zone = '+00:00';
SELECT x.class_code,
       CASE WHEN x.age IS NULL THEN 'unknown'
            WHEN x.age < 5  THEN '00-04'
            WHEN x.age < 15 THEN '05-14'
            WHEN x.age < 25 THEN '15-24'
            WHEN x.age < 45 THEN '25-44'
            WHEN x.age < 65 THEN '45-64'
            ELSE '65+' END AS age_group,
       COUNT(*) AS notices
FROM (SELECT n.degree_id AS class_code,
             TIMESTAMPDIFF(YEAR, p.dob, DATE(n.field_created)) AS age
        FROM t_patient_notifications n
        JOIN t_patients p ON p.id = n.p_id
       WHERE CAST(p.dob AS CHAR) <> '0000-00-00') x
GROUP BY x.class_code, age_group
ORDER BY x.class_code, age_group;
