(: Q4. Which categories of criteria the class of the case rests on: for every class and
   category (the first word of its name - clinical, laboratory, epidemiological, diagnostic),
   the number of notices with at least one ticked criterion in that category.
   The instance carries the category of every ground as a coded value. :)
declare namespace n = "http://EN13606-RM.xsd";
string-join(
  for $entry in collection('/db/notifications')/n:InfectiousDiseaseCaseNotification
                /n:SECTION-CASE.CLASSIFICATION/n:ENTRY-CASE.CLASS
  let $class := string($entry/n:CASE.CLASS/n:codeValue)
  for $category in distinct-values(
      for $name in $entry/n:GROUNDS/n:CRITERION.CATEGORY/n:displayName
      return tokenize(normalize-space($name), ' ')[1])
  group by $class, $category
  order by $class, $category
  return string-join(($class, $category, string(count($entry))), '&#9;'),
  '&#10;')
