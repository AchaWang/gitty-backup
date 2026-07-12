$path = "C:\Users\Acha\Desktop\Acha\rclone-ui\RcloneRuleManager.ps1"
if (Test-Path $path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        # Already has UTF-8 BOM
    } else {
        $bom = [byte[]]@(0xEF, 0xBB, 0xBF)
        $newBytes = [byte[]]($bom + $bytes)
        [System.IO.File]::WriteAllBytes($path, $newBytes)
    }
}
