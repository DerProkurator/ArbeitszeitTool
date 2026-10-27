#Requires -Version 5.1
<#
==================================================================
 ArbeitszeitTool - Testeinstieg
 NICHT Teil der Auslieferung (export-ignore, siehe .gitattributes).

 Tests:    powershell.exe -NoProfile -File .\tests\Run-Tests.ps1
 Manuell:  powershell.exe -NoProfile -File .\tests\Run-Tests.ps1 -ScrollLockManual
           (optionaler, systemabhaengiger Scroll-Lock-Integrationstest mit
            ECHTEN Tastendruecken - laeuft nur nach ausdruecklicher Bestaetigung)

 Ablauf: Die Anwendung wird per Dot-Sourcing mit -DefinitionsOnly geladen
 (Funktionen, Konstanten, Assemblies/C#-Typen - KEIN Programmstart, kein
 Tresor, keine Dialoge), danach die Testsuite aus InternalTests.ps1.
 Beide teilen sich damit denselben Skriptbereich ($script:App usw.).
 Die Tests arbeiten ausschliesslich in temporaeren Testordnern und
 veraendern keine echten Benutzerdaten.
 Exitcode: 0 = alle Pruefungen bestanden, sonst Fehler.
==================================================================
#>
[CmdletBinding()]
param(
    [switch]$ScrollLockManual,
    # Zu pruefende Anwendung (Standard: ArbeitszeitTool.ps1 im Repository-Stamm)
    [string]$AppPath = ''
)

if ($AppPath -eq '') { $AppPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'ArbeitszeitTool.ps1' }
if (-not (Test-Path -LiteralPath $AppPath -PathType Leaf)) {
    Write-Host "Anwendung nicht gefunden: $AppPath" -ForegroundColor Red
    exit 1
}
# WPF-Tests benoetigen STA (Standard bei powershell.exe 5.1)
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Write-Host 'Die Tests benoetigen einen STA-Thread: bitte mit powershell.exe -Sta starten.' -ForegroundColor Red
    exit 1
}

. (Resolve-Path -LiteralPath $AppPath).Path -DefinitionsOnly
. (Join-Path $PSScriptRoot 'InternalTests.ps1')

Initialize-AppState
if ($ScrollLockManual) {
    $script:App.Settings = Get-DefaultSettings
    $exitCode = Invoke-ScrollLockManualTest
}
else {
    $exitCode = Invoke-InternalTests
}
exit $exitCode
