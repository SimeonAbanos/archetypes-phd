# Ambulatory List (EN ISO 13606)

`CEN-EN13606-COMPOSITION.AmbulatoryList.v1`

An EN ISO 13606 archetype of the ambulatory list, the record of a single visit that a Bulgarian general practitioner
reports to the National Health Insurance Fund. It has four sections, one for each stage of the visit: observation,
evaluation, instruction and action (`SECTION-OBSERVATION`, `SECTION-EVALUATION`, `SECTION-INSTRUCTION` and
`SECTION-ACTION`). Rebuilt for the doctoral thesis from a 2019 archetype.

## Origin

The archetype follows the method published in section 6 of

> Evgeniy Krastev, Dimitar Tcharaktchiev, Kalinka Kaloyanova, Lyubomir Kirov, Petko Kovachev, Simeon Abanos, Nonka
> Mateva, **Standards Based Adaptation of Clinical Documents for Interoperability of e-Health Services**, *Information
> Systems and Grid Technologies* (ISGT 2020), Sofia, Bulgaria, 29-30 May 2020, pp. 14-29. (CEUR-WS.org vol. 2656).

It takes the names, codes and data types of its elements from `CEN-EN13606-COMPOSITION.PATIENT.v1` (E. Krastev, FMI,
2019), from which it was rebuilt. That archetype is not part of this repository. Where the method maps data types to ISO
21090, this archetype uses the CEN/TS 14796 data types of `TS14796-dataTypes.xsd`, like the other EN ISO 13606
archetypes here.

## Files

| File | What it is |
| --- | --- |
| `1-reference-model/TS14796-dataTypes.xsd` | the EN ISO 13606 data types; see [NOTICE.md](../NOTICE.md) |
| `2-archetypes/CEN-EN13606-COMPOSITION.AmbulatoryList.v1.adl` | the archetype |
| `2-archetypes/CEN-EN13606-COMPOSITION.AmbulatoryList.v1.xsd` | the XML schema derived from it |
| `3-instances/instance-valid.xml` | a minimal valid instance |
| `3-instances/instance-invalid-structural-rm.xml` | the code of the diagnosis placed before its coding scheme, contrary to the order set by the RM data type |
| `3-instances/instance-invalid-semantic-archetype.xml` | the diagnosis coded in `SNOMED-CT`, whereas the archetype requires `ICD10_1998` |

The schema is derived from the archetype, so one check covers both steps of validity, and `4-validity-check` has only
`validate-all.cmd`. The schema includes the data types from `1-reference-model`.

The instances are deliberately minimal: one section with one entry, holding a diagnosis with its ICD-10 code and no data
about any person. They show that the derived schema accepts and rejects instances as intended.
