# ============================================================
#  PURPLE RUSH — генератор иконки
#  Рисует app-icon.png (1024) и multiresolution rust-optimizer.ico.
#  Запуск: powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\make-icon.ps1
# ============================================================
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$assets = Join-Path $root 'assets'
New-Item -ItemType Directory -Force -Path $assets | Out-Null

$script:IconSize = 1024
$script:AccentA = [System.Drawing.Color]::FromArgb(188, 92, 255)
$script:AccentB = [System.Drawing.Color]::FromArgb(255, 61, 154)
$script:AccentC = [System.Drawing.Color]::FromArgb(0, 229, 255)

function New-RoundPath {
    param([System.Drawing.RectangleF]$Rect, [float]$Radius)
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $Radius * 2
    if ($d -gt $Rect.Width) { $d = $Rect.Width }
    if ($d -gt $Rect.Height) { $d = $Rect.Height }
    $p.AddArc($Rect.X, $Rect.Y, $d, $d, 180, 90)
    $p.AddArc($Rect.Right - $d, $Rect.Y, $d, $d, 270, 90)
    $p.AddArc($Rect.Right - $d, $Rect.Bottom - $d, $d, $d, 0, 90)
    $p.AddArc($Rect.X, $Rect.Bottom - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function New-BoltPath {
    param([float]$X, [float]$Y, [float]$W, [float]$H)
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $pts = @(
        [System.Drawing.PointF]::new($X + $W * 0.58, $Y),
        [System.Drawing.PointF]::new($X + $W * 0.18, $Y + $H * 0.55),
        [System.Drawing.PointF]::new($X + $W * 0.48, $Y + $H * 0.55),
        [System.Drawing.PointF]::new($X + $W * 0.36, $Y + $H),
        [System.Drawing.PointF]::new($X + $W * 0.86, $Y + $H * 0.40),
        [System.Drawing.PointF]::new($X + $W * 0.56, $Y + $H * 0.40)
    )
    $p.AddPolygon($pts)
    return $p
}

$bmp = New-Object System.Drawing.Bitmap($script:IconSize, $script:IconSize,
    [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.Clear([System.Drawing.Color]::Transparent)

# --- мягкое свечение вокруг значка ---
for ($i = 10; $i -ge 1; $i--) {
    $inset = 70 + $i * 15
    $alpha = 5 + (11 - $i) * 2
    $rect = [System.Drawing.RectangleF]::new($inset, $inset, $script:IconSize - $inset * 2, $script:IconSize - $inset * 2)
    $path = New-RoundPath $rect (180 + $i * 8)
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($alpha, 190, 80, 255))
    $g.FillPath($brush, $path)
    $brush.Dispose(); $path.Dispose()
}

# --- тень под плиткой ---
for ($i = 0; $i -lt 10; $i++) {
    $off = 44 + $i * 4
    $rect = [System.Drawing.RectangleF]::new(102, 102 + $off, 820, 820)
    $path = New-RoundPath $rect 190
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(16, 0, 0, 0))
    $g.FillPath($brush, $path)
    $brush.Dispose(); $path.Dispose()
}

# --- основная плитка ---
$bodyRect = [System.Drawing.RectangleF]::new(92, 92, 840, 840)
$body = New-RoundPath $bodyRect 188
$grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    [System.Drawing.Rectangle]::new(92, 92, 840, 840),
    [System.Drawing.Color]::FromArgb(26, 10, 46),
    [System.Drawing.Color]::FromArgb(76, 20, 126),
    [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)
$blend = New-Object System.Drawing.Drawing2D.ColorBlend(3)
$blend.Colors = @(
    [System.Drawing.Color]::FromArgb(20, 8, 38),
    [System.Drawing.Color]::FromArgb(52, 14, 92),
    [System.Drawing.Color]::FromArgb(84, 22, 140)
)
$blend.Positions = @(0.0, 0.55, 1.0)
$grad.InterpolationColors = $blend
$g.FillPath($grad, $body)
$grad.Dispose()

# --- диагональный блик (стекло) ---
$oldClip = $g.Clip
$g.SetClip($body)
$gloss = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    [System.Drawing.Rectangle]::new(0, 0, 1024, 1024),
    [System.Drawing.Color]::FromArgb(30, 255, 255, 255),
    [System.Drawing.Color]::FromArgb(0, 255, 255, 255),
    [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)
$blend2 = New-Object System.Drawing.Drawing2D.ColorBlend(3)
$blend2.Colors = @(
    [System.Drawing.Color]::FromArgb(22, 255, 255, 255),
    [System.Drawing.Color]::FromArgb(8, 255, 255, 255),
    [System.Drawing.Color]::FromArgb(0, 255, 255, 255)
)
$blend2.Positions = @(0.0, 0.55, 1.0)
$gloss.InterpolationColors = $blend2
$g.FillRectangle($gloss, 92, 92, 840, 840)
$gloss.Dispose()
$g.Clip = $oldClip

# --- тонкая сетка / трассировка платы ---
$gridPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(13, 210, 170, 255), 2)
for ($x = 150; $x -le 874; $x += 62) {
    $g.DrawLine($gridPen, $x, 130, $x, 894)
}
for ($y = 150; $y -le 874; $y += 62) {
    $g.DrawLine($gridPen, 120, $y, 904, $y)
}
$gridPen.Dispose()

# --- неоновый кант ---
$rim = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    [System.Drawing.Rectangle]::new(92, 92, 840, 840),
    $script:AccentA, $script:AccentB,
    [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)
$rimPen = New-Object System.Drawing.Pen($rim, 9)
$g.DrawPath($rimPen, $body)
$rimPen.Dispose(); $rim.Dispose()

# --- щит ---
$shield = New-Object System.Drawing.Drawing2D.GraphicsPath
$sx = 512.0; $sy = 218.0
$shield.AddBezier(512, 218, 620, 274, 726, 300, 770, 308)
$shield.AddLine(770, 308, 770, 520)
$shield.AddBezier(770, 520, 760, 676, 662, 788, 512, 850)
$shield.AddBezier(512, 850, 362, 788, 264, 676, 254, 520)
$shield.AddLine(254, 520, 254, 308)
$shield.AddBezier(254, 308, 300, 300, 404, 274, 512, 218)
$shield.CloseFigure()

$shieldFill = New-Object System.Drawing.Drawing2D.PathGradientBrush($shield)
$shieldFill.CenterColor = [System.Drawing.Color]::FromArgb(175, 18, 7, 38)
$shieldFill.SurroundColors = @([System.Drawing.Color]::FromArgb(80, 120, 40, 190))
$shieldFill.CenterPoint = [System.Drawing.PointF]::new(512, 560)
$g.FillPath($shieldFill, $shield)
$shieldFill.Dispose()

$shieldPenBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    [System.Drawing.Rectangle]::new(250, 214, 524, 640),
    $script:AccentC, $script:AccentA,
    [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)
$shieldPen = New-Object System.Drawing.Pen($shieldPenBrush, 12)
$g.DrawPath($shieldPen, $shield)
$shieldPen.Dispose(); $shieldPenBrush.Dispose()

# --- молния ---
$bolt = New-BoltPath 362 300 300 470
for ($i = 8; $i -ge 1; $i--) {
    $glowColor = [System.Drawing.Color]::FromArgb(13 + $i * 2, 255, 70, 200)
    $glowPen = [System.Drawing.Pen]::new($glowColor, [float](8 + $i * 5))
    $glowPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $g.DrawPath($glowPen, $bolt)
    $glowPen.Dispose()
}
$boltBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    [System.Drawing.Rectangle]::new(360, 296, 310, 480),
    [System.Drawing.Color]::FromArgb(233, 200, 255),
    $script:AccentB,
    [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
$g.FillPath($boltBrush, $bolt)
$boltBrush.Dispose()

# --- блик на молнии ---
$boltShine = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    [System.Drawing.Rectangle]::new(360, 296, 310, 480),
    [System.Drawing.Color]::FromArgb(130, 255, 255, 255),
    [System.Drawing.Color]::FromArgb(0, 255, 255, 255),
    [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
$g.FillPath($boltShine, $bolt)
$boltShine.Dispose()
$bolt.Dispose()

# --- орбитальные точки ---
$dotBrush = New-Object System.Drawing.SolidBrush($script:AccentC)
$g.FillEllipse($dotBrush, 184, 184, 18, 18)
$g.FillEllipse($dotBrush, 822, 790, 14, 14)
$g.FillEllipse($dotBrush, 804, 190, 10, 10)
$dotBrush.Dispose()

$shield.Dispose(); $body.Dispose(); $g.Dispose()

$png = Join-Path $assets 'app-icon.png'
$bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host ("PNG: {0} ({1} KB)" -f $png, [math]::Round((Get-Item $png).Length / 1KB))

# --- ICO: PNG-кадры 16…256 ---
$sizes = @(16, 24, 32, 48, 64, 128, 256)
$frames = @()
foreach ($s in $sizes) {
    $small = New-Object System.Drawing.Bitmap($s, $s, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $sg = [System.Drawing.Graphics]::FromImage($small)
    $sg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $sg.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $sg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $sg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $sg.Clear([System.Drawing.Color]::Transparent)
    $sg.DrawImage($bmp, 0, 0, $s, $s)
    $sg.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $small.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $frames += ,@($s, $ms.ToArray())
    $small.Dispose(); $ms.Dispose()
}
$bmp.Dispose()

$ico = Join-Path $assets 'rust-optimizer.ico'
$fs = [System.IO.File]::Create($ico)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$frames.Count)
$offset = 6 + 16 * $frames.Count
foreach ($f in $frames) {
    $s = [int]$f[0]; $data = [byte[]]$f[1]
    $bw.Write([byte]$(if ($s -ge 256) { 0 } else { $s }))
    $bw.Write([byte]$(if ($s -ge 256) { 0 } else { $s }))
    $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([UInt16]1); $bw.Write([UInt16]32)
    $bw.Write([UInt32]$data.Length); $bw.Write([UInt32]$offset)
    $offset += $data.Length
}
foreach ($f in $frames) { $bw.Write([byte[]]$f[1]) }
$bw.Flush(); $bw.Dispose(); $fs.Dispose()
Write-Host ("ICO: {0} ({1} KB, {2} sizes)" -f $ico, [math]::Round((Get-Item $ico).Length / 1KB), $sizes.Count)
