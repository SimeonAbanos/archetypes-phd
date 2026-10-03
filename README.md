# Archetypes of Clinical Concepts – Doctoral Thesis

The archetypes behind the doctoral thesis
*Archetype-Oriented Modeling and Management of Clinical Data* by Simeon Abanos,
Faculty of Mathematics and Informatics, Sofia University St. Kliment Ohridski.
The models follow EN ISO 13606 and the openEHR specifications.
Each folder holds one model, its instances and a script that checks them.

For readers new to archetypes, a description in Bulgarian of how the models were built and checked is in
[Архетипи, инстанции и проверка на валидността.docx](Архетипи,%20инстанции%20и%20проверка%20на%20валидността.docx).

| Folder | Framework | Root archetype | Origin |
| --- | --- | --- | --- |
| [`body-mass-index`](body-mass-index) | openEHR | `openEHR-EHR-COMPOSITION.anthropometry.v0` | after the body mass index example of Krastev, Abanos and Tcharaktchiev (2022) |
| [`occupational-health-assessment-summary`](occupational-health-assessment-summary) | EN ISO 13606 | `CEN-EN13606-COMPOSITION.OccupationalHealthAssessmentSummary.v1` | published by E. Krastev with Krastev et al. (2023), here with updates |
| [`infectious-disease-case-notification`](infectious-disease-case-notification) | EN ISO 13606 | `CEN-EN13606-COMPOSITION.InfectiousDiseaseCaseNotification.v1` | built in the thesis, continuing Abanos et al. (2023) |
| [`ambulatory-list`](ambulatory-list) | EN ISO 13606 | `CEN-EN13606-COMPOSITION.AmbulatoryList.v1` | built in the thesis, after the method of Krastev et al. (2020) |

## Layout of a folder

Every folder has the same four subfolders:

| Subfolder | Holds |
| --- | --- |
| `1-reference-model` | the XML schemas of the reference model (RM) and its data types; in two folders only the data types |
| `2-archetypes` | the archetypes in ADL; in two folders also the XML schema derived from the archetype, in one the template, the operational template and the XML schema derived from it (TDS) |
| `3-instances` | the instances; in `body-mass-index` also `generation`, the scripts that produced the TDS and the valid instance |
| `4-validity-check` | the script that checks the instances, with its launchers |

## Two steps of validity

Validity is checked in two steps.

1. **Structural validity** – the instance against the RM of its
   framework, EN ISO 13606-1 or openEHR, in `1-reference-model`. In `body-mass-index` the
   instance is checked against the TDS, which imports the RM and adds the structure of the
   template.
2. **Semantic validity** – the instance against the constraints of the archetype, or of
   the operational template where there is one, in `2-archetypes`.

The archetype itself is written in ADL as an instance of the Archetype Object Model (AOM). Whether it is a
valid AOM model is checked by the modelling tool – LinkEHR Studio for EN ISO 13606,
Archetype Designer for openEHR – and not by the scripts here.

In two folders the XML schema is derived from the archetype. Such a schema carries the
RM and the archetype together, so one check covers both steps.

## Running the check

Every `4-validity-check` holds the same `validate.ps1` and the launchers that apply:

| Launcher | Runs |
| --- | --- |
| `validate-1-structural-rm.cmd` | step 1 |
| `validate-2-semantic-archetype.cmd` | step 2 |
| `validate-all.cmd` | step 1, then step 2 for the instances valid in step 1 |

Double-click a launcher on Windows. Nothing has to be installed. The script reads the
folder above it and changes nothing.

The name of an instance states the result it should have, and the script reports
whether it has it:

| Instance | Expected result |
| --- | --- |
| `instance-valid.xml` | valid in both steps |
| `instance-invalid-structural-rm.xml` | invalid in step 1 |
| `instance-invalid-semantic-archetype.xml` | valid in step 1, invalid in step 2 |

## Publications

The publications named in the Origin column:

- Evgeniy Krastev, Simeon Abanos, Dimitar Tcharaktchiev,
  **Health Data Exchange Based on Archetypes of Clinical Concepts**,
  *Information Systems and Grid Technologies* (ISGT 2022), Sofia, Bulgaria, 27–28 May 2022,
  pp. 98–112. (CEUR-WS.org vol. 3191).
- Evgeniy Krastev, Dimitar Tcharaktchiev, Petko Kovachev, Simeon Abanos,
  **Occupational Health Assessment Summary Designed for Semantic Interoperability**,
  *International Journal of Medical Informatics*, vol. 178, 2023, Art. No. 105207.
  DOI: [10.1016/j.ijmedinf.2023.105207](https://doi.org/10.1016/j.ijmedinf.2023.105207). PMID: 37688835.
- Simeon Abanos, Evgeniy Krastev, Petko Kovachev, Dimitar Tcharaktchiev,
  **Modeling and Clinical Data Exchange in Registration of Infectious Disease Cases**,
  *Annual of Sofia University “St. Kliment Ohridski”, FMI*, vol. 110, 2023, pp. 7–23.
  DOI: [10.60063/GSU.FMI.110.7-23](https://doi.org/10.60063/GSU.FMI.110.7-23).
- Evgeniy Krastev, Dimitar Tcharaktchiev, Kalinka Kaloyanova, Lyubomir Kirov, Petko Kovachev,
  Simeon Abanos, Nonka Mateva,
  **Standards Based Adaptation of Clinical Documents for Interoperability of e-Health Services**,
  *Information Systems and Grid Technologies* (ISGT 2020), Sofia, Bulgaria, 29–30 May 2020,
  pp. 14–29. (CEUR-WS.org vol. 2656).

## Licence

The work of the author is released under [CC0 1.0 Universal](LICENSE). Third-party files
keep their own licences; see [NOTICE.md](NOTICE.md).

## Citing

Abanos, S. *Archetypes of Clinical Concepts – Doctoral Thesis*. Faculty of Mathematics and Informatics,
Sofia University St. Kliment Ohridski, 2026. https://github.com/SimeonAbanos/archetypes-phd
