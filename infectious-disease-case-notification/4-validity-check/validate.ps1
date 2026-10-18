# Validity check of archetype instances - EN ISO 13606 and openEHR.
# Run it through the .cmd files next to it. It reads the folder above and changes nothing.
#   validate-1-structural-rm.cmd        step 1: every instance against the Reference Model (RM),
#                                       or against the XML schema derived from the operational
#                                       template (TDS) when the folder has one
#   validate-2-semantic-archetype.cmd   step 2: every instance against the archetype, or against
#                                       the operational template (.opt) when the folder has one:
#                                       whether every node is one the archetype defines, in its
#                                       place and as many times as it allows, with the attributes
#                                       it requires; and for EN ISO 13606 also the patterns and
#                                       lists of allowed texts, the language and character set of
#                                       texts, the data type of every value, the code and the code
#                                       system of every coded value, and the unit and the allowed
#                                       range of every quantity, the bounds of an interval included
#   validate-all.cmd                   step 1, then step 2 for the instances valid in step 1
# The file name of an instance may state the result it should have, and the run reports
# whether it gets it:
#   instance-valid*, instance-invalid-structural-rm*, instance-invalid-semantic-archetype*
param([ValidateSet('all', '1', '2')][string]$Step = 'all')

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# '1 error', '2 errors'
function Get-Count([int]$n, [string]$word) { if ($n -eq 1) { return '1 ' + $word } else { return $n.ToString() + ' ' + $word + 's' } }
$dir  = Split-Path -Parent $here
$sep  = [IO.Path]::DirectorySeparatorChar
$inv  = [Globalization.CultureInfo]::InvariantCulture

# ---------------------------------------------------------------- the files of the set

# Files under the folder above, its own files first, the folder of the script excepted.
function Get-SetFiles([string]$filter) {
    $f = @(Get-ChildItem -LiteralPath $dir -Filter $filter -File -Recurse |
        Where-Object { -not $_.FullName.StartsWith($here + $sep) })
    return @($f | Sort-Object @{ Expression = { if ($_.DirectoryName -eq $dir) { 0 } else { 1 } } }, FullName)
}

function Get-Relative([string]$path) { return $path.Substring($dir.Length + 1) }

function Read-Lines([string]$path) { return [System.IO.File]::ReadAllLines($path, [System.Text.Encoding]::UTF8) }

# The identifier of an archetype, from the line after "archetype (adl_version=...)".
function Get-ArchetypeId($lines) {
    foreach ($l in $lines) {
        $m = [regex]::Match($l, '^\s*((?:openEHR|CEN)-[A-Za-z0-9]+-[A-Z_]+\.[A-Za-z0-9_-]+\.v\d+)\s*$')
        if ($m.Success) { return $m.Groups[1].Value }
    }
    return ''
}

# ---------------------------------------------------------------- step 1: XML schema

$script:schemaSet = $null
$script:rootName = ''
function Open-Schema([string]$xsd, [bool]$ownRoot = $false) {
    $x = New-Object System.Xml.XmlDocument
    $x.Load($xsd)
    # a TDS imports the schema of the reference model, whose root elements the set then also
    # accepts; an instance must use the root element of the TDS itself
    if ($ownRoot) {
        $e = $x.DocumentElement.SelectSingleNode("*[local-name()='element']")
        $script:rootName = '{' + $x.DocumentElement.GetAttribute('targetNamespace') + '}' + $e.GetAttribute('name')
    }
    $set = New-Object System.Xml.Schema.XmlSchemaSet
    # a schema may include another one, and .NET resolves the include only with a resolver
    $set.XmlResolver = New-Object System.Xml.XmlUrlResolver
    $null = $set.Add($x.DocumentElement.GetAttribute('targetNamespace'), $xsd)
    $script:schemaSet = $set
}

function Test-Schema([string]$path) {
    $st = New-Object System.Xml.XmlReaderSettings
    $st.ValidationType = [System.Xml.ValidationType]::Schema
    $st.Schemas = $script:schemaSet
    $script:errs = 0
    $script:first = ''
    $st.add_ValidationEventHandler({
        param($s, $e)
        $script:errs++
        if ($script:first -eq '') { $script:first = $e.Message }
    })
    $root = ''
    try {
        $r = [System.Xml.XmlReader]::Create($path, $st)
        try {
            while ($r.Read()) {
                if ($root -eq '' -and $r.NodeType -eq [System.Xml.XmlNodeType]::Element) { $root = '{' + $r.NamespaceURI + '}' + $r.LocalName }
            }
        } finally { $r.Close() }
    } catch {
        return New-Object PSObject -Property @{ Ok = $false; Text = 'not well-formed XML'; Detail = @($_.Exception.Message) }
    }
    if ($script:rootName -ne '' -and $root -ne $script:rootName) {
        $script:errs++
        $script:first = 'The root element is ' + $root + ', the schema requires ' + $script:rootName + '.'
    }
    if ($script:errs -eq 0) { return New-Object PSObject -Property @{ Ok = $true; Text = ''; Detail = @() } }
    return New-Object PSObject -Property @{ Ok = $false; Text = (Get-Count $script:errs 'error'); Detail = @($script:first) }
}

# ---------------------------------------------------------------- step 2: EN ISO 13606

# The parent of every data type, read from the schema of the data types (TS14796-dataTypes.xsd),
# so that a value whose type is derived from the required one is accepted: CD for CV, say.
$script:baseOf = @{}
function Read-TypeTree([string]$xsd) {
    $x = New-Object System.Xml.XmlDocument
    $x.Load($xsd)
    foreach ($t in $x.DocumentElement.SelectNodes("*[local-name()='complexType']")) {
        $ext = $t.SelectSingleNode(".//*[local-name()='extension' or local-name()='restriction']")
        if ($null -ne $ext) { $script:baseOf[$t.GetAttribute('name')] = ($ext.GetAttribute('base') -split ':')[-1] }
    }
}

function Test-TypeConforms([string]$actual, [string]$required) {
    $t = $actual
    for ($n = 0; $t -ne '' -and $n -lt 20; $n++) {
        if ($t -eq $required) { return $true }
        $t = [string]$script:baseOf[$t]
    }
    return $false
}

# The block of a PQ in the archetype: the units its CS allows and the constraint on its number -
# an interval such as |>=0.0| or a single value. After ";" stands the assumed value, not a limit.
function Read-En13606Quantity($lines, [int]$k) {
    $units = @(); $schemes = @(); $range = $null; $depth = 0
    for ($j = $k; $j -lt $lines.Length; $j++) {
        $l = $lines[$j]
        $u = [regex]::Match($l, '^\s*codeValue existence matches \{[^}]*\} matches \{(.+)\}\s*$')
        if ($u.Success) { $units += @(Get-Strings $u.Groups[1].Value) }
        $n = [regex]::Match($l, '^\s*codingSchemeName existence matches \{[^}]*\} matches \{(.+)\}\s*$')
        if ($n.Success) { $schemes += @(Get-Strings $n.Groups[1].Value) }
        $v = [regex]::Match($l, '^\s*value existence matches \{[^}]*\} matches \{([^{}]+)\}\s*$')
        if ($v.Success) {
            $c = ($v.Groups[1].Value -split ';', 2)[0].Trim()
            if ($c.StartsWith('|') -and $c.EndsWith('|')) { $c = $c.Substring(1, $c.Length - 2) }
            if ($c -ne '*') { $range = Read-Interval $c }
        }
        $depth += [regex]::Matches($l, '\{').Count - [regex]::Matches($l, '\}').Count
        if ($j -gt $k -and $depth -le 0) { break }
    }
    return New-Object PSObject -Property @{ Units = $units; Schemes = $schemes; Range = $range }
}

# The strings of a list constraint such as {"ICD10_1998"} or {"0","1"; "0"}; after ";" stands the
# assumed value, not a further option. {*} gives no string, that is no constraint.
function Get-Strings([string]$spec) {
    return @([regex]::Matches(($spec -split ';', 2)[0], '"([^"]*)"') | ForEach-Object { $_.Groups[1].Value })
}

# The block of a coded value (CS, CV, CE, CD) in the archetype: the constraint on its code - a
# regular expression or a list - and the code systems it allows.
function Read-En13606Coded($lines, [int]$k) {
    $rx = $null; $codes = @(); $schemes = @(); $depth = 0
    for ($j = $k; $j -lt $lines.Length; $j++) {
        $l = $lines[$j]
        if ($depth -eq 1) {
            $c = [regex]::Match($l, '^\s*codeValue existence matches \{[^}]*\} matches \{(.+)\}\s*$')
            if ($c.Success) {
                $spec = $c.Groups[1].Value.Trim()
                if ($spec.StartsWith('/') -and $spec.EndsWith('/') -and $spec -ne '/.*/') { $rx = $spec.Substring(1, $spec.Length - 2) }
                else { $codes += @(Get-Strings $spec) }
            }
            $n = [regex]::Match($l, '^\s*codingSchemeName existence matches \{[^}]*\} matches \{(.+)\}\s*$')
            if ($n.Success) { $schemes += @(Get-Strings $n.Groups[1].Value) }
        }
        $depth += [regex]::Matches($l, '\{').Count - [regex]::Matches($l, '\}').Count
        if ($j -gt $k -and $depth -le 0) { break }
    }
    return New-Object PSObject -Property @{ Pattern = $rx; Codes = $codes; Schemes = $schemes
        Regex = $(if ($null -ne $rx) { New-Object System.Text.RegularExpressions.Regex('\A(?:' + $rx + ')\z') } else { $null }) }
}

# The bounds of an interval (IVLPQ) in the archetype: for low and high, the PQ block of each,
# read as any other quantity.
function Read-En13606Bounds($lines, [int]$k) {
    $out = @(); $depth = 0
    for ($j = $k; $j -lt $lines.Length; $j++) {
        $l = $lines[$j]
        if ($depth -eq 1) {
            $b = [regex]::Match($l, '^\s*(low|high) existence matches \{[^}]*\} matches \{\s*$')
            if ($b.Success -and $j + 1 -lt $lines.Length -and $lines[$j + 1] -match '^\s*PQ\[at\d+\]') {
                $out += New-Object PSObject -Property @{ Side = $b.Groups[1].Value; Q = (Read-En13606Quantity $lines ($j + 1)) }
            }
        }
        $depth += [regex]::Matches($l, '\{').Count - [regex]::Matches($l, '\}').Count
        if ($j -gt $k -and $depth -le 0) { break }
    }
    return $out
}

# The language and the character set of a text in the archetype: the codes and code systems
# of the CS objects under each of the two attributes.
function Read-En13606TextCodes($lines, [int]$k) {
    $out = @(); $depth = 0
    for ($j = $k; $j -lt $lines.Length; $j++) {
        $l = $lines[$j]
        if ($depth -eq 1) {
            $a = [regex]::Match($l, '^\s*(language|charset) existence matches \{[^}]*\} matches \{\s*$')
            if ($a.Success) {
                $codes = @(); $schemes = @(); $d = 0
                for ($i = $j; $i -lt $lines.Length; $i++) {
                    $c = [regex]::Match($lines[$i], '^\s*codeValue existence matches \{[^}]*\} matches \{(.+)\}\s*$')
                    if ($c.Success) { $codes += @(Get-Strings $c.Groups[1].Value) }
                    $n = [regex]::Match($lines[$i], '^\s*codingSchemeName existence matches \{[^}]*\} matches \{(.+)\}\s*$')
                    if ($n.Success) { $schemes += @(Get-Strings $n.Groups[1].Value) }
                    $d += [regex]::Matches($lines[$i], '\{').Count - [regex]::Matches($lines[$i], '\}').Count
                    if ($i -gt $j -and $d -le 0) { break }
                }
                if ($codes.Count -gt 0 -or $schemes.Count -gt 0) {
                    $out += New-Object PSObject -Property @{ Attr = $a.Groups[1].Value; Codes = $codes; Schemes = $schemes }
                }
            }
        }
        $depth += [regex]::Matches($l, '\{').Count - [regex]::Matches($l, '\}').Count
        if ($j -gt $k -and $depth -le 0) { break }
    }
    return $out
}

# Three kinds of constraint are read, each together with the ELEMENT it belongs to:
#   text      a regular expression or a list of allowed strings for originalText
#   type      the data type of the value, or of each of its alternatives
#   code      for a coded value (CS, CV, CE, CD), the allowed codes and the code system
#   quantity  for a PQ, or a bound of an IVLPQ, the allowed units, their code system and the
#             allowed range of the number
#   textcode  for a text, the allowed codes and code systems of its language and character set
function Get-En13606Constraints($archetypes) {
    $list = @()
    foreach ($a in $archetypes) {
        $lines = $a.Lines
        $code = ''; $name = ''
        for ($i = 0; $i -lt $lines.Length; $i++) {
            $e = [regex]::Match($lines[$i], 'ELEMENT\[(at\d+)\].*--\s*(.*?)\s*$')
            if ($e.Success) {
                $code = $e.Groups[1].Value; $name = $e.Groups[2].Value
                # the value may have several alternatives, each an object of its own data type
                if ($i + 2 -lt $lines.Length -and $lines[$i + 1] -match '^\s*value existence matches \{[^}]*\} matches \{\s*$') {
                    $types = @(); $depth = 1
                    for ($j = $i + 2; $j -lt $lines.Length -and $depth -gt 0; $j++) {
                        $t = [regex]::Match($lines[$j], '^\s*([A-Z_]+)\[at\d+\]')
                        if ($depth -eq 1 -and $t.Success) {
                            $types += $t.Groups[1].Value
                            if ($t.Groups[1].Value -eq 'PQ') {
                                $q = Read-En13606Quantity $lines $j
                                $list += New-Object PSObject -Property @{ Kind = 'quantity'; Code = $code; Name = $name; Sub = ''; Units = $q.Units; Schemes = $q.Schemes; Range = $q.Range }
                            }
                            if ($t.Groups[1].Value -eq 'IVLPQ') {
                                foreach ($b in @(Read-En13606Bounds $lines $j)) {
                                    $list += New-Object PSObject -Property @{ Kind = 'quantity'; Code = $code; Name = $name; Sub = $b.Side; Units = $b.Q.Units; Schemes = $b.Q.Schemes; Range = $b.Q.Range }
                                }
                            }
                            if (@('SIMPLE_TEXT', 'CODED_TEXT') -contains $t.Groups[1].Value) {
                                foreach ($s in @(Read-En13606TextCodes $lines $j)) {
                                    $list += New-Object PSObject -Property @{ Kind = 'textcode'; Code = $code; Name = $name; Sub = $s.Attr; Codes = $s.Codes; Schemes = $s.Schemes }
                                }
                            }
                            if (@('CS', 'CV', 'CE', 'CD') -contains $t.Groups[1].Value) {
                                $q = Read-En13606Coded $lines $j
                                if ($null -ne $q.Regex -or $q.Codes.Count -gt 0 -or $q.Schemes.Count -gt 0) {
                                    $list += New-Object PSObject -Property @{ Kind = 'code'; Code = $code; Name = $name; Type = $t.Groups[1].Value
                                        Pattern = $q.Pattern; Regex = $q.Regex; Codes = $q.Codes; Schemes = $q.Schemes }
                                }
                            }
                        }
                        $depth += [regex]::Matches($lines[$j], '\{').Count - [regex]::Matches($lines[$j], '\}').Count
                    }
                    if ($types.Count -gt 0) { $list += New-Object PSObject -Property @{ Kind = 'type'; Code = $code; Name = $name; Types = $types } }
                }
                continue
            }
            $m = [regex]::Match($lines[$i], '^\s*originalText existence matches \{[^}]*\} matches \{(.+)\}\s*$')
            if (-not $m.Success -or $code -eq '') { continue }
            $spec = $m.Groups[1].Value.Trim()
            $rx = $null; $values = $null
            if ($spec.StartsWith('/') -and $spec.EndsWith('/')) {
                $p = $spec.Substring(1, $spec.Length - 2)
                if ($p -eq '.*') { continue }
                $rx = $p
            } elseif ($spec.StartsWith('"')) {
                # a list of allowed strings; after ";" stands the assumed value, not a further option
                $values = @([regex]::Matches(($spec -split ';', 2)[0], '"([^"]*)"') | ForEach-Object { $_.Groups[1].Value })
            } else { continue }
            $list += New-Object PSObject -Property @{ Kind = 'text'; Code = $code; Name = $name
                Pattern = $rx; Values = $values
                Regex = $(if ($null -ne $rx) { New-Object System.Text.RegularExpressions.Regex('\A(?:' + $rx + ')\z') } else { $null }) }
        }
    }
    return $list
}

# '- the archetype allows only 18.0' for a single value, '- outside the allowed range >=0.0' otherwise
function Format-Allowed($iv) {
    if ($null -ne $iv.Lo -and $null -ne $iv.Hi -and $iv.Lo -eq $iv.Hi) { return ' - the archetype allows only ' + $iv.Text.Trim() }
    return ' - outside the allowed range ' + $iv.Text.Trim()
}

function Test-En13606([string]$path, $constraints) {
    $doc = New-Object System.Xml.XmlDocument
    $doc.Load($path)
    $nm = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
    $nm.AddNamespace('e', 'http://EN13606-RM.xsd')
    $xsi = 'http://www.w3.org/2001/XMLSchema-instance'
    $count = 0; $bad = @()
    if ($null -ne $script:tree) {
        $st = Test-En13606Structure $doc
        $count += $st.Count; $bad += @($st.Bad)
    }
    foreach ($c in @($constraints | Where-Object { $_.Kind -eq 'text' })) {
        foreach ($v in $doc.SelectNodes("//e:*[e:archetype_id='" + $c.Code + "']/e:value/e:originalText", $nm)) {
            $count++
            $t = $v.InnerText
            if ($null -ne $c.Regex) {
                if (-not $c.Regex.IsMatch($t)) { $bad += ($c.Name + ' (' + $c.Code + "): '" + $t + "' does not match /" + $c.Pattern + '/') }
            } elseif ($c.Values -notcontains $t) {
                $bad += ($c.Name + ' (' + $c.Code + "): '" + $t + "' is not one of " + (($c.Values | ForEach-Object { '"' + $_ + '"' }) -join ', '))
            }
        }
    }
    foreach ($c in @($constraints | Where-Object { $_.Kind -eq 'type' })) {
        foreach ($v in $doc.SelectNodes("//e:*[e:archetype_id='" + $c.Code + "']/e:value", $nm)) {
            $count++
            $t = ($v.GetAttribute('type', $xsi) -split ':')[-1]
            if (@($c.Types | Where-Object { Test-TypeConforms $t $_ }).Count -eq 0) {
                $bad += ($c.Name + ' (' + $c.Code + '): data type ' + $t + ', the archetype requires ' + ($c.Types -join ' or '))
            }
        }
    }
    foreach ($c in @($constraints | Where-Object { $_.Kind -eq 'code' })) {
        foreach ($v in $doc.SelectNodes("//e:*[e:archetype_id='" + $c.Code + "']/e:value", $nm)) {
            if (-not (Test-TypeConforms (($v.GetAttribute('type', $xsi) -split ':')[-1]) $c.Type)) { continue }
            $cv = $v.SelectSingleNode('e:codeValue', $nm)
            $sn = $v.SelectSingleNode('e:codingSchemeName', $nm)
            if ($null -eq $cv -and $null -eq $sn) { continue }
            $what = $c.Name + ' (' + $c.Code + ')'
            if ($null -ne $cv -and ($null -ne $c.Regex -or $c.Codes.Count -gt 0)) {
                $count++
                $t = $cv.InnerText.Trim()
                if ($null -ne $c.Regex) { if (-not $c.Regex.IsMatch($t)) { $bad += ($what + ": code '" + $t + "' does not match /" + $c.Pattern + '/') } }
                elseif ($c.Codes -notcontains $t) { $bad += ($what + ": code '" + $t + "' is not one of " + ($c.Codes -join ', ')) }
            }
            if ($null -ne $sn -and $c.Schemes.Count -gt 0) {
                $count++
                $t = $sn.InnerText.Trim()
                if ($c.Schemes -notcontains $t) { $bad += ($what + ": code system '" + $t + "', the archetype requires " + ($c.Schemes -join ' or ')) }
            }
        }
    }
    foreach ($c in @($constraints | Where-Object { $_.Kind -eq 'quantity' })) {
        $sub = $(if ($c.Sub) { '/e:' + $c.Sub } else { '' })
        foreach ($v in $doc.SelectNodes("//e:*[e:archetype_id='" + $c.Code + "']/e:value" + $sub + "[e:value][e:units]", $nm)) {
            $text = $v.SelectSingleNode('e:value', $nm).InnerText.Trim()
            $un = $v.SelectSingleNode('e:units/e:codeValue', $nm)
            $unit = $(if ($null -ne $un) { $un.InnerText.Trim() } else { '' })
            $what = $c.Name + ' (' + $c.Code + ')' + $(if ($c.Sub) { ', ' + $c.Sub } else { '' }) + ': ' + $text + ' ' + $unit
            if (@($c.Units).Count -gt 0) {
                $count++
                if ($c.Units -notcontains $unit) { $bad += ($what + " - unit not allowed; allowed: " + ($c.Units -join ', ')) }
            }
            $us = $v.SelectSingleNode('e:units/e:codingSchemeName', $nm)
            if (@($c.Schemes).Count -gt 0 -and $null -ne $us) {
                $count++
                if ($c.Schemes -notcontains $us.InnerText.Trim()) { $bad += ($what + " - unit system '" + $us.InnerText.Trim() + "', the archetype requires " + ($c.Schemes -join ' or ')) }
            }
            if ($null -ne $c.Range) {
                $count++
                $x = 0.0
                if (-not [double]::TryParse($text, [Globalization.NumberStyles]::Float, $inv, [ref]$x)) { $bad += ($what + ' - not a number') }
                elseif (-not (Test-Interval $c.Range $x)) { $bad += ($what + (Format-Allowed $c.Range)) }
            }
        }
    }
    foreach ($c in @($constraints | Where-Object { $_.Kind -eq 'textcode' })) {
        foreach ($v in $doc.SelectNodes("//e:*[e:archetype_id='" + $c.Code + "']/e:value/e:" + $c.Sub, $nm)) {
            $what = $c.Name + ' (' + $c.Code + '), ' + $c.Sub
            $cv = $v.SelectSingleNode('e:codeValue', $nm)
            if ($null -ne $cv -and @($c.Codes).Count -gt 0) {
                $count++
                if ($c.Codes -notcontains $cv.InnerText.Trim()) { $bad += ($what + ": code '" + $cv.InnerText.Trim() + "' is not one of " + ($c.Codes -join ', ')) }
            }
            $sn = $v.SelectSingleNode('e:codingSchemeName', $nm)
            if ($null -ne $sn -and @($c.Schemes).Count -gt 0) {
                $count++
                if ($c.Schemes -notcontains $sn.InnerText.Trim()) { $bad += ($what + ": code system '" + $sn.InnerText.Trim() + "', the archetype requires " + ($c.Schemes -join ' or ')) }
            }
        }
    }
    return New-Object PSObject -Property @{ Count = $count; Bad = $bad; Unit = 'check' }
}

# ---------------------------------------------------------------- step 2: EN ISO 13606, the nodes

# The definition of the archetype as a tree: every object with its class, code and occurrences, every
# attribute with its existence and, when it holds several objects, its cardinality.
$script:rcClasses = @('COMPOSITION', 'SECTION', 'ENTRY', 'CLUSTER', 'ELEMENT')
$script:tree = $null

function Read-En13606Tree($lines) {
    $root = $null
    $stack = New-Object System.Collections.ArrayList
    $i = 0
    while ($i -lt $lines.Length -and $lines[$i] -notmatch '^definition\s*$') { $i++ }
    for ($i++; $i -lt $lines.Length; $i++) {
        $l = $lines[$i]
        if ($l -match '^(ontology|invariant)\b') { break }
        $o = [regex]::Match($l, '^\s*([A-Z_]+)\[(at\d+(?:\.\d+)*)\]\s+occurrences matches \{(\d+)\.\.(\d+|\*)\}\s+matches \{(.*)$')
        if ($o.Success) {
            $rest = $o.Groups[5].Value
            $obj = New-Object PSObject -Property @{ Class = $o.Groups[1].Value; Code = $o.Groups[2].Value
                Min = [int]$o.Groups[3].Value; Max = $(if ($o.Groups[4].Value -eq '*') { [int]::MaxValue } else { [int]$o.Groups[4].Value })
                Name = [regex]::Match($rest, '--\s*(.*?)\s*$').Groups[1].Value; Attrs = (New-Object System.Collections.ArrayList) }
            if ($stack.Count -gt 0) { [void]$stack[$stack.Count - 1].Children.Add($obj) } else { $root = $obj }
            # an object whose block closes on the same line has nothing below it
            if (($rest -replace '--.*$', '').Trim() -eq '') { [void]$stack.Add($obj) }
            continue
        }
        $a = [regex]::Match($l, '^\s*([A-Za-z_]+) existence matches \{(\d+)\.\.(\d+)\}(?: cardinality matches \{(\d+)\.\.(\d+|\*)[^}]*\})? matches \{(.*)$')
        if ($a.Success -and $stack.Count -gt 0) {
            $multi = $a.Groups[4].Success
            $att = New-Object PSObject -Property @{ Name = $a.Groups[1].Value; Min = [int]$a.Groups[2].Value; Multiple = $multi
                CMin = $(if ($multi) { [int]$a.Groups[4].Value } else { 0 })
                CMax = $(if (-not $multi -or $a.Groups[5].Value -eq '*') { [int]::MaxValue } else { [int]$a.Groups[5].Value })
                Children = (New-Object System.Collections.ArrayList) }
            [void]$stack[$stack.Count - 1].Attrs.Add($att)
            if ($a.Groups[6].Value.Trim() -eq '') { [void]$stack.Add($att) }
            continue
        }
        if ($l -match '^\s*\}\s*(--.*)?$' -and $stack.Count -gt 0) { $stack.RemoveAt($stack.Count - 1) }
    }
    return $root
}

# The nodes of the tree - COMPOSITION, SECTION, ENTRY, CLUSTER and ELEMENT, not the data types.
function Get-TreeNodes($o) {
    $n = $(if ($script:rcClasses -contains $o.Class) { 1 } else { 0 })
    foreach ($a in $o.Attrs) { foreach ($c in $a.Children) { $n += Get-TreeNodes $c } }
    return $n
}

function Get-NodeCode($el) {
    foreach ($c in $el.ChildNodes) { if ($c.NodeType -eq 'Element' -and $c.LocalName -eq 'archetype_id') { return $c.InnerText.Trim() } }
    return ''
}

function Get-Label($o) { if ($o.Name -ne '') { return $o.Name + ' (' + $o.Code + ')' } else { return $o.Code } }

# One node of an instance against its object in the archetype: the attributes the object requires,
# the number of nodes in a container, how many times each of its nodes occurs, and for every node
# of the instance below it - its code, that the archetype has that node in this place, and its class.
function Test-En13606Node($el, $obj) {
    foreach ($att in $obj.Attrs) {
        $kids = @($el.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.LocalName -eq $att.Name })
        $nodes = @($att.Children | Where-Object { $script:rcClasses -contains $_.Class })
        if ($att.Min -ge 1) {
            $script:sCount++
            if ($kids.Count -eq 0) { [void]$script:sBad.Add((Get-Label $obj) + ': ' + $att.Name + ' is missing - the archetype requires it'); continue }
        }
        if ($nodes.Count -eq 0 -or $kids.Count -eq 0) { continue }
        if ($att.Multiple) {
            $script:sCount++
            if ($kids.Count -lt $att.CMin -or $kids.Count -gt $att.CMax) {
                [void]$script:sBad.Add((Get-Label $obj) + ': ' + (Get-Count $kids.Count 'node') + ' in ' + $att.Name + ', the archetype allows ' + (Format-Range $att.CMin $att.CMax))
            }
        }
        foreach ($c in $nodes) {
            $script:sCount++
            $n = @($kids | Where-Object { (Get-NodeCode $_) -eq $c.Code }).Count
            if ($n -eq 0 -and $c.Min -gt 0) { [void]$script:sBad.Add((Get-Label $c) + ' in ' + (Get-Label $obj) + ': missing - the archetype requires ' + (Format-Range $c.Min $c.Max)) }
            elseif ($n -lt $c.Min -or $n -gt $c.Max) {
                [void]$script:sBad.Add((Get-Label $c) + ' in ' + (Get-Label $obj) + ': ' + (Get-Count $n 'time') + ', the archetype allows ' + (Format-Range $c.Min $c.Max))
            }
        }
        foreach ($k in $kids) {
            $script:sCount++
            $code = Get-NodeCode $k
            if ($code -eq '') { [void]$script:sBad.Add($att.Name + ' of ' + (Get-Label $obj) + ': a node without a code from the archetype'); continue }
            $c = $nodes | Where-Object { $_.Code -eq $code } | Select-Object -First 1
            if ($null -eq $c) { [void]$script:sBad.Add($att.Name + ' of ' + (Get-Label $obj) + ': code ' + $code + ' - the archetype has no such node here'); continue }
            $t = ($k.GetAttribute('type', 'http://www.w3.org/2001/XMLSchema-instance') -split ':')[-1]
            if ($t -ne '' -and $t -ne $c.Class) { [void]$script:sBad.Add((Get-Label $c) + ': class ' + $t + ', the archetype requires ' + $c.Class); continue }
            Test-En13606Node $k $c
        }
    }
}

function Test-En13606Structure($doc) {
    $script:sCount = 1
    $script:sBad = New-Object System.Collections.ArrayList
    $r = $doc.DocumentElement
    $code = Get-NodeCode $r
    if ($code -ne $script:tree.Code -or $r.LocalName -ne $script:tree.Class) {
        [void]$script:sBad.Add('root: ' + $r.LocalName + ' ' + $code + ', the archetype starts with ' + $script:tree.Class + ' ' + $script:tree.Code)
    } else { Test-En13606Node $r $script:tree }
    return New-Object PSObject -Property @{ Count = $script:sCount; Bad = @($script:sBad) }
}

# ---------------------------------------------------------------- step 2: openEHR

function Read-Interval([string]$text) {
    $lo = $null; $hi = $null; $loIn = $true; $hiIn = $true
    if ($text.Contains('..')) {
        $p = $text -split '\.\.', 2
        $a = $p[0].Trim(); $b = $p[1].Trim()
        if ($a.StartsWith('>=')) { $a = $a.Substring(2) } elseif ($a.StartsWith('>')) { $a = $a.Substring(1); $loIn = $false }
        if ($b.StartsWith('<=')) { $b = $b.Substring(2) } elseif ($b.StartsWith('<')) { $b = $b.Substring(1); $hiIn = $false }
        if ($a -ne '' -and $a -ne '*') { $lo = [double]::Parse($a, $inv) }
        if ($b -ne '' -and $b -ne '*') { $hi = [double]::Parse($b, $inv) }
    } else {
        $t = $text.Trim()
        if ($t.StartsWith('>=')) { $lo = [double]::Parse($t.Substring(2), $inv) }
        elseif ($t.StartsWith('>')) { $lo = [double]::Parse($t.Substring(1), $inv); $loIn = $false }
        elseif ($t.StartsWith('<=')) { $hi = [double]::Parse($t.Substring(2), $inv) }
        elseif ($t.StartsWith('<')) { $hi = [double]::Parse($t.Substring(1), $inv); $hiIn = $false }
        else { $lo = [double]::Parse($t, $inv); $hi = $lo }
    }
    return New-Object PSObject -Property @{ Text = $text; Lo = $lo; Hi = $hi; LoIn = $loIn; HiIn = $hiIn }
}

function Test-Interval($iv, [double]$v) {
    if ($null -ne $iv.Lo) { if ($iv.LoIn) { if ($v -lt $iv.Lo) { return $false } } elseif ($v -le $iv.Lo) { return $false } }
    if ($null -ne $iv.Hi) { if ($iv.HiIn) { if ($v -gt $iv.Hi) { return $false } } elseif ($v -ge $iv.Hi) { return $false } }
    return $true
}

# Four kinds of constraint are read: quantities (units, interval, precision), coded texts with
# local codes, the slots of a composition and the number of its content items.
function Get-OpenEhrConstraints($archetypes) {
    $list = @()
    foreach ($a in $archetypes) {
        $id = $a.Id; $lines = $a.Lines; $isComp = $id -match '-COMPOSITION\.'
        $code = ''; $name = ''
        for ($i = 0; $i -lt $lines.Length; $i++) {
            $s = [regex]::Match($lines[$i], 'allow_archetype\s+([A-Z_]+)\[(at\d+)\]\s+occurrences\s+matches\s+\{(\d+)\.\.(\d+|\*)\}.*--\s*(.*?)\s*$')
            if ($s.Success -and $isComp) {
                $pattern = ''
                for ($j = $i + 1; $j -lt $lines.Length -and $j -le $i + 4; $j++) {
                    $inc = [regex]::Match($lines[$j], 'archetype_id/value\s+matches\s+\{/(.*)/\}')
                    if ($inc.Success) { $pattern = $inc.Groups[1].Value; break }
                }
                $max = $(if ($s.Groups[4].Value -eq '*') { [int]::MaxValue } else { [int]$s.Groups[4].Value })
                $list += New-Object PSObject -Property @{ Kind = 'slot'; Archetype = $id; Code = $s.Groups[2].Value
                    Name = $s.Groups[5].Value; RmType = $s.Groups[1].Value; Pattern = $pattern; Min = [int]$s.Groups[3].Value; Max = $max }
                continue
            }
            $k = [regex]::Match($lines[$i], '^\s*content\s+cardinality\s+matches\s+\{(\d+)\.\.(\d+|\*)')
            if ($k.Success -and $isComp) {
                $max = $(if ($k.Groups[2].Value -eq '*') { [int]::MaxValue } else { [int]$k.Groups[2].Value })
                $list += New-Object PSObject -Property @{ Kind = 'content'; Archetype = $id; Min = [int]$k.Groups[1].Value; Max = $max }
                continue
            }
            $e = [regex]::Match($lines[$i], 'ELEMENT\[(at\d+)\].*--\s*(.*?)\s*$')
            if ($e.Success) { $code = $e.Groups[1].Value; $name = $e.Groups[2].Value; continue }
            if ($lines[$i] -match '\[local::' -and $code -ne '') {
                $codes = @()
                for ($j = $i; $j -lt $lines.Length; $j++) {
                    $part = $lines[$j] -replace '--.*$', ''
                    $codes += @([regex]::Matches($part, 'at\d+') | ForEach-Object { $_.Value })
                    if ($part.Contains(']')) { $i = $j; break }
                }
                $list += New-Object PSObject -Property @{ Kind = 'codes'; Archetype = $id; Code = $code; Name = $name; Codes = $codes }
                continue
            }
            if ($lines[$i] -notmatch 'C_DV_QUANTITY') { continue }
            $options = @(); $opt = $null
            for ($j = $i + 1; $j -lt $lines.Length -and $lines[$j] -notmatch '^\s*}\s*$'; $j++) {
                $u = [regex]::Match($lines[$j], 'units\s*=\s*<"(.*)">')
                $g = [regex]::Match($lines[$j], 'magnitude\s*=\s*<\|(.*)\|>')
                $p = [regex]::Match($lines[$j], 'precision\s*=\s*<\|(.*)\|>')
                if ($u.Success) {
                    $opt = New-Object PSObject -Property @{ Units = $u.Groups[1].Value; Magnitude = $null; Precision = $null }
                    $options += $opt
                } elseif ($g.Success -and $null -ne $opt) { $opt.Magnitude = Read-Interval $g.Groups[1].Value }
                elseif ($p.Success -and $null -ne $opt) { $opt.Precision = [int]$p.Groups[1].Value }
            }
            if ($options.Count -gt 0) {
                $list += New-Object PSObject -Property @{ Kind = 'quantity'; Archetype = $id; Code = $code; Name = $name; Options = $options }
            }
        }
    }
    return $list
}

# An XPath that matches by local name, so that it reads a canonical instance and an instance in
# the form of a TDS alike: 'value/magnitude' -> *[local-name()='value']/*[local-name()='magnitude']
function Get-Path([string]$p) { return (($p -split '/') | ForEach-Object { "*[local-name()='" + $_ + "']" }) -join '/' }

# The content items of a composition: in a canonical instance the elements "content", in the form
# of a TDS the elements named after the archetypes - in both, the ones with an archetype identifier.
$script:itemsXp = "*[starts-with(@archetype_node_id,'openEHR-')]"

# The class of the Reference Model of a content item: xsi:type, the attribute "type" of a TDS, or
# the class named in the archetype identifier.
function Get-RmType($item) {
    $t = $item.GetAttribute('type', 'http://www.w3.org/2001/XMLSchema-instance')
    if ($t -eq '') { $t = $item.GetAttribute('type') }
    if ($t -eq '') { $t = [regex]::Match($item.GetAttribute('archetype_node_id'), '^openEHR-[A-Za-z0-9]+-([A-Z_]+)\.').Groups[1].Value }
    return ($t -split ':')[-1]
}

# The elements with a given code whose nearest archetype root is the given archetype.
function Get-Nodes($doc, $nm, $c) {
    $xp = "//*[@archetype_node_id='" + $c.Code + "'][ancestor-or-self::*[starts-with(@archetype_node_id,'openEHR-')][1]/@archetype_node_id='" + $c.Archetype + "']"
    return $doc.SelectNodes($xp, $nm)
}

function Format-Range($min, $max) { return ($min.ToString() + '..' + $(if ($max -eq [int]::MaxValue) { '*' } else { $max.ToString() })) }

function Test-OpenEhr([string]$path, $constraints) {
    $doc = New-Object System.Xml.XmlDocument
    $doc.Load($path)
    $nm = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
    $nm.AddNamespace('o', 'http://schemas.openehr.org/v1')
    $count = 0; $bad = @()
    foreach ($c in @($constraints | Where-Object { $_.Kind -eq 'quantity' })) {
        foreach ($el in (Get-Nodes $doc $nm $c)) {
            $v = $el.SelectSingleNode((Get-Path 'value') + '[' + (Get-Path 'magnitude') + ']')
            if ($null -eq $v) { continue }
            $count++
            $text = $v.SelectSingleNode((Get-Path 'magnitude')).InnerText.Trim()
            $un = $v.SelectSingleNode((Get-Path 'units'))
            $units = $(if ($null -ne $un) { $un.InnerText.Trim() } else { '' })
            $what = $c.Name + ' (' + $c.Code + '): ' + $text + ' ' + $units
            $opt = $c.Options | Where-Object { $_.Units -eq $units } | Select-Object -First 1
            if ($null -eq $opt) { $bad += ($what + ' - unit not allowed; allowed: ' + (($c.Options | ForEach-Object { $_.Units }) -join ', ')); continue }
            $value = [double]::Parse($text, $inv)
            if ($null -ne $opt.Magnitude -and -not (Test-Interval $opt.Magnitude $value)) { $bad += ($what + ' - outside |' + $opt.Magnitude.Text + '|'); continue }
            if ($null -ne $opt.Precision -and $opt.Precision -ge 0) {
                $dec = $(if ($text.Contains('.')) { $text.Length - $text.IndexOf('.') - 1 } else { 0 })
                if ($dec -gt $opt.Precision) { $bad += ($what + ' - more decimals than the precision of ' + $opt.Precision) }
            }
        }
    }
    foreach ($c in @($constraints | Where-Object { $_.Kind -eq 'codes' })) {
        foreach ($el in (Get-Nodes $doc $nm $c)) {
            $dc = $el.SelectSingleNode((Get-Path 'value/defining_code'))
            if ($null -eq $dc) { continue }
            $count++
            $term = $dc.SelectSingleNode((Get-Path 'terminology_id/value')).InnerText.Trim()
            $cs = $dc.SelectSingleNode((Get-Path 'code_string')).InnerText.Trim()
            if ($term -ne 'local' -or $c.Codes -notcontains $cs) { $bad += ($c.Name + ' (' + $c.Code + '): ' + $term + '::' + $cs + ' - allowed: ' + ($c.Codes -join ', ')) }
        }
    }
    $root = $doc.DocumentElement
    $rid = $root.GetAttribute('archetype_node_id')
    $slots = @($constraints | Where-Object { $_.Kind -eq 'slot' -and $_.Archetype -eq $rid })
    $n = $root.SelectNodes($script:itemsXp).Count
    foreach ($k in @($constraints | Where-Object { $_.Kind -eq 'content' -and $_.Archetype -eq $rid })) {
        $count++
        if ($n -lt $k.Min -or $n -gt $k.Max) { $bad += ('content: ' + (Get-Count $n 'item') + ', the composition requires ' + (Format-Range $k.Min $k.Max)) }
    }
    if ($slots.Count -gt 0) {
        $used = @{}
        foreach ($item in $root.SelectNodes($script:itemsXp)) {
            $count++
            $aid = $item.GetAttribute('archetype_node_id')
            $type = Get-RmType $item
            $slot = $slots | Where-Object { $_.RmType -eq $type -and [regex]::IsMatch($aid, '^(?:' + $_.Pattern + ')$') } | Select-Object -First 1
            if ($null -eq $slot) { $bad += ('content: ' + $aid + ' - no slot of the composition allows it'); continue }
            $used[$slot.Code] = 1 + [int]$used[$slot.Code]
        }
        foreach ($slot in $slots) {
            $u = [int]$used[$slot.Code]
            if ($u -lt $slot.Min -or $u -gt $slot.Max) { $bad += ('slot ' + $slot.Name + ' (' + $slot.Code + '): filled ' + (Get-Count $u 'time') + ', allowed ' + (Format-Range $slot.Min $slot.Max)) }
        }
    }
    # with an operational template: every node of the instance must be one the template keeps
    if ($null -ne $script:optNodes) {
        $count++
        if ($rid -ne $script:optRoot) { $bad += ('composition: ' + $rid + ' - the template is built on ' + $script:optRoot) }
        foreach ($el in $doc.SelectNodes("//*[starts-with(@archetype_node_id,'at')]", $nm)) {
            $count++
            $a = $el.SelectSingleNode("ancestor::*[starts-with(@archetype_node_id,'openEHR-')][1]", $nm)
            $aid = $(if ($null -ne $a) { $a.GetAttribute('archetype_node_id') } else { '' })
            $code = $el.GetAttribute('archetype_node_id')
            if (-not $script:optNodes.ContainsKey($aid + '|' + $code)) { $bad += ($el.LocalName + ' ' + $code + ' in ' + $aid + ' - the template leaves this node out') }
        }
        # every node that the template keeps right below a node of the instance, as many times as it allows
        foreach ($el in $doc.SelectNodes('//*[@archetype_node_id]', $nm)) {
            $id = $el.GetAttribute('archetype_node_id')
            $rootId = $id
            if (-not $id.StartsWith('openEHR-')) {
                $a = $el.SelectSingleNode("ancestor::*[starts-with(@archetype_node_id,'openEHR-')][1]", $nm)
                if ($null -eq $a) { continue }
                $rootId = $a.GetAttribute('archetype_node_id')
            }
            $specs = $script:optKids[$rootId + '|' + $id]
            if ($null -eq $specs) { continue }
            $below = @($el.SelectNodes('.//*[@archetype_node_id]', $nm) | Where-Object { [object]::ReferenceEquals($_.SelectSingleNode('ancestor::*[@archetype_node_id][1]', $nm), $el) })
            foreach ($sp in $specs) {
                $n = @{}; $present = 0
                foreach ($k in $sp.Kids) { $n[$k.Code] = @($below | Where-Object { $_.GetAttribute('archetype_node_id') -eq $k.Code }).Count; $present += $n[$k.Code] }
                if ($present -eq 0 -and $sp.Min -eq 0) { continue }
                if ($present -eq 0 -and $sp.Single -and $sp.Kids.Count -gt 1) { $count++; $bad += ($sp.Owner + ': ' + $sp.Attr + ' is missing - the template requires it'); continue }
                foreach ($k in $sp.Kids) {
                    # of several alternatives of a single attribute, one is present and the others are not required
                    if ($sp.Single -and $sp.Kids.Count -gt 1 -and $n[$k.Code] -eq 0) { continue }
                    $count++
                    $label = $(if ($k.Name -ne '') { $k.Name + ' (' + $k.Code + ')' } else { $k.Code })
                    if ($n[$k.Code] -eq 0 -and $k.Min -gt 0) { $bad += ($label + ' in ' + $sp.Owner + ': missing - the template requires ' + (Format-Range $k.Min $k.Max)) }
                    elseif ($n[$k.Code] -lt $k.Min -or $n[$k.Code] -gt $k.Max) {
                        $bad += ($label + ' in ' + $sp.Owner + ': ' + (Get-Count $n[$k.Code] 'time') + ', the template allows ' + (Format-Range $k.Min $k.Max))
                    }
                }
            }
        }
    }
    return New-Object PSObject -Property @{ Count = $count; Bad = $bad; Unit = 'check' }
}

# ---------------------------------------------------------------- step 2: openEHR operational template

# An operational template (.opt) holds the archetypes as the template has narrowed them. The same
# four kinds of constraint are read from it, and also every node the template keeps, so that a
# node it leaves out (occurrences 0..0) is found in an instance.
$script:optNodes = $null
$script:optKids = $null
$script:onm = $null

function Get-OptText($node, [string]$xp) {
    $n = $node.SelectSingleNode($xp, $script:onm)
    if ($null -eq $n) { return '' }
    return $n.InnerText.Trim()
}

function Read-OptInterval($iv) {
    $lo = $null; $hi = $null
    $a = Get-OptText $iv 'o:lower'; $b = Get-OptText $iv 'o:upper'
    if ((Get-OptText $iv 'o:lower_unbounded') -ne 'true' -and $a -ne '') { $lo = [double]::Parse($a, $inv) }
    if ((Get-OptText $iv 'o:upper_unbounded') -ne 'true' -and $b -ne '') { $hi = [double]::Parse($b, $inv) }
    $loIn = (Get-OptText $iv 'o:lower_included') -ne 'false'
    $hiIn = (Get-OptText $iv 'o:upper_included') -ne 'false'
    $text = $(if ($null -eq $lo) { '*' } elseif ($loIn) { $a } else { '>' + $a }) + '..' + $(if ($null -eq $hi) { '*' } elseif ($hiIn) { $b } else { '<' + $b })
    return New-Object PSObject -Property @{ Text = $text; Lo = $lo; Hi = $hi; LoIn = $loIn; HiIn = $hiIn }
}

function Read-OptRange($iv) {
    if ($null -eq $iv) { return @(0, [int]::MaxValue) }
    $max = $(if ((Get-OptText $iv 'o:upper_unbounded') -eq 'true') { [int]::MaxValue } else { [int](Get-OptText $iv 'o:upper') })
    return @([int](Get-OptText $iv 'o:lower'), $max)
}

function Add-OptNode($node, [string]$root, $terms) {
    $aid = Get-OptText $node 'o:archetype_id/o:value'
    if ($aid -ne '') {
        $root = $aid; $terms = @{}
        foreach ($t in $node.SelectNodes('o:term_definitions', $script:onm)) { $terms[$t.GetAttribute('code')] = Get-OptText $t "o:items[@id='text']" }
    }
    $code = Get-OptText $node 'o:node_id'
    if ($code -match '^at\d+(\.\d+)*$') { $script:optNodes[$root + '|' + $code] = $true }
    $rm = Get-OptText $node 'o:rm_type_name'
    # the nodes the template keeps right below this one, attribute by attribute: how many times each
    # may occur, and whether the attribute is required
    $self = $(if ($aid -ne '') { $aid } else { $code })
    if ($self -match '^(at\d+(\.\d+)*|openEHR-.+)$') {
        $selfName = $(if ($aid -ne '') { [string]$terms['at0000'] } else { [string]$terms[$code] })
        foreach ($at in $node.SelectNodes('o:attributes', $script:onm)) {
            $an = Get-OptText $at 'o:rm_attribute_name'
            # the content of a composition is checked through its slots
            if ($rm -eq 'COMPOSITION' -and $an -eq 'content') { continue }
            $kids = @()
            foreach ($c in $at.SelectNodes('o:children', $script:onm)) {
                if ($c.GetAttribute('type', 'http://www.w3.org/2001/XMLSchema-instance') -eq 'ARCHETYPE_SLOT') { continue }
                $cid = Get-OptText $c 'o:archetype_id/o:value'
                if ($cid -ne '') { $cname = Get-OptText $c "o:term_definitions[@code='at0000']/o:items[@id='text']" }
                else { $cid = Get-OptText $c 'o:node_id'; $cname = [string]$terms[$cid] }
                if ($cid -notmatch '^(at\d+(\.\d+)*|openEHR-.+)$') { continue }
                $r = Read-OptRange $c.SelectSingleNode('o:occurrences', $script:onm)
                $kids += New-Object PSObject -Property @{ Code = $cid; Name = $cname; Min = $r[0]; Max = $r[1] }
            }
            if ($kids.Count -eq 0) { continue }
            $ex = Read-OptRange $at.SelectSingleNode('o:existence', $script:onm)
            # a container whose cardinality requires an item is treated as required: the form of a TDS
            # does not show an empty container apart from a missing one
            $card = $at.SelectSingleNode('o:cardinality/o:interval', $script:onm)
            if ($null -ne $card -and (Read-OptRange $card)[0] -gt $ex[0]) { $ex = @((Read-OptRange $card)[0], $ex[1]) }
            $key = $root + '|' + $self
            if (-not $script:optKids.ContainsKey($key)) { $script:optKids[$key] = New-Object System.Collections.ArrayList }
            [void]$script:optKids[$key].Add((New-Object PSObject -Property @{ Attr = $an; Min = $ex[0]
                Single = ($at.GetAttribute('type', 'http://www.w3.org/2001/XMLSchema-instance') -eq 'C_SINGLE_ATTRIBUTE')
                Owner = $(if ($selfName -ne '') { $selfName + ' (' + $self + ')' } else { $self }); Kids = $kids }))
        }
    }
    if ($rm -eq 'ELEMENT' -and $code -ne '') {
        $name = [string]$terms[$code]
        foreach ($v in $node.SelectNodes("o:attributes[o:rm_attribute_name='value']/o:children", $script:onm)) {
            if ($v.GetAttribute('type', 'http://www.w3.org/2001/XMLSchema-instance') -eq 'C_DV_QUANTITY') {
                $options = @()
                foreach ($l in $v.SelectNodes('o:list', $script:onm)) {
                    $m = $l.SelectSingleNode('o:magnitude', $script:onm)
                    $p = Get-OptText $l 'o:precision/o:lower'
                    $options += New-Object PSObject -Property @{ Units = (Get-OptText $l 'o:units')
                        Magnitude = $(if ($null -ne $m) { Read-OptInterval $m } else { $null }); Precision = $(if ($p -ne '') { [int]$p } else { $null }) }
                }
                if ($options.Count -gt 0) { [void]$script:optList.Add((New-Object PSObject -Property @{ Kind = 'quantity'; Archetype = $root; Code = $code; Name = $name; Options = $options })) }
            } elseif ((Get-OptText $v 'o:rm_type_name') -eq 'DV_CODED_TEXT') {
                $cp = $v.SelectSingleNode("o:attributes[o:rm_attribute_name='defining_code']/o:children[o:terminology_id/o:value='local']", $script:onm)
                if ($null -ne $cp) {
                    $codes = @($cp.SelectNodes('o:code_list', $script:onm) | ForEach-Object { $_.InnerText.Trim() })
                    [void]$script:optList.Add((New-Object PSObject -Property @{ Kind = 'codes'; Archetype = $root; Code = $code; Name = $name; Codes = $codes }))
                }
            }
        }
    }
    foreach ($at in $node.SelectNodes('o:attributes', $script:onm)) {
        if ($rm -eq 'COMPOSITION' -and (Get-OptText $at 'o:rm_attribute_name') -eq 'content') {
            $r = Read-OptRange $at.SelectSingleNode('o:cardinality/o:interval', $script:onm)
            [void]$script:optList.Add((New-Object PSObject -Property @{ Kind = 'content'; Archetype = $root; Min = $r[0]; Max = $r[1] }))
            foreach ($c in $at.SelectNodes('o:children[o:archetype_id]', $script:onm)) {
                $cid = Get-OptText $c 'o:archetype_id/o:value'
                $r = Read-OptRange $c.SelectSingleNode('o:occurrences', $script:onm)
                [void]$script:optList.Add((New-Object PSObject -Property @{ Kind = 'slot'; Archetype = $root; Code = $cid
                    Name = (Get-OptText $c "o:term_definitions[@code='at0000']/o:items[@id='text']"); RmType = (Get-OptText $c 'o:rm_type_name')
                    Pattern = [regex]::Escape($cid); Min = $r[0]; Max = $r[1] }))
            }
        }
        foreach ($c in $at.SelectNodes('o:children', $script:onm)) { Add-OptNode $c $root $terms }
    }
}

function Get-OptConstraints([string]$path) {
    $doc = New-Object System.Xml.XmlDocument
    $doc.Load($path)
    $script:onm = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
    $script:onm.AddNamespace('o', 'http://schemas.openehr.org/v1')
    $script:optList = New-Object System.Collections.ArrayList
    $script:optNodes = @{}
    $script:optKids = @{}
    $script:optTemplate = Get-OptText $doc.DocumentElement 'o:template_id/o:value'
    $def = $doc.DocumentElement.SelectSingleNode('o:definition', $script:onm)
    $script:optRoot = Get-OptText $def 'o:archetype_id/o:value'
    Add-OptNode $def '' @{}
    return @($script:optList)
}

# ---------------------------------------------------------------- output

# The output is kept within this many columns, so that it reads in a narrow window.
$script:Width = 94

# Breaks a text into lines of at most $width characters, at spaces; a longer word is cut.
function Split-Words([string]$text, [int]$width) {
    $lines = @()
    $cur = ''
    foreach ($w in ($text -split ' ')) {
        if ($cur -eq '') { $cur = $w }
        elseif (($cur.Length + 1 + $w.Length) -le $width) { $cur += ' ' + $w }
        else { $lines += $cur; $cur = $w }
    }
    $lines += $cur
    $out = @()
    foreach ($l in $lines) {
        while ($l.Length -gt $width) { $out += $l.Substring(0, $width); $l = $l.Substring($width) }
        $out += $l
    }
    return $out
}

# A label in the left column and its text; a text too long for one line continues under it.
function Write-Line([string]$label, [string]$text, [string]$color = '') {
    $w = $script:Width - 12
    $lines = $(if ($text.Length -le $w) { @($text) } else { @(Split-Words $text $w) })
    $first = $true
    foreach ($l in $lines) {
        $t = '  ' + $(if ($first) { $label.PadRight(10) } else { ' ' * 10 }) + $l
        $first = $false
        if ($color -eq '') { Write-Host $t } else { Write-Host $t -ForegroundColor $color }
    }
}

function Write-Rule { Write-Host ('  ' + ('-' * ($script:Width - 2))) -ForegroundColor DarkGray }

# One step of one instance: the result, whether it is the expected one, and the details.
function Write-Step([string]$step, [bool]$ok, [string]$text, $detail, [string]$expect) {
    $res = $(if ($ok) { 'VALID' } else { 'INVALID' })
    if ($text -ne '') { $res += ' - ' + $text }
    $color = $(if ($ok) { 'Green' } else { 'Red' })
    $verdict = ''
    if ($expect -ne '') {
        $match = ($expect -eq 'valid') -eq $ok
        $res = $res.PadRight(32)
        # The verdict has its own colour: green whenever the result is the expected one, even for INVALID.
        $verdict = $(if ($match) { 'as expected' } else { 'NOT AS EXPECTED' })
        if ($match) { $script:matched++ } else { $script:mismatch++ }
    }
    if ($verdict -eq '') {
        Write-Host ('    ' + $step.PadRight(21) + $res) -ForegroundColor $color
    } else {
        Write-Host ('    ' + $step.PadRight(21) + $res) -ForegroundColor $color -NoNewline
        Write-Host $verdict -ForegroundColor $(if ($match) { 'Green' } else { 'Red' })
    }
    $d = @($detail)
    foreach ($x in @($d | Select-Object -First 5)) {
        foreach ($l in (Split-Words ([string]$x) ($script:Width - 25))) { Write-Host ('    ' + (' ' * 21) + $l) -ForegroundColor $color }
    }
    if ($d.Count -gt 5) { Write-Host ('    ' + (' ' * 21) + '... and ' + ($d.Count - 5) + ' more') -ForegroundColor $color }
    if (-not $ok) { $script:instanceOk = $false }
}

# The result the name of an instance states for a step: valid, invalid, or nothing.
function Get-Expected([string]$name, [string]$step) {
    $n = $name.ToLowerInvariant()
    if ($n.StartsWith('instance-valid')) { return 'valid' }
    if ($n.StartsWith('instance-invalid-structural')) { if ($step -eq '2') { return 'valid' } else { return 'invalid' } }
    if ($n.StartsWith('instance-invalid-semantic')) { if ($step -eq '1') { return 'valid' } else { return 'invalid' } }
    return ''
}

function Get-Order([string]$name) {
    $n = $name.ToLowerInvariant()
    if ($n.StartsWith('instance-valid')) { return 0 }
    if ($n.StartsWith('instance-invalid-structural')) { return 2 }
    if ($n.StartsWith('instance-invalid-semantic')) { return 3 }
    return 1
}

# ---------------------------------------------------------------- run

# The window stays open whatever happens, so that an error can be read.
try {
    Clear-Host
    $archetypes = @()
    foreach ($f in (Get-SetFiles '*.adl')) {
        $lines = Read-Lines $f.FullName
        $id = Get-ArchetypeId $lines
        if ($id -ne '') { $archetypes += New-Object PSObject -Property @{ Id = $id; File = $f; Lines = $lines } }
    }
    $openEHR = @($archetypes | Where-Object { $_.Id.StartsWith('openEHR-') }).Count -gt 0
    $framework = $(if ($openEHR) { 'openEHR' } else { 'EN ISO 13606' })
    Write-Host ('  VALIDITY CHECK OF ARCHETYPE INSTANCES - ' + $framework) -ForegroundColor Cyan
    Write-Line 'Folder' (Split-Path $dir -Leaf)
    if ($archetypes.Count -eq 0) { Write-Line '' 'No archetype (.adl) in this folder.' 'Yellow'; return }

    $derived = $false
    $opt = $null
    $tds = $null
    if ($openEHR) {
        $opt = @(Get-SetFiles '*.opt') | Select-Object -First 1
        $rm = @(Get-SetFiles 'Version.xsd') | Select-Object -First 1
        $rmName = 'Reference Model (RM) of openEHR, release 1.0.2'
        $tool = 'Archetype Designer'
        # the XML schema derived from the operational template (TDS): the file name of the
        # template with .xsd; it imports the schema of the reference model
        $tds = $null
        if ($null -ne $opt) {
            $cand = Join-Path $opt.DirectoryName ($opt.BaseName + '.xsd')
            if (Test-Path -LiteralPath $cand) { $tds = Get-Item -LiteralPath $cand }
        }
    } else {
        $rm = @(Get-SetFiles 'EN13606-RM.xsd') | Select-Object -First 1
        $dt = @(Get-SetFiles 'TS14796-dataTypes.xsd') | Select-Object -First 1
        if ($null -ne $dt) { Read-TypeTree $dt.FullName }
        $rmName = 'Reference Model (RM) of EN ISO 13606-1'
        $tool = 'LinkEHR Studio'
        if ($null -eq $rm) {
            # an XML schema derived from the archetype: the file name of the archetype with .xsd
            foreach ($a in $archetypes) {
                $cand = Join-Path $a.File.DirectoryName ($a.File.Name -replace '\.adl$', '.xsd')
                if (Test-Path -LiteralPath $cand) { $rm = Get-Item -LiteralPath $cand; $derived = $true; break }
            }
        }
    }
    if ($null -eq $rm) { Write-Line '' 'No XML schema of the reference model in this folder.' 'Yellow'; return }
    Write-Line 'What' 'Each instance - a sample record in XML - is checked against its model.'
    if ($derived) { Write-Line '' 'One check covers both its structure and its values. The files are only read.' }
    else {
        Write-Line '' 'Step 1 checks its structure, step 2 its nodes and values.'
        Write-Line '' 'An instance is valid when it passes both. The files are only read.'
    }
    if ($null -ne $tds) { Open-Schema $tds.FullName $true } else { Open-Schema $rm.FullName }
    if ($derived) {
        Write-Line 'Steps 1+2' 'Structural and semantic validity in one check:'
        Write-Line '' 'Against the XML schema derived from the archetype'
        Write-Line '' ('It carries both the ' + $rmName)
        Write-Line '' 'and the constraints of the archetype.'
        Write-Line '' (Get-Relative $rm.FullName)
        $constraints = @()
    } else {
        if ($null -ne $tds) {
            Write-Line 'Step 1' 'Structural validity: Against the XML schema of the operational template (TDS)'
            Write-Line '' (Get-Relative $tds.FullName)
            Write-Line '' ('which imports the ' + $rmName)
            Write-Line '' (Get-Relative $rm.FullName)
        } else {
            Write-Line 'Step 1' ('Structural validity: Against the ' + $rmName)
            Write-Line '' (Get-Relative $rm.FullName)
        }
        if ($null -ne $opt) {
            $constraints = @(Get-OptConstraints $opt.FullName)
            Write-Line 'Step 2' 'Semantic validity: Against the operational template'
            Write-Line '' ($script:optTemplate + ', built on ' + $archetypes.Count + ' archetypes')
            Write-Line '' (Get-Relative $opt.FullName)
        } else {
            if ($openEHR) { $constraints = @(Get-OpenEhrConstraints $archetypes) } else {
                $constraints = @(Get-En13606Constraints $archetypes)
                $script:tree = Read-En13606Tree $archetypes[0].Lines
            }
            if ($archetypes.Count -eq 1) { Write-Line 'Step 2' 'Semantic validity: Against the archetype'; Write-Line '' $archetypes[0].Id }
            else { Write-Line 'Step 2' ('Semantic validity: Against the constraints of ' + $archetypes.Count + ' archetypes') }
            foreach ($a in $archetypes) { Write-Line '' (Get-Relative $a.File.FullName) }
        }
        if ($openEHR) {
            $nq = @($constraints | Where-Object { $_.Kind -eq 'quantity' }).Count
            $nc = @($constraints | Where-Object { $_.Kind -eq 'codes' }).Count
            $nsl = @($constraints | Where-Object { $_.Kind -eq 'slot' }).Count
            $t = 'checked: ' + $nq + ' quantities, ' + $nc + ' coded texts, ' + $nsl + ' slots of the composition'
            if ($null -ne $opt) {
                Write-Line '' ($t + ',')
                Write-Line '' ('whether every node is one of the ' + $script:optNodes.Count + ' the template keeps,')
                Write-Line '' 'and whether it occurs as many times as the template allows'
            } else { Write-Line '' $t }
        } else {
            $nt = @($constraints | Where-Object { $_.Kind -eq 'text' }).Count
            $ny = @($constraints | Where-Object { $_.Kind -eq 'type' }).Count
            $nq = @($constraints | Where-Object { $_.Kind -eq 'quantity' -and -not $_.Sub }).Count
            $ni = @($constraints | Where-Object { $_.Kind -eq 'quantity' -and $_.Sub } | ForEach-Object { $_.Code } | Sort-Object -Unique).Count
            $nc = @($constraints | Where-Object { $_.Kind -eq 'code' }).Count
            $nl = @($constraints | Where-Object { $_.Kind -eq 'textcode' } | ForEach-Object { $_.Code } | Sort-Object -Unique).Count
            $nn = $(if ($null -ne $script:tree) { Get-TreeNodes $script:tree } else { 0 })
            Write-Line '' ('checked: ' + $nn + ' nodes - code, place, class and number of occurrences,')
            Write-Line '' ('         ' + $nt + ' texts - patterns and lists of allowed values,')
            Write-Line '' ('         ' + $nl + ' texts - language and character set,')
            Write-Line '' ('         ' + $ny + ' data types, ' + $nc + ' coded values - code and code system,')
            $iv = $(if ($ni -eq 1) { ' and 1 interval' } elseif ($ni -gt 1) { ' and ' + $ni + ' intervals' } else { '' })
            Write-Line '' ('         ' + $nq + ' quantities' + $iv + ' - unit, its code system and allowed range')
        }
    }
    $what = $(if ($null -ne $opt) { 'The template and its archetypes are' } elseif ($archetypes.Count -gt 1) { 'The archetypes themselves are' } else { 'The archetype itself is' })
    Write-Line 'Note' ($what + ' checked in ' + $tool + ',') 'DarkGray'
    Write-Line '' 'against the Archetype Object Model (AOM), not here.' 'DarkGray'
    if ($derived -and $Step -ne 'all') { Write-Line 'This run' 'Steps 1 and 2 - here they are one check.' 'Yellow'; $Step = 'all' }
    elseif ($Step -eq '1') { Write-Line 'This run' 'Step 1 only.' 'Yellow' }
    elseif ($Step -eq '2') { Write-Line 'This run' 'Step 2 only.' 'Yellow' }

    $files = @(Get-SetFiles '*.xml' | Sort-Object @{ Expression = { Get-Order $_.Name } }, FullName)
    if ($files.Count -eq 0) { Write-Host ''; Write-Line '' 'No instance (.xml) in this folder.' 'Yellow'; return }

    # what the file names mean, when at least one of them states an expected result
    if (@($files | Where-Object { (Get-Expected $_.Name '1') -ne '' }).Count -gt 0) {
        Write-Line 'Expected' 'The file name of an instance states the result it should have:'
        if ($derived) {
            Write-Line '' ('instance-valid'.PadRight(37) + 'valid')
            Write-Line '' ('instance-invalid-structural-rm'.PadRight(37) + 'invalid - the structure breaks the schema')
            Write-Line '' ('instance-invalid-semantic-archetype'.PadRight(37) + 'invalid - a value breaks the archetype')
        } else {
            Write-Line '' ('instance-valid'.PadRight(37) + 'valid in both steps')
            Write-Line '' ('instance-invalid-structural-rm'.PadRight(37) + 'invalid in step 1, step 2 not run')
            Write-Line '' ('instance-invalid-semantic-archetype'.PadRight(37) + 'valid in step 1, invalid in step 2')
        }
    }
    Write-Rule
    $script:matched = 0; $script:mismatch = 0; $valid = 0

    foreach ($f in $files) {
        $name = $f.Name
        $script:instanceOk = $true
        Write-Host ('  ' + (Get-Relative $f.FullName))
        if ($derived) {
            $r = Test-Schema $f.FullName
            Write-Step 'Steps 1+2' $r.Ok $r.Text $r.Detail (Get-Expected $name '12')
        } else {
            $skip = $false
            if ($Step -ne '2') {
                $r = Test-Schema $f.FullName
                Write-Step 'Step 1 structural' $r.Ok $r.Text $r.Detail (Get-Expected $name '1')
                if (-not $r.Ok -and $Step -eq 'all') {
                    Write-Host ('    ' + 'Step 2 semantic'.PadRight(21) + 'not run - the instance is invalid in step 1') -ForegroundColor DarkGray
                    $skip = $true
                }
            }
            if ($Step -ne '1' -and -not $skip) {
                try {
                    if ($openEHR) { $t = Test-OpenEhr $f.FullName $constraints } else { $t = Test-En13606 $f.FullName $constraints }
                    if ($t.Bad.Count -eq 0) { Write-Step 'Step 2 semantic' $true (Get-Count $t.Count $t.Unit) @() (Get-Expected $name '2') }
                    else { Write-Step 'Step 2 semantic' $false ($t.Bad.Count.ToString() + ' of ' + (Get-Count $t.Count $t.Unit)) $t.Bad (Get-Expected $name '2') }
                } catch {
                    Write-Step 'Step 2 semantic' $false 'not well-formed XML' @($_.Exception.Message) (Get-Expected $name '2')
                }
            }
        }
        if ($script:instanceOk) { $valid++ }
    }
    Write-Rule
    # which validity the count is about: the one combined check, both steps, or the step of this run
    $n = Get-Count $files.Count 'instance'
    $bad = ($files.Count - $valid).ToString() + ' invalid.'
    if ($derived) { $sum = $n + ': ' + $valid + ' valid, ' + $bad }
    elseif ($Step -eq 'all') { $sum = $n + ': ' + $valid + ' valid in both steps, ' + $bad }
    else { $sum = $n + ' checked in step ' + $Step + ': ' + $valid + ' valid, ' + $bad }
    if ($script:mismatch -gt 0) {
        Write-Line 'Result' $sum 'Red'
        if ($script:mismatch -eq 1) { $t = '1 result differs from what its file name states' } else { $t = $script:mismatch.ToString() + ' results differ from what the file names state' }
        Write-Line '' ($t + ' - see NOT AS EXPECTED above.') 'Red'
    } elseif ($script:matched -gt 0) {
        Write-Line 'Result' $sum 'Green'
        Write-Line '' 'All results are as expected from the file names.' 'Green'
    } else { Write-Line 'Result' $sum }
} catch {
    Write-Host ''
    Write-Host ('  Error: ' + $_.Exception.Message) -ForegroundColor Red
} finally {
    Write-Host ''
    Read-Host '  Press Enter to close'
}
