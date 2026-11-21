# Generates the windows/ folder, sets the Oganesson name and the app icon.
$ErrorActionPreference = 'Stop'
flutter create --org com.rafa --project-name notas --platforms=windows .
# flutter create adds a sample test that does not apply; our tests stay.
if (Test-Path test\widget_test.dart) { Remove-Item -Force test\widget_test.dart }

(Get-Content windows\runner\main.cpp) -replace 'L"notas"', 'L"Oganesson"' | Set-Content windows\runner\main.cpp
(Get-Content windows\CMakeLists.txt) -replace 'set\(BINARY_NAME "notas"\)', 'set(BINARY_NAME "Oganesson")' | Set-Content windows\CMakeLists.txt
(Get-Content windows\runner\Runner.rc) -replace '"notas"', '"Oganesson"' -replace 'notas\.exe', 'Oganesson.exe' | Set-Content windows\runner\Runner.rc
# The window is shown from Dart once the first frame is painted (lib/main.dart);
# the default runner shows it earlier, with a blank white frame.
(Get-Content windows\runner\flutter_window.cpp) -replace 'this->Show\(\);', '' | Set-Content windows\runner\flutter_window.cpp

flutter pub get
dart run flutter_launcher_icons -f icons-windows.yaml
if ($LASTEXITCODE -ne 0) { throw "Icon generation failed" }
