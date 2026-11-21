# Generates the windows/ folder, sets the Oganesson name and the app icon.
$ErrorActionPreference = 'Stop'
flutter create --org com.rafa --project-name notas --platforms=windows .
if (Test-Path test) { Remove-Item -Recurse -Force test }

(Get-Content windows\runner\main.cpp) -replace 'L"notas"', 'L"Oganesson"' | Set-Content windows\runner\main.cpp
(Get-Content windows\CMakeLists.txt) -replace 'set\(BINARY_NAME "notas"\)', 'set(BINARY_NAME "Oganesson")' | Set-Content windows\CMakeLists.txt
(Get-Content windows\runner\Runner.rc) -replace '"notas"', '"Oganesson"' -replace 'notas\.exe', 'Oganesson.exe' | Set-Content windows\runner\Runner.rc

flutter pub get
dart run flutter_launcher_icons -f icons-windows.yaml
if ($LASTEXITCODE -ne 0) { throw "Icon generation failed" }
