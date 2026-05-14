$p = New-Object System.IO.Ports.SerialPort COM3,115200
$p.DtrEnable = $false
$p.RtsEnable = $false
$p.ReadTimeout = 5000
$p.Open()
$f = [System.IO.File]::CreateText("C:\Users\billg\billAi\paddlestroke\doze_diag.txt")
Write-Host "Logging COM3 to doze_diag.txt - press Ctrl+C to stop"
try {
    while($true) {
        try {
            $l = $p.ReadLine()
            Write-Host $l
            $f.WriteLine($l)
            $f.Flush()
        } catch [System.TimeoutException] {
            # no data for 5 s - keep waiting
        }
    }
} finally {
    $f.Close()
    $p.Close()
}
