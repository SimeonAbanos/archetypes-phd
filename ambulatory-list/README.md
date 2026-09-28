# Ambulatory List (EN ISO 13606)

`CEN-EN13606-COMPOSITION.AmbulatoryList.v1`

An EN ISO 13606 archetype of the ambulatory list a Bulgarian general practitioner
reports to the National Health Insurance Fund, organised along the four stages of a
visit: observation, evaluation, instruction and action. Built on 2026-09-12 within the
doctoral thesis.

## Scope

The archetype is built from the method published in section 6 of

> Evgeniy Krastev, Dimitar Tcharaktchiev, Kalinka Kaloyanova, Lyubomir Kirov, Petko Kovachev,
> Simeon Abanos, Nonka Mateva,
> **Standards Based Adaptation of Clinical Documents for Interoperability of e-Health Services**,
> *Information Systems and Grid Technologies* (ISGT 2020), Sofia, Bulgaria, 29–30 May 2020,
> pp. 14–29. (CEUR-WS.org vol. 2656).

It follows the vocabulary and the recording style of
`CEN-EN13606-COMPOSITION.PATIENT.v1` (E. Krastev, FMI, 2019), from which it is derived.

## Files

| File | What it is |
| --- | --- |
| `1-reference-model/TS14796-dataTypes.xsd` | the EN ISO 13606 data types, (c) IBIME, UPV, CC-BY; see ../NOTICE.md |
| `2-archetypes/CEN-EN13606-COMPOSITION.AmbulatoryList.v1.adl` | the archetype |
| `2-archetypes/CEN-EN13606-COMPOSITION.AmbulatoryList.v1.xsd` | the W3C XML Schema derived from it, 32 complex types |
| `3-instances/instance-valid.xml` | a minimal valid instance |
| `3-instances/instance-invalid-structural-rm.xml` | the code of the diagnosis placed before its coding scheme, against the order the RM data type sets |
| `3-instances/instance-invalid-semantic-archetype.xml` | the diagnosis coded in `SNOMED-CT`, while the archetype fixes `ICD10_1998` |

The schema is derived from the archetype, so one check covers both steps of validity,
and `4-validity-check` has only `validate-all.cmd`.

The instances are deliberately minimal: one section with one entry, carrying a diagnosis
and its ICD-10 code and no data about any person. Their purpose is to show that the
derived schema accepts and rejects as intended, so they do not show what a complete
ambulatory list looks like.
