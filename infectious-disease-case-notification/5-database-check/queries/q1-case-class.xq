(: Q1. Notices by class of the case: code, name and number of notices. :)
declare namespace n = "http://EN13606-RM.xsd";
string-join(
  for $class in collection('/db/notifications')/n:InfectiousDiseaseCaseNotification
                //n:ENTRY-CASE.CLASS/n:CASE.CLASS
  let $code := string($class/n:codeValue)
  group by $code
  order by $code
  return string-join(($code, string(($class/n:displayName)[1]), string(count($class))), '&#9;'),
  '&#10;')
