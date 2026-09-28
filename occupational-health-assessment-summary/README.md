# Occupational Health Assessment Summary (EN ISO 13606)

`CEN-EN13606-COMPOSITION.OccupationalHealthAssessmentSummary.v1`, in the file `….v3EN.adl`

The archetype, the three instances and the two schemas come from the repository of
Prof. Evgeniy Krastev, [github.com/euggit/EN13606-archetypes](https://github.com/euggit/EN13606-archetypes),
released under CC0 1.0. That repository accompanies

> Evgeniy Krastev, Dimitar Tcharaktchiev, Petko Kovachev, Simeon Abanos,
> **Occupational Health Assessment Summary Designed for Semantic Interoperability**,
> *International Journal of Medical Informatics*, vol. 178, 2023, Art. No. 105207.
> DOI: [10.1016/j.ijmedinf.2023.105207](https://doi.org/10.1016/j.ijmedinf.2023.105207). PMID: 37688835.

The files here carry the changes listed below, which make the published instances valid
against the archetype. The original repository is the one to cite for the published
version.

## Changes

In the archetype:

- `FAMILY NAME` (at0005) required at least two names and now allows one.
  `MUNICIPALITY` (at0127) did not allow a space and now follows the same pattern.
  In both, the character ranges `A-z` and `А-` became `A-Z` and `А-Я`.
- Nine elements had a description as their only allowed value, for example `"GP names"`
  for `GP_NAMES` (at0223). They now accept any text.
- The node name `PERMANENT_WORK_DIABILITY` became `PERMANENT_WORK_DISABILITY`, and a
  Latin `e` at the end of “условие” became Cyrillic.

In the instances:

- A stray `>` before the municipality and the prefix `BG ` before the EGN, the Bulgarian
  personal number, were removed.
- Yes/no answers written as words – Да, Не, Yes, No – became `1` and `0`, as the
  archetype requires. The working time became “нормално работно време” or
  `normal worktime`, the values from the list of the archetype.
- A stray Cyrillic `П` before “Occupational”, a Cyrillic `Я` in
  `PERMANENT_WORK_DISABILITY`, a Latin `e` at the end of “изследване” and the phrase
  “параклинични изследване” were corrected.
- The two instances that name the RM schema point to it in `1-reference-model`.

## Files

| File | What it is |
| --- | --- |
| `1-reference-model/EN13606-RM.xsd`, `TS14796-dataTypes.xsd` | the XML schema of the RM, (c) IBIME, UPV, CC-BY; see ../NOTICE.md |
| `2-archetypes/CEN-EN13606-COMPOSITION.OccupationalHealthAssessmentSummary.v3EN.adl` | the archetype |
| `3-instances/….v3EN.xml`, `….v3EN_SAdata.xml`, `instanceCOMPOSITION.… - instance.xml` | the three published instances |
| `3-instances/instance-invalid-structural-rm.xml` | the third instance without `rc_id` |
| `3-instances/instance-invalid-semantic-archetype.xml` | the third instance with an EGN of nine digits |

Step 2 checks the value constraints of the archetype: 14 regular expressions and 18 lists
of allowed values. It does not check occurrences or terminology bindings.
