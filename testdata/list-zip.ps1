Add-Type -AssemblyName System.IO.Compression.FileSystem
$z1 = [System.IO.Compression.ZipFile]::OpenRead("E:\workspace\project\ireader\testdata\images_with_chapters.zip")
Write-Output "with chapters:"
$z1.Entries | ForEach-Object { Write-Output $_.FullName }
$z1.Dispose()
$z2 = [System.IO.Compression.ZipFile]::OpenRead("E:\workspace\project\ireader\testdata\images_flat.zip")
Write-Output "flat:"
$z2.Entries | ForEach-Object { Write-Output $_.FullName }
$z2.Dispose()
