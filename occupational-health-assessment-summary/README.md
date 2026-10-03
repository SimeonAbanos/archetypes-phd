# Occupational Health Assessment Summary (EN ISO 13606)

`CEN-EN13606-COMPOSITION.OccupationalHealthAssessmentSummary.v1`, in the file `….v3EN.adl`

The archetype, the three instances and the two schemas come from the repository of
Prof. Evgeniy Krastev, [github.com/euggit/EN13606-archetypes](https://github.com/euggit/EN13606-archetypes),
released under CC0 1.0. That repository accompanies

> Evgeniy Krastev, Dimitar Tcharaktchiev, Petko Kovachev, Simeon Abanos,
> **Occupational Health Assessment Summary Designed for Semantic Interoperability**,
> *International Journal of Medical Informatics*, vol. 178, 2023, Art. No. 105207.
> DOI: [10.1016/j.ijmedinf.2023.105207](https://doi.org/10.1016/j.ijmedinf.2023.105207). PMID: 37688835.

The files here carry the updates listed below. With them, the three published instances
are valid in both steps, and the values of the case study are recorded with matching data
types. The original repository is the one to cite for the published version.

## Updates

In the archetype:

- `FAMILY NAME` (at0005) and `MUNICIPALITY` (at0127) accept one or more words, with the
  character ranges `a-zA-Z` and `а-яА-Я`.
- Nine text elements, among them `GP_NAMES` (at0223), accept any text.
- The node is named `PERMANENT_WORK_DISABILITY`, and the word “условие” is written
  entirely in Cyrillic.
- The `displayName` of coded diagnoses is unconstrained, so it can hold the title of the
  code in its classification.
- The temperature accepts any value, and the humidity a value from 0 to 100 %.
- `CHEMICAL_AGENTS` holds the CAS number of an agent as a coded value (CV) and its
  concentration in air as a physical quantity (PQ) in `ug/m3`, not below 0.
- `CARD_PRELIMINARY_EXAM_DATA` has a `BIOLOGICAL_MONITORING` cluster with the agent by its
  CAS number, the specimen, the result (PQ, not below 0) and the reference range (IVLPQ).

In the instances:

- The municipality and the EGN, the Bulgarian personal number, hold the value alone.
- Yes/no answers are `1` and `0`, and the working time is “нормално работно време” or
  `normal worktime`, both from the lists of the archetype.
- A few texts are spelled consistently, with no Latin letters among Cyrillic ones.
- The two instances that name the RM schema point to it in `1-reference-model`.
- The diagnoses are coded values (CV) with the code and the coding scheme that the
  archetype requires, and G62.2 and N14.3 also carry their titles from the WHO ICD-10.
  The missing diagnosis of the occupational accident is marked with the null flavor `NI`.
- The unit of humidity is `%`.
- For lead, the instances add the CAS number 7439-92-1 and the air concentration of 120 μg/m³.
- The lead levels are also recorded in the biological monitoring cluster: 55 μg/dL in blood with an upper limit of 25 μg/dL, and 0.25 μmol/L in urine with an upper limit of 0.10 μmol/L, as in the publication.

## Files

| File | What it is |
| --- | --- |
| `1-reference-model/EN13606-RM.xsd`, `TS14796-dataTypes.xsd` | the XML schemas of the RM and of its data types, (c) IBIME, UPV, CC-BY; see ../NOTICE.md |
| `2-archetypes/CEN-EN13606-COMPOSITION.OccupationalHealthAssessmentSummary.v3EN.adl` | the archetype |
| `3-instances/….v3EN.xml`, `….v3EN_SAdata.xml`, `instanceCOMPOSITION.… - instance.xml` | the three published instances |
| `3-instances/instance-invalid-structural-rm.xml` | the third instance without `rc_id` |
| `3-instances/instance-invalid-semantic-archetype.xml` | the third instance with an EGN of nine digits |

Step 2 checks the value constraints of the archetype: the regular expressions and lists
of allowed values, the data type of each value, the code and coding scheme of coded values,
and the unit and allowed range of quantities. It does not check occurrences, or whether a
code exists in its coding scheme. LinkEHR Studio 1.0.20240603 reports the archetype itself
as valid.
