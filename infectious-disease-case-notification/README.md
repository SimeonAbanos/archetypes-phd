# Infectious Disease Case Notification (EN ISO 13606)

`CEN-EN13606-COMPOSITION.InfectiousDiseaseCaseNotification.v1`

An EN ISO 13606 archetype of the rapid notification a general practitioner submits when
a case of an infectious disease is registered, under Ordinance No 21 of 18 July 2005 of
the Bulgarian Ministry of Health. Built on 2026-09-20 within the doctoral thesis.

## Four sections

| Section | Holds |
| --- | --- |
| `SECTION-SUBJECT` | the subject of the notification: identifier, date of birth, sex |
| `SECTION-DISEASE` | the disease, by name, by ICD-10 code and by its number in Annex 1 of the ordinance |
| `SECTION-CASE.CLASSIFICATION` | the class of the case, the rule that produced it, and every criterion it rests on |
| `SECTION-REPORTER` | the reporting physician, the practice and the date |

The third section is the point of the model. The class of a case, possible or probable
or confirmed, is normally a rule inside application logic and stays in the system that
computed it. Here it is recorded in the document as a coded statement, together with the
grounds it follows from: each criterion with its category, its number in Annex 3 of the
ordinance, and its text.

## Terminology binding

Two bindings, both through `codingSchemeName` in the data type itself rather than
through a `term_binding` section: `ICD10_1998` for the ICD-10 code of the disease, and
the numbering of the ordinance's annexes – `NAREDBA21-PRIL1` for the number of the
disease, `NAREDBA21-PRIL2` for the class of the case and `NAREDBA21-PRIL3` for the
criteria. **There is no binding to SNOMED CT or LOINC anywhere in this archetype.**

## Files

| File | What it is |
| --- | --- |
| `1-reference-model/TS14796-dataTypes.xsd` | the EN ISO 13606 data types, (c) IBIME, UPV, CC-BY; see ../NOTICE.md |
| `2-archetypes/CEN-EN13606-COMPOSITION.InfectiousDiseaseCaseNotification.v1.adl` | the archetype |
| `2-archetypes/CEN-EN13606-COMPOSITION.InfectiousDiseaseCaseNotification.v1.xsd` | the W3C XML Schema derived from it, 14 complex types |
| `2-archetypes/LinkEHR-archetype-tree-2026-09-20.png` | the archetype as LinkEHR Studio renders it |
| `2-archetypes/LinkEHR-parse-result-2026-09-20.png` | the parse result, with no errors |
| `3-instances/instance-valid.xml` | a valid instance |
| `3-instances/instance-invalid-structural-rm.xml` | the classification date written as 17.04.2026, which the date type of the RM does not accept |
| `3-instances/instance-invalid-semantic-archetype.xml` | the class of the case declared under `NAREDBA21-PRIL1` instead of `NAREDBA21-PRIL2` |

The schema is derived from the archetype, so one check covers both steps of validity,
and `4-validity-check` has only `validate-all.cmd`. Each invalid instance differs
from the valid one by one value and a comment, and the schema rejects it with a single
error.

## About the instances

The valid instance is the export of a recorded notification of a confirmed case of
scarlet fever, produced by the information system that holds it.
**The data is demonstration data**: the names, the practices and the national numbers
are invented, and the national number is not part of the document at all.

## Three things recorded as the source has them

**A clinical criterion may be unnumbered in the ordinance itself.** Scarlet fever is
such a case. `CRITERION.CODE` is therefore optional and such a criterion carries only
its text, which is how the ordinance states it.

**`APPLIED.RULE` is an uncoded string.** It is the expression the system computed with,
and there is no nomenclature to bind it to.

**The coding of `SEX` is not documented in the source**, neither in the database nor in
the system that writes it, so the value is recorded as the code of that system, with no
terminology named.

## Scope

The archetype is built within the doctoral thesis, continuing the work published in

> Simeon Abanos, Evgeniy Krastev, Petko Kovachev, Dimitar Tcharaktchiev,
> **Modeling and Clinical Data Exchange in Registration of Infectious Disease Cases**,
> *Annual of Sofia University “St. Kliment Ohridski”, FMI*, vol. 110, 2023, pp. 7–23.
> DOI: [10.60063/GSU.FMI.110.7-23](https://doi.org/10.60063/GSU.FMI.110.7-23).

It follows the text of the ordinance as that text is held in the database of the
information system.
