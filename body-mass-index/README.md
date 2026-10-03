# Body Mass Index (openEHR)

`openEHR-EHR-COMPOSITION.anthropometry.v0`, three observation archetypes and the template
`anthropometric_measurements.en.v0`

Built after the body mass index example in

> Evgeniy Krastev, Simeon Abanos, Dimitar Tcharaktchiev,
> **Health Data Exchange Based on Archetypes of Clinical Concepts**,
> *Information Systems and Grid Technologies* (ISGT 2022), Sofia, Bulgaria, 27–28 May 2022,
> pp. 98–112. (CEUR-WS.org vol. 3191).

The values in the instances are illustrative and describe no person.

## Archetypes and template

| File | Role | Source |
| --- | --- | --- |
| `openEHR-EHR-OBSERVATION.body_weight.v2` | body weight | CKM, unchanged |
| `openEHR-EHR-OBSERVATION.height.v2` | height | CKM, unchanged |
| `openEHR-EHR-OBSERVATION.body_mass_index.v2` | body mass index | CKM, unchanged |
| `openEHR-EHR-COMPOSITION.anthropometry.v0` | the document, with one slot for each observation | built here |
| `anthropometric_measurements.en.v0.oet` | the template | built here in Archetype Designer |
| `anthropometric_measurements.en.v0.opt` | the operational template | exported from Archetype Designer |
| `anthropometric_measurements.en.v0.xmind` | a mind map of the template | exported from Archetype Designer |
| `anthropometric_measurements.en.v0.xsd` | the XML schema derived from the operational template (TDS) | derived here with `3-instances/generation/tds.py` |

All of them are in `2-archetypes`. The CKM archetypes were taken on 2026-09-26 from
[github.com/openEHR/CKM-mirror](https://github.com/openEHR/CKM-mirror), commit `5cb099f`.

The template fills the three slots of the composition, leaves out the birth events of the
weight and height archetypes and restricts the units to kg, cm and kg/m2. Its identifier
has the form concept.language.version, which the EHRServer schema in `1-reference-model`
requires.

## Instances

| File | What it is |
| --- | --- |
| `3-instances/instance-valid.xml` | weight 82.0 kg measured lightly clothed, height 178.0 cm standing, body mass index 25.9 kg/m2 calculated automatically |
| `3-instances/instance-invalid-structural-rm.xml` | the body mass index observation has no subject |
| `3-instances/instance-invalid-semantic-archetype.xml` | a height of 1780 cm, as if entered in millimetres |

`instance-valid.xml` was generated from the operational template with the
[CaboLabs openEHR-OPT](https://github.com/ppazos/openEHR-OPT) library, commit `dbd30f1`,
filled with the values above and converted from canonical openEHR XML into the form
the TDS defines. The two invalid instances are derived from it. The scripts and the
steps are in [`3-instances/generation`](3-instances/generation).

## The TDS

The Template Data Schema (TDS) is an XML schema derived from the operational template.
Its element names come from the nodes of the template, and the values below them keep
the types of the openEHR RM, which the TDS imports from `1-reference-model/Version.xsd`.
It follows the form of the TDS that Template Designer of Ocean Health Systems exports,
with one difference: it holds only the structure of the template – which nodes, in which
order, how many times and of which types. The constraints on values are left to step 2,
so that the two steps stay apart. Template Designer ships its transform only with the tool
itself, so the TDS here is derived with `tds.py`.

## Validity check

Step 1 checks the instances against the TDS. Step 2 checks them against the operational
template: the units, intervals and precision of quantities, the local codes of coded
texts, the archetypes in the slots of the composition, and whether every node of an
instance is one the template keeps. It does not check the terminology bindings.

In canonical form, before the conversion, the three instances were also checked with the
validator of the openEHR-OPT library (`3-instances/generation/opt.groovy`), against the RM
schema of the library and against the operational template, with the same results.

The official schemas in
[github.com/openEHR/specifications-ITS-XML](https://github.com/openEHR/specifications-ITS-XML)
reject an underscore in an archetype identifier, as in `body_mass_index`. The EHRServer
schema accepts it, which is why that schema is used here.

## Differences from the publication

- **Height.** CKM had no published height archetype when the publication was written, so
  it specialises the body weight archetype into one. The kit uses `height.v2`, which CKM
  has published since.
- **Step 1.** The publication describes checking instances against the TDS, the XML schema
  to which the operational template can be converted. Here the TDS is derived with
  `tds.py` and leaves the constraints on values to step 2.
- **Data and terminology.** The publication loads real data into the instances and binds weight, height and body mass index to SNOMED CT codes. Here the values are illustrative, and the bindings are those of the CKM archetypes: LOINC for weight and height, SNOMED CT and LOINC for body mass index.
