# Genera la carpeta windows/, pone el nombre BabuNotes y el icono.
$ErrorActionPreference = 'Stop'
flutter create --org com.rafa --project-name notas --platforms=windows .
if (Test-Path test) { Remove-Item -Recurse -Force test }

(Get-Content windows\runner\main.cpp) -replace 'L"notas"', 'L"BabuNotes"' | Set-Content windows\runner\main.cpp
(Get-Content windows\CMakeLists.txt) -replace 'set\(BINARY_NAME "notas"\)', 'set(BINARY_NAME "BabuNotes")' | Set-Content windows\CMakeLists.txt
(Get-Content windows\runner\Runner.rc) -replace '"notas"', '"BabuNotes"' -replace 'notas\.exe', 'BabuNotes.exe' | Set-Content windows\runner\Runner.rc

flutter pub get
dart run flutter_launcher_icons -f iconos-windows.yaml
if ($LASTEXITCODE -ne 0) { throw "Fallo al generar el icono" }
