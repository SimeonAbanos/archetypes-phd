-- Q4. Which categories of criteria the class of the case rests on: for every class and
-- category (the first word of its name - clinical, laboratory, epidemiological, diagnostic),
-- the number of notices with at least one ticked criterion in that category.
-- The notice does not store the category of a ticked criterion. It is found the way the
-- application finds it: the last category (type 1) of the disease that begins at or before
-- the place of the criterion (seq) in the tree of criteria. A category without a number in
-- Annex 3, or a notice without the number of its disease, gives no code, and the instance does
-- not carry such a category. Words are compared exactly (binary collation), as in XQuery.
SET time_zone = '+00:00';
SELECT n.degree_id                                              AS class_code,
       SUBSTRING_INDEX(cat.name, ' ', 1) COLLATE utf8mb4_bin    AS category,
       COUNT(DISTINCT n.id)                                     AS notices
FROM t_patient_notifications n
JOIN t_patient_notification_criteria pc ON pc.notification_id = n.id
JOIN t_d_criteria cat
  ON cat.d_id = n.disease_id
 AND cat.type = 1
 AND cat.seq = (SELECT MAX(c2.seq)
                  FROM t_d_criteria c2
                 WHERE c2.d_id = n.disease_id
                   AND c2.type = 1
                   AND c2.seq <= pc.d_seq)
 AND TRIM(COALESCE(cat.p3_path, '')) <> ''
 AND TRIM(COALESCE(n.d_code, '')) <> ''
GROUP BY class_code, category
ORDER BY class_code, category;
