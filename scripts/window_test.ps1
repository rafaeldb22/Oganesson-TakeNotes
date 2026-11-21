# Opens the app (DEMO mode), resizes the window in several ways and takes
# screenshots to check that it repaints correctly.
param([string]$Exe)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path screenshots | Out-Null

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[W]::SetProcessDPIAware() | Out-Null

function Shot($name) {
  $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
  $bmp.Save("screenshots\$name.png")
  $g.Dispose(); $bmp.Dispose()
  Write-Host "screenshot $name"
}
function Click($x, $y) {
  [W]::SetCursorPos($x, $y) | Out-Null; Start-Sleep -Milliseconds 100
  [W]::mouse_event(2, 0, 0, 0, [IntPtr]::Zero); [W]::mouse_event(4, 0, 0, 0, [IntPtr]::Zero)
}
function Size($w, $h) { [W]::SetWindowPos($script:h, [IntPtr]::Zero, 40, 40, $w, $h, 0x0040) | Out-Null }

$p = Start-Process -FilePath $Exe -PassThru
$script:h = [IntPtr]::Zero
for ($i = 0; $i -lt 60 -and $script:h -eq [IntPtr]::Zero; $i++) {
  Start-Sleep -Milliseconds 500; $p.Refresh(); $script:h = $p.MainWindowHandle
}
if ($script:h -eq [IntPtr]::Zero) { throw "Window not found" }
[W]::SetForegroundWindow($script:h) | Out-Null
Start-Sleep 6
Size 1000 700; Start-Sleep 3; Shot "01-start"

# Open a note (list on the left)
Click 200 430; Start-Sleep 3; Shot "02-note-open"
Click 210 200; Start-Sleep 3; Shot "02b-folder"
Click 282 703; Start-Sleep 3; Shot "02c-calendar"
Click 105 200; Start-Sleep 2

# Simulated drag: shrink step by step (like dragging with the mouse)
for ($w = 1000; $w -ge 600; $w -= 20) { Size $w 700; Start-Sleep -Milliseconds 16 }
Start-Sleep 2; Shot "03-after-shrinking"

for ($w = 600; $w -le 980; $w += 20) { Size $w 700; Start-Sleep -Milliseconds 16 }
Start-Sleep 2; Shot "04-after-widening"

for ($hh = 700; $hh -ge 560; $hh -= 15) { Size 1000 $hh; Start-Sleep -Milliseconds 16 }
Start-Sleep 2; Shot "05-after-lower-height"

[W]::ShowWindow($script:h, 3) | Out-Null; Start-Sleep 3; Shot "06-maximized"
[W]::ShowWindow($script:h, 9) | Out-Null; Start-Sleep 3; Shot "07-restored"
[W]::ShowWindow($script:h, 6) | Out-Null; Start-Sleep 2
[W]::ShowWindow($script:h, 9) | Out-Null; Start-Sleep 3; Shot "08-after-minimize"

Stop-Process -Id $p.Id -Force
