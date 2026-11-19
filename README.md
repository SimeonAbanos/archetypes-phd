# Archetypes of Clinical Concepts - Doctoral Thesis

The archetypes behind the doctoral thesis *Archetype-Oriented Modeling and Management of Clinical Data* by Simeon
Abanos, Faculty of Mathematics and Informatics, Sofia University St. Kliment Ohridski. The models follow EN ISO 13606
and the openEHR specifications. Each folder holds one model, its instances and a script that checks them.

An archetype describes one clinical concept, such as a body mass index measurement, as constraints on a generic
reference model: which parts a record has and which values they may take. An instance is a concrete record in XML. It is
valid when it conforms both to the reference model and to the archetype.

For readers new to archetypes, a Bulgarian description of how the models were built and checked is available in
[Архетипи, инстанции и проверка на валидността.docx](Архетипи,%20инстанции%20и%20проверка%20на%20валидността.docx).

| Folder | Framework | Root archetype | Origin |
| --- | --- | --- | --- |
| [`body-mass-index`](body-mass-index) | openEHR | `openEHR-EHR-COMPOSITION.anthropometry.v0` | based on the body mass index example in Krastev, Abanos and Tcharaktchiev (2022) |
| [`occupational-health-assessment-summary`](occupational-health-assessment-summary) | EN ISO 13606 | `CEN-EN13606-COMPOSITION.OccupationalHealthAssessmentSummary.v1` | published with Krastev et al. (2023) in E. Krastev's repository, here with updates |
| [`infectious-disease-case-notification`](infectious-disease-case-notification) | EN ISO 13606 | `CEN-EN13606-COMPOSITION.InfectiousDiseaseCaseNotification.v1` | built for the thesis, continuing Abanos et al. (2023) |
| [`ambulatory-list`](ambulatory-list) | EN ISO 13606 | `CEN-EN13606-COMPOSITION.AmbulatoryList.v1` | built for the thesis, after the method of Krastev et al. (2020) |

## Layout of a folder

Every folder has the same four subfolders:

| Subfolder | Holds |
| --- | --- |
| `1-reference-model` | the XML schemas of the reference model (RM) and its data types; in two folders only the data types |
| `2-archetypes` | the archetypes in ADL; in two folders also the XML schema derived from the archetype, in one the template, the operational template and the XML schema derived from it (TDS) |
| `3-instances` | the instances; in `body-mass-index` also `generation`, the scripts that produced the TDS and the valid instance |
| `4-validity-check` | the script that checks the instances, with its launchers |

In `infectious-disease-case-notification` a fifth subfolder, `5-database-check`, holds 3003 notices from the information
system twice, in a relational and in an XML database, with the queries that compare the two.

## Two steps of validity

1. **Structural validity** - the instance against the RM of its framework, EN ISO 13606-1 or openEHR, in
   `1-reference-model`. In `body-mass-index` the instance is checked against the TDS, which imports the RM and adds the
   structure of the template.
2. **Semantic validity** - the instance against the constraints of the archetype, or of the operational template where
   there is one, in `2-archetypes`. It checks the nodes - their codes, places and number of occurrences, and for EN ISO
   13606 also their classes - and the values.

The archetype itself is written in ADL as an instance of the Archetype Object Model (AOM). Its conformance to the AOM is
checked in the modelling tool (LinkEHR Studio for EN ISO 13606, Archetype Designer for openEHR), not by the scripts
here.

In `infectious-disease-case-notification` and `ambulatory-list` the XML schema is derived from the archetype. Such a
schema carries the RM and the archetype together, so one check covers both steps. It includes the data type schema, so
in these two folders `1-reference-model` holds only `TS14796-dataTypes.xsd`.

## Running the check

Every `4-validity-check` holds the same `validate.ps1` and the launchers that apply:

| Launcher | Runs |
| --- | --- |
| `validate-1-structural-rm.cmd` | step 1 |
| `validate-2-semantic-archetype.cmd` | step 2 |
| `validate-all.cmd` | step 1, then step 2 for the instances valid in step 1 |

Run a launcher on Windows. Each one runs `validate.ps1` with its own choice of steps. The script uses only what comes
with Windows PowerShell, so nothing has to be installed. It reads the XML schemas, the archetypes or the operational
template, and takes every other XML file in the model's folder, subfolders included, as an instance, which in practice
means the files in `3-instances`. It changes nothing.

The script compares each result with the one the file name states:

| Instance | Expected result |
| --- | --- |
| `instance-valid.xml` | valid in both steps |
| `instance-invalid-structural-rm.xml` | invalid in step 1 |
| `instance-invalid-semantic-archetype.xml` | valid in step 1, invalid in step 2 |

The three published instances in `occupational-health-assessment-summary` keep their original names; with the updates,
all three are valid in both steps. Where the XML schema is derived from the archetype there is one check, and both
invalid instances fail it.

## Publications

- Evgeniy Krastev, Simeon Abanos, Dimitar Tcharaktchiev, **Health Data Exchange Based on Archetypes of Clinical
  Concepts**, *Information Systems and Grid Technologies* (ISGT 2022), Sofia, Bulgaria, 27-28 May 2022, pp. 98-112.
  (CEUR-WS.org vol. 3191).
- Evgeniy Krastev, Dimitar Tcharaktchiev, Petko Kovachev, Simeon Abanos, **Occupational Health Assessment Summary
  Designed for Semantic Interoperability**, *International Journal of Medical Informatics*, vol. 178, 2023, Art.
  No. 105207. DOI: [10.1016/j.ijmedinf.2023.105207](https://doi.org/10.1016/j.ijmedinf.2023.105207). PMID: 37688835.
- Simeon Abanos, Evgeniy Krastev, Petko Kovachev, Dimitar Tcharaktchiev, **Modeling and Clinical Data Exchange in
  Registration of Infectious Disease Cases**, *Annual of Sofia University "St. Kliment Ohridski", FMI*, vol. 110, 2023,
  pp. 7-23. DOI: [10.60063/GSU.FMI.110.7-23](https://doi.org/10.60063/GSU.FMI.110.7-23).
- Evgeniy Krastev, Dimitar Tcharaktchiev, Kalinka Kaloyanova, Lyubomir Kirov, Petko Kovachev, Simeon Abanos, Nonka
  Mateva, **Standards Based Adaptation of Clinical Documents for Interoperability of e-Health Services**, *Information
  Systems and Grid Technologies* (ISGT 2020), Sofia, Bulgaria, 29-30 May 2020, pp. 14-29. (CEUR-WS.org vol. 2656).

## Licence

The author's own work is released under [CC0 1.0 Universal](LICENSE). Third-party files keep their own licences; see
[NOTICE.md](NOTICE.md).

## Citing

Abanos, S. *Archetypes of Clinical Concepts - Doctoral Thesis*. Faculty of Mathematics and Informatics, Sofia University
St. Kliment Ohridski, 2026. https://github.com/SimeonAbanos/archetypes-phd
