(: Q3. Pertussis (number 30 in Annex 1) in 2025: notices by month of classification and by
   class of the case. :)
declare namespace n = "http://EN13606-RM.xsd";
string-join(
  for $notice in collection('/db/notifications')/n:InfectiousDiseaseCaseNotification
                 [n:SECTION-DISEASE/n:ENTRY-DISEASE/n:DISEASE.CODE/n:codeValue = '30']
  let $entry := $notice/n:SECTION-CASE.CLASSIFICATION/n:ENTRY-CASE.CLASS
  let $date := xs:date($entry/n:CLASSIFICATION.DATE/n:date)
  where year-from-date($date) = 2025
  let $month := month-from-date($date)
  let $class := string($entry/n:CASE.CLASS/n:codeValue)
  group by $month, $class
  order by $month, $class
  return string-join((string($month), $class, string(count($notice))), '&#9;'),
  '&#10;')
