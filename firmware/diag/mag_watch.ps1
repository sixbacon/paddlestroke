param([string]$Port = "COM3", [int]$Baud = 115200)
$p = New-Object System.IO.Ports.SerialPort($Port, $Baud, 'None', 8, 'One')
$p.ReadTimeout = 2000
$p.DtrEnable   = $false
$p.RtsEnable   = $false
try { $p.Open() } catch { [Console]::WriteLine("OPEN_FAIL: $_"); exit 1 }
[Console]::WriteLine("LISTENING_ON_$Port")
[Console]::Out.Flush()
while ($true) {
    try {
        $line = $p.ReadLine()
        if ($line -match 'MAG_CAL|DCD_SAVED|ready|Payload|FAIL|PASS|rst:0x|GPS fix|starting|logging|Paddle|Boat|SD|CPM') {
            [Console]::WriteLine($line)
            [Console]::Out.Flush()
        }
    } catch [TimeoutException] { }
}
