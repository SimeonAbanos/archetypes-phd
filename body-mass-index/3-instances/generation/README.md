# How the schema and the instances were made

The valid instance was generated from the operational template with the CaboLabs openEHR-OPT library and filled with illustrative values. It was then converted from canonical openEHR XML into the form defined by the TDS, the XML schema derived from the operational template. The two invalid instances are copies of it with one deliberate change each, described at the top of each file.

| File | What it does |
| --- | --- |
| `opt.groovy` | Generates an instance from the operational template, with a random value in every element the template keeps. It also checks canonical instances in two steps: against the reference model schema that comes with the library, and against the template. |
| `fill.py` | Replaces the random values with the illustrative ones and removes the optional elements the generator filled with random text. It is written for this template only. |
| `tds.py` | Derives the TDS from the operational template and converts a canonical instance into the form the TDS defines. It is written for this template only. |

## Steps

1. Get openEHR-OPT at the commit used here and compile it with Groovy 3.0, leaving out the JSON parts, which need libraries this kit does not use:

   ```
   git clone https://github.com/ppazos/openEHR-OPT
   cd openEHR-OPT
   git checkout dbd30f132ce0820747213dea6012d53114edbd14
   groovyc -j -d classes $(find src/main -name '*.groovy' -o -name '*.java' | grep -v -E 'JsonInstanceGenerator|AdlToOpt|JsonInstanceValidation|OpenEhrJsonParser')
   ```

   The classpath for the next steps is `classes`, `src/main/resources`, Jackson Databind 2.16 and SLF4J API 1.7.

2. Generate an instance. Each run gives different random values.

   ```
   groovy -cp <classpath> opt.groovy generate ../../2-archetypes/anthropometric_measurements.en.v0.opt generated.xml
   ```

3. Fill in the illustrative values (needs Python 3 with lxml):

   ```
   python fill.py generated.xml filled.xml
   ```

4. Check the filled instance in canonical form:

   ```
   groovy -cp <classpath> opt.groovy validate ../../2-archetypes/anthropometric_measurements.en.v0.opt filled.xml
   ```

5. Derive the TDS and convert the instance into its form (needs Python 3 with lxml):

   ```
   python tds.py schema ../../2-archetypes/anthropometric_measurements.en.v0.opt ../../2-archetypes/anthropometric_measurements.en.v0.xsd
   python tds.py document ../../2-archetypes/anthropometric_measurements.en.v0.opt filled.xml ../instance-valid.xml
   ```

6. Delete `generated.xml` and `filled.xml`, because the check reads every XML file in the kit. Then check the instances with `validate-all.cmd` in `4-validity-check`, which needs nothing to be installed.

openEHR-OPT is developed by CaboLabs and is under the Apache License 2.0. It is not copied here. The three scripts are part of this kit and fall under its CC0 1.0 licence.
