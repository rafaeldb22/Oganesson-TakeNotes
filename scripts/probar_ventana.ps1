# Abre la app (modo DEMO), cambia el tamaño de la ventana de varias formas
# y hace capturas para comprobar que se repinta bien.
param([string]$Exe)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path capturas | Out-Null

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
  $bmp.Save("capturas\$name.png")
  $g.Dispose(); $bmp.Dispose()
  Write-Host "captura $name"
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
if ($script:h -eq [IntPtr]::Zero) { throw "No se encontró la ventana" }
[W]::SetForegroundWindow($script:h) | Out-Null
Start-Sleep 6
Size 1200 780; Start-Sleep 3; Shot "01-inicio-1200"

# Abrir la primera nota (lista a la izquierda)
Click 200 300; Start-Sleep 2; Shot "02-nota-abierta"

# Arrastre simulado: ir estrechando poco a poco (como con el ratón)
for ($w = 1200; $w -ge 600; $w -= 20) { Size $w 780; Start-Sleep -Milliseconds 16 }
Start-Sleep 2; Shot "03-tras-estrechar-600"

for ($w = 600; $w -le 1400; $w += 20) { Size $w 860; Start-Sleep -Milliseconds 16 }
Start-Sleep 2; Shot "04-tras-ensanchar-1400"

for ($hh = 860; $hh -ge 560; $hh -= 15) { Size 1000 $hh; Start-Sleep -Milliseconds 16 }
Start-Sleep 2; Shot "05-tras-bajar-altura"

[W]::ShowWindow($script:h, 3) | Out-Null; Start-Sleep 3; Shot "06-maximizada"
[W]::ShowWindow($script:h, 9) | Out-Null; Start-Sleep 3; Shot "07-restaurada"
[W]::ShowWindow($script:h, 6) | Out-Null; Start-Sleep 2
[W]::ShowWindow($script:h, 9) | Out-Null; Start-Sleep 3; Shot "08-tras-minimizar"

Stop-Process -Id $p.Id -Force
