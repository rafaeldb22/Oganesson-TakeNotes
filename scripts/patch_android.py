"""Enables core library desugaring in android/app/build.gradle(.kts),
required by flutter_local_notifications."""
import pathlib
import re
import sys

kts = pathlib.Path("android/app/build.gradle.kts")
groovy = pathlib.Path("android/app/build.gradle")
f = kts if kts.exists() else groovy
s = f.read_text()
if "desugar_jdk_libs" in s:
    sys.exit(0)

if f.suffix == ".kts":
    s = re.sub(r"compileOptions\s*\{", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", s, count=1)
    s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
else:
    s = re.sub(r"compileOptions\s*\{", "compileOptions {\n        coreLibraryDesugaringEnabled true", s, count=1)
    s += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
f.write_text(s)
print("Patched", f)
