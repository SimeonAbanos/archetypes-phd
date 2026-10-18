# Infectious Disease Case Notification (EN ISO 13606)

`CEN-EN13606-COMPOSITION.InfectiousDiseaseCaseNotification.v1`

An EN ISO 13606 archetype of the rapid notification by which a physician reports a case of an infectious disease under
Ordinance No 21 of 18 July 2005 of the Bulgarian Ministry of Health, last amended in 2026. Built for the doctoral
thesis.

## Four sections

| Section | Holds |
| --- | --- |
| `SECTION-SUBJECT` | the subject of the notification: identifier, date of birth, sex |
| `SECTION-DISEASE` | the disease, by name, by ICD-10 code and by its number in Annex 1 of the ordinance |
| `SECTION-CASE.CLASSIFICATION` | the class of the case, the rule that produced it, and every criterion it rests on |
| `SECTION-REPORTER` | the reporting physician, the practice and the date |

The third section is what the model was built for. The class of a case - possible, probable or confirmed - is normally
set by a rule in the application logic, and its grounds can be read only in the system that computed it. Here it is
recorded in the document as a coded value, together with the grounds it rests on: each criterion with its category, its
number in Annex 3 of the ordinance, and its text.

## Terminology binding

For the content of the notification the archetype uses four coding schemes, all bound through `codingSchemeName` in the
data type itself rather than through a `term_binding` section: `ICD10_1998` for the ICD-10 code of the disease, and the
numbering of the ordinance's annexes - `NAREDBA21-PRIL1` for the number of the disease, `NAREDBA21-PRIL2` for the class
of the case and `NAREDBA21-PRIL3` for the criteria. The archetype has no binding to SNOMED CT or LOINC.

## Files

| File | What it is |
| --- | --- |
| `1-reference-model/TS14796-dataTypes.xsd` | the EN ISO 13606 data types; see [NOTICE.md](../NOTICE.md) |
| `2-archetypes/CEN-EN13606-COMPOSITION.InfectiousDiseaseCaseNotification.v1.adl` | the archetype |
| `2-archetypes/CEN-EN13606-COMPOSITION.InfectiousDiseaseCaseNotification.v1.xsd` | the XML schema derived from it |
| `2-archetypes/LinkEHR-archetype-tree-2026-09-20.png` | the archetype as LinkEHR Studio renders it |
| `2-archetypes/LinkEHR-validation-2026-10-04.png` | the archetype validated in LinkEHR Studio 1.0.20240603: "The archetype is valid" |
| `3-instances/instance-valid.xml` | a valid instance |
| `3-instances/instance-invalid-structural-rm.xml` | the classification date written as 17.04.2026, which the date type of the RM does not accept |
| `3-instances/instance-invalid-semantic-archetype.xml` | the class of the case coded in `NAREDBA21-PRIL1` instead of `NAREDBA21-PRIL2` |
| `5-database-check/` | 3003 notices from the information system in a relational and in an XML database, with the queries that compare them; see below |

The schema is derived from the archetype, so one check covers both steps of validity, and `4-validity-check` has only
`validate-all.cmd`. The schema includes the data types from `1-reference-model`. Each invalid instance differs from the
valid one by one value and a comment, and the schema rejects it with a single error.

## About the instances

The valid instance is a notification of a confirmed case of scarlet fever, as stored in the information system and
exported by it. **The data is generated**: the names, practices and identifiers are invented, and the personal
identification number (EGN) is not part of the document.

## Database check

[`5-database-check`](5-database-check) holds all 3003 notices of the information system twice: in its relational schema
and as instances of this archetype, exported by the system. All 3003 instances are valid against the schema derived from
the archetype. Five questions, each written in SQL and in XQuery, get the same answers from both databases. Performance
is not measured. See [`5-database-check/README.md`](5-database-check/README.md).

## Recorded as in the source

**A clinical criterion may be unnumbered in the ordinance itself.** Scarlet fever is such a case. `CRITERION.CODE` is
therefore optional and such a criterion carries only its category and its text, which is how the ordinance states it.

**In two places the ordinance repeats a number.** In section 17.2 (influenza A(H5N1)) the clinical criteria carry the
numbers of the laboratory criteria that follow them (17.2.2), and in section 41 (malaria) the clinical criterion carries
the number of its heading (41.1). `CRITERION.CODE` keeps these numbers as the ordinance gives them, and the criteria are
told apart by their text.

**`APPLIED.RULE` is an uncoded string.** It is the expression the system used to compute the class, and there is no
nomenclature to bind it to.

**The ordinance names no code list for `SEX`**, and the database does not document the coding either, so the value is
recorded as the code the system uses, with no terminology named.

## Publication and scope

The archetype continues the work published in

> Simeon Abanos, Evgeniy Krastev, Petko Kovachev, Dimitar Tcharaktchiev, **Modeling and Clinical Data Exchange in
> Registration of Infectious Disease Cases**, *Annual of Sofia University "St. Kliment Ohridski", FMI*, vol. 110, 2023,
> pp. 7-23. DOI: [10.60063/GSU.FMI.110.7-23](https://doi.org/10.60063/GSU.FMI.110.7-23).

It follows the text of the ordinance as that text is held in the database of the information system.
