<# 
.SYNOPSIS
    Combine all blog posts into a single Word file with Mermaid diagrams as SVG.
.DESCRIPTION
    This script reads all Markdown files from _posts directory,
    converts Mermaid diagrams to SVG vector images (preserving Japanese text),
    combines posts in date order, and converts to a Word document using Pandoc.
    Heading1 style is set to "page break before" so each article starts on a new page.
    Note: Word 2016+ supports SVG natively.
.EXAMPLE
    .\scripts\generate-all-posts-docx.ps1
#>

param(
    [string]$SinglePost = "",
    [string]$OutputFileOverride = ""
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$postsDir = Join-Path $projectRoot "_posts"
$outputDir = Join-Path $projectRoot "assets\downloads"
$tempDir = Join-Path $env:TEMP "mermaid-docx-$(Get-Date -Format 'yyyyMMddHHmmss')"
$tempFile = Join-Path $tempDir "combined-posts.md"
$referenceDoc = Join-Path $projectRoot "scripts\reference-pagebreak.docx"
$mermaidConfigPath = Join-Path $tempDir "mermaid-config.json"

# No special SVG normalization needed - Word handles SVG with Japanese text natively

# Create temp and output directories
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

function Ensure-ReferenceDoc([string]$path) {
    if (Test-Path $path) {
        return
    }

    $tempRefDir = Join-Path $env:TEMP "pandoc-ref-$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $tempRefDir -Force | Out-Null

    # Create default reference.docx via pandoc (use cmd to preserve binary output)
    $cmd = "cmd /c `"pandoc --print-default-data-file reference.docx > `"$path`"`""
    Invoke-Expression $cmd
    if (-not (Test-Path $path)) {
        throw "Failed to create reference docx at $path."
    }

    # Unzip and modify styles.xml
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($path, $tempRefDir)
    $stylesPath = Join-Path $tempRefDir "word\styles.xml"
    if (-not (Test-Path $stylesPath)) {
        throw "styles.xml not found in reference docx."
    }

    [xml]$styles = Get-Content -Path $stylesPath
    $ns = New-Object System.Xml.XmlNamespaceManager($styles.NameTable)
    $ns.AddNamespace("w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")
    $heading1 = $styles.SelectSingleNode("//w:style[@w:styleId='Heading1']", $ns)
    if (-not $heading1) {
        throw "Heading1 style not found in reference docx."
    }

    $pPr = $heading1.SelectSingleNode("w:pPr", $ns)
    if (-not $pPr) {
        $pPr = $styles.CreateElement("w:pPr", $ns.LookupNamespace("w"))
        $heading1.AppendChild($pPr) | Out-Null
    }

    if (-not $pPr.SelectSingleNode("w:pageBreakBefore", $ns)) {
        $pageBreak = $styles.CreateElement("w:pageBreakBefore", $ns.LookupNamespace("w"))
        $pPr.AppendChild($pageBreak) | Out-Null
        $styles.Save($stylesPath)
    }

    # Repack modified reference docx
    Remove-Item $path -Force
    [System.IO.Compression.ZipFile]::CreateFromDirectory($tempRefDir, $path)
    Remove-Item $tempRefDir -Recurse -Force
}

# Embed SVGs directly into the DOCX (avoid rasterization by Pandoc)
function Embed-SvgImagesInDocx([string]$docxPath, [string[]]$svgFiles) {
    if (-not (Test-Path $docxPath)) {
        throw "DOCX not found: $docxPath"
    }
    if (-not $svgFiles -or $svgFiles.Count -eq 0) {
        Write-Host "No SVG files to embed." -ForegroundColor Yellow
        return
    }

    $workDir = Join-Path $env:TEMP "docx-svg-$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($docxPath, $workDir)

    $relsPath = Join-Path $workDir "word\_rels\document.xml.rels"
    if (-not (Test-Path $relsPath)) {
        throw "document.xml.rels not found in DOCX."
    }

    [xml]$rels = Get-Content -Path $relsPath
    $relNodes = $rels.SelectNodes("/*[local-name()='Relationships']/*[local-name()='Relationship' and contains(@Type, '/image')]")
    if (-not $relNodes -or $relNodes.Count -eq 0) {
        Write-Host "No image relationships found to replace." -ForegroundColor Yellow
        Remove-Item $workDir -Recurse -Force
        return
    }

    $imageRels = @()
    foreach ($rel in $relNodes) {
        $target = $rel.GetAttribute("Target")
        $id = $rel.GetAttribute("Id")
        $idNumber = 0
        if ($id -match 'rId(\d+)') {
            $idNumber = [int]$Matches[1]
        }
        $imageRels += [pscustomobject]@{
            Node = $rel
            Target = $target
            Id = $id
            IdNumber = $idNumber
        }
    }

    $imageRels = $imageRels | Sort-Object IdNumber, Id
    $replaceCount = [Math]::Min($imageRels.Count, $svgFiles.Count)

    if ($imageRels.Count -ne $svgFiles.Count) {
        Write-Host "Warning: SVG count ($($svgFiles.Count)) does not match image count ($($imageRels.Count)). Replacing first $replaceCount." -ForegroundColor Yellow
    }

    for ($i = 0; $i -lt $replaceCount; $i++) {
        $rel = $imageRels[$i]
        $svgSource = $svgFiles[$i]

        if (-not (Test-Path $svgSource)) {
            throw "SVG file missing: $svgSource"
        }

        $targetFileName = [System.IO.Path]::GetFileName($rel.Target)
        $targetBaseName = [System.IO.Path]::GetFileNameWithoutExtension($targetFileName)
        $targetSvg = "media/$targetBaseName.svg"
        $rel.Node.SetAttribute("Target", $targetSvg)

        $svgDest = Join-Path $workDir ("word\media\" + $targetBaseName + ".svg")
        Copy-Item -Path $svgSource -Destination $svgDest -Force

        $oldPath = Join-Path $workDir ("word\" + $rel.Target)
        if (Test-Path $oldPath) {
            Remove-Item $oldPath -Force
        }
    }

    $rels.Save($relsPath)

    # Ensure SVG content type is declared
    $typesPath = Join-Path $workDir "[Content_Types].xml"
    if (-not (Test-Path -LiteralPath $typesPath)) {
        throw "[Content_Types].xml not found in DOCX."
    }

    [xml]$types = Get-Content -LiteralPath $typesPath
    $typesRoot = $types.DocumentElement
    $svgDefault = $types.SelectSingleNode("/*[local-name()='Types']/*[local-name()='Default' and @Extension='svg']")
    if (-not $svgDefault) {
        $newDefault = $types.CreateElement("Default", $typesRoot.NamespaceURI)
        $newDefault.SetAttribute("Extension", "svg")
        $newDefault.SetAttribute("ContentType", "image/svg+xml")
        $typesRoot.AppendChild($newDefault) | Out-Null
        $types.Save($typesPath)
    }

    # Repack docx
    Remove-Item $docxPath -Force
    [System.IO.Compression.ZipFile]::CreateFromDirectory($workDir, $docxPath)
    Remove-Item $workDir -Recurse -Force
}

# Ensure reference docx exists (Heading1 has page break before)
Ensure-ReferenceDoc $referenceDoc

# Mermaid config to avoid HTML labels (foreignObject) in SVG
$mermaidConfig = @{
    theme = "default"
    htmlLabels = $false
    themeVariables = @{
        fontFamily = "Yu Gothic UI, Meiryo, MS PGothic, Arial, sans-serif"
    }
    flowchart = @{
        htmlLabels = $false
    }
    sequence = @{
        htmlLabels = $false
    }
}
$mermaidConfigJson = $mermaidConfig | ConvertTo-Json -Depth 6
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($mermaidConfigPath, $mermaidConfigJson, $utf8NoBom)

# Get post files sorted by filename (date order)
$postFiles = @()
$outputFile = ""
$includeCollectionHeader = $true

if ($SinglePost) {
    $singlePath = $SinglePost
    if (-not (Test-Path $singlePath)) {
        $singlePath = Join-Path $postsDir $SinglePost
    }
    if (-not (Test-Path $singlePath)) {
        throw "Single post not found: $SinglePost"
    }

    $postFiles = @((Get-Item -Path $singlePath))
    $includeCollectionHeader = $false

    if ($OutputFileOverride) {
        $outputFile = $OutputFileOverride
    } else {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($postFiles[0].Name)
        if ($baseName -match '^(\d{4}-\d{2}-\d{2})-\d{3}-(.+)$') {
            $outputName = "$($Matches[1])-$($Matches[2]).docx"
        } else {
            $outputName = "$baseName.docx"
        }
        $outputFile = Join-Path $outputDir $outputName
    }
} else {
    $postFiles = Get-ChildItem -Path $postsDir -Filter "*.md" | Sort-Object Name
    $outputFile = Join-Path $outputDir "all-blog-posts.docx"
}

if ($postFiles.Count -eq 0) {
    Write-Host "No posts found." -ForegroundColor Yellow
    exit 1
}

if ($postFiles.Count -eq 1) {
    Write-Host "Processing 1 post..." -ForegroundColor Cyan
} else {
    Write-Host "Combining $($postFiles.Count) posts..." -ForegroundColor Cyan
}

$combinedContent = @()
if ($includeCollectionHeader) {
    $combinedContent += "# KomuraSoft Technical Blog Collection"
    $combinedContent += ""
    $combinedContent += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    $combinedContent += ""
    $combinedContent += "---"
    $combinedContent += ""
}

$mermaidIndex = 0
$svgFiles = @()

for ($i = 0; $i -lt $postFiles.Count; $i++) {
    $file = $postFiles[$i]
    Write-Host "  Processing: $($file.Name)" -ForegroundColor Gray
    
    $content = Get-Content -Path $file.FullName -Encoding UTF8 -Raw
    
    # Extract title and date from front matter
    $title = ""
    $date = ""
    if ($content -match '(?s)^---\s*\n(.*?)\n---') {
        $frontMatter = $Matches[1]
        if ($frontMatter -match 'title:\s*"?([^"\n]+)"?') {
            $title = $Matches[1].Trim()
        }
        if ($frontMatter -match 'date:\s*(\d{4}-\d{2}-\d{2})') {
            $date = $Matches[1]
        }
        # Remove front matter
        $content = $content -replace '(?s)^---\s*\n.*?\n---\s*\n', ''
    }
    
    # Remove duplicate h1 heading (article title)
    $content = $content -replace '(?m)^#\s+[^\n]+\n', ''
    
    # Convert Mermaid blocks to SVG images (Word 2016+ supports SVG natively)
    $mermaidPattern = '(?s)<pre class="mermaid">\s*(.*?)\s*</pre>'
    $mermaidMatches = [regex]::Matches($content, $mermaidPattern)
    
    foreach ($match in $mermaidMatches) {
        $mermaidCode = $match.Groups[1].Value
        $mermaidIndex++
        $mermaidFile = Join-Path $tempDir "mermaid-$mermaidIndex.mmd"
        $svgFile = Join-Path $tempDir "mermaid-$mermaidIndex.svg"
        $pngFile = Join-Path $tempDir "mermaid-$mermaidIndex.png"
        
        # Save Mermaid code to temp file (preserve Japanese text as-is)
        [System.IO.File]::WriteAllText($mermaidFile, $mermaidCode, $utf8NoBom)
        
        # Convert to SVG using mmdc (for final embed)
        Write-Host "    Converting Mermaid diagram $mermaidIndex to SVG..." -ForegroundColor DarkGray
        $mmdcOut = Join-Path $tempDir "mmdc-$mermaidIndex.out"
        $mmdcErr = Join-Path $tempDir "mmdc-$mermaidIndex.err"
        $mmdcProcess = Start-Process `
            -FilePath "cmd.exe" `
            -ArgumentList @("/c", "mmdc", "-i", $mermaidFile, "-o", $svgFile, "-b", "white", "-c", $mermaidConfigPath) `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $mmdcOut `
            -RedirectStandardError $mmdcErr
        if ($mmdcProcess.ExitCode -ne 0) {
            $mmdcErrorText = ""
            if (Test-Path $mmdcErr) {
                $mmdcErrorText = (Get-Content $mmdcErr -Raw).Trim()
            }
            throw "Mermaid CLI failed for diagram $mermaidIndex (exit code $($mmdcProcess.ExitCode)). $mmdcErrorText"
        }

        if (-not (Test-Path $svgFile)) {
            throw "Mermaid SVG conversion failed for diagram $mermaidIndex."
        }

        # Convert to PNG for Pandoc placeholder (will be replaced with SVG after)
        Write-Host "    Converting Mermaid diagram $mermaidIndex to PNG (placeholder)..." -ForegroundColor DarkGray
        $mmdcPngOut = Join-Path $tempDir "mmdc-$mermaidIndex-png.out"
        $mmdcPngErr = Join-Path $tempDir "mmdc-$mermaidIndex-png.err"
        $mmdcPngProcess = Start-Process `
            -FilePath "cmd.exe" `
            -ArgumentList @("/c", "mmdc", "-i", $mermaidFile, "-o", $pngFile, "-b", "white", "-c", $mermaidConfigPath) `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $mmdcPngOut `
            -RedirectStandardError $mmdcPngErr
        if ($mmdcPngProcess.ExitCode -ne 0) {
            $mmdcPngErrorText = ""
            if (Test-Path $mmdcPngErr) {
                $mmdcPngErrorText = (Get-Content $mmdcPngErr -Raw).Trim()
            }
            throw "Mermaid CLI PNG failed for diagram $mermaidIndex (exit code $($mmdcPngProcess.ExitCode)). $mmdcPngErrorText"
        }

        if (-not (Test-Path $pngFile)) {
            throw "Mermaid PNG conversion failed for diagram $mermaidIndex."
        }

        $svgFiles += $svgFile

        # Replace Mermaid block with SVG image reference
        # Use PNG as Pandoc placeholder; we'll swap in SVG after conversion
        $imageRef = "![]($pngFile)"
        $content = $content.Replace($match.Value, $imageRef)
    }
    
    # Add article title
    $combinedContent += "# $title"
    if ($date) {
        $combinedContent += ""
        $combinedContent += "**Date: $date**"
    }
    $combinedContent += ""
    $combinedContent += $content.Trim()
    $combinedContent += ""
    $combinedContent += ""
}

# Save combined Markdown to temp file
$combinedContent -join "`n" | Out-File -FilePath $tempFile -Encoding UTF8

Write-Host "Converting with Pandoc..." -ForegroundColor Cyan

# Convert with Pandoc (use temp directory as resource path for images)
try {
    & pandoc $tempFile -o $outputFile --from markdown --to docx --resource-path=$tempDir --reference-doc=$referenceDoc
    Write-Host "Embedding SVG images into DOCX..." -ForegroundColor Cyan
    Embed-SvgImagesInDocx $outputFile $svgFiles
    Write-Host "Done: $outputFile" -ForegroundColor Green
    Write-Host "  Converted $mermaidIndex Mermaid diagrams to SVG (with Japanese text preserved)." -ForegroundColor Gray
} catch {
    Write-Host "Pandoc failed: $_" -ForegroundColor Red
    exit 1
} finally {
    # Remove temp directory
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force
    }
}
