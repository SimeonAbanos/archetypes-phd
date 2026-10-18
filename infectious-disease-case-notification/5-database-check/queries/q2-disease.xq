(: Q2. Notices by disease: number in Annex 1 of Ordinance No 21, ICD-10 code (empty where the
   disease has no reliable match) and number of notices. :)
declare namespace n = "http://EN13606-RM.xsd";
string-join(
  for $disease in collection('/db/notifications')/n:InfectiousDiseaseCaseNotification
                  /n:SECTION-DISEASE/n:ENTRY-DISEASE
  let $number := string($disease/n:DISEASE.CODE/n:codeValue)
  let $icd := string($disease/n:MKB/n:codeValue)
  group by $number, $icd
  order by $number
  return string-join(($number, $icd, string(count($disease))), '&#9;'),
  '&#10;')
