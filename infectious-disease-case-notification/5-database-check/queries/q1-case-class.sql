-- Q1. Notices by class of the case: code, name and number of notices.
SET time_zone = '+00:00';
SELECT n.degree_id AS class_code,
       g.name      AS class_name,
       COUNT(*)    AS notices
FROM t_patient_notifications n
JOIN t_d_degree g ON g.id = n.degree_id
GROUP BY n.degree_id, g.name
ORDER BY n.degree_id;
