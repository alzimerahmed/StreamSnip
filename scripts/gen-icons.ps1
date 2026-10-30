Add-Type -AssemblyName System.Drawing

$src = [System.Drawing.Image]::FromFile("$PSScriptRoot\..\assets\streamsnip-icon.jpg")
$root = Split-Path -Parent $PSScriptRoot

function Save-Scaled([System.Drawing.Image]$img, [string]$out, [int]$w, [int]$h) {
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($img, 0, 0, $w, $h)
    $g.Dispose()
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "wrote $out ($w x $h)"
}

# Compose: background color fill + centered icon scaled to fit with margin
function Save-Composed([System.Drawing.Image]$img, [string]$out, [int]$w, [int]$h, [double]$fillRatio) {
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $bg = [System.Drawing.Color]::FromArgb(255, 243, 234, 221) # cream from icon bg
    $g.Clear($bg)
    $target = [Math]::Min($w, $h) * $fillRatio
    $iw = $target; $ih = $target
    $x = [int](($w - $iw) / 2); $y = [int](($h - $ih) / 2)
    $g.DrawImage($img, $x, $y, [int]$iw, [int]$ih)
    $g.Dispose()
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "wrote $out ($w x $h)"
}

$iconset = "$root\StreamSnip\Assets.xcassets\AppIcon.appiconset"
# iOS universal 1024
Save-Scaled $src "$iconset\icon-1024.png" 1024 1024
# Mac sizes: size@scale
foreach ($s in 16, 32, 128, 256, 512) {
    Save-Scaled $src "$iconset\icon-${s}.png" $s $s          # 1x
    Save-Scaled $src "$iconset\icon-${s}@2x.png" ($s * 2) ($s * 2)  # 2x
}

# AppIconPreview imageset (settings/about previews)
$prev = "$root\StreamSnip\Assets.xcassets\AppIconPreview.imageset"
Save-Scaled $src "$prev\AppIconPreview.png" 128 128
Save-Scaled $src "$prev\AppIconPreview@2x.png" 256 256
Save-Scaled $src "$prev\AppIconPreview@3x.png" 384 384

# tvOS brandassets
$ba = "$root\StreamSnip\Assets.xcassets\StreamSnip.brandassets"
# Small app icon layers (Back carries the artwork; Front/Middle emptied)
Save-Composed $src "$ba\App Icon.imagestack\Back.imagestacklayer\Content.imageset\tvOS-Small@1x.png" 400 240 0.78
Save-Composed $src "$ba\App Icon.imagestack\Back.imagestacklayer\Content.imageset\tvOS-Small@2x.png" 800 480 0.78
# App Store icon layer
Save-Composed $src "$ba\App Icon - App Store.imagestack\Back.imagestacklayer\Content.imageset\tvOS-AppStore-1280x768.png" 1280 768 0.72
# Top shelf banners
Save-Composed $src "$ba\Top Shelf Image.imageset\TopShelf.png" 1920 720 0.85
Save-Composed $src "$ba\Top Shelf Image Wide.imageset\TopShelf-Wide.png" 2320 720 0.85

$src.Dispose()
Write-Host "done"
