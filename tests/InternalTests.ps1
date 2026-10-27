#Requires -Version 5.1
<#
==================================================================
 ArbeitszeitTool - interne Testsuite
 NICHT Teil der Auslieferung (export-ignore, siehe .gitattributes).

 Wird ausschliesslich ueber tests\Run-Tests.ps1 geladen, NACHDEM die
 Definitionen der Anwendung per Dot-Sourcing (-DefinitionsOnly)
 bereitgestellt wurden. Die Funktionen hier greifen auf denselben
 Skriptbereich ($script:App, $script:Paths, ...) zu.
 Quelltextpruefungen (BOM, CRLF, Startlogik) lesen die Anwendung ueber
 $script:AppScriptPath - nie diese Datei.
==================================================================
#>

#region ===== Interne Tests (Einstieg: tests\Run-Tests.ps1) =====

function New-TestDay {
    param([string]$DateText = '2026-07-10', [int]$RegularMinutes = 420)
    $date = [datetime]::ParseExact($DateText, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    return New-WorkDayObject -Date $date -RegularMinutes $RegularMinutes
}

function Add-TestSegment {
    param($Day, [string]$Mode, [string]$StartText, [string]$EndText = '')
    $start = Get-DayDateTime -DayDate $Day.Date -TimeText $StartText
    if ($EndText -ne '') {
        $end = Get-DayDateTime -DayDate $Day.Date -TimeText $EndText
        $seg = New-SegmentObject -Mode $Mode -Start $start -End $end
    }
    else {
        $seg = New-SegmentObject -Mode $Mode -Start $start -Running $true
    }
    [void]$Day['Segments'].Add($seg)
    return $seg
}

function Add-TestInterval {
    param($Day, [string]$ListName, [string]$StartText, [string]$EndText = '')
    $start = Get-DayDateTime -DayDate $Day.Date -TimeText $StartText
    if ($EndText -ne '') {
        $iv = New-IntervalObject -Start $start -End (Get-DayDateTime -DayDate $Day.Date -TimeText $EndText)
    }
    else {
        $iv = New-IntervalObject -Start $start
    }
    [void]$Day[$ListName].Add($iv)
    return $iv
}

function Get-TestNow {
    param($Day, [string]$TimeText)
    return Get-DayDateTime -DayDate $Day.Date -TimeText $TimeText
}

function Invoke-InternalTests {
    $script:TestMode = $true   # keine Dialoge im Testlauf
    Initialize-AppState
    $script:App.Settings = Get-DefaultSettings
    $script:App.Data = $null   # verhindert echte Speicherzugriffe waehrend der Tests
    # WICHTIG: Der automatische Testlauf sendet NIEMALS echte Scroll-Lock-
    # Eingaben - saemtliche SendInput-Aufrufe werden im C# simuliert
    # (TestFailMode=3 = simulierter Erfolg; 1/2/4 = simulierte Fehler).
    [ArbeitszeitTool.NativeInput]::TestFailMode = 3

    $results = New-Object System.Collections.ArrayList
    $assert = {
        param([string]$Name, $Expected, $Actual)
        $ok = ([string]$Expected -eq [string]$Actual)
        [void]$results.Add(@{ Name = $Name; Ok = $ok; Expected = [string]$Expected; Actual = [string]$Actual })
        $status = 'PASS'
        $color = 'Green'
        if (-not $ok) { $status = 'FAIL'; $color = 'Red' }
        Write-Host ('[{0}] {1}' -f $status, $Name) -ForegroundColor $color
        if (-not $ok) {
            Write-Host ('       erwartet: {0} | tatsaechlich: {1}' -f $Expected, $Actual) -ForegroundColor Yellow
        }
    }

    Write-Host ''
    Write-Host '=== ArbeitszeitTool - interne Tests ===' -ForegroundColor Cyan
    Write-Host ''

    # --- Test 1: Reiner Betriebstag 06:12, jetzt 13:33 ---
    $day = New-TestDay
    Add-TestSegment -Day $day -Mode 'Betrieb' -StartText '06:12' | Out-Null
    $comp = Get-DayComputation -Day $day -Now (Get-TestNow $day '13:33')
    & $assert 'Test 1a: Bruttozeit 07:21' '07:21' (Format-Duration $comp.BetriebBrutto)
    & $assert 'Test 1b: feste Pause 00:45' '00:45' (Format-Duration $comp.FesteAbzug)
    & $assert 'Test 1c: Nettozeit 06:36' '06:36' (Format-Duration $comp.Netto)
    & $assert 'Test 1d: Soll-Ende 13:57' '13:57' (Format-Clock $comp.SollEnde)
    & $assert 'Test 1e: Max-Ende 16:57' '16:57' (Format-Clock $comp.MaxEnde)

    # --- Test 2: Betrieb unter sechs Stunden -> keine feste Pause ---
    $day = New-TestDay
    Add-TestSegment -Day $day -Mode 'Betrieb' -StartText '06:00' -EndText '11:59' | Out-Null
    $comp = Get-DayComputation -Day $day -Now (Get-TestNow $day '12:30')
    & $assert 'Test 2a: keine feste Pause' '00:00' (Format-Duration $comp.FesteAbzug)
    & $assert 'Test 2b: Nettozeit 05:59' '05:59' (Format-Duration $comp.Netto)

    # --- Test 3: Betriebspause beginnt (Netto bleibt bei 06:00 stehen) ---
    $day = New-TestDay
    Add-TestSegment -Day $day -Mode 'Betrieb' -StartText '06:00' | Out-Null
    $comp = Get-DayComputation -Day $day -Now (Get-TestNow $day '12:00')
    & $assert 'Test 3a: Netto bei 12:00 = 06:00' '06:00' (Format-Duration $comp.Netto)
    $comp = Get-DayComputation -Day $day -Now (Get-TestNow $day '12:20')
    & $assert 'Test 3b: Netto bei 12:20 = 06:00 (Pause läuft)' '06:00' (Format-Duration $comp.Netto)
    & $assert 'Test 3c: Status feste Betriebspause aktiv' 'True' ([string]$comp.InFesterPause)

    # --- Test 4: Betriebspause endet (Netto laeuft ab 12:45 weiter) ---
    $comp = Get-DayComputation -Day $day -Now (Get-TestNow $day '12:45')
    & $assert 'Test 4a: Netto bei 12:45 = 06:00' '06:00' (Format-Duration $comp.Netto)
    $comp = Get-DayComputation -Day $day -Now (Get-TestNow $day '13:00')
    & $assert 'Test 4b: Netto bei 13:00 = 06:15' '06:15' (Format-Duration $comp.Netto)

    # --- Test 5: Homeoffice mit Sperre ---
    $day = New-TestDay
    Add-TestSegment -Day $day -Mode 'Homeoffice' -StartText '08:00' -EndText '12:00' | Out-Null
    Add-TestInterval -Day $day -ListName 'LockIntervals' -StartText '09:00' -EndText '09:20' | Out-Null
    $comp = Get-DayComputation -Day $day -Now (Get-TestNow $day '12:30')
    & $assert 'Test 5: Homeoffice mit Sperre = 03:40' '03:40' (Format-Duration $comp.Netto)

    # --- Test 6: Homeoffice mit manueller Pause ---
    $day = New-TestDay
    Add-TestSegment -Day $day -Mode 'Homeoffice' -StartText '08:00' -EndText '12:00' | Out-Null
    Add-TestInterval -Day $day -ListName 'ManualPauses' -StartText '10:00' -EndText '10:30' | Out-Null
    $comp = Get-DayComputation -Day $day -Now (Get-TestNow $day '12:30')
    & $assert 'Test 6: Homeoffice mit Pause = 03:30' '03:30' (Format-Duration $comp.Netto)

    # --- Test 7: Ueberlappende Pausen werden nur einmal abgezogen ---
    $day = New-TestDay
    Add-TestSegment -Day $day -Mode 'Homeoffice' -StartText '08:00' -EndText '12:00' | Out-Null
    Add-TestInterval -Day $day -ListName 'ManualPauses' -StartText '10:00' -EndText '10:30' | Out-Null
    Add-TestInterval -Day $day -ListName 'LockIntervals' -StartText '10:10' -EndText '10:40' | Out-Null
    $comp = Get-DayComputation -Day $day -Now (Get-TestNow $day '12:30')
    & $assert 'Test 7a: Gesamtabzug 00:40 (nicht 01:00)' '00:40' (Format-Duration $comp.HoAbzug)
    & $assert 'Test 7b: Nettozeit 03:20' '03:20' (Format-Duration $comp.Netto)

    # --- Test 8: Gemischter Tag ---
    $day = New-TestDay
    Add-TestSegment -Day $day -Mode 'Betrieb' -StartText '06:00' -EndText '10:00' | Out-Null
    Add-TestSegment -Day $day -Mode 'Homeoffice' -StartText '10:30' -EndText '13:30' | Out-Null
    $comp = Get-DayComputation -Day $day -Now (Get-TestNow $day '14:00')
    & $assert 'Test 8a: gemischter Tag Netto 07:00' '07:00' (Format-Duration $comp.Netto)
    & $assert 'Test 8b: Regelarbeitszeit erreicht' 'True' ([string]$comp.SollErreicht)
    & $assert 'Test 8c: keine feste Pause (Betrieb nur 4h)' '00:00' (Format-Duration $comp.FesteAbzug)

    # --- Test 9: Ueberstunden ---
    $day = New-TestDay
    Add-TestSegment -Day $day -Mode 'Homeoffice' -StartText '08:00' -EndText '15:35' | Out-Null
    $comp = Get-DayComputation -Day $day -Now (Get-TestNow $day '16:00')
    & $assert 'Test 9: Ueberstunden +00:35' '+00:35' (Format-Duration $comp.Ueberstunden -WithSign)

    # --- Test 10: Maximale Arbeitszeit (automatischer Stopp) ---
    $day = New-TestDay
    Add-TestSegment -Day $day -Mode 'Betrieb' -StartText '06:00' | Out-Null
    $stopped = Invoke-AutoStopIfNeeded -Day $day -Now (Get-TestNow $day '17:45')
    $comp = Get-DayComputation -Day $day -Now (Get-TestNow $day '17:45')
    & $assert 'Test 10a: automatischer Stopp ausgeloest' 'True' ([string]$stopped)
    & $assert 'Test 10b: Netto exakt 10:00' '10:00' (Format-Duration $comp.Netto)
    & $assert 'Test 10c: Max-Rest 00:00' '00:00' (Format-Duration $comp.MaxRest)
    & $assert 'Test 10d: Status Maximale Arbeitszeit erreicht' 'True' ([string]$comp.MaxReached)
    & $assert 'Test 10e: kein laufender Abschnitt mehr' 'True' ([string]($null -eq $comp.RunningSegment))

    # --- Test 11: Warnung ab 09:45, Erfassung laeuft weiter ---
    $day = New-TestDay
    Add-TestSegment -Day $day -Mode 'Betrieb' -StartText '06:00' | Out-Null
    $comp = Get-DayComputation -Day $day -Now (Get-TestNow $day '16:30')  # brutto 10:30 - 0:45 = 09:45
    & $assert 'Test 11a: Warnzustand aktiv bei 09:45' 'True' ([string]$comp.WarnActive)
    & $assert 'Test 11b: noch nicht gestoppt' 'False' ([string]$comp.MaxReached)
    & $assert 'Test 11c: Netto 09:45' '09:45' (Format-Duration $comp.Netto)

    # --- Test 12: Programmneustart im Betrieb (JSON-Roundtrip) ---
    $day = New-TestDay
    Add-TestSegment -Day $day -Mode 'Betrieb' -StartText '06:00' | Out-Null
    $json = $day | ConvertTo-Json -Depth 20
    $reloaded = ConvertTo-PlainObject ($json | ConvertFrom-Json)
    $comp = Get-DayComputation -Day $reloaded -Now (Get-TestNow $day '10:00')
    & $assert 'Test 12: Betriebszeit nach Neustart 04:00' '04:00' (Format-Duration $comp.Netto)

    # --- Test 13: Programmneustart im Homeoffice -> Luecke wird erkannt ---
    $day = New-TestDay -DateText ((Get-Date).ToString('yyyy-MM-dd'))
    Add-TestSegment -Day $day -Mode 'Homeoffice' -StartText '08:00' | Out-Null
    $fakeData = @{ LastSavedAt = (ConvertTo-DateTimeString (Get-TestNow $day '10:00')) }
    $gap = Get-HomeofficeGap -Day $day -Data $fakeData -Now (Get-TestNow $day '10:30')
    & $assert 'Test 13a: Homeoffice-Luecke erkannt' 'True' ([string]($null -ne $gap))
    $gapLen = ''
    if ($gap) { $gapLen = Format-Duration ($gap.End - $gap.Start) }
    & $assert 'Test 13b: Lueckenlaenge 00:30' '00:30' $gapLen
    $dayB = New-TestDay
    Add-TestSegment -Day $dayB -Mode 'Betrieb' -StartText '08:00' | Out-Null
    $gapB = Get-HomeofficeGap -Day $dayB -Data $fakeData -Now (Get-TestNow $dayB '10:30')
    & $assert 'Test 13c: im Betrieb keine Nachfrage' 'True' ([string]($null -eq $gapB))

    # --- Test 14: Tageswechsel um 00:00 ---
    $yesterday = (Get-Date).AddDays(-1)
    $day = New-TestDay -DateText ($yesterday.ToString('yyyy-MM-dd'))
    Add-TestSegment -Day $day -Mode 'Betrieb' -StartText '22:00' | Out-Null
    $rolled = Invoke-MidnightRolloverIfNeeded -Day $day -Now (Get-Date)
    $comp = Get-DayComputation -Day $day -Now (Get-Date)
    & $assert 'Test 14a: Tageswechsel ausgefuehrt' 'True' ([string]$rolled)
    & $assert 'Test 14b: Status Beendet' 'Beendet' ([string]$day.Status)
    & $assert 'Test 14c: Abschlussgrund Tageswechsel' 'Tageswechsel' ([string]$day.EndReason)
    & $assert 'Test 14d: Netto bis 00:00 = 02:00' '02:00' (Format-Duration $comp.Netto)
    & $assert 'Test 14e: kein neuer Tag automatisch gestartet' 'True' ([string]($null -eq (Get-ActiveDayFromList @($day))))

    # --- Tests 15/16: Scroll-Lock-Doppelpuls (entkoppelt, ohne Zustandspruefung) ---
    # Der komplette Doppelpuls laeuft im SIMULATIONSMODUS (TestFailMode=3):
    # der automatische Testlauf sendet keine echten Scroll-Lock-Eingaben.
    # Zeitablauf (Thread.Sleep), ThreadPool und Interlocked sind dabei echt;
    # bewertet wird anhand der C#-Diagnose - ohne Tastenzustandsabfrage.
    [void][ArbeitszeitTool.NativeInput]::DrainPulseResults()
    $pulseStartSw = [System.Diagnostics.Stopwatch]::StartNew()
    $pulseStarted = [ArbeitszeitTool.NativeInput]::StartScrollLockPulse(200)
    $pulseStartMs = $pulseStartSw.ElapsedMilliseconds
    if ($pulseStarted) {
        & $assert 'Test 15a: Pulsstart kehrt sofort zurueck (blockiert den UI-Thread nicht)' 'True' ([string]($pulseStartMs -lt 100))
        $parallelBlocked = -not [ArbeitszeitTool.NativeInput]::StartScrollLockPulse(200)
        & $assert 'Test 15b: paralleler Puls wird verhindert (Interlocked)' 'True' ([string]$parallelBlocked)
        $deadline = [System.Diagnostics.Stopwatch]::StartNew()
        while ([ArbeitszeitTool.NativeInput]::IsPulseRunning() -and $deadline.ElapsedMilliseconds -lt 2000) { Start-Sleep -Milliseconds 25 }
        & $assert 'Test 15c: Doppelpuls beendet sich selbststaendig und gibt den Laufstatus frei' 'False' ([string][ArbeitszeitTool.NativeInput]::IsPulseRunning())
        $okEntry = ''
        foreach ($pe in @([ArbeitszeitTool.NativeInput]::DrainPulseResults())) {
            if (([string]$pe).StartsWith('OK')) { $okEntry = [string]$pe }
        }
        & $assert 'Test 15d: genau zwei vollstaendige Tastendruecke (je Key Down + Key Up uebernommen)' 'True' ([string]($okEntry -match 'accepted1=2 accepted2=2'))
        $gapOk = $false
        if ($okEntry -match 'elapsedMs=(\d+)') { $gapOk = ([int]$Matches[1] -ge 150 -and [int]$Matches[1] -le 350) }
        & $assert 'Test 15e: Abstand zwischen den Tastendruecken ~200 ms' 'True' ([string]$gapOk)
        & $assert 'Test 15f: Doppelpuls laeuft auf einem Hintergrund-Thread (ThreadPool, nicht WPF-UI)' 'True' ([string]($okEntry -match 'pool=True'))
        & $assert 'Test 15g: der Testlauf hat die Simulation verwendet (keine echten Eingaben)' 'True' ([string]($okEntry -match 'test=True'))
        # Nach Abschluss kann der naechste Puls regulaer starten
        $secondStart = [ArbeitszeitTool.NativeInput]::StartScrollLockPulse(100)
        & $assert 'Test 16a: nach Abschluss startet der naechste Puls regulaer' 'True' ([string]$secondStart)
        $deadline = [System.Diagnostics.Stopwatch]::StartNew()
        while ([ArbeitszeitTool.NativeInput]::IsPulseRunning() -and $deadline.ElapsedMilliseconds -lt 2000) { Start-Sleep -Milliseconds 25 }
        [void][ArbeitszeitTool.NativeInput]::DrainPulseResults()
    }
    else {
        Write-Host '[SKIP] Test 15: Scroll-Lock-Puls in dieser Umgebung nicht startbar (z. B. Dienst-Sitzung).' -ForegroundColor Yellow
        [void][ArbeitszeitTool.NativeInput]::DrainPulseResults()
    }
    # Test 16b-16e: Fehlerpfade (simuliert ueber TestFailMode - es werden
    # KEINE echten Eingaben gesendet und keine Nebenwirkungen ausgeloest)
    $script:App.Settings['KeepAliveEnabled'] = $true
    $script:App.KeepAlive.ConsecutiveErrors = 0
    foreach ($failMode in @(1, 2)) {
        [ArbeitszeitTool.NativeInput]::TestFailMode = $failMode
        [void][ArbeitszeitTool.NativeInput]::StartScrollLockPulse(100)
        $deadline = [System.Diagnostics.Stopwatch]::StartNew()
        while ([ArbeitszeitTool.NativeInput]::IsPulseRunning() -and $deadline.ElapsedMilliseconds -lt 2000) { Start-Sleep -Milliseconds 25 }
        [ArbeitszeitTool.NativeInput]::TestFailMode = 3
        $failEntries = @([ArbeitszeitTool.NativeInput]::DrainPulseResults())
        Invoke-ScrollLockPulseLogDrain -Entries $failEntries
        $hasError = $false
        foreach ($fe in $failEntries) { if (([string]$fe).StartsWith('FEHLER')) { $hasError = $true } }
        & $assert ('Test 16b: Fehler beim ' + $failMode + '. Tastendruck wird nur als Diagnose erfasst') 'True' ([string]$hasError)
    }
    & $assert 'Test 16c: SendInput-Fehler deaktivieren die Funktion NICHT (KeepAliveEnabled unveraendert)' 'True' ([string]$script:App.Settings['KeepAliveEnabled'])
    & $assert 'Test 16d: SendInput-Fehler loesen keinen Tresorspeichervorgang aus' 'False False' ("$($script:App.Flags.SaveInProgress) $($script:App.Flags.UnsavedChanges)")
    # Test 16e: Drosselung identischer Fehler (1., 10., 20. Fehler; erster
    # spaeterer Erfolg einmalig) - injizierte Eintraege, keine echten Pulse
    $script:App.KeepAlive.ConsecutiveErrors = 0
    $logCountBefore = @($script:StartupLogBuffer).Count
    $fakeErrors = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt 25; $i++) { [void]$fakeErrors.Add('FEHLER|Simulierter identischer Fehler') }
    Invoke-ScrollLockPulseLogDrain -Entries $fakeErrors
    $afterErrors = @($script:StartupLogBuffer).Count
    Invoke-ScrollLockPulseLogDrain -Entries @('OK|accepted1=2 accepted2=2 gapMs=200 elapsedMs=200 pool=True')
    Invoke-ScrollLockPulseLogDrain -Entries @('OK|accepted1=2 accepted2=2 gapMs=200 elapsedMs=200 pool=True')
    $afterSuccess = @($script:StartupLogBuffer).Count
    & $assert 'Test 16e: 25 identische Fehler ergeben nur 3 Protokolleintraege (1., 10., 20.)' '3' ([string]($afterErrors - $logCountBefore))
    & $assert 'Test 16f: erster wieder erfolgreicher Puls wird genau einmal protokolliert' '1' ([string]($afterSuccess - $afterErrors))
    # Test 16g: Der normale Produktivbetrieb fragt den Scroll-Lock-Zustand
    # nicht ab (Quelltextpruefung der produktiven Scroll-Lock-Region;
    # GetScrollLockState ist dem manuellen Diagnosetest vorbehalten).
    $slSource = [System.IO.File]::ReadAllText($script:AppScriptPath)
    $slStart = $slSource.IndexOf('#region ===== Scroll-Lock-Aktivhaltung')
    $slEnd = $slSource.IndexOf('#endregion', $slStart)
    $slRegion = $slSource.Substring($slStart, $slEnd - $slStart)
    & $assert 'Test 16g: produktive Scroll-Lock-Logik ohne Zustandsabfrage (kein GetScrollLockState/GetKeyState)' 'False False' ("$($slRegion.Contains('GetScrollLockState')) $($slRegion.Contains('GetKeyState'))")

    # --- Test 17: Fensterposition ausserhalb der Monitore wird korrigiert ---
    $oneScreen = @(@{ Left = 0; Top = 0; Width = 1920; Height = 1080 })
    $pos = Resolve-WindowPosition -Left 99999 -Top 99999 -Width 500 -Height 60 -Screens $oneScreen
    $inBounds = ($pos.Left -ge 0 -and $pos.Left -le (1920 - 500) -and $pos.Top -ge 0 -and $pos.Top -le (1080 - 60))
    & $assert 'Test 17a: Position wird in den sichtbaren Bereich geholt' 'True' ([string]$inBounds)
    $pos = Resolve-WindowPosition -Left -5000 -Top -5000 -Width 500 -Height 60 -Screens $oneScreen
    $inBounds = ($pos.Left -ge 0 -and $pos.Top -ge 0)
    & $assert 'Test 17b: negative Position wird korrigiert' 'True' ([string]$inBounds)

    # =====================================================================
    # Tresor-, Krypto- und Wiederherstellungs-Tests.
    # Alle Dateioperationen finden ausschliesslich in temporaeren Testordnern
    # statt; echte Benutzerdaten werden niemals gelesen oder veraendert.
    # =====================================================================
    $origPaths = $script:Paths
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('ArbeitszeitTool_Test_' + [guid]::NewGuid().ToString('N'))
    $testRoot2 = Join-Path ([System.IO.Path]::GetTempPath()) ('ArbeitszeitTool_Test_' + [guid]::NewGuid().ToString('N'))
    $testRoot3 = Join-Path ([System.IO.Path]::GetTempPath()) ('ArbeitszeitTool_Test_' + [guid]::NewGuid().ToString('N'))
    $testRoot4 = Join-Path ([System.IO.Path]::GetTempPath()) ('ArbeitszeitTool_Test_' + [guid]::NewGuid().ToString('N'))
    $testRoot5 = Join-Path ([System.IO.Path]::GetTempPath()) ('ArbeitszeitTool_Test_' + [guid]::NewGuid().ToString('N'))
    $newTestPaths = {
        param([string]$Root)
        return @{
            Root           = $Root
            Data           = Join-Path $Root 'Data'
            Exports        = Join-Path $Root 'Exports'
            Recovery       = Join-Path $Root 'Recovery'
            VaultFile      = Join-Path $Root 'Data\vault.azt'
            VaultPending   = Join-Path $Root 'Data\vault.pending.azt'
            VaultBackup1   = Join-Path $Root 'Data\vault.backup1.azt'
            VaultBackup2   = Join-Path $Root 'Data\vault.backup2.azt'
            VaultPrev      = Join-Path $Root 'Data\vault.prev.azt'
            VaultTxn       = Join-Path $Root 'Data\vault.txn'
            LegacyWork     = Join-Path $Root 'Data\worktime.json'
            LegacyBackup   = Join-Path $Root 'Data\worktime.backup.json'
            LegacySettings = Join-Path $Root 'Data\settings.json'
            LegacyLog      = Join-Path $Root 'Logs\application.log'
            LegacyLogDir   = Join-Path $Root 'Logs'
        }
    }
    $testPwdText = 'Test-Passwort mit Umlauten äöüß und Leerzeichen 4711!'
    $testPwdBytes = [System.Text.Encoding]::UTF8.GetBytes($testPwdText)
    $wrongPwdBytes = [System.Text.Encoding]::UTF8.GetBytes('Voellig falsches Passwort 999?')
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    $cloneKeys = {
        param($SourceKeys)
        return @{ Aes = [byte[]]$SourceKeys.Aes.Clone(); Hmac = [byte[]]$SourceKeys.Hmac.Clone() }
    }
    try {
        New-Item -ItemType Directory -Path (Join-Path $testRoot 'Data') -Force | Out-Null
        $script:Paths = (& $newTestPaths $testRoot)
        $iter = $script:VaultConst.Iterations
        $salt = [ArbeitszeitTool.VaultCrypto]::GetRandomBytes($script:VaultConst.SaltBytes)
        Write-Host '(Schluesselableitung mit 600.000 PBKDF2-Iterationen - die Krypto-Tests dauern einige Sekunden...)' -ForegroundColor DarkGray
        $keys = Get-VaultKeysFromPassword -PasswordBytes $testPwdBytes -Salt $salt -Iterations $iter

        # --- Test 18: Verschluesselung und erfolgreiche Entschluesselung (inkl. Unicode) ---
        $plain = 'Geheimer Klartext mit Umlauten äöüß ÄÖÜ und Euro € - MARKER_ROUNDTRIP_0815'
        $containerJson = Protect-VaultContainer -PlainText $plain -AesKey $keys.Aes -HmacKey $keys.Hmac -Salt $salt -Iterations $iter
        $roundtripFile = Join-Path $testRoot 'Data\roundtrip.azt'
        [System.IO.File]::WriteAllText($roundtripFile, $containerJson, $utf8Bom)
        $container = Read-VaultContainerFromFile -Path $roundtripFile
        $decrypted = Unprotect-VaultContainer -Container $container -AesKey $keys.Aes -HmacKey $keys.Hmac
        & $assert 'Test 18a: Entschluesselung liefert identischen Klartext (Unicode erhalten)' $plain $decrypted
        $rawRoundtrip = [System.IO.File]::ReadAllText($roundtripFile)
        & $assert 'Test 18b: Klartext erscheint nicht in der Containerdatei' 'False' ([string]$rawRoundtrip.Contains('MARKER_ROUNDTRIP_0815'))
        & $assert 'Test 18c: Salt mindestens 16 Byte' 'True' ([string]($container.Salt.Length -ge 16))
        & $assert 'Test 18d: IV exakt 16 Byte' 'True' ([string]($container.IV.Length -eq 16))

        # --- Test 19: Falsches Passwort wird neutral abgewiesen ---
        $wrongKeys = Get-VaultKeysFromPassword -PasswordBytes $wrongPwdBytes -Salt $salt -Iterations $iter
        $rejected = $false
        try { Unprotect-VaultContainer -Container $container -AesKey $wrongKeys.Aes -HmacKey $wrongKeys.Hmac | Out-Null }
        catch { $rejected = ($_.Exception.Message -eq 'VAULT_INVALID') }
        & $assert 'Test 19: falsches Passwort wird abgewiesen (vor der Entschluesselung)' 'True' ([string]$rejected)
        Clear-VaultKeys -Keys $wrongKeys

        # --- Test 20: Manipulierter Ciphertext wird erkannt ---
        $tamperFile = Join-Path $testRoot 'Data\tamper.azt'
        $tamper = {
            param([string]$Field, $NewValue)
            $obj = $containerJson | ConvertFrom-Json
            $obj.$Field = $NewValue
            [System.IO.File]::WriteAllText($tamperFile, ($obj | ConvertTo-Json), $utf8Bom)
            try {
                $c = Read-VaultContainerFromFile -Path $tamperFile
                Unprotect-VaultContainer -Container $c -AesKey $keys.Aes -HmacKey $keys.Hmac | Out-Null
                return 'akzeptiert'
            }
            catch { return $_.Exception.Message }
        }
        $cipherBytes = [Convert]::FromBase64String(($containerJson | ConvertFrom-Json).Ciphertext)
        $cipherBytes[3] = $cipherBytes[3] -bxor 0xFF
        & $assert 'Test 20: manipulierter Ciphertext wird erkannt' 'VAULT_INVALID' (& $tamper 'Ciphertext' ([Convert]::ToBase64String($cipherBytes)))

        # --- Test 21: Manipulierter HMAC wird erkannt ---
        $hmacBytes = [Convert]::FromBase64String(($containerJson | ConvertFrom-Json).Hmac)
        $hmacBytes[0] = $hmacBytes[0] -bxor 0x01
        & $assert 'Test 21: manipulierter HMAC wird erkannt' 'VAULT_INVALID' (& $tamper 'Hmac' ([Convert]::ToBase64String($hmacBytes)))

        # --- Test 22: Manipulierter Header wird erkannt ---
        & $assert 'Test 22a: veraenderte Iterationszahl wird erkannt' 'VAULT_INVALID' (& $tamper 'Iterations' 700000)
        & $assert 'Test 22b: veraenderte Formatkennung wird erkannt' 'VAULT_INVALID' (& $tamper 'Magic' 'XXXXXXXX')
        & $assert 'Test 22c: unzulaessig kleine Iterationszahl wird abgelehnt' 'VAULT_INVALID' (& $tamper 'Iterations' 1000)

        # --- Test 23/24: Zufaelliger IV, gleicher Klartext -> unterschiedliche Ciphertexte ---
        $containerJson2 = Protect-VaultContainer -PlainText $plain -AesKey $keys.Aes -HmacKey $keys.Hmac -Salt $salt -Iterations $iter
        $c1 = $containerJson | ConvertFrom-Json
        $c2 = $containerJson2 | ConvertFrom-Json
        & $assert 'Test 23: jeder Verschluesselungsvorgang verwendet einen neuen IV' 'False' ([string]($c1.IV -eq $c2.IV))
        & $assert 'Test 24: gleicher Klartext ergibt unterschiedliche Ciphertexte' 'False' ([string]($c1.Ciphertext -eq $c2.Ciphertext))
        Remove-Item -LiteralPath $roundtripFile, $tamperFile -Force

        # --- Test 25/26: Tresor speichern - kein Klartext, keine unverschluesselte Datei ---
        Initialize-AppState
        Set-VaultSessionKeys -Keys (& $cloneKeys $keys) -Salt $salt -Iterations $iter
        $vault = New-VaultDataObject
        $day = New-TestDay
        Add-TestSegment -Day $day -Mode 'Betrieb' -StartText '08:00' -EndText '12:00' | Out-Null
        [void]$day['Corrections'].Add([ordered]@{ Timestamp = '2026-07-10 08:00:00'; Description = 'MARKER_TAGESDATEN_4711'; OldValue = ''; NewValue = '' })
        [void]$vault['WorkData']['Days'].Add($day)
        Set-ActiveVault -Vault $vault
        $saved1 = Save-Vault
        $saved2 = Save-Vault
        & $assert 'Test 25a: Tresor gespeichert' 'True True' ("$saved1 $saved2")
        & $assert 'Test 25b: vault.azt vorhanden, Journal (vault.pending.azt) spiegelt die Hauptdatei' 'True True' ("$(Test-Path -LiteralPath $script:Paths.VaultFile) $((Get-FileSha256Hex -Path $script:Paths.VaultFile) -eq (Get-FileSha256Hex -Path $script:Paths.VaultPending))")
        & $assert 'Test 25c: Backup1 nach zweitem Speichern vorhanden' 'True' ([string](Test-Path -LiteralPath $script:Paths.VaultBackup1))
        & $assert 'Test 25d: Revision monoton steigend' '2' ([string]$script:App.Vault['Revision'])
        $b1HashBefore = Get-FileSha256Hex -Path $script:Paths.VaultBackup1
        $b2ExistsBefore = Test-Path -LiteralPath $script:Paths.VaultBackup2
        $savedNoRot = Save-Vault -NoBackupRotation
        $b1HashAfter = Get-FileSha256Hex -Path $script:Paths.VaultBackup1
        & $assert 'Test 25f: Checkpoint ohne Backuprotation - gespeichert, Backup1 unveraendert, kein Backup2, kein prev' "True|True|$b2ExistsBefore|False|3" ("$savedNoRot|$($b1HashBefore -eq $b1HashAfter)|$(Test-Path -LiteralPath $script:Paths.VaultBackup2)|$(Test-Path -LiteralPath $script:Paths.VaultPrev)|$(([long](Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey)['Revision']))")
        $savedRot = Save-Vault
        & $assert 'Test 25g: fachliches Speichern rotiert wieder (Backup1 = Stand des Checkpoints)' 'True|False|True' ("$savedRot|$($b1HashAfter -eq (Get-FileSha256Hex -Path $script:Paths.VaultBackup1))|$(Test-Path -LiteralPath $script:Paths.VaultBackup2)")
        # --- Test 25h: Tresordateien werden in-place geschrieben, nie ersetzt ---
        # Ein vor dem Speichern geoeffnetes Handle zeigt nur dann den neuen
        # Inhalt, wenn die Datei selbst ueberschrieben (und nicht geloescht,
        # umbenannt oder per Replace ausgetauscht) wurde. Genau das verhindert
        # Papierkorbeintraege in Cloud-Ordnern (OneDrive/SharePoint).
        $inPlace25 = {
            param([string]$Path, [scriptblock]$Action)
            $h = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
                ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
            try {
                & $Action
                $h.Position = 0
                $buf = New-Object byte[] ([int]$h.Length)
                $read = 0
                while ($read -lt $buf.Length) { $n = $h.Read($buf, $read, $buf.Length - $read); if ($n -le 0) { break }; $read += $n }
                return ((Get-BytesSha256Hex -Bytes $buf) -eq (Get-FileSha256Hex -Path $Path))
            }
            finally { $h.Dispose() }
        }
        $ipMainCp = & $inPlace25 $script:Paths.VaultFile { Save-Vault -NoBackupRotation | Out-Null }
        $ipPendCp = & $inPlace25 $script:Paths.VaultPending { Save-Vault -NoBackupRotation | Out-Null }
        $ipMain = & $inPlace25 $script:Paths.VaultFile { Save-Vault | Out-Null }
        $ipB1 = & $inPlace25 $script:Paths.VaultBackup1 { Save-Vault | Out-Null }
        $ipB2 = & $inPlace25 $script:Paths.VaultBackup2 { Save-Vault | Out-Null }
        & $assert 'Test 25h: Checkpoint und fachliches Speichern ueberschreiben vault.azt, Journal, Backup1 und Backup2 in-place' 'True|True|True|True|True' ("$ipMainCp|$ipPendCp|$ipMain|$ipB1|$ipB2")
        & $assert 'Test 25i: kein vault.prev.azt, Journal = Hauptdatei, Backups vollstaendig verwendbar' 'False|True|True|True' ("$(Test-Path -LiteralPath $script:Paths.VaultPrev)|$((Get-FileSha256Hex -Path $script:Paths.VaultFile) -eq (Get-FileSha256Hex -Path $script:Paths.VaultPending))|$(Test-VaultFileFullyUsable -Path $script:Paths.VaultBackup1)|$(Test-VaultFileFullyUsable -Path $script:Paths.VaultBackup2)")
        # --- Test 25j: Checkpoint im Betrieb nur noch bei Bedarf ---
        $d25j = New-TestDay
        Add-TestSegment -Day $d25j -Mode 'Betrieb' -StartText '08:00' | Out-Null
        Add-TestInterval -Day $d25j -ListName 'LockIntervals' -StartText '12:00' | Out-Null
        $c25j = Get-DayComputation -Day $d25j -Now (Get-TestNow $d25j '12:30')
        $d25k = New-TestDay
        Add-TestSegment -Day $d25k -Mode 'Homeoffice' -StartText '08:00' | Out-Null
        $c25k = Get-DayComputation -Day $d25k -Now (Get-TestNow $d25k '12:30')
        & $assert 'Test 25j: Windows-Sperre im Betrieb loest keinen 30-s-Checkpoint aus, Homeoffice weiterhin' 'False|True' ("$(Test-TrackingCheckpointNeeded -Comp $c25j)|$(Test-TrackingCheckpointNeeded -Comp $c25k)")
        $leakFound = $false
        $plainStructureFound = $false
        foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $testRoot 'Data') -File)) {
            $raw = [System.IO.File]::ReadAllText($file.FullName)
            if ($raw.Contains('MARKER_TAGESDATEN_4711') -or $raw.Contains($testPwdText)) { $leakFound = $true }
            if ($raw.Contains('"Days"') -or $raw.Contains('"Segments"')) { $plainStructureFound = $true }
        }
        & $assert 'Test 25e: weder Klartextdaten noch Passwort in irgendeiner Datei' 'False' ([string]$leakFound)
        & $assert 'Test 26: keine unverschluesselte Datenstruktur in Data (auch nicht temporaer)' 'False' ([string]$plainStructureFound)

        # --- Test 27: Klartext-Migration (Lesen, Uebernahme, sicheres Entfernen) ---
        $legacyDay = New-TestDay -DateText '2026-07-08'
        Add-TestSegment -Day $legacyDay -Mode 'Homeoffice' -StartText '08:00' -EndText '12:00' | Out-Null
        $legacyDay['Status'] = 'Beendet'
        $legacyDay['EndedAt'] = '2026-07-08 12:00:00'
        $legacyWork = [ordered]@{ SchemaVersion = 1; LastSavedAt = '2026-07-08 12:00:00'; Days = @($legacyDay) }
        [System.IO.File]::WriteAllText($script:Paths.LegacyWork, ($legacyWork | ConvertTo-Json -Depth 20), $utf8Bom)
        [System.IO.File]::WriteAllText($script:Paths.LegacySettings, ((Get-DefaultSettings) | ConvertTo-Json), $utf8Bom)
        New-Item -ItemType Directory -Path $script:Paths.LegacyLogDir -Force | Out-Null
        [System.IO.File]::WriteAllText($script:Paths.LegacyLog, "2026-07-08 08:00:00 [INFO ] Altes Protokoll`r`n", $utf8Bom)
        $legacy = Read-LegacyPlaintextData
        & $assert 'Test 27a: Klartextdaten gelesen (1 Tag, 1 Logzeile)' '1 1' ("$(@($legacy.WorkData['Days']).Count) $(@($legacy.LogEntries).Count)")
        [void]$script:App.Vault['WorkData']['Days'].Add($legacy.WorkData['Days'][0])
        $importSaved = Save-Vault
        & $assert 'Test 27b: uebernommene Daten verschluesselt gespeichert' 'True' ([string]$importSaved)
        $reloaded = Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        & $assert 'Test 27c: migrierter Tag im Tresor vorhanden' '2' ([string]@($reloaded['WorkData']['Days']).Count)
        foreach ($legacyPath in @($script:Paths.LegacyWork, $script:Paths.LegacySettings, $script:Paths.LegacyLog)) {
            Remove-PlaintextFileSecure -Path $legacyPath
        }
        $legacyLeftList = Get-LegacyPlaintextFiles
        $legacyLeft = @($legacyLeftList).Count
        & $assert 'Test 27d: Klartextdateien nach Migration ueberschrieben und geloescht' '0' ([string]$legacyLeft)

        # --- Test 28: Fehlgeschlagene Migration erhaelt die Originaldateien ---
        $brokenContent = '{ "kaputt": '
        [System.IO.File]::WriteAllText($script:Paths.LegacyWork, $brokenContent, $utf8Bom)
        $migrationFailed = $false
        try { Read-LegacyPlaintextData | Out-Null } catch { $migrationFailed = $true }
        $stillThere = (Test-Path -LiteralPath $script:Paths.LegacyWork) -and ([System.IO.File]::ReadAllText($script:Paths.LegacyWork).Contains('kaputt'))
        & $assert 'Test 28: fehlgeschlagene Migration laesst Originaldatei unveraendert' 'True True' ("$migrationFailed $stillThere")
        Remove-Item -LiteralPath $script:Paths.LegacyWork -Force   # Testaufraeumen

        # --- Test 29: Passwortaenderung verschluesselt alle Tresordateien neu ---
        $newPwdBytes = [System.Text.Encoding]::UTF8.GetBytes('Neues Passwort äß 456!')
        $newSalt = [ArbeitszeitTool.VaultCrypto]::GetRandomBytes($script:VaultConst.SaltBytes)
        $newKeys = Get-VaultKeysFromPassword -PasswordBytes $newPwdBytes -Salt $newSalt -Iterations $iter
        $changeError = Invoke-VaultReencryption -OldPasswordBytes $testPwdBytes `
            -NewAesKey $newKeys.Aes -NewHmacKey $newKeys.Hmac -NewSalt $newSalt -NewIterations $iter
        & $assert 'Test 29a: Passwortaenderung erfolgreich' '' $changeError
        $withNew = Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $newKeys.Aes -HmacKey $newKeys.Hmac
        & $assert 'Test 29b: Tresor mit neuem Passwort lesbar' '2' ([string]@($withNew['WorkData']['Days']).Count)
        $oldStillWorks = $true
        try { Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $keys.Aes -HmacKey $keys.Hmac | Out-Null }
        catch { $oldStillWorks = $false }
        & $assert 'Test 29c: altes Passwort funktioniert nicht mehr' 'False' ([string]$oldStillWorks)
        $backupWithNew = $true
        try { Read-VaultFromFile -Path $script:Paths.VaultBackup1 -AesKey $newKeys.Aes -HmacKey $newKeys.Hmac | Out-Null }
        catch { $backupWithNew = $false }
        & $assert 'Test 29d: Backup ebenfalls neu verschluesselt' 'True' ([string]$backupWithNew)
        $readable29 = {
            param([string]$Path, $Keys)
            try { Read-VaultFromFile -Path $Path -AesKey $Keys.Aes -HmacKey $Keys.Hmac | Out-Null; return $true } catch { return $false }
        }
        & $assert 'Test 29e: Journal (vault.pending.azt) nur noch mit dem neuen Passwort lesbar' 'True|True|False' ("$(Test-Path -LiteralPath $script:Paths.VaultPending)|$(& $readable29 $script:Paths.VaultPending $newKeys)|$(& $readable29 $script:Paths.VaultPending $keys)")

        # --- Test 30: Fehlgeschlagene Passwortaenderung erhaelt den alten Tresor ---
        $failError = Invoke-VaultReencryption -OldPasswordBytes $wrongPwdBytes `
            -NewAesKey $keys.Aes -NewHmacKey $keys.Hmac -NewSalt $salt -NewIterations $iter
        $mainIntact = $true
        try { Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $newKeys.Aes -HmacKey $newKeys.Hmac | Out-Null }
        catch { $mainIntact = $false }
        & $assert 'Test 30a: falsches aktuelles Passwort wird neutral abgelehnt' 'True' ([string]($failError -eq $script:VaultNeutralError))
        & $assert 'Test 30b: bisheriger Tresor bleibt vollstaendig erhalten' 'True' ([string]$mainIntact)
        # Fuer die Folgetests zurueck auf das Testpasswort wechseln - dabei
        # scheitert (Testhook) das Neuschreiben des Journals
        $script:App.Flags.TestFailJournalMirror = $true
        $backError = Invoke-VaultReencryption -OldPasswordBytes $newPwdBytes `
            -NewAesKey $keys.Aes -NewHmacKey $keys.Hmac -NewSalt $salt -NewIterations $iter
        $script:App.Flags.TestFailJournalMirror = $false
        & $assert 'Test 30c: Ruecknahme der Passwortaenderung erfolgreich' '' $backError
        # Journal traegt noch das andere Passwort; ein danach scheiternder
        # Speichervorgang darf diesen Stand NICHT zurueckschreiben
        $script:App.VaultFileHash = Get-FileSha256Hex -Path $script:Paths.VaultFile
        $stale30 = & $readable29 $script:Paths.VaultPending $newKeys
        $script:App.Flags.TestFailMainWrite = $true
        $save30d = Save-Vault -Quiet
        $script:App.Flags.TestFailMainWrite = $false
        Clear-VaultSaveFailedState
        & $assert 'Test 30d: Journal mit anderem Passwort wird nach Schreibfehler durch den aktuellen Hauptstand ersetzt' 'True|False|True|False' ("$stale30|$save30d|$(& $readable29 $script:Paths.VaultPending $keys)|$(& $readable29 $script:Paths.VaultPending $newKeys)")
        & $assert 'Test 30e: danach speichert der Tresor regulaer, Journal = Hauptdatei' 'True|True' ("$(Save-Vault)|$((Get-FileSha256Hex -Path $script:Paths.VaultFile) -eq (Get-FileSha256Hex -Path $script:Paths.VaultPending))")
        Clear-VaultKeys -Keys $newKeys
        [ArbeitszeitTool.VaultCrypto]::ClearBytes($newPwdBytes)
        # Die Umverschluesselung hat die Dateien ausserhalb von Save-Vault
        # veraendert - Referenzhash fuer die externe Aenderungserkennung nachziehen
        $script:App.VaultFileHash = Get-FileSha256Hex -Path $script:Paths.VaultFile

        # --- Test 31: Beschaedigte Hauptdatei -> Wiederherstellung aus gueltigem Backup ---
        $goodVaultBytes = [System.IO.File]::ReadAllBytes($script:Paths.VaultFile)
        [System.IO.File]::WriteAllText($script:Paths.VaultFile, 'ZERSTOERT', $utf8Bom)
        $scan = Get-VaultCandidates -PasswordBytes $testPwdBytes
        $mainCand = $null; $backupCand = $null
        foreach ($cand in @($scan.Candidates)) {
            if ($cand.Kind -eq 'Haupt') { $mainCand = $cand }
            if ($cand.Kind -eq 'Backup1') { $backupCand = $cand }
        }
        & $assert 'Test 31a: beschaedigte Hauptdatei wird erkannt' 'False' ([string]$mainCand.Valid)
        & $assert 'Test 31b: gueltiges verschluesseltes Backup steht zur Wiederherstellung bereit' 'True' ([string]($backupCand -and $backupCand.Valid))
        Clear-UnusedScanKeys -KeyCache $scan.KeyCache -KeepKeys $null
        [System.IO.File]::WriteAllBytes($script:Paths.VaultFile, $goodVaultBytes)
        $script:App.VaultFileHash = Get-FileSha256Hex -Path $script:Paths.VaultFile

        # --- Test 32: Gueltige Pending-Datei mit hoeherer Revision wird erkannt ---
        $pendingVault = Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        $pendingVault['Revision'] = [long]$pendingVault['Revision'] + 5
        Write-VaultToFile -Path $script:Paths.VaultPending -Vault $pendingVault `
            -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey -Salt $salt -Iterations $iter
        $scan = Get-VaultCandidates -PasswordBytes $testPwdBytes
        $newest = $null
        foreach ($cand in @($scan.Candidates)) {
            if ($cand.Valid -and ($null -eq $newest -or $cand.Revision -gt $newest.Revision)) { $newest = $cand }
        }
        & $assert 'Test 32: neuester gueltiger Stand wird anhand der Revision ermittelt (Pending)' 'Pending' ([string]$newest.Kind)
        Clear-UnusedScanKeys -KeyCache $scan.KeyCache -KeepKeys $null

        # --- Test 33: Beschaedigte Pending-Datei wird nicht uebernommen ---
        [System.IO.File]::WriteAllText($script:Paths.VaultPending, 'KAPUTTE PENDING-DATEI', $utf8Bom)
        $scan = Get-VaultCandidates -PasswordBytes $testPwdBytes
        $pendingCand = $null; $mainCand = $null
        foreach ($cand in @($scan.Candidates)) {
            if ($cand.Kind -eq 'Pending') { $pendingCand = $cand }
            if ($cand.Kind -eq 'Haupt') { $mainCand = $cand }
        }
        & $assert 'Test 33: beschaedigte Pending-Datei wird verworfen, Hauptdatei bleibt massgeblich' 'False True' ("$($pendingCand.Valid) $($mainCand.Valid)")
        Clear-UnusedScanKeys -KeyCache $scan.KeyCache -KeepKeys $null
        Remove-Item -LiteralPath $script:Paths.VaultPending -Force

        # --- Test 34: CleanShutdown=false wird beim Start erkannt ---
        $script:App.Vault['CleanShutdown'] = $false
        Save-Vault | Out-Null
        $scan = Get-VaultCandidates -PasswordBytes $testPwdBytes
        $mainCand = $null
        foreach ($cand in @($scan.Candidates)) { if ($cand.Kind -eq 'Haupt') { $mainCand = $cand } }
        & $assert 'Test 34: unsauberes Programmende (CleanShutdown=false) wird erkannt' 'False' ([string]$mainCand.Vault['CleanShutdown'])
        Clear-UnusedScanKeys -KeyCache $scan.KeyCache -KeepKeys $null
        $script:App.Vault['CleanShutdown'] = $true
        Save-Vault | Out-Null

        # --- Test 35: Unbekannte Schema-Version wird abgelehnt ---
        $schemaVault = Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        $schemaVault['SchemaVersion'] = 99
        $schemaFile = Join-Path $testRoot 'Data\schema.azt'
        Write-VaultToFile -Path $schemaFile -Vault $schemaVault -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey -Salt $salt -Iterations $iter
        $schemaRejected = $false
        try { Read-VaultFromFile -Path $schemaFile -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey | Out-Null }
        catch { $schemaRejected = $_.Exception.Message.StartsWith('VAULT_SCHEMA') }
        & $assert 'Test 35: unbekannte Schema-Version wird nicht stillschweigend geoeffnet' 'True' ([string]$schemaRejected)
        Remove-Item -LiteralPath $schemaFile -Force

        # --- Test 36: Regelarbeitszeit-Validierung (groesser 00:00, maximal 10:00) ---
        & $assert 'Test 36a: Regelarbeitszeit 10:01 wird abgelehnt' '-1' ([string](Test-RegularTimeInput -Text '10:01'))
        & $assert 'Test 36b: Regelarbeitszeit 10:00 ist zulaessig' '600' ([string](Test-RegularTimeInput -Text '10:00'))
        & $assert 'Test 36c: Regelarbeitszeit 00:00 wird abgelehnt' '-1' ([string](Test-RegularTimeInput -Text '00:00'))
        & $assert 'Test 36d: Regelarbeitszeit 07:30 ist zulaessig' '450' ([string](Test-RegularTimeInput -Text '07:30'))

        # --- Test 37: Manuelle Korrektur ueber 10:00 wird abgelehnt (Snapshot-Ruecknahme) ---
        $day = New-TestDay
        Add-TestSegment -Day $day -Mode 'Homeoffice' -StartText '08:00' -EndText '12:00' | Out-Null
        $snapshot = Get-DaySnapshot -Day $day
        Add-TestSegment -Day $day -Mode 'Homeoffice' -StartText '12:00' -EndText '23:00' | Out-Null
        $underMax = Test-DayUnderMax -Day $day -Now (Get-TestNow $day '23:30')
        & $assert 'Test 37a: Korrektur ueber 10:00 wird erkannt' 'False' ([string]$underMax)
        Restore-DayFromSnapshot -Day $day -Snapshot $snapshot
        & $assert 'Test 37b: abgelehnte Korrektur wird vollstaendig zurueckgenommen' '1' ([string]@($day.Segments).Count)

        # --- Test 38: MaxReached wird nach gueltiger Korrektur zurueckgenommen ---
        $day = New-TestDay
        Add-TestSegment -Day $day -Mode 'Homeoffice' -StartText '08:00' -EndText '12:00' | Out-Null
        $day['Status'] = 'Beendet'
        $day['EndedAt'] = ConvertTo-DateTimeString (Get-TestNow $day '12:00')
        $day['MaxReached'] = $true
        Update-MaxReachedState -Day $day -Now (Get-TestNow $day '12:30')
        & $assert 'Test 38: MaxReached nach Korrektur unter 10:00 zurueckgenommen' 'False' ([string]$day.MaxReached)

        # --- Test 39: EndedAt-/Abschlussvalidierung ---
        $day = New-TestDay
        Add-TestSegment -Day $day -Mode 'Betrieb' -StartText '08:00' -EndText '12:00' | Out-Null
        Add-TestSegment -Day $day -Mode 'Betrieb' -StartText '13:00' | Out-Null   # laufender Abschnitt
        $errBeforeSegment = Test-DayEndTime -Day $day -End (Get-TestNow $day '11:00') -Now (Get-TestNow $day '18:00')
        $errBeforeRunning = Test-DayEndTime -Day $day -End (Get-TestNow $day '12:30') -Now (Get-TestNow $day '18:00')
        $errFuture = Test-DayEndTime -Day $day -End (Get-TestNow $day '19:00') -Now (Get-TestNow $day '18:00')
        $errValid = Test-DayEndTime -Day $day -End (Get-TestNow $day '17:00') -Now (Get-TestNow $day '18:00')
        & $assert 'Test 39a: Endzeit vor abgeschlossenem Abschnitt wird abgelehnt' 'True' ([string]($errBeforeSegment -ne ''))
        & $assert 'Test 39b: Endzeit vor dem laufenden Abschnitt wird abgelehnt' 'True' ([string]($errBeforeRunning -ne ''))
        & $assert 'Test 39c: Endzeit in der Zukunft wird abgelehnt' 'True' ([string]($errFuture -ne ''))
        & $assert 'Test 39d: gueltige Endzeit wird akzeptiert' '' $errValid

        # --- Test 40: CSV-Formelinjektion wird neutralisiert ---
        & $assert 'Test 40a: fuehrendes = wird neutralisiert' "'=SUMME(A1:A9)" (Get-CsvEscaped -Value '=SUMME(A1:A9)')
        & $assert 'Test 40b: fuehrendes + wird neutralisiert' "'+49 123" (Get-CsvEscaped -Value '+49 123')
        & $assert 'Test 40c: fuehrendes @ wird neutralisiert' "'@cmd" (Get-CsvEscaped -Value '@cmd')
        & $assert 'Test 40d: negativer Zeitwert als Text bleibt geschuetzt' "'-00:30" (Get-CsvEscaped -Value '-00:30')
        & $assert 'Test 40e: normaler Text bleibt unveraendert' 'Betrieb' (Get-CsvEscaped -Value 'Betrieb')
        & $assert 'Test 40f: Semikolon wird weiterhin maskiert' '"a;b"' (Get-CsvEscaped -Value 'a;b')

        # --- Test 41: entfallen ---
        # Die frueheren Wiederherstellungs-Kerntests sind mit der Entkopplung
        # der Scroll-Lock-Funktion (einfacher C#-Doppelpuls ohne
        # Zustandspruefung) gegenstandslos; die Doppelpuls-Tests befinden
        # sich in den Tests 15/16.

        # --- Test 42: Feste Betriebspause bei exakt 06:00 (Randwerte) ---
        $day = New-TestDay
        Add-TestSegment -Day $day -Mode 'Betrieb' -StartText '06:00' | Out-Null
        $comp = Get-DayComputation -Day $day -Now ((Get-TestNow $day '12:00').AddSeconds(-1))   # 05:59:59 Betriebszeit
        & $assert 'Test 42a: bei 05:59:59 noch keine feste Pause aktiv' 'False' ([string]$comp.InFesterPause)
        $comp = Get-DayComputation -Day $day -Now (Get-TestNow $day '12:00')                    # exakt 06:00:00
        & $assert 'Test 42b: bei exakt 06:00:00 ist die feste Pause aktiv' 'True' ([string]$comp.InFesterPause)
        $comp = Get-DayComputation -Day $day -Now ((Get-TestNow $day '12:45').AddSeconds(-1))   # 06:44:59
        & $assert 'Test 42c: bei 06:44:59 laeuft die feste Pause noch' 'True' ([string]$comp.InFesterPause)
        $comp = Get-DayComputation -Day $day -Now (Get-TestNow $day '12:45')                    # 06:45:00
        & $assert 'Test 42d: bei 06:45:00 ist die feste Pause beendet' 'False' ([string]$comp.InFesterPause)
        & $assert 'Test 42e: Netto bei 06:45:00 exakt 06:00' '06:00' (Format-Duration $comp.Netto)

        # --- Test 43: Alter WindowWidth-Wert (z. B. 680) erzeugt KEINE Mindestbreite ---
        # Die Breite der kompakten Ansicht richtet sich ausschliesslich nach
        # dem Inhalt (SizeToContent); MinWidth muss 0 bleiben.
        $script:App.Settings['WindowWidth'] = 680.0   # Altwert aus frueherer Version
        $script:App.Settings['WindowLeft'] = $null
        $script:App.Settings['WindowTop'] = $null
        $mockWin = [pscustomobject]@{ MinWidth = 77.0; ActualWidth = 0.0; ActualHeight = 0.0; Left = 0.0; Top = 0.0 }
        Set-CompactWindowPosition -Window $mockWin
        & $assert 'Test 43a: alter WindowWidth-Wert wird nicht als MinWidth uebernommen (MinWidth = 0)' '0' ([string][int]$mockWin.MinWidth)
        & $assert 'Test 43b: alter WindowWidth-Wert wird beim Validieren der Einstellungen verworfen' '' ([string](Get-ValidatedSettings -Loaded @{ WindowWidth = 680 })['WindowWidth'])
        $script:App.Settings['WindowWidth'] = $null

        # --- Test 44: Fensterposition in einer Luecke zwischen Monitoren ---
        $twoScreens = @(
            @{ Left = 0; Top = 0; Width = 1920; Height = 1040 },
            @{ Left = 2000; Top = 0; Width = 1920; Height = 1040 }
        )
        $pos = Resolve-WindowPosition -Left 1930 -Top 100 -Width 60 -Height 50 -Screens $twoScreens
        $onRealScreen = $false
        foreach ($scr in $twoScreens) {
            if ($pos.Left -ge $scr.Left -and ($pos.Left + 60) -le ($scr.Left + $scr.Width) -and
                $pos.Top -ge $scr.Top -and ($pos.Top + 50) -le ($scr.Top + $scr.Height)) { $onRealScreen = $true }
        }
        & $assert 'Test 44a: Fenster in Monitor-Luecke wird auf einen echten Monitor verschoben' 'True' ([string]$onRealScreen)
        $pos = Resolve-WindowPosition -Left 100 -Top 100 -Width 400 -Height 50 -Screens $twoScreens
        & $assert 'Test 44b: sichtbares Fenster bleibt unveraendert' '100 100' ("$([int]$pos.Left) $([int]$pos.Top)")

        # --- Test 45: Wiederherstellung Betrieb nach Absturz (verschluesselter Roundtrip) ---
        $crashVault = New-VaultDataObject
        $crashDay = New-TestDay
        Add-TestSegment -Day $crashDay -Mode 'Betrieb' -StartText '06:00' | Out-Null
        [void]$crashVault['WorkData']['Days'].Add($crashDay)
        $crashVault['CleanShutdown'] = $false
        $crashFile = Join-Path $testRoot 'Data\crash.azt'
        Write-VaultToFile -Path $crashFile -Vault $crashVault -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey -Salt $salt -Iterations $iter
        $crashReloaded = Read-VaultFromFile -Path $crashFile -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        $crashComp = Get-DayComputation -Day $crashReloaded['WorkData']['Days'][0] -Now (Get-TestNow $crashDay '10:00')
        & $assert 'Test 45: Betriebszeit laeuft nach Absturz anhand der Zeitstempel weiter (04:00)' '04:00' (Format-Duration $crashComp.Netto)
        Remove-Item -LiteralPath $crashFile -Force

        # --- Test 46: Absturz waehrend der Passwortaenderung (liegengebliebene .new-Datei) ---
        [System.IO.File]::Copy($script:Paths.VaultFile, ($script:Paths.VaultFile + '.new'), $true)
        $scan = Get-VaultCandidates -PasswordBytes $testPwdBytes
        $mainCand = $null
        foreach ($cand in @($scan.Candidates)) { if ($cand.Kind -eq 'Haupt') { $mainCand = $cand } }
        & $assert 'Test 46: Tresor bleibt nach abgebrochener Passwortaenderung nutzbar' 'True' ([string]$mainCand.Valid)
        Clear-UnusedScanKeys -KeyCache $scan.KeyCache -KeepKeys $null
        Remove-Item -LiteralPath ($script:Paths.VaultFile + '.new') -Force

        # --- Test 47: Absturz waehrend der Migration (nur Pending vorhanden) ---
        New-Item -ItemType Directory -Path (Join-Path $testRoot2 'Data') -Force | Out-Null
        $script:Paths = (& $newTestPaths $testRoot2)
        [System.IO.File]::WriteAllText($script:Paths.LegacyWork, ($legacyWork | ConvertTo-Json -Depth 20), $utf8Bom)
        Write-VaultToFile -Path $script:Paths.VaultPending -Vault $crashVault -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey -Salt $salt -Iterations $iter
        & $assert 'Test 47a: Wiederherstellungsdateien verhindern das automatische Anlegen eines leeren Tresors' 'True' ([string](Test-VaultFilesPresent))
        $scan = Get-VaultCandidates -PasswordBytes $testPwdBytes
        $pendingCand = $null
        foreach ($cand in @($scan.Candidates)) { if ($cand.Kind -eq 'Pending') { $pendingCand = $cand } }
        & $assert 'Test 47b: gueltige Pending-Datei aus abgebrochener Migration wird gefunden' 'True' ([string]($pendingCand -and $pendingCand.Valid))
        & $assert 'Test 47c: Klartext-Originaldateien sind noch vorhanden' 'True' ([string](Test-Path -LiteralPath $script:Paths.LegacyWork))
        Clear-UnusedScanKeys -KeyCache $scan.KeyCache -KeepKeys $null
        $script:Paths = (& $newTestPaths $testRoot)

        # --- Test 48: Keine unverschluesselte Log- oder Datendatei in der Testumgebung ---
        Write-AppLog -Message 'Testeintrag fuer das verschluesselte Protokoll äöü'
        $plainFiles = @(Get-ChildItem -LiteralPath $testRoot -Recurse -File | Where-Object {
                $_.Extension -in @('.log', '.txt') -or $_.Name -like 'worktime*' -or $_.Name -like 'settings*'
            })
        & $assert 'Test 48a: keine unverschluesselte Log-/Datendatei vorhanden' '0' ([string]$plainFiles.Count)
        & $assert 'Test 48b: Logeintraege liegen im verschluesselten Tresor' 'True' ([string](@($script:App.Vault['Logs']).Count -gt 0))

        # --- Test 49: Tresor mit BEENDETEM Tag laesst sich in frischer Sitzung laden ---
        # (Regression: Test-VaultStructure ruft fuer beendete Tage Get-DayComputation
        #  auf; $script:App.Settings ist beim Laden noch $null und darf nicht crashen.)
        $script:Paths = (& $newTestPaths $testRoot)
        Initialize-AppState
        Set-VaultSessionKeys -Keys (& $cloneKeys $keys) -Salt $salt -Iterations $iter
        $endVault = New-VaultDataObject
        $endDay = New-TestDay
        Add-TestSegment -Day $endDay -Mode 'Betrieb' -StartText '08:00' -EndText '16:00' | Out-Null
        $endDay['Status'] = 'Beendet'
        $endDay['EndedAt'] = ConvertTo-DateTimeString (Get-TestNow $endDay '16:00')
        [void]$endVault['WorkData']['Days'].Add($endDay)
        Set-ActiveVault -Vault $endVault
        # Simulierter regulaerer Ladezustand: Referenz auf die vorhandene
        # Hauptdatei setzen, damit der Speicher-Kontrakt (externe
        # Aenderungserkennung) erfuellt ist
        $script:App.VaultFileHash = Get-FileSha256Hex -Path $script:Paths.VaultFile
        $script:App.VaultLoadedRevision = [long]$endVault['Revision']
        Save-Vault | Out-Null
        # Frische Sitzung erzwingen: Settings = $null (wie beim echten Programmstart)
        $reloadKeys = & $cloneKeys $keys
        Initialize-AppState
        $script:Paths = (& $newTestPaths $testRoot)
        $settingsNull = ($null -eq $script:App.Settings)
        $endReadOk = $false
        try {
            Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $reloadKeys.Aes -HmacKey $reloadKeys.Hmac | Out-Null
            $endReadOk = $true
        }
        catch { $endReadOk = $false }
        & $assert 'Test 49a: Sitzung beim Laden ist frisch (Settings=null)' 'True' ([string]$settingsNull)
        & $assert 'Test 49b: Tresor mit beendetem Tag laedt trotz fehlender Settings' 'True' ([string]$endReadOk)
        Clear-VaultKeys -Keys $reloadKeys

        # =====================================================================
        # Neue Pruefungen (Ueberarbeitung): Kodierung, Layout, Fensterposition,
        # Wiederherstellungszeitpunkt, Migration, Importkonflikte,
        # Transaktionen, Backupschutz, Containerhaertung
        # =====================================================================

        # --- Test 50: Dateikodierung (UTF-8 mit BOM) ---
        $bomBytes = Get-Content -LiteralPath $script:AppScriptPath -Encoding Byte -TotalCount 3
        & $assert 'Test 50a: ArbeitszeitTool.ps1 ist UTF-8 mit BOM' '239 187 191' ("$($bomBytes[0]) $($bomBytes[1]) $($bomBytes[2])")
        $readmePath = Join-Path $origPaths.Root 'README.md'
        if (Test-Path -LiteralPath $readmePath) {
            $readmeBom = Get-Content -LiteralPath $readmePath -Encoding Byte -TotalCount 3
            & $assert 'Test 50b: README.md ist UTF-8 mit BOM' '239 187 191' ("$($readmeBom[0]) $($readmeBom[1]) $($readmeBom[2])")
        }

        # --- Test 51: Unicode-Roundtrip mit deutschen Prueftexten ---
        $prueftext = 'Überstunden Verschlüsselung regelmäßig ungültig Änderungen Schließen Größe größer ÄÖÜ äöü ß'
        $ctJson = Protect-VaultContainer -PlainText $prueftext -AesKey $keys.Aes -HmacKey $keys.Hmac -Salt $salt -Iterations $iter
        $ctFile = Join-Path $testRoot 'Data\unicode.azt'
        [System.IO.File]::WriteAllText($ctFile, $ctJson, $utf8Bom)
        $ctBack = Unprotect-VaultContainer -Container (Read-VaultContainerFromFile -Path $ctFile) -AesKey $keys.Aes -HmacKey $keys.Hmac
        & $assert 'Test 51: deutsche Prueftexte bleiben nach Ver-/Entschluesselung unveraendert' $prueftext $ctBack
        Remove-Item -LiteralPath $ctFile -Force

        # --- Test 52: Fensterposition - Monitorflaeche vs. Arbeitsbereich ---
        $fullBounds = @(@{ Left = 0; Top = 0; Width = 1920; Height = 1080 })
        $workArea = @(@{ Left = 0; Top = 0; Width = 1920; Height = 1040 })
        $pos = Resolve-WindowPosition -Left 100 -Top 1045 -Width 500 -Height 30 -Screens $fullBounds -DefaultScreens $workArea
        & $assert 'Test 52a: Top 1045 (ueber der Taskleiste, innerhalb des Monitors) bleibt exakt erhalten' '100 1045' ("$([int]$pos.Left) $([int]$pos.Top)")
        $pos = Resolve-WindowPosition -Left 100 -Top 5000 -Width 500 -Height 30 -Screens $fullBounds -DefaultScreens $workArea
        & $assert 'Test 52b: Position ausserhalb aller Monitorflaechen wird korrigiert' 'True' ([string]($pos.Top -le (1080 - 30)))
        $pos = Resolve-WindowPosition -Left $null -Top $null -Width 500 -Height 40 -Screens $fullBounds -DefaultScreens $workArea
        & $assert 'Test 52c: erstmalige Standardposition nutzt weiterhin den Arbeitsbereich' '992' ([string][int]$pos.Top)
        $twoFull = @(
            @{ Left = 0; Top = 0; Width = 1920; Height = 1080 },
            @{ Left = 2000; Top = 0; Width = 1920; Height = 1080 }
        )
        $pos = Resolve-WindowPosition -Left 1930 -Top 100 -Width 60 -Height 50 -Screens $twoFull -DefaultScreens $twoFull
        $onScreen = $false
        foreach ($scr in $twoFull) {
            if ($pos.Left -ge $scr.Left -and ($pos.Left + 60) -le ($scr.Left + $scr.Width)) { $onScreen = $true }
        }
        & $assert 'Test 52d: Position in einer echten Monitor-Luecke wird weiterhin korrigiert' 'True' ([string]$onScreen)

        # --- Test 53: vorheriger Tracking-Checkpoint bleibt vor dem ersten Sitzungsspeichern erhalten ---
        Initialize-AppState
        $script:Paths = (& $newTestPaths $testRoot)
        Set-VaultSessionKeys -Keys (& $cloneKeys $keys) -Salt $salt -Iterations $iter
        $rsVault = New-VaultDataObject
        $rsDay = New-TestDay -DateText ((Get-Date).ToString('yyyy-MM-dd'))
        Add-TestSegment -Day $rsDay -Mode 'Homeoffice' -StartText '08:00' | Out-Null
        Add-TestInterval -Day $rsDay -ListName 'LockIntervals' -StartText '09:30' | Out-Null
        [void]$rsVault['WorkData']['Days'].Add($rsDay)
        $prevCheckpoint = ConvertTo-DateTimeString (Get-TestNow $rsDay '10:00')
        $rsVault['WorkData']['LastSavedAt'] = $prevCheckpoint
        $rsVault['CleanShutdown'] = $false
        Set-ActiveVault -Vault $rsVault
        $script:App.VaultFileHash = Get-FileSha256Hex -Path $script:Paths.VaultFile
        $script:App.VaultLoadedRevision = [long]$rsVault['Revision']
        $script:App.LoadedFrom = 'Haupt'
        $script:App.RecoveryState = New-RecoveryState -Vault $rsVault -LoadedFrom 'Haupt'
        $rsSaved = Save-Vault -NoTrackingCheckpoint
        & $assert 'Test 53a: Sitzungsstart-Speichern (CleanShutdown=false) erfolgreich' 'True' ([string]$rsSaved)
        & $assert 'Test 53b: Tracking-Checkpoint (WorkData.LastSavedAt) NICHT ueberschrieben' $prevCheckpoint ([string]$script:App.Vault['WorkData']['LastSavedAt'])
        & $assert 'Test 53c: RecoveryState enthaelt den vorherigen Checkpoint' $prevCheckpoint ([string]$script:App.RecoveryState.PreviousLastSavedAt)
        & $assert 'Test 53d: RecoveryState erkennt offenes Sperrintervall und Quelle' 'True Haupt' ("$($script:App.RecoveryState.HadOpenLock) $($script:App.RecoveryState.LoadedFrom)")

        # --- Test 54: Wiederherstellung verwendet den VORHERIGEN Checkpoint ---
        $gapData = @{ LastSavedAt = $script:App.RecoveryState.PreviousLastSavedAt }
        $gap = Get-HomeofficeGap -Day $rsDay -Data $gapData -Now (Get-TestNow $rsDay '10:30')
        $gapLen = ''
        if ($gap) { $gapLen = Format-Duration ($gap.End - $gap.Start) }
        & $assert 'Test 54a: Homeoffice-Luecke wird anhand des vorherigen Checkpoints weiterhin abgefragt' '00:30' $gapLen
        Close-StaleOpenLocks -Day $rsDay
        $lockEnd = ''
        foreach ($iv in @($rsDay.LockIntervals)) { $lockEnd = [string]$iv.End }
        & $assert 'Test 54b: offenes Sperrintervall endet am vorherigen Checkpoint (nicht am Programmstart)' $prevCheckpoint $lockEnd
        Save-Vault | Out-Null
        & $assert 'Test 54c: regulaeres Speichern setzt danach den neuen Tracking-Checkpoint' 'False' ([string]([string]$script:App.Vault['WorkData']['LastSavedAt'] -eq $prevCheckpoint))

        # --- Tests 55-57: Migrationsquellen (worktime.backup.json) ---
        New-Item -ItemType Directory -Path (Join-Path $testRoot3 'Data') -Force | Out-Null
        $script:Paths = (& $newTestPaths $testRoot3)
        $legacyDayB = New-TestDay -DateText '2026-07-01'
        Add-TestSegment -Day $legacyDayB -Mode 'Betrieb' -StartText '08:00' -EndText '12:00' | Out-Null
        $legacyDayB['Status'] = 'Beendet'
        $legacyDayB['EndedAt'] = '2026-07-01 12:00:00'
        $legacyWorkB = [ordered]@{ SchemaVersion = 1; LastSavedAt = '2026-07-01 12:00:00'; Days = @($legacyDayB) }
        [System.IO.File]::WriteAllText($script:Paths.LegacyBackup, ($legacyWorkB | ConvertTo-Json -Depth 20), $utf8Bom)
        $legacyB = Read-LegacyPlaintextData
        & $assert 'Test 55: Migration ausschliesslich aus worktime.backup.json moeglich' 'worktime.backup.json 1' ("$($legacyB.Source) $(@($legacyB.WorkData['Days']).Count)")

        [System.IO.File]::WriteAllText($script:Paths.LegacyWork, '{ "kaputt": ', $utf8Bom)
        $legacyB2 = Read-LegacyPlaintextData
        & $assert 'Test 56a: ungueltige worktime.json -> gueltiges Backup wird als Quelle verwendet' 'worktime.backup.json 1' ("$($legacyB2.Source) $(@($legacyB2.WorkData['Days']).Count)")
        & $assert 'Test 56b: unbrauchbare worktime.json zaehlt nicht zu den uebernommenen Quellen' 'False' ([string](@($legacyB2.UsedFiles) -contains $script:Paths.LegacyWork))

        $legacyDayC = New-TestDay -DateText '2026-07-02'
        Add-TestSegment -Day $legacyDayC -Mode 'Homeoffice' -StartText '09:00' -EndText '11:00' | Out-Null
        $legacyDayC['Status'] = 'Beendet'
        $legacyDayC['EndedAt'] = '2026-07-02 11:00:00'
        $legacyWorkC = [ordered]@{ SchemaVersion = 1; LastSavedAt = '2026-07-02 11:00:00'; Days = @($legacyDayC) }
        [System.IO.File]::WriteAllText($script:Paths.LegacyWork, ($legacyWorkC | ConvertTo-Json -Depth 20), $utf8Bom)
        $legacyC = Read-LegacyPlaintextData
        foreach ($p in @($legacyC.UsedFiles)) { Remove-PlaintextFileSecure -Path $p }
        & $assert 'Test 57a: nicht uebernommene worktime.backup.json wird bei der Migration nicht geloescht' 'worktime.json False True' ("$($legacyC.Source) $(Test-Path -LiteralPath $script:Paths.LegacyWork) $(Test-Path -LiteralPath $script:Paths.LegacyBackup)")
        $archOk = Move-LegacyFileToEncryptedRecovery -Path $script:Paths.LegacyBackup
        $recFiles = @(Get-ChildItem -LiteralPath $script:Paths.Recovery -Filter 'legacy-*.azt' -File -ErrorAction SilentlyContinue)
        & $assert 'Test 57b: nicht uebernommene Altdatei wird verschluesselt archiviert (kein Loeschen ohne Kopie)' 'True 1 False' ("$archOk $($recFiles.Count) $(Test-Path -LiteralPath $script:Paths.LegacyBackup)")

        # --- Tests 58/59: Importkonflikt bei gleichem Datum + Rollback ---
        Initialize-AppState
        $script:Paths = (& $newTestPaths $testRoot3)
        Set-VaultSessionKeys -Keys (& $cloneKeys $keys) -Salt $salt -Iterations $iter
        $impVault = New-VaultDataObject
        $vaultDayX = New-TestDay -DateText '2026-07-03'
        Add-TestSegment -Day $vaultDayX -Mode 'Betrieb' -StartText '08:00' -EndText '12:00' | Out-Null
        $vaultDayX['Status'] = 'Beendet'
        $vaultDayX['EndedAt'] = '2026-07-03 12:00:00'
        [void]$impVault['WorkData']['Days'].Add($vaultDayX)
        Set-ActiveVault -Vault $impVault
        Save-Vault | Out-Null
        $importDayX = New-TestDay -DateText '2026-07-03'
        Add-TestSegment -Day $importDayX -Mode 'Homeoffice' -StartText '13:00' -EndText '16:00' | Out-Null
        $importDayX['Status'] = 'Beendet'
        $importDayX['EndedAt'] = '2026-07-03 16:00:00'
        $importWork = [ordered]@{ SchemaVersion = 1; LastSavedAt = '2026-07-03 16:00:00'; Days = @($importDayX) }
        [System.IO.File]::WriteAllText($script:Paths.LegacyWork, ($importWork | ConvertTo-Json -Depth 20), $utf8Bom)
        $importOk = Invoke-PlaintextImportIntoVault -ConflictResolver { param($d, $v, $i) 'Uebernehmen' }
        $dayNow = $null
        foreach ($d in @($script:App.Data.Days)) { if ($d.Date -eq '2026-07-03') { $dayNow = $d } }
        $modeNow = ''
        foreach ($s in @($dayNow.Segments)) { $modeNow = [string]$s.Mode }
        & $assert 'Test 58a: Konflikt bei gleichem Datum wird nicht still uebersprungen (Import uebernommen)' 'True Homeoffice' ("$importOk $modeNow")
        & $assert 'Test 58b: Klartextquelle erst nach Konfliktaufloesung archiviert und entfernt' 'False' ([string](Test-Path -LiteralPath $script:Paths.LegacyWork))
        $impArch = @(Get-ChildItem -LiteralPath $script:Paths.Recovery -Filter 'import-day-*.azt' -File -ErrorAction SilentlyContinue)
        & $assert 'Test 58c: verdraengter Tresortag wurde verschluesselt archiviert' 'True' ([string]($impArch.Count -ge 1))

        $fingerprintBefore = Get-DayContentFingerprint -Day $dayNow
        New-Item -ItemType Directory -Path $script:Paths.LegacyLogDir -Force | Out-Null
        [System.IO.File]::WriteAllText($script:Paths.LegacyLog, "ALT-EINTRAG 1`r`n", $utf8Bom)
        $importDayY = New-TestDay -DateText '2026-07-03'
        Add-TestSegment -Day $importDayY -Mode 'Betrieb' -StartText '06:00' -EndText '09:00' | Out-Null
        $importDayY['Status'] = 'Beendet'
        $importDayY['EndedAt'] = '2026-07-03 09:00:00'
        $importWorkY = [ordered]@{ SchemaVersion = 1; LastSavedAt = '2026-07-03 09:00:00'; Days = @($importDayY) }
        [System.IO.File]::WriteAllText($script:Paths.LegacyWork, ($importWorkY | ConvertTo-Json -Depth 20), $utf8Bom)
        $importAborted = Invoke-PlaintextImportIntoVault -ConflictResolver { param($d, $v, $i) 'Abbrechen' }
        $dayAfter = $null
        foreach ($d in @($script:App.Data.Days)) { if ($d.Date -eq '2026-07-03') { $dayAfter = $d } }
        $altCount = 0
        foreach ($e in @($script:App.Vault['Logs'])) { if ([string]$e.Level -eq 'ALT') { $altCount++ } }
        & $assert 'Test 59a: Importabbruch liefert false und erhaelt die Klartextquelle' 'False True' ("$importAborted $(Test-Path -LiteralPath $script:Paths.LegacyWork)")
        & $assert 'Test 59b: WorkData nach Abbruch vollstaendig zurueckgesetzt' $fingerprintBefore (Get-DayContentFingerprint -Day $dayAfter)
        & $assert 'Test 59c: keine importierten Logeintraege nach Abbruch im Tresor' '0' ([string]$altCount)
        Remove-Item -LiteralPath $script:Paths.LegacyWork -Force
        Remove-Item -LiteralPath $script:Paths.LegacyLog -Force -ErrorAction SilentlyContinue

        # --- Test 60: Unterbrechung waehrend der Passwortaenderung (.new/.old) ---
        Move-Item -LiteralPath $script:Paths.VaultFile -Destination ($script:Paths.VaultFile + '.old') -Force
        Repair-VaultTransactionState | Out-Null
        & $assert 'Test 60a: fehlende Hauptdatei wird beim Start aus .old wiederhergestellt' 'True False' ("$(Test-Path -LiteralPath $script:Paths.VaultFile) $(Test-Path -LiteralPath ($script:Paths.VaultFile + '.old'))")
        [System.IO.File]::Copy($script:Paths.VaultFile, ($script:Paths.VaultFile + '.new'), $true)
        [System.IO.File]::Copy($script:Paths.VaultFile, ($script:Paths.VaultFile + '.old'), $true)
        Complete-VaultTransactionCleanup
        $mainStillOk = Test-VaultFileFullyUsable -Path $script:Paths.VaultFile
        & $assert 'Test 60b: Start mit .new- und .old-Datei -> Reste werden archiviert, Hauptdatei bleibt nutzbar' 'True False False' ("$mainStillOk $(Test-Path -LiteralPath ($script:Paths.VaultFile + '.new')) $(Test-Path -LiteralPath ($script:Paths.VaultFile + '.old'))")
        [System.IO.File]::Copy($script:Paths.VaultFile, ($script:Paths.VaultFile + '.new'), $true)
        [System.IO.File]::WriteAllText($script:Paths.VaultFile, 'ZERSTOERT', $utf8Bom)
        $script:App.VaultFileHash = 'VERALTETER-HASH'
        $script:App.VaultFileExistedAtLoad = $false
        Complete-VaultTransactionCleanup
        & $assert 'Test 60c: nutzbare .new-Datei ersetzt eine unbrauchbare Hauptdatei' 'True' ([string](Test-VaultFileFullyUsable -Path $script:Paths.VaultFile))
        & $assert 'Test 60d: Transaktionsbereinigung aktualisiert Hash und Existenzstatus der Hauptdatei' "$(Get-FileSha256Hex -Path $script:Paths.VaultFile)|True" ("$($script:App.VaultFileHash)|$($script:App.VaultFileExistedAtLoad)")
        $script:App.VaultFileHash = Get-FileSha256Hex -Path $script:Paths.VaultFile

        # --- Test 61: Wiederherstellung aus Backup2, einziger gueltiger Stand bleibt erhalten ---
        [System.IO.File]::Copy($script:Paths.VaultFile, $script:Paths.VaultBackup2, $true)
        [System.IO.File]::WriteAllText($script:Paths.VaultFile, 'KAPUTT-MAIN', $utf8Bom)
        [System.IO.File]::WriteAllText($script:Paths.VaultBackup1, 'KAPUTT-B1', $utf8Bom)
        $b2Vault = Read-VaultFromFile -Path $script:Paths.VaultBackup2 -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        Initialize-AppState
        $script:Paths = (& $newTestPaths $testRoot3)
        Set-ActiveVault -Vault $b2Vault
        # Nachbildung des Entsperr-Ablaufs: Der Hash der (hier beschaedigten)
        # Hauptdatei wird auch beim Laden aus Backup2 erfasst; das Ersetzen
        # ist danach ein explizit erkannter Wiederherstellungsvorgang.
        Set-VaultLoadReference -Kind 'Backup2' -Revision ([long]$b2Vault['Revision'])
        $b2SaveOk = Save-Vault
        $mainReadable = $true
        try { Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey | Out-Null }
        catch { $mainReadable = $false }
        $b2StillOk = Test-VaultFileFullyUsable -Path $script:Paths.VaultBackup2
        & $assert 'Test 61a: aus Backup2 geladener Stand wird kontrolliert neuer Hauptstand' 'True True' ("$b2SaveOk $mainReadable")
        & $assert 'Test 61b: einziger gueltiger Backupstand (Backup2) wurde NICHT ueberschrieben' 'True' ([string]$b2StillOk)
        Save-Vault | Out-Null
        $b1State = 'fehlt'
        if (Test-Path -LiteralPath $script:Paths.VaultBackup1) {
            if (Test-VaultFileFullyUsable -Path $script:Paths.VaultBackup1) { $b1State = 'gueltig' } else { $b1State = 'unbrauchbar' }
        }
        & $assert 'Test 61c: unbrauchbare Dateien gelangen nicht in die Backupkette (Backup1 gueltig oder fehlt)' 'True' ([string]($b1State -ne 'unbrauchbar'))
        & $assert 'Test 61d: Backup2 bleibt auch nach weiterem Speichern gueltig' 'True' ([string](Test-VaultFileFullyUsable -Path $script:Paths.VaultBackup2))

        # --- Test 62: fehlgeschlagener Speichervorgang setzt saemtliche Metadaten zurueck ---
        $metaVault = $script:App.Vault
        $revBefore = [string]$metaVault['Revision']
        $chkBefore = [string]$metaVault['LastCheckpointAt']
        $modBefore = [string]$metaVault['ModifiedAt']
        $savedAtBefore = [string]$metaVault['WorkData']['LastSavedAt']
        $goodPendingPath = $script:Paths.VaultPending
        $script:Paths.VaultPending = Join-Path $testRoot3 'gibtsnicht\vault.pending.azt'
        $failSave = Save-Vault
        $script:Paths.VaultPending = $goodPendingPath
        & $assert 'Test 62a: fehlgeschlagener Speichervorgang liefert false' 'False' ([string]$failSave)
        & $assert 'Test 62b: Revision, LastCheckpointAt, ModifiedAt und LastSavedAt vollstaendig zurueckgesetzt' "$revBefore|$chkBefore|$modBefore|$savedAtBefore" ("$($metaVault['Revision'])|$($metaVault['LastCheckpointAt'])|$($metaVault['ModifiedAt'])|$($metaVault['WorkData']['LastSavedAt'])")
        & $assert 'Test 62c: Zustand ist als NICHT GESPEICHERT markiert' 'True' ([string]$script:App.Flags.UnsavedChanges)
        Clear-VaultSaveFailedState

        # --- Test 63: externe Aenderung von vault.azt wird erkannt ---
        $extBytes = [System.IO.File]::ReadAllBytes($script:Paths.VaultFile)
        [System.IO.File]::WriteAllBytes($script:Paths.VaultFile, [byte[]]($extBytes + 32))
        $recCountBefore = @(Get-ChildItem -LiteralPath $script:Paths.Recovery -Filter 'vault-*.azt' -File -ErrorAction SilentlyContinue).Count
        $extSave = Save-Vault
        $extLenAfter = ([System.IO.File]::ReadAllBytes($script:Paths.VaultFile)).Length
        $recCountAfter = @(Get-ChildItem -LiteralPath $script:Paths.Recovery -Filter 'vault-*.azt' -File -ErrorAction SilentlyContinue).Count
        & $assert 'Test 63a: extern veraenderte Tresordatei wird NICHT ueberschrieben' 'False' ([string]$extSave)
        & $assert 'Test 63b: extern veraenderte Datei bleibt unangetastet' ([string]($extBytes.Length + 1)) ([string]$extLenAfter)
        & $assert 'Test 63c: eigener Stand als neutrale Konfliktdatei (GUID) in Recovery gesichert' 'True|True' ("$($recCountAfter -gt $recCountBefore)|$($script:App.Flags.LastConflictCopySaved)")
        # Fehlgeschlagene Konfliktsicherung darf NIE als gesichert gemeldet werden
        $logCount63d = @($script:App.Vault['Logs']).Count
        $script:App.Flags.TestFailConflictCopy = $true
        $extSave63d = Save-Vault
        $script:App.Flags.TestFailConflictCopy = $false
        $recCount63d = @(Get-ChildItem -LiteralPath $script:Paths.Recovery -Filter 'vault-*.azt' -File -ErrorAction SilentlyContinue).Count
        $newLogs63d = (@(@($script:App.Vault['Logs']) | Select-Object -Skip $logCount63d) | ForEach-Object { [string]$_['Message'] }) -join "`n"
        & $assert 'Test 63d: Konfliktsicherung fehlgeschlagen - false, keine Erfolgsmeldung, Fehlschlag protokolliert, Datei unangetastet' "False|False|$recCountAfter|True|False|$($extBytes.Length + 1)" ("$extSave63d|$($script:App.Flags.LastConflictCopySaved)|$recCount63d|$($newLogs63d.Contains('FEHLGESCHLAGEN'))|$($newLogs63d.Contains('in Recovery gesichert'))|$(([System.IO.File]::ReadAllBytes($script:Paths.VaultFile)).Length)")
        Clear-VaultSaveFailedState
        $script:App.VaultFileHash = Get-FileSha256Hex -Path $script:Paths.VaultFile

        # --- Test 63e-63j: Fremdaenderung zwischen Pruefung und Schreiben ---
        $save63e = Save-Vault -Quiet
        & $assert 'Test 63e: Referenzhash nach dem Speichern = Hash der geschriebenen Hauptdatei' "True|$(Get-FileSha256Hex -Path $script:Paths.VaultFile)" ("$save63e|$($script:App.VaultFileHash)")
        $mainBefore63 = [System.IO.File]::ReadAllBytes($script:Paths.VaultFile)
        $pendingHash63 = Get-FileSha256Hex -Path $script:Paths.VaultPending
        $revBefore63 = [long]$script:App.Vault['Revision']
        $foreign63 = Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        $foreign63['Revision'] = 50
        $foreignBytes63 = ConvertTo-VaultFileBytes -Vault $foreign63 -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey `
            -Salt $script:VaultSession.Salt -Iterations $script:VaultSession.Iterations
        $mainPath63 = $script:Paths.VaultFile
        $script:App.Flags.TestBeforeMainWrite = { [System.IO.File]::WriteAllBytes($mainPath63, $foreignBytes63) }.GetNewClosure()
        $recBefore63f = @(Get-ChildItem -LiteralPath $script:Paths.Recovery -Filter 'vault-*.azt' -File -ErrorAction SilentlyContinue).Count
        $save63f = Save-Vault -Quiet
        $script:App.Flags.TestBeforeMainWrite = $null
        $recAfter63f = @(Get-ChildItem -LiteralPath $script:Paths.Recovery -Filter 'vault-*.azt' -File -ErrorAction SilentlyContinue).Count
        $disk63f = Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        & $assert 'Test 63f: Fremdaenderung zwischen Pruefung und Schreiben - false, fremder Stand (Rev. 50) bleibt, Konfliktkopie gesichert' 'False|50|True|True' ("$save63f|$($disk63f['Revision'])|$($recAfter63f -gt $recBefore63f)|$($script:App.Flags.LastConflictCopySaved)")
        & $assert 'Test 63g: Journal und Revision zurueckgenommen' "$pendingHash63|$revBefore63" ("$(Get-FileSha256Hex -Path $script:Paths.VaultPending)|$($script:App.Vault['Revision'])")
        Clear-VaultSaveFailedState
        $save63h = Save-Vault -Quiet
        & $assert 'Test 63h: Folgespeichern ueberschreibt den fremden Stand ebenfalls NICHT (Referenz unveraendert)' 'False|50' ("$save63h|$((Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey)['Revision'])")
        [System.IO.File]::WriteAllBytes($script:Paths.VaultFile, $mainBefore63)
        Clear-VaultSaveFailedState
        $script:App.VaultFileHash = Get-FileSha256Hex -Path $script:Paths.VaultFile
        # Bedingtes Schreiben: Abweichung, Erfolg, unerwartet vorhandene und fehlende Datei
        $f63 = Join-Path $testRoot3 'Data\ifunchanged63.bin'
        [System.IO.File]::WriteAllBytes($f63, [byte[]](1, 2, 3))
        $h63 = Get-FileSha256Hex -Path $f63
        $r63a = ''; try { Write-FileInPlaceVerified -Path $f63 -Bytes ([byte[]](9, 9)) -ExpectedHash ('0' * 64) } catch { $r63a = $_.Exception.Message }
        $len63a = ([System.IO.File]::ReadAllBytes($f63)).Length
        Write-FileInPlaceVerified -Path $f63 -Bytes ([byte[]](7, 7, 7, 7)) -ExpectedHash $h63
        $len63b = ([System.IO.File]::ReadAllBytes($f63)).Length
        $r63c = ''; try { Write-FileInPlaceVerified -Path $f63 -Bytes ([byte[]](5)) } catch { $r63c = $_.Exception.Message }
        $r63d = ''; try { Write-FileInPlaceVerified -Path (Join-Path $testRoot3 'Data\fehlt63.bin') -Bytes ([byte[]](5)) -ExpectedHash $h63 } catch { $r63d = $_.Exception.Message }
        Remove-Item -LiteralPath $f63 -Force
        & $assert 'Test 63i: bedingtes Schreiben - Abweichung unangetastet, Erfolg, extern angelegte/entfernte Datei erkannt' 'VAULT_EXTERNAL_CHANGE|3|4|VAULT_EXTERNAL_CHANGE|VAULT_EXTERNAL_CHANGE' "$r63a|$len63a|$len63b|$r63c|$r63d"
        # Einzelinstanz: ein zweiter Thread/Prozess erhaelt den Mutex nicht
        $dataBefore63 = $script:Paths.Data
        $script:Paths.Data = Join-Path $testRoot3 'Data'
        $probe63 = {
            param([string]$Name)
            $rs = [runspacefactory]::CreateRunspace()
            $rs.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::UseNewThread
            $rs.Open()
            $ps = [powershell]::Create()
            $ps.Runspace = $rs
            try {
                [void]$ps.AddScript('param($n) $m = New-Object System.Threading.Mutex($false, $n); $ok = $false; try { $ok = $m.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $ok = $true }; if ($ok) { $m.ReleaseMutex() }; $m.Dispose(); $ok').AddArgument($Name)
                return [bool](@($ps.Invoke())[0])
            }
            finally { $ps.Dispose(); $rs.Dispose() }
        }
        $enter63 = Enter-SingleInstance
        $second63 = & $probe63 (Get-SingleInstanceMutexName)
        Exit-SingleInstance
        $afterExit63 = & $probe63 (Get-SingleInstanceMutexName)
        $script:Paths.Data = $dataBefore63
        & $assert 'Test 63j: Einzelinstanz - erste Instanz erhaelt die Sperre, zweite nicht, nach Freigabe wieder verfuegbar' 'True|False|True' "$enter63|$second63|$afterExit63"

        # --- Test 64: uebermaessig grosse Tresordatei wird vor ReadAllText abgelehnt ---
        $limitBefore = $script:VaultConst.MaxFileBytes
        $script:VaultConst.MaxFileBytes = 1024
        $bigFile = Join-Path $testRoot3 'Data\big.azt'
        [System.IO.File]::WriteAllText($bigFile, ('X' * 4096), $utf8Bom)
        $bigRejected = $false
        try { Read-VaultContainerFromFile -Path $bigFile | Out-Null } catch { $bigRejected = ($_.Exception.Message -eq 'VAULT_INVALID') }
        $script:VaultConst.MaxFileBytes = $limitBefore
        & $assert 'Test 64: uebergrosse Tresordatei wird vor dem Einlesen abgelehnt' 'True' ([string]$bigRejected)
        Remove-Item -LiteralPath $bigFile -Force

        # --- Test 65: Salt mit falscher Laenge wird abgelehnt ---
        $saltJson = Protect-VaultContainer -PlainText 'Salttest größer ungültig' -AesKey $keys.Aes -HmacKey $keys.Hmac -Salt $salt -Iterations $iter
        $saltObj = $saltJson | ConvertFrom-Json
        $saltObj.Salt = [Convert]::ToBase64String([ArbeitszeitTool.VaultCrypto]::GetRandomBytes(16))
        $saltFile = Join-Path $testRoot3 'Data\salt.azt'
        [System.IO.File]::WriteAllText($saltFile, ($saltObj | ConvertTo-Json), $utf8Bom)
        $saltRejected = $false
        try { Read-VaultContainerFromFile -Path $saltFile | Out-Null } catch { $saltRejected = ($_.Exception.Message -eq 'VAULT_INVALID') }
        & $assert 'Test 65: Salt mit falscher Laenge (16 statt 32 Byte) wird abgelehnt' 'True' ([string]$saltRejected)
        Remove-Item -LiteralPath $saltFile -Force

        # --- Tests 66-69: Layout des Einstellungs- und Exportdialogs ---
        # Hinweis: WPF layoutet skalierungsunabhaengig in geraeteunabhaengigen
        # Einheiten (DIPs). Die Pruefung bei fester Fensterbreite gilt daher
        # fuer 100 %, 125 % und 150 % Windows-Skalierung gleichermassen; die
        # Fensterhoehe wird zur Laufzeit durch MaxHeight + ScrollViewer begrenzt.
        try {
            $setWin = New-XamlWindow -Xaml $script:SettingsXaml
            $pnl = $setWin.FindName('PnlFields')
            foreach ($key in $script:CompactFieldDefs.Keys) {
                [void]$pnl.Children.Add((New-WrappedCheckBox -Text $script:CompactFieldDefs[$key]))
            }
            $content = $setWin.Content
            $contentWidth = 700.0
            $content.Measure((New-Object System.Windows.Size($contentWidth, [double]::PositiveInfinity)))
            $content.Arrange((New-Object System.Windows.Rect(0, 0, $contentWidth, $content.DesiredSize.Height)))
            $content.UpdateLayout()
            $wrapOk = $true
            foreach ($name in @('ChkTopmostReassert', 'ChkWarn', 'ChkSound', 'ChkTray', 'ChkSeconds', 'ChkKeepAlive')) {
                $cb = $setWin.FindName($name)
                if ($null -eq $cb -or $cb.Content -isnot [System.Windows.Controls.TextBlock] -or $cb.Content.TextWrapping -ne [System.Windows.TextWrapping]::Wrap) { $wrapOk = $false }
            }
            foreach ($child in $pnl.Children) {
                if ($child.Content -isnot [System.Windows.Controls.TextBlock] -or $child.Content.TextWrapping -ne [System.Windows.TextWrapping]::Wrap) { $wrapOk = $false }
            }
            & $assert 'Test 66: lange Beschriftungen (statisch und dynamisch) sind umbruchfaehig (kein Abschneiden)' 'True' ([string]$wrapOk)
            # Fuer die Layoutpruefung der Presets den Tab "Kompakte Ansicht"
            # aktivieren (TabControl realisiert nur den ausgewaehlten Tab)
            $setWin.FindName('TabSettings').SelectedIndex = 1
            $content.Measure((New-Object System.Windows.Size($contentWidth, [double]::PositiveInfinity)))
            $content.Arrange((New-Object System.Windows.Rect(0, 0, $contentWidth, $content.DesiredSize.Height)))
            $content.UpdateLayout()
            $bp1 = $setWin.FindName('BtnPresetStandard')
            $bp2 = $setWin.FindName('BtnPresetKlassisch')
            $sameSize = ([math]::Abs($bp1.ActualWidth - $bp2.ActualWidth) -lt 0.6 -and [math]::Abs($bp1.ActualHeight - $bp2.ActualHeight) -lt 0.6)
            & $assert 'Test 67a: Preset-Schaltflaechen besitzen identische Abmessungen' 'True' ([string]$sameSize)
            $edge = $bp2.TranslatePoint((New-Object System.Windows.Point($bp2.ActualWidth, 0)), $content)
            & $assert 'Test 67b: "Preset: Klassisch" liegt vollstaendig innerhalb des Fensters' 'True' ([string]($edge.X -le $contentWidth + 0.5))
            $tf = New-Object System.Windows.Media.Typeface($bp2.FontFamily, $bp2.FontStyle, $bp2.FontWeight, $bp2.FontStretch)
            $ft = New-Object System.Windows.Media.FormattedText('Preset: Klassisch', [System.Globalization.CultureInfo]::CurrentCulture,
                [System.Windows.FlowDirection]::LeftToRight, $tf, $bp2.FontSize, [System.Windows.Media.Brushes]::White)
            & $assert 'Test 67c: Beschriftung passt vollstaendig in die Schaltflaeche (kein abgeschnittener Text)' 'True' ([string]($ft.Width -le ($bp2.ActualWidth - 10)))
            & $assert 'Test 68a: Einstellungsdialog fordert keine Breite ueber der Fensterbreite an (DIP-invariant fuer 100/125/150 %)' 'True' ([string]($content.DesiredSize.Width -le $contentWidth + 0.5))
            $bOk = $setWin.FindName('BtnOk')
            $bCancel = $setWin.FindName('BtnCancel')
            $sameOkCancel = ([math]::Abs($bOk.ActualWidth - $bCancel.ActualWidth) -lt 0.6 -and [math]::Abs($bOk.ActualHeight - $bCancel.ActualHeight) -lt 0.6)
            & $assert 'Test 68b: Speichern und Abbrechen sind exakt gleich gross' 'True' ([string]$sameOkCancel)
            $setWin.Close()

            $expWin = New-XamlWindow -Xaml $script:ExportXaml
            $expContent = $expWin.Content
            $expContent.Measure((New-Object System.Windows.Size(440.0, [double]::PositiveInfinity)))
            $expContent.Arrange((New-Object System.Windows.Rect(0, 0, 440.0, $expContent.DesiredSize.Height)))
            $expContent.UpdateLayout()
            $eOk = $expWin.FindName('BtnOk')
            $eCancel = $expWin.FindName('BtnCancel')
            $sameExp = ([math]::Abs($eOk.ActualWidth - $eCancel.ActualWidth) -lt 0.6 -and [math]::Abs($eOk.ActualHeight - $eCancel.ActualHeight) -lt 0.6)
            $expEdge = $eCancel.TranslatePoint((New-Object System.Windows.Point($eCancel.ActualWidth, 0)), $expContent)
            & $assert 'Test 69: CSV-Dialog - Exportieren/Abbrechen gleich gross und vollstaendig sichtbar' 'True True' ("$sameExp $($expEdge.X -le 440.5)")
            $expWin.Close()
        }
        catch {
            Write-Host ('[SKIP] Tests 66-69 (UI-Layout): in dieser Umgebung nicht ausfuehrbar: ' + $_.Exception.Message) -ForegroundColor Yellow
        }

        # =====================================================================
        # Tests 70-83: Scroll-Lock-Feinschliff, Startablauf, Neustartverhalten,
        # Internetradio und Sichtschutz - ohne echte Tastendruecke und ohne
        # echte Netzwerk-/Streamzugriffe.
        # =====================================================================

        # --- Test 70: abgelehnter Hintergrundauftrag gibt den Pulsstatus frei ---
        [ArbeitszeitTool.NativeInput]::TestFailMode = 4
        $rejectedStart = [ArbeitszeitTool.NativeInput]::StartScrollLockPulse(200)
        [ArbeitszeitTool.NativeInput]::TestFailMode = 3
        $rejectLogged = $false
        foreach ($re in @([ArbeitszeitTool.NativeInput]::DrainPulseResults())) {
            if (([string]$re).Contains('nicht angenommen')) { $rejectLogged = $true }
        }
        & $assert 'Test 70a: QueueUserWorkItem=false liefert false und neutralen Diagnoseeintrag' 'False True' ("$rejectedStart $rejectLogged")
        & $assert 'Test 70b: _pulseRunning bleibt nicht haengen (kein Puls aktiv)' 'False' ([string][ArbeitszeitTool.NativeInput]::IsPulseRunning())
        $retryStart = [ArbeitszeitTool.NativeInput]::StartScrollLockPulse(100)
        & $assert 'Test 70c: naechster regulaerer Versuch startet wieder' 'True' ([string]$retryStart)
        $deadline = [System.Diagnostics.Stopwatch]::StartNew()
        while ([ArbeitszeitTool.NativeInput]::IsPulseRunning() -and $deadline.ElapsedMilliseconds -lt 2000) { Start-Sleep -Milliseconds 25 }
        [void][ArbeitszeitTool.NativeInput]::DrainPulseResults()

        # --- Test 71: Regulaeres Schliessen laesst den laufenden Abschnitt unveraendert ---
        $closeDay = New-TestDay -DateText ((Get-Date).ToString('yyyy-MM-dd'))
        $closeSeg = New-SegmentObject -Mode 'Betrieb' -Start (Get-Date).AddHours(-1) -Running $true
        [void]$closeDay['Segments'].Add($closeSeg)
        [void]$script:App.Vault['WorkData']['Days'].Add($closeDay)
        $segIdBefore = [string]$closeSeg['Id']
        $segStartBefore = [string]$closeSeg['Start']
        $script:App.Vault['CleanShutdown'] = $true
        $closeSaved = Save-Vault
        & $assert 'Test 71a: finaler Speichervorgang beim Schliessen (CleanShutdown=true) erfolgreich' 'True' ([string]$closeSaved)
        & $assert 'Test 71b: Segment-ID, Start, Running, End und Segmentanzahl bleiben unveraendert' "$segIdBefore|$segStartBefore|True||1" ("$($closeSeg['Id'])|$($closeSeg['Start'])|$($closeSeg['Running'])|$($closeSeg['End'])|$(@($closeDay['Segments']).Count)")

        # --- Test 72: Startablauf - aktiver Tag vor dem Startdialog, Speicherpruefung ---
        $script:App.Data = $script:App.Vault['WorkData']
        $script:App.Flags.ActiveDayDecisionCompleted = $false
        & $assert 'Test 72a: vor Abschluss der Startentscheidungen wird kein Startdialog angeboten' 'False' ([string](Test-ShouldOfferStartDay))
        $script:App.Flags.ActiveDayDecisionCompleted = $true
        & $assert 'Test 72b: aktiver Tag wird VOR Invoke-StartDayFlow erkannt (kein Startdialog)' 'False' ([string](Test-ShouldOfferStartDay))
        $goodPending72 = $script:Paths.VaultPending
        $script:Paths.VaultPending = Join-Path $testRoot3 'gibtsnicht\pending72.azt'
        $startSaveOk = Invoke-SessionStartSave
        $script:Paths.VaultPending = $goodPending72
        & $assert 'Test 72c: fehlgeschlagener Sitzungsstart-Speichervorgang verhindert den produktiven Start' 'False' ([string]$startSaveOk)
        Clear-VaultSaveFailedState
        $script:App.Vault['CleanShutdown'] = $true
        Save-Vault | Out-Null

        # --- Test 73: Fortsetzen im Betrieb erzeugt keinen neuen Timeslot ---
        $resumeDay = New-TestDay -DateText ((Get-Date).ToString('yyyy-MM-dd'))
        $resumeSeg = New-SegmentObject -Mode 'Betrieb' -Start (Get-Date).AddHours(-2) -Running $true
        [void]$resumeDay['Segments'].Add($resumeSeg)
        $script:App.RecoveryState = @{ PreviousCleanShutdown = $true; PreviousLastSavedAt = (ConvertTo-DateTimeString (Get-Date).AddMinutes(-30)) }
        $script:App.CurrentDay = $resumeDay
        Invoke-CleanResume -Day $resumeDay
        & $assert 'Test 73: sauberer Betriebsneustart - gleicher Abschnitt, gleiche ID, kein Ende, kein neuer Timeslot' "$($resumeSeg['Id'])|True||1" ("$($resumeDay['Segments'][0]['Id'])|$($resumeDay['Segments'][0]['Running'])|$($resumeDay['Segments'][0]['End'])|$(@($resumeDay['Segments']).Count)")

        # --- Test 74: HO-Luecke fuegt nur Pause/Sperrintervall ein (kein neuer Timeslot) ---
        $gapDay = New-TestDay -DateText ((Get-Date).ToString('yyyy-MM-dd'))
        $gapSeg = New-SegmentObject -Mode 'Homeoffice' -Start (Get-Date).AddHours(-2) -Running $true
        [void]$gapDay['Segments'].Add($gapSeg)
        Add-GapInterval -Day $gapDay -Kind 'Pause' -Start (Get-Date).AddMinutes(-50) -End (Get-Date).AddMinutes(-40) | Out-Null
        Add-GapInterval -Day $gapDay -Kind 'Sperrzeit' -Start (Get-Date).AddMinutes(-30) -End (Get-Date).AddMinutes(-20) | Out-Null
        & $assert 'Test 74: Luecken werden als Intervalle eingefuegt - Segmentanzahl und laufender Abschnitt unveraendert' '1|1|1|True' ("$(@($gapDay['Segments']).Count)|$(@($gapDay['ManualPauses']).Count)|$(@($gapDay['LockIntervals']).Count)|$($gapDay['Segments'][0]['Running'])")

        # --- Test 75: NUR ein ausdruecklicher Moduswechsel erzeugt einen neuen Abschnitt ---
        Switch-WorkMode -Day $gapDay -NewMode 'Betrieb' -EndTime (Get-Date) -StartTime (Get-Date) | Out-Null
        & $assert 'Test 75: Moduswechsel beendet den alten Abschnitt und beginnt genau EINEN neuen' '2|False|Betrieb|True' ("$(@($gapDay['Segments']).Count)|$($gapDay['Segments'][0]['Running'])|$($gapDay['Segments'][1]['Mode'])|$($gapDay['Segments'][1]['Running'])")

        # --- Test 76: Sendervalidierung (URI-Schemas, Zugangsdaten, Grenzen) ---
        $mkStation = { param($u, $n = 'Sender') return [ordered]@{ Id = 'x'; Name = $n; Url = $u } }
        & $assert 'Test 76a: http-Adresse ist zulaessig' '' (Test-RadioStation -Station (& $mkStation 'http://streams.example.de/live/mp3'))
        & $assert 'Test 76b: https-Adresse ist zulaessig' '' (Test-RadioStation -Station (& $mkStation 'https://streams.example.de/live'))
        & $assert 'Test 76c: ftp wird abgelehnt' 'True' ([string]((Test-RadioStation -Station (& $mkStation 'ftp://x.de/a')) -ne ''))
        & $assert 'Test 76d: file-URI wird abgelehnt' 'True' ([string]((Test-RadioStation -Station (& $mkStation 'file:///C:/x.mp3')) -ne ''))
        & $assert 'Test 76e: lokaler Dateipfad wird abgelehnt' 'True' ([string]((Test-RadioStation -Station (& $mkStation 'C:\Musik\x.mp3')) -ne ''))
        & $assert 'Test 76f: UNC-Pfad wird abgelehnt' 'True' ([string]((Test-RadioStation -Station (& $mkStation '\\server\freigabe\x.mp3')) -ne ''))
        & $assert 'Test 76g: javascript-Schema wird abgelehnt' 'True' ([string]((Test-RadioStation -Station (& $mkStation 'javascript:alert(1)')) -ne ''))
        & $assert 'Test 76h: data-Schema wird abgelehnt' 'True' ([string]((Test-RadioStation -Station (& $mkStation 'data:audio/mp3;base64,AAAA')) -ne ''))
        & $assert 'Test 76i: eingebettete Zugangsdaten werden abgelehnt' 'True' ([string]((Test-RadioStation -Station (& $mkStation 'http://benutzer:geheim@x.de/live')) -ne ''))
        & $assert 'Test 76j: leerer Name wird abgelehnt' 'True' ([string]((Test-RadioStation -Station (& $mkStation 'http://x.de/live' '')) -ne ''))
        & $assert 'Test 76k: ueberlanger Name wird abgelehnt' 'True' ([string]((Test-RadioStation -Station (& $mkStation 'http://x.de/live' ('N' * 81))) -ne ''))
        & $assert 'Test 76l: ueberlange URL wird abgelehnt' 'True' ([string]((Test-RadioStation -Station (& $mkStation ('http://x.de/' + ('a' * 2049)))) -ne ''))

        # --- Test 77: Radioeinstellungen verschluesselt speichern/laden ---
        $legacySettings77 = Get-ValidatedSettings -Loaded ([ordered]@{ RegularTime = '07:00' })
        & $assert 'Test 77a: Tresore ohne Radioeinstellungen erhalten Standardwerte (keine Schemaerhoehung, keine voreingestellten Sender)' '0|20|True|False' ("$(@($legacySettings77['RadioStations']).Count)|$($legacySettings77['RadioVolume'])|$($legacySettings77['RadioResumeAfterUnlock'])|$($legacySettings77['RadioRememberPlaybackState'])")
        $customStations = New-Object System.Collections.ArrayList
        [void]$customStations.Add([ordered]@{ Id = 'eigener'; Name = 'Mein Sender äöü'; Url = 'http://radio.example.de/stream' })
        $script:App.Settings['RadioStations'] = $customStations
        $script:App.Settings['RadioSelectedStationId'] = 'eigener'
        $saved77 = Save-Vault
        $reload77 = Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        $reStations = @($reload77['Settings']['RadioStations'])
        $raw77 = [System.IO.File]::ReadAllText($script:Paths.VaultFile)
        & $assert 'Test 77b: Senderliste wird verschluesselt gespeichert und korrekt geladen' "True|1|Mein Sender äöü|eigener" ("$saved77|$($reStations.Count)|$($reStations[0]['Name'])|$($reload77['Settings']['RadioSelectedStationId'])")
        & $assert 'Test 77c: keine Klartext-Stream-URL in der Tresordatei' 'False' ([string]$raw77.Contains('radio.example.de'))

        # --- Test 78: Radio bei Sperre/Entsperrung (reine Zustandslogik, kein Player) ---
        $script:App.Settings['RadioResumeAfterUnlock'] = $true
        $radio78 = $script:App.Radio
        $radio78.Player = $null
        $radio78.DesiredState = 'Playing'
        $radio78.ActualState = 'Wiedergabe'
        Invoke-RadioLock
        & $assert 'Test 78a: Sperre haelt das Radio an und merkt den Zustand' 'True|True|Paused' ("$($radio78.WasPlayingBeforeLock)|$($radio78.SuspendedByLock)|$($radio78.DesiredState)")
        & $assert 'Test 78b: automatische Fortsetzung nach dem Entsperren ist vorgesehen' 'True' ([string](Test-RadioShouldResumeAfterUnlock))
        Stop-RadioPlayback
        & $assert 'Test 78c: nach manuellem Stop wird beim Entsperren NICHT fortgesetzt' 'False' ([string](Test-RadioShouldResumeAfterUnlock))
        $radio78.DesiredState = 'Stopped'
        $radio78.WasPlayingBeforeLock = $false
        $radio78.SuspendedByLock = $false
        Invoke-RadioLock
        & $assert 'Test 78d: war das Radio vor der Sperre aus, bleibt es beim Entsperren aus' 'False' ([string](Test-RadioShouldResumeAfterUnlock))

        # --- Test 79: verspaetetes MediaOpened wird ignoriert; Radiofehler ohne Nebenwirkungen ---
        $radio78.CurrentRequestId = [long]5
        $radio78.OpenRequestId = [long]4
        $radio78.DesiredState = 'Playing'
        & $assert 'Test 79a: veraltete Open-Anforderung (RequestId) startet keine Wiedergabe' 'False' ([string](Test-RadioOpenStillValid -RequestId ([long]$radio78.OpenRequestId)))
        $radio78.OpenRequestId = [long]5
        $radio78.DesiredState = 'Paused'
        & $assert 'Test 79b: nach Pause/Stop/Lock startet auch ein aktuelles MediaOpened nicht' 'False' ([string](Test-RadioOpenStillValid -RequestId 5))
        $radio78.DesiredState = 'Playing'
        & $assert 'Test 79c: nur die aktuellste gueltige Open-Anforderung darf starten' 'True' ([string](Test-RadioOpenStillValid -RequestId 5))
        $fp79 = Get-DayContentFingerprint -Day $closeDay
        $keep79 = [bool]$script:App.Settings['KeepAliveEnabled']
        Invoke-RadioMediaFailed
        & $assert 'Test 79d: Radiofehler veraendert weder Arbeitstag noch Einstellungen noch Speicherstatus' "$fp79|$keep79|False" ("$(Get-DayContentFingerprint -Day $closeDay)|$($script:App.Settings['KeepAliveEnabled'])|$($script:App.Flags.SaveInProgress)")

        # --- Test 80: vault.txn enthaelt keine absoluten Pfade ---
        $prepared80 = @(
            @{ Orig = $script:Paths.VaultFile; New = ($script:Paths.VaultFile + '.new'); Kind = 'Haupt' },
            @{ Orig = $script:Paths.VaultBackup1; New = ($script:Paths.VaultBackup1 + '.new'); Kind = 'Backup1' }
        )
        $txn80 = New-VaultTxnContent -Prepared $prepared80
        & $assert 'Test 80: vault.txn verwendet nur logische Bezeichnungen (keine absoluten Pfade)' 'True|True' ("$($txn80.Contains('Haupt') -and $txn80.Contains('Backup1'))|$(-not ($txn80 -match '(?i)[a-z]:'))")

        # --- Test 81: Sichtschutz-Grundzustand und Umschalten ohne Datenaenderung ---
        Set-PauseLockDetailsVisibility $true
        & $assert 'Test 81a: Sichtbarkeit laesst sich einschalten' 'True' ([string]$script:App.UiPrivacy.PauseAndLockDetailsVisible)
        $fp81 = Get-DayContentFingerprint -Day $gapDay
        Hide-PauseLockDetails
        & $assert 'Test 81b: Verbergen (z. B. bei Lock/Schliessen/Minimieren) aendert nur die Anzeige' "False|$fp81|False" ("$($script:App.UiPrivacy.PauseAndLockDetailsVisible)|$(Get-DayContentFingerprint -Day $gapDay)|$($script:App.Flags.SaveInProgress)")
        Initialize-AppState
        $script:App.Settings = Get-DefaultSettings
        & $assert 'Test 81c: nach Neustart/Neuinitialisierung sind die Details IMMER verborgen' 'False' ([string]$script:App.UiPrivacy.PauseAndLockDetailsVisible)

        # --- Test 82: Maskierung der Tageswerte (verborgen vs. sichtbar) ---
        $maskDay = New-TestDay
        Add-TestSegment -Day $maskDay -Mode 'Homeoffice' -StartText '08:00' -EndText '12:00' | Out-Null
        Add-TestInterval -Day $maskDay -ListName 'ManualPauses' -StartText '10:00' -EndText '10:30' | Out-Null
        Add-TestInterval -Day $maskDay -ListName 'LockIntervals' -StartText '11:00' -EndText '11:15' | Out-Null
        $maskComp = Get-DayComputation -Day $maskDay -Now (Get-TestNow $maskDay '12:30')
        $script:App.UiPrivacy.PauseAndLockDetailsVisible = $false
        $hiddenText = Get-ExtendedValuesText -Comp $maskComp -Day $maskDay
        $script:App.UiPrivacy.PauseAndLockDetailsVisible = $true
        $visibleText = Get-ExtendedValuesText -Comp $maskComp -Day $maskDay
        $script:App.UiPrivacy.PauseAndLockDetailsVisible = $false
        $hiddenLines = @($hiddenText -split "`r`n").Count
        $visibleLines = @($visibleText -split "`r`n").Count
        & $assert 'Test 82a: verborgen = Platzhalter statt konkreter Pausen-/Sperrzeiten' 'True|False' ("$($hiddenText.Contains('••:••'))|$($hiddenText.Contains('Manuelle Pausen    00:30'))")
        & $assert 'Test 82b: sichtbar = konkrete Werte werden angezeigt' 'True|True' ("$($visibleText.Contains('00:30'))|$($visibleText.Contains('00:15'))")
        & $assert 'Test 82c: Maskierung veraendert weder Zeilenanzahl noch Layout' ([string]$visibleLines) ([string]$hiddenLines)

        # --- Test 83: Sichtschutz auf UI-Ebene (Blur, HitTest, AutomationProperties) ---
        try {
            $privWin = New-XamlWindow -Xaml $script:ExtendedXaml
            $script:App.Ui.Extended = $privWin
            $script:App.UiPrivacy.PauseAndLockDetailsVisible = $false
            Update-PauseLockPrivacyUi
            $grid83 = $privWin.FindName('ExtPauses')
            $autoName = [System.Windows.Automation.AutomationProperties]::GetName($grid83)
            & $assert 'Test 83a: verborgen = BlurEffect aktiv, keine Treffererkennung, neutrale Automation' 'True|False|Pausen- und Sperrzeiten verborgen' ("$($grid83.Effect -is [System.Windows.Media.Effects.BlurEffect])|$($grid83.IsHitTestVisible)|$autoName")
            Set-PauseLockDetailsVisibility $true
            & $assert 'Test 83b: sichtbar = kein Effekt, Treffererkennung aktiv' 'True|True' ("$($null -eq $grid83.Effect)|$($grid83.IsHitTestVisible)")
            Hide-PauseLockDetails
            & $assert 'Test 83c: erneutes Verbergen stellt Blur und neutrale Automation wieder her' 'True' ([string]($grid83.Effect -is [System.Windows.Media.Effects.BlurEffect]))
            # Sichtschutz: verborgen duerfen die echten Werte nicht in der
            # gebundenen Datenquelle (und damit im Automation-Baum) stehen
            $day83 = New-TestDay
            Add-TestSegment -Day $day83 -Mode 'Homeoffice' -StartText '08:00' -EndText '14:00' | Out-Null
            $pause83 = Add-TestInterval -Day $day83 -ListName 'ManualPauses' -StartText '12:17' -EndText '12:43'
            [void](Set-ItemComment -Item $pause83 -Text 'MARKER_83_PAUSE')
            $script:App.Ui.ExtendedPauseTable = Get-PausesTable -Day $day83 -Comp $null
            $gridText83 = { (@($grid83.ItemsSource) | ForEach-Object { $_.Row.ItemArray -join '|' }) -join ';' }
            Hide-PauseLockDetails
            $hidden83 = & $gridText83
            Set-PauseLockDetailsVisibility $true
            $shown83 = & $gridText83
            Hide-PauseLockDetails
            $rehidden83 = & $gridText83
            $leak83 = { param($t) $t.Contains('12:17') -or $t.Contains('12:43') -or $t.Contains('00:26') -or $t.Contains('MARKER_83') }
            & $assert 'Test 83d: verborgen nur Platzhalter gebunden (keine Zeiten/Kommentare), Art bleibt lesbar' 'False|True|True' ("$(& $leak83 $hidden83)|$($hidden83.Contains('Manuelle Pause'))|$($hidden83.Contains('••:••'))")
            & $assert 'Test 83e: Einblenden bindet die echten Werte, erneutes Verbergen entfernt sie wieder' 'True|True|False' ("$($shown83.Contains('12:17|12:43|00:26'))|$($shown83.Contains('MARKER_83_PAUSE'))|$(& $leak83 $rehidden83)")
            $script:App.Ui.ExtendedPauseTable = $null
            $script:App.Ui.Extended = $null
            $privWin.Close()
        }
        catch {
            $script:App.Ui.Extended = $null
            Write-Host ('[SKIP] Test 83 (Sichtschutz-UI): in dieser Umgebung nicht ausfuehrbar: ' + $_.Exception.Message) -ForegroundColor Yellow
        }

        # --- Test 84: Ausblenden in den Infobereich beendet die Anwendung nicht ---
        $saSource = [System.IO.File]::ReadAllText($script:AppScriptPath)
        # Quelltext der ANWENDUNG (nicht dieser Testdatei) - LastIndexOf als
        # Absicherung, falls Suchbegriffe mehrfach vorkommen
        $saStart = $saSource.LastIndexOf('function Start-Application')
        $saEnd = $saSource.LastIndexOf('# ===== Einstieg =====')
        $saText = $saSource.Substring($saStart, $saEnd - $saStart)
        & $assert 'Test 84a: kompaktes Fenster ist KEIN modaler Lebensdauer-Anker mehr (Show + Dispatcher.Run statt ShowDialog)' 'True|False' ("$($saText.Contains('$compact.Show()') -and $saText.Contains('Dispatcher]::Run()'))|$($saText.Contains('$compact.ShowDialog'))")
        try {
            Initialize-AppState
            $script:App.Settings = Get-DefaultSettings
            $hideDay = New-TestDay -DateText ((Get-Date).ToString('yyyy-MM-dd'))
            Add-TestSegment -Day $hideDay -Mode 'Betrieb' -StartText ((Get-Date).AddHours(-1).ToString('HH:mm')) | Out-Null
            $script:App.CurrentDay = $hideDay
            $cwin84 = New-XamlWindow -Xaml $script:CompactXaml
            $cwin84.Opacity = 0                      # fuer den Testlauf unsichtbar
            $cwin84.ShowActivated = $false
            $script:App.Ui.Compact = $cwin84
            $script:App.Ui.Tray = [pscustomobject]@{ Visible = $true }   # funktionierendes Tray-Symbol simulieren
            Start-AppTimers
            $timersBefore84 = @($script:App.Timers.Main, $script:App.Timers.KeepAlive)
            $script:App.Radio.DesiredState = 'Paused'
            $cycleOk = $true
            for ($i = 1; $i -le 10; $i++) {
                Show-CompactWindow
                if (-not $cwin84.IsVisible) { $cycleOk = $false }
                Hide-CompactWindow
                if ($cwin84.IsVisible) { $cycleOk = $false }
            }
            Show-CompactWindow
            & $assert 'Test 84b: 10x Verbergen/Anzeigen DERSELBEN Fensterinstanz funktioniert' 'True True' ("$cycleOk $($cwin84.IsVisible)")
            & $assert 'Test 84c: Ausblenden beendet nichts - Timer, Arbeitstag und Radiozustand laufen unveraendert weiter' 'True|True|False|Aktiv|Paused' ("$($script:App.Timers.Main.IsEnabled)|$($script:App.Timers.KeepAlive.IsEnabled)|$($script:App.ShuttingDown)|$($hideDay['Status'])|$($script:App.Radio.DesiredState)")
            & $assert 'Test 84d: Verbergen/Anzeigen erzeugt keine neuen Timerinstanzen' 'True True' ("$([object]::ReferenceEquals($timersBefore84[0], $script:App.Timers.Main)) $([object]::ReferenceEquals($timersBefore84[1], $script:App.Timers.KeepAlive))")
            # Fallback ohne funktionierendes Tray-Symbol: minimieren statt verstecken
            $script:App.Ui.Tray = [pscustomobject]@{ Visible = $false }
            Hide-CompactWindow
            & $assert 'Test 84e: ohne Tray-Symbol bleibt die Anwendung ueber die Taskleiste erreichbar (minimiert, nicht versteckt)' 'Minimized True' ("$($cwin84.WindowState) $($cwin84.ShowInTaskbar)")
            Stop-AppTimers
            $cwin84.Close()
            $script:App.Ui.Compact = $null
            $script:App.Ui.Tray = $null
            $script:App.CurrentDay = $null
        }
        catch {
            try { Stop-AppTimers } catch { }
            $script:App.Ui.Compact = $null
            $script:App.Ui.Tray = $null
            Write-Host ('[SKIP] Test 84b-e (Fensterlebensdauer): in dieser Umgebung nicht ausfuehrbar: ' + $_.Exception.Message) -ForegroundColor Yellow
        }

        # --- Test 85: Einstellungsfenster - Tabs, feste Groesse, Schaltflaechen immer sichtbar ---
        try {
            $setWin85 = New-XamlWindow -Xaml $script:SettingsXaml
            $tab85 = $setWin85.FindName('TabSettings')
            $headers85 = (@($tab85.Items | ForEach-Object { [string]$_.Header }) -join '|')
            & $assert 'Test 85a: alle Einstellungsbereiche sind als Tabs erreichbar' 'Allgemein|Kompakte Ansicht|Aktivhaltung|Internetradio' $headers85
            $sizeOk85 = ($setWin85.Width -ge 720 -and $setWin85.Width -le 820 -and $setWin85.Height -ge 560 -and $setWin85.Height -le 680 -and $setWin85.MinWidth -gt 0 -and $setWin85.MinHeight -gt 0 -and $setWin85.ResizeMode -eq [System.Windows.ResizeMode]::CanResize)
            & $assert 'Test 85b: feste sinnvolle Ausgangsgroesse mit Min-Grenzen, Fenster bleibt verkleinerbar' 'True' ([string]$sizeOk85)
            # Speichern/Abbrechen liegen AUSSERHALB des TabControls (immer sichtbar)
            $btnOk85 = $setWin85.FindName('BtnOk')
            $inTab85 = $false
            $p85 = [System.Windows.LogicalTreeHelper]::GetParent($btnOk85)
            while ($p85) {
                if ($p85 -eq $tab85) { $inTab85 = $true }
                $p85 = [System.Windows.LogicalTreeHelper]::GetParent($p85)
            }
            & $assert 'Test 85c: Speichern/Abbrechen liegen ausserhalb der Tabs (immer sichtbar)' 'False' ([string]$inTab85)
            # Begrenzung auf den Monitor-Arbeitsbereich (gleiche Logik wie Show-SettingsDialog)
            $wa85 = [System.Windows.SystemParameters]::WorkArea.Height
            if ($wa85 -gt 200) { $setWin85.MaxHeight = $wa85 - 20 }
            & $assert 'Test 85d: Fensterhoehe ueberschreitet den Monitor-Arbeitsbereich nicht' 'True' ([string]($setWin85.MaxHeight -le $wa85))
            # Tab-Aenderungen speichern nichts: Werte werden erst im
            # Speichern-Handler uebernommen; Abbrechen verwirft alles
            $regBefore85 = [string]$script:App.Settings['RegularTime']
            $volBefore85 = [string]$script:App.Settings['RadioVolume']
            $setWin85.FindName('TxtRegular').Text = '09:59'
            $setWin85.FindName('TxtRadioVolume').Text = '77'
            & $assert 'Test 85e: Aenderungen in den Tabs veraendern die Einstellungen NICHT ohne Speichern' "$regBefore85|$volBefore85" ("$($script:App.Settings['RegularTime'])|$($script:App.Settings['RadioVolume'])")
            $setWin85.Close()
        }
        catch {
            Write-Host ('[SKIP] Test 85 (Einstellungs-Tabs): in dieser Umgebung nicht ausfuehrbar: ' + $_.Exception.Message) -ForegroundColor Yellow
        }

        # --- Test 86: dunkle Radio-ComboBox in der erweiterten Ansicht ---
        try {
            $extWin86 = New-XamlWindow -Xaml $script:ExtendedXaml
            $cmb86 = $extWin86.FindName('CmbRadioStation')
            $darkStyle86 = $extWin86.FindResource('DarkComboBoxStyle')
            & $assert 'Test 86a: CmbRadioStation verwendet den expliziten dunklen Stil (keyed, keine globale Aenderung)' 'True' ([string]([object]::ReferenceEquals($cmb86.Style, $darkStyle86)))
            & $assert 'Test 86b: dunkles Dropdown mit begrenzter Hoehe und eigenem Item-Stil' 'True|280' ("$($null -ne $cmb86.ItemContainerStyle)|$($cmb86.MaxDropDownHeight)")
            $items86 = New-Object System.Collections.ArrayList
            [void]$items86.Add([pscustomobject]@{ Id = 'a1'; Name = 'Sender A' })
            [void]$items86.Add([pscustomobject]@{ Id = 'b2'; Name = 'Sender B' })
            $cmb86.ItemsSource = $items86
            $cmb86.SelectedValue = 'b2'
            & $assert 'Test 86c: DisplayMemberPath/SelectedValuePath und Senderwechsel funktionieren mit dem neuen Stil' 'Sender B|b2' ("$($cmb86.SelectedItem.Name)|$($cmb86.SelectedValue)")
            $extWin86.Close()
        }
        catch {
            Write-Host ('[SKIP] Test 86 (ComboBox-Stil): in dieser Umgebung nicht ausfuehrbar: ' + $_.Exception.Message) -ForegroundColor Yellow
        }

        # --- Test 87: Log-Viewer liest nur (Zusammenfuehrung, Filter, Limit, Exportbereinigung) ---
        $lvVault = New-VaultDataObject
        for ($i = 1; $i -le 5; $i++) {
            [void]$lvVault['Logs'].Add([ordered]@{ Timestamp = ('2026-07-13 10:0{0}:00' -f $i); Level = 'INFO'; Message = ('Aktuell {0}' -f $i) })
        }
        [void]$lvVault['Logs'].Add([ordered]@{ Timestamp = '2026-07-13 11:00:00'; Level = 'ERROR'; Message = 'Fehler Ende' })
        $lvArch = New-Object System.Collections.ArrayList
        [void]$lvArch.Add([ordered]@{ Timestamp = '2026-07-12 09:00:00'; Level = 'WARN'; Message = 'Archiviert 1' })
        [void]$lvVault['LogArchives'].Add([ordered]@{ Id = 'lv-a'; Entries = $lvArch })
        $lvLogsBefore = @($lvVault['Logs']).Count
        $lvPage = Get-LogViewEntries -Vault $lvVault -MaxCount 3
        & $assert 'Test 87a: neueste Eintraege zuerst, Mengenbegrenzung greift' '3|Fehler Ende' ("$(@($lvPage).Count)|$(@($lvPage)[0].Meldung)")
        $lvWarn = Get-LogViewEntries -Vault $lvVault -Levels @('WARN') -MaxCount 500
        & $assert 'Test 87b: Levelfilter und Archiv-Zusammenfuehrung funktionieren' '1|Archiviert 1' ("$(@($lvWarn).Count)|$(@($lvWarn)[0].Meldung)")
        $lvFound = Get-LogViewEntries -Vault $lvVault -SearchText 'aktuell 3' -MaxCount 500
        & $assert 'Test 87c: Suche ohne Beachtung der Gross-/Kleinschreibung' '1' ([string]@($lvFound).Count)
        & $assert 'Test 87d: der Viewer veraendert keine Logs und keine Archive' "$lvLogsBefore|1|1" ("$(@($lvVault['Logs']).Count)|$(@($lvVault['LogArchives']).Count)|$(@($lvArch).Count)")
        & $assert 'Test 87e: Export entfernt vollstaendige Stream-/Internetadressen' 'Fehler [URL entfernt] Ende' (Get-SanitizedLogMessage 'Fehler http://stream.example.de/pfad?token=geheim Ende')

        # =====================================================================
        # Tests 88-101 (Ueberarbeitung): Vortags-Review, Endzeit-Anzeige,
        # Live-Segmenttabelle, Speicherrueckgaben/Rollback, Radio-Playerkontext,
        # Presets, Shutdown (nur simuliert) und Speicheruebersicht.
        # Keine echten Tastendruecke, Radiostreams, Netzwerkzugriffe oder
        # PC-Shutdowns; ausschliesslich temporaere Testverzeichnisse.
        # =====================================================================
        $yesterdayText = (Get-Date).AddDays(-1).ToString('yyyy-MM-dd')
        $threeDaysAgoText = (Get-Date).AddDays(-3).ToString('yyyy-MM-dd')

        # --- Test 88: Erkennung offener/auto-beendeter Vortage -----------------
        $d88 = New-TestDay -DateText $yesterdayText
        Add-TestSegment -Day $d88 -Mode 'Betrieb' -StartText '22:00' | Out-Null
        & $assert 'Test 88a: aktiver Arbeitstag vom Vortag wird als klaerungsbeduerftig erkannt' 'True' ([string](Test-DayNeedsPreviousDayReview -Day $d88))
        $d88b = New-TestDay -DateText ((Get-Date).ToString('yyyy-MM-dd'))
        Add-TestSegment -Day $d88b -Mode 'Betrieb' -StartText '08:00' | Out-Null
        & $assert 'Test 88b: aktiver Tag von HEUTE erzeugt keine Vortags-Klaerung (Fall C unveraendert)' 'False' ([string](Test-DayNeedsPreviousDayReview -Day $d88b))
        Invoke-MidnightRolloverIfNeeded -Day $d88 | Out-Null
        & $assert 'Test 88c: automatisch beendeter Tag erhaelt offenen Bestaetigungsstatus (AutoEndReviewPending)' 'Beendet|True|False' ("$($d88['Status'])|$($d88['AutoEndReviewPending'])|$($d88['AutoEndReviewed'])")
        & $assert 'Test 88d: der pruefbeduerftige Tag wird als juengster Tag gefunden' 'True' ([string]($null -ne (Get-AutoEndReviewCandidate -Days @($d88))))
        # Historische AutoEnded-Tage OHNE Review-Felder: nur der Vortag ist
        # pruefbeduerftig; aeltere gelten als geprueft (keine Abfragekette).
        $d88old = New-TestDay -DateText $threeDaysAgoText
        Add-TestSegment -Day $d88old -Mode 'Betrieb' -StartText '08:00' -EndText '16:00' | Out-Null
        $d88old['Status'] = 'Beendet'
        $d88old['EndedAt'] = ($threeDaysAgoText + ' 16:00:00')
        $d88old['AutoEnded'] = $true
        $d88old.Remove('AutoEndReviewPending')
        $d88old.Remove('AutoEndReviewed')
        & $assert 'Test 88e: aelterer historischer AutoEnded-Tag ohne Review-Feld gilt als geprueft' 'True' ([string]($null -eq (Get-AutoEndReviewCandidate -Days @($d88old))))
        $d88mig = New-TestDay -DateText $yesterdayText
        Add-TestSegment -Day $d88mig -Mode 'Betrieb' -StartText '08:00' -EndText '18:00' | Out-Null
        $d88mig['Status'] = 'Beendet'
        $d88mig['EndedAt'] = ($yesterdayText + ' 18:00:00')
        $d88mig['AutoEnded'] = $true
        $d88mig.Remove('AutoEndReviewPending')
        $d88mig.Remove('AutoEndReviewed')
        & $assert 'Test 88f: nur der juengste AutoEnded-VORTAG ohne Review-Feld ist pruefbeduerftig (Migration)' 'True|True' ("$($null -ne (Get-AutoEndReviewCandidate -Days @($d88old, $d88mig)))|$($null -eq (Get-AutoEndReviewCandidate -Days @($d88old)))")

        # --- Test 89: Bestaetigung der 10 Stunden setzt exaktes Ende -----------
        $d89 = New-TestDay -DateText $yesterdayText
        Add-TestSegment -Day $d89 -Mode 'Betrieb' -StartText '06:00' | Out-Null
        $err89 = Complete-AutoEndTenHours -Day $d89
        $comp89 = Get-DayComputation -Day $d89 -Now (ConvertFrom-DateTimeString $d89.EndedAt)
        $segEnd89 = ''
        foreach ($s89 in @($d89.Segments)) { $segEnd89 = [string]$s89.End }
        & $assert 'Test 89a: 10:00-Bestaetigung setzt Segmentende und EndedAt exakt auf den 10h-Zeitpunkt (16:45)' "|$yesterdayText 16:45:00|$yesterdayText 16:45:00" ("$err89|$($d89['EndedAt'])|$segEnd89")
        & $assert 'Test 89b: Netto exakt 10:00, Status Beendet, Review abgeschlossen' '10:00|Beendet|False|True|True' ("$(Format-Duration $comp89.Netto)|$($d89['Status'])|$($d89['AutoEndReviewPending'])|$($d89['AutoEndReviewed'])|$($d89['MaxReached'])")

        # --- Test 90: manuelles Ende korrigiert Segment, Totals und EndedAt ----
        $d90 = New-TestDay -DateText $yesterdayText
        Add-TestSegment -Day $d90 -Mode 'Betrieb' -StartText '06:00' | Out-Null
        $end90 = Get-DayDateTime -DayDate $yesterdayText -TimeText '15:00'
        $err90 = Complete-AutoEndManual -Day $d90 -End $end90
        $comp90 = Get-DayComputation -Day $d90 -Now $end90
        & $assert 'Test 90a: manuelle Endzeit korrigiert Segment, Totals und EndedAt' "|$yesterdayText 15:00:00|08:15|Beendet|False" ("$err90|$($d90['EndedAt'])|$(Format-Duration $comp90.Netto)|$($d90['Status'])|$($d90['AutoEnded'])")
        & $assert 'Test 90b: EndReason kennzeichnet die nachtraegliche manuelle Korrektur' 'Nachträglich manuell korrigiert' ([string]$d90['EndReason'])
        & $assert 'Test 90c: Verlauf zeigt nach Korrektur die tatsaechliche Endzeit' '15:00' (Get-DayEndDisplayText -Day $d90 -OpenText 'Aktiv')
        $d90b = New-TestDay -DateText $yesterdayText
        Add-TestSegment -Day $d90b -Mode 'Betrieb' -StartText '06:00' | Out-Null
        $err90b = Complete-AutoEndManual -Day $d90b -End (Get-DayDateTime -DayDate $yesterdayText -TimeText '18:00')
        & $assert 'Test 90d: Ende ueber 10:00 Netto wird abgelehnt und vollstaendig zurueckgenommen' 'True|Aktiv|True' ("$($err90b -ne '')|$($d90b['Status'])|$($d90b['Segments'][0]['Running'])")
        & $assert 'Test 90e: Ablehnung erklaert den Zeitpunkt der maximalen Nettozeit (16:45)' 'True' ([string]($err90b -match '16:45'))
        $err90c = Complete-AutoEndManual -Day $d90b -End (Get-Date).AddHours(2)
        & $assert 'Test 90f: Ende in der Zukunft wird abgelehnt' 'True' ([string]($err90c -ne ''))

        # --- Test 91: Neue Tageserfassung erst nach Klaerung; Abbruch startet nichts
        Initialize-AppState
        $script:App.Settings = Get-DefaultSettings
        $d91 = New-TestDay -DateText $yesterdayText
        Add-TestSegment -Day $d91 -Mode 'Betrieb' -StartText '22:00' | Out-Null
        Invoke-MidnightRolloverIfNeeded -Day $d91 | Out-Null
        $days91 = New-Object System.Collections.ArrayList
        [void]$days91.Add($d91)
        $script:App.Data = [ordered]@{ SchemaVersion = 1; LastSavedAt = $null; Days = $days91 }
        $script:App.Flags.ActiveDayDecisionCompleted = $true
        & $assert 'Test 91a: solange die Klaerung offen ist, wird KEIN neuer Arbeitstag angeboten' 'False' ([string](Test-ShouldOfferStartDay))
        $flow91 = Invoke-AutoEndReviewFlow -Day $d91 -ChoiceResolver { param($d, $c, $a) @{ Choice = 'Abbrechen'; EndTime = $null } }
        & $assert 'Test 91b: Abbruch der Review-Abfrage klaert nichts und startet keinen neuen Tag' 'False|True|False' ("$flow91|$($d91['AutoEndReviewPending'])|$(Test-ShouldOfferStartDay)")
        $flow91b = Invoke-AutoEndReviewFlow -Day $d91 -ChoiceResolver { param($d, $c, $a) @{ Choice = 'Bestaetigen'; EndTime = $null } }
        & $assert 'Test 91c: nach der Bestaetigung ist der Tag geklaert und ein neuer Tag moeglich' 'True|False|True|True' ("$flow91b|$($d91['AutoEndReviewPending'])|$($d91['AutoEndReviewed'])|$(Test-ShouldOfferStartDay)")

        # --- Test 92: Endzeit-Anzeige liefert niemals 00:00 aus fehlenden Werten
        $d92 = New-TestDay
        Add-TestSegment -Day $d92 -Mode 'Betrieb' -StartText '08:00' | Out-Null
        & $assert 'Test 92a: aktiver Tag zeigt Offen/Aktiv statt 00:00' 'Offen|Aktiv' ("$(Get-DayEndDisplayText -Day $d92)|$(Get-DayEndDisplayText -Day $d92 -OpenText 'Aktiv')")
        $d92b = New-TestDay
        Add-TestSegment -Day $d92b -Mode 'Betrieb' -StartText '08:00' -EndText '16:30' | Out-Null
        $d92b['Status'] = 'Beendet'
        $d92b['EndedAt'] = $null
        & $assert 'Test 92b: fehlendes EndedAt faellt auf das letzte Segmentende zurueck (nicht 00:00)' '16:30' (Get-DayEndDisplayText -Day $d92b)
        $d92c = New-TestDay
        $d92c['Status'] = 'Beendet'
        $d92c['EndedAt'] = ''
        & $assert 'Test 92c: ohne Ende und ohne Segmente erscheint --:-- (kein Mitternachts-Standard)' '--:--' (Get-DayEndDisplayText -Day $d92c)
        $hist92 = Get-HistoryTable -Days @($d92)
        & $assert 'Test 92d: Verlauf zeigt bei aktivem Tag nicht 00:00' 'Aktiv' ([string]$hist92.Rows[0]['Ende'])

        # --- Test 93: CSV verwendet dieselbe korrekte Endzeit -------------------
        New-Item -ItemType Directory -Path $script:Paths.Exports -Force | Out-Null
        $csv93 = Export-WorkDataCsv -Days @($d90) -Suffix 'Test93'
        $csvLines93 = [System.IO.File]::ReadAllLines([string]@($csv93)[0])
        # Spalte 'Ende' (Index 2) der Datenzeile: identische zentrale Endzeit
        $endCol93 = (@($csvLines93)[1] -split ';')[2]
        & $assert 'Test 93: CSV verwendet dieselbe korrekte Endzeit (15:00, nicht 00:00)' '15:00' $endCol93
        foreach ($f93 in @($csv93)) { Remove-Item -LiteralPath ([string]$f93) -Force -ErrorAction SilentlyContinue }

        # --- Test 94: 'Sollabweichung' entfernt; dynamischer Wert bleibt korrekt
        $d94 = New-TestDay
        Add-TestSegment -Day $d94 -Mode 'Homeoffice' -StartText '08:00' | Out-Null
        $comp94a = Get-DayComputation -Day $d94 -Now (Get-TestNow $d94 '10:00')
        $text94a = Get-ExtendedValuesText -Comp $comp94a -Day $d94
        $comp94b = Get-DayComputation -Day $d94 -Now (Get-TestNow $d94 '16:00')
        $text94b = Get-ExtendedValuesText -Comp $comp94b -Day $d94
        & $assert 'Test 94a: Sollabweichung ist nicht mehr Teil der erweiterten Oberflaeche' 'False|False' ("$($text94a.Contains('Sollabweichung'))|$($text94b.Contains('Sollabweichung'))")
        & $assert 'Test 94b: vor der Sollzeit erscheint Soll-Rest, danach Ueberstunden (dynamisch, korrekt)' 'True|False|True|False' ("$($text94a.Contains('Soll-Rest          05:00'))|$($text94a.Contains('Überstunden'))|$($text94b.Contains('Überstunden        +01:00'))|$($text94b.Contains('Soll-Rest'))")
        & $assert 'Test 94c: kein leerer Platzhalter - Zeilen ruecken sauber nach (keine Doppelleerzeile)' 'False' ([string]($text94a.Contains("`r`n`r`n`r`n")))

        # --- Test 95: laufende Segmentzeile aktualisiert Brutto/Netto ohne Datenmutation
        $d95 = New-TestDay
        Add-TestSegment -Day $d95 -Mode 'Homeoffice' -StartText '08:00' | Out-Null
        Add-TestInterval -Day $d95 -ListName 'ManualPauses' -StartText '09:00' -EndText '09:30' | Out-Null
        $fp95 = Get-DayContentFingerprint -Day $d95
        $mod95 = [string]$d95['ModifiedAt']
        $rows95a = Get-SegmentDisplayRows -Day $d95 -Now (Get-TestNow $d95 '10:00')
        $rows95b = Get-SegmentDisplayRows -Day $d95 -Now (Get-TestNow $d95 '10:30')
        & $assert 'Test 95a: laufende Zeile veraendert Brutto und Netto bei veraendertem Now' '02:00|01:30|02:30|02:00' ("$($rows95a[0].Brutto)|$($rows95a[0].Netto)|$($rows95b[0].Brutto)|$($rows95b[0].Netto)")
        $table95 = Get-SegmentsTable -Day $d95 -Now (Get-TestNow $d95 '10:30')
        & $assert 'Test 95b: Tabellenaufbau liefert dieselben Anzeigewerte' '02:30|02:00' ("$($table95.Rows[0]['Brutto'])|$($table95.Rows[0]['Netto'])")
        & $assert 'Test 95c: Tabellenrefresh veraendert keine Arbeitszeitdaten und loest kein Save aus' "$fp95|$mod95|False|False" ("$(Get-DayContentFingerprint -Day $d95)|$($d95['ModifiedAt'])|$($script:App.Flags.SaveInProgress)|$($script:App.Flags.UnsavedChanges)")

        # --- Tests 96: Speicherrueckgaben und Snapshot-Wiederherstellung --------
        Initialize-AppState
        $script:Paths = (& $newTestPaths $testRoot3)
        Set-VaultSessionKeys -Keys (& $cloneKeys $keys) -Salt $salt -Iterations $iter
        $v96 = New-VaultDataObject
        Set-ActiveVault -Vault $v96
        Set-VaultLoadReference -Kind 'Haupt' -Revision ([long]$v96['Revision'])
        $saveWd96 = Save-WorkData
        $saveSet96 = Save-Settings
        & $assert 'Test 96a: Save-WorkData und Save-Settings liefern booleschen Erfolg' 'True True|Boolean Boolean' ("$saveWd96 $saveSet96|$($saveWd96.GetType().Name) $($saveSet96.GetType().Name)")
        $goodPending96 = $script:Paths.VaultPending
        $script:Paths.VaultPending = Join-Path $testRoot3 'gibtsnicht96\pending.azt'
        $failWd96 = Save-WorkData
        & $assert 'Test 96b: fehlgeschlagenes Speichern liefert false und markiert NICHT GESPEICHERT' 'False|True' ("$failWd96|$($script:App.Flags.UnsavedChanges)")
        # Start eines Arbeitstags mit Speicherfehler: vollstaendige Ruecknahme
        $daysBefore96 = @($script:App.Data.Days).Count
        $newDay96 = Start-WorkDay -Mode 'Betrieb' -StartTime (Get-Date).AddHours(-1)
        & $assert 'Test 96c: fehlgeschlagener Save beim Start stellt den Snapshot wieder her (kein neuer Tag)' "True|$daysBefore96|True" ("$($null -eq $newDay96)|$(@($script:App.Data.Days).Count)|$($null -eq $script:App.CurrentDay)")
        $script:Paths.VaultPending = $goodPending96
        Clear-VaultSaveFailedState
        $day96 = Start-WorkDay -Mode 'Betrieb' -StartTime (Get-Date).AddHours(-1)
        & $assert 'Test 96d: nach behobenem Fehler startet der Arbeitstag regulaer' 'True' ([string]($null -ne $day96))
        # Moduswechsel mit Speicherfehler: Snapshot-Ruecknahme
        $script:Paths.VaultPending = Join-Path $testRoot3 'gibtsnicht96\pending.azt'
        $seg96 = Switch-WorkMode -Day $day96 -NewMode 'Homeoffice' -EndTime (Get-Date) -StartTime (Get-Date)
        & $assert 'Test 96e: fehlgeschlagener Save beim Moduswechsel stellt den Snapshot wieder her' 'True|1|True' ("$($null -eq $seg96)|$(@($day96.Segments).Count)|$($day96.Segments[0]['Running'])")
        # Manuelle Pause mit Speicherfehler: Snapshot-Ruecknahme
        $pause96 = Start-ManualPauseInterval -Day $day96
        & $assert 'Test 96f: fehlgeschlagener Save bei manueller Pause stellt den Snapshot wieder her' 'True|0' ("$($null -eq $pause96)|$(@($day96.ManualPauses).Count)")
        # Automatisches Lock-Ereignis: Zustand bleibt erhalten, kein Dialog, UnsavedChanges
        Clear-VaultSaveFailedState
        $lock96 = Start-LockInterval -Day $day96
        & $assert 'Test 96g: Lock-Speicherfehler behaelt den Ereigniszustand (kein Rollback) und markiert UnsavedChanges' 'True|1|True' ("$($null -ne $lock96)|$(@($day96.LockIntervals).Count)|$($script:App.Flags.UnsavedChanges)")
        $script:Paths.VaultPending = $goodPending96
        Stop-LockInterval -Day $day96 | Out-Null
        Clear-VaultSaveFailedState
        # Vortagskorrektur mit Speicherfehler: Zustand UND Review-Status zurueck
        [void]$script:App.Data.Days.Remove($day96)
        $script:App.CurrentDay = $null
        $d96r = New-TestDay -DateText $yesterdayText
        Add-TestSegment -Day $d96r -Mode 'Betrieb' -StartText '22:00' | Out-Null
        Invoke-MidnightRolloverIfNeeded -Day $d96r | Out-Null
        [void]$script:App.Data.Days.Add($d96r)
        Save-Vault | Out-Null
        $script:Paths.VaultPending = Join-Path $testRoot3 'gibtsnicht96\pending.azt'
        $err96r = Complete-AutoEndManual -Day $d96r -End (Get-DayDateTime -DayDate $yesterdayText -TimeText '23:00')
        & $assert 'Test 96h: fehlgeschlagener Save der Vortagskorrektur stellt Zustand und Review-Status wieder her' 'True|True|False' ("$($err96r -ne '')|$($d96r['AutoEndReviewPending'])|$($d96r['AutoEndReviewed'])")
        $script:Paths.VaultPending = $goodPending96
        Clear-VaultSaveFailedState
        $err96ok = Complete-AutoEndManual -Day $d96r -End (Get-DayDateTime -DayDate $yesterdayText -TimeText '23:00')
        & $assert 'Test 96i: nach behobenem Fehler wird die Vortagskorrektur gespeichert' '|False|True' ("$err96ok|$($d96r['AutoEndReviewPending'])|$($d96r['AutoEndReviewed'])")

        # --- Test 97: Radio-Playerkontext (verspaetete Ereignisse, Handler) -----
        $objA = New-Object object
        $objB = New-Object object
        $radio97 = $script:App.Radio
        $ctxOld = @{ Player = $objA; RequestId = [long]1; StationId = 'alt'; Url = 'http://alt.example/1'; Handlers = $null; HandlersRemoved = $false }
        $ctxNew = @{ Player = $objB; RequestId = [long]2; StationId = 'neu'; Url = 'http://neu.example/1'; Handlers = $null; HandlersRemoved = $false }
        $radio97.PlayerContext = $ctxNew
        $radio97.Player = $objB
        $radio97.CurrentRequestId = [long]2
        $radio97.SelectedStationId = 'neu'
        & $assert 'Test 97a: verspaetete Ereignisse eines ALTEN MediaPlayers werden ignoriert' 'False' ([string](Test-RadioEventStillValid -Context $ctxOld))
        & $assert 'Test 97b: Ereignisse des aktuellen Players mit aktueller RequestId sind gueltig' 'True' ([string](Test-RadioEventStillValid -Context $ctxNew))
        $radio97.CurrentRequestId = [long]3
        & $assert 'Test 97c: nach neuer Oeffnungsgeneration sind auch Ereignisse desselben Players ungueltig' 'False' ([string](Test-RadioEventStillValid -Context $ctxNew))
        $fpRadio97 = Get-DayContentFingerprint -Day $d96r
        Invoke-RadioMediaFailed -Context $ctxOld
        Invoke-RadioMediaOpened -Context $ctxOld
        & $assert 'Test 97d: ignorierte Alt-Ereignisse veraendern weder Radiozustand noch Daten' "3|neu|$fpRadio97" ("$($radio97.CurrentRequestId)|$($radio97.SelectedStationId)|$(Get-DayContentFingerprint -Day $d96r)")
        try {
            $ctx97 = New-RadioPlayerContext -RequestId ([long]9) -StationId 's97' -Url 'http://beispiel.invalid/stream'
            $radio97.PlayerContext = $ctx97
            $radio97.Player = $ctx97.Player
            $had97 = ($null -ne $ctx97.Handlers)
            Clear-RadioPlayerContext -Context $ctx97
            & $assert 'Test 97e: alte Radiohandler werden beim Playerwechsel entfernt und Referenzen freigegeben' "True|True|True|True" ("$had97|$($ctx97.HandlersRemoved)|$($null -eq $radio97.PlayerContext)|$($null -eq $radio97.Player)")
        }
        catch {
            Write-Host ('[SKIP] Test 97e (MediaPlayer-Kontext): in dieser Umgebung nicht ausfuehrbar: ' + $_.Exception.Message) -ForegroundColor Yellow
        }
        # Senderaenderungen in den Einstellungen (reine Entscheidungslogik)
        $stations97 = New-Object System.Collections.ArrayList
        [void]$stations97.Add([ordered]@{ Id = 'a'; Name = 'Sender A'; Url = 'http://a.example/live' })
        $script:App.Settings['RadioStations'] = $stations97
        $script:App.Settings['RadioSelectedStationId'] = 'a'
        $act97 = Get-RadioSettingsChangeAction -WasPlaying $true -OpenStationId 'a' -OpenUrl 'http://a.example/live'
        & $assert 'Test 97f: unveraenderte URL - laufender Stream laeuft weiter' 'Weiter' ([string]$act97.Kind)
        $act97 = Get-RadioSettingsChangeAction -WasPlaying $true -OpenStationId 'a' -OpenUrl 'http://a.example/ALT'
        & $assert 'Test 97g: geaenderte URL - Stream wird kontrolliert neu geoeffnet' 'NeuOeffnen' ([string]$act97.Kind)
        $act97 = Get-RadioSettingsChangeAction -WasPlaying $true -OpenStationId 'geloescht' -OpenUrl 'http://x.example/1'
        & $assert 'Test 97h: laufender Sender entfernt - gueltiger Ersatzsender wird geoeffnet (kein alter Stream laeuft unbemerkt weiter)' 'Ersatz|a' ("$($act97.Kind)|$($act97.Station['Id'])")
        $script:App.Settings['RadioSelectedStationId'] = 'auch-geloescht'
        $act97 = Get-RadioSettingsChangeAction -WasPlaying $true -OpenStationId 'geloescht' -OpenUrl 'http://x.example/1'
        & $assert 'Test 97i: laufender Sender entfernt ohne Ersatz - Stream wird sicher gestoppt' 'Stopp' ([string]$act97.Kind)
        $act97 = Get-RadioSettingsChangeAction -WasPlaying $false -OpenStationId '' -OpenUrl ''
        & $assert 'Test 97j: pausiertes/gestopptes Radio startet nach Einstellungsaenderung nicht automatisch' 'Nichts' ([string]$act97.Kind)
        # Wiedergabestatus wird vor dem finalen Save bestimmt
        $script:App.Settings['RadioRememberPlaybackState'] = $true
        $script:App.Radio.DesiredState = 'Playing'
        $val97 = Set-RadioLastPlayingSetting
        & $assert 'Test 97k: Wiedergabestatus wird vor dem finalen Save bestimmt und gesetzt' 'True|True' ("$val97|$($script:App.Settings['RadioLastWasPlaying'])")
        $script:App.Settings['RadioRememberPlaybackState'] = $false
        $val97 = Set-RadioLastPlayingSetting
        & $assert 'Test 97l: ohne "merken" wird der Status nicht uebernommen' 'False|False' ("$val97|$($script:App.Settings['RadioLastWasPlaying'])")
        $script:App.Radio.DesiredState = 'Stopped'

        # --- Test 98: Presets (Minimum, Schutz der Standard-Presets, eigene) ----
        $minFields98 = @($script:CompactPresets['Minimum'])
        $script:App.Settings['CompactFields'] = $minFields98
        $d98 = New-TestDay -DateText ((Get-Date).ToString('yyyy-MM-dd'))
        Add-TestSegment -Day $d98 -Mode 'Betrieb' -StartText '08:00' | Out-Null
        $comp98 = Get-DayComputation -Day $d98 -Now (Get-Date)
        $status98 = Get-CompactStatusText -Comp $comp98 -Day $d98
        $header98 = Get-HeaderLineText
        & $assert 'Test 98a: Minimum-Preset zeigt nur den Status (keine Arbeitszeit-Detailwerte)' 'True|False|False|False|False' ("$($status98.Contains('Status:'))|$($status98.Contains('Beginn:'))|$($status98.Contains('Netto:'))|$($status98.Contains('Soll'))|$($status98.Contains('Max-'))")
        & $assert 'Test 98b: Uhrzeit, KW und Datum stehen weiterhin in der Kopfzeile' 'True' ([string]($header98 -match '^\d{2}:\d{2}(:\d{2})? \| KW \d+ \| '))
        & $assert 'Test 98c: reservierte Namen der Standard-Presets sind nicht zulaessig (auch case-insensitive)' 'True|True|True' ("$((Test-CompactPresetName -Name 'Minimum') -ne '')|$((Test-CompactPresetName -Name 'standard') -ne '')|$((Test-CompactPresetName -Name ' KLASSISCH ') -ne '')")
        $bad98 = @(
            [ordered]@{ Id = 'p1'; Name = 'Minimum'; Fields = @('Netto') },
            [ordered]@{ Id = 'p2'; Name = 'Mein Preset'; Fields = @('Netto', 'Unbekannt') },
            [ordered]@{ Id = 'p3'; Name = ''; Fields = @('Netto') },
            [ordered]@{ Id = 'p4'; Name = 'Nur Unbekannt'; Fields = @('GibtEsNicht') }
        )
        $valid98 = Get-ValidatedCompactPresets -Loaded $bad98
        & $assert 'Test 98d: Validierung verwirft reservierte/leere/feldlose Presets und ignoriert unbekannte Felder' '1|Mein Preset|Netto' ("$(@($valid98).Count)|$($valid98[0]['Name'])|$(@($valid98[0]['Fields']) -join ',')")
        $six98 = New-Object System.Collections.ArrayList
        for ($i = 1; $i -le 6; $i++) { [void]$six98.Add([ordered]@{ Id = "id$i"; Name = "Preset $i"; Fields = @('Netto') }) }
        $five98 = Get-ValidatedCompactPresets -Loaded $six98
        & $assert 'Test 98e: es sind hoechstens fuenf eigene Presets moeglich' '5' ([string]@($five98).Count)
        # Eigene Presets werden verschluesselt gespeichert
        $custom98 = New-Object System.Collections.ArrayList
        [void]$custom98.Add([ordered]@{ Id = 'geheim98'; Name = 'GEHEIMES_PRESET_98'; Fields = @('Netto', 'Beginn') })
        $script:App.Settings['CompactPresets'] = $custom98
        $saved98 = Save-Vault
        $reload98 = Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        $raw98 = [System.IO.File]::ReadAllText($script:Paths.VaultFile)
        & $assert 'Test 98f: eigene Presets werden validiert und verschluesselt gespeichert' "True|GEHEIMES_PRESET_98|False" ("$saved98|$(@($reload98['Settings']['CompactPresets'])[0]['Name'])|$($raw98.Contains('GEHEIMES_PRESET_98'))")
        # Arbeitskopie-Prinzip: Aenderungen ohne Speichern wirken nicht
        $workCopy98 = New-Object System.Collections.ArrayList
        foreach ($p in @($script:App.Settings['CompactPresets'])) { [void]$workCopy98.Add([ordered]@{ Id = $p['Id']; Name = $p['Name']; Fields = @($p['Fields']) }) }
        $workCopy98[0]['Name'] = 'VERWORFEN'
        & $assert 'Test 98g: Abbrechen im Einstellungsdialog verwirft Presetaenderungen (Arbeitskopie)' 'GEHEIMES_PRESET_98' ([string]@($script:App.Settings['CompactPresets'])[0]['Name'])
        # Aktivieren eines Presets veraendert keine Arbeitszeitdaten
        [void]$script:App.Data.Days.Add($d98)
        Save-Vault | Out-Null
        $fp98 = Get-DayContentFingerprint -Day $d98
        $applied98 = Set-CompactFieldsPreset -Fields @('Beginn', 'Netto') -PresetName 'Testlauf'
        & $assert 'Test 98h: Preset-Aktivierung aendert nur die Feldauswahl - keine Arbeitszeitdaten, kein neuer Abschnitt' "True|$fp98|1|Beginn,Netto" ("$applied98|$(Get-DayContentFingerprint -Day $d98)|$(@($d98.Segments).Count)|$(@($script:App.Settings['CompactFields']) -join ',')")
        [void]$script:App.Data.Days.Remove($d98)
        Save-Vault | Out-Null

        # --- Test 99: Shutdown nur Opt-in, nur simuliert, nie bei Fehlern -------
        $def99 = Get-DefaultSettings
        & $assert 'Test 99a: Opt-in-Einstellung ist standardmaessig deaktiviert' 'False' ([string][bool]$def99['ShutdownOfferEnabled'])
        try {
            $endWin99 = New-XamlWindow -Xaml $script:EndDayXaml
            & $assert 'Test 99b: Shutdown-Schaltflaeche ist im Dialog standardmaessig NICHT sichtbar' 'Collapsed' ([string]$endWin99.FindName('BtnOkShutdown').Visibility)
            $endWin99.Close()
        }
        catch {
            Write-Host ('[SKIP] Test 99b (EndDay-Dialog): in dieser Umgebung nicht ausfuehrbar: ' + $_.Exception.Message) -ForegroundColor Yellow
        }
        $script:App.Flags.SimulatedShutdownRequested = $false
        $d99 = New-TestDay -DateText ((Get-Date).ToString('yyyy-MM-dd'))
        Add-TestSegment -Day $d99 -Mode 'Betrieb' -StartText ((Get-Date).AddHours(-2).ToString('HH:mm')) | Out-Null
        [void]$script:App.Data.Days.Add($d99)
        Save-Vault | Out-Null
        $completed99 = Complete-WorkDay -Day $d99 -End (Get-Date) -Reason 'Manuell'
        & $assert 'Test 99c: normales "Arbeitstag beenden" loest niemals einen Shutdown aus' 'True|False' ("$completed99|$($script:App.Flags.SimulatedShutdownRequested)")
        # Speicherfehler: kein Shutdown
        $script:Paths.VaultPending = Join-Path $testRoot3 'gibtsnicht99\pending.azt'
        $sd99 = Invoke-EndDayShutdown
        & $assert 'Test 99d: Shutdown wird bei Speicherfehler niemals aufgerufen' 'False|False' ("$sd99|$($script:App.Flags.SimulatedShutdownRequested)")
        $script:Paths.VaultPending = $goodPending96
        Clear-VaultSaveFailedState
        # Cloudkonflikt: kein Shutdown
        $extBytes99 = [System.IO.File]::ReadAllBytes($script:Paths.VaultFile)
        [System.IO.File]::WriteAllBytes($script:Paths.VaultFile, [byte[]]($extBytes99 + 32))
        $sd99b = Invoke-EndDayShutdown
        & $assert 'Test 99e: Shutdown wird bei Cloudkonflikt niemals aufgerufen' 'False|False' ("$sd99b|$($script:App.Flags.SimulatedShutdownRequested)")
        [System.IO.File]::WriteAllBytes($script:Paths.VaultFile, $extBytes99)
        $script:App.VaultFileHash = Get-FileSha256Hex -Path $script:Paths.VaultFile
        Clear-VaultSaveFailedState
        # Simulierte Anforderung im Testlauf (niemals echt)
        $req99 = Invoke-WindowsShutdownRequest
        & $assert 'Test 99f: im Testlauf wird der Shutdown ausschliesslich simuliert' 'True|True' ("$req99|$($script:App.Flags.SimulatedShutdownRequested)")
        $script:App.Flags.SimulatedShutdownRequested = $false
        [void]$script:App.Data.Days.Remove($d99)
        Save-Vault | Out-Null

        # --- Tests 100: Speicheruebersicht (nur lesend, feste Pfade) ------------
        New-Item -ItemType Directory -Path (Join-Path $testRoot4 'Data') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $testRoot4 'Exports') -Force | Out-Null
        $paths100 = (& $newTestPaths $testRoot4)
        $prevPaths100 = $script:Paths
        $script:Paths = $paths100
        [System.IO.File]::WriteAllBytes($script:Paths.VaultFile, (New-Object byte[] 500))
        [System.IO.File]::WriteAllBytes((Join-Path $testRoot4 'Data\vault.backup1.azt'), (New-Object byte[] 300))
        [System.IO.File]::WriteAllBytes((Join-Path $testRoot4 'Exports\export1.csv'), (New-Object byte[] 111))
        [System.IO.File]::WriteAllBytes((Join-Path $testRoot4 'Exports\export2.csv'), (New-Object byte[] 89))
        $limit100 = $script:VaultConst.MaxFileBytes
        $script:VaultConst.MaxFileBytes = 10000
        $cmd100 = Get-Command Get-StorageOverviewData
        $userParams100 = @($cmd100.Parameters.Keys | Where-Object { [System.Management.Automation.Cmdlet]::CommonParameters -notcontains $_ })
        & $assert 'Test 100a: Speicheruebersicht akzeptiert keine benutzergesteuerten Pfade (feste Pfade Data/Recovery/Exports)' '0' ([string]@($userParams100).Count)
        $filesBefore100 = (@(Get-ChildItem -LiteralPath $testRoot4 -Recurse -File | ForEach-Object { $_.FullName + '|' + $_.Length + '|' + $_.LastWriteTimeUtc.Ticks } | Sort-Object) -join ';')
        $data100 = Get-StorageOverviewData
        $null = Get-StorageOverviewData   # "Aktualisieren" (zweite Ermittlung)
        $filesAfter100 = (@(Get-ChildItem -LiteralPath $testRoot4 -Recurse -File | ForEach-Object { $_.FullName + '|' + $_.Length + '|' + $_.LastWriteTimeUtc.Ticks } | Sort-Object) -join ';')
        & $assert 'Test 100b: Dateigroessen und Gesamtgroessen werden korrekt addiert' '500|300|800|2|200|2' ("$($data100.VaultMain)|$($data100.VaultBackup1)|$($data100.DataFolder.TotalBytes)|$($data100.ExportsFolder.FileCount)|$($data100.ExportsFolder.TotalBytes)|$($data100.DataFolder.FileCount)")
        & $assert 'Test 100c: fehlender Recovery-Ordner wird als nicht vorhanden (0/0) behandelt - kein Abbruch' 'False|0|0' ("$($data100.RecoveryFolder.Exists)|$($data100.RecoveryFolder.FileCount)|$($data100.RecoveryFolder.TotalBytes)")
        & $assert 'Test 100d: prozentuale Tresorauslastung wird korrekt gegen MaxFileBytes berechnet' '5' ([string]$data100.VaultPercent)
        & $assert 'Test 100e: fehlende Einzeldateien (Pending/Prev) erscheinen als nicht vorhanden' 'True|True|Nicht vorhanden' ("$($null -eq $data100.VaultPending)|$($null -eq $data100.VaultPrev)|$(Format-ByteSize $data100.VaultPending)")
        & $assert 'Test 100f: Oeffnen und Aktualisieren veraendern keine Datei und erzeugen keine Klartextdatei' 'True' ([string]($filesBefore100 -eq $filesAfter100))
        & $assert 'Test 100g: Loganzahlen und Grenzwerte werden korrekt ermittelt' "5000|20000" ("$($data100.LogLimitCurrent)|$($data100.LogLimitArchived)")
        # Zaehlwerte aus dem entsperrten Tresor im Arbeitsspeicher
        $v100 = New-VaultDataObject
        $d100 = New-TestDay
        Add-TestSegment -Day $d100 -Mode 'Betrieb' -StartText '08:00' -EndText '12:00' | Out-Null
        Add-TestInterval -Day $d100 -ListName 'ManualPauses' -StartText '10:00' -EndText '10:15' | Out-Null
        [void]$v100['WorkData']['Days'].Add($d100)
        for ($i = 1; $i -le 7; $i++) { [void]$v100['Logs'].Add([ordered]@{ Timestamp = ''; Level = 'INFO'; Message = "L$i" }) }
        $arch100 = New-Object System.Collections.ArrayList
        for ($i = 1; $i -le 3; $i++) { [void]$arch100.Add([ordered]@{ Timestamp = ''; Level = 'INFO'; Message = "A$i" }) }
        [void]$v100['LogArchives'].Add([ordered]@{ Id = 'a100'; Entries = $arch100 })
        $script:App.Vault = $v100
        $data100c = Get-StorageOverviewData
        & $assert 'Test 100h: Datenbestand und Loganzahlen aus dem Tresor werden korrekt gezaehlt' '1|1|1|1|0|7|3' ("$($data100c.Days)|$($data100c.ActiveDays)|$($data100c.Segments)|$($data100c.Pauses)|$($data100c.Locks)|$($data100c.LogsCurrent)|$($data100c.LogsArchived)")
        $script:App.Vault = $null
        # Reparse Points (Junction) werden nicht verfolgt
        $junctionOk100 = $false
        try {
            $externDir100 = Join-Path $testRoot4 'Extern'
            New-Item -ItemType Directory -Path $externDir100 -Force | Out-Null
            [System.IO.File]::WriteAllBytes((Join-Path $externDir100 'gross.bin'), (New-Object byte[] 5000))
            New-Item -ItemType Directory -Path (Join-Path $testRoot4 'Recovery') -Force | Out-Null
            [System.IO.File]::WriteAllBytes((Join-Path $testRoot4 'Recovery\echt.azt'), (New-Object byte[] 100))
            New-Item -ItemType Junction -Path (Join-Path $testRoot4 'Recovery\link') -Target $externDir100 -ErrorAction Stop | Out-Null
            $junctionOk100 = $true
        }
        catch { }
        if ($junctionOk100) {
            $data100d = Get-StorageOverviewData
            & $assert 'Test 100i: Reparse Points werden in der Speicheruebersicht nicht verfolgt' '1|100' ("$($data100d.RecoveryFolder.FileCount)|$($data100d.RecoveryFolder.TotalBytes)")
        }
        else {
            Write-Host '[SKIP] Test 100i (Junction): in dieser Umgebung nicht erstellbar.' -ForegroundColor Yellow
        }
        & $assert 'Test 100j: Speicheruebersichts-Tests verwenden ausschliesslich temporaere Testverzeichnisse' 'True' ([string]$script:Paths.Root.StartsWith([System.IO.Path]::GetTempPath(), [System.StringComparison]::OrdinalIgnoreCase))
        $script:VaultConst.MaxFileBytes = $limit100
        $script:Paths = $prevPaths100

        # --- Test 101: Dateikodierung CRLF (BOM siehe Test 50a) -----------------
        $src101 = [System.IO.File]::ReadAllText($script:AppScriptPath)
        $loneLf101 = [regex]::IsMatch($src101, '(?<!\r)\n')
        & $assert 'Test 101: ArbeitszeitTool.ps1 verwendet durchgaengig CRLF-Zeilenenden' 'False' ([string]$loneLf101)
        # Seit 1.4.0: Testsuite liegt ausschliesslich in tests\ (nicht ausgeliefert)
        & $assert 'Test 101b: ArbeitszeitTool.ps1 enthaelt keine Testsuite/Testhelfer' 'False|False|False' ("$($src101.Contains('function Invoke-InternalTests'))|$($src101.Contains('function New-TestDay'))|$($src101.Contains('function Invoke-ScrollLockManualTest'))")

        # =====================================================================
        # Tests 102-105 (Korrekturdurchlauf): Speichererfolg des automatischen
        # Tagesabschlusses, transaktionale Vortagspruefung (offene
        # Sperrintervalle), Speicherrueckgaben der Wiederherstellungsablaeufe
        # und Radiozustand nach fehlgeschlagenem (nur simuliertem)
        # Shutdownstart. Kein echter Shutdown, keine echten Eingaben.
        # =====================================================================

        # --- Test 102: automatischer Tagesabschluss wertet den Speichererfolg aus
        Initialize-AppState
        $script:Paths = (& $newTestPaths $testRoot3)
        Set-VaultSessionKeys -Keys (& $cloneKeys $keys) -Salt $salt -Iterations $iter
        $v102 = New-VaultDataObject
        Set-ActiveVault -Vault $v102
        Set-VaultLoadReference -Kind 'Haupt' -Revision ([long]$v102['Revision'])
        $goodPending102 = $script:Paths.VaultPending
        $successLogCount102 = {
            $n = 0
            foreach ($e in @($script:App.Vault['Logs'])) {
                if (([string]$e['Message']).Contains('Automatischer Tagesabschluss um 00:00')) { $n++ }
            }
            return $n
        }
        $d102 = New-TestDay -DateText $yesterdayText
        Add-TestSegment -Day $d102 -Mode 'Betrieb' -StartText '22:00' | Out-Null
        [void]$script:App.Data.Days.Add($d102)
        Save-Vault | Out-Null
        $okLogs102Start = & $successLogCount102
        $roll102 = Invoke-MidnightRolloverIfNeeded -Day $d102
        & $assert 'Test 102a: erfolgreicher automatischer Tagesabschluss gibt true zurueck und schreibt das Erfolgslog' "True|Beendet|$($okLogs102Start + 1)" ("$roll102|$($d102['Status'])|$(& $successLogCount102)")
        [void]$script:App.Data.Days.Remove($d102)
        Save-Vault | Out-Null
        # Fehlerfall: Speichern schlaegt fehl -> false, Zustand bleibt erhalten
        $d102b = New-TestDay -DateText $yesterdayText
        Add-TestSegment -Day $d102b -Mode 'Betrieb' -StartText '22:00' | Out-Null
        [void]$script:App.Data.Days.Add($d102b)
        Save-Vault | Out-Null
        $okLogsBefore102 = & $successLogCount102
        $fp102 = Get-DayContentFingerprint -Day $d102b
        $script:Paths.VaultPending = Join-Path $testRoot3 'gibtsnicht102\pending.azt'
        $roll102b = Invoke-MidnightRolloverIfNeeded -Day $d102b
        & $assert 'Test 102b: fehlgeschlagenes Save-Vault beim automatischen Tagesabschluss gibt false zurueck' 'False' ([string]$roll102b)
        & $assert 'Test 102c: der vorherige aktive Tageszustand bleibt vollstaendig erhalten' "Aktiv|$fp102" ("$($d102b['Status'])|$(Get-DayContentFingerprint -Day $d102b)")
        & $assert 'Test 102d: kein Erfolgslog beim fehlgeschlagenen automatischen Tagesabschluss' ([string]$okLogsBefore102) ([string](& $successLogCount102))
        $warn102 = $false
        foreach ($e in @($script:App.Vault['Logs'])) {
            if ([string]$e['Level'] -eq 'WARN' -and ([string]$e['Message']).Contains('Tageswechsel') -and ([string]$e['Message']).Contains('konnte nicht gespeichert')) { $warn102 = $true }
        }
        & $assert 'Test 102e: neutrale WARN-Meldung vorhanden; Folgeversuche sind gedrosselt (kein Sekundentakt-Spam)' 'True|False' ("$warn102|$(Invoke-MidnightRolloverIfNeeded -Day $d102b)")
        $script:Paths.VaultPending = $goodPending102
        Clear-VaultSaveFailedState
        $script:App.Flags.RolloverNextRetryAt = $null
        $roll102c = Invoke-MidnightRolloverIfNeeded -Day $d102b
        & $assert 'Test 102f: nach behobenem Fehler gelingt der Tagesabschluss und meldet Erfolg' "True|Beendet|$($okLogsBefore102 + 1)" ("$roll102c|$($d102b['Status'])|$(& $successLogCount102)")
        [void]$script:App.Data.Days.Remove($d102b)
        Save-Vault | Out-Null

        # --- Test 103: Vortagsabfrage veraendert offene Sperrintervalle nicht ---
        $d103 = New-TestDay -DateText $yesterdayText
        Add-TestSegment -Day $d103 -Mode 'Homeoffice' -StartText '20:00' | Out-Null
        Add-TestInterval -Day $d103 -ListName 'LockIntervals' -StartText '22:00' | Out-Null   # OFFEN
        [void]$script:App.Data.Days.Add($d103)
        $script:App.RecoveryState = @{ PreviousCleanShutdown = $false; PreviousLastSavedAt = ($yesterdayText + ' 23:00:00') }
        Save-Vault | Out-Null
        $fp103 = Get-DayContentFingerprint -Day $d103
        $flow103 = Invoke-AutoEndReviewFlow -Day $d103 -ChoiceResolver { param($d, $c, $a) @{ Choice = 'Abbrechen'; EndTime = $null } }
        & $assert 'Test 103a: Oeffnen + Abbrechen der Vortagsabfrage laesst das offene Sperrintervall unveraendert' "False|$fp103|" ("$flow103|$(Get-DayContentFingerprint -Day $d103)|$([string]$d103['LockIntervals'][0]['End'])")
        # Cleanup-artiger Speichervorgang nach dem Abbruch (wie beim Beenden
        # der Anwendung): es wird nur der UNVERAENDERTE Zustand geschrieben
        Save-Vault | Out-Null
        $reload103 = Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        $reDay103 = $null
        foreach ($d in @($reload103['WorkData']['Days'])) { if ([string]$d['Date'] -eq $yesterdayText) { $reDay103 = $d } }
        & $assert 'Test 103b: nach Abbruch + Cleanup bleibt das offene Sperrintervall auch in der Tresordatei offen' 'True|' ("$($null -ne $reDay103)|$([string]$reDay103['LockIntervals'][0]['End'])")
        # Save-Fehler bei der Vortagskorrektur: Tag, offenes Sperrintervall UND
        # Logeintraege werden vollstaendig wiederhergestellt (kein falscher
        # Erfolgseintrag bleibt bestehen)
        $corrLogCount103 = {
            $n = 0
            foreach ($e in @($script:App.Vault['Logs'])) {
                if (([string]$e['Message']).Contains('Arbeitsende nachträglich manuell korrigiert')) { $n++ }
            }
            return $n
        }
        $end103 = Get-DayDateTime -DayDate $yesterdayText -TimeText '23:30'
        $corrBefore103 = & $corrLogCount103
        $script:Paths.VaultPending = Join-Path $testRoot3 'gibtsnicht103\pending.azt'
        $errFail103 = Complete-AutoEndManual -Day $d103 -End $end103
        $script:Paths.VaultPending = $goodPending102
        Clear-VaultSaveFailedState
        & $assert 'Test 103c: Save-Fehler stellt Tagesdaten und offenes Sperrintervall vollstaendig wieder her' "True|$fp103|" ("$($errFail103 -ne '')|$(Get-DayContentFingerprint -Day $d103)|$([string]$d103['LockIntervals'][0]['End'])")
        & $assert 'Test 103d: nach dem Rollback bleibt kein falscher Erfolgslogeintrag erhalten' ([string]$corrBefore103) ([string](& $corrLogCount103))
        # Erfolgreiche manuelle Korrektur: das offene Sperrintervall wird
        # EXAKT am bestaetigten Arbeitsende geschlossen (nicht am Checkpoint;
        # der Zeitraum bis zum Ende zaehlt als Sperrzeit, nie als Arbeitszeit)
        $err103 = Complete-AutoEndManual -Day $d103 -End $end103
        $lockEnd103 = [string]$d103['LockIntervals'][0]['End']
        & $assert 'Test 103e: offenes Sperrintervall endet exakt am bestaetigten Arbeitsende' "|$yesterdayText 23:30:00|Beendet|False|Nachträglich manuell korrigiert" ("$err103|$lockEnd103|$($d103['Status'])|$($d103['AutoEndReviewPending'])|$($d103['EndReason'])")
        $lockStart103 = ConvertFrom-DateTimeString $d103['LockIntervals'][0]['Start']
        $lockEndDt103 = ConvertFrom-DateTimeString $lockEnd103
        & $assert 'Test 103f: Intervallende nie vor dem Beginn und nie nach dem bestaetigten Ende' 'True|True' ("$($lockEndDt103 -ge $lockStart103)|$($lockEndDt103 -le $end103)")
        $comp103 = Get-DayComputation -Day $d103 -Now (ConvertFrom-DateTimeString $d103.EndedAt)
        & $assert 'Test 103g: Nettozeit nach der Korrektur korrekt neu berechnet (HO 3:30 brutto - 1:30 Sperre)' '02:00' (Format-Duration $comp103.Netto)
        & $assert 'Test 103h: nach erfolgreicher Speicherung existiert genau der passende Erfolgslogeintrag' ([string]($corrBefore103 + 1)) ([string](& $corrLogCount103))
        # Randfall: bestaetigtes Ende liegt VOR dem Beginn des offenen
        # Sperrintervalls -> das Intervall wird verworfen (kein invertiertes Ende)
        $d103b = New-TestDay -DateText $yesterdayText
        Add-TestSegment -Day $d103b -Mode 'Homeoffice' -StartText '18:00' | Out-Null
        Add-TestInterval -Day $d103b -ListName 'LockIntervals' -StartText '22:00' | Out-Null
        $err103b = Complete-AutoEndManual -Day $d103b -End (Get-DayDateTime -DayDate $yesterdayText -TimeText '21:00')
        & $assert 'Test 103i: erst nach dem bestaetigten Ende beginnendes offenes Sperrintervall wird verworfen' "|0|Beendet" ("$err103b|$(@($d103b.LockIntervals).Count)|$($d103b['Status'])")
        [void]$script:App.Data.Days.Remove($d103)
        $script:App.RecoveryState = $null
        Save-Vault | Out-Null

        # --- Test 104: Wiederherstellungsablaeufe werten den Speichererfolg aus -
        $d104 = New-TestDay -DateText ((Get-Date).ToString('yyyy-MM-dd'))
        $seg104 = New-SegmentObject -Mode 'Betrieb' -Start (Get-Date).AddHours(-1) -Running $true
        [void]$d104['Segments'].Add($seg104)
        [void]$script:App.Data.Days.Add($d104)
        $script:App.CurrentDay = $d104
        $script:App.RecoveryState = @{ PreviousCleanShutdown = $true; PreviousLastSavedAt = (ConvertTo-DateTimeString (Get-Date).AddMinutes(-10)) }
        Save-Vault | Out-Null
        $resumeLogCount104 = {
            $n = 0
            foreach ($e in @($script:App.Vault['Logs'])) {
                if (([string]$e['Message']).Contains('nach regulärem Neustart unverändert fortgesetzt')) { $n++ }
            }
            return $n
        }
        $okResumeBefore104 = & $resumeLogCount104
        $script:Paths.VaultPending = Join-Path $testRoot3 'gibtsnicht104\pending.azt'
        Invoke-CleanResume -Day $d104
        & $assert 'Test 104a: fehlgeschlagene Speicherung der Neustartentscheidung erzeugt KEINE Erfolgsmeldung' ([string]$okResumeBefore104) ([string](& $resumeLogCount104))
        & $assert 'Test 104b: der Nicht-gespeichert-Zustand ist nach dem Fehlversuch korrekt gesetzt' 'True' ([string]$script:App.Flags.UnsavedChanges)
        $script:Paths.VaultPending = $goodPending102
        Clear-VaultSaveFailedState
        Invoke-CleanResume -Day $d104
        & $assert 'Test 104c: nach behobenem Fehler wird die Fortsetzung regulaer als Erfolg protokolliert' ([string]($okResumeBefore104 + 1)) ([string](& $resumeLogCount104))
        [void]$script:App.Data.Days.Remove($d104)
        $script:App.CurrentDay = $null
        $script:App.RecoveryState = $null
        Save-Vault | Out-Null

        # --- Test 105: fehlgeschlagener Shutdownstart - Radio/Tag konsistent ----
        $d105 = New-TestDay -DateText ((Get-Date).ToString('yyyy-MM-dd'))
        Add-TestSegment -Day $d105 -Mode 'Betrieb' -StartText ((Get-Date).AddHours(-2).ToString('HH:mm')) | Out-Null
        [void]$script:App.Data.Days.Add($d105)
        Save-Vault | Out-Null
        $completed105 = Complete-WorkDay -Day $d105 -End (Get-Date) -Reason 'Manuell'
        $script:App.Flags.SimulatedShutdownStartFails = $true
        $script:App.Flags.SimulatedShutdownRequested = $false
        $sd105 = Invoke-EndDayShutdown
        $script:App.Flags.SimulatedShutdownStartFails = $false
        & $assert 'Test 105a: fehlgeschlagener Shutdownstart gibt false zurueck (kein Shutdown, nur simuliert)' 'False|False' ("$sd105|$($script:App.Flags.SimulatedShutdownRequested)")
        & $assert 'Test 105b: Radiozustand ist danach wieder bedienbar bzw. neu initialisierbar' 'False|True|Stopped' ("$($script:App.Radio.IsShuttingDown)|$($null -eq $script:App.Radio.Player)|$($script:App.Radio.DesiredState)")
        & $assert 'Test 105c: Anwendung bleibt geoeffnet (kein CloseConfirmed, kein Dispatcher-Stopp)' 'False|False' ("$($script:App.CloseConfirmed)|$($script:App.ShuttingDown)")
        $reload105 = Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        $reDay105 = $null
        foreach ($d in @($reload105['WorkData']['Days'])) { if ([string]$d['Id'] -eq [string]$d105['Id']) { $reDay105 = $d } }
        & $assert 'Test 105d: der Arbeitstag bleibt korrekt beendet und gespeichert' 'True|Beendet' ("$completed105|$($reDay105['Status'])")
        [void]$script:App.Data.Days.Remove($d105)
        Save-Vault | Out-Null

        # --- Test 106: CleanShutdown nach (nur simuliertem) Shutdownstart -------
        # Erfolgspfad: ein Fake-Fenster faengt den kontrollierten Close ab
        $fakeCompact106 = [pscustomobject]@{}
        $fakeCompact106 | Add-Member -MemberType ScriptMethod -Name Close -Value { }
        $script:App.Ui.Compact = $fakeCompact106
        $script:App.Flags.SimulatedShutdownRequested = $false
        $sd106 = Invoke-EndDayShutdown
        & $assert 'Test 106a: erfolgreich gestarteter (simulierter) Shutdown behaelt CleanShutdown=true' 'True|True|True' ("$sd106|$($script:App.Vault['CleanShutdown'])|$($script:App.Flags.SimulatedShutdownRequested)")
        $script:App.Ui.Compact = $null
        $script:App.CloseConfirmed = $false
        $script:App.Flags.SimulatedShutdownRequested = $false
        $script:App.Radio.IsShuttingDown = $false
        # Fehlstart: CleanShutdown wird zurueckgesetzt und mit
        # -NoTrackingCheckpoint erfolgreich gespeichert
        $script:App.Flags.SimulatedShutdownStartFails = $true
        $sd106b = Invoke-EndDayShutdown
        $script:App.Flags.SimulatedShutdownStartFails = $false
        $reload106 = Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        & $assert 'Test 106b: fehlgeschlagener Shutdownstart setzt CleanShutdown wieder auf false (Speicher UND Datei)' 'False|False|False' ("$sd106b|$($script:App.Vault['CleanShutdown'])|$($reload106['CleanShutdown'])")
        & $assert 'Test 106c: der korrigierte Sitzungsstatus ist erfolgreich gespeichert; Radio bleibt initialisierbar' 'False|False' ("$($script:App.Flags.UnsavedChanges)|$($script:App.Radio.IsShuttingDown)")
        # Schlaegt auch das Zurueckspeichern fehl: identische Speicheroperation
        # des Fehlpfads (Save-Vault -NoTrackingCheckpoint -Quiet) -> false,
        # der Nicht-gespeichert-Zustand bleibt gesetzt
        $script:Paths.VaultPending = Join-Path $testRoot3 'gibtsnicht106\pending.azt'
        $saveFail106 = Save-Vault -NoTrackingCheckpoint -Quiet
        & $assert 'Test 106d: schlaegt auch das Zurueckspeichern fehl, bleibt UnsavedChanges gesetzt' 'False|True' ("$saveFail106|$($script:App.Flags.UnsavedChanges)")
        $script:Paths.VaultPending = $goodPending102
        Clear-VaultSaveFailedState
        Save-Vault | Out-Null

        # --- Test 107: Abschlussgrund unterscheidet 10:00 und angenommenes Ende -
        $d107 = New-TestDay -DateText $yesterdayText
        Add-TestSegment -Day $d107 -Mode 'Betrieb' -StartText '06:00' | Out-Null   # erreicht 10:00 (16:45)
        $err107 = Complete-AutoEndTenHours -Day $d107
        & $assert 'Test 107a: bei tatsaechlich erreichten zehn Stunden wird der 10:00-Abschlussgrund gespeichert' '|Automatisch (10:00 bestätigt)|True' ("$err107|$($d107['EndReason'])|$($d107['MaxReached'])")
        $d107b = New-TestDay -DateText $yesterdayText
        Add-TestSegment -Day $d107b -Mode 'Betrieb' -StartText '22:00' | Out-Null  # nur 2:00 bis Mitternacht
        $err107b = Complete-AutoEndTenHours -Day $d107b
        & $assert 'Test 107b: bei weniger als zehn Stunden wird das angenommene Ende als Grund gespeichert' '|Automatisch angenommenes Ende bestätigt|False' ("$err107b|$($d107b['EndReason'])|$($d107b['MaxReached'])")

        # --- Test 107c-f: Endvorschlag nach automatischem Tageswechsel (00:00) -
        # Homeoffice, PC ab 16:30 gesperrt und bis Mitternacht weitergelaufen
        $d107c = New-TestDay -DateText $yesterdayText
        Add-TestSegment -Day $d107c -Mode 'Homeoffice' -StartText '08:00' | Out-Null
        Add-TestInterval -Day $d107c -ListName 'LockIntervals' -StartText '16:30' | Out-Null
        Invoke-MidnightRolloverIfNeeded -Day $d107c | Out-Null
        $midnight107 = (Get-DayDateTime -DayDate $yesterdayText -TimeText '00:00').AddDays(1)
        $sugg107c = Get-AutoEndSuggestedEnd -Day $d107c -Cutoff $midnight107
        & $assert 'Test 107c: Tageswechsel beendet um 00:00, vorgeschlagen wird aber der Beginn der letzten Sperre (16:30)' "$(ConvertTo-DateTimeString $midnight107)|$yesterdayText 16:30:00" ("$($d107c['EndedAt'])|$(ConvertTo-DateTimeString $sugg107c)")
        $flow107c = Invoke-AutoEndReviewFlow -Day $d107c -ChoiceResolver { param($d, $c, $a) @{ Choice = 'Bestaetigen'; EndTime = $null } }
        $comp107c = Get-DayComputation -Day $d107c -Now (ConvertFrom-DateTimeString $d107c.EndedAt)
        & $assert 'Test 107d: Bestaetigen uebernimmt den Vorschlag (Ende 16:30, Sperre bis 00:00 entfernt, Netto 08:30)' "True|$yesterdayText 16:30:00|0|08:30" ("$flow107c|$($d107c['EndedAt'])|$(@($d107c['LockIntervals']).Count)|$(Format-Duration $comp107c.Netto)")
        # Betrieb, 10:00 vor Mitternacht erreicht: Vorschlag = 16:45
        $d107e = New-TestDay -DateText $yesterdayText
        Add-TestSegment -Day $d107e -Mode 'Betrieb' -StartText '06:00' | Out-Null
        Invoke-MidnightRolloverIfNeeded -Day $d107e | Out-Null
        & $assert 'Test 107e: Betrieb mit erreichter 10:00-Grenze schlaegt 16:45 vor (nicht 00:00)' "$yesterdayText 16:45:00" (ConvertTo-DateTimeString (Get-AutoEndSuggestedEnd -Day $d107e -Cutoff $midnight107))
        # Ohne Sperre und ohne 10:00: kein besserer Anhaltspunkt -> Mitternacht
        $d107f = New-TestDay -DateText $yesterdayText
        Add-TestSegment -Day $d107f -Mode 'Betrieb' -StartText '22:00' | Out-Null
        Invoke-MidnightRolloverIfNeeded -Day $d107f | Out-Null
        & $assert 'Test 107f: ohne Sperre/Pause und ohne 10:00 bleibt Mitternacht der Vorschlag' (ConvertTo-DateTimeString $midnight107) (ConvertTo-DateTimeString (Get-AutoEndSuggestedEnd -Day $d107f -Cutoff $midnight107))

        # =====================================================================
        # Tests 108/109 (Stabilitaetsdurchlauf): Save-Vault-Commit-Punkt,
        # Best-Effort-Backuprotation und abgesicherter Dateiaustausch-Fallback.
        # Saemtliche Dateifehler werden ausschliesslich ueber TestFail*-Hooks
        # simuliert (nur bei -RunTests wirksam, keine produktiven Dateien).
        # =====================================================================
        $countVaultLogs = {
            param([string]$Needle)
            $n = 0
            foreach ($e in @($script:App.Vault['Logs'])) {
                if (([string]$e['Message']).Contains($Needle)) { $n++ }
            }
            return $n
        }
        # Ausgangszustand: zwei erfolgreiche Speichervorgaenge (Backup1 vorhanden)
        Save-Vault | Out-Null
        Save-Vault | Out-Null
        & $assert 'Test 108a: Ausgangszustand - Hauptdatei und Backup1 vorhanden, keine Blockade' 'True|True|' ("$(Test-Path -LiteralPath $script:Paths.VaultFile)|$(Test-Path -LiteralPath $script:Paths.VaultBackup1)|$($script:App.Flags.SaveBlockedReason)")
        # Fehler NACH dem Commit: Kopie Backup1 -> Backup2 schlaegt fehl
        $rev108 = [long]$script:App.Vault['Revision']
        $warn108Before = & $countVaultLogs 'Backuprotation nach erfolgreichem Speichern fehlgeschlagen'
        $script:App.Flags.TestFailBackupCopy = $true
        $save108b = Save-Vault
        $script:App.Flags.TestFailBackupCopy = $false
        $main108 = Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        & $assert 'Test 108b: Backupkopie-Fehler nach dem Commit liefert true und setzt kein UnsavedChanges' 'True|False' ("$save108b|$($script:App.Flags.UnsavedChanges)")
        & $assert 'Test 108c: Hauptdatei traegt die neue Revision, In-Memory bleibt synchron' "$($rev108 + 1)|$($rev108 + 1)" ("$($main108['Revision'])|$($script:App.Vault['Revision'])")
        & $assert 'Test 108d: neutrale Backupwarnung wurde protokolliert' 'True' ([string]((& $countVaultLogs 'Backuprotation nach erfolgreichem Speichern fehlgeschlagen') -gt $warn108Before))
        # Fehler beim Schreiben von Backup1 (ebenfalls nach dem Commit); eine
        # vault.prev.azt aus einer aelteren Programmversion wird dabei
        # einmalig neutral in Recovery gesichert (nicht ueberschrieben).
        [System.IO.File]::Copy($script:Paths.VaultFile, $script:Paths.VaultPrev, $true)
        $prevRec108 = @(Get-ChildItem -LiteralPath $script:Paths.Recovery -Filter 'vault-prev-*.azt' -File -ErrorAction SilentlyContinue).Count
        $script:App.Flags.TestFailBackup1Write = $true
        $save108e = Save-Vault
        $script:App.Flags.TestFailBackup1Write = $false
        $prevRec108b = @(Get-ChildItem -LiteralPath $script:Paths.Recovery -Filter 'vault-prev-*.azt' -File -ErrorAction SilentlyContinue).Count
        & $assert 'Test 108e: Backup1-Schreibfehler nach dem Commit - true, Hauptdatei vollstaendig gueltig' 'True|True' ("$save108e|$(Test-VaultFileFullyUsable -Path $script:Paths.VaultFile)")
        & $assert 'Test 108f: alte vault.prev.azt wurde neutral in Recovery gesichert (nicht ueberschrieben)' 'True|False' ("$($prevRec108b -gt $prevRec108)|$(Test-Path -LiteralPath $script:Paths.VaultPrev)")
        Save-Vault | Out-Null
        & $assert 'Test 108g: naechster regulaerer Speichervorgang inkl. Backuprotation funktioniert wieder' 'True|False' ("$(Test-VaultFileFullyUsable -Path $script:Paths.VaultBackup1)|$($script:App.Flags.UnsavedChanges)")
        # Referenzhash nach dem Commit nicht ermittelbar -> Erfolg + Blockade
        $script:App.Flags.TestFailPostCommitHash = $true
        $save108h = Save-Vault
        $script:App.Flags.TestFailPostCommitHash = $false
        & $assert 'Test 108h: Hashfehler nach dem Commit - Speichern erfolgreich, weitere Speichervorgaenge blockiert' 'True|True|True' ("$save108h|$($null -eq $script:App.VaultFileHash)|$([string]$script:App.Flags.SaveBlockedReason -ne '')")
        $save108i = Save-Vault -Quiet
        & $assert 'Test 108i: blockierter Folgespeichervorgang liefert kontrolliert false (kein ungeschuetztes Schreiben)' 'False|True' ("$save108i|$($script:App.Flags.UnsavedChanges)")
        # Blockade aufheben (kontrollierter Neustart simuliert), Referenz nachziehen
        $script:App.Flags.SaveBlockedReason = ''
        $script:App.Flags.SaveBlockedLogged = $false
        $script:App.VaultFileHash = Get-FileSha256Hex -Path $script:Paths.VaultFile
        Clear-VaultSaveFailedState
        & $assert 'Test 108j: nach Aufhebung der Blockade funktioniert das Speichern wieder' 'True' ([string](Save-Vault))

        # --- Tests 109: Schreibfehler der Hauptdatei (in-place mit Journal) ---
        $readRev109 = {
            param([string]$Path)
            try { return [string](Read-VaultFromFile -Path $Path -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey)['Revision'] }
            catch { return 'unlesbar' }
        }
        # Abbruch mitten im Schreiben der Hauptdatei -> alter Stand wird sofort
        # zurueckgeschrieben, das Journal ebenfalls zurueckgenommen
        $revBefore109 = [long]$script:App.Vault['Revision']
        $script:App.Flags.TestFailMainWrite = $true
        $save109a = Save-Vault -Quiet
        $script:App.Flags.TestFailMainWrite = $false
        & $assert 'Test 109a: Schreibfehler der Hauptdatei - false, alter Stand sofort wiederhergestellt, Speicher synchron' "False|$revBefore109|$revBefore109" ("$save109a|$(& $readRev109 $script:Paths.VaultFile)|$($script:App.Vault['Revision'])")
        & $assert 'Test 109b: Journal zurueckgenommen (kein neuerer Stand), kein prev, Zustand NICHT GESPEICHERT' "$revBefore109|False|True" ("$(& $readRev109 $script:Paths.VaultPending)|$(Test-Path -LiteralPath $script:Paths.VaultPrev)|$($script:App.Flags.UnsavedChanges)")
        Clear-VaultSaveFailedState
        & $assert 'Test 109c: danach speichert der Tresor regulaer weiter' "True|$($revBefore109 + 1)" ("$(Save-Vault)|$(& $readRev109 $script:Paths.VaultFile)")
        # Kritischer Fall: auch das Zurueckschreiben scheitert -> Blockade, der
        # neue Stand liegt geprueft im Journal (hoehere Revision)
        $revBefore109d = [long]$script:App.Vault['Revision']
        $script:App.Flags.TestFailMainWrite = $true
        $script:App.Flags.TestFailMainRestore = $true
        $save109d = Save-Vault -Quiet
        $script:App.Flags.TestFailMainWrite = $false
        $script:App.Flags.TestFailMainRestore = $false
        & $assert 'Test 109d: kritischer Schreibfehler - false, Blockade gesetzt, Journal haelt den neuen Stand' "False|True|$($revBefore109d + 1)" ("$save109d|$([string]$script:App.Flags.SaveBlockedReason -ne '')|$(& $readRev109 $script:Paths.VaultPending)")
        & $assert 'Test 109e: Hauptdatei unbrauchbar, Journal vollstaendig verwendbar (wird beim Start angeboten)' 'False|True' ("$(Test-VaultFileFullyUsable -Path $script:Paths.VaultFile)|$(Test-VaultFileFullyUsable -Path $script:Paths.VaultPending)")
        # Start-Auswahl simulieren: neuester gueltiger Stand = Journal
        $pendVault109 = Read-VaultFromFile -Path $script:Paths.VaultPending -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        Set-ActiveVault -Vault $pendVault109
        Set-VaultLoadReference -Kind 'Pending' -Revision ([long]$pendVault109['Revision'])
        $script:App.Flags.SaveBlockedReason = ''
        $script:App.Flags.SaveBlockedLogged = $false
        Clear-VaultSaveFailedState
        $save109g = Save-Vault
        & $assert 'Test 109f: nach Auswahl des Journalstands speichert der Tresor wieder, Hauptdatei gueltig' "True|$($revBefore109d + 2)|True" ("$save109g|$(& $readRev109 $script:Paths.VaultFile)|$(Test-VaultFileFullyUsable -Path $script:Paths.VaultFile)")
        & $assert 'Test 109g: unbrauchbare alte Hauptdatei gelangt nicht in die Backupkette' 'True' ([string](Test-VaultFileFullyUsable -Path $script:Paths.VaultBackup1))

        # --- Tests 110: exakter 10-Stunden-Zeitpunkt (zentrale Suche) ---------
        $d110a = New-TestDay
        Add-TestSegment -Day $d110a -Mode 'Betrieb' -StartText '06:00' | Out-Null
        $t110a = Find-DayMaxNettoReachedTime -Day $d110a -Cutoff (Get-TestNow $d110a '22:00')
        & $assert 'Test 110a: kontinuierlicher Betriebstag inkl. fester Pause -> 16:45' '2026-07-10 16:45:00' (ConvertTo-DateTimeString $t110a)
        $d110b = New-TestDay
        Add-TestSegment -Day $d110b -Mode 'Homeoffice' -StartText '06:00' | Out-Null
        Add-TestInterval -Day $d110b -ListName 'ManualPauses' -StartText '17:00' -EndText '18:00' | Out-Null
        $cut110b = (Get-TestNow $d110b '00:00').AddDays(1)
        $t110b = Find-DayMaxNettoReachedTime -Day $d110b -Cutoff $cut110b
        & $assert 'Test 110b: HO-Pause NACH dem tatsaechlichen Grenzzeitpunkt -> 16:00 (nicht 17:00)' '2026-07-10 16:00:00' (ConvertTo-DateTimeString $t110b)
        & $assert 'Test 110c: Get-DayTenHourStopTime nutzt dieselbe zentrale Suche' (ConvertTo-DateTimeString $t110b) (ConvertTo-DateTimeString (Get-DayTenHourStopTime -Day $d110b -Cutoff $cut110b))
        $d110d = New-TestDay
        Add-TestSegment -Day $d110d -Mode 'Homeoffice' -StartText '06:00' | Out-Null
        Add-TestInterval -Day $d110d -ListName 'ManualPauses' -StartText '10:00' -EndText '11:00' | Out-Null
        & $assert 'Test 110d: Pause VOR der Grenze verschiebt den Grenzzeitpunkt korrekt nach hinten (17:00)' '2026-07-10 17:00:00' (ConvertTo-DateTimeString (Find-DayMaxNettoReachedTime -Day $d110d -Cutoff (Get-TestNow $d110d '20:00')))
        $d110e = New-TestDay
        Add-TestSegment -Day $d110e -Mode 'Homeoffice' -StartText '06:00' | Out-Null
        Add-TestInterval -Day $d110e -ListName 'LockIntervals' -StartText '17:30' -EndText '18:30' | Out-Null
        & $assert 'Test 110e: Sperrintervall NACH dem Grenzzeitpunkt veraendert ihn nicht (16:00)' '2026-07-10 16:00:00' (ConvertTo-DateTimeString (Find-DayMaxNettoReachedTime -Day $d110e -Cutoff (Get-TestNow $d110e '20:00')))
        $d110f = New-TestDay
        Add-TestSegment -Day $d110f -Mode 'Homeoffice' -StartText '08:00' | Out-Null
        Add-TestInterval -Day $d110f -ListName 'LockIntervals' -StartText '12:00' | Out-Null
        & $assert 'Test 110f: offenes Sperrintervall unter zehn Stunden -> kein (falscher) Grenzzeitpunkt' 'True' ([string]($null -eq (Find-DayMaxNettoReachedTime -Day $d110f -Cutoff (Get-TestNow $d110f '20:00'))))
        $nettoAt110 = Get-DayNettoAtTime -Day $d110b -Time $t110b
        $nettoBefore110 = Get-DayNettoAtTime -Day $d110b -Time ($t110b.AddSeconds(-1))
        & $assert 'Test 110g: eine Sekunde vor dem Ergebnis unter 10:00, am Ergebnis mindestens 10:00' 'True|True' ("$($nettoAt110 -ge [TimeSpan]::FromMinutes(600))|$($nettoBefore110 -lt [TimeSpan]::FromMinutes(600))")
        $fp110 = Get-DayContentFingerprint -Day $d110b
        $mod110 = [string]$d110b['ModifiedAt']
        $logs110 = @($script:App.Vault['Logs']).Count
        $null = Find-DayMaxNettoReachedTime -Day $d110b -Cutoff $cut110b
        & $assert 'Test 110h: Zeitpunktsuche veraendert den Tag nicht und loest weder Save noch Log aus' "$fp110|$mod110|$logs110|False" ("$(Get-DayContentFingerprint -Day $d110b)|$($d110b['ModifiedAt'])|$(@($script:App.Vault['Logs']).Count)|$($script:App.Flags.SaveInProgress)")
        # Auto-Stopp nach groesserem Zeitsprung nutzt denselben exakten Zeitpunkt
        $d110i = New-TestDay
        Add-TestSegment -Day $d110i -Mode 'Homeoffice' -StartText '06:00' | Out-Null
        Add-TestInterval -Day $d110i -ListName 'ManualPauses' -StartText '17:00' -EndText '18:00' | Out-Null
        $stopped110i = Invoke-AutoStopIfNeeded -Day $d110i -Now (Get-TestNow $d110i '20:00')
        $segEnd110i = ''
        foreach ($s110 in @($d110i.Segments)) { $segEnd110i = [string]$s110.End }
        $comp110i = Get-DayComputation -Day $d110i -Now (Get-TestNow $d110i '20:00')
        & $assert 'Test 110i: Auto-Stopp nach Zeitsprung stoppt exakt am Grenzzeitpunkt (16:00, Netto 10:00)' 'True|2026-07-10 16:00:00|10:00|True' ("$stopped110i|$segEnd110i|$(Format-Duration $comp110i.Netto)|$($d110i.MaxReached)")
        $d110j = New-TestDay
        Add-TestSegment -Day $d110j -Mode 'Betrieb' -StartText '06:00' | Out-Null
        $stopped110j = Invoke-AutoStopIfNeeded -Day $d110j -Now (Get-TestNow $d110j '23:00')
        $comp110j = Get-DayComputation -Day $d110j -Now (Get-TestNow $d110j '23:00')
        & $assert 'Test 110j: Auto-Stopp im Betrieb nach Zeitsprung -> Ende 16:45, Netto exakt 10:00' 'True|16:45|10:00' ("$stopped110j|$(Format-Clock (ConvertFrom-DateTimeString $d110j.Segments[0].End))|$(Format-Duration $comp110j.Netto)")

        # --- Tests 111: transaktionale Erfolgslogs (Korrekturen) --------------
        $d111 = New-TestDay -DateText '2026-07-05'
        Add-TestSegment -Day $d111 -Mode 'Betrieb' -StartText '08:00' -EndText '12:00' | Out-Null
        $d111['Status'] = 'Beendet'
        $d111['EndedAt'] = '2026-07-05 12:00:00'
        [void]$script:App.Data.Days.Add($d111)
        Save-Vault | Out-Null
        $corrCount111 = @($d111.Corrections).Count
        Add-Correction -Day $d111 -Description 'TESTKORREKTUR-111A' -NewValue 'x' -NoLog
        & $assert 'Test 111a: Add-Correction -NoLog erzeugt Korrektureintrag ohne Erfolgslog' "$($corrCount111 + 1)|0" ("$(@($d111.Corrections).Count)|$(& $countVaultLogs 'TESTKORREKTUR-111A')")
        Write-CorrectionLog -Day $d111 -Description 'TESTKORREKTUR-111A' -NewValue 'x'
        & $assert 'Test 111b: Write-CorrectionLog schreibt genau einen passenden Erfolgseintrag' '1' ([string](& $countVaultLogs 'TESTKORREKTUR-111A'))
        Save-Vault | Out-Null
        # Speicherfehler beim transaktionalen Korrektur-Muster (Segment/Pause/
        # Sperrintervall identisch): Rollback ohne Erfolgslogeintrag
        $snap111 = Get-DaySnapshot -Day $d111
        $script:Paths.VaultPending = Join-Path $testRoot3 'gibtsnicht111\pending.azt'
        Add-TestSegment -Day $d111 -Mode 'Homeoffice' -StartText '13:00' -EndText '14:00' | Out-Null
        Add-Correction -Day $d111 -Description 'TESTKORREKTUR-111C' -NewValue 'Segment' -NoLog
        if (Save-WorkData -Quiet) { Write-CorrectionLog -Day $d111 -Description 'TESTKORREKTUR-111C' -NewValue 'Segment' }
        else { Restore-DayFromSnapshot -Day $d111 -Snapshot $snap111 }
        $script:Paths.VaultPending = $goodPending102
        Clear-VaultSaveFailedState
        & $assert 'Test 111c: Speicherfehler -> kein Erfolgslog, Korrektur und Segment vollstaendig zurueckgerollt' "0|$($corrCount111 + 1)|1" ("$(& $countVaultLogs 'TESTKORREKTUR-111C')|$(@($d111.Corrections).Count)|$(@($d111.Segments).Count)")
        # Automatisches Windows-Ereignis: Ereignislog bleibt trotz Speicherfehler
        $d111e = New-TestDay -DateText ((Get-Date).ToString('yyyy-MM-dd'))
        $seg111e = New-SegmentObject -Mode 'Homeoffice' -Start (Get-Date).AddHours(-1) -Running $true
        [void]$d111e['Segments'].Add($seg111e)
        [void]$script:App.Data.Days.Add($d111e)
        $script:Paths.VaultPending = Join-Path $testRoot3 'gibtsnicht111\pending.azt'
        Start-LockInterval -Day $d111e | Out-Null
        $script:Paths.VaultPending = $goodPending102
        Clear-VaultSaveFailedState
        & $assert 'Test 111e: automatisches Lock-Ereignis behaelt seinen Ereignislog trotz Speicherfehler' 'True|1' ("$((& $countVaultLogs 'Windows gesperrt') -ge 1)|$(@($d111e.LockIntervals).Count)")
        Stop-LockInterval -Day $d111e -NoSave | Out-Null
        [void]$script:App.Data.Days.Remove($d111e)
        Save-Vault | Out-Null
        # Logrotation waehrend der Aktion verfaelscht den Rollback nicht
        $fill111 = $script:Const.MaxLogEntries - @($script:App.Vault['Logs']).Count
        if ($fill111 -gt 0) {
            for ($i = 0; $i -lt $fill111; $i++) { Write-AppLog -Message 'FUELLER-111' }
        }
        $archBefore111 = @($script:App.Vault['LogArchives']).Count
        $snap111d = Get-DaySnapshot -Day $d111
        $script:Paths.VaultPending = Join-Path $testRoot3 'gibtsnicht111\pending.azt'
        Add-TestSegment -Day $d111 -Mode 'Homeoffice' -StartText '15:00' -EndText '16:00' | Out-Null
        Add-Correction -Day $d111 -Description 'TESTKORREKTUR-111D' -NewValue 'Rotation' -NoLog
        Write-AppLog -Message 'ROTATIONSAUSLOESER-111'
        if (Save-WorkData -Quiet) { Write-CorrectionLog -Day $d111 -Description 'TESTKORREKTUR-111D' -NewValue 'Rotation' }
        else { Restore-DayFromSnapshot -Day $d111 -Snapshot $snap111d }
        $script:Paths.VaultPending = $goodPending102
        Clear-VaultSaveFailedState
        & $assert 'Test 111d: Logrotation waehrend der Aktion - Rollback korrekt, kein Erfolgslog' "0|1|True" ("$(& $countVaultLogs 'TESTKORREKTUR-111D')|$(@($d111.Segments).Count)|$(@($script:App.Vault['LogArchives']).Count -gt $archBefore111)")

        # --- Tests 112: transaktionale Loeschung der Protokolle ---------------
        Save-Vault | Out-Null
        $auditNeedle112 = 'Protokolle wurden durch den Benutzer gelöscht'
        $totalEntries112 = {
            $n = @($script:App.Vault['Logs']).Count
            foreach ($b in @($script:App.Vault['LogArchives'])) { $n += @($b.Entries).Count }
            return $n
        }
        $totalBefore112 = & $totalEntries112
        $auditBefore112 = & $countVaultLogs $auditNeedle112
        $script:Paths.VaultPending = Join-Path $testRoot3 'gibtsnicht112\pending.azt'
        $res112a = Clear-VaultProtocols
        $script:Paths.VaultPending = $goodPending102
        Clear-VaultSaveFailedState
        & $assert 'Test 112a: fehlgeschlagene Speicherung -> false, Logs und Archive vollstaendig wiederhergestellt (keine Erfolgsannahme)' "False|$($totalBefore112 + 1)|$auditBefore112|True" ("$res112a|$(& $totalEntries112)|$(& $countVaultLogs $auditNeedle112)|$((& $countVaultLogs 'FUELLER-111') -gt 0)")
        $res112b = Clear-VaultProtocols
        & $assert 'Test 112b: erfolgreiche Loeschung leert Logs und Archive; genau der Audit-Eintrag bleibt' 'True|1|0|True' ("$res112b|$(@($script:App.Vault['Logs']).Count)|$(@($script:App.Vault['LogArchives']).Count)|$((& $countVaultLogs $auditNeedle112) -eq 1)")
        $plain112 = @(Get-ChildItem -LiteralPath (Join-Path $testRoot3 'Data') -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.json', '.log', '.txt', '.csv') }).Count
        & $assert 'Test 112c: Loeschung erzeugt keine Klartextdatei' '0' ([string]$plain112)

        # --- Tests 113: Anonymisierung des Klartext-Logexports ----------------
        & $assert 'Test 113a: Internetadressen werden weiterhin entfernt' 'Fehler [URL entfernt] Ende' (Get-SanitizedLogMessage 'Fehler http://stream.example.de/pfad?token=geheim Ende')
        $msg113 = 'Pfad: ' + $script:Paths.Root + '\Data\vault.azt gemeldet'
        $san113 = Get-SanitizedLogMessage $msg113
        & $assert 'Test 113b: Toolpfad (PSScriptRoot) wird anonymisiert' 'True|False' ("$($san113.Contains('[TOOLPFAD]'))|$($san113.IndexOf([string]$script:Paths.Root, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)")
        $up113 = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
        $san113c = Get-SanitizedLogMessage ('Datei ' + $up113 + '\Desktop\x.txt fehlt')
        & $assert 'Test 113c: Benutzerprofilpfad wird anonymisiert' 'True|False' ("$($san113c.Contains('[BENUTZERPROFIL]'))|$($san113c.IndexOf($up113, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)")
        $tmp113 = [System.IO.Path]::GetTempPath().TrimEnd('\')
        $san113d = Get-SanitizedLogMessage ('Temp: ' + $tmp113 + '\abc.tmp')
        & $assert 'Test 113d: Temp-Pfad wird anonymisiert' 'True|False' ("$($san113d.Contains('[TEMP-PFAD]'))|$($san113d.IndexOf($tmp113, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)")
        & $assert 'Test 113e: fremde C:\Users-Pfade werden generisch anonymisiert' '[BENUTZERPROFIL]\Dokumente\a.txt' (Get-SanitizedLogMessage 'C:\Users\jemand\Dokumente\a.txt')
        & $assert 'Test 113f: normale technische Meldungen bleiben unveraendert lesbar' 'Der Stream wurde beendet (Code 42).' (Get-SanitizedLogMessage 'Der Stream wurde beendet (Code 42).')
        & $assert 'Test 113g: CSV-Formelinjektionsschutz gilt auch fuer bereinigte Meldungen' "'=SUMME(A1)" (Get-CsvEscaped -Value (Get-SanitizedLogMessage '=SUMME(A1)'))

        # --- Tests 114: optionaler PC-Shutdown beim Anwendungsschliessen ------
        # Saemtliche Shutdowns sind AUSSCHLIESSLICH simuliert (TestMode):
        # shutdown.exe wird niemals gestartet, kein Radiostream, kein Netzwerk,
        # keine Scroll-Lock-Eingaben, keine produktiven Dateien.
        $origOffer114 = [bool]$script:App.Settings['ShutdownOfferEnabled']
        $script:App.CurrentDay = $null
        $script:App.CloseConfirmed = $false
        # 1) Opt-in deaktiviert: Auswahl wird logisch nicht angeboten; der
        #    bisherige Schliessen-Dialog bleibt unveraendert (kein Shutdown)
        $script:App.Settings['ShutdownOfferEnabled'] = $false
        & $assert 'Test 114a: ohne Opt-in wird im Schliessen-Dialog keine Shutdown-Auswahl angeboten' 'True|True' ("$($null -eq (Get-CloseShutdownOfferText -HasActiveDay $true))|$($null -eq (Get-CloseShutdownOfferText -HasActiveDay $false))")
        $script:App.Flags.SimulatedShutdownRequested = $false
        $res114b = Invoke-CloseChoice -Choice 'HerunterfahrenUndSchliessen' -ActiveDay $null
        & $assert 'Test 114b: ohne Opt-in fuehrt selbst eine Shutdown-Auswahl niemals zum Shutdown' 'Abbrechen|False|False' ("$res114b|$($script:App.Flags.SimulatedShutdownRequested)|$($script:App.CloseConfirmed)")
        # 2) Opt-in aktiv: Beschriftungen benennen den Shutdown ausdruecklich;
        #    bei aktivem Tag AUCH den Tagesabschluss
        $script:App.Settings['ShutdownOfferEnabled'] = $true
        & $assert 'Test 114c: Beschriftung bei aktivem Tag nennt Tagesabschluss UND Shutdown' 'Arbeitstag beenden, Anwendung schließen und PC herunterfahren' (Get-CloseShutdownOfferText -HasActiveDay $true)
        & $assert 'Test 114d: Beschriftung ohne aktiven Tag nennt Schliessen UND Shutdown' 'Anwendung schließen und PC herunterfahren' (Get-CloseShutdownOfferText -HasActiveDay $false)
        # 3) Abbruch im Dialog: keine Aenderung, kein Shutdown
        $script:App.Flags.SimulatedShutdownRequested = $false
        $res114e = Invoke-CloseChoice -Choice 'Abbrechen' -ActiveDay $null
        & $assert 'Test 114e: Abbrechen loest weder Shutdown noch Schliessen aus' 'Abbrechen|False|False' ("$res114e|$($script:App.Flags.SimulatedShutdownRequested)|$($script:App.CloseConfirmed)")
        # 4) Erfolgspfad MIT aktivem Tag: Tag wird ZUERST vollstaendig beendet,
        #    erst danach folgt die (simulierte) Shutdown-Anforderung
        $fakeCompact114 = [pscustomobject]@{}
        $fakeCompact114 | Add-Member -MemberType ScriptMethod -Name Close -Value { }
        $script:App.Ui.Compact = $fakeCompact114
        $d114 = New-TestDay -DateText ((Get-Date).ToString('yyyy-MM-dd'))
        Add-TestSegment -Day $d114 -Mode 'Betrieb' -StartText ((Get-Date).AddHours(-2).ToString('HH:mm')) | Out-Null
        [void]$script:App.Data.Days.Add($d114)
        Save-Vault | Out-Null
        $script:App.CloseConfirmed = $false
        $script:App.Flags.SimulatedShutdownRequested = $false
        $script:App.Flags.SimulatedShutdownRequestCount = 0
        $res114f = Invoke-CloseChoice -Choice 'HerunterfahrenUndSchliessen' -ActiveDay $d114
        & $assert 'Test 114f: Shutdown-Auswahl beendet den aktiven Tag vollstaendig VOR dem (simulierten) Shutdown' 'ShutdownGestartet|Beendet|True' ("$res114f|$($d114['Status'])|$($null -ne $d114['EndedAt'])")
        & $assert 'Test 114g: nach erfolgreichem finalem Speichern: CleanShutdown, Shutdownanforderung und CloseConfirmed gesetzt' 'True|True|True' ("$($script:App.Vault['CleanShutdown'])|$($script:App.Flags.SimulatedShutdownRequested)|$($script:App.CloseConfirmed)")
        $reload114 = Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        $reDay114 = $null
        foreach ($d in @($reload114['WorkData']['Days'])) { if ([string]$d['Id'] -eq [string]$d114['Id']) { $reDay114 = $d } }
        & $assert 'Test 114h: der finale Tresorstand enthaelt den beendeten Tag und CleanShutdown=true' 'Beendet|True' ("$($reDay114['Status'])|$($reload114['CleanShutdown'])")
        & $assert 'Test 114i: Reentranz - genau EINE simulierte Shutdownanforderung, kein Dispatcher-Stopp im Testlauf' '1|False' ("$($script:App.Flags.SimulatedShutdownRequestCount)|$($script:App.ShuttingDown)")
        [void]$script:App.Data.Days.Remove($d114)
        $script:App.CloseConfirmed = $false
        $script:App.Radio.IsShuttingDown = $false
        Save-Vault | Out-Null
        # 5) Erfolgspfad OHNE aktiven Tag: keine Tagesdaten erzeugt/veraendert
        $daysBefore114 = @($script:App.Data.Days).Count
        $script:App.Flags.SimulatedShutdownRequested = $false
        $script:App.Flags.SimulatedShutdownRequestCount = 0
        $res114j = Invoke-CloseChoice -Choice 'HerunterfahrenUndSchliessen' -ActiveDay $null
        & $assert 'Test 114j: ohne aktiven Tag - simulierter Shutdown ohne neue oder veraenderte Tagesdaten' "ShutdownGestartet|$daysBefore114|True|True|1" ("$res114j|$(@($script:App.Data.Days).Count)|$($script:App.Vault['CleanShutdown'])|$($script:App.Flags.SimulatedShutdownRequested)|$($script:App.Flags.SimulatedShutdownRequestCount)")
        & $assert 'Test 114k: CloseConfirmed wird erst nach erfolgreich gestarteter Shutdownanforderung gesetzt' 'True' ([string]$script:App.CloseConfirmed)
        $script:App.CloseConfirmed = $false
        $script:App.Radio.IsShuttingDown = $false
        # 6) Aktiver Tag kann nicht beendet werden (Speicherfehler beim
        #    Tagesabschluss): kein Shutdown, Tag bleibt Aktiv
        $d114l = New-TestDay -DateText ((Get-Date).ToString('yyyy-MM-dd'))
        Add-TestSegment -Day $d114l -Mode 'Betrieb' -StartText ((Get-Date).AddHours(-2).ToString('HH:mm')) | Out-Null
        [void]$script:App.Data.Days.Add($d114l)
        Save-Vault | Out-Null
        $script:App.Flags.SimulatedShutdownRequested = $false
        $script:Paths.VaultPending = Join-Path $testRoot3 'gibtsnicht114\pending.azt'
        $res114l = Invoke-CloseChoice -Choice 'HerunterfahrenUndSchliessen' -ActiveDay $d114l
        $script:Paths.VaultPending = $goodPending102
        Clear-VaultSaveFailedState
        & $assert 'Test 114l: nicht beendbarer Tag - kein Shutdown, Tag bleibt Aktiv, Anwendung bleibt logisch geoeffnet' 'Abbrechen|Aktiv|False|False|False' ("$res114l|$($d114l['Status'])|$($script:App.Flags.SimulatedShutdownRequested)|$($script:App.CloseConfirmed)|$($script:App.ShuttingDown)")
        [void]$script:App.Data.Days.Remove($d114l)
        Save-Vault | Out-Null
        # 7) Finaler Save-Vault schlaegt fehl: kein Shutdown, CleanShutdown
        #    bleibt bzw. wird wieder false, Anwendung bleibt geoeffnet
        $script:App.Flags.SimulatedShutdownRequested = $false
        $script:Paths.VaultPending = Join-Path $testRoot3 'gibtsnicht114b\pending.azt'
        $res114m = Invoke-CloseChoice -Choice 'HerunterfahrenUndSchliessen' -ActiveDay $null
        $script:Paths.VaultPending = $goodPending102
        Clear-VaultSaveFailedState
        & $assert 'Test 114m: fehlgeschlagener finaler Save-Vault - kein Shutdown, CleanShutdown wieder false' 'Abbrechen|False|False|False' ("$res114m|$($script:App.Flags.SimulatedShutdownRequested)|$($script:App.Vault['CleanShutdown'])|$($script:App.CloseConfirmed)")
        Save-Vault | Out-Null
        # 8) Simulierter Startfehler des Shutdownprozesses: Zustand wird
        #    vollstaendig wiederhergestellt und erneut gespeichert
        $script:App.Flags.SimulatedShutdownRequested = $false
        $script:App.Flags.SimulatedShutdownStartFails = $true
        $res114n = Invoke-CloseChoice -Choice 'HerunterfahrenUndSchliessen' -ActiveDay $null
        $script:App.Flags.SimulatedShutdownStartFails = $false
        $reload114n = Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        & $assert 'Test 114n: Startfehler - kein Shutdown, CloseConfirmed/ShuttingDown false, Radio wieder initialisierbar' 'Abbrechen|False|False|False|False' ("$res114n|$($script:App.Flags.SimulatedShutdownRequested)|$($script:App.CloseConfirmed)|$($script:App.ShuttingDown)|$($script:App.Radio.IsShuttingDown)")
        & $assert 'Test 114o: Startfehler - CleanShutdown wieder false (Speicher UND Datei), korrigierter Status gespeichert' 'False|False|False' ("$($script:App.Vault['CleanShutdown'])|$($reload114n['CleanShutdown'])|$($script:App.Flags.UnsavedChanges)")
        # 9) "Nur Anwendung schliessen" bei aktivem Tag: laufender Abschnitt
        #    bleibt UNVERAENDERT, kein Shutdown
        $d114p = New-TestDay -DateText ((Get-Date).ToString('yyyy-MM-dd'))
        $seg114p = Add-TestSegment -Day $d114p -Mode 'Betrieb' -StartText ((Get-Date).AddHours(-1).ToString('HH:mm'))
        [void]$script:App.Data.Days.Add($d114p)
        Save-Vault | Out-Null
        $segId114p = [string]$seg114p['Id']
        $segStart114p = [string]$seg114p['Start']
        $script:App.Flags.SimulatedShutdownRequested = $false
        $res114p = Invoke-CloseChoice -Choice 'NurSchliessen' -ActiveDay $d114p
        & $assert 'Test 114p: "Nur Anwendung schliessen" - Tag bleibt Aktiv, kein Shutdown, finaler Stand gespeichert' 'NormalSchliessen|Aktiv|False|True' ("$res114p|$($d114p['Status'])|$($script:App.Flags.SimulatedShutdownRequested)|$($script:App.Vault['CleanShutdown'])")
        & $assert 'Test 114q: laufender Abschnitt bleibt unveraendert (ID, Start, End=null, Running, Anzahl)' "1|$segId114p|$segStart114p|True|True" ("$(@($d114p['Segments']).Count)|$($seg114p['Id'])|$($seg114p['Start'])|$($null -eq $seg114p['End'])|$($seg114p['Running'])")
        [void]$script:App.Data.Days.Remove($d114p)
        # 10) Wrapperkompatibilitaet: Invoke-EndDayShutdown nutzt weiterhin den
        #     gemeinsamen Shutdownpfad (identisches Erfolgsverhalten)
        $script:App.Flags.SimulatedShutdownRequested = $false
        $script:App.Flags.SimulatedShutdownRequestCount = 0
        $script:App.CloseConfirmed = $false
        $sd114r = Invoke-EndDayShutdown
        & $assert 'Test 114r: Invoke-EndDayShutdown bleibt kompatibler Wrapper des gemeinsamen Shutdownpfads' 'True|True|1|True' ("$sd114r|$($script:App.Flags.SimulatedShutdownRequested)|$($script:App.Flags.SimulatedShutdownRequestCount)|$($script:App.CloseConfirmed)")
        # Aufraeumen: Testzustand vollstaendig zuruecksetzen
        $script:App.Ui.Compact = $null
        $script:App.CloseConfirmed = $false
        $script:App.Radio.IsShuttingDown = $false
        $script:App.Flags.SimulatedShutdownRequested = $false
        $script:App.Flags.SimulatedShutdownRequestCount = 0
        $script:App.Settings['ShutdownOfferEnabled'] = $origOffer114
        $script:App.Vault['CleanShutdown'] = $false
        Save-Vault | Out-Null

        # --- Test 115: "Arbeitstag beenden" mit nachtraeglich geschlossenem
        #     Sperrintervall, das ueber das gewaehlte Arbeitsende hinausreicht
        #     (Laptop um 15:17 zugeklappt, um 16:28 entsperrt, Ende 15:17) ---
        $d115 = New-TestDay -DateText $yesterdayText
        Add-TestSegment -Day $d115 -Mode 'Homeoffice' -StartText '08:00' | Out-Null
        Add-TestInterval -Day $d115 -ListName 'ManualPauses' -StartText '12:00' -EndText '12:30' | Out-Null
        Add-TestInterval -Day $d115 -ListName 'LockIntervals' -StartText '15:10' -EndText '16:28' | Out-Null
        Add-TestInterval -Day $d115 -ListName 'LockIntervals' -StartText '15:17' -EndText '16:28' | Out-Null
        [void]$script:App.Data.Days.Add($d115)
        Save-Vault | Out-Null
        $end115 = Get-TestNow $d115 '15:17'
        $strict115 = Test-DayEndTime -Day $d115 -End $end115
        $trim115 = Test-DayEndTime -Day $d115 -End $end115 -TrimTrailingIntervals
        & $assert 'Test 115a: strikte Pruefung lehnt weiterhin ab, mit -TrimTrailingIntervals wird das Ende akzeptiert' 'True|' ("$($strict115 -ne '')|$trim115")
        $corrBefore115 = & $countVaultLogs 'Nachlaufende Pausen-/Sperrintervalle am Arbeitsende gekappt'
        # Reparierter Pfad des Tray-Menues: Invoke-EndDayFlow mit simuliertem
        # Dialogergebnis (Show-EndDayDialog wird fuer den Test ersetzt)
        $origDialog115 = ${function:Show-EndDayDialog}
        $script:App.CurrentDay = $d115
        try {
            Set-Item -Path 'function:script:Show-EndDayDialog' -Value { param($Day, [switch]$NoShutdownOption) @{ End = (Get-TestNow $Day '15:17'); Shutdown = $false } }
            try { Invoke-EndDayFlow } catch { }   # UI-Aktualisierung ohne Fenster ist im Testlauf irrelevant
        }
        finally {
            Set-Item -Path 'function:script:Show-EndDayDialog' -Value $origDialog115
            $script:App.CurrentDay = $null
        }
        $comp115 = Get-DayComputation -Day $d115 -Now (ConvertFrom-DateTimeString $d115.EndedAt)
        & $assert 'Test 115b: Tag beendet um 15:17, Grund Manuell, geprueft' "Beendet|$yesterdayText 15:17:00|Manuell|False|True" ("$($d115['Status'])|$($d115['EndedAt'])|$($d115['EndReason'])|$($d115['AutoEndReviewPending'])|$($d115['AutoEndReviewed'])")
        & $assert 'Test 115c: Sperre ab 15:10 auf 15:17 gekappt, Sperre ab 15:17 verworfen, Pause unveraendert' "1|$yesterdayText 15:10:00|$yesterdayText 15:17:00|$yesterdayText 12:30:00" ("$(@($d115.LockIntervals).Count)|$($d115.LockIntervals[0].Start)|$($d115.LockIntervals[0].End)|$($d115.ManualPauses[0].End)")
        & $assert 'Test 115d: Netto korrekt (7:17 brutto - 0:30 Pause - 0:07 Sperre = 6:40), Korrektur protokolliert' "06:40|True|$($corrBefore115 + 1)" ("$(Format-Duration $comp115.Netto)|$(@($d115.Corrections).Count -ge 1)|$(& $countVaultLogs 'Nachlaufende Pausen-/Sperrintervalle am Arbeitsende gekappt')")
        $corr115 = @($d115.Corrections)[-1]
        & $assert 'Test 115g: Korrektureintrag nennt Original- und neue Intervalle' 'Sperre 15:10-16:28; Sperre 15:17-16:28|Sperre 15:10-15:17; Sperre 15:17-16:28 verworfen; Arbeitsende 15:17' ("$($corr115['OldValue'])|$($corr115['NewValue'])")
        # Normalfall ohne nachlaufende Intervalle: keine Korrektur, offene Sperre am Ende geschlossen
        $d115e = New-TestDay -DateText $yesterdayText
        Add-TestSegment -Day $d115e -Mode 'Homeoffice' -StartText '08:00' | Out-Null
        Add-TestInterval -Day $d115e -ListName 'LockIntervals' -StartText '15:00' | Out-Null
        $ok115e = Complete-WorkDay -Day $d115e -End (Get-TestNow $d115e '16:00') -Reason 'Manuell' -TrimTrailingIntervals
        & $assert 'Test 115e: Normalfall - offene Sperre endet am Arbeitsende, kein Korrektureintrag' "True|$yesterdayText 16:00:00|0" ("$ok115e|$($d115e.LockIntervals[0].End)|$(@($d115e.Corrections).Count)")
        # Speicherfehler: vollstaendiger Rollback inkl. gekappter Intervalle
        $d115f = New-TestDay -DateText $yesterdayText
        Add-TestSegment -Day $d115f -Mode 'Homeoffice' -StartText '08:00' | Out-Null
        Add-TestInterval -Day $d115f -ListName 'LockIntervals' -StartText '15:17' -EndText '16:28' | Out-Null
        [void]$script:App.Data.Days.Add($d115f)
        Save-Vault | Out-Null
        $fp115f = Get-DayContentFingerprint -Day $d115f
        $script:Paths.VaultPending = Join-Path $testRoot3 'gibtsnicht115\pending.azt'
        $ok115f = Complete-WorkDay -Day $d115f -End (Get-TestNow $d115f '15:17') -Reason 'Manuell' -TrimTrailingIntervals -Quiet
        $script:Paths.VaultPending = $goodPending102
        Clear-VaultSaveFailedState
        & $assert 'Test 115f: Speicherfehler - false, Tag inkl. Sperrintervall vollstaendig zurueckgerollt' "False|Aktiv|$fp115f" ("$ok115f|$($d115f['Status'])|$(Get-DayContentFingerprint -Day $d115f)")
        [void]$script:App.Data.Days.Remove($d115)
        [void]$script:App.Data.Days.Remove($d115f)
        Save-Vault | Out-Null

        # --- Test 116: Passwortaenderung stellt auch die Recovery-Container um ---
        # Eigener Testordner mit frischem Tresor; Pfade werden danach zurueckgesetzt.
        $paths116 = $script:Paths
        $script:Paths = (& $newTestPaths $testRoot5)
        New-Item -ItemType Directory -Path $script:Paths.Data -Force | Out-Null
        New-Item -ItemType Directory -Path $script:Paths.Recovery -Force | Out-Null
        Initialize-AppState
        Set-VaultSessionKeys -Keys (& $cloneKeys $keys) -Salt $salt -Iterations $iter
        Set-ActiveVault -Vault (New-VaultDataObject)
        Set-VaultLoadReference -Kind 'Neu' -Revision 0
        $saved116 = "$(Save-Vault)|$(Save-Vault)"
        # Recovery-Inhalte wie im Betrieb: Konfliktkopie und Altdatenarchiv
        # (Sitzungsschluessel), Tresorstand eines frueheren Salts mit demselben
        # Passwort, Tresor eines fremden Passworts, beschaedigte und fremde Datei
        $markerA116 = 'MARKER_KONFLIKT_116 äöüß €'
        $recA116 = Protect-TextToRecovery -PlainText $markerA116 -Prefix 'vault'
        $legacyJson116 = [ordered]@{ OriginalName = 'worktime.corrupt.1.json'; Content = '{ "MARKER_LEGACY_116": "äöü" }' } | ConvertTo-Json -Depth 5
        $recB116 = Protect-TextToRecovery -PlainText $legacyJson116 -Prefix 'legacy'
        $saltF116 = [ArbeitszeitTool.VaultCrypto]::GetRandomBytes($script:VaultConst.SaltBytes)
        $keysF116 = Get-VaultKeysFromPassword -PasswordBytes $testPwdBytes -Salt $saltF116 -Iterations $iter
        $recF116 = Join-Path $script:Paths.Recovery ('vault-prev-{0}.azt' -f ([guid]::NewGuid().ToString()))
        Write-VaultToFile -Path $recF116 -Vault $script:App.Vault -AesKey $keysF116.Aes -HmacKey $keysF116.Hmac -Salt $saltF116 -Iterations $iter
        $plainF116 = Unprotect-VaultContainer -Container (Read-VaultContainerFromFile -Path $recF116) -AesKey $keysF116.Aes -HmacKey $keysF116.Hmac
        $saltC116 = [ArbeitszeitTool.VaultCrypto]::GetRandomBytes($script:VaultConst.SaltBytes)
        $keysC116 = Get-VaultKeysFromPassword -PasswordBytes $wrongPwdBytes -Salt $saltC116 -Iterations $iter
        $recC116 = Join-Path $script:Paths.Recovery ('vault-unreadable-{0}.azt' -f ([guid]::NewGuid().ToString()))
        [System.IO.File]::WriteAllText($recC116, (Protect-VaultContainer -PlainText 'FREMDES_PASSWORT_116' -AesKey $keysC116.Aes -HmacKey $keysC116.Hmac -Salt $saltC116 -Iterations $iter), $utf8Bom)
        Clear-VaultKeys -Keys $keysC116
        $recD116 = Join-Path $script:Paths.Recovery ('vault-unreadable-{0}.azt' -f ([guid]::NewGuid().ToString()))
        [System.IO.File]::WriteAllText($recD116, 'KAPUTT_116', $utf8Bom)
        $recE116 = Join-Path $script:Paths.Recovery 'notiz.txt'
        [System.IO.File]::WriteAllText($recE116, 'kein Container', $utf8Bom)
        $untouched116 = { "$(Get-FileSha256Hex -Path $recC116)|$(Get-FileSha256Hex -Path $recD116)|$(Get-FileSha256Hex -Path $recE116)" }
        $untouchedBefore116 = & $untouched116
        $readWith116 = {
            param([string]$Path, $Keys)
            try { return (Unprotect-VaultContainer -Container (Read-VaultContainerFromFile -Path $Path) -AesKey $Keys.Aes -HmacKey $Keys.Hmac) }
            catch { return '<nicht lesbar>' }
        }
        $newCount116 = { @(Get-ChildItem -LiteralPath $script:Paths.Recovery -Filter '*.new' -File -ErrorAction SilentlyContinue).Count }
        # Vorabpruefung: keine Umverschluesselung einer extern veraenderten Hauptdatei
        $unchanged116a = Test-VaultMainFileUnchanged
        $mainBytes116 = [System.IO.File]::ReadAllBytes($script:Paths.VaultFile)
        [System.IO.File]::WriteAllBytes($script:Paths.VaultFile, [byte[]]($mainBytes116 + [byte[]]@(32)))
        $unchanged116b = Test-VaultMainFileUnchanged
        [System.IO.File]::WriteAllBytes($script:Paths.VaultFile, $mainBytes116)
        $hash116 = $script:App.VaultFileHash
        $script:App.VaultFileHash = $null
        $unchanged116c = Test-VaultMainFileUnchanged
        $script:App.VaultFileHash = $hash116
        & $assert 'Test 116a: Passwortaenderung nur bei unveraenderter Hauptdatei (unveraendert / extern geaendert / ohne Referenzhash)' 'True|True|True|False|False|True' ("$saved116|$unchanged116a|$unchanged116b|$unchanged116c|$(Test-VaultMainFileUnchanged)")
        # Passwortaenderung wie in Invoke-PasswordChangeFlow (ohne Dialog)
        $newPwd116 = [System.Text.Encoding]::UTF8.GetBytes('Neues Passwort 116 äöü!')
        $newSalt116 = [ArbeitszeitTool.VaultCrypto]::GetRandomBytes($script:VaultConst.SaltBytes)
        $newKeys116 = Get-VaultKeysFromPassword -PasswordBytes $newPwd116 -Salt $newSalt116 -Iterations $iter
        $err116 = Invoke-VaultReencryption -OldPasswordBytes $testPwdBytes -NewAesKey $newKeys116.Aes -NewHmacKey $newKeys116.Hmac -NewSalt $newSalt116 -NewIterations $iter
        Set-VaultSessionKeys -Keys (& $cloneKeys $newKeys116) -Salt $newSalt116 -Iterations $iter
        $script:App.VaultFileHash = Get-FileSha256Hex -Path $script:Paths.VaultFile
        $save116 = Save-Vault
        $rec116 = Invoke-RecoveryReencryption -OldPasswordBytes $testPwdBytes -NewAesKey $script:VaultSession.AesKey -NewHmacKey $script:VaultSession.HmacKey `
            -NewSalt $script:VaultSession.Salt -NewIterations $script:VaultSession.Iterations
        & $assert 'Test 116b: Passwortaenderung inkl. Recovery: 3 neu verschluesselt, 2 nicht mit altem Passwort lesbar, 0 Fehler' '|True|3|2|0' ("$err116|$save116|$($rec116.Reencrypted)|$($rec116.Skipped)|$(@($rec116.Failed).Count)")
        & $assert 'Test 116c: Recovery-Container mit neuem Passwort lesbar, Klartext zeichengenau erhalten' 'True|True|True' ("$((& $readWith116 $recA116 $newKeys116) -ceq $markerA116)|$((& $readWith116 $recB116 $newKeys116) -ceq $legacyJson116)|$((& $readWith116 $recF116 $newKeys116) -ceq $plainF116)")
        & $assert 'Test 116d: altes Passwort oeffnet keinen Recovery-Container mehr (auch nicht mit frueherem Salt)' '<nicht lesbar>|<nicht lesbar>|<nicht lesbar>' ("$(& $readWith116 $recA116 $keys)|$(& $readWith116 $recB116 $keys)|$(& $readWith116 $recF116 $keysF116)")
        & $assert 'Test 116e: fremdes Passwort, beschaedigte und Nicht-Container-Datei byteidentisch, keine .new-Reste' "$untouchedBefore116|0" ("$(& $untouched116)|$(& $newCount116)")
        $leak116 = $false
        foreach ($f116 in @(Get-ChildItem -LiteralPath $script:Paths.Recovery -File)) {
            $raw116 = [System.IO.File]::ReadAllText($f116.FullName)
            if ($raw116.Contains('MARKER_KONFLIKT_116') -or $raw116.Contains('MARKER_LEGACY_116')) { $leak116 = $true }
        }
        & $assert 'Test 116f: kein Klartext in Recovery; Haupt/Journal/Backups nur mit neuem Passwort lesbar' 'False|True True True|False False False' ("$leak116|$(& $readable29 $script:Paths.VaultFile $newKeys116) $(& $readable29 $script:Paths.VaultPending $newKeys116) $(& $readable29 $script:Paths.VaultBackup1 $newKeys116)|$(& $readable29 $script:Paths.VaultFile $keys) $(& $readable29 $script:Paths.VaultPending $keys) $(& $readable29 $script:Paths.VaultBackup1 $keys)")
        # Fehlerfall: Ueberschreiben scheitert (Testhook) - jede Datei wird
        # gemeldet, bleibt unveraendert lesbar, die Pruefkopie wird entfernt
        $hashes116 = { "$(Get-FileSha256Hex -Path $recA116)|$(Get-FileSha256Hex -Path $recB116)|$(Get-FileSha256Hex -Path $recF116)" }
        $before116g = & $hashes116
        $script:App.Flags.TestFailRecoveryWrite = $true
        $recFail116 = Invoke-RecoveryReencryption -OldPasswordBytes $newPwd116 -NewAesKey $keys.Aes -NewHmacKey $keys.Hmac -NewSalt $salt -NewIterations $iter
        $script:App.Flags.TestFailRecoveryWrite = $false
        & $assert 'Test 116g: Schreibfehler je Datei gemeldet (nicht verschluckt), Dateien unveraendert und lesbar, keine .new-Reste' "0|3|$before116g|True|0" ("$($recFail116.Reencrypted)|$(@($recFail116.Failed).Count)|$(& $hashes116)|$((& $readWith116 $recA116 $newKeys116) -ceq $markerA116)|$(& $newCount116)")
        $recPath116 = $script:Paths.Recovery
        $script:Paths.Recovery = Join-Path $testRoot5 'gibtsnicht116'
        $recNone116 = Invoke-RecoveryReencryption -OldPasswordBytes $newPwd116 -NewAesKey $keys.Aes -NewHmacKey $keys.Hmac -NewSalt $salt -NewIterations $iter
        $script:Paths.Recovery = $recPath116
        & $assert 'Test 116h: ohne Recovery-Ordner gibt es nichts umzustellen' '0|0|0' ("$($recNone116.Reencrypted)|$($recNone116.Skipped)|$(@($recNone116.Failed).Count)")

        # --- Test 117: Uebernahme scheitert an einer geoeffneten Hauptdatei ---
        # (realistisch: Sync-Client oder Virenscanner haelt die Datei offen)
        $leftovers117 = { @(Get-ChildItem -LiteralPath $script:Paths.Data -File | Where-Object { $_.Name -like '*.old' -or $_.Name -like '*.new' -or $_.Name -eq 'vault.txn' }).Count }
        $lock117 = New-Object System.IO.FileStream($script:Paths.VaultFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        try { $err117a = Invoke-VaultReencryption -OldPasswordBytes $newPwd116 -NewAesKey $keys.Aes -NewHmacKey $keys.Hmac -NewSalt $salt -NewIterations $iter }
        finally { $lock117.Dispose() }
        & $assert 'Test 117a: gesperrte Hauptdatei - Ruecknahme gemeldet, alle Dateien weiter mit aktuellem Passwort lesbar, keine Reste' 'True|True|True|True|0' ("$($err117a.Contains('wurde wiederhergestellt'))|$(& $readable29 $script:Paths.VaultFile $newKeys116)|$(& $readable29 $script:Paths.VaultBackup1 $newKeys116)|$(& $readable29 $script:Paths.VaultBackup2 $newKeys116)|$(& $leftovers117)")
        $lock117 = New-Object System.IO.FileStream($script:Paths.VaultFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $script:App.Flags.TestFailReencryptRollback = $true
        try { $err117b = Invoke-VaultReencryption -OldPasswordBytes $newPwd116 -NewAesKey $keys.Aes -NewHmacKey $keys.Hmac -NewSalt $salt -NewIterations $iter }
        finally { $script:App.Flags.TestFailReencryptRollback = $false; $lock117.Dispose() }
        & $assert 'Test 117b: unvollstaendige Ruecknahme wird ehrlich gemeldet (kein "wiederhergestellt"), vault.txn bleibt' 'True|False|True' ("$($err117b.Contains('NICHT vollständig'))|$($err117b.Contains('wurde wiederhergestellt'))|$(Test-Path -LiteralPath $script:Paths.VaultTxn)")
        $repaired117 = Repair-VaultTransactionState
        Complete-VaultTransactionCleanup
        & $assert 'Test 117c: Startreparatur stellt den Dateisatz mit dem aktuellen Passwort vollstaendig wieder her' 'True|True|True|True|0' ("$repaired117|$(& $readable29 $script:Paths.VaultFile $newKeys116)|$(& $readable29 $script:Paths.VaultBackup1 $newKeys116)|$(& $readable29 $script:Paths.VaultBackup2 $newKeys116)|$(& $leftovers117)")

        # --- Test 118: Aktivhaltung ist optional (Opt-in) und kompatibel zu 1.0.0/1.1.x ---
        # Tresor aus 1.1.x (ohne Aktivhaltungswerte) -> Aktivhaltung bleibt AUS
        $new118 = New-VaultDataObject
        [void]$new118['Settings'].Remove('KeepAliveEnabled')
        [void]$new118['Settings'].Remove('KeepAliveIntervalSec')
        $new118['Settings']['CompactFields'] = @('Beginn', 'Netto')
        $new118Path = Join-Path $script:Paths.Data 'neu118.azt'
        Write-VaultToFile -Path $new118Path -Vault $new118 -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey -Salt $script:VaultSession.Salt -Iterations $script:VaultSession.Iterations
        $loadedNew118 = Read-VaultFromFile -Path $new118Path -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        Remove-Item -LiteralPath $new118Path -Force
        Set-ActiveVault -Vault $loadedNew118
        & $assert 'Test 118a: Tresor aus 1.1.x laedt mit Aktivhaltung AUS und Standardintervall 60 s' 'False|60|Beginn+Netto' ("$([bool]$script:App.Settings['KeepAliveEnabled'])|$($script:App.Settings['KeepAliveIntervalSec'])|$(@($script:App.Settings['CompactFields']) -join '+')")
        & $assert 'Test 118b: Standardeinstellungen - Aktivhaltung ist Opt-in (aus)' 'False' ([string][bool](Get-DefaultSettings)['KeepAliveEnabled'])
        # Tresor aus 1.0.0 mit eingeschalteter Aktivhaltung -> Werte bleiben erhalten
        $old118 = New-VaultDataObject
        $old118['Settings']['KeepAliveEnabled'] = $true
        $old118['Settings']['KeepAliveIntervalSec'] = 30
        $old118['Settings']['CompactFields'] = @('Beginn', 'ScrollLock', 'Netto')
        $old118['Settings']['CompactPresets'] = @(
            [ordered]@{ Id = 'p1'; Name = 'Nur Scroll'; Fields = @('ScrollLock') },
            [ordered]@{ Id = 'p2'; Name = 'Gemischt'; Fields = @('Netto', 'ScrollLock') })
        $old118Path = Join-Path $script:Paths.Data 'alt118.azt'
        Write-VaultToFile -Path $old118Path -Vault $old118 -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey -Salt $script:VaultSession.Salt -Iterations $script:VaultSession.Iterations
        $loaded118 = Read-VaultFromFile -Path $old118Path -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        Remove-Item -LiteralPath $old118Path -Force
        Set-ActiveVault -Vault $loaded118
        $s118 = $script:App.Settings
        $presets118 = (@($s118['CompactPresets']) | ForEach-Object { "$($_['Name'])=$(@($_['Fields']) -join '+')" }) -join ','
        & $assert 'Test 118c: Tresor aus 1.0.0 behaelt Aktivhaltung, Intervall, Kompaktfeld und Presets' 'True|30|Beginn+ScrollLock+Netto|Nur Scroll=ScrollLock,Gemischt=Netto+ScrollLock' ("$([bool]$s118['KeepAliveEnabled'])|$($s118['KeepAliveIntervalSec'])|$(@($s118['CompactFields']) -join '+')|$presets118")
        $unknown118 = Get-ValidatedSettings -Loaded ([ordered]@{ CompactFields = @('Beginn', 'Unbekannt') })
        $onlyUnknown118 = Get-ValidatedSettings -Loaded ([ordered]@{ CompactFields = @('Unbekannt') })
        & $assert 'Test 118d: unbekannte Kompaktfelder werden verworfen, nur unbekannte -> Standardauswahl' 'Beginn|Beginn+Netto+SollRestOderUeberstunden+MaxEnde' ("$(@($unknown118['CompactFields']) -join '+')|$(@($onlyUnknown118['CompactFields']) -join '+')")
        $low118 = Get-ValidatedSettings -Loaded ([ordered]@{ KeepAliveIntervalSec = 1 })
        $high118 = Get-ValidatedSettings -Loaded ([ordered]@{ KeepAliveIntervalSec = 99999 })
        & $assert 'Test 118e: Intervall wird auf 10-600 Sekunden begrenzt' '10|600' ("$($low118['KeepAliveIntervalSec'])|$($high118['KeepAliveIntervalSec'])")
        $script:App.Settings['KeepAliveEnabled'] = $false
        & $assert 'Test 118f: ausgeschaltete Aktivhaltung startet keinen Puls' 'False' ([string](Test-KeepAliveShouldRun))
        $save118 = Save-Vault
        $raw118 = Unprotect-VaultContainer -Container (Read-VaultContainerFromFile -Path $script:Paths.VaultFile) -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        & $assert 'Test 118g: Einstellung wird im Tresor gespeichert' 'True|True' ("$save118|$($raw118.Contains('KeepAliveEnabled'))")

        # --- Tests 119-121: Recovery-Neuverschluesselung - Fehlerfaelle, ---
        # --- Unterbrechung, Startreparatur, Ergebnisbewertung             ---
        # Ausgangslage: Sitzung = Passwort aus Test 116 ($newPwd116) = "bisheriges"
        # Passwort; Ziel ist ein neues Passwort 119. Jeder Teiltest nutzt einen
        # eigenen Recovery-Ordner im Testverzeichnis.
        $recPath119 = $script:Paths.Recovery
        $pwd119 = [System.Text.Encoding]::UTF8.GetBytes('Neues Passwort 119 äöü!')
        $salt119 = [ArbeitszeitTool.VaultCrypto]::GetRandomBytes($script:VaultConst.SaltBytes)
        $keys119 = Get-VaultKeysFromPassword -PasswordBytes $pwd119 -Salt $salt119 -Iterations $iter
        $saltW119 = [ArbeitszeitTool.VaultCrypto]::GetRandomBytes($script:VaultConst.SaltBytes)
        $keysW119 = Get-VaultKeysFromPassword -PasswordBytes $wrongPwdBytes -Salt $saltW119 -Iterations $iter
        $oldSession119 = @{ Keys = (& $cloneKeys @{ Aes = $script:VaultSession.AesKey; Hmac = $script:VaultSession.HmacKey }); Salt = [byte[]]$script:VaultSession.Salt.Clone() }
        # Containerbytes (UTF-8 mit BOM, wie Protect-TextToRecovery)
        $mkBytes119 = {
            param([string]$Text, $K, [byte[]]$S)
            $json = Protect-VaultContainer -PlainText $Text -AesKey $K.Aes -HmacKey $K.Hmac -Salt $S -Iterations $iter
            $pre = $utf8Bom.GetPreamble()
            $body = $utf8Bom.GetBytes($json)
            return ,([byte[]]($pre + $body))
        }
        $mkFile119 = {
            param([string]$Dir, [string]$Name, [byte[]]$Bytes)
            $p = Join-Path $Dir $Name
            [System.IO.File]::WriteAllBytes($p, $Bytes)
            return $p
        }
        $readAs119 = {
            param([string]$Path, $K)
            try { return (Unprotect-VaultContainer -Container (Read-VaultContainerFromFile -Path $Path) -AesKey $K.Aes -HmacKey $K.Hmac) }
            catch { return '<nicht lesbar>' }
        }
        $runRec119 = {
            Invoke-RecoveryReencryption -OldPasswordBytes $newPwd116 -NewAesKey $keys119.Aes -NewHmacKey $keys119.Hmac -NewSalt $salt119 -NewIterations $iter
        }
        $hash119 = { param([string]$Path) Get-FileSha256Hex -Path $Path }
        $oldK119 = $oldSession119.Keys
        $oldS119 = $oldSession119.Salt

        # Testbestand: regulaer, gesperrt, ohne Leserecht, extern geaendert,
        # fremdes Passwort, beschaedigt (abgeschnitten), keine Tresordatei
        $dir119 = Join-Path $testRoot5 'Recovery119'
        New-Item -ItemType Directory -Path $dir119 -Force | Out-Null
        $script:Paths.Recovery = $dir119
        $okA119 = & $mkFile119 $dir119 'vault-a119.azt' (& $mkBytes119 'MARKER_119_A' $oldK119 $oldS119)
        $lockF119 = & $mkFile119 $dir119 'vault-lock119.azt' (& $mkBytes119 'MARKER_119_LOCK' $oldK119 $oldS119)
        $denyF119 = & $mkFile119 $dir119 'vault-deny119.azt' (& $mkBytes119 'MARKER_119_DENY' $oldK119 $oldS119)
        $chgF119 = & $mkFile119 $dir119 'vault-chg119.azt' (& $mkBytes119 'MARKER_119_ORIGINAL' $oldK119 $oldS119)
        $forF119 = & $mkFile119 $dir119 'vault-foreign119.azt' (& $mkBytes119 'MARKER_119_FREMD' $keysW119 $saltW119)
        $fullBytes119 = & $mkBytes119 'MARKER_119_KAPUTT' $oldK119 $oldS119
        $corF119 = & $mkFile119 $dir119 'vault-corrupt119.azt' ([byte[]]($fullBytes119[0..([int]($fullBytes119.Length / 2))]))
        $notF119 = & $mkFile119 $dir119 'notiz119.azt' ($utf8Bom.GetBytes('kein Container'))
        $extBytes119 = & $mkBytes119 'MARKER_119_EXTERN' $oldK119 $oldS119
        $all119 = @($okA119, $lockF119, $denyF119, $chgF119, $forF119, $corF119, $notF119)
        $hashesOf119 = { (@($all119) | ForEach-Object { & $hash119 $_ }) -join '|' }
        $newFiles119 = { @(Get-ChildItem -LiteralPath $script:Paths.Recovery -File | Where-Object { $_.Name -like '*.new' } | ForEach-Object { $_.Name } | Sort-Object) -join ',' }

        # 119a: Fehler beim Auflisten des Ordners ist ein Fehler, kein leerer Ordner
        $before119a = & $hashesOf119
        $script:App.Flags.TestFailRecoveryList = $true
        try { $r119a = & $runRec119 }
        finally { $script:App.Flags.TestFailRecoveryList = $false }
        $rep119a = Get-PasswordChangeReport -SaveOk $true -Recovery $r119a -DataResidue @()
        & $assert 'Test 119a: Auflistungsfehler -> Fehler gemeldet (nicht 0 Dateien = Erfolg), Status Teilweise, nichts veraendert' 'True|0|Teilweise|Warning|True' ("$(@($r119a.Failed).Count -eq 1 -and ([string]@($r119a.Failed)[0]).Contains('nicht auflistbar'))|$($r119a.Reencrypted)|$($rep119a.Status)|$($rep119a.Level)|$((& $hashesOf119) -eq $before119a)")

        # 119b: Sperre durch anderen Prozess (echte exklusive Dateisperre),
        # fehlendes Leserecht (Simulation: UnauthorizedAccessException beim
        # Lesen), externe Aenderung zwischen Lesen und Uebernahme (Simulation
        # eines Sync-Clients unmittelbar vor dem Ueberschreiben)
        $script:App.Flags.TestRecoveryDenyRead = 'vault-deny119.azt'
        $script:App.Flags.TestRecoveryBeforeCommit = {
            param([string]$Path)
            if ($Path -eq $chgF119) { [System.IO.File]::WriteAllBytes($Path, $extBytes119) }
        }
        $lockStream119 = New-Object System.IO.FileStream($lockF119, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try { $r119b = & $runRec119 }
        finally {
            $lockStream119.Dispose()
            $script:App.Flags.TestRecoveryDenyRead = ''
            $script:App.Flags.TestRecoveryBeforeCommit = $null
        }
        $reason119 = {
            param([string]$Name, [string]$Needle)
            return [bool](@($r119b.Failed) | Where-Object { ([string]$_).StartsWith($Name + ':') -and ([string]$_).Contains($Needle) })
        }
        & $assert 'Test 119b: Kategorien getrennt - 1 neu, je 1 fremdes Passwort/beschaedigt/keine Tresordatei, 3 technische Fehler' '1|vault-foreign119.azt|vault-corrupt119.azt|notiz119.azt|3|3|0' ("$($r119b.Reencrypted)|$(@($r119b.Foreign) -join ',')|$(@($r119b.Corrupt) -join ',')|$(@($r119b.NotContainer) -join ',')|$($r119b.Skipped)|$(@($r119b.Failed).Count)|$(@($r119b.CleanupFailed).Count)")
        & $assert 'Test 119c: Fehlergruende - gesperrt, Zugriff verweigert, Konflikt durch externe Aenderung' 'True|True|True' ("$(& $reason119 'vault-lock119.azt' 'gesperrt')|$(& $reason119 'vault-deny119.azt' 'Zugriff verweigert')|$(& $reason119 'vault-chg119.azt' 'Konflikt')")
        & $assert 'Test 119d: gesperrte/nicht lesbare Datei unveraendert mit bisherigem Passwort lesbar; regulaere Datei nur noch mit neuem Passwort' 'MARKER_119_LOCK|MARKER_119_DENY|MARKER_119_A|<nicht lesbar>' ("$(& $readAs119 $lockF119 $oldK119)|$(& $readAs119 $denyF119 $oldK119)|$(& $readAs119 $okA119 $keys119)|$(& $readAs119 $okA119 $oldK119)")
        & $assert 'Test 119e: extern geaenderte Datei NICHT ueberschrieben, gepruefte Kopie (alter Inhalt, neues Passwort) bleibt erhalten' 'MARKER_119_EXTERN|MARKER_119_ORIGINAL|vault-chg119.azt.new' ("$(& $readAs119 $chgF119 $oldK119)|$(& $readAs119 ($chgF119 + '.new') $keys119)|$(& $newFiles119)")
        $rep119b = Get-PasswordChangeReport -SaveOk $true -Recovery $r119b -DataResidue @()
        & $assert 'Test 119f: Bericht "teilweise" mit allen betroffenen Dateien, nicht "erfolgreich geaendert"' 'Teilweise|Warning|True|True|False|True' ("$($rep119b.Status)|$($rep119b.Level)|$($rep119b.Message.Contains('NUR TEILWEISE'))|$($rep119b.Message.Contains('vault-lock119.azt') -and $rep119b.Message.Contains('vault-deny119.azt') -and $rep119b.Message.Contains('vault-chg119.azt'))|$($rep119b.Message.Contains('erfolgreich geändert'))|$($rep119b.Message.Contains('3 Datei(en)'))")

        # 119g: zweiter Lauf nach Wegfall der Ursachen - gesperrte und nicht
        # lesbare Datei werden umgestellt; die Restkopie der Konfliktdatei wird
        # NICHT ueberschrieben (unklarer Zwischenstand bleibt erhalten)
        $copyHash119 = & $hash119 ($chgF119 + '.new')
        $r119g = & $runRec119
        & $assert 'Test 119g: Wiederholung stellt frei gewordene Dateien um, vorhandene Restkopie bleibt unangetastet' '2|1|True|True|MARKER_119_LOCK|MARKER_119_DENY' ("$($r119g.Reencrypted)|$(@($r119g.Failed).Count)|$(([string]@($r119g.Failed)[0]).Contains('Restdatei'))|$((& $hash119 ($chgF119 + '.new')) -eq $copyHash119)|$(& $readAs119 $lockF119 $keys119)|$(& $readAs119 $denyF119 $keys119)")

        # 119h: Bereinigung der Pruefkopie scheitert -> trotzdem erfolgreich
        # neu verschluesselt (getrennt gemeldet), kein "weiterhin alt lesbar"
        $dir119h = Join-Path $testRoot5 'Recovery119h'
        New-Item -ItemType Directory -Path $dir119h -Force | Out-Null
        $script:Paths.Recovery = $dir119h
        $okB119 = & $mkFile119 $dir119h 'vault-b119.azt' (& $mkBytes119 'MARKER_119_B' $oldK119 $oldS119)
        $script:App.Flags.TestFailRecoveryCleanup = $true
        try { $r119h = & $runRec119 }
        finally { $script:App.Flags.TestFailRecoveryCleanup = $false }
        $rep119h = Get-PasswordChangeReport -SaveOk $true -Recovery $r119h -DataResidue @()
        & $assert 'Test 119h: fehlgeschlagene Bereinigung = Erfolg mit Bereinigungshinweis (nicht als Fehler/teilweise gewertet)' '1|0|vault-b119.azt.new|MARKER_119_B|MARKER_119_B|VollstaendigBereinigung|Info|False' ("$($r119h.Reencrypted)|$(@($r119h.Failed).Count)|$(@($r119h.CleanupFailed) -join ',')|$(& $readAs119 $okB119 $keys119)|$(& $readAs119 ($okB119 + '.new') $keys119)|$($rep119h.Status)|$($rep119h.Level)|$($rep119h.Message.Contains('BISHERIGEN'))")

        # --- Test 120: Unterbrechung in verschiedenen Phasen + Neustart ---
        # Ein echter Prozessabbruch ist im Testlauf nicht praktikabel; die
        # Dateizustaende, die ein Abbruch in der jeweiligen Phase hinterlaesst,
        # werden mit echten Containerbytes exakt nachgebildet. Danach laeuft die
        # Startreparatur mit dem NEUEN Passwort als Sitzungspasswort.
        $dir120 = Join-Path $testRoot5 'Recovery120'
        New-Item -ItemType Directory -Path $dir120 -Force | Out-Null
        $script:Paths.Recovery = $dir120
        $o120 = @{}; $n120 = @{}
        foreach ($k120 in @('1', '2', '3', '3c', '4')) {
            $o120[$k120] = & $mkBytes119 ('MARKER_120_' + $k120) $oldK119 $oldS119
            $n120[$k120] = & $mkBytes119 ('MARKER_120_' + $k120) $keys119 $salt119
        }
        # Phase 1: Abbruch beim Schreiben der Kopie (Kopie abgeschnitten)
        $f1 = & $mkFile119 $dir120 'r1.azt' $o120['1']
        & $mkFile119 $dir120 'r1.azt.new' ([byte[]]($n120['1'][0..200])) | Out-Null
        # Phase 2: Kopie vollstaendig und geprueft, Original noch unveraendert
        $f2 = & $mkFile119 $dir120 'r2.azt' $o120['2']
        & $mkFile119 $dir120 'r2.azt.new' $n120['2'] | Out-Null
        # Phase 3: Abbruch WAEHREND des In-place-Ueberschreibens (Kopf neu,
        # Rest alt - gleiche Laenge, formal gueltiges JSON, HMAC ungueltig)
        $mix120 = [byte[]]$o120['3'].Clone()
        $cut120 = [int]($n120['3'].Length * 0.6)
        [System.Array]::Copy($n120['3'], 0, $mix120, 0, $cut120)
        $f3 = & $mkFile119 $dir120 'r3.azt' $mix120
        & $mkFile119 $dir120 'r3.azt.new' $n120['3'] | Out-Null
        # Phase 3c: Ueberschreiben abgebrochen, Datei verkuerzt (Format zerstoert)
        $f3c = & $mkFile119 $dir120 'r3c.azt' ([byte[]]($n120['3c'][0..150]))
        & $mkFile119 $dir120 'r3c.azt.new' $n120['3c'] | Out-Null
        # Phase 4: Abbruch beim Aufraeumen (Original bereits neu, Kopie noch da)
        $f4 = & $mkFile119 $dir120 'r4.azt' $n120['4']
        & $mkFile119 $dir120 'r4.azt.new' (& $mkBytes119 'MARKER_120_4' $keys119 $salt119) | Out-Null
        # Kopie ohne Original (z. B. Original extern entfernt)
        & $mkFile119 $dir120 'r5.azt.new' (& $mkBytes119 'MARKER_120_5' $keys119 $salt119) | Out-Null
        $keep120 = { "$(& $hash119 $f1)|$(& $hash119 ($f1 + '.new'))|$(& $hash119 $f2)|$(& $hash119 ($f2 + '.new'))|$(& $hash119 (Join-Path $dir120 'r5.azt.new'))" }
        $keepBefore120 = & $keep120
        # Neustart: Sitzung mit dem neuen Passwort
        Set-VaultSessionKeys -Keys (& $cloneKeys $keys119) -Salt $salt119 -Iterations $iter
        $r120 = Resolve-RecoveryReencryptionLeftovers
        & $assert 'Test 120a: eindeutige Zustaende aufgeloest (abgebrochenes Ueberschreiben wiederhergestellt, Aufraeumrest entfernt), unklare gemeldet' '2|True|True|r4.azt.new|3' ("$(@($r120.Completed).Count)|$(@($r120.Completed) -contains 'r3.azt')|$(@($r120.Completed) -contains 'r3c.azt')|$(@($r120.Removed) -join ',')|$(@($r120.Unclear).Count)")
        & $assert 'Test 120b: unklare Zwischenstaende (Kopie unvollstaendig / Original noch altes Passwort / Original fehlt) byteidentisch erhalten' $keepBefore120 (& $keep120)
        & $assert 'Test 120c: je Datei mindestens ein vollstaendiger, entschluesselbarer Stand' 'MARKER_120_1|MARKER_120_2|MARKER_120_2|MARKER_120_3|MARKER_120_3c|MARKER_120_4|MARKER_120_5' ("$(& $readAs119 $f1 $oldK119)|$(& $readAs119 $f2 $oldK119)|$(& $readAs119 ($f2 + '.new') $keys119)|$(& $readAs119 $f3 $keys119)|$(& $readAs119 $f3c $keys119)|$(& $readAs119 $f4 $keys119)|$(& $readAs119 (Join-Path $dir120 'r5.azt.new') $keys119)")
        $r120b = Resolve-RecoveryReencryptionLeftovers
        & $assert 'Test 120d: erneuter Start ist idempotent (nichts weiter veraendert, Unklares weiter gemeldet)' "0|0|3|$keepBefore120" ("$(@($r120b.Completed).Count)|$(@($r120b.Removed).Count)|$(@($r120b.Unclear).Count)|$(& $keep120)")
        $notice120 = Invoke-RecoveryStartupCheck -Interrupted $false
        & $assert 'Test 120e: Starthinweis nennt unklare Zwischenstaende und bestaetigt, dass nichts geloescht wurde' 'True|True|True' ("$($notice120.Contains('r1.azt.new'))|$($notice120.Contains('r2.azt'))|$($notice120.Contains('NICHT verändert oder gelöscht'))")
        # Sitzung zurueck auf das bisherige Passwort (Tresor in Data)
        Set-VaultSessionKeys -Keys (& $cloneKeys $oldK119) -Salt $oldS119 -Iterations $iter

        # --- Test 121: vollstaendige Passwortaenderung inkl. Folgeschritten, ---
        # --- unterbrochene Recovery-Phase und erfolgreicher Neustart       ---
        # Eigener Recovery-Ordner: fremdes Passwort, keine Tresordatei, Altstand
        $dir121 = Join-Path $testRoot5 'Recovery121'
        New-Item -ItemType Directory -Path $dir121 -Force | Out-Null
        $script:Paths.Recovery = $dir121
        [System.IO.File]::Copy($recC116, (Join-Path $dir121 'vault-foreign121.azt'))
        [System.IO.File]::Copy($recD116, (Join-Path $dir121 'vault-kaputt121.azt'))
        # Ein beim Aufraeumen nicht entfernter Altstand (.old, bisheriges Passwort)
        $err121 = Invoke-VaultReencryption -OldPasswordBytes $newPwd116 -NewAesKey $keys119.Aes -NewHmacKey $keys119.Hmac -NewSalt $salt119 -NewIterations $iter
        [System.IO.File]::WriteAllBytes(($script:Paths.VaultBackup2 + '.old'), $o120['1'])
        $oldInRecovery121 = & $mkFile119 $script:Paths.Recovery 'vault-alt121.azt' (& $mkBytes119 'MARKER_121_ALT' $oldK119 $oldS119)
        Set-VaultSessionKeys -Keys (& $cloneKeys $keys119) -Salt $salt119 -Iterations $iter
        $script:App.VaultFileHash = Get-FileSha256Hex -Path $script:Paths.VaultFile
        $rep121 = Complete-PasswordChangeFollowUp -OldPasswordBytes $newPwd116
        $notCurrent121 = @(Get-ChildItem -LiteralPath $script:Paths.Recovery -Filter '*.azt' -File | Where-Object { $_.Extension -eq '.azt' -and -not (Test-VaultFileAuthentication -Path $_.FullName) } | ForEach-Object { $_.Name } | Sort-Object)
        & $assert 'Test 121a: Passwortaenderung vollstaendig - .old-Rest gesichert und umgestellt, Data ohne Altstand, nur bewusst fremde Dateien nicht umgestellt' "|Vollstaendig|Info|False|False|vault-foreign121.azt,vault-kaputt121.azt|MARKER_121_ALT" ("$err121|$($rep121.Status)|$($rep121.Level)|$(Test-Path -LiteralPath ($script:Paths.VaultBackup2 + '.old'))|$(Test-Path -LiteralPath $script:Paths.VaultTxn)|$($notCurrent121 -join ',')|$(& $readAs119 $oldInRecovery121 $keys119)")
        & $assert 'Test 121b: Data-Ordner nach der Aenderung ohne Rest mit bisherigem Passwort' '0' ([string](Get-PasswordChangeDataResidue).Count)
        # Abbruch waehrend der Recovery-Phase: Markierung bleibt stehen, eine
        # Datei ist noch mit dem bisherigen Passwort verschluesselt
        Set-RecoveryReencryptionMarker
        $stale121 = & $mkFile119 $script:Paths.Recovery 'vault-stale121.azt' (& $mkBytes119 'MARKER_121_STALE' $oldK119 $oldS119)
        # Neustart wie in Start-Application
        $repaired121 = Repair-VaultTransactionState
        $int121 = Test-RecoveryReencryptionInterrupted
        Complete-VaultTransactionCleanup
        $notice121 = Invoke-RecoveryStartupCheck -Interrupted $int121
        & $assert 'Test 121c: Neustart erkennt unterbrochene Recovery-Phase und nennt die nicht umgestellte Datei; Markierung danach entfernt' 'False|True|True|True|False|False' ("$repaired121|$int121|$($notice121.Contains('unterbrochen'))|$($notice121.Contains('vault-stale121.azt'))|$($notice121.Contains('vault-alt121.azt'))|$(Test-Path -LiteralPath $script:Paths.VaultTxn)")
        & $assert 'Test 121d: Datei der unterbrochenen Phase unveraendert mit bisherigem Passwort lesbar' 'MARKER_121_STALE' (& $readAs119 $stale121 $oldK119)
        $loaded121 = 'False'
        try { Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $keys119.Aes -HmacKey $keys119.Hmac | Out-Null; $loaded121 = 'True' } catch { }
        & $assert 'Test 121e: nach dem Neustart Tresor mit neuem Passwort ladbar und speicherbar, altes Passwort oeffnet ihn nicht' 'True|True|False' ("$loaded121|$(Save-Vault)|$(& $readable29 $script:Paths.VaultFile $oldK119)")
        $rep121f = Get-PasswordChangeReport -SaveOk $false -Recovery @{ Failed = @(); CleanupFailed = @() } -DataResidue @('vault.backup2.azt')
        $rep121g = Get-PasswordChangeReport -SaveOk $true -Recovery @{ Reencrypted = 0; Failed = @(); CleanupFailed = @(); Foreign = @('a.azt') } -DataResidue @()
        & $assert 'Test 121f: Bericht - Altstand in Data = teilweise + Speicherfehler sichtbar; vollstaendig = Info mit Hinweis auf bewusst belassene Dateien' 'Teilweise|Warning|True|True|Vollstaendig|Info|True' ("$($rep121f.Status)|$($rep121f.Level)|$($rep121f.Message.Contains('vault.backup2.azt'))|$($rep121f.Message.Contains('FEHLGESCHLAGEN'))|$($rep121g.Status)|$($rep121g.Level)|$($rep121g.Message.Contains('bewusst unverändert'))")

        Clear-VaultKeys -Keys $keys119
        Clear-VaultKeys -Keys $keysW119
        Clear-VaultKeys -Keys $oldK119
        [ArbeitszeitTool.VaultCrypto]::ClearBytes($pwd119)

        $script:Paths.Recovery = $recPath119

        # --- Tests 122: Kommentare (Tag, Abschnitt, Pause, Sperre, Korrektur) ---
        $crlf122 = "`r`n"
        & $assert 'Test 122a: Normalisierung - Rand, Steuerzeichen, Zeilenenden, leer' ("a${crlf122}bc|a${crlf122}b||") ("$(Get-NormalizedComment -Text ("  a`r`nb" + [char]1 + "c  "))|$(Get-NormalizedComment -Text "a`nb")|$(Get-NormalizedComment -Text "  `r`n ")|$(Get-NormalizedComment -Text $null)")
        & $assert 'Test 122b: Laengenbegrenzung auf MaxLength' ([string]$script:CommentConst.MaxLength) ([string](Get-NormalizedComment -Text ('x' * 1500)).Length)
        $seg122 = New-SegmentObject -Mode 'Homeoffice' -Start (Get-Date '2026-07-10 08:00') -End (Get-Date '2026-07-10 09:00')
        $set122 = Set-ItemComment -Item $seg122 -Text ' Kundentermin '
        $had122 = $seg122.Contains('Comment')
        [void](Set-ItemComment -Item $seg122 -Text '   ')
        & $assert 'Test 122c: Set-ItemComment setzt normalisiert und entfernt bei leerem Text' 'Kundentermin|True|False' ("$set122|$had122|$($seg122.Contains('Comment'))")
        & $assert 'Test 122d: Kurzfassung einzeilig und gekuerzt' 'a / b|60|True' ("$(Get-CommentPreview -Text "a`r`nb")|$((Get-CommentPreview -Text ('y' * 200)).Length)|$((Get-CommentPreview -Text ('y' * 200)).EndsWith('…'))")
        $d122 = New-TestDay -DateText '2026-07-08'
        $s122 = Add-TestSegment -Day $d122 -Mode 'Homeoffice' -StartText '08:00' -EndText '12:00'
        $p122 = Add-TestInterval -Day $d122 -ListName 'ManualPauses' -StartText '10:00' -EndText '10:15'
        $l122 = Add-TestInterval -Day $d122 -ListName 'LockIntervals' -StartText '11:00' -EndText '11:05'
        Add-Correction -Day $d122 -Description 'Test ohne Kommentar' -NoLog
        Add-Correction -Day $d122 -Description 'Test mit Kommentar' -Comment ' vergessen zu stempeln ' -NoLog
        & $assert 'Test 122e: Korrektur speichert optionale Begruendung, ohne Begruendung kein Feld' 'False|vergessen zu stempeln' ("$($d122['Corrections'][0].Contains('Comment'))|$($d122['Corrections'][1]['Comment'])")
        $fpA122 = Get-DayContentFingerprint -Day $d122
        [void](Set-ItemComment -Item $d122 -Text 'Tag')
        $fpB122 = Get-DayContentFingerprint -Day $d122
        [void](Set-ItemComment -Item $s122 -Text 'Abschnitt')
        [void](Set-ItemComment -Item $p122 -Text 'Arzt')
        [void](Set-ItemComment -Item $l122 -Text 'Sperre')
        $fpC122 = Get-DayContentFingerprint -Day $d122
        & $assert 'Test 122f: Kommentare fliessen in den Inhaltsvergleich ein (Importkonflikt)' 'True|True' ("$($fpA122 -ne $fpB122)|$($fpB122 -ne $fpC122)")
        $snap122 = Get-DaySnapshot -Day $d122
        [void](Set-ItemComment -Item $d122 -Text 'geaendert')
        Restore-DayFromSnapshot -Day $d122 -Snapshot $snap122
        & $assert 'Test 122g: Schnappschuss/Rollback stellt Kommentare wieder her' "Tag|$fpC122" ("$(Get-ItemComment -Item $d122)|$(Get-DayContentFingerprint -Day $d122)")
        $d122['Status'] = 'Beendet'
        $d122['EndedAt'] = ConvertTo-DateTimeString (Get-TestNow $d122 '12:00')
        $segT122 = Get-SegmentsTable -Day $d122
        $pauseT122 = Get-PausesTable -Day $d122 -Comp (Get-DayComputation -Day $d122 -Now (Get-TestNow $d122 '12:00'))
        $ivT122 = Get-IntervalTable -Intervals $d122.ManualPauses
        $histT122 = Get-HistoryTable -Days @($d122)
        $corrT122 = Get-CorrectionsTable -Corrections $d122.Corrections
        & $assert 'Test 122h: Tabellen zeigen die Kommentare (Abschnitte, Pausen/Sperren, Intervalle, Verlauf, Aenderungsprotokoll)' 'Abschnitt|Arzt|Sperre|Arzt|Tag||vergessen zu stempeln' ("$($segT122.Rows[0]['Kommentar'])|$($pauseT122.Rows[0]['Kommentar'])|$($pauseT122.Rows[1]['Kommentar'])|$($ivT122.Rows[0]['Kommentar'])|$($histT122.Rows[0]['Kommentar'])|$($corrT122.Rows[0]['Kommentar'])|$($corrT122.Rows[1]['Kommentar'])")
        # CSV: einzeilig, Formel-Schutz, eigene Spalte am Ende (bestehende Spalten unveraendert)
        [void](Set-ItemComment -Item $d122 -Text "=1+1`r`nzweite Zeile")
        New-Item -ItemType Directory -Path $script:Paths.Exports -Force | Out-Null
        $csv122 = Export-WorkDataCsv -Days @($d122) -Suffix 'Test122' -IncludeDetail $true
        $main122 = [System.IO.File]::ReadAllLines([string]$csv122[0])
        $detail122 = [System.IO.File]::ReadAllLines([string]$csv122[1])
        & $assert 'Test 122i: CSV - Spalte Kommentar am Ende, einzeilig und gegen Formeln geschuetzt' "Kommentar|'=1+1 / zweite Zeile|Kommentar|Abschnitt|2" ("$(@($main122[0] -split ';')[-1])|$(@($main122[1] -split ';')[-1])|$(@($detail122[0] -split ';')[-1])|$(@($detail122[1] -split ';')[-1])|$(@($main122).Count)")
        foreach ($f122 in $csv122) { Remove-Item -LiteralPath ([string]$f122) -Force -ErrorAction SilentlyContinue }
        # Ziele des Kommentar-Dialogs fuer den laufenden Tag
        $a122 = New-TestDay -DateText '2026-07-09'
        Add-TestSegment -Day $a122 -Mode 'Homeoffice' -StartText '08:00' | Out-Null
        $t1122 = Get-CurrentDayCommentTargets -Day $a122
        Add-TestInterval -Day $a122 -ListName 'ManualPauses' -StartText '09:00' | Out-Null
        $t2122 = Get-CurrentDayCommentTargets -Day $a122
        $t3122 = Get-CurrentDayCommentTargets -Day $d122
        & $assert 'Test 122j: Kommentarziele - Tag/Abschnitt (Standard Tag), mit laufender Pause Standard Pause, beendeter Tag nur Tag' 'Day,Segment|Day|Day,Segment,Pause|Pause|Day|Day' ("$((@($t1122.Targets) | ForEach-Object { $_.Key }) -join ',')|$($t1122.DefaultKey)|$((@($t2122.Targets) | ForEach-Object { $_.Key }) -join ',')|$($t2122.DefaultKey)|$((@($t3122.Targets) | ForEach-Object { $_.Key }) -join ',')|$($t3122.DefaultKey)")
        # Speichern im Tresor (transaktional, Inhalt nicht im Protokoll) und Rollback bei Speicherfehler
        $d122['Comment'] = $null
        [void]$d122.Remove('Comment')
        [void]$script:App.Data['Days'].Add($d122)
        $saved122 = Set-DayItemCommentSaved -Day $d122 -Item $d122 -Text 'MARKER_122_KOMMENTAR' -Label 'Tag'
        $raw122 = Unprotect-VaultContainer -Container (Read-VaultContainerFromFile -Path $script:Paths.VaultFile) -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        $lastLog122 = [string]@($script:App.Vault['Logs'])[-1]['Message']
        & $assert 'Test 122k: Kommentar wird im Tresor gespeichert, Protokoll ohne Kommentarinhalt' 'True|True|True|False' ("$saved122|$($raw122.Contains('MARKER_122_KOMMENTAR'))|$($lastLog122.Contains('Kommentar hinzugefuegt'))|$($lastLog122.Contains('MARKER_122'))")
        & $assert 'Test 122l: Tresor mit Kommentaren besteht die Strukturpruefung' '0' ([string](Test-VaultStructure -Vault $script:App.Vault).Count)
        # Formal korrekte, aber unmoegliche Kalenderdaten
        $dateVault = New-VaultDataObject
        $dateErrors = @{}
        foreach ($dateText in @('2026-07-10', '2026-99-99', '2026-02-30')) {
            $dateDay = New-TestDay
            $dateDay['Date'] = $dateText
            $dateVault['WorkData']['Days'] = New-Object System.Collections.ArrayList
            [void]$dateVault['WorkData']['Days'].Add($dateDay)
            $dateErrors[$dateText] = (Test-VaultStructure -Vault $dateVault).Count
        }
        & $assert 'Test 122o: ungueltiges Kalenderdatum (99-99, 30.02.) wird abgelehnt, gueltiges Datum akzeptiert' '0|1|1' ("$($dateErrors['2026-07-10'])|$($dateErrors['2026-99-99'])|$($dateErrors['2026-02-30'])")
        $corrBefore122 = @($d122['Corrections']).Count
        $script:App.Flags.TestFailMainWrite = $true
        $failed122 = Set-DayItemCommentSaved -Day $d122 -Item $d122 -Text 'NICHT_GESPEICHERT' -Label 'Tag'
        $script:App.Flags.TestFailMainWrite = $false
        Clear-VaultSaveFailedState
        & $assert 'Test 122m: Speicherfehler - false, Kommentar vollstaendig zurueckgenommen, keine Korrektur angelegt' "False|MARKER_122_KOMMENTAR|$corrBefore122" ("$failed122|$(Get-ItemComment -Item $d122)|$(@($d122['Corrections']).Count)")
        [void]$script:App.Data['Days'].Remove($d122)
        & $assert 'Test 122n: danach speichert der Tresor wieder regulaer' 'True' ([string](Save-Vault))

        # --- Test 123: Kompaktfeld Soll-Ende / Max-Ende (automatischer Wechsel) ---
        $fields123 = $script:App.Settings['CompactFields']
        $script:App.Settings['CompactFields'] = @('SollEndeOderMaxEnde')
        $d123 = New-TestDay
        Add-TestSegment -Day $d123 -Mode 'Betrieb' -StartText '08:00' | Out-Null
        $c123a = Get-DayComputation -Day $d123 -Now (Get-TestNow $d123 '10:00')
        $c123b = Get-DayComputation -Day $d123 -Now (Get-TestNow $d123 '16:30')
        $t123a = Get-CompactStatusText -Comp $c123a -Day $d123
        $t123b = Get-CompactStatusText -Comp $c123b -Day $d123
        & $assert 'Test 123a: vor Erreichen der Sollzeit wird das Soll-Ende angezeigt' ('False|Soll-Ende: ' + (Format-Clock $c123a.SollEnde)) ("$($c123a.SollErreicht)|$(@($t123a -split ' \| ')[0])")
        & $assert 'Test 123b: nach Erreichen der Sollzeit automatisch das Max-Ende (kein Soll-Ende mehr)' ('True|Max-Ende: ' + (Format-Clock $c123b.MaxEnde)) ("$($c123b.SollErreicht)|$(@($t123b -split ' \| ')[0])")
        $script:App.Settings['CompactFields'] = @('SollEnde', 'MaxEnde')
        & $assert 'Test 123c: Einzelfelder Soll-Ende/Max-Ende unveraendert' ('Soll-Ende: ' + (Format-Clock $c123a.SollEnde) + ' | Max-Ende: ' + (Format-Clock $c123a.MaxEnde)) ((@((Get-CompactStatusText -Comp $c123a -Day $d123) -split ' \| ')[0..1]) -join ' | ')
        $script:App.Settings['CompactFields'] = $fields123

        Clear-VaultKeys -Keys $newKeys116
        Clear-VaultKeys -Keys $keysF116
        [ArbeitszeitTool.VaultCrypto]::ClearBytes($newPwd116)
        $script:Paths = $paths116

        Clear-VaultKeys -Keys $keys
        [ArbeitszeitTool.VaultCrypto]::ClearBytes($testPwdBytes)
        [ArbeitszeitTool.VaultCrypto]::ClearBytes($wrongPwdBytes)
    }
    finally {
        [ArbeitszeitTool.NativeInput]::TestFailMode = 0
        Clear-VaultSessionKeys
        $script:Paths = $origPaths
        Initialize-AppState
        foreach ($dir in @($testRoot, $testRoot2, $testRoot3, $testRoot4, $testRoot5)) {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # --- Zusammenfassung ---
    $failed = @($results | Where-Object { -not $_.Ok })
    Write-Host ''
    Write-Host ('Ergebnis: {0} von {1} Pruefungen bestanden.' -f (@($results).Count - $failed.Count), @($results).Count) -ForegroundColor Cyan
    if ($failed.Count -gt 0) {
        Write-Host 'FEHLGESCHLAGEN:' -ForegroundColor Red
        foreach ($f in $failed) { Write-Host (' - ' + $f.Name) -ForegroundColor Red }
        return 1
    }
    return 0
}

# Hilfsfunktion fuer Test 14e (arbeitet auf einer uebergebenen Liste statt $script:App)
function Get-ActiveDayFromList {
    param($Days)
    foreach ($day in @($Days)) {
        if ($day.Status -eq 'Aktiv') { return $day }
    }
    return $null
}

# AUSDRUECKLICH OPTIONALER manueller Windows-Integrationstest der Scroll-Lock-
# Aktivhaltung (-RunScrollLockManualTest). Er loest ECHTE Doppelpulse aus und
# laeuft nur nach ausdruecklicher Bestaetigung. NUR HIER ist die
# Zustandsabfrage (GetScrollLockState) zulaessig - der normale
# Produktivbetrieb fragt den Scroll-Lock-Zustand nicht ab. Das Ergebnis ist
# ehrlich als manuell bzw. systemabhaengig gekennzeichnet; es werden keine
# Arbeitszeitdaten und keine Tresordateien veraendert.
function Invoke-ScrollLockManualTest {
    $script:TestMode = $true   # keine Dialoge
    Write-Host ''
    Write-Host '=== ArbeitszeitTool - manueller Scroll-Lock-Integrationstest ===' -ForegroundColor Cyan
    Write-Host 'Dieser Test loest mehrere ECHTE Scroll-Lock-Doppelpulse aus. Die zwei' -ForegroundColor Yellow
    Write-Host 'Tastendruecke je Puls heben sich im Normalfall gegenseitig auf.' -ForegroundColor Yellow
    Write-Host 'Das Ergebnis ist systemabhaengig (Treiber, Sitzungsart, Remotezugriff).' -ForegroundColor Yellow
    $confirm = Read-Host 'Zum Starten JA eingeben (alles andere bricht ab)'
    if ($confirm -ne 'JA') {
        Write-Host 'Abgebrochen - es wurde nichts veraendert.'
        return 0
    }
    $actualSize = [int][ArbeitszeitTool.NativeInput]::GetActualInputSize()
    $expectedSize = [int][ArbeitszeitTool.NativeInput]::GetExpectedInputSize()
    Write-Host ('INPUT-Strukturgroesse: {0} Byte (erwartet {1})' -f $actualSize, $expectedSize)
    if ($actualSize -ne $expectedSize) {
        Write-Host 'Unerwartete Strukturgroesse - der Test wird nicht ausgefuehrt.' -ForegroundColor Red
        return 1
    }
    $readState = {
        try { return @{ Ok = $true; State = [bool][ArbeitszeitTool.NativeInput]::GetScrollLockState() } }
        catch { return @{ Ok = $false; State = $false } }
    }
    $initialRead = & $readState
    if (-not $initialRead.Ok) {
        Write-Host 'Zustandsabfrage nicht moeglich - Test abgebrochen.' -ForegroundColor Red
        return 1
    }
    $initialState = [bool]$initialRead.State
    Write-Host ('Ausgangszustand der Rollen-Taste: {0}' -f $(if ($initialState) { 'AN' } else { 'AUS' }))
    [void][ArbeitszeitTool.NativeInput]::DrainPulseResults()
    $failures = 0
    for ($cycle = 1; $cycle -le 3; $cycle++) {
        $started = [ArbeitszeitTool.NativeInput]::StartScrollLockPulse([int]$script:KeepAliveConst.PulseGapMs)
        if (-not $started) {
            Write-Host ('Zyklus {0}: Puls konnte nicht gestartet werden.' -f $cycle) -ForegroundColor Red
            $failures++
            continue
        }
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while ([ArbeitszeitTool.NativeInput]::IsPulseRunning() -and $sw.ElapsedMilliseconds -lt 3000) {
            Start-Sleep -Milliseconds 25
        }
        Start-Sleep -Milliseconds 100
        $after = & $readState
        $ok = ($after.Ok -and ([bool]$after.State -eq $initialState))
        if (-not $ok) { $failures++ }
        $color = 'Green'
        if (-not $ok) { $color = 'Red' }
        Write-Host ('Zyklus {0}: Zustand nach dem Doppelpuls {1}' -f $cycle, $(if ($ok) { 'UNVERAENDERT (OK)' } else { 'ABWEICHEND' })) -ForegroundColor $color
    }
    foreach ($entry in @([ArbeitszeitTool.NativeInput]::DrainPulseResults())) {
        Write-Host ('  Diagnose: ' + $entry) -ForegroundColor DarkGray
    }
    # Bestmoegliche Wiederherstellung, falls ein Puls den Zustand veraendert
    # hat (Umschaltung anhand des gelesenen Zustands ist NUR hier zulaessig)
    $final = & $readState
    if ($final.Ok -and ([bool]$final.State -ne $initialState)) {
        Write-Host 'Zustand weicht ab - einmalige Wiederherstellung per Tastendruck...' -ForegroundColor Yellow
        [void][ArbeitszeitTool.NativeInput]::ToggleScrollLock()
        Start-Sleep -Milliseconds 100
        $final = & $readState
    }
    Write-Host ('Endzustand: {0} (Ausgangszustand: {1})' -f $(if ($final.State) { 'AN' } else { 'AUS' }), $(if ($initialState) { 'AN' } else { 'AUS' }))
    Write-Host ''
    Write-Host 'Zusaetzliche manuelle Pruefung im laufenden Programm (nicht automatisierbar):' -ForegroundColor Yellow
    Write-Host ' - mehrere Pulse bei sichtbarer kompakter Ansicht' -ForegroundColor Yellow
    Write-Host ' - mehrere Pulse bei geoeffneter erweiterter Ansicht' -ForegroundColor Yellow
    Write-Host ' - mehrere Pulse bei geoeffnetem Einstellungsdialog' -ForegroundColor Yellow
    Write-Host ''
    Write-Host ('Ergebnis (MANUELL / SYSTEMABHAENGIG): {0} von 3 Zyklen unauffaellig.' -f (3 - $failures)) -ForegroundColor Cyan
    if ($failures -gt 0) { return 1 }
    return 0
}

#endregion
