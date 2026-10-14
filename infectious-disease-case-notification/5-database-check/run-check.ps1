# Database check - the same notices in a relational and in an XML database.
# Run it through run-check.cmd next to it, or from PowerShell with the parameters below.
#
#   1. loads relational/notifications.sql into a new database in MariaDB or MySQL;
#   2. checks every instance in xml-database/instances.zip against the XML schema derived
#      from the archetype (../2-archetypes) and stores the valid ones in eXist-db;
#   3. runs every query in queries/ twice - the .sql file in the relational database and
#      the .xq file of the same name in eXist-db - and compares the two answers with each
#      other and with the expected answer in results/.
#
# Nothing is measured: the check is whether the two databases give the same answers.
# The files of this folder are only read. The database and the collection named below are
# dropped and created again on every run, and the instances are unpacked into a temporary
# folder that is removed at the end.
#
# Needs: MariaDB or MySQL with its command-line client (mysql.exe or mariadb.exe), and
# eXist-db running, by default at http://localhost:8080/exist with the user admin.
# Exit code: 0 - same answers; 1 - the answers differ; 2 - the check could not be run.
param(
    [string]$MySql = '',
    [string]$DbHost = '127.0.0.1',
    [int]$DbPort = 3306,
    [string]$DbUser = 'root',
    [string]$DbPassword = '',
    [string]$DbName = 'notifications_check',
    [string]$Exist = 'http://localhost:8080/exist',
    [string]$ExistUser = 'admin',
    [string]$ExistPassword = '',
    [string]$Collection = '/db/notifications'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$kit = Split-Path -Parent $here
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$script:temp = ''
$failed = $false

function Say([string]$text) { Write-Host $text }

# Stops the check: removes the temporary folder and leaves with exit code 2.
function Stop-Check([string]$text) {
    Write-Host ('STOPPED: ' + $text) -ForegroundColor Red
    if ($script:temp -ne '' -and (Test-Path -LiteralPath $script:temp)) {
        Remove-Item -LiteralPath $script:temp -Recurse -Force -ErrorAction SilentlyContinue
    }
    exit 2
}

# ---------------------------------------------------------------- the parameters and the folder

if ($DbName -notmatch '^[A-Za-z0-9_]+$' -or
    @('mysql', 'information_schema', 'performance_schema', 'sys') -contains $DbName.ToLowerInvariant()) {
    Stop-Check ('-DbName must be a new database name of letters, digits and _, not ' + $DbName)
}
if ($Collection -notmatch '^/db/[A-Za-z0-9_.-]+$' -or $Collection -match '^/db/system') {
    Stop-Check ('-Collection must be one collection directly under /db, for example /db/notifications, not ' + $Collection)
}
foreach ($need in @('1-reference-model', '2-archetypes')) {
    if (-not (Test-Path -LiteralPath (Join-Path $kit $need))) {
        Stop-Check ('the folder ' + $need + ' of the set was not found next to this folder')
    }
}

# ---------------------------------------------------------------- eXist-db over its REST interface

function New-ExistClient {
    $wc = New-Object System.Net.WebClient
    $wc.Encoding = $utf8
    $token = [Convert]::ToBase64String($utf8.GetBytes($ExistUser + ':' + $ExistPassword))
    $wc.Headers.Add('Authorization', 'Basic ' + $token)
    return $wc
}

# The answer is serialized as plain text, so that & < > come back as they are.
function Invoke-XQuery([string]$query) {
    $query = $query.Replace("collection('/db/notifications')", "collection('" + $Collection + "')")
    $body = '<query xmlns="http://exist.sourceforge.net/NS/exist" wrap="no"><text><![CDATA[' +
        $query + ']]></text><properties><property name="method" value="text"/></properties></query>'
    $wc = New-ExistClient
    $wc.Headers.Add('Content-Type', 'application/xml; charset=utf-8')
    try { $answer = $wc.UploadString($Exist + '/rest/db', 'POST', $body) }
    catch { Stop-Check ('eXist-db did not run the query: ' + $_.Exception.Message) }
    return @($answer -split "`n")
}

try { $null = (New-ExistClient).DownloadString($Exist + '/rest/db') }
catch { Stop-Check ('eXist-db does not answer at ' + $Exist + ': ' + $_.Exception.Message) }

# ---------------------------------------------------------------- the client of the database

function Find-MySql {
    if ($MySql -ne '') {
        if (Test-Path -LiteralPath $MySql) { return $MySql }
        Stop-Check ('the client given with -MySql was not found: ' + $MySql)
    }
    foreach ($name in @('mysql', 'mariadb')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Path }
    }
    $candidates = @('C:\xampp\mysql\bin\mysql.exe')
    $found = @(Get-ChildItem -Path 'C:\laragon\bin\mysql\*\bin\mysql.exe' -ErrorAction SilentlyContinue | Sort-Object FullName -Descending)
    foreach ($f in $found) { $candidates += $f.FullName }
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $root) { continue }
        foreach ($pattern in @('MariaDB*\bin\mysql.exe', 'MariaDB*\bin\mariadb.exe', 'MySQL\MySQL Server*\bin\mysql.exe')) {
            $found = @(Get-ChildItem -Path (Join-Path $root $pattern) -ErrorAction SilentlyContinue)
            foreach ($f in $found) { $candidates += $f.FullName }
        }
    }
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }
    Stop-Check 'no mysql.exe or mariadb.exe was found; give its path with -MySql'
}

# The password goes through MYSQL_PWD, so that the client does not warn about it. The client
# may go on after an error in a sourced file and still exit with 0, so every ERROR line it
# writes stops the check as well.
function Invoke-Sql([string]$sql, [string]$database) {
    $arguments = @('--protocol=TCP', ('--host=' + $DbHost), ('--port=' + $DbPort), ('--user=' + $DbUser),
        '--default-character-set=utf8mb4', '--batch', '--raw', '--skip-column-names')
    if ($database -ne '') { $arguments += '--database=' + $database }
    $arguments += '--execute=' + $sql
    $env:MYSQL_PWD = $DbPassword
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & $script:client $arguments 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    $lines = @()
    $messages = @()
    foreach ($o in $output) {
        if ($o -is [System.Management.Automation.ErrorRecord]) { $messages += $o.ToString() } else { $lines += [string]$o }
    }
    $errors = @($messages | Where-Object { $_ -match '^ERROR' })
    if ($code -ne 0 -or $errors.Count -gt 0) {
        Stop-Check ('the database client answered: ' + ($messages -join ' '))
    }
    return $lines
}

# ---------------------------------------------------------------- answers

# The lines of an answer, without empty ones, in ordinal order, so that the order in which
# each database returns equal rows does not matter.
function Get-Lines($lines) {
    $clean = @($lines | ForEach-Object { ([string]$_).TrimEnd("`r") } | Where-Object { $_ -ne '' })
    [string[]]$sorted = $clean
    [Array]::Sort($sorted, [StringComparer]::Ordinal)
    return ,$sorted
}

function Test-Same([string[]]$a, [string[]]$b) {
    if ($a.Count -ne $b.Count) { return $false }
    for ($i = 0; $i -lt $a.Count; $i++) { if ($a[$i] -cne $b[$i]) { return $false } }
    return $true
}

# ---------------------------------------------------------------- 1. the relational database

$script:client = Find-MySql
Say ('Database client: ' + $script:client)

# The client reads the dump from a temporary folder, so that its path is passed unchanged.
$script:temp = Join-Path ([IO.Path]::GetTempPath()) ('notifications-check-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $script:temp
$dump = Join-Path $script:temp 'notifications.sql'
Copy-Item -LiteralPath (Join-Path (Join-Path $here 'relational') 'notifications.sql') -Destination $dump

$version = @(Invoke-Sql 'SELECT VERSION();' '')[0]
Say ('Database server: ' + $version)
$null = Invoke-Sql ('DROP DATABASE IF EXISTS `' + $DbName + '`; CREATE DATABASE `' + $DbName +
    '` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;') ''
$null = Invoke-Sql ('source ' + ($dump -replace '\\', '/')) $DbName
$relCount = @(Invoke-Sql 'SELECT COUNT(*) FROM t_patient_notifications;' $DbName)[0]
$relGrounds = @(Invoke-Sql 'SELECT COUNT(*) FROM t_patient_notification_criteria;' $DbName)[0]
Say ('Relational database ' + $DbName + ': ' + $relCount + ' notices, ' + $relGrounds + ' ticked criteria')

# ---------------------------------------------------------------- 2. the instances

$schemaFile = @(Get-ChildItem -LiteralPath (Join-Path $kit '2-archetypes') -Filter '*.xsd' -File)
if ($schemaFile.Count -ne 1) { Stop-Check 'expected one XML schema in ../2-archetypes' }
$schemas = New-Object System.Xml.Schema.XmlSchemaSet
$schemas.XmlResolver = New-Object System.Xml.XmlUrlResolver
# [NullString]::Value, because PowerShell passes $null to a string parameter as ''
$null = $schemas.Add([NullString]::Value, $schemaFile[0].FullName)
$schemas.Compile()

$unpacked = Join-Path $script:temp 'instances'
Expand-Archive -LiteralPath (Join-Path (Join-Path $here 'xml-database') 'instances.zip') -DestinationPath $unpacked
$files = @(Get-ChildItem -LiteralPath $unpacked -Filter '*.xml' -File | Sort-Object Name)

# Warnings are counted too: without them a root element the schema does not declare passes.
$valid = New-Object System.Collections.ArrayList
$invalid = 0
foreach ($f in $files) {
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.ValidationType = [System.Xml.ValidationType]::Schema
    $settings.ValidationFlags = $settings.ValidationFlags -bor
        [System.Xml.Schema.XmlSchemaValidationFlags]::ReportValidationWarnings
    $settings.Schemas = $schemas
    $script:errors = 0
    $settings.add_ValidationEventHandler({ $script:errors++ })
    $reader = [System.Xml.XmlReader]::Create($f.FullName, $settings)
    try { while ($reader.Read()) { } } catch { $script:errors++ } finally { $reader.Close() }
    if ($script:errors -eq 0) { $null = $valid.Add($f) } else { $invalid++; Say ('  invalid: ' + $f.Name) }
}
Say ('Schema of the archetype: ' + $schemaFile[0].Name)
Say ('Instances: ' + $files.Count + ', valid: ' + $valid.Count + ', invalid: ' + $invalid)
if ($invalid -gt 0) { $failed = $true }

# ---------------------------------------------------------------- 3. the XML database

try { $null = (New-ExistClient).UploadString($Exist + '/rest' + $Collection, 'DELETE', '') }
catch {
    $status = $null
    if ($_.Exception.InnerException -and $_.Exception.InnerException.Response) {
        $status = [int]$_.Exception.InnerException.Response.StatusCode
    }
    if ($status -ne 404) { Stop-Check ('the collection ' + $Collection + ' could not be emptied: ' + $_.Exception.Message) }
}
$notStored = 0
foreach ($f in $valid) {
    $wc = New-ExistClient
    $wc.Headers.Add('Content-Type', 'application/xml')
    try {
        $null = $wc.UploadData($Exist + '/rest' + $Collection + '/' + $f.Name, 'PUT',
            [IO.File]::ReadAllBytes($f.FullName))
    }
    catch { $notStored++; Say ('  not stored: ' + $f.Name + ' - ' + $_.Exception.Message) }
}
if ($notStored -gt 0) { $failed = $true }
$xmlCount = @(Get-Lines (Invoke-XQuery "string(count(collection('/db/notifications')))"))[0]
$xmlGrounds = @(Get-Lines (Invoke-XQuery ("declare namespace n = 'http://EN13606-RM.xsd'; " +
    "string(count(collection('/db/notifications')//n:GROUNDS))")))[0]
Say ('XML database, collection ' + $Collection + ': ' + $xmlCount + ' documents, ' + $xmlGrounds + ' grounds')
if ($xmlCount -ne $relCount -or $xmlGrounds -ne $relGrounds) { $failed = $true }

# ---------------------------------------------------------------- 4. the queries

# The output has no empty lines; a line of dashes separates its parts.
$rule = '-' * 66
Say $rule
Say ('{0,-16} {1,8} {2,8} {3,16} {4,14}' -f 'Query', 'SQL', 'XQuery', 'SQL = XQuery', '= expected')
$queries = @(Get-ChildItem -LiteralPath (Join-Path $here 'queries') -Filter '*.sql' -File | Sort-Object Name)
foreach ($q in $queries) {
    $name = [IO.Path]::GetFileNameWithoutExtension($q.Name)
    $xq = Join-Path (Join-Path $here 'queries') ($name + '.xq')
    $expectedFile = Join-Path (Join-Path $here 'results') ($name + '.tsv')
    $sqlLines = Get-Lines (Invoke-Sql ([IO.File]::ReadAllText($q.FullName, $utf8)) $DbName)
    $xqLines = Get-Lines (Invoke-XQuery ([IO.File]::ReadAllText($xq, $utf8)))
    $same = Test-Same $sqlLines $xqLines
    $expected = 'no file'
    if (Test-Path -LiteralPath $expectedFile) {
        $exp = Get-Lines (@([IO.File]::ReadAllLines($expectedFile, $utf8)) | Select-Object -Skip 1)
        if ((Test-Same $sqlLines $exp) -and (Test-Same $xqLines $exp)) { $expected = 'yes' } else { $expected = 'NO' }
    }
    if (-not $same -or $expected -ne 'yes') { $failed = $true }
    $sameText = 'NO'
    if ($same) { $sameText = 'yes' }
    Say ('{0,-16} {1,8} {2,8} {3,16} {4,14}' -f $name, $sqlLines.Count, $xqLines.Count, $sameText, $expected)
}

Remove-Item -LiteralPath $script:temp -Recurse -Force -ErrorAction SilentlyContinue
Say $rule
if ($failed) { Say 'Result: the two databases do NOT give the same answers.'; exit 1 }
Say ('Result: the two databases give the same answers to all ' + $queries.Count + ' queries.')
exit 0
