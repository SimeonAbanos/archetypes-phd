# Database check - the same notices in a relational and in an XML database

The 3003 notices of the information system for registration, notification and reporting of communicable diseases are
held here twice: in the relational schema of the system and as instances of the archetype
`CEN-EN13606-COMPOSITION.InfectiousDiseaseCaseNotification.v1`. The check loads both into a database, asks both the same
five questions - once in SQL and once in XQuery - and compares the answers.

Performance is not measured. The check shows whether the two databases give the same answers, and where each query finds
the meaning of the data.

## Files

| File | What it is |
| --- | --- |
| `relational/notifications.sql` | eight of the nine working tables of the system (version 4), all but the user accounts: the nomenclatures of Ordinance No 21, the general practitioners, the patients and the 3003 notices with the criteria ticked for each |
| `xml-database/instances.zip` | the same 3003 notices as instances of the archetype, exported by the system, one file per notice |
| `queries/*.sql`, `queries/*.xq` | five questions, each written in SQL for the relational schema and in XQuery for the instances |
| `results/*.tsv` | the expected answer to each question |
| `run-check.ps1`, `run-check.cmd` | the script that runs the check, and its launcher |

## The questions

| Query | Question | Rows |
| --- | --- | --- |
| `q1-case-class` | notices by class of the case - possible, probable, confirmed | 3 |
| `q2-disease` | notices by disease, with its number in Annex 1 of the ordinance and its ICD-10 code | 66 |
| `q3-month` | pertussis in 2025, by month of classification and by class | 16 |
| `q4-grounds` | which categories of criteria - clinical, laboratory, epidemiological, diagnostic imaging - each class rests on | 9 |
| `q5-age` | notices by class and by age group at the date of classification | 18 |

The two versions of a question differ in where they find the meaning. The SQL query reads columns whose meaning is kept
in the application: in `q4-grounds` it has to rebuild the category of every ticked criterion from the tree of criteria,
the way the application does, because the notice does not store it. The XQuery reads the instance, which carries the
category of every ground as a coded value (`CRITERION.CATEGORY`), so the same question is a path in the document.

## Running the check

Requirements:

- MariaDB or MySQL with its command-line client (`mysql.exe` or `mariadb.exe`);
- eXist-db, running and reachable over its REST interface (on Windows, unpack it into a folder whose path has no
  spaces - its `bin\startup.bat` does not start otherwise);
- Windows PowerShell 5.1, which comes with Windows, or PowerShell 7.

The check was run on Linux with MariaDB 10.11.14, eXist-db 6.4.1 on Java 21 and PowerShell 7.4.6, and on Windows with
MariaDB 10.11.19, eXist-db 6.4.1 on Java 8 and Windows PowerShell 5.1, with the same result. It has not been run with
MySQL, but the queries use only syntax that MySQL 8.0 also accepts.

Run `run-check.cmd` on Windows, or `run-check.ps1` with parameters:

| Parameter | Default |
| --- | --- |
| `-MySql` | looked up: `mysql`, `mariadb`, XAMPP, Laragon, the MariaDB and MySQL folders in Program Files |
| `-DbHost`, `-DbPort`, `-DbUser`, `-DbPassword` | `127.0.0.1`, `3306`, `root`, empty |
| `-DbName` | `notifications_check` - dropped and created again on every run |
| `-Exist`, `-ExistUser`, `-ExistPassword` | `http://localhost:8080/exist`, `admin`, empty |
| `-Collection` | `/db/notifications` - emptied and filled again on every run; one collection directly under `/db` |

The script:

1. loads `relational/notifications.sql` into the database;
2. checks every instance against the XML schema in `../2-archetypes`, which carries the reference model and the
   archetype together, and stores only the valid ones in eXist-db;
3. compares the number of notices and of ticked criteria in the two databases;
4. runs every query in both databases and compares the two answers with each other and with `results/`.

The files of this folder are only read; the instances are unpacked into a temporary folder that is removed at the end.
The exit code is 0 when the answers are the same, 1 when they differ and 2 when the check could not be run, for example
when the database client reports an error while loading the data. The output ends with one line per query:

```
------------------------------------------------------------------
Query                 SQL   XQuery     SQL = XQuery     = expected
q1-case-class           3        3              yes            yes
q2-disease             66       66              yes            yes
q3-month               16       16              yes            yes
q4-grounds              9        9              yes            yes
q5-age                 18       18              yes            yes
------------------------------------------------------------------
Result: the two databases give the same answers to all 5 queries.
```

## About the data

**The data is generated.** The notices are not cases of real people and do not describe a real epidemic situation. The
names of the general practitioners and of their practices are invented; their middle names and e-mail addresses are left
empty. In `t_patients` the columns that hold personal data in the system are left empty; the identifier, the date of
birth and the sex are kept, because the instances carry them. The personal identification number (EGN) is in neither
database.

The class of every notice was set by the system itself, by the rules of the ordinance and the ticked criteria. Notices
exist for 66 of the 88 entries of Annex 1 (its 67 numbered items and their 21 sub-items) - those for which the text of
the ordinance has been turned into a classification rule.

The instances were exported with the function `arch_xml` of the system (`includes/archetype-xml.inc.php`), called for
every notice from the command line with PHP 8.3, in a database session whose time zone is UTC. Timestamps are therefore
read in UTC, and the SQL queries set the time zone of their session to UTC, so that their dates are the dates in the
instances.

The XML schema allows most elements of the notice to repeat, including the class of the case, the date of classification
and the date of birth. The queries rely on what the export function guarantees: one class of the case, one date of
classification and at most one date of birth in every notice.
