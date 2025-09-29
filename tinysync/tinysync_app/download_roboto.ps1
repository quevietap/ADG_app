$fonts = @(
    @{
        name = "Roboto-Regular.ttf"
        url = "https://fonts.gstatic.com/s/roboto/v30/KFOmCnqEu92Fr1Me5Q.ttf"
    },
    @{
        name = "Roboto-Medium.ttf"
        url = "https://fonts.gstatic.com/s/roboto/v30/KFOlCnqEu92Fr1MmEU9vAw.ttf"
    },
    @{
        name = "Roboto-Bold.ttf"
        url = "https://fonts.gstatic.com/s/roboto/v30/KFOlCnqEu92Fr1MmWUlvAw.ttf"
    }
)

foreach ($font in $fonts) {
    $outputPath = "fonts/$($font.name)"
    Write-Host "Downloading $($font.name)..."
    Invoke-WebRequest -Uri $font.url -OutFile $outputPath
} 