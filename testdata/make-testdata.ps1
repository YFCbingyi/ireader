$root = "E:\workspace\project\ireader\testdata"
$text = [System.IO.File]::ReadAllText((Join-Path $root "sample_utf8.txt"), [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText((Join-Path $root "sample_gbk.txt"), $text, [System.Text.Encoding]::GetEncoding("GBK"))
Compress-Archive -Path (Join-Path $root "images_with_chapters\*") -DestinationPath (Join-Path $root "images_with_chapters.zip") -Force
Compress-Archive -Path (Join-Path $root "images_flat\*") -DestinationPath (Join-Path $root "images_flat.zip") -Force
Write-Output "done"
