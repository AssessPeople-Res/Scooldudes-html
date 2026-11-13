<#
  Converts the classic ASP / ASP.NET Scooldudes site into a static HTML site
  suitable for GitHub Pages.

  Usage:  powershell -ExecutionPolicy Bypass -File tools\convert-to-html.ps1 [-Source D:\Sites\Scooldudes_2015] [-Dest D:\Sites\scooldudes-html]

  - Resolves <!-- #include --> files
  - Strips server-side code (<% %>, <%= %>, <%@ %>, <%# %>) and runat="server"
  - Converts common <asp:*> controls to plain HTML
  - Renames .asp/.aspx -> .html and rewrites links (with correct letter case,
    because GitHub Pages is case-sensitive)
  - Server-only handlers (Save*, *Action, payment gateway...) are not converted;
    links/forms pointing to them go to not-available.html
  - Copies assets but never *.inc, *.cs, *.config, bin, App_Code (they contain DB credentials / server code)
#>
param(
  [string]$Source = 'D:\Sites\Scooldudes_2015',
  [string]$Dest   = 'D:\Sites\scooldudes-html'
)

$ErrorActionPreference = 'Stop'
$Source = (Resolve-Path $Source).Path.TrimEnd('\')
New-Item -ItemType Directory -Force $Dest | Out-Null
$Dest = (Resolve-Path $Dest).Path.TrimEnd('\')

$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$cp1252     = [System.Text.Encoding]::GetEncoding(1252)
$utf8NoBom  = New-Object System.Text.UTF8Encoding($false)

function Read-Text([string]$path) {
  $bytes = [IO.File]::ReadAllBytes($path)
  try { $t = $utf8Strict.GetString($bytes) } catch { $t = $cp1252.GetString($bytes) }
  if ($t.Length -gt 0 -and $t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }
  return $t
}

function Rel([string]$full) { return $full.Substring($Source.Length + 1).Replace('\', '/') }

# ---------------------------------------------------------------- classify
$excludeDirs  = '^(bin|app_code|aspnet_client|tools|\..*)$'
$excludeExt   = '^\.(cs|inc|config|dll|refresh|db|vb|asax|ascx|master|ps1)$'
# server-only pages: form handlers, login/session/payment plumbing
$serverOnly   = '^(save.*|.*action|check|cwiserouter|ccav.*|paymentgateway|transactionredirect|transactioncanceled|getsessionfromloginaction|printeventregistration|verifyeventregistration|orderstatus|logout|preparecontest)\.aspx?$'

$all = Get-ChildItem $Source -Recurse -File | Where-Object {
  $parts = (Rel $_.FullName).Split('/')
  -not ($parts[0..($parts.Count - 2)] | Where-Object { $_ -match $excludeDirs }) -and
  -not ($parts | Where-Object { $_ -match '^(bin|app_code)$' })
}

$pages = @(); $assets = @()
foreach ($f in $all) {
  $ext = $f.Extension.ToLower()
  if ($f.Name -eq 'Thumbs.db') { continue }
  if ((Rel $f.FullName) -ieq 'j4m/Caption-Contest-V2/j4m-contests.asp') { continue }   # stray broken copy of /j4m-contests.asp
  if ($ext -in '.asp', '.aspx') {
    if ($f.Name -notmatch $serverOnly) { $pages += $f }
  } elseif ($ext -in '.html', '.htm') {
    $pages += $f
  } elseif ($ext -notmatch $excludeExt) {
    $assets += $f
  }
}

# map: lower-case source rel path -> output rel path (true case)
$map = @{}
foreach ($f in $assets) { $r = Rel $f.FullName; $map[$r.ToLower()] = $r }
foreach ($f in $pages) {
  $r = Rel $f.FullName
  $o = if ($f.Extension -match '^\.aspx?$') { $r -replace '\.aspx?$', '.html' } else { $r }
  $map[$r.ToLower()] = $o
  $map[$o.ToLower()] = $o
}
$map['not-available.html'] = 'not-available.html'

# ---------------------------------------------------------------- helpers
function Expand-Includes([string]$text, [string]$dir, [int]$depth = 0) {
  if ($depth -gt 8) { return $text }
  $rx = [regex]'<!--\s*#include\s+(file|virtual)\s*=\s*"([^"]+)"\s*-->'
  return $rx.Replace($text, {
    param($m)
    $p = $m.Groups[2].Value
    $full = if ($m.Groups[1].Value -eq 'virtual') { Join-Path $Source $p.TrimStart('/') } else { Join-Path $dir $p }
    if (-not (Test-Path $full)) { $full = Join-Path $Source (Split-Path $p -Leaf) }   # fall back to the site-root copy
    if (-not (Test-Path $full)) {   # missing include -> drop
      Write-Warning "missing include $p in $dir"; return ''
    }
    $inner = Read-Text $full
    Expand-Includes $inner (Split-Path $full) ($depth + 1)
  })
}

function Convert-AspControls([string]$t) {
  $o = [Text.RegularExpressions.RegexOptions]'IgnoreCase, Singleline'
  # attribute helper
  $attr = { param($a, $n) $m = [regex]::Match($a, "\b$n\s*=\s*""([^""]*)""", 'IgnoreCase'); if ($m.Success) { $m.Groups[1].Value } else { '' } }

  # Calendar: replaced by a simple note (events came from the database)
  $t = [regex]::Replace($t, '<asp:Calendar\b.*?</asp:Calendar>', '<p class="static-note">The event calendar was generated from the database and is not available on the static site.</p>', $o)
  # GridView: data-bound, cannot be rendered statically
  $t = [regex]::Replace($t, '<asp:GridView\b.*?</asp:GridView>', '', $o)
  # DropDownList / ListItem
  $t = [regex]::Replace($t, '<asp:DropDownList\b([^>]*)>', { param($m) $id = & $attr $m.Groups[1].Value 'ID'; "<select id=""$id"" name=""$id"">" }, $o)
  $t = [regex]::Replace($t, '</asp:DropDownList>', '</select>', $o)
  $t = [regex]::Replace($t, '<asp:ListItem\b([^>]*)>(.*?)</asp:ListItem>', { param($m) $v = & $attr $m.Groups[1].Value 'Value'; "<option value=""$v"">$($m.Groups[2].Value)</option>" }, $o)
  # TextBox
  $t = [regex]::Replace($t, '<asp:TextBox\b([^>]*?)/?>(\s*</asp:TextBox>)?', {
      param($m) $a = $m.Groups[1].Value; $id = & $attr $a 'ID'; $mode = & $attr $a 'TextMode'
      if ($mode -match 'MultiLine') { "<textarea id=""$id"" name=""$id""></textarea>" }
      elseif ($mode -match 'Password') { "<input type=""password"" id=""$id"" name=""$id"" />" }
      else { "<input type=""text"" id=""$id"" name=""$id"" />" } }, $o)
  # Button
  $t = [regex]::Replace($t, '<asp:Button\b([^>]*?)/?>(\s*</asp:Button>)?', { param($m) $a = $m.Groups[1].Value; "<input type=""submit"" id=""$(& $attr $a 'ID')"" value=""$(& $attr $a 'Text')"" />" }, $o)
  # CheckBox
  $t = [regex]::Replace($t, '<asp:CheckBox\b([^>]*?)/?>(\s*</asp:CheckBox>)?', { param($m) $a = $m.Groups[1].Value; $id = & $attr $a 'ID'; "<label><input type=""checkbox"" id=""$id"" name=""$id"" /> $(& $attr $a 'Text')</label>" }, $o)
  # HyperLink
  $t = [regex]::Replace($t, '<asp:HyperLink\b([^>]*?)(/>|>(.*?)</asp:HyperLink>)', { param($m) $a = $m.Groups[1].Value; $txt = & $attr $a 'Text'; if (-not $txt) { $txt = $m.Groups[3].Value }; "<a href=""$(& $attr $a 'NavigateUrl')"">$txt</a>" }, $o)
  # Label (keep static Text)
  $t = [regex]::Replace($t, '<asp:Label\b([^>]*?)(/>|>(.*?)</asp:Label>)', { param($m) $a = $m.Groups[1].Value; $txt = & $attr $a 'Text'; if (-not $txt) { $txt = $m.Groups[3].Value }; "<span id=""$(& $attr $a 'ID')"">$txt</span>" }, $o)
  # HiddenField and anything left
  $t = [regex]::Replace($t, '<asp:HiddenField\b[^>]*?/>', '', $o)
  $t = [regex]::Replace($t, '</?asp:[^>]*>', '', $o)
  # elements hidden server-side by default stay hidden
  $t = [regex]::Replace($t, '(<[^>]*?)\s+visible\s*=\s*"false"', '$1 style="display:none"', $o)
  $t = [regex]::Replace($t, '\s+runat\s*=\s*"server"', '', $o)
  return $t
}

function Strip-ServerCode([string]$t) {
  $o = [Text.RegularExpressions.RegexOptions]'IgnoreCase, Singleline'
  # the shared login header: show the logged-out state
  $t = [regex]::Replace($t, '<%=\s*(mydiv1|mydiv2)\s*%>', 'visible', $o)
  $t = [regex]::Replace($t, '<%=\s*divLogOut\s*%>', 'hidden', $o)
  $t = [regex]::Replace($t, '<%=\s*margin\s*%>', '0%', $o)
  # everything else server-side
  $t = [regex]::Replace($t, '<%.*?%>', '', $o)
  # the server-side poll/table logic sometimes lives inside HTML comments; drop empty leftovers
  return $t
}

function Resolve-Ref([string]$ref, [string]$pageDir) {
  # returns rewritten ref, or $null to leave untouched
  if ($ref -match '^(#|mailto:|javascript:|data:|tel:)') { return $null }
  if ($ref -match '^[\w.+-]+@[\w-]+(\.[\w-]+)+$') { return "mailto:$ref" }   # e-mail written without mailto:
  if ($ref -match '^www\.scooldudes\.com') { $ref = 'http://' + $ref }
  $q = ''
  $m = [regex]::Match($ref, '^([^?#]*)([?#].*)?$')
  $path = $m.Groups[1].Value; $q = $m.Groups[2].Value
  if (-not $path) { return $null }
  $abs = $false
  if ($path -match '^(https?:)?//(www\.)?scooldudes\.com(/.*)?$') {
    $path = $Matches[3]; if (-not $path) { $path = '/' }
  } elseif ($path -match '^[a-z][a-z0-9+.-]*:' -or $path.StartsWith('//')) { return $null }
  if ($path.StartsWith('/')) { $abs = $true; $segs = @() } else { $segs = @($pageDir.Split('/') | Where-Object { $_ }) }
  foreach ($s in $path.Split('/')) {
    if ($s -eq '' -or $s -eq '.') { continue }
    if ($s -eq '..') { if ($segs.Count -gt 1) { $segs = @($segs[0..($segs.Count - 2)]) } else { $segs = @() } ; continue }  # clamp at site root
    $segs += [Uri]::UnescapeDataString($s)
  }
  $target = ($segs -join '/')
  if ($path.EndsWith('/') -or $target -eq '') { $target = ($target + '/index.html').TrimStart('/') }
  $key = $target.ToLower()
  if ($map.ContainsKey($key)) { $out = $map[$key] }
  elseif ($key -match '\.aspx?$') { $out = 'not-available.html'; $q = '' }
  else {
    $script:missing[$target] = $true
    if (-not $abs -and $ref -notmatch '^https?:') { return $null }
    $out = $target
  }
  # make relative to page dir
  $from = @($pageDir.Split('/') | Where-Object { $_ })
  $to = $out.Split('/')
  $i = 0
  while ($i -lt $from.Count -and $i -lt ($to.Count - 1) -and $from[$i] -ieq $to[$i]) { $i++ }
  $rel = ((@('..') * ($from.Count - $i)) + $to[$i..($to.Count - 1)]) -join '/'
  return ($rel -replace ' ', '%20') + $q
}

function Rewrite-Links([string]$t, [string]$pageDir) {
  $o = [Text.RegularExpressions.RegexOptions]'IgnoreCase'
  # attributes
  $t = [regex]::Replace($t, '(\b(?:href|src|action|background|data)\s*=\s*)(["''])([^"''<>]*?)\2', {
      param($m) $r = Resolve-Ref $m.Groups[3].Value.Trim() $pageDir
      if ($null -eq $r) { $m.Value } else { $m.Groups[1].Value + $m.Groups[2].Value + $r + $m.Groups[2].Value } }, $o)
  # JS / CSS string literals referencing .asp(x) pages, e.g. location.href="Forcelogin.asp?x"
  $t = [regex]::Replace($t, '(["''])([\w./:-]*?\.aspx?(?:\?[^"''<>\s]*)?)\1', {
      param($m) $r = Resolve-Ref $m.Groups[2].Value $pageDir
      if ($null -eq $r) { $m.Value } else { $m.Groups[1].Value + $r + $m.Groups[1].Value } }, $o)
  # CSS url(...)
  $t = [regex]::Replace($t, 'url\(\s*([''"]?)([^)''"]+)\1\s*\)', {
      param($m) $r = Resolve-Ref $m.Groups[2].Value.Trim() $pageDir
      if ($null -eq $r) { $m.Value } else { "url($($m.Groups[1].Value)$r$($m.Groups[1].Value))" } }, $o)
  return $t
}

function Ensure-Charset([string]$t) {
  if ($t -match '<meta[^>]+charset') {
    return [regex]::Replace($t, '(<meta[^>]+charset\s*=\s*)["'']?[\w-]+["'']?', '$1"utf-8"', 'IgnoreCase')
  }
  if ($t -match '<head[^>]*>') { return [regex]::Replace($t, '(<head[^>]*>)', "`$1`r`n<meta charset=""utf-8"" />", 'IgnoreCase') }
  return $t
}

# ---------------------------------------------------------------- run
$script:missing = @{}
$report = New-Object System.Collections.Generic.List[string]

foreach ($f in $assets) {
  $dst = Join-Path $Dest (Rel $f.FullName)
  New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
  if ($f.Extension -ieq '.css') {
    $t = Rewrite-Links (Read-Text $f.FullName) ((Split-Path (Rel $f.FullName)) -replace '\\', '/')
    [IO.File]::WriteAllText($dst, $t, $utf8NoBom)
  } else {
    Copy-Item $f.FullName $dst -Force
  }
}

foreach ($f in $pages) {
  $rel = Rel $f.FullName
  $pageDir = if ($rel.Contains('/')) { $rel.Substring(0, $rel.LastIndexOf('/')) } else { '' }
  $t = Read-Text $f.FullName
  $t = Expand-Includes $t $f.DirectoryName
  $hadCode = $t -match '<%'
  $t = Convert-AspControls $t
  $t = Strip-ServerCode $t
  $t = Rewrite-Links $t $pageDir
  $t = Ensure-Charset $t
  $t = $t.TrimStart()
  $out = $map[$rel.ToLower()]
  $dst = Join-Path $Dest $out
  New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
  [IO.File]::WriteAllText($dst, $t, $utf8NoBom)
  $report.Add(('{0} -> {1}{2}' -f $rel, $out, $(if ($hadCode) { '  (server code removed)' } else { '' })))
}

# placeholder for server-only features
$na = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>Scooldudes - Not available</title>
<link href="css/style.css" rel="stylesheet" type="text/css" />
<style>body{font-family:Arial,Helvetica,sans-serif;text-align:center;padding:60px 16px}a{color:#273cbf}</style>
</head>
<body>
<p><a href="index.html"><img src="images/logo.png" alt="Scooldudes" /></a></p>
<h2>This feature is not available</h2>
<p>Login, registration, forms, polls and payments needed the original web server and database.<br />
This archived version of Scooldudes.com is a static site, so they no longer work.</p>
<p><a href="index.html">Back to the home page</a></p>
</body>
</html>
'@
[IO.File]::WriteAllText((Join-Path $Dest 'not-available.html'), $na, $utf8NoBom)
[IO.File]::WriteAllText((Join-Path $Dest '.nojekyll'), '', $utf8NoBom)

$report | Sort-Object | Set-Content (Join-Path $Dest 'tools\conversion-report.txt') -Encoding utf8
"Converted pages: $($pages.Count)   Assets copied: $($assets.Count)"
if ($script:missing.Count) { "Referenced but missing files:"; $script:missing.Keys | Sort-Object | ForEach-Object { "  $_" } }
