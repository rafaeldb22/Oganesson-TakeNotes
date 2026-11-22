"""Patches the generated android/app/build.gradle(.kts):
- core library desugaring, required by flutter_local_notifications;
- compileSdk 37, required by receive_sharing_intent 1.9 (targetSdk is unchanged,
  so the app's runtime behaviour does not change)."""
import pathlib
import re

kts = pathlib.Path("android/app/build.gradle.kts")
groovy = pathlib.Path("android/app/build.gradle")
f = kts if kts.exists() else groovy
s = original = f.read_text()

if "desugar_jdk_libs" not in s:
    if f.suffix == ".kts":
        s = re.sub(r"compileOptions\s*\{", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", s, count=1)
        s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    else:
        s = re.sub(r"compileOptions\s*\{", "compileOptions {\n        coreLibraryDesugaringEnabled true", s, count=1)
        s += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"

if f.suffix == ".kts":
    s = re.sub(r"compileSdk\s*=\s*[^\n]+", "compileSdk = 37", s, count=1)
else:
    s = re.sub(r"compileSdk(Version)?\s+[^\n]+", "compileSdk 37", s, count=1)

if s != original:
    f.write_text(s)
    print("Patched", f)
