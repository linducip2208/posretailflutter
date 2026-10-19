# Generate launcher icons + splash logo untuk POS Retail (Windows PowerShell).
#
# Sumber: android/icon/app_icon.png (master 1024x1024, dibuat dari
# assets/app_icon.png dengan upscale HighQualityBicubic).
# Jalankan dari root project:  powershell -File android/icon/generate_icons.ps1
#
# Menghasilkan:
#   - mipmap-*/ic_launcher.png             (ikon legacy API < 26)
#   - mipmap-*/ic_launcher_foreground.png  (layer depan adaptive icon, 108dp)
#   - mipmap-anydpi-v26/ic_launcher.xml    (adaptive icon API >= 26)
#   - drawable-*/launch_logo.png           (logo splash)
#   - values/colors.xml                    (warna brand untuk icon/splash)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ResDir = Join-Path $ProjectRoot 'android\app\src\main\res'
$Master = Join-Path $PSScriptRoot 'app_icon.png'
$BrandBlue = '#0258E3'

if (-not (Test-Path $Master)) {
    throw "Master icon tidak ditemukan: $Master"
}

$master = [System.Drawing.Bitmap]::FromFile($Master)

function Save-ScaledPng {
    param(
        [System.Drawing.Bitmap]$Source,
        [int]$Size,
        [string]$OutPath
    )
    $dir = Split-Path -Parent $OutPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $dst = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($dst)
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.DrawImage($Source, (New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)), 0, 0, $Source.Width, $Source.Height, [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    $dst.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $dst.Dispose()
}

# Densitas Android: mdpi 1x, hdpi 1.5x, xhdpi 2x, xxhdpi 3x, xxxhdpi 4x
$densities = @(
    @{ Dir = 'mipmap-mdpi';    Legacy = 48;  Foreground = 108; Logo = 96 },
    @{ Dir = 'mipmap-hdpi';    Legacy = 72;  Foreground = 162; Logo = 144 },
    @{ Dir = 'mipmap-xhdpi';   Legacy = 96;  Foreground = 216; Logo = 192 },
    @{ Dir = 'mipmap-xxhdpi';  Legacy = 144; Foreground = 324; Logo = 288 },
    @{ Dir = 'mipmap-xxxhdpi'; Legacy = 192; Foreground = 432; Logo = 384 }
)

foreach ($d in $densities) {
    $mipmapDir = Join-Path $ResDir $d.Dir
    Save-ScaledPng -Source $master -Size $d.Legacy  -OutPath (Join-Path $mipmapDir 'ic_launcher.png')
    Save-ScaledPng -Source $master -Size $d.Foreground -OutPath (Join-Path $mipmapDir 'ic_launcher_foreground.png')

    $drawableDir = Join-Path $ResDir ($d.Dir -replace '^mipmap-', 'drawable-')
    Save-ScaledPng -Source $master -Size $d.Logo -OutPath (Join-Path $drawableDir 'launch_logo.png')
}

# Adaptive icon (API >= 26): background warna brand + layer depan logo.
$anyDpi = Join-Path $ResDir 'mipmap-anydpi-v26'
if (-not (Test-Path $anyDpi)) { New-Item -ItemType Directory -Force -Path $anyDpi | Out-Null }
@"
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
"@ | Set-Content -Path (Join-Path $anyDpi 'ic_launcher.xml') -Encoding UTF8

# Warna brand terpusat.
$valuesDir = Join-Path $ResDir 'values'
if (-not (Test-Path $valuesDir)) { New-Item -ItemType Directory -Force -Path $valuesDir | Out-Null }
@"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Biru brand untuk adaptive icon + splash (lihat generate_icons.ps1). -->
    <color name="ic_launcher_background">$BrandBlue</color>
    <color name="launch_background">$BrandBlue</color>
</resources>
"@ | Set-Content -Path (Join-Path $valuesDir 'colors.xml') -Encoding UTF8

$master.Dispose()
Write-Host "OK: launcher icon, adaptive icon, splash logo, dan colors.xml diperbarui."
