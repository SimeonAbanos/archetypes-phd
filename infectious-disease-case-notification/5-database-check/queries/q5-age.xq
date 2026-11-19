(: Q5. Notices by class of the case and by age group of the person at the date of
   classification (full years): 00-04, 05-14, 15-24, 25-44, 45-64, 65+. :)
declare namespace n = "http://EN13606-RM.xsd";
declare function local:age($birth as xs:date, $on as xs:date) as xs:integer {
  year-from-date($on) - year-from-date($birth)
  - (if (month-from-date($on) * 100 + day-from-date($on)
         lt month-from-date($birth) * 100 + day-from-date($birth)) then 1 else 0)
};
string-join(
  for $notice in collection('/db/notifications')/n:InfectiousDiseaseCaseNotification
  let $birth := $notice/n:SECTION-SUBJECT/n:ENTRY-PERSON/n:BIRTH.DATE/n:date
  let $entry := $notice/n:SECTION-CASE.CLASSIFICATION/n:ENTRY-CASE.CLASS
  let $on := $entry/n:CLASSIFICATION.DATE/n:date
  where exists($birth) and exists($on)
  let $age := local:age(xs:date($birth), xs:date($on))
  let $group := if ($age lt 5) then '00-04' else if ($age lt 15) then '05-14'
                else if ($age lt 25) then '15-24' else if ($age lt 45) then '25-44'
                else if ($age lt 65) then '45-64' else '65+'
  let $class := string($entry/n:CASE.CLASS/n:codeValue)
  group by $class, $group
  order by $class, $group
  return string-join(($class, $group, string(count($notice))), '&#9;'),
  '&#10;')
