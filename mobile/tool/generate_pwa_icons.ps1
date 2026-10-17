param(
    [Parameter(Mandatory = $true)]
    [string]$Source
)

Add-Type -AssemblyName System.Drawing

$iconsDirectory = Join-Path $PSScriptRoot "..\web\icons"
$iconsDirectory = [System.IO.Path]::GetFullPath($iconsDirectory)
[System.IO.Directory]::CreateDirectory($iconsDirectory) | Out-Null

$sourceImage = [System.Drawing.Image]::FromFile($Source)

function New-RoundedIcon {
    param(
        [int]$Size,
        [string]$Destination,
        [bool]$Maskable = $false
    )

    $scale = 4
    $workingSize = $Size * $scale
    $working = New-Object System.Drawing.Bitmap($workingSize, $workingSize, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($working)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.Clear([System.Drawing.Color]::Transparent)

    if ($Maskable) {
        $graphics.Clear([System.Drawing.ColorTranslator]::FromHtml("#FFE600"))
    }

    $margin = if ($Maskable) { [int]($workingSize * 0.10) } else { 0 }
    $iconSize = $workingSize - (2 * $margin)
    # El JPEG original incluye un lienzo blanco fuera del contorno del icono.
    # Este radio sigue la silueta amarilla real y recorta por completo esas esquinas.
    $cornerDiameter = [int]($iconSize * 0.34)
    $rect = New-Object System.Drawing.Rectangle($margin, $margin, $iconSize, $iconSize)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc($rect.Left, $rect.Top, $cornerDiameter, $cornerDiameter, 180, 90)
    $path.AddArc($rect.Right - $cornerDiameter, $rect.Top, $cornerDiameter, $cornerDiameter, 270, 90)
    $path.AddArc($rect.Right - $cornerDiameter, $rect.Bottom - $cornerDiameter, $cornerDiameter, $cornerDiameter, 0, 90)
    $path.AddArc($rect.Left, $rect.Bottom - $cornerDiameter, $cornerDiameter, $cornerDiameter, 90, 90)
    $path.CloseFigure()

    $textureBitmap = New-Object System.Drawing.Bitmap($iconSize, $iconSize, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $textureGraphics = [System.Drawing.Graphics]::FromImage($textureBitmap)
    $textureGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $crop = [int]([Math]::Min($sourceImage.Width, $sourceImage.Height) * 0.02)
    $croppedWidth = $sourceImage.Width - (2 * $crop)
    $croppedHeight = $sourceImage.Height - (2 * $crop)
    $sourceRect = New-Object System.Drawing.Rectangle($crop, $crop, $croppedWidth, $croppedHeight)
    $destinationRect = New-Object System.Drawing.Rectangle(0, 0, $iconSize, $iconSize)
    $textureGraphics.DrawImage(
        $sourceImage,
        $destinationRect,
        $sourceRect,
        [System.Drawing.GraphicsUnit]::Pixel
    )
    $textureGraphics.Dispose()
    $texture = New-Object System.Drawing.TextureBrush($textureBitmap)
    $texture.TranslateTransform($margin, $margin)
    $graphics.FillPath($texture, $path)

    $result = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $resultGraphics = [System.Drawing.Graphics]::FromImage($result)
    $resultGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $resultGraphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    if ($Maskable) {
        $resultGraphics.Clear([System.Drawing.ColorTranslator]::FromHtml("#FFE600"))
    }
    else {
        $resultGraphics.Clear([System.Drawing.Color]::Transparent)
    }
    $resultGraphics.DrawImage($working, 0, 0, $Size, $Size)
    $result.Save($Destination, [System.Drawing.Imaging.ImageFormat]::Png)

    $resultGraphics.Dispose()
    $result.Dispose()
    $texture.Dispose()
    $textureBitmap.Dispose()
    $path.Dispose()
    $graphics.Dispose()
    $working.Dispose()
}

try {
    New-RoundedIcon -Size 1024 -Destination (Join-Path $iconsDirectory "gudex-logo.png")
    New-RoundedIcon -Size 512 -Destination (Join-Path $iconsDirectory "Icon-512.png")
    New-RoundedIcon -Size 192 -Destination (Join-Path $iconsDirectory "Icon-192.png")
    New-RoundedIcon -Size 180 -Destination (Join-Path $iconsDirectory "Icon-180.png")
    New-RoundedIcon -Size 32 -Destination (Join-Path $iconsDirectory "Icon-32.png")
    New-RoundedIcon -Size 512 -Destination (Join-Path $iconsDirectory "Icon-maskable-512.png") -Maskable $true
    New-RoundedIcon -Size 192 -Destination (Join-Path $iconsDirectory "Icon-maskable-192.png") -Maskable $true
}
finally {
    $sourceImage.Dispose()
}

Write-Output "Iconos PWA generados en $iconsDirectory"
