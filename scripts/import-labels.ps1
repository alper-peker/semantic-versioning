param(
    [switch]$PreviewOnly
)

function Normalize([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return "" }
    $s = $s.Trim()
    $s = [regex]::Replace($s, "\s+", " ")
    return $s.ToLowerInvariant()
}

# 1) read desired labels
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$labelsPath = Join-Path $scriptDir "labels.json"
if (!(Test-Path $labelsPath)) {
    Write-Host "labels.json not found at $labelsPath"
    exit 1
}
$desiredList = Get-Content $labelsPath | ConvertFrom-Json

# map: normalized name -> original object
$desiredMap = @{}
foreach ($l in $desiredList) {
    $norm = Normalize $l.name
    $desiredMap[$norm] = $l
}

# 2) fetch current labels (full list)
$currentList = gh label list --limit 200 --json name,color,description | ConvertFrom-Json
$currentMap = @{}
if ($currentList) {
    foreach ($c in $currentList) {
        $currentMap[(Normalize $c.name)] = $c.name  # store original name for deletes/edits
    }
}

# 3) create or update desired labels
foreach ($l in $desiredList) {
    $name  = $l.name
    $color = $l.color
    $desc  = $l.description
    $norm  = Normalize $name
    $exists = $currentMap.ContainsKey($norm)

    if ($PreviewOnly) {
        if ($exists) { Write-Host "[Preview] update -> $name" } else { Write-Host "[Preview] create -> $name" }
        continue
    }

    if ($exists) {
        Write-Host "Updating: $name"
        gh label edit "$name" --color "$color" --description "$desc" | Out-Null
    } else {
        Write-Host "Creating: $name"
        gh label create "$name" --color "$color" --description "$desc" | Out-Null
    }
}

# 4) re-fetch current after edits (in case state changed)
$currentList = gh label list --limit 200 --json name | ConvertFrom-Json
$currentMap = @{}
$currentNames = @()
if ($currentList) {
    foreach ($c in $currentList) {
        $currentMap[(Normalize $c.name)] = $c.name
        $currentNames += $c.name
    }
}

# 5) delete labels that are not in JSON (by normalized name)
$toDelete = @()
foreach ($origName in $currentNames) {
    $norm = Normalize $origName
    if (-not $desiredMap.ContainsKey($norm)) {
        $toDelete += $origName
    }
}

if ($toDelete.Count -gt 0) {
    if ($PreviewOnly) {
        Write-Host "[Preview] delete (not in JSON):"
        $toDelete | ForEach-Object { Write-Host " - $_" }
    } else {
        Write-Host "Deleting labels not in JSON..."
        foreach ($n in $toDelete) {
            Write-Host "Deleting: $n"
            gh label delete "$n" --yes | Out-Null
        }
    }
} else {
    Write-Host "No extra labels to delete."
}

# 6) summary
$final = gh label list --limit 200 --json name | ConvertFrom-Json
$finalCount = ($final | Measure-Object).Count
Write-Host "Label sync complete. Total labels: $finalCount"
