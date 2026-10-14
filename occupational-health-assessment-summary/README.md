# Occupational Health Assessment Summary (EN ISO 13606)

`CEN-EN13606-COMPOSITION.OccupationalHealthAssessmentSummary.v1`, in the file
`CEN-EN13606-COMPOSITION.OccupationalHealthAssessmentSummary.v3EN.adl`

The archetype, the three instances and the XML schemas of the reference model and its data types come from the
repository of Prof. Evgeniy Krastev,
[github.com/euggit/EN13606-archetypes](https://github.com/euggit/EN13606-archetypes). That repository accompanies

> Evgeniy Krastev, Dimitar Tcharaktchiev, Petko Kovachev, Simeon Abanos, **Occupational Health Assessment Summary
> Designed for Semantic Interoperability**, *International Journal of Medical Informatics*, vol. 178, 2023, Art.
> No. 105207. DOI: [10.1016/j.ijmedinf.2023.105207](https://doi.org/10.1016/j.ijmedinf.2023.105207). PMID: 37688835.

The files here close some gaps in the published version, in its structure, naming and value constraints. The main
changes are listed below. The three instances are valid in both steps, and the values of the case study are recorded
with matching data types. The original repository is the one to cite for the published version.

## Updates

The main changes concern the hierarchy of the nodes and the data types:

- `CHEMICAL_AGENTS` may repeat, one cluster per agent. It holds the CAS number of the agent as a coded value (CV) and
  its concentration in air as a physical quantity (PQ).
- `CARD_PRELIMINARY_EXAM_DATA` has a `BIOLOGICAL_MONITORING` cluster with the agent, the specimen, the result (PQ) and
  the reference range as an interval of physical quantities (IVLPQ).
- In the instances `...v3EN.xml` and `...v3EN_SAdata.xml`, each job is in its own employment section.
- In the instances, each diagnosis is a coded value (CV) in one of the coding schemes the archetype allows.
- The instances record the lead exposure case from the publication: lead (CAS number 7439-92-1) at 120 μg/m³ in air, 55
  μg/dL in blood with an upper limit of 25 μg/dL, and 0.25 μmol/L in urine with an upper limit of 0.10 μmol/L.

## Files

| File | What it is |
| --- | --- |
| `1-reference-model/EN13606-RM.xsd`, `TS14796-dataTypes.xsd` | the XML schemas of the RM and of its data types; see [NOTICE.md](../NOTICE.md) |
| `2-archetypes/CEN-EN13606-COMPOSITION.OccupationalHealthAssessmentSummary.v3EN.adl` | the archetype |
| `3-instances/...v3EN.xml`, `...v3EN_SAdata.xml`, `instanceCOMPOSITION... - instance.xml` | the three published instances |
| `3-instances/instance-invalid-structural-rm.xml` | the third instance without `rc_id` |
| `3-instances/instance-invalid-semantic-archetype.xml` | the third instance with a Bulgarian personal identification number (EGN) of nine digits instead of ten |

## Validity check

Step 1 checks the instances against the XML schemas of the RM and its data types. Step 2 first checks the nodes of an
instance: each must have a code from the archetype, sit where the archetype places it, be of the right class, occur as
many times as allowed and have the attributes the archetype requires. Then it checks the values: the regular expressions
and lists of allowed values, the language and character set of texts, the data type of each value, the code and coding
scheme of coded values, and the unit and allowed range of quantities and of interval bounds. It does not check whether a
code exists in its coding scheme. LinkEHR Studio 1.0.20240603 reports the archetype itself as valid.
