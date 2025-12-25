@echo off
echo ===================================
echo   Getting SHA-1 Fingerprint
echo ===================================
echo.

cd /d "%~dp0android"

echo Running gradlew signingReport...
echo.

call gradlew.bat signingReport

echo.
echo ===================================
echo Look for "SHA1:" in the output above
echo Copy the SHA1 value to Firebase Console
echo ===================================
pause