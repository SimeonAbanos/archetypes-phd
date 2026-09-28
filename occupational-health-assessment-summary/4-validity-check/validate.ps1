# Validity check of archetype instances - EN ISO 13606 and openEHR.
# Run it through the .cmd files next to it. It reads the folder above and changes nothing.
#   validate-1-structural-rm.cmd        step 1: every instance against the Reference Model (RM),
#                                       or against the XML schema derived from the operational
#                                       template (TDS) when the folder has one
#   validate-2-semantic-archetype.cmd   step 2: every instance against the archetype, or against
#                                       the operational template (.opt) when the folder has one
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

# The archetype sets its value constraints on originalText: a regular expression or a list of
# allowed strings. Each is read together with the ELEMENT it belongs to.
function Get-En13606Constraints($archetypes) {
    $list = @()
    foreach ($a in $archetypes) {
        $lines = $a.Lines
        for ($i = 0; $i -lt $lines.Length; $i++) {
            $m = [regex]::Match($lines[$i], '^\s*originalText existence matches \{[^}]*\} matches \{(.+)\}\s*$')
            if (-not $m.Success) { continue }
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
            for ($j = $i - 1; $j -ge [Math]::Max(0, $i - 40); $j--) {
                $e = [regex]::Match($lines[$j], 'ELEMENT\[(at\d+)\].*--\s*(.*?)\s*$')
                if ($e.Success) {
                    $list += New-Object PSObject -Property @{ Code = $e.Groups[1].Value; Name = $e.Groups[2].Value
                        Pattern = $rx; Values = $values
                        Regex = $(if ($null -ne $rx) { New-Object System.Text.RegularExpressions.Regex('\A(?:' + $rx + ')\z') } else { $null }) }
                    break
                }
            }
        }
    }
    return $list
}

function Test-En13606([string]$path, $constraints) {
    $doc = New-Object System.Xml.XmlDocument
    $doc.Load($path)
    $nm = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
    $nm.AddNamespace('e', 'http://EN13606-RM.xsd')
    $count = 0; $bad = @()
    foreach ($c in $constraints) {
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
    return New-Object PSObject -Property @{ Count = $count; Bad = $bad; Unit = 'value' }
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
    }
    return New-Object PSObject -Property @{ Count = $count; Bad = $bad; Unit = 'check' }
}

# ---------------------------------------------------------------- step 2: openEHR operational template

# An operational template (.opt) holds the archetypes as the template has narrowed them. The same
# four kinds of constraint are read from it, and also every node the template keeps, so that a
# node it leaves out (occurrences 0..0) is found in an instance.
$script:optNodes = $null
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
    $script:optTemplate = Get-OptText $doc.DocumentElement 'o:template_id/o:value'
    $def = $doc.DocumentElement.SelectSingleNode('o:definition', $script:onm)
    $script:optRoot = Get-OptText $def 'o:archetype_id/o:value'
    Add-OptNode $def '' @{}
    return @($script:optList)
}

# ---------------------------------------------------------------- output

function Write-Line([string]$label, [string]$text, [string]$color = '') {
    $t = '  ' + $label.PadRight(10) + $text
    if ($color -eq '') { Write-Host $t } else { Write-Host $t -ForegroundColor $color }
}

function Write-Rule { Write-Host ('  ' + ('-' * 76)) -ForegroundColor DarkGray }

# One step of one instance: the result, whether it is the expected one, and the details.
function Write-Step([string]$step, [bool]$ok, [string]$text, $detail, [string]$expect) {
    $res = $(if ($ok) { 'VALID' } else { 'INVALID' })
    if ($text -ne '') { $res += ' - ' + $text }
    $color = $(if ($ok) { 'Green' } else { 'Red' })
    if ($expect -ne '') {
        $match = ($expect -eq 'valid') -eq $ok
        $res = $res.PadRight(32) + $(if ($match) { 'as expected' } else { 'NOT AS EXPECTED' })
        if ($match) { $script:matched++ } else { $script:mismatch++ }
    }
    Write-Host ('    ' + $step.PadRight(21) + $res) -ForegroundColor $color
    $d = @($detail)
    foreach ($x in @($d | Select-Object -First 5)) { Write-Host ('    ' + (' ' * 21) + $x) -ForegroundColor $color }
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
    Write-Host ''
    Write-Host ('  VALIDITY CHECK OF ARCHETYPE INSTANCES - ' + $framework) -ForegroundColor Cyan
    Write-Line 'Folder' $dir
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
    if ($null -ne $tds) { Open-Schema $tds.FullName $true } else { Open-Schema $rm.FullName }
    Write-Host ''
    if ($derived) {
        Write-Line 'Steps 1+2' 'Structural and semantic validity in one check: Against the XML schema derived from the archetype'
        Write-Line '' ('It carries both the ' + $rmName + ' and the archetype constraints.')
        Write-Line '' (Get-Relative $rm.FullName)
        $constraints = @()
    } else {
        if ($null -ne $tds) {
            Write-Line 'Step 1' 'Structural validity: Against the XML schema derived from the operational template (TDS)'
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
            if ($openEHR) { $constraints = @(Get-OpenEhrConstraints $archetypes) } else { $constraints = @(Get-En13606Constraints $archetypes) }
            if ($archetypes.Count -eq 1) { Write-Line 'Step 2' 'Semantic validity: Against the archetype'; Write-Line '' $archetypes[0].Id }
            else { Write-Line 'Step 2' ('Semantic validity: Against the constraints of ' + $archetypes.Count + ' archetypes') }
            foreach ($a in $archetypes) { Write-Line '' (Get-Relative $a.File.FullName) }
        }
        if ($openEHR) {
            $nq = @($constraints | Where-Object { $_.Kind -eq 'quantity' }).Count
            $nc = @($constraints | Where-Object { $_.Kind -eq 'codes' }).Count
            $nsl = @($constraints | Where-Object { $_.Kind -eq 'slot' }).Count
            $t = 'checked: ' + $nq + ' quantities, ' + $nc + ' coded texts, ' + $nsl + ' slots of the composition'
            if ($null -ne $opt) { Write-Line '' ($t + ',') ; Write-Line '' ('and whether every node is one of the ' + $script:optNodes.Count + ' the template keeps') }
            else { Write-Line '' $t }
        } else {
            Write-Line '' ('checked: ' + $constraints.Count + ' value constraints - regular expressions and lists of values')
        }
    }
    $what = $(if ($null -ne $opt) { 'The template and its archetypes are' } elseif ($archetypes.Count -gt 1) { 'The archetypes themselves are' } else { 'The archetype itself is' })
    Write-Line 'Note' ($what + ' checked against the Archetype Object Model (AOM)') 'DarkGray'
    Write-Line '' ('in ' + $tool + ', not here.') 'DarkGray'
    if ($derived -and $Step -ne 'all') { Write-Line 'This run' 'Steps 1 and 2 - here they are one check.' 'Yellow'; $Step = 'all' }
    elseif ($Step -eq '1') { Write-Line 'This run' 'Step 1 only.' 'Yellow' }
    elseif ($Step -eq '2') { Write-Line 'This run' 'Step 2 only.' 'Yellow' }

    $files = @(Get-SetFiles '*.xml' | Sort-Object @{ Expression = { Get-Order $_.Name } }, FullName)
    if ($files.Count -eq 0) { Write-Host ''; Write-Line '' 'No instance (.xml) in this folder.' 'Yellow'; return }

    # what the file names mean, when at least one of them states an expected result
    if (@($files | Where-Object { (Get-Expected $_.Name '1') -ne '' }).Count -gt 0) {
        Write-Host ''
        Write-Line 'Expected' 'The file name of an instance states the result it should have:'
        if ($derived) {
            Write-Line '' ('  ' + 'instance-valid'.PadRight(38) + 'valid')
            Write-Line '' ('  ' + 'instance-invalid-structural-rm'.PadRight(38) + 'invalid - the structure does not fit the schema')
            Write-Line '' ('  ' + 'instance-invalid-semantic-archetype'.PadRight(38) + 'invalid - a value that breaks a constraint of the archetype')
        } else {
            Write-Line '' ('  ' + 'instance-valid'.PadRight(38) + 'valid in both steps')
            Write-Line '' ('  ' + 'instance-invalid-structural-rm'.PadRight(38) + 'invalid in step 1 - the structure does not fit the schema')
            Write-Line '' ('  ' + 'instance-invalid-semantic-archetype'.PadRight(38) + 'valid in step 1, invalid in step 2 - a value that breaks a constraint')
        }
    }
    Write-Host ''
    Write-Rule
    $script:matched = 0; $script:mismatch = 0; $valid = 0

    foreach ($f in $files) {
        $name = $f.Name
        $script:instanceOk = $true
        Write-Host ''
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
    Write-Host ''
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
