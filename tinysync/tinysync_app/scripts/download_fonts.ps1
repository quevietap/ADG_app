$fonts = @(
    @{
        name = "Inter-Regular.ttf"
        url = "https://github.com/rsms/inter/raw/master/docs/font-files/Inter-Regular.ttf"
    },
    @{
        name = "Inter-Medium.ttf"
        url = "https://github.com/rsms/inter/raw/master/docs/font-files/Inter-Medium.ttf"
    },
    @{
        name = "Inter-SemiBold.ttf"
        url = "https://github.com/rsms/inter/raw/master/docs/font-files/Inter-SemiBold.ttf"
    },
    @{
        name = "Inter-Bold.ttf"
        url = "https://github.com/rsms/inter/raw/master/docs/font-files/Inter-Bold.ttf"
    }
)

foreach ($font in $fonts) {
    $outputPath = "assets/fonts/$($font.name)"
    Write-Host "Downloading $($font.name)..."
    Invoke-WebRequest -Uri $font.url -OutFile $outputPath
} 