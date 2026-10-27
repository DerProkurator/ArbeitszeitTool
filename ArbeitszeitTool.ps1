#Requires -Version 5.1
<#
==================================================================
 ArbeitszeitTool.ps1
 Lokale Arbeitszeit-Erfassung fuer Windows 10/11
 Windows PowerShell 5.1 + WPF (.NET Framework)
 Keine externen Module, keine Installation, keine Cloud.

 Alle Arbeitszeitdaten, Einstellungen und Protokolle werden in einem
 verschluesselten Datentresor gespeichert (AES-256-CBC + HMAC-SHA256,
 Schluesselableitung PBKDF2-HMAC-SHA256 mit 600.000 Iterationen).
 Das Passwort wird bei jedem Start abgefragt und nirgends gespeichert.

 NETZWERK (optionales Internetradio): Einzige ausgehende Netzwerkfunktion
 ist das optionale Internetradio. Es wird AUSSCHLIESSLICH der ausgewaehlte
 Radiostream vom Streamanbieter abgerufen - Arbeitszeitdaten, Einstellungen
 und Protokolle werden NIEMALS uebertragen. Der Streamanbieter sieht dabei
 technisch uebliche Verbindungsdaten (IP-Adresse, Zeitpunkt, Playeranfrage).
 Unternehmensproxy, Firewall oder Virenschutz koennen den Stream blockieren.
 Ohne gestartetes Radio findet aufgrund dieser Funktion keine
 Streamverbindung statt. Die Nutzung von Internetradio und Scroll-Lock-
 Aktivhaltung muss mit den betrieblichen Vorgaben vereinbar sein.

 Start:    powershell.exe -Sta -NoProfile -File .\ArbeitszeitTool.ps1
 Tests:    nicht Teil dieser Datei (seit 1.4.0) - im Entwicklungs-
           Repository: powershell.exe -NoProfile -File .\tests\Run-Tests.ps1
           (-ScrollLockManual: optionaler, systemabhaengiger Scroll-Lock-
            Integrationstest mit ECHTEN Tastendruecken)

 Hinweis: Es wird keine ExecutionPolicy umgangen oder veraendert.
 Verhindert die Unternehmensrichtlinie die Skriptausfuehrung, ist der
 zulaessige Startweg mit der zustaendigen IT abzustimmen.
==================================================================
 AENDERUNGSJOURNAL
--------------------------------------------------
27.10.2026 - VERSION 1.4.0: TESTSUITE AUSGELAGERT
--------------------------------------------------
 Status: umgesetzt, automatisiert getestet (alle Tests gruen
         ueber tests\Run-Tests.ps1, Test 101b neu).
 - Testsuite (Invoke-InternalTests, Testhelfer, manueller
   Scroll-Lock-Test; ca. 3.060 Zeilen) unveraendert nach
   tests\InternalTests.ps1 verschoben; Testeinstieg
   tests\Run-Tests.ps1. Die Anwendung schrumpft um rund ein
   Viertel.
 - Neuer Schalter -DefinitionsOnly: der Testeinstieg laedt die
   Anwendung per Dot-Sourcing; das Skript endet VOR dem
   Programmstart (kein Tresor, keine Dialoge).
 - $script:AppScriptPath: Quelltextpruefungen der Tests (BOM,
   CRLF, Startlogik, Scroll-Lock-Region) lesen die Anwendung,
   nie die Testdatei.
 - -RunTests / -RunScrollLockManualTest zeigen nur noch einen
   Hinweis (Exit-Code 2), kein Rueckfall auf den Programmstart.
 - .gitattributes: tests/, .gitattributes, .gitignore als
   export-ignore - nicht im GitHub-ZIP/Release-Archiv.
 - Test-Hooks (TestFail* usw.) bleiben vorerst im Programmcode.
 - Unveraendert: Fachlogik, Tresorformat, Datenpfade.
--------------------------------------------------
27.10.2026 - VERSION 1.3.6: KALENDERDATUM VALIDIEREN
--------------------------------------------------
 Status: umgesetzt, automatisiert getestet (Test 122o).
 - Test-VaultStructure prueft das Tagesdatum per
   TryParseExact (bisher nur Format): z. B. 2026-99-99 oder
   2026-02-30 werden abgelehnt, statt spaeter Export und
   Tages-Editor abstuerzen zu lassen. Vom Tool selbst
   angelegte Tage sind immer gueltige Kalenderdaten.
 - BEWUSST NICHT umgesetzt (Risiko, bestehende Tresore
   unladbar bzw. nicht mehr speicherbar zu machen):
   Pflicht-EndedAt / 10h-Pruefung fuer beendete Tage ohne
   Abschlusszeit (Altdaten), Eindeutigkeit des Datums,
   innere WorkData-Schemaversion.
--------------------------------------------------
27.10.2026 - VERSION 1.3.5: KONKURRIERENDE TRESORZUGRIFFE
--------------------------------------------------
 Status: umgesetzt, automatisiert getestet (Tests 63e-63j);
         Einzelinstanz-Meldung beim Doppelstart manuell NICHT
         getestet.
 - Save-Vault Schritt 6: Hauptdatei ueber
   Write-FileInPlaceVerified - Vergleich mit dem in Schritt 4
   geprueften Hash und Schreiben unter EINEM Handle (fremde
   Schreibzugriffe ausgeschlossen), danach Ruecklesen und
   Vergleich ueber dasselbe Handle. Fremdaenderung dazwischen:
   nichts ueberschrieben, Journal/Metadaten zurueck, regulaere
   Konfliktbehandlung (Sicherung nach Recovery).
 - Scheitert die Pruefung NACH dem Schreiben und liegt nicht
   mehr der eigene Stand in der Datei, wird nicht
   zurueckgeschrieben (Fremdaenderung bleibt erhalten).
 - Referenzhash nach dem Commit aus den eigenen Bytes statt
   durch erneutes Lesen der Datei.
 - Einzelinstanz je Datenordner (benannter Mutex, Name aus
   Pfad-Hash); zweiter Start zeigt einen Hinweis und beendet
   sich ohne Dateizugriff auf den Tresor.
 - Konfliktbehandlung als Scriptblock fuer Schritt 4 und die
   spaete Erkennung; Testhook TestBeforeMainWrite.
 - NICHT umgesetzt (bewusst): instanzuebergreifende Sperre
   ueber den gesamten Dateisatz inkl. Journal/Backups und
   Passwortwechsel - fuer ein Einzelplatz-Tool unverhaeltnis-
   maessig; abgedeckt durch Einzelinstanz + Hash-Pruefung.
--------------------------------------------------
27.10.2026 - VERSION 1.3.4: SICHTSCHUTZ AUCH FUER UI
AUTOMATION
--------------------------------------------------
 Status: umgesetzt, automatisiert getestet (Tests 83d/83e).
 - Verborgener Zustand: An die Pausen-/Sperrtabelle der
   erweiterten Ansicht wird nur noch eine maskierte Kopie
   gebunden (Get-MaskedPausesTable: Zeiten '••:••',
   Kommentare '•••', Art lesbar). Zuvor lagen die echten
   Werte trotz Blur im Automation-Baum (Screenreader).
 - Echte Tabelle nur im Speicher (Ui.ExtendedPauseTable);
   Bindung zentral ueber Set-ExtendedPausesSource, auch beim
   Umschalten des Sichtschutzes.
--------------------------------------------------
27.10.2026 - VERSION 1.3.3: KONFLIKTSICHERUNG EHRLICH MELDEN
--------------------------------------------------
 Status: umgesetzt, automatisiert getestet (Test 63c/63d).
 - Externe Aenderung erkannt: Die Sicherung des eigenen
   Standes nach Recovery wird per Hash geprueft. Nur bei
   Erfolg Warnung mit Pfad ("gesichert"); bei Fehlschlag
   Fehlermeldung "NICHT gesichert - Anwendung nicht beenden"
   und ERROR-Protokolleintrag (zuvor leerer catch und
   unbedingte Erfolgsmeldung).
 - Testhook TestFailConflictCopy, Flag LastConflictCopySaved.
--------------------------------------------------
27.10.2026 - VERSION 1.3.2: TAGES-EDITOR LAYOUT UND
KOMMENTARZUGANG
--------------------------------------------------
 Status: umgesetzt, automatisiert getestet (alle Tests gruen),
         XAML offscreen geladen; Layout manuell geprueft.
 - Tages-Editor neu gegliedert: Arbeitsabschnitte oben immer
   sichtbar; Manuelle Pausen, Sperrintervalle und
   Aenderungsprotokoll als Reiter darunter (Titel mit Anzahl).
   Schaltflaechen als Leiste unter der Tabelle - der vierte
   Button "Kommentar..." lag zuvor ausserhalb des sichtbaren
   Bereichs, "Loeschen" war abgeschnitten.
 - "Bearbeiten" (Abschnitt/Pause/Sperrintervall) zeigt und
   aendert den Kommentar des Eintrags; separates Feld
   "Begruendung der Zeitaenderung" fuer das Protokoll.
 - Bearbeiten ohne Aenderung von Modus/Zeiten (Minutenebene)
   legt keine Korrektur mehr an und setzt 'Korrigiert' nicht;
   ein reiner Kommentarwechsel wird wie ueber "Kommentar..."
   transaktional gespeichert.
 - Doppelklick auf eine Zeile = Bearbeiten (Protokoll:
   Kommentar); Kommentarspalte doppelt breit, voller Kommentar
   als Tooltip.
 - Offenes Ende im Korrektur-Neuwert einheitlich leer statt
   '--:--' (vorher z. B. "17:09---:--").
 - Tests 122i/122l korrigiert: Rueckgabe per 'return ,$list'
   wurde mit @(...) doppelt verpackt (122i brach ab und
   verdeckte 122j-122n, 122l zaehlte die leere Fehlerliste
   als 1).
--------------------------------------------------
27.10.2026 - VERSION 1.3.1: KOMPAKTFELD SOLL-ENDE /
MAX-ENDE
--------------------------------------------------
 Status: umgesetzt, automatisiert getestet (Tests 123a-123c);
         Einstellungsdialog manuell NICHT getestet.
 - Neues waehlbares Feld 'SollEndeOderMaxEnde' fuer die kompakte
   Ansicht und eigene Presets: zeigt bis zum Erreichen der
   Sollzeit das Soll-Ende, danach automatisch das Max-Ende
   (analog Soll-Rest / Ueberstunden).
 - Soll-Ende-/Max-Ende-Text gemeinsam erzeugt (identisches
   Format inkl. '*' bei pausierter Prognose).
--------------------------------------------------
27.10.2026 - VERSION 1.3.0: KOMMENTARE
--------------------------------------------------
 Status: umgesetzt, automatisiert getestet (Tests 122a-122n);
         Dialoge/Menues/Layout manuell NICHT getestet.
 - Optionales Feld 'Comment' an Tag, Abschnitt, manueller Pause,
   Sperrintervall und Korrektur (max. 1000 Zeichen, normalisiert;
   leer = kein Feld). Kein Schemawechsel - aeltere Tresore laden
   unveraendert.
 - Neuer Kommentar-Dialog (Show-CommentDialog); "Kommentar..." im
   Kontext-/Tray-Menue und in der erweiterten Ansicht fuer Tag,
   laufenden Abschnitt oder laufende Pause.
 - Tages-Editor: Tageskommentar, Kommentar je Liste, neues
   Aenderungsprotokoll (Korrekturen) mit Kommentarspalte; neue
   Eintraege mit Kommentar, Korrekturen mit optionaler Begruendung.
 - Spalte 'Kommentar' in Abschnitts-/Pausen-/Intervalltabellen,
   Verlauf und CSV-Export (letzte Spalte, einzeilig,
   Formelschutz).
 - Kommentaraenderungen sind transaktional (Rollback bei
   Speicherfehler), zaehlen nicht als Korrektur; das Protokoll
   enthaelt keinen Kommentarinhalt.
 - Kommentare fliessen in den Inhaltsvergleich beim Import ein.
--------------------------------------------------
27.10.2026 - VERSION 1.2.0: SCROLL-LOCK-AKTIVHALTUNG ALS
OPTIONALE FUNKTION ZURUECK
--------------------------------------------------
 Status: umgesetzt, automatisiert getestet (Tests 15/16, 70,
         118a-118g); Menues/Einstellungsdialog und echte
         Tastendruecke manuell NICHT getestet.
 - Aktivhaltung aus 1.0.0 wiederhergestellt: C#-Doppelpuls
   (SendInput auf ThreadPool-Thread), Timer, Einstellungs-Tab,
   Kontext-/Tray-Menueeintrag, Kompaktfeld 'ScrollLock' und
   -RunScrollLockManualTest.
 - Opt-in: KeepAliveEnabled ist standardmaessig AUS; Tresore aus
   1.1.x (ohne Aktivhaltungswerte) laden mit ausgeschalteter
   Funktion, Tresore aus 1.0.0 behalten ihre Werte.
 - Beschriftung im Einstellungsdialog korrigiert
   ("Standard: aus" statt "Standard: ein").
 - Beibehalten aus 1.1.0: unbekannte Kompaktfelder werden beim
   Laden verworfen.
 - Hinweis: Das Skript enthaelt damit wieder Code zur
   Tastatureingabe-Simulation (auch wenn die Funktion
   ausgeschaltet ist). Einsatz mit IT/Sicherheit abstimmen.
--------------------------------------------------
22.10.2026 - VERSION 1.1.1: SECURITY-NACHBESSERUNG
RECOVERY-NEUVERSCHLUESSELUNG
--------------------------------------------------
 Status: umgesetzt, automatisiert getestet (Tests 119a-121f);
         Dialogtexte/UI manuell NICHT getestet.
 - Invoke-RecoveryReencryption ordnet jede Datei genau einer
   Kategorie zu (neu verschluesselt / anderes Passwort /
   beschaedigt / keine Tresordatei / fehlgeschlagen). Gesperrte,
   nicht lesbare oder verschwundene Dateien und ein nicht
   auflistbarer Ordner gelten als FEHLER, nicht als uebersprungen.
 - SHA-256-Referenz je Datei: das Original wird nur ueberschrieben,
   wenn es seit dem Lesen unveraendert ist (Pruefung und Schreiben
   ueber denselben exklusiven Handle, Write-FileInPlaceIfUnchanged);
   sonst Konflikt, nichts ueberschrieben. Pruefkopie mit
   CreateNew - vorhandene Restkopien werden nie ueberschrieben.
 - Fehlgeschlagenes Entfernen der Pruefkopie zaehlt nicht mehr als
   Fehlschlag (eigene Kategorie, Abschlussmeldung mit Hinweis).
 - Recovery-Phase mit neutralem Transaktionsstatus (vault.txn,
   Kind 'RecoveryReencryption'); Startpruefung meldet eine
   unterbrochene Phase und loest .azt.new-Reste nur bei eindeutigem
   Stand auf (Resolve-RecoveryReencryptionLeftovers), sonst bleibt
   alles byteidentisch erhalten.
 - .old-Reste in Data werden nach Recovery gesichert und mit
   umgestellt; Data wird abschliessend auf Dateien ohne neues
   Passwort geprueft. Abschlussmeldung unterscheidet vollstaendig /
   vollstaendig mit offener Bereinigung / teilweise
   (Get-PasswordChangeReport).
 - Unveraendert: regulaerer Speicherzyklus (Save-Vault,
   Write-FileInPlace), Containerformat, Kryptografie.
--------------------------------------------------
22.10.2026 - VERSION 1.1.0: SCROLL-LOCK-AKTIVHALTUNG
ENTFERNT
--------------------------------------------------
 Status: umgesetzt, automatisiert getestet (Test 118a-118d);
         Menues/Einstellungsdialog manuell NICHT getestet.
 - Aktivhaltung vollstaendig entfernt: C#-Tastatureingabe,
   Timer, Einstellungen (Tab, Kontext-/Tray-Menue, Kompaktfeld)
   und der manuelle Integrationstest samt Startparameter.
 - Die Anwendung simuliert keine Eingaben mehr und beeinflusst
   die automatische Bildschirmsperre nicht.
 - Rueckwaertskompatibel: alte Werte KeepAliveEnabled/
   KeepAliveIntervalSec und das Kompaktfeld 'ScrollLock' werden
   beim Laden verworfen (auch in eigenen Presets).
 - Entfallene Tests: 15/16 und 70.
--------------------------------------------------
22.10.2026 - SECURITY-REVIEW: PASSWORTAENDERUNG UND
RECOVERY
--------------------------------------------------
 Status: umgesetzt, automatisiert getestet (Tests 116a-117c);
         Dialogtexte/UI manuell NICHT getestet.
 - Passwortaenderung verschluesselt jetzt auch alle mit dem
   bisherigen Passwort lesbaren Container im Ordner Recovery neu
   (Invoke-RecoveryReencryption); fremde/beschaedigte Dateien
   bleiben byteidentisch. Nicht umgestellte Dateien werden
   gemeldet und protokolliert.
 - Keine Passwortaenderung bei extern veraenderter vault.azt
   (Test-VaultMainFileUnchanged, Massstab wie Save-Vault).
 - Unvollstaendige Ruecknahme einer gescheiterten Uebernahme
   wird nicht mehr als "wiederhergestellt" gemeldet; stumm nach
   Recovery verschobene Backups werden protokolliert.
 - STA-Neustart startet powershell.exe ueber den festen
   Systempfad statt ueber den Suchpfad.
 - Speicherzyklus, Journal, Backups und Containerformat sind
   unveraendert.
--------------------------------------------------
19.07.2026 - OPTIONALER PC-SHUTDOWN BEIM
ANWENDUNGSSCHLIESSEN
--------------------------------------------------
 Status: umgesetzt, statisch geprueft, automatisiert getestet
         (Tests 114a-114r); UI-Optik und echter Shutdownstart
         manuell NICHT getestet.
 - Die vorhandene Opt-in-Einstellung ShutdownOfferEnabled gilt
   jetzt zusaetzlich fuer den Dialog "Anwendung schliessen"
   (kein neuer persistenter Schalter, Standard bleibt false).
 - Zusaetzliche eindeutige Shutdown-Auswahl im Schliessen-Dialog:
   mit aktivem Tag "Arbeitstag beenden, Anwendung schliessen und
   PC herunterfahren", ohne aktiven Tag "Anwendung schliessen und
   PC herunterfahren"; bei deaktivierter Einstellung vollstaendig
   ausgeblendet.
 - Ein aktiver Arbeitstag wird VOR dem Shutdown vollstaendig
   validiert und beendet (Complete-WorkDay, keine -SkipValidation);
   es gibt keinen Pfad, der den PC mit offenem Arbeitstag
   herunterfaehrt.
 - Gemeinsamer sicherer Shutdownpfad Invoke-SafeApplicationShutdown
   (Fensterposition, Radiostatus, CleanShutdown=true, finaler
   Save-Vault, Radioabbau, Shutdown-Anforderung, erst danach
   CloseConfirmed/kontrolliertes Schliessen);
   Invoke-EndDayShutdown bleibt als kompatibler Wrapper erhalten.
 - Kein Shutdown bei Speicherfehler; bei fehlgeschlagenem
   Shutdownstart werden CleanShutdown und Radiozustand
   wiederhergestellt und der korrigierte Sitzungsstatus erneut
   gespeichert (sonst NICHT-GESPEICHERT-Anzeige).
 - Ergaenzte Tests 114a-114r; automatisierte Tests starten
   niemals shutdown.exe (ausschliesslich Simulationsflags).
==================================================================
#>
[CmdletBinding()]
param(
    # Veraltet seit 1.4.0: Die Tests liegen in tests\ (nicht Teil der
    # Auslieferung). Beide Schalter zeigen nur noch einen Hinweis an.
    [switch]$RunTests,
    [switch]$RunScrollLockManualTest,
    # Nur fuer den Testeinstieg tests\Run-Tests.ps1 (Dot-Sourcing): stellt
    # Funktionen und Konstanten bereit und endet VOR dem Programmstart -
    # kein Tresor, keine Dialoge, keine Dateizugriffe.
    [switch]$DefinitionsOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Off
# Pfad dieser Datei - auch bei Dot-Sourcing durch den Testeinstieg; die
# Quelltextpruefungen der Tests lesen darueber die Anwendung selbst.
$script:AppScriptPath = $PSCommandPath

#region ===== Initialisierung: STA, Assemblies, Interop =====

# WPF benoetigt einen STA-Thread. powershell.exe startet ab v3 standardmaessig
# in STA; falls nicht (z. B. Sonderfaelle), Neustart mit -Sta.
# Bewusst ohne -ExecutionPolicy: geltende Richtlinien werden nicht umgangen.
# Fester Systempfad statt Suchpfad (keine fremde powershell.exe aus dem
# aktuellen Verzeichnis oder PATH).
if (-not $RunTests -and -not $RunScrollLockManualTest -and -not $DefinitionsOnly -and [System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $psExe = Join-Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::System)) 'WindowsPowerShell\v1.0\powershell.exe'
    Start-Process -FilePath $psExe -ArgumentList @('-Sta', '-NoProfile', '-File', "`"$PSCommandPath`"")
    exit
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# C#-Interop:
#  - SessionMonitor: puffert Lock/Unlock-Zeitstempel threadsicher (wird vom
#    UI-Timer ausgelesen -> keine Runspace-Probleme mit PowerShell-Events)
#  - NativeInput:    Scroll-Lock-Doppelpuls via SendInput auf einem
#                    ThreadPool-Thread (Zustandsabfrage nur im manuellen Test)
#  - NativeWindow:   Topmost erneut setzen ohne Aktivierung (SWP_NOACTIVATE)
$interopSource = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.Win32;

namespace ArbeitszeitTool
{
    public static class SessionMonitor
    {
        private static readonly object Gate = new object();
        private static readonly List<object[]> Events = new List<object[]>();
        private static bool _started = false;
        public static volatile bool IsLocked = false;

        public static void Start()
        {
            if (_started) return;
            SystemEvents.SessionSwitch += OnSwitch;
            _started = true;
        }

        public static void Stop()
        {
            if (!_started) return;
            SystemEvents.SessionSwitch -= OnSwitch;
            _started = false;
        }

        private static void OnSwitch(object sender, SessionSwitchEventArgs e)
        {
            if (e.Reason == SessionSwitchReason.SessionLock)
            {
                lock (Gate) { Events.Add(new object[] { DateTime.Now, "Lock" }); }
                IsLocked = true;
            }
            else if (e.Reason == SessionSwitchReason.SessionUnlock)
            {
                lock (Gate) { Events.Add(new object[] { DateTime.Now, "Unlock" }); }
                IsLocked = false;
            }
        }

        public static object[][] Drain()
        {
            lock (Gate)
            {
                object[][] result = Events.ToArray();
                Events.Clear();
                return result;
            }
        }
    }

    // Scroll-Lock-Doppelpuls: vollstaendig gekapselt, laeuft auf einem
    // ThreadPool-Thread (niemals auf dem WPF-Dispatcher-Thread). KEINE
    // Zustandsabfrage im Produktivbetrieb - GetScrollLockState existiert nur
    // noch fuer den optionalen manuellen Diagnosetest. Ergebnisse werden als
    // Diagnosezeilen gepuffert und vom UI-Timer abgeholt (Drain), damit der
    // Hintergrundthread niemals PowerShell-/WPF-Objekte beruehrt.
    public static class NativeInput
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct KEYBDINPUT
        {
            public ushort wVk;
            public ushort wScan;
            public uint dwFlags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MOUSEINPUT
        {
            public int dx;
            public int dy;
            public uint mouseData;
            public uint dwFlags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Explicit)]
        private struct INPUTUNION
        {
            [FieldOffset(0)] public KEYBDINPUT ki;
            [FieldOffset(0)] public MOUSEINPUT mi;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct INPUT
        {
            public uint type;
            public INPUTUNION u;
        }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

        [DllImport("user32.dll")]
        private static extern short GetKeyState(int nVirtKey);

        private const int VK_SCROLL = 0x91;
        private const uint INPUT_KEYBOARD = 1;
        private const uint KEYEVENTF_KEYUP = 0x0002;

        // Abstand der beiden Tastendruecke: Standard 200 ms, zulaessig 100-300 ms
        public const int DefaultPulseGapMs = 200;
        public const int MinPulseGapMs = 100;
        public const int MaxPulseGapMs = 300;

        // 0 = kein Puls aktiv, 1 = Puls laeuft (ausschliesslich via Interlocked)
        private static int _pulseRunning = 0;

        // 1 = Anwendung faehrt herunter: keine neuen Pulse mehr starten
        private static int _shutdown = 0;

        // Nur fuer -RunTests: 0 = normal (echte Eingaben),
        // 1 = erster Tastendruck schlaegt fehl (simuliert),
        // 2 = zweiter Tastendruck schlaegt fehl (simuliert),
        // 3 = simulierter ERFOLG (fuer den normalen automatischen Testfall),
        // 4 = simulierte Ablehnung des Hintergrundauftrags (QueueUserWorkItem=false).
        // In JEDEM Testmodus (!= 0) werden KEINE echten Eingaben gesendet.
        public static volatile int TestFailMode = 0;

        // Beim regulaeren Programmende aufrufen: ab dann werden keine neuen
        // Pulse mehr gestartet; ein laufender Puls beendet sich regulaer.
        public static void BeginShutdown()
        {
            Interlocked.Exchange(ref _shutdown, 1);
        }

        private static readonly object PulseGate = new object();
        private static readonly List<string> PulseResults = new List<string>();

        // NUR fuer den optionalen manuellen Diagnosetest - der normale
        // Produktivbetrieb fragt den Scroll-Lock-Zustand nicht ab.
        public static bool GetScrollLockState()
        {
            return (GetKeyState(VK_SCROLL) & 1) == 1;
        }

        // Erwartete Groesse der INPUT-Struktur: 28 Byte (x86) / 40 Byte (x64)
        public static int GetExpectedInputSize()
        {
            return (IntPtr.Size == 8) ? 40 : 28;
        }

        public static int GetActualInputSize()
        {
            return Marshal.SizeOf(typeof(INPUT));
        }

        public static bool IsPulseRunning()
        {
            return Interlocked.CompareExchange(ref _pulseRunning, 0, 0) == 1;
        }

        // Diagnosezeilen abgeschlossener Pulse abholen (threadsicher)
        public static string[] DrainPulseResults()
        {
            lock (PulseGate)
            {
                string[] result = PulseResults.ToArray();
                PulseResults.Clear();
                return result;
            }
        }

        private static void AddResult(string text)
        {
            lock (PulseGate)
            {
                PulseResults.Add(text);
                if (PulseResults.Count > 100) { PulseResults.RemoveAt(0); }
            }
        }

        // Ein vollstaendiger Tastendruck (Key Down + Key Up). Liefert die
        // Anzahl der von SendInput uebernommenen Ereignisse (0..2).
        // which: 1 = erster, 2 = zweiter Tastendruck des Doppelpulses.
        private static uint SendFullKeyPress(int failMode, int which)
        {
            if (failMode != 0)
            {
                // Testmodus: keine echten Eingaben senden
                if (failMode == which) { return (uint)((which == 1) ? 1 : 0); }
                return 2;
            }
            INPUT[] inputs = new INPUT[2];
            inputs[0].type = INPUT_KEYBOARD;
            inputs[0].u.ki.wVk = VK_SCROLL;
            inputs[1].type = INPUT_KEYBOARD;
            inputs[1].u.ki.wVk = VK_SCROLL;
            inputs[1].u.ki.dwFlags = KEYEVENTF_KEYUP;
            return SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
        }

        // Bestmoeglich ein einzelnes Key-Up nachsenden (schaltet nicht um),
        // damit keine Taste logisch gedrueckt haengen bleibt.
        private static void SendKeyUpBestEffort(int failMode)
        {
            if (failMode != 0) { return; }
            try
            {
                INPUT[] inputs = new INPUT[1];
                inputs[0].type = INPUT_KEYBOARD;
                inputs[0].u.ki.wVk = VK_SCROLL;
                inputs[0].u.ki.dwFlags = KEYEVENTF_KEYUP;
                SendInput(1, inputs, Marshal.SizeOf(typeof(INPUT)));
            }
            catch { }
        }

        // Startet den Doppelpuls im Hintergrund (ThreadPool). Liefert false,
        // wenn bereits ein Puls laeuft oder die INPUT-Groesse unerwartet ist -
        // dann passiert nichts weiter (nur Diagnoseeintrag): kein Dialog,
        // keine Einstellungsaenderung, naechster regulaerer Intervall.
        public static bool StartScrollLockPulse(int gapMs)
        {
            if (gapMs < MinPulseGapMs) { gapMs = MinPulseGapMs; }
            if (gapMs > MaxPulseGapMs) { gapMs = MaxPulseGapMs; }
            if (Interlocked.CompareExchange(ref _shutdown, 0, 0) == 1)
            {
                return false; // Programmende: keine neuen Pulse mehr
            }
            if (Marshal.SizeOf(typeof(INPUT)) != GetExpectedInputSize())
            {
                AddResult("FEHLER|INPUT-Struktur " + Marshal.SizeOf(typeof(INPUT)) +
                    " statt " + GetExpectedInputSize() + " Byte - SendInput nicht ausgefuehrt");
                return false;
            }
            if (Interlocked.CompareExchange(ref _pulseRunning, 1, 0) != 0)
            {
                return false; // es laeuft bereits ein Puls
            }
            int captured = gapMs;
            bool queued = false;
            try
            {
                if (TestFailMode == 4)
                {
                    queued = false; // Testmodus: Ablehnung des Auftrags simulieren
                }
                else
                {
                    queued = ThreadPool.QueueUserWorkItem(delegate(object unused) { RunPulse(captured); });
                }
            }
            catch (Exception ex)
            {
                Interlocked.Exchange(ref _pulseRunning, 0);
                AddResult("FEHLER|Hintergrundstart fehlgeschlagen: " + ex.Message);
                return false;
            }
            if (!queued)
            {
                // Rueckgabewert von QueueUserWorkItem auswerten: der Pulsstatus
                // darf unter keinem Fehlerpfad dauerhaft auf 1 haengen bleiben.
                Interlocked.Exchange(ref _pulseRunning, 0);
                AddResult("FEHLER|Hintergrundauftrag wurde nicht angenommen");
                return false;
            }
            return true;
        }

        // Vollstaendiger Doppelpuls auf dem Hintergrundthread:
        // Tastendruck 1 -> Wartezeit (Thread.Sleep) -> Tastendruck 2.
        // Der Laufstatus wird in JEDEM Fall wieder freigegeben (finally).
        // Schlaegt der erste Tastendruck fehl, wird KEIN zweiter
        // Umschaltvorgang erzwungen; nach einem Teilerfolg wird bestmoeglich
        // ein separates Key-Up nachgesendet.
        private static void RunPulse(int gapMs)
        {
            try
            {
                int failMode = TestFailMode;
                bool pool = Thread.CurrentThread.IsThreadPoolThread;
                uint accepted1 = SendFullKeyPress(failMode, 1);
                if (accepted1 != 2)
                {
                    // Marshal.GetLastWin32Error NUR auswerten, wenn SendInput
                    // nicht die erwartete Ereigniszahl uebernommen hat - nach
                    // einem Erfolg kann der Fehlercode ein alter Wert sein.
                    int err1 = Marshal.GetLastWin32Error();
                    SendKeyUpBestEffort(failMode);
                    AddResult("FEHLER|Erster Tastendruck unvollstaendig: uebernommen=" +
                        accepted1 + " Win32=" + err1 + " pool=" + pool + " test=" + (failMode != 0));
                    return;
                }
                int t0 = Environment.TickCount;
                Thread.Sleep(gapMs);
                int elapsed = Environment.TickCount - t0;
                uint accepted2 = SendFullKeyPress(failMode, 2);
                if (accepted2 != 2)
                {
                    int err2 = Marshal.GetLastWin32Error();
                    SendKeyUpBestEffort(failMode);
                    AddResult("FEHLER|Zweiter Tastendruck unvollstaendig: uebernommen=" +
                        accepted2 + " Win32=" + err2 + " pool=" + pool + " test=" + (failMode != 0));
                    return;
                }
                AddResult("OK|accepted1=2 accepted2=2 gapMs=" + gapMs +
                    " elapsedMs=" + elapsed + " pool=" + pool + " test=" + (failMode != 0));
            }
            catch (Exception ex)
            {
                AddResult("FEHLER|Ausnahme im Doppelpuls: " + ex.Message);
            }
            finally
            {
                Interlocked.Exchange(ref _pulseRunning, 0);
            }
        }

        // NUR fuer den optionalen manuellen Diagnosetest (einmalige
        // Wiederherstellung): ein einzelner vollstaendiger Tastendruck.
        public static bool ToggleScrollLock()
        {
            return SendFullKeyPress(0, 0) == 2;
        }
    }

    public static class NativeWindow
    {
        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
            int X, int Y, int cx, int cy, uint uFlags);

        private static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
        private const uint SWP_NOSIZE = 0x0001;
        private const uint SWP_NOMOVE = 0x0002;
        private const uint SWP_NOACTIVATE = 0x0010;

        // Fenster im Vordergrund halten, ohne Fokus zu stehlen.
        public static void EnsureTopmostNoActivate(IntPtr hWnd)
        {
            if (hWnd != IntPtr.Zero)
            {
                SetWindowPos(hWnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            }
        }
    }
}
'@

if (-not ('ArbeitszeitTool.NativeInput' -as [type])) {
    Add-Type -TypeDefinition $interopSource -ReferencedAssemblies @('System') -Language CSharp
}

# Kryptografie-Kern in eingebettetem C# (nur .NET-Framework-Bordmittel):
#  - PBKDF2-HMAC-SHA256 (Rfc2898DeriveBytes mit expliziter HashAlgorithmName-
#    Ueberladung; existiert erst ab .NET Framework 4.7.2 - fehlt sie, schlaegt
#    bereits die Kompilierung fehl und es gibt KEINEN stillen SHA1-Rueckfall)
#  - AES-256-CBC mit PKCS#7-Padding
#  - HMAC-SHA256 (Encrypt-then-MAC), zeitkonstanter Vergleich
#  - Zufall ausschliesslich ueber RandomNumberGenerator
$vaultCryptoSource = @'
using System;
using System.Security.Cryptography;
using System.Text;

namespace ArbeitszeitTool
{
    public static class VaultCrypto
    {
        public static byte[] GetRandomBytes(int count)
        {
            byte[] data = new byte[count];
            using (RandomNumberGenerator rng = RandomNumberGenerator.Create())
            {
                rng.GetBytes(data);
            }
            return data;
        }

        // PBKDF2-HMAC-SHA256. Die verwendete Ueberladung erzwingt SHA256;
        // der klassische Konstruktor (intern SHA1) wird bewusst nicht benutzt.
        public static byte[] DeriveKeyMaterial(byte[] password, byte[] salt, int iterations, int byteCount)
        {
            if (password == null) throw new ArgumentNullException("password");
            if (salt == null || salt.Length < 16) throw new ArgumentException("Salt zu kurz.");
            if (iterations < 1) throw new ArgumentException("Iterationszahl ungueltig.");
            using (Rfc2898DeriveBytes kdf = new Rfc2898DeriveBytes(password, salt, iterations, HashAlgorithmName.SHA256))
            {
                return kdf.GetBytes(byteCount);
            }
        }

        // Zeitkonstanter Bytevergleich (CryptographicOperations.FixedTimeEquals
        // existiert im .NET Framework nicht). Die HMAC-Laenge ist konstant und
        // nicht geheim, daher darf bei Laengendifferenz frueh beendet werden.
        public static bool FixedTimeEquals(byte[] a, byte[] b)
        {
            if (a == null || b == null) return false;
            if (a.Length != b.Length) return false;
            int diff = 0;
            for (int i = 0; i < a.Length; i++)
            {
                diff |= a[i] ^ b[i];
            }
            return diff == 0;
        }

        public static byte[] AesEncrypt(byte[] plain, byte[] key, byte[] iv)
        {
            using (Aes aes = Aes.Create())
            {
                aes.KeySize = 256;
                aes.Mode = CipherMode.CBC;
                aes.Padding = PaddingMode.PKCS7;
                aes.Key = key;
                aes.IV = iv;
                using (ICryptoTransform enc = aes.CreateEncryptor())
                {
                    return enc.TransformFinalBlock(plain, 0, plain.Length);
                }
            }
        }

        public static byte[] AesDecrypt(byte[] cipher, byte[] key, byte[] iv)
        {
            using (Aes aes = Aes.Create())
            {
                aes.KeySize = 256;
                aes.Mode = CipherMode.CBC;
                aes.Padding = PaddingMode.PKCS7;
                aes.Key = key;
                aes.IV = iv;
                using (ICryptoTransform dec = aes.CreateDecryptor())
                {
                    return dec.TransformFinalBlock(cipher, 0, cipher.Length);
                }
            }
        }

        public static byte[] ComputeHmacSha256(byte[] key, byte[] data)
        {
            using (HMACSHA256 hmac = new HMACSHA256(key))
            {
                return hmac.ComputeHash(data);
            }
        }

        // Authentifizierte Daten fuer Encrypt-then-MAC:
        // Formatkennung | Version | KDF | Iterationen | Salt | IV | Ciphertext
        public static byte[] BuildAuthData(string magic, int version, string kdf, int iterations, byte[] salt, byte[] iv, byte[] cipher)
        {
            byte[] header = Encoding.UTF8.GetBytes(magic + "|" + version.ToString() + "|" + kdf + "|" + iterations.ToString() + "|");
            byte[] result = new byte[header.Length + salt.Length + iv.Length + cipher.Length];
            int offset = 0;
            Buffer.BlockCopy(header, 0, result, offset, header.Length); offset += header.Length;
            Buffer.BlockCopy(salt, 0, result, offset, salt.Length); offset += salt.Length;
            Buffer.BlockCopy(iv, 0, result, offset, iv.Length); offset += iv.Length;
            Buffer.BlockCopy(cipher, 0, result, offset, cipher.Length);
            return result;
        }

        public static void ClearBytes(byte[] data)
        {
            if (data != null)
            {
                Array.Clear(data, 0, data.Length);
            }
        }
    }
}
'@

$script:VaultCryptoReady = $false
$script:VaultCryptoError = ''
try {
    if (-not ('ArbeitszeitTool.VaultCrypto' -as [type])) {
        Add-Type -TypeDefinition $vaultCryptoSource -ReferencedAssemblies @('System', 'System.Core') -Language CSharp
    }
    # Selbsttest: SHA256-Ableitung muss funktionieren (kein SHA1-Rueckfall moeglich)
    $probe = [ArbeitszeitTool.VaultCrypto]::DeriveKeyMaterial([byte[]]@(1, 2, 3), [byte[]](1..16), 10, 32)
    if ($probe.Length -eq 32) { $script:VaultCryptoReady = $true }
    [ArbeitszeitTool.VaultCrypto]::ClearBytes($probe)
}
catch {
    $script:VaultCryptoError = $_.Exception.Message
}

#endregion

#region ===== Pfade, Konstanten, Logging =====

$script:Paths = @{
    Root           = $PSScriptRoot
    Data           = Join-Path $PSScriptRoot 'Data'
    Exports        = Join-Path $PSScriptRoot 'Exports'
    Recovery       = Join-Path $PSScriptRoot 'Recovery'
    # Verschluesselter Tresor (stabile, neutrale Dateinamen - siehe README)
    VaultFile      = Join-Path $PSScriptRoot 'Data\vault.azt'
    VaultPending   = Join-Path $PSScriptRoot 'Data\vault.pending.azt'
    VaultBackup1   = Join-Path $PSScriptRoot 'Data\vault.backup1.azt'
    VaultBackup2   = Join-Path $PSScriptRoot 'Data\vault.backup2.azt'
    # Beiseite gelegter alter Hauptstand waehrend eines Speichervorgangs
    VaultPrev      = Join-Path $PSScriptRoot 'Data\vault.prev.azt'
    # Neutraler Transaktionsstatus einer Passwortaenderung (keine Arbeitszeitdaten)
    VaultTxn       = Join-Path $PSScriptRoot 'Data\vault.txn'
    # Alt-Dateien (Klartext) - nur noch fuer die einmalige Migration relevant
    LegacyWork     = Join-Path $PSScriptRoot 'Data\worktime.json'
    LegacyBackup   = Join-Path $PSScriptRoot 'Data\worktime.backup.json'
    LegacySettings = Join-Path $PSScriptRoot 'Data\settings.json'
    LegacyLog      = Join-Path $PSScriptRoot 'Logs\application.log'
    LegacyLogDir   = Join-Path $PSScriptRoot 'Logs'
}

# Versionsstand der Anwendung (fuer Fenstertitel und Einstellungen-Dialog)
$script:AppVersion = '1.4.0'

# Feste, nicht ueber die Einstellungen aenderbare Grenzen
$script:Const = @{
    SchemaVersion           = 1     # Schema der WorkData-Struktur (Tage/Segmente)
    VaultSchemaVersion      = 2     # Schema des entschluesselten Tresorinhalts
    MaxMinutes              = 600   # 10:00 h  - maximale Netto-Arbeitszeit
    WarnMinutes             = 585   # 09:45 h  - Vorwarnung
    BetriebPauseMinutes     = 45    # feste Betriebspause
    BetriebPauseNachMinuten = 360   # Pause beginnt nach 6 h Betriebszeit
    HoGapPromptMinutes      = 3     # ab dieser Luecke wird im Homeoffice nachgefragt
    MaxLogEntries           = 5000  # aktuelle Logeintraege im Tresor
    LogArchiveChunk         = 1000  # Anzahl Eintraege, die pro Rotation archiviert werden
    MaxArchivedEntries      = 20000 # Obergrenze des verschluesselten Logarchivs
}

# Kryptografie-Parameter des Tresor-Containers
$script:VaultConst = @{
    Magic            = 'AZTVAULT'
    ContainerVersion = 1
    Kdf              = 'PBKDF2-HMAC-SHA256'
    Iterations       = 600000
    SaltBytes        = 32    # Mindestanforderung: 16
    IvBytes          = 16
    KeyBytes         = 32    # AES-256
    HmacBytes        = 32    # HMAC-SHA256
    KeyMaterialBytes = 64    # 32 Byte AES + 32 Byte HMAC
    MinIterations    = 600000
    MaxIterations    = 5000000
    MinPasswordLen   = 12
    MaxPasswordLen   = 256
    # Plausibilitaetsgrenzen des Containers (Schutz vor uebergrossen Dateien)
    MaxFileBytes     = 100MB   # maximale Groesse einer Tresordatei
    MaxFieldChars    = 140000000 # maximale Laenge eines Base64-Feldes (Zeichen)
}

function Initialize-Folders {
    foreach ($dir in @($script:Paths.Data, $script:Paths.Exports)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
}

# Verschluesseltes Logging: Eintraege liegen ausschliesslich im Tresor.
# Vor dem Entsperren werden Eintraege nur im Arbeitsspeicher gepuffert und
# nach erfolgreichem Entsperren in den Tresor uebernommen - es entsteht
# niemals eine unverschluesselte Logdatei auf dem Datentraeger.
$script:StartupLogBuffer = New-Object System.Collections.ArrayList

# Im Testlauf (-RunTests) werden keine Dialoge angezeigt; Meldungen werden
# ausschliesslich protokolliert. Es gibt keinen Einfluss auf den Normalbetrieb.
$script:TestMode = $false

function Write-AppLog {
    param(
        [string]$Level = 'INFO',
        [Parameter(Mandatory)][string]$Message
    )
    try {
        $entry = [ordered]@{
            Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            Level     = $Level
            Message   = $Message
        }
        if ($script:App -and $script:App.Vault -and $script:App.Vault.Contains('Logs')) {
            [void]$script:App.Vault['Logs'].Add($entry)
            Invoke-LogRotationIfNeeded
        }
        else {
            [void]$script:StartupLogBuffer.Add($entry)
        }
    }
    catch { } # Logging darf die Anwendung nie zum Absturz bringen
}

# Begrenzung/Rotation der verschluesselten Logs innerhalb des Tresors
function Invoke-LogRotationIfNeeded {
    $vault = $script:App.Vault
    if ($null -eq $vault) { return }
    $logs = $vault['Logs']
    if ($logs.Count -le $script:Const.MaxLogEntries) { return }
    $moveCount = [math]::Min($script:Const.LogArchiveChunk, $logs.Count - $script:Const.MaxLogEntries + $script:Const.LogArchiveChunk)
    $archived = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $moveCount -and $logs.Count -gt 0; $i++) {
        [void]$archived.Add($logs[0])
        $logs.RemoveAt(0)
    }
    if (-not $vault.Contains('LogArchives') -or $null -eq $vault['LogArchives']) {
        $vault['LogArchives'] = New-Object System.Collections.ArrayList
    }
    [void]$vault['LogArchives'].Add([ordered]@{
            Id      = [guid]::NewGuid().ToString()
            Entries = $archived
        })
    # Gesamtobergrenze des Archivs einhalten (aelteste Bloecke zuerst entfernen)
    $totalArchived = 0
    foreach ($block in @($vault['LogArchives'])) { $totalArchived += @($block.Entries).Count }
    while ($totalArchived -gt $script:Const.MaxArchivedEntries -and $vault['LogArchives'].Count -gt 0) {
        $totalArchived -= @($vault['LogArchives'][0].Entries).Count
        $vault['LogArchives'].RemoveAt(0)
    }
}

# Uebernimmt vor dem Entsperren gepufferte Logeintraege in den Tresor
function Move-StartupLogToVault {
    if ($null -eq $script:App -or $null -eq $script:App.Vault) { return }
    foreach ($entry in @($script:StartupLogBuffer)) {
        [void]$script:App.Vault['Logs'].Add($entry)
    }
    $script:StartupLogBuffer.Clear()
    Invoke-LogRotationIfNeeded
}

# Loescht die verschluesselten Protokolle (aktuelles Protokoll + Archive)
# TRANSAKTIONAL: Vor dem Loeschen wird ein vollstaendiger Snapshot beider
# Listen AUSSCHLIESSLICH im Arbeitsspeicher angelegt (keine Klartextkopie).
# Nach dem Leeren wird genau EIN neutraler Audit-Eintrag erzeugt und der
# Speichererfolg von Save-Vault ausgewertet: Nur bei erfolgreichem,
# verifiziertem Speichern bleibt die Loeschung bestehen - sonst werden Logs
# und Archive vollstaendig wiederhergestellt (einschliesslich Ruecknahme des
# noch nicht gespeicherten Audit-Eintrags). Liefert booleschen Erfolg.
function Clear-VaultProtocols {
    if ($null -eq $script:App -or $null -eq $script:App.Vault) { return $false }
    $vault = $script:App.Vault
    $logsBackup = New-Object System.Collections.ArrayList
    foreach ($entry in @($vault['Logs'])) { [void]$logsBackup.Add($entry) }
    $archBackup = New-Object System.Collections.ArrayList
    foreach ($block in @($vault['LogArchives'])) { [void]$archBackup.Add($block) }
    $vault['Logs'].Clear()
    $vault['LogArchives'].Clear()
    Write-AppLog -Message 'Verschlüsselte Protokolle wurden durch den Benutzer gelöscht.'
    if (Save-Vault) { return $true }
    # Fehlgeschlagen: beide Listen vollstaendig aus dem Snapshot wiederherstellen
    $vault['Logs'].Clear()
    foreach ($entry in @($logsBackup)) { [void]$vault['Logs'].Add($entry) }
    $vault['LogArchives'].Clear()
    foreach ($block in @($archBackup)) { [void]$vault['LogArchives'].Add($block) }
    Write-AppLog -Level 'WARN' -Message 'Löschung der Protokolle NICHT gespeichert - die bisherigen Protokolle wurden vollständig wiederhergestellt.'
    return $false
}

function Show-AppError {
    param(
        [Parameter(Mandatory)][string]$Message,
        $ErrorRecord
    )
    $detail = ''
    if ($ErrorRecord) {
        $detail = ' | Technisch: ' + $ErrorRecord.Exception.Message
        if ($ErrorRecord.ScriptStackTrace) {
            $detail += ' | ' + ($ErrorRecord.ScriptStackTrace -replace "`r?`n", ' <- ')
        }
    }
    Write-AppLog -Level 'ERROR' -Message ($Message + $detail)
    if ($script:TestMode) {
        # Im Testlauf sichtbar auf der Konsole statt als Dialog
        try { Write-Host ('(Testlauf-Fehler) ' + $Message + $detail) -ForegroundColor DarkYellow } catch { }
        return
    }
    try {
        [System.Windows.MessageBox]::Show($Message, 'ArbeitszeitTool - Fehler',
            [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
    }
    catch { }
}

#endregion


#region ===== Zeit-Helfer =====

function ConvertTo-DateTimeString {
    param([datetime]$Value)
    return $Value.ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertFrom-DateTimeString {
    param($Text)
    if ([string]::IsNullOrEmpty([string]$Text)) { return $null }
    return [datetime]::ParseExact([string]$Text, 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Test-TimeText {
    param([string]$Text)
    return ([string]$Text -match '^([01]?[0-9]|2[0-3]):[0-5][0-9]$')
}

# Kombiniert das Datum eines Arbeitstages ('yyyy-MM-dd') mit einer Uhrzeit 'HH:mm'
function Get-DayDateTime {
    param([string]$DayDate, [string]$TimeText)
    return [datetime]::ParseExact("$DayDate $TimeText", 'yyyy-MM-dd H:mm', [System.Globalization.CultureInfo]::InvariantCulture)
}

# Dauer als HH:mm - funktioniert auch oberhalb von 24 Stunden und bei negativen Werten
function Format-Duration {
    param([TimeSpan]$Value, [switch]$WithSign)
    $negative = $Value.Ticks -lt 0
    if ($negative) { $Value = $Value.Negate() }
    $hours = [math]::Floor($Value.TotalHours)
    $text = '{0:00}:{1:00}' -f $hours, $Value.Minutes
    if ($negative) { return "-$text" }
    if ($WithSign) { return "+$text" }
    return $text
}

function Format-Clock {
    param($Value)
    if ($null -eq $Value) { return '--:--' }
    return ([datetime]$Value).ToString('HH:mm')
}

# ISO-8601-Kalenderwoche (Montag = erster Wochentag, KW 1 = Woche mit erstem Donnerstag).
# .NET Framework besitzt keine ISOWeek-Klasse, daher der uebliche Donnerstag-Trick.
function Get-IsoWeek {
    param([datetime]$Date)
    $cal = [System.Globalization.CultureInfo]::InvariantCulture.Calendar
    $dow = [int]$cal.GetDayOfWeek($Date)
    if ($dow -ge 1 -and $dow -le 3) { $Date = $Date.AddDays(3) }
    return $cal.GetWeekOfYear($Date, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [System.DayOfWeek]::Monday)
}

#endregion

#region ===== Verschluesselter Datentresor (Container, Schluessel, atomares Speichern) =====

# Neutrale Fehlermeldung: falsches Passwort, manipulierter Header/Ciphertext/HMAC,
# ungueltiges Padding und beschaedigtes JSON sind nach aussen NICHT unterscheidbar.
$script:VaultNeutralError = 'Das Passwort ist falsch oder der Datentresor ist beschädigt.'

# Sitzungsschluessel (nur im Arbeitsspeicher; werden beim Beenden ueberschrieben)
$script:VaultSession = @{
    AesKey     = $null
    HmacKey    = $null
    Salt       = $null
    Iterations = $script:VaultConst.Iterations
    Unlocked   = $false
}

function Assert-VaultCryptoReady {
    if (-not $script:VaultCryptoReady) {
        throw ("Die benötigten .NET-Kryptografiefunktionen (PBKDF2 mit SHA256, .NET Framework 4.7.2 oder neuer) stehen auf diesem System nicht zur Verfügung. " +
            "Es werden keine Dateien verändert und keine schwächere Verschlüsselung verwendet. Technischer Hinweis: " + $script:VaultCryptoError)
    }
}

# SecureString -> UTF8-Bytes. Das Passwort wird nicht getrimmt oder veraendert;
# Unicode (auch Leer- und Sonderzeichen) bleibt vollstaendig erhalten.
# Zwischenpuffer werden anschliessend ueberschrieben.
function ConvertTo-PasswordBytes {
    param([Parameter(Mandatory)][securestring]$Secure)
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    $chars = $null
    try {
        $length = [System.Runtime.InteropServices.Marshal]::ReadInt32($bstr, -4) / 2
        $chars = New-Object char[] $length
        [System.Runtime.InteropServices.Marshal]::Copy($bstr, $chars, 0, $length)
        return ,[System.Text.Encoding]::UTF8.GetBytes($chars)
    }
    finally {
        if ($chars) { [System.Array]::Clear($chars, 0, $chars.Length) }
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

# Prueft die Passwortregeln (Laenge in Zeichen). Liefert '' oder eine Meldung.
function Test-PasswordPolicy {
    param([Parameter(Mandatory)][securestring]$Secure)
    $len = $Secure.Length
    if ($len -lt $script:VaultConst.MinPasswordLen) {
        return ('Das Passwort muss mindestens {0} Zeichen lang sein (empfohlen: mindestens 16 zufällige Zeichen).' -f $script:VaultConst.MinPasswordLen)
    }
    if ($len -gt $script:VaultConst.MaxPasswordLen) {
        return ('Das Passwort darf höchstens {0} Zeichen lang sein.' -f $script:VaultConst.MaxPasswordLen)
    }
    return ''
}

# PBKDF2-HMAC-SHA256: 64 Byte Schluesselmaterial -> 32 Byte AES + 32 Byte HMAC.
# Die uebergebenen Passwort-Bytes werden hier NICHT geloescht (Aufgabe des Aufrufers).
function Get-VaultKeysFromPassword {
    param(
        [Parameter(Mandatory)][byte[]]$PasswordBytes,
        [Parameter(Mandatory)][byte[]]$Salt,
        [Parameter(Mandatory)][int]$Iterations
    )
    Assert-VaultCryptoReady
    $material = [ArbeitszeitTool.VaultCrypto]::DeriveKeyMaterial($PasswordBytes, $Salt, $Iterations, $script:VaultConst.KeyMaterialBytes)
    try {
        $aes = New-Object byte[] $script:VaultConst.KeyBytes
        $hmac = New-Object byte[] $script:VaultConst.KeyBytes
        [System.Buffer]::BlockCopy($material, 0, $aes, 0, $script:VaultConst.KeyBytes)
        [System.Buffer]::BlockCopy($material, $script:VaultConst.KeyBytes, $hmac, 0, $script:VaultConst.KeyBytes)
        return @{ Aes = $aes; Hmac = $hmac }
    }
    finally {
        [ArbeitszeitTool.VaultCrypto]::ClearBytes($material)
    }
}

function Clear-VaultKeys {
    param($Keys)
    if ($null -eq $Keys) { return }
    [ArbeitszeitTool.VaultCrypto]::ClearBytes($Keys.Aes)
    [ArbeitszeitTool.VaultCrypto]::ClearBytes($Keys.Hmac)
}

function Set-VaultSessionKeys {
    param([Parameter(Mandatory)]$Keys, [Parameter(Mandatory)][byte[]]$Salt, [Parameter(Mandatory)][int]$Iterations)
    Clear-VaultSessionKeys
    $script:VaultSession.AesKey = $Keys.Aes
    $script:VaultSession.HmacKey = $Keys.Hmac
    $script:VaultSession.Salt = $Salt
    $script:VaultSession.Iterations = $Iterations
    $script:VaultSession.Unlocked = $true
}

function Clear-VaultSessionKeys {
    [ArbeitszeitTool.VaultCrypto]::ClearBytes($script:VaultSession.AesKey)
    [ArbeitszeitTool.VaultCrypto]::ClearBytes($script:VaultSession.HmacKey)
    $script:VaultSession.AesKey = $null
    $script:VaultSession.HmacKey = $null
    $script:VaultSession.Salt = $null
    $script:VaultSession.Unlocked = $false
}

# Verschluesselt einen Klartext (UTF-8) in das Containerformat (JSON).
# Pro Aufruf wird ein NEUER kryptografisch zufaelliger IV erzeugt.
function Protect-VaultContainer {
    param(
        [Parameter(Mandatory)][string]$PlainText,
        [Parameter(Mandatory)][byte[]]$AesKey,
        [Parameter(Mandatory)][byte[]]$HmacKey,
        [Parameter(Mandatory)][byte[]]$Salt,
        [Parameter(Mandatory)][int]$Iterations
    )
    Assert-VaultCryptoReady
    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    try {
        $iv = [ArbeitszeitTool.VaultCrypto]::GetRandomBytes($script:VaultConst.IvBytes)
        $cipher = [ArbeitszeitTool.VaultCrypto]::AesEncrypt($plainBytes, $AesKey, $iv)
        $auth = [ArbeitszeitTool.VaultCrypto]::BuildAuthData($script:VaultConst.Magic, $script:VaultConst.ContainerVersion,
            $script:VaultConst.Kdf, $Iterations, $Salt, $iv, $cipher)
        $mac = [ArbeitszeitTool.VaultCrypto]::ComputeHmacSha256($HmacKey, $auth)
        $container = [ordered]@{
            Magic      = $script:VaultConst.Magic
            Version    = $script:VaultConst.ContainerVersion
            Kdf        = $script:VaultConst.Kdf
            Iterations = $Iterations
            Salt       = [Convert]::ToBase64String($Salt)
            IV         = [Convert]::ToBase64String($iv)
            Ciphertext = [Convert]::ToBase64String($cipher)
            Hmac       = [Convert]::ToBase64String($mac)
        }
        return ($container | ConvertTo-Json)
    }
    finally {
        [ArbeitszeitTool.VaultCrypto]::ClearBytes($plainBytes)
    }
}

# Liest und validiert einen Container von der Platte (nur Header/Metadaten,
# noch keine Entschluesselung). Wirft 'VAULT_INVALID' bzw. 'VAULT_NEWER'.
function Read-VaultContainerFromFile {
    param([Parameter(Mandatory)][string]$Path)
    # Plausibilitaet VOR dem Einlesen: uebergrosse Dateien werden abgelehnt,
    # ohne dass ihr Inhalt in den Speicher geladen wird.
    $fileInfo = New-Object System.IO.FileInfo $Path
    if (-not $fileInfo.Exists) { throw (New-Object System.IO.FileNotFoundException $Path) }
    if ($fileInfo.Length -gt $script:VaultConst.MaxFileBytes) {
        throw (New-Object System.InvalidOperationException 'VAULT_INVALID')
    }
    $raw = [System.IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($raw)) { throw (New-Object System.InvalidOperationException 'VAULT_INVALID') }
    $obj = $null
    try { $obj = ConvertTo-PlainObject ($raw | ConvertFrom-Json) }
    catch { throw (New-Object System.InvalidOperationException 'VAULT_INVALID') }
    if ($obj -isnot [System.Collections.IDictionary]) { throw (New-Object System.InvalidOperationException 'VAULT_INVALID') }
    foreach ($field in @('Magic', 'Version', 'Kdf', 'Iterations', 'Salt', 'IV', 'Ciphertext', 'Hmac')) {
        if (-not $obj.Contains($field) -or $null -eq $obj[$field]) { throw (New-Object System.InvalidOperationException 'VAULT_INVALID') }
    }
    if ([string]$obj['Magic'] -ne $script:VaultConst.Magic) { throw (New-Object System.InvalidOperationException 'VAULT_INVALID') }
    $version = 0
    if (-not [int]::TryParse([string]$obj['Version'], [ref]$version)) { throw (New-Object System.InvalidOperationException 'VAULT_INVALID') }
    if ($version -gt $script:VaultConst.ContainerVersion) { throw (New-Object System.InvalidOperationException 'VAULT_NEWER') }
    if ($version -lt 1) { throw (New-Object System.InvalidOperationException 'VAULT_INVALID') }
    if ([string]$obj['Kdf'] -ne $script:VaultConst.Kdf) { throw (New-Object System.InvalidOperationException 'VAULT_INVALID') }
    $iterations = 0
    if (-not [int]::TryParse([string]$obj['Iterations'], [ref]$iterations)) { throw (New-Object System.InvalidOperationException 'VAULT_INVALID') }
    if ($iterations -lt $script:VaultConst.MinIterations -or $iterations -gt $script:VaultConst.MaxIterations) {
        throw (New-Object System.InvalidOperationException 'VAULT_INVALID')
    }
    # Uebermaessig grosse Base64-Felder vor der Dekodierung ablehnen
    foreach ($b64Field in @('Salt', 'IV', 'Ciphertext', 'Hmac')) {
        if (([string]$obj[$b64Field]).Length -gt $script:VaultConst.MaxFieldChars) {
            throw (New-Object System.InvalidOperationException 'VAULT_INVALID')
        }
    }
    $salt = $null; $iv = $null; $cipher = $null; $hmac = $null
    try {
        $salt = [Convert]::FromBase64String([string]$obj['Salt'])
        $iv = [Convert]::FromBase64String([string]$obj['IV'])
        $cipher = [Convert]::FromBase64String([string]$obj['Ciphertext'])
        $hmac = [Convert]::FromBase64String([string]$obj['Hmac'])
    }
    catch { throw (New-Object System.InvalidOperationException 'VAULT_INVALID') }
    # Container-Version 1 schreibt immer exakt 32 Byte Salt
    if ($version -eq 1 -and $salt.Length -ne $script:VaultConst.SaltBytes) {
        throw (New-Object System.InvalidOperationException 'VAULT_INVALID')
    }
    if ($salt.Length -lt 16 -or $iv.Length -ne $script:VaultConst.IvBytes -or $hmac.Length -ne $script:VaultConst.HmacBytes) {
        throw (New-Object System.InvalidOperationException 'VAULT_INVALID')
    }
    if ($cipher.Length -lt 16 -or ($cipher.Length % 16) -ne 0) { throw (New-Object System.InvalidOperationException 'VAULT_INVALID') }
    return @{
        Version    = $version
        Kdf        = [string]$obj['Kdf']
        Iterations = $iterations
        Salt       = $salt
        IV         = $iv
        Ciphertext = $cipher
        Hmac       = $hmac
    }
}

# Encrypt-then-MAC: Der HMAC wird IMMER vor dem Entschluesselungsversuch
# zeitkonstant geprueft. Liefert den Klartext (UTF-8) oder wirft 'VAULT_INVALID'.
function Unprotect-VaultContainer {
    param(
        [Parameter(Mandatory)]$Container,
        [Parameter(Mandatory)][byte[]]$AesKey,
        [Parameter(Mandatory)][byte[]]$HmacKey
    )
    Assert-VaultCryptoReady
    $auth = [ArbeitszeitTool.VaultCrypto]::BuildAuthData($script:VaultConst.Magic, [int]$Container.Version,
        [string]$Container.Kdf, [int]$Container.Iterations, $Container.Salt, $Container.IV, $Container.Ciphertext)
    $mac = [ArbeitszeitTool.VaultCrypto]::ComputeHmacSha256($HmacKey, $auth)
    $macOk = [ArbeitszeitTool.VaultCrypto]::FixedTimeEquals($mac, $Container.Hmac)
    [ArbeitszeitTool.VaultCrypto]::ClearBytes($mac)
    if (-not $macOk) { throw (New-Object System.InvalidOperationException 'VAULT_INVALID') }
    $plainBytes = $null
    try {
        $plainBytes = [ArbeitszeitTool.VaultCrypto]::AesDecrypt($Container.Ciphertext, $AesKey, $Container.IV)
        return [System.Text.Encoding]::UTF8.GetString($plainBytes)
    }
    catch [System.Security.Cryptography.CryptographicException] {
        throw (New-Object System.InvalidOperationException 'VAULT_INVALID')
    }
    finally {
        if ($plainBytes) { [ArbeitszeitTool.VaultCrypto]::ClearBytes($plainBytes) }
    }
}

# Leerer Tresorinhalt (existiert nur im Arbeitsspeicher)
function New-VaultDataObject {
    $now = ConvertTo-DateTimeString (Get-Date)
    return [ordered]@{
        SchemaVersion    = $script:Const.VaultSchemaVersion
        Revision         = [long]0
        SessionId        = [guid]::NewGuid().ToString()
        CleanShutdown    = $true
        LastCheckpointAt = $now
        ModifiedAt       = $now
        WorkData         = (New-EmptyWorkData)
        Settings         = (Get-DefaultSettings)
        Logs             = (New-Object System.Collections.ArrayList)
        LogArchives      = (New-Object System.Collections.ArrayList)
    }
}

# Vollstaendige Strukturvalidierung des entschluesselten Tresorinhalts.
# Liefert eine Liste von Fehlertexten (leer = gueltig). Unbekannte neuere
# Schema-Versionen werden abgelehnt und niemals stillschweigend geoeffnet.
function Test-VaultStructure {
    param([Parameter(Mandatory)]$Vault)
    $errors = New-Object System.Collections.ArrayList
    if ($Vault -isnot [System.Collections.IDictionary]) {
        [void]$errors.Add('Tresorinhalt ist keine gültige Struktur.')
        return ,$errors
    }
    foreach ($field in @('SchemaVersion', 'Revision', 'SessionId', 'CleanShutdown', 'WorkData', 'Settings', 'Logs')) {
        if (-not $Vault.Contains($field) -or $null -eq $Vault[$field]) {
            [void]$errors.Add("Pflichtfeld '$field' fehlt.")
        }
    }
    if ($errors.Count -gt 0) { return ,$errors }
    $schema = 0
    if (-not [int]::TryParse([string]$Vault['SchemaVersion'], [ref]$schema)) {
        [void]$errors.Add('Schema-Version ist keine Zahl.')
        return ,$errors
    }
    if ($schema -ne $script:Const.VaultSchemaVersion) {
        [void]$errors.Add("Schema-Version $schema wird nicht unterstützt (erwartet: $($script:Const.VaultSchemaVersion)).")
        return ,$errors
    }
    $revision = [long]0
    if (-not [long]::TryParse([string]$Vault['Revision'], [ref]$revision) -or $revision -lt 0) {
        [void]$errors.Add('Revisionsnummer ist ungültig.')
    }
    $work = $Vault['WorkData']
    if ($work -isnot [System.Collections.IDictionary] -or -not $work.Contains('Days') -or $work['Days'] -isnot [System.Collections.IList]) {
        [void]$errors.Add("Arbeitszeitdaten (WorkData/Days) sind ungültig.")
        return ,$errors
    }
    # Einstellungen: Regelarbeitszeit > 00:00 und <= 10:00
    $settings = $Vault['Settings']
    if ($settings -is [System.Collections.IDictionary] -and $settings.Contains('RegularTime')) {
        $regText = [string]$settings['RegularTime']
        if (-not (Test-TimeText $regText)) {
            [void]$errors.Add("Regelarbeitszeit '$regText' ist keine gültige Zeitangabe.")
        }
        else {
            $p = $regText.Split(':')
            $regMin = ([int]$p[0]) * 60 + [int]$p[1]
            if ($regMin -le 0 -or $regMin -gt $script:Const.MaxMinutes) {
                [void]$errors.Add("Regelarbeitszeit '$regText' liegt außerhalb des zulässigen Bereichs (größer 00:00, maximal 10:00).")
            }
        }
    }
    $activeCount = 0
    foreach ($day in @($work['Days'])) {
        if ($day -isnot [System.Collections.IDictionary]) { [void]$errors.Add('Ungültiges Tagesobjekt gefunden.'); continue }
        $dayLabel = '?'
        if ($day.Contains('Date')) { $dayLabel = [string]$day['Date'] }
        if ($dayLabel -notmatch '^\d{4}-\d{2}-\d{2}$') { [void]$errors.Add("Tag '$dayLabel': ungültiges Datum."); continue }
        # Format allein genuegt nicht (z. B. 2026-99-99): ein ungueltiger
        # Kalendertag liesse Export und Tages-Editor an ParseExact scheitern
        $calendarDate = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($dayLabel, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::None, [ref]$calendarDate)) {
            [void]$errors.Add("Tag '$dayLabel': ungültiges Kalenderdatum."); continue
        }
        if (@('Aktiv', 'Beendet') -notcontains [string]$day['Status']) { [void]$errors.Add("Tag '$dayLabel': ungültiger Status.") }
        if ([string]$day['Status'] -eq 'Aktiv') { $activeCount++ }
        $regMinutes = 0
        if (-not [int]::TryParse([string]$day['RegularMinutes'], [ref]$regMinutes) -or $regMinutes -le 0 -or $regMinutes -gt $script:Const.MaxMinutes) {
            [void]$errors.Add("Tag '$dayLabel': Regelarbeitszeit außerhalb des zulässigen Bereichs.")
        }
        $maxMinutes = 0
        if (-not [int]::TryParse([string]$day['MaxMinutes'], [ref]$maxMinutes) -or $maxMinutes -ne $script:Const.MaxMinutes) {
            [void]$errors.Add("Tag '$dayLabel': maximale Arbeitszeit muss exakt 10:00 Stunden betragen.")
        }
        # Segmente
        $runningCount = 0
        $parsed = New-Object System.Collections.ArrayList
        foreach ($seg in @($day['Segments'])) {
            if ($null -eq $seg) { continue }
            if (@('Betrieb', 'Homeoffice') -notcontains [string]$seg['Mode']) {
                [void]$errors.Add("Tag '$dayLabel': ungültiger Modus '$($seg['Mode'])'.")
                continue
            }
            $s = $null
            try { $s = ConvertFrom-DateTimeString $seg['Start'] } catch { }
            if ($null -eq $s) { [void]$errors.Add("Tag '$dayLabel': Abschnitt mit ungültigem Beginn."); continue }
            $e = $null
            if ($seg['End']) {
                try { $e = ConvertFrom-DateTimeString $seg['End'] } catch { }
                if ($null -eq $e) { [void]$errors.Add("Tag '$dayLabel': Abschnitt mit ungültigem Ende."); continue }
                if ($e -lt $s) { [void]$errors.Add("Tag '$dayLabel': Abschnittsende liegt vor dem Beginn."); continue }
            }
            if ([bool]$seg['Running']) {
                $runningCount++
                if ($seg['End']) { [void]$errors.Add("Tag '$dayLabel': laufender Abschnitt darf kein Ende besitzen.") }
                if ([string]$day['Status'] -ne 'Aktiv') { [void]$errors.Add("Tag '$dayLabel': laufender Abschnitt in beendetem Tag.") }
            }
            elseif (-not $seg['End']) {
                [void]$errors.Add("Tag '$dayLabel': abgeschlossener Abschnitt ohne Ende.")
            }
            $effEnd = $e
            if ($null -eq $effEnd) { $effEnd = [datetime]::MaxValue }
            [void]$parsed.Add(@{ Start = $s; End = $effEnd })
        }
        if ($runningCount -gt 1) { [void]$errors.Add("Tag '$dayLabel': mehr als ein laufender Abschnitt.") }
        # Ueberlappungspruefung der Abschnitte
        $sorted = @($parsed | Sort-Object -Property @{ Expression = { $_.Start } })
        for ($i = 1; $i -lt $sorted.Count; $i++) {
            if ($sorted[$i].Start -lt $sorted[$i - 1].End) {
                [void]$errors.Add("Tag '$dayLabel': Arbeitsabschnitte überlappen sich.")
                break
            }
        }
        # Pausen / Sperrintervalle: hoechstens je ein offenes Intervall
        foreach ($pair in @(@{ Name = 'ManualPauses'; Label = 'manuelle Pause' }, @{ Name = 'LockIntervals'; Label = 'Sperrintervall' })) {
            $openCount = 0
            foreach ($iv in @($day[$pair.Name])) {
                if ($null -eq $iv) { continue }
                $s = $null
                try { $s = ConvertFrom-DateTimeString $iv['Start'] } catch { }
                if ($null -eq $s) { [void]$errors.Add("Tag '$dayLabel': $($pair.Label) mit ungültigem Beginn."); continue }
                if ($iv['End']) {
                    $e = $null
                    try { $e = ConvertFrom-DateTimeString $iv['End'] } catch { }
                    if ($null -eq $e) { [void]$errors.Add("Tag '$dayLabel': $($pair.Label) mit ungültigem Ende.") }
                    elseif ($e -lt $s) { [void]$errors.Add("Tag '$dayLabel': $($pair.Label) endet vor dem Beginn.") }
                }
                else { $openCount++ }
            }
            if ($openCount -gt 1) { [void]$errors.Add("Tag '$dayLabel': mehr als ein offenes Intervall ($($pair.Label)).") }
        }
        # Abgeschlossene Tage: Nettozeit darf 10:00 nicht ueberschreiten
        if ([string]$day['Status'] -eq 'Beendet' -and $day['EndedAt']) {
            $endedAt = $null
            try { $endedAt = ConvertFrom-DateTimeString $day['EndedAt'] } catch { }
            if ($null -eq $endedAt) {
                [void]$errors.Add("Tag '$dayLabel': ungültiger Abschlusszeitpunkt.")
            }
            else {
                try {
                    $comp = Get-DayComputation -Day $day -Now $endedAt
                    if ($comp.Netto.TotalMinutes -gt ($script:Const.MaxMinutes + 0.02)) {
                        [void]$errors.Add("Tag '$dayLabel': Netto-Arbeitszeit überschreitet 10:00 Stunden.")
                    }
                }
                catch { [void]$errors.Add("Tag '$dayLabel': Tagesberechnung fehlgeschlagen.") }
            }
        }
    }
    if ($activeCount -gt 1) { [void]$errors.Add('Mehr als ein aktiver Arbeitstag vorhanden.') }
    return ,$errors
}

# Serialisiert und verschluesselt den Tresor und schreibt ihn in eine Datei.
# Es entsteht zu keinem Zeitpunkt eine Klartextdatei.
function Write-VaultToFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Vault,
        [Parameter(Mandatory)][byte[]]$AesKey,
        [Parameter(Mandatory)][byte[]]$HmacKey,
        [Parameter(Mandatory)][byte[]]$Salt,
        [Parameter(Mandatory)][int]$Iterations
    )
    $json = $Vault | ConvertTo-Json -Depth 30
    $containerJson = Protect-VaultContainer -PlainText $json -AesKey $AesKey -HmacKey $HmacKey -Salt $Salt -Iterations $Iterations
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Path, $containerJson, $utf8Bom)
}

# Liest eine Tresordatei, prueft HMAC, entschluesselt und validiert die Struktur.
# Liefert die nutzbare Datenstruktur oder wirft 'VAULT_INVALID' / 'VAULT_NEWER' /
# 'VAULT_SCHEMA:<Fehler>' bei struktureller Unbrauchbarkeit.
function Read-VaultFromFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][byte[]]$AesKey,
        [Parameter(Mandatory)][byte[]]$HmacKey
    )
    $container = Read-VaultContainerFromFile -Path $Path
    $plainJson = Unprotect-VaultContainer -Container $container -AesKey $AesKey -HmacKey $HmacKey
    $vault = $null
    try { $vault = ConvertTo-PlainObject ($plainJson | ConvertFrom-Json) }
    catch { throw (New-Object System.InvalidOperationException 'VAULT_INVALID') }
    $structErrors = Test-VaultStructure -Vault $vault
    if (@($structErrors).Count -gt 0) {
        throw (New-Object System.InvalidOperationException ('VAULT_SCHEMA:' + (@($structErrors) -join ' | ')))
    }
    return $vault
}

# SHA-256-Hash einer Datei (hex) - dient der Erkennung externer Aenderungen
# (z. B. durch Cloud-Synchronisierung) an der verschluesselten Hauptdatei.
function Get-FileSha256Hex {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        try { return ([System.BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '') }
        finally { $stream.Dispose() }
    }
    finally { $sha.Dispose() }
}

# Schnelle AUTHENTIZITAETSpruefung einer Tresordatei mit den Sitzungsschluesseln:
# Containerformat + identisches Salt + gueltiger HMAC (ohne Entschluesselung).
# ACHTUNG: Diese Pruefung sagt nichts ueber die strukturelle Verwendbarkeit
# des Inhalts aus. Fuer die Backuprotation und jede Entscheidung, ob eine
# Datei eine andere ersetzen darf, ist IMMER die vollstaendige Pruefung
# (Test-VaultFileFullyUsable) erforderlich.
function Test-VaultFileAuthentication {
    param([Parameter(Mandatory)][string]$Path)
    if (-not $script:VaultSession.Unlocked) { return $false }
    try {
        $container = Read-VaultContainerFromFile -Path $Path
        if (-not [ArbeitszeitTool.VaultCrypto]::FixedTimeEquals($container.Salt, $script:VaultSession.Salt)) { return $false }
        if ([int]$container.Iterations -ne [int]$script:VaultSession.Iterations) { return $false }
        $auth = [ArbeitszeitTool.VaultCrypto]::BuildAuthData($script:VaultConst.Magic, [int]$container.Version,
            [string]$container.Kdf, [int]$container.Iterations, $container.Salt, $container.IV, $container.Ciphertext)
        $mac = [ArbeitszeitTool.VaultCrypto]::ComputeHmacSha256($script:VaultSession.HmacKey, $auth)
        $ok = [ArbeitszeitTool.VaultCrypto]::FixedTimeEquals($mac, $container.Hmac)
        [ArbeitszeitTool.VaultCrypto]::ClearBytes($mac)
        return $ok
    }
    catch { return $false }
}

# VOLLSTAENDIGE Verwendbarkeitspruefung einer Tresordatei mit den
# Sitzungsschluesseln. Zusaetzlich zur Authentizitaet (Salt, Iterationen,
# HMAC) werden ueber Read-VaultFromFile geprueft: Entschluesselung,
# UTF-8-Dekodierung, JSON-Parsing, Tresor-Schema, vollstaendige
# Strukturvalidierung, interne Revision und Arbeitszeitstruktur.
# Die Pruefung ist nebenwirkungsfrei: sie veraendert weder den aktiven
# Tresor noch Einstellungen, Session-Werte, Dateien oder die Revision.
# Nur Dateien, die DIESE Pruefung bestehen, gelangen in die Backupkette -
# eine lediglich HMAC-gueltige, aber strukturell ungueltige Datei darf
# niemals ein anderes gueltiges Backup ueberschreiben.
function Test-VaultFileFullyUsable {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-VaultFileAuthentication -Path $Path)) { return $false }
    try {
        $vault = Read-VaultFromFile -Path $Path -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        # Interne Revision muss lesbar und plausibel sein
        $revision = [long]0
        if (-not [long]::TryParse([string]$vault['Revision'], [ref]$revision) -or $revision -lt 0) { return $false }
        return $true
    }
    catch { return $false }
}

# Verschiebt eine nicht verwendbare (aber weiterhin verschluesselte) Datei
# neutral in den Recovery-Ordner. Der Dateiname enthaelt keine Zeit- oder
# Arbeitszeitangaben (nur GUID).
function Move-FileToRecovery {
    param([Parameter(Mandatory)][string]$Path, [string]$Prefix = 'vault')
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    if (-not (Test-Path -LiteralPath $script:Paths.Recovery)) {
        New-Item -ItemType Directory -Path $script:Paths.Recovery -Force | Out-Null
    }
    $target = Join-Path $script:Paths.Recovery ('{0}-{1}.azt' -f $Prefix, ([guid]::NewGuid().ToString()))
    Move-Item -LiteralPath $Path -Destination $target -Force
    return $target
}

# Verschluesselt beliebigen Text mit den Sitzungsschluesseln in den
# Recovery-Ordner (GUID-Name). Wird fuer Archivkopien von Import-/Altdaten
# verwendet - es entsteht keine Klartextkopie.
function Protect-TextToRecovery {
    param([Parameter(Mandatory)][string]$PlainText, [string]$Prefix = 'archive')
    if (-not $script:VaultSession.Unlocked) { return $null }
    if (-not (Test-Path -LiteralPath $script:Paths.Recovery)) {
        New-Item -ItemType Directory -Path $script:Paths.Recovery -Force | Out-Null
    }
    $target = Join-Path $script:Paths.Recovery ('{0}-{1}.azt' -f $Prefix, ([guid]::NewGuid().ToString()))
    $containerJson = Protect-VaultContainer -PlainText $PlainText -AesKey $script:VaultSession.AesKey `
        -HmacKey $script:VaultSession.HmacKey -Salt $script:VaultSession.Salt -Iterations $script:VaultSession.Iterations
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($target, $containerJson, $utf8Bom)
    return $target
}

# Serialisiert und verschluesselt den Tresor zu den exakten Dateibytes
# (UTF-8 mit BOM, identisch zu Write-VaultToFile).
function ConvertTo-VaultFileBytes {
    param(
        [Parameter(Mandatory)]$Vault,
        [Parameter(Mandatory)][byte[]]$AesKey,
        [Parameter(Mandatory)][byte[]]$HmacKey,
        [Parameter(Mandatory)][byte[]]$Salt,
        [Parameter(Mandatory)][int]$Iterations
    )
    $json = $Vault | ConvertTo-Json -Depth 30
    $containerJson = Protect-VaultContainer -PlainText $json -AesKey $AesKey -HmacKey $HmacKey -Salt $Salt -Iterations $Iterations
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    $preamble = $utf8Bom.GetPreamble()
    $body = $utf8Bom.GetBytes($containerJson)
    $bytes = New-Object byte[] ($preamble.Length + $body.Length)
    [System.Array]::Copy($preamble, 0, $bytes, 0, $preamble.Length)
    [System.Array]::Copy($body, 0, $bytes, $preamble.Length, $body.Length)
    return ,$bytes
}

# Schreibt Bytes IN-PLACE in eine Datei: eine vorhandene Datei wird geoeffnet,
# ueberschrieben und auf die neue Laenge gekuerzt - sie wird weder geloescht
# noch umbenannt oder ersetzt. Cloud-Ordner (OneDrive/SharePoint) sehen
# dadurch nur eine neue Version derselben Datei und keine Loeschung (kein
# Papierkorbeintrag). Fehlt die Datei, wird sie angelegt. Kurze Wiederholung
# bei voruebergehender Sperre (z. B. waehrend eines Sync-Uploads).
function Write-FileInPlace {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][byte[]]$Bytes)
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
            try {
                $stream.Write($Bytes, 0, $Bytes.Length)
                $stream.SetLength($Bytes.Length)
                $stream.Flush($true)
            }
            finally { $stream.Dispose() }
            return
        }
        catch [System.IO.IOException] {
            if ($attempt -ge 3 -or $_.Exception -is [System.IO.DirectoryNotFoundException] -or
                $_.Exception -is [System.IO.FileNotFoundException]) { throw }
            Start-Sleep -Milliseconds 150
        }
    }
}

# Bedingtes In-place-Schreiben (Hauptdatei): Vergleich und
# Schreiben laufen unter EINEM Handle, das fremde Schreibzugriffe ausschliesst
# (FileShare.Read - wie Write-FileInPlace; Leser wie Sync-Clients bleiben
# moeglich). Zwischen Pruefung und Schreiben kann so weder eine zweite
# Instanz noch ein Sync-Client die Datei veraendern.
#  $ExpectedHash: erwarteter SHA-256 des aktuellen Inhalts; leer = die Datei
#  darf noch nicht existieren. Weicht der Inhalt ab, fehlt die Datei oder
#  existiert sie unerwartet, wird NICHTS geschrieben und
#  'VAULT_EXTERNAL_CHANGE' geworfen.
# Nach dem Schreiben wird ueber dasselbe Handle zurueckgelesen und per Hash
# verglichen - die Datei enthaelt danach nachweislich exakt $Bytes.
# (Nicht zu verwechseln mit Write-FileInPlaceIfUnchanged der Passwortaenderung:
# dort Rueckgabe true/false, ohne Anlegen und ohne Ruecklesen.)
function Write-FileInPlaceVerified {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][byte[]]$Bytes, [string]$ExpectedHash = '')
    $mode = [System.IO.FileMode]::Open
    if ($ExpectedHash -eq '') { $mode = [System.IO.FileMode]::CreateNew }
    $readAll = {
        param($Stream)
        $ms = New-Object System.IO.MemoryStream
        try { $Stream.CopyTo($ms); return ,$ms.ToArray() }
        finally { $ms.Dispose() }
    }
    $attempt = 0
    while ($true) {
        $attempt++
        $stream = $null
        try {
            $stream = New-Object System.IO.FileStream($Path, $mode, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read)
        }
        catch [System.IO.FileNotFoundException] {
            throw (New-Object System.InvalidOperationException 'VAULT_EXTERNAL_CHANGE')
        }
        catch [System.IO.IOException] {
            # CreateNew scheitert, weil die Datei inzwischen extern angelegt wurde
            if ($ExpectedHash -eq '' -and (Test-Path -LiteralPath $Path)) {
                throw (New-Object System.InvalidOperationException 'VAULT_EXTERNAL_CHANGE')
            }
            if ($attempt -ge 3 -or $_.Exception -is [System.IO.DirectoryNotFoundException]) { throw }
            Start-Sleep -Milliseconds 150
            continue
        }
        try {
            if ($ExpectedHash -ne '') {
                if ($stream.Length -gt $script:VaultConst.MaxFileBytes) {
                    throw (New-Object System.InvalidOperationException 'VAULT_EXTERNAL_CHANGE')
                }
                $current = & $readAll $stream
                if ((Get-BytesSha256Hex -Bytes $current) -ne $ExpectedHash) {
                    throw (New-Object System.InvalidOperationException 'VAULT_EXTERNAL_CHANGE')
                }
                $stream.Position = 0
            }
            $stream.Write($Bytes, 0, $Bytes.Length)
            $stream.SetLength($Bytes.Length)
            $stream.Flush($true)
            $stream.Position = 0
            $written = & $readAll $stream
            if ((Get-BytesSha256Hex -Bytes $written) -ne (Get-BytesSha256Hex -Bytes $Bytes)) {
                throw (New-Object System.IO.IOException 'Zurueckgelesener Inhalt weicht vom geschriebenen ab.')
            }
        }
        finally { $stream.Dispose() }
        return
    }
}

function Get-BytesSha256Hex {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes)) -replace '-', '') }
    finally { $sha.Dispose() }
}

# Speichervorgang des aktiven Tresors (Sitzungsschluessel). Im Tresorordner
# wird dabei NIEMALS eine Datei geloescht, umbenannt oder ersetzt - alle
# Tresordateien werden ausschliesslich in-place ueberschrieben (siehe
# Write-FileInPlace). Die Absturzsicherheit liefert ein Schreibjournal:
# vault.pending.azt bleibt dauerhaft liegen und spiegelt im Ruhezustand die
# Hauptdatei (gleiche Revision; beim Start gewinnt bei Gleichstand die
# Hauptdatei).
#   1. Validierung im Speicher              2. Metadaten-Snapshot anlegen
#   3. Revision erhoehen, Zeitstempel       4. Pruefen, ob vault.azt seit dem
#      letzten Laden extern veraendert wurde (Cloud-Synchronisierung) - dann
#      NICHT ueberschreiben, eigener Stand als neue Datei nach Recovery
#   5. Journal: neuen Stand in vault.pending.azt schreiben, erneut lesen,
#      HMAC pruefen, entschluesseln, validieren
#   6. Hauptdatei in-place mit demselben Stand ueberschreiben, erneut
#      oeffnen und pruefen. Bricht das Schreiben ab (Absturz), liegt der neue
#      Stand geprueft im Journal (hoehere Revision) und wird beim Start
#      angeboten; bei einem Schreibfehler wird der alte Stand sofort aus dem
#      Speicher zurueckgeschrieben.
#   7. ERST DANACH Backups rotieren (backup1 -> backup2, alter Hauptstand ->
#      backup1), ebenfalls in-place und nur mit nachweislich verwendbaren
#      Staenden; unbrauchbare Dateien wandern nach Recovery.
# Bei jedem Fehler vor dem Commit werden saemtliche zuvor veraenderten
# Metadaten (Revision, LastCheckpointAt, ModifiedAt, WorkData.LastSavedAt)
# aus dem Snapshot wiederhergestellt; die letzte gueltige Datei bleibt erhalten.
#  -NoTrackingCheckpoint: WorkData.LastSavedAt (fachlicher Tracking-
#   Checkpoint fuer die Homeoffice-Wiederherstellung) NICHT aktualisieren.
#  -Quiet: keine Fehlerdialoge (fuer automatische Wiederholungsversuche).
#  -NoBackupRotation: reine Zwischenspeicherung (30-Sekunden-Checkpoint,
#   Radiolautstaerke): backup1/backup2 bleiben unveraendert. Backups rotieren
#   nur bei fachlichen Wechseln (Modus, Pause, Sperre, Arbeitsende,
#   Korrekturen, Schliessen). Wurde der Stand aus Pending/Backup geladen,
#   wird trotzdem regulaer rotiert.
function Save-Vault {
    param(
        [switch]$NoTrackingCheckpoint,
        [switch]$Quiet,
        [switch]$NoBackupRotation
    )
    if ($null -eq $script:App -or $null -eq $script:App.Vault) { return $false }
    if (-not $script:VaultSession.Unlocked) { return $false }
    # Kontrollierte Blockade: Nach einem kritischen Schreibfehler der
    # Hauptdatei oder einem fehlenden Referenzhash der committeten Hauptdatei
    # wird NICHT ungeschuetzt weitergeschrieben (keine zuverlaessige externe
    # Aenderungserkennung moeglich). Aufhebung erst durch Neustart.
    if ($script:App.Flags.SaveBlockedReason) {
        if (-not $script:App.Flags.SaveBlockedLogged) {
            $script:App.Flags.SaveBlockedLogged = $true
            Write-AppLog -Level 'ERROR' -Message ('Speichervorgang blockiert: ' + [string]$script:App.Flags.SaveBlockedReason)
        }
        Set-VaultSaveFailedState
        return $false
    }
    # Keine ueberlappenden Speichervorgaenge (Re-Entranz ueber Dialog-Nachrichtenpumpe)
    if ($script:App.Flags.SaveInProgress) { return $false }
    $script:App.Flags.SaveInProgress = $true
    $vault = $script:App.Vault
    # 2. Metadaten-Snapshot fuer die vollstaendige Ruecknahme im Fehlerfall
    $metaSnapshot = @{
        Revision         = $vault['Revision']
        LastCheckpointAt = $vault['LastCheckpointAt']
        ModifiedAt       = $vault['ModifiedAt']
        CleanShutdown    = $vault['CleanShutdown']
        LastSavedAt      = $null
    }
    if ($vault['WorkData'] -is [System.Collections.IDictionary]) {
        $metaSnapshot.LastSavedAt = $vault['WorkData']['LastSavedAt']
    }
    $restoreMeta = {
        $vault['Revision'] = $metaSnapshot.Revision
        $vault['LastCheckpointAt'] = $metaSnapshot.LastCheckpointAt
        $vault['ModifiedAt'] = $metaSnapshot.ModifiedAt
        $vault['CleanShutdown'] = $metaSnapshot.CleanShutdown
        if ($vault['WorkData'] -is [System.Collections.IDictionary]) {
            $vault['WorkData']['LastSavedAt'] = $metaSnapshot.LastSavedAt
        }
    }
    # Commit-Punkt: Der Speichervorgang gilt als dauerhaft committed, sobald
    # die neue Hauptdatei geschrieben UND vollstaendig geprueft wurde. Ab dann
    # duerfen nachgelagerte Fehler (Backuprotation, Referenzdaten) weder false
    # liefern noch Metadaten zuruecksetzen noch einen fachlichen Rollback der
    # aufrufenden Aktion ausloesen.
    $commitCompleted = $false
    # Bytes des bisherigen Standes (Hauptdatei bzw. Journal) fuer die
    # Ruecknahme im Fehlerfall und fuer backup1
    $oldMainBytes = $null
    $oldPendingBytes = $null
    $oldPendingUnreadable = $null
    $journalTouched = $false
    try {
        # 1. Validierung im Speicher - ungueltige Daten werden niemals geschrieben
        $errors = Test-VaultStructure -Vault $vault
        if (@($errors).Count -gt 0) {
            Set-VaultSaveFailedState
            if (-not $Quiet) {
                Show-AppError -Message ("Die Daten wurden NICHT gespeichert, weil die interne Validierung fehlschlug:`r`n- " + (@($errors) -join "`r`n- "))
            }
            return $false
        }
        # 3. Revision erhoehen, Zeitstempel aktualisieren
        $vault['Revision'] = [long]$vault['Revision'] + 1
        $now = Get-Date
        $nowText = ConvertTo-DateTimeString $now
        $vault['LastCheckpointAt'] = $nowText
        $vault['ModifiedAt'] = $nowText
        if (-not $NoTrackingCheckpoint -and $vault['WorkData'] -is [System.Collections.IDictionary]) {
            $vault['WorkData']['LastSavedAt'] = $nowText
        }
        $newBytes = ConvertTo-VaultFileBytes -Vault $vault `
            -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey `
            -Salt $script:VaultSession.Salt -Iterations $script:VaultSession.Iterations
        # 4. Externe Veraenderungen der Hauptdatei erkennen (z. B. Cloud-
        #    Synchronisierung). Massstab ist der beim Entsperren bzw. beim
        #    letzten Schreiben erfasste SHA-256-Hash der Hauptdatei. Er wird
        #    beim Entsperren IMMER erfasst, wenn eine Hauptdatei existiert -
        #    auch wenn der Stand aus Pending/Backup1/Backup2 geladen wurde
        #    oder die Hauptdatei beschaedigt ist (der Hash beschreibt den
        #    Bytezustand, nicht die inhaltliche Verwendbarkeit). Erkannt werden:
        #      - inhaltliche Veraenderung (Hash weicht ab)
        #      - extern neu angelegte Hauptdatei (beim Laden war keine da)
        #      - extern entfernte oder ersetzte Hauptdatei (beim Laden war eine da)
        $mainExists = (Test-Path -LiteralPath $script:Paths.VaultFile)
        $externalChange = ''
        if ($mainExists) {
            $oldMainBytes = [System.IO.File]::ReadAllBytes($script:Paths.VaultFile)
            $currentHash = Get-BytesSha256Hex -Bytes $oldMainBytes
            if ($script:App.VaultFileHash) {
                if ($currentHash -ne $script:App.VaultFileHash) { $externalChange = 'inhaltlich verändert' }
            }
            elseif ($script:App.VaultFileExistedAtLoad) {
                # Datei existierte beim Laden, aber es liegt kein Referenzhash
                # vor (Erfassung fehlgeschlagen): kein verlaesslicher Vergleich
                # moeglich - im Zweifel NICHT ueberschreiben.
                $externalChange = 'nicht vergleichbar (Referenzhash fehlt)'
            }
            else {
                # Beim Laden existierte KEINE Hauptdatei, jetzt gibt es eine:
                # sie wurde extern angelegt und wird nicht ueberschrieben.
                $externalChange = 'extern neu angelegt'
            }
        }
        elseif ($script:App.VaultFileExistedAtLoad -or $script:App.VaultFileHash) {
            # Beim Laden existierte eine Hauptdatei, jetzt fehlt sie: extern
            # entfernt oder ersetzt - es wird nichts stillschweigend neu angelegt.
            $externalChange = 'extern entfernt'
        }
        # Konfliktbehandlung - auch fuer die spaete Erkennung unmittelbar vor
        # dem Schreiben der Hauptdatei (Schritt 6, siehe aeusserer catch):
        # Vorhandene Dateien nicht ueberschreiben; eigenen (verschluesselten)
        # Stand als NEUE Datei neutral in Recovery sichern (keine Loeschung,
        # kein Verschieben); keine automatische Zusammenfuehrung.
        # Erfolg wird nur gemeldet, wenn die Kopie nachweislich vollstaendig
        # geschrieben wurde (Bytes erneut gelesen und per Hash verglichen).
        $handleExternalChange = {
            param([string]$ExternalChange)
            $externalChange = $ExternalChange
            $conflictPath = $null
            $conflictSaved = $false
            try {
                if ($script:TestMode -and $script:App.Flags.TestFailConflictCopy) {
                    throw (New-Object System.IO.IOException 'TESTHOOK: Konfliktsicherung deaktiviert')
                }
                if (-not (Test-Path -LiteralPath $script:Paths.Recovery -PathType Container)) {
                    New-Item -ItemType Directory -Path $script:Paths.Recovery -Force -ErrorAction Stop | Out-Null
                }
                $conflictPath = Join-Path $script:Paths.Recovery ('vault-{0}.azt' -f ([guid]::NewGuid().ToString()))
                [System.IO.File]::WriteAllBytes($conflictPath, $newBytes)
                $conflictSaved = ((Get-FileSha256Hex -Path $conflictPath) -eq (Get-BytesSha256Hex -Bytes $newBytes))
            }
            catch { $conflictSaved = $false }
            & $restoreMeta
            Set-VaultSaveFailedState
            # Keine automatische Wiederholung: sie wuerde nur weitere
            # Konfliktkopien erzeugen - der Benutzer muss entscheiden.
            $script:App.Flags.SaveRetryCount = 3
            $script:App.Flags.LastConflictCopySaved = $conflictSaved
            $conflictIntro = ("Die Tresordatei wurde außerhalb dieser Anwendung verändert ({0}), z. B. durch eine Cloud-Synchronisierung. " -f $externalChange) +
                "Vorhandene Dateien wurden NICHT überschrieben. "
            if ($conflictSaved) {
                Write-AppLog -Level 'WARN' -Message ("Externe Änderung der Tresordatei erkannt ({0}) - Speichern abgebrochen, eigener Stand in Recovery gesichert." -f $externalChange)
                if (-not $Quiet) {
                    Show-Warning -Message ($conflictIntro + "Der aktuelle lokale Stand wurde verschlüsselt im Ordner 'Recovery' gesichert:`r`n`r`n" +
                        [string]$conflictPath + "`r`n`r`nEs findet keine automatische Zusammenführung statt. Bitte die Anwendung neu starten und den gewünschten Stand wählen.")
                }
            }
            else {
                Write-AppLog -Level 'ERROR' -Message ("Externe Änderung der Tresordatei erkannt ({0}) - Speichern abgebrochen. Sicherung des eigenen Standes in Recovery FEHLGESCHLAGEN - lokale Änderungen sind nicht gesichert." -f $externalChange)
                if (-not $Quiet) {
                    Show-AppError -Message ($conflictIntro + "ACHTUNG: Der aktuelle lokale Stand konnte NICHT im Ordner 'Recovery' gesichert werden. " +
                        "Ihre lokalen Änderungen sind derzeit nur im Arbeitsspeicher vorhanden.`r`n`r`n" +
                        "Bitte die Anwendung NICHT beenden oder neu starten, solange der Ordner 'Recovery' nicht beschreibbar ist (z. B. Speicherplatz, Berechtigungen, gesperrte Datei). " +
                        "Notieren Sie wichtige Änderungen gegebenenfalls manuell. Es findet keine automatische Zusammenführung statt.")
                }
            }
        }
        if ($externalChange -ne '') {
            & $handleExternalChange $externalChange
            return $false
        }
        # Hauptdatei ist unveraendert (oder existierte weder beim Laden noch jetzt).
        #  - Stand aus der Hauptdatei geladen: der alte Hauptstand wurde beim
        #    Entsperren bereits vollstaendig validiert -> rotationsfaehig.
        #  - Stand bewusst aus Pending/Backup geladen (Auswahl im
        #    Wiederherstellungsdialog): das Ersetzen der unveraenderten alten
        #    Hauptdatei ist ein EXPLIZIT erkannter Wiederherstellungsvorgang,
        #    kein gewoehnlicher Speichervorgang. Der alte Hauptstand gelangt
        #    nur nach vollstaendiger Pruefung in die Backupkette.
        $mainKnownGood = ($mainExists -and $script:App.LoadedFrom -eq 'Haupt')
        $skipRotation = ($NoBackupRotation -and $mainKnownGood)
        $oldMainUsable = $mainKnownGood
        if ($mainExists -and -not $mainKnownGood) {
            Write-AppLog -Level 'WARN' -Message ("Wiederherstellungsvorgang: Der aus '{0}' geladene Stand ersetzt die unveränderte bisherige Hauptdatei." -f $script:App.LoadedFrom)
            $oldMainUsable = Test-VaultFileFullyUsable -Path $script:Paths.VaultFile
        }
        # 5. Journal: neuen Stand in vault.pending.azt schreiben und pruefen.
        #    Der bisherige Journalinhalt wird fuer die Ruecknahme gemerkt.
        if (Test-Path -LiteralPath $script:Paths.VaultPending) {
            try { $oldPendingBytes = [System.IO.File]::ReadAllBytes($script:Paths.VaultPending) } catch { $oldPendingBytes = $null }
            # Nur einen mit dem aktuellen Schluessel lesbaren Journalstand fuer
            # die Ruecknahme merken - nie z. B. einen Stand mit altem Passwort
            # zurueckschreiben (Fallback: bisherige Hauptdatei). Im Ruhezustand
            # spiegelt das Journal die Hauptdatei; dann entfaellt die Pruefung.
            if ($null -ne $oldPendingBytes -and -not ($null -ne $oldMainBytes -and
                    (Get-BytesSha256Hex -Bytes $oldPendingBytes) -eq (Get-BytesSha256Hex -Bytes $oldMainBytes))) {
                try {
                    Read-VaultFromFile -Path $script:Paths.VaultPending `
                        -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey | Out-Null
                }
                catch { $oldPendingUnreadable = $oldPendingBytes; $oldPendingBytes = $null }
            }
        }
        $journalTouched = $true
        Write-FileInPlace -Path $script:Paths.VaultPending -Bytes $newBytes
        $verify = Read-VaultFromFile -Path $script:Paths.VaultPending `
            -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        if ([long]$verify['Revision'] -ne [long]$vault['Revision']) {
            throw (New-Object System.InvalidOperationException 'VAULT_INVALID')
        }
        # 6. Hauptdatei in-place ueberschreiben und vollstaendig pruefen.
        #    Vergleich mit dem in Schritt 4 geprueften Stand und Schreiben
        #    erfolgen unter EINEM Handle (Write-FileInPlaceVerified): eine
        #    zwischenzeitliche Fremdaenderung (zweite Instanz, Sync-Client)
        #    wird erkannt und NICHT ueberschrieben.
        $mainWriteOk = $false
        $mainWriteCompleted = $false
        $mainExternalChange = $false
        try {
            if ($script:TestMode -and $script:App.Flags.TestFailMainWrite) {
                # Simuliert einen Abbruch MITTEN im Schreiben (Datei beschaedigt)
                Write-FileInPlace -Path $script:Paths.VaultFile -Bytes ([System.Text.Encoding]::UTF8.GetBytes('TESTHOOK-HALB-GESCHRIEBEN'))
                throw (New-Object System.IO.IOException 'TESTHOOK: Schreiben der Hauptdatei deaktiviert')
            }
            if ($script:TestMode -and $null -ne $script:App.Flags.TestBeforeMainWrite) {
                # Simuliert eine Fremdaenderung zwischen Pruefung und Schreiben
                & $script:App.Flags.TestBeforeMainWrite
            }
            $expectedMainHash = ''
            if ($mainExists) { $expectedMainHash = $currentHash }
            Write-FileInPlaceVerified -Path $script:Paths.VaultFile -Bytes $newBytes -ExpectedHash $expectedMainHash
            $mainWriteCompleted = $true
            $verifyMain = Read-VaultFromFile -Path $script:Paths.VaultFile `
                -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
            if ([long]$verifyMain['Revision'] -ne [long]$vault['Revision']) {
                throw (New-Object System.InvalidOperationException 'VAULT_INVALID')
            }
            $mainWriteOk = $true
        }
        catch {
            $mainWriteOk = $false
            if ([string]$_.Exception.Message -eq 'VAULT_EXTERNAL_CHANGE') { $mainExternalChange = $true }
        }
        if (-not $mainWriteOk -and -not $mainExternalChange -and $mainWriteCompleted) {
            # Eigene Bytes wurden nachweislich geschrieben, die anschliessende
            # Pruefung scheiterte: Liegt inzwischen nicht mehr der eigene Stand
            # in der Datei, wurde sie extern veraendert - dann NICHT zurueck-
            # schreiben (sonst ginge die Fremdaenderung verloren).
            $hashNow = $null
            try { $hashNow = Get-FileSha256Hex -Path $script:Paths.VaultFile } catch { }
            if ($hashNow -ne (Get-BytesSha256Hex -Bytes $newBytes)) { $mainExternalChange = $true }
        }
        if ($mainExternalChange) {
            # Die Hauptdatei enthaelt einen fremden Stand und bleibt unangetastet;
            # Journal und Metadaten nimmt der aeussere catch zurueck, danach
            # folgt die regulaere Konfliktbehandlung (Sicherung nach Recovery).
            Write-AppLog -Level 'WARN' -Message 'Externe Änderung der Tresordatei unmittelbar vor bzw. während des Schreibens erkannt - Hauptdatei NICHT überschrieben.'
            throw (New-Object System.InvalidOperationException 'VAULT_EXTERNAL_CHANGE')
        }
        if (-not $mainWriteOk) {
            # Alten Hauptstand sofort aus dem Speicher zurueckschreiben und
            # pruefen; das Journal wird unten ebenfalls zurueckgenommen.
            $restoredOk = $false
            if ($null -ne $oldMainBytes) {
                try {
                    if ($script:TestMode -and $script:App.Flags.TestFailMainRestore) {
                        throw (New-Object System.IO.IOException 'TESTHOOK: Wiederherstellung der Hauptdatei deaktiviert')
                    }
                    Write-FileInPlace -Path $script:Paths.VaultFile -Bytes $oldMainBytes
                    if ((Get-FileSha256Hex -Path $script:Paths.VaultFile) -eq (Get-BytesSha256Hex -Bytes $oldMainBytes)) { $restoredOk = $true }
                }
                catch { $restoredOk = $false }
            }
            else {
                # Es gab noch keine Hauptdatei: eine evtl. halb geschriebene
                # neue Datei wird wieder entfernt (nur beim ersten Speichern).
                try {
                    if (Test-Path -LiteralPath $script:Paths.VaultFile) {
                        Remove-Item -LiteralPath $script:Paths.VaultFile -Force -ErrorAction SilentlyContinue
                    }
                }
                catch { }
            }
            if ($restoredOk -or $null -eq $oldMainBytes) {
                Write-AppLog -Level 'WARN' -Message 'Schreiben der Hauptdatei fehlgeschlagen - der bisherige Stand wurde sofort wiederhergestellt.'
                throw (New-Object System.InvalidOperationException 'VAULT_SWAP_FAILED')
            }
            # Kritischer Fall: auch die sofortige Wiederherstellung ist
            # fehlgeschlagen. Ab hier KEINE weiteren Schreibversuche; das
            # Journal (vault.pending.azt) haelt den neuen, geprueften Stand
            # mit hoeherer Revision und wird beim naechsten Start angeboten.
            $journalTouched = $false
            $script:App.Flags.SaveBlockedReason = 'Die Hauptdatei des Tresors konnte nach einem fehlgeschlagenen Schreibvorgang nicht wiederhergestellt werden. Es werden keine weiteren Schreibversuche unternommen.'
            $script:App.Flags.SaveRetryCount = 3
            Write-AppLog -Level 'ERROR' -Message 'KRITISCH: Schreiben UND sofortige Wiederherstellung der Hauptdatei fehlgeschlagen - weitere Speichervorgänge werden blockiert.'
            Show-AppError -Message ('Der Speichervorgang ist fehlgeschlagen und die bisherige Tresordatei konnte nicht automatisch wiederhergestellt werden. ' +
                'Es werden keine weiteren Schreibversuche unternommen; der neue Stand liegt geprüft in der Journaldatei (vault.pending.azt). ' +
                'Der Zustand wird als NICHT GESPEICHERT angezeigt. Bitte die Anwendung neu starten - beim nächsten Start wird der neueste gültige Stand zur Auswahl angeboten.')
            throw (New-Object System.InvalidOperationException 'VAULT_SWAP_CRITICAL')
        }
        # ----- COMMIT-PUNKT ERREICHT -----
        # Die neue Hauptdatei wurde geschrieben und vollstaendig geprueft
        # (Authentizitaet, Entschluesselung, JSON, Struktur, Revision).
        $commitCompleted = $true
        # Referenzdaten nach dem Commit (Best Effort - niemals Rollback):
        # Kann der Referenzhash der bereits gueltig gespeicherten Hauptdatei
        # nicht ermittelt werden, bleibt der Speichervorgang erfolgreich;
        # weitere Speichervorgaenge werden aber kontrolliert blockiert.
        # Der Hash wird aus den SELBST geschriebenen (unter dem Handle
        # zurueckgelesenen) Bytes gebildet - ein erneutes Lesen der Datei
        # koennte eine zwischenzeitliche Fremdaenderung als Referenz
        # uebernehmen und sie beim naechsten Speichern ueberschreiben.
        $newMainHash = $null
        try {
            if ($script:TestMode -and $script:App.Flags.TestFailPostCommitHash) {
                throw (New-Object System.IO.IOException 'TESTHOOK: Referenzhash deaktiviert')
            }
            $newMainHash = Get-BytesSha256Hex -Bytes $newBytes
        }
        catch { $newMainHash = $null }
        if ($null -eq $newMainHash) {
            $script:App.VaultFileHash = $null
            $script:App.Flags.SaveBlockedReason = 'Der Referenzhash der erfolgreich gespeicherten Tresordatei konnte nicht ermittelt werden. Ohne Referenzhash ist keine zuverlässige externe Änderungserkennung möglich; weitere Speichervorgänge sind bis zu einem Neustart blockiert.'
            Write-AppLog -Level 'WARN' -Message 'Referenzhash nach erfolgreichem Speichern nicht ermittelbar - weitere Speichervorgänge werden bis zum Neustart blockiert.'
            if (-not $Quiet) {
                Show-Warning -Message ('Die Arbeitszeitdaten wurden erfolgreich gespeichert. Der Prüfwert der Tresordatei konnte jedoch nicht ermittelt werden; ' +
                    'weitere Speichervorgänge sind deshalb bis zu einem Neustart der Anwendung blockiert.')
            }
        }
        else {
            $script:App.VaultFileHash = $newMainHash
        }
        $script:App.VaultFileExistedAtLoad = $true
        $script:App.VaultLoadedRevision = [long]$vault['Revision']
        # Ab jetzt entspricht die Hauptdatei dem eigenen Stand - ein evtl.
        # Wiederherstellungsvorgang aus Pending/Backup ist damit abgeschlossen.
        $script:App.LoadedFrom = 'Haupt'
        # Eine vault.prev.azt aus aelteren Programmversionen (frueherer
        # Dateiaustausch) wird einmalig neutral nach Recovery gesichert.
        if (Test-Path -LiteralPath $script:Paths.VaultPrev) {
            try {
                $prevLeftPrefix = 'vault-unreadable'
                if (Test-VaultFileFullyUsable -Path $script:Paths.VaultPrev) { $prevLeftPrefix = 'vault-prev' }
                Move-FileToRecovery -Path $script:Paths.VaultPrev -Prefix $prevLeftPrefix | Out-Null
                Write-AppLog -Message 'Vorhandene vault.prev.azt neutral in Recovery gesichert.'
            }
            catch { }
        }
        # 7. Backuprotation NACH erfolgreicher Uebernahme und Pruefung,
        #    ausschliesslich in-place. Rotationsentscheidungen beruhen IMMER
        #    auf der VOLLSTAENDIGEN Pruefung (Test-VaultFileFullyUsable): eine
        #    lediglich HMAC-gueltige, aber strukturell ungueltige Datei darf
        #    niemals ein anderes gueltiges Backup ueberschreiben. Unbrauchbare
        #    Dateien werden neutral nach Recovery gesichert. ($mainKnownGood
        #    ist zulaessig: der alte Hauptstand wurde beim Entsperren
        #    vollstaendig validiert und ist seither nachweislich unveraendert.)
        #    Die gesamte Rotation ist NACH dem Commit reine Best-Effort-
        #    Arbeit: ein Fehler hier macht den committeten Hauptspeicherstand
        #    NICHT rueckgaengig, Save-Vault liefert weiterhin true.
        try {
            if ($null -ne $oldMainBytes -and -not $skipRotation) {
                if ($oldMainUsable) {
                    if (Test-Path -LiteralPath $script:Paths.VaultBackup1) {
                        if (Test-VaultFileFullyUsable -Path $script:Paths.VaultBackup1) {
                            if ($script:TestMode -and $script:App.Flags.TestFailBackupCopy) {
                                throw (New-Object System.IO.IOException 'TESTHOOK: Backupkopie deaktiviert')
                            }
                            Write-FileInPlace -Path $script:Paths.VaultBackup2 -Bytes ([System.IO.File]::ReadAllBytes($script:Paths.VaultBackup1))
                        }
                        else {
                            # Unbrauchbares Backup1 darf Backup2 nicht ueberschreiben
                            try { Move-FileToRecovery -Path $script:Paths.VaultBackup1 -Prefix 'vault-unreadable' | Out-Null } catch { }
                        }
                    }
                    if ($script:TestMode -and $script:App.Flags.TestFailBackup1Write) {
                        throw (New-Object System.IO.IOException 'TESTHOOK: Schreiben von Backup1 deaktiviert')
                    }
                    Write-FileInPlace -Path $script:Paths.VaultBackup1 -Bytes $oldMainBytes
                }
                else {
                    # Eine beschaedigte alte Hauptdatei wird NICHT als Backup1
                    # weitergefuehrt, sondern als neue Datei nach Recovery gesichert
                    try {
                        if (-not (Test-Path -LiteralPath $script:Paths.Recovery)) {
                            New-Item -ItemType Directory -Path $script:Paths.Recovery -Force | Out-Null
                        }
                        [System.IO.File]::WriteAllBytes((Join-Path $script:Paths.Recovery ('vault-unreadable-{0}.azt' -f ([guid]::NewGuid().ToString()))), $oldMainBytes)
                    }
                    catch { }
                }
            }
        }
        catch {
            # Fehlgeschlagene Backuprotation ist KEIN fehlgeschlagener
            # Hauptspeicherstand: nur neutral protokollieren und den Benutzer
            # hoechstens einmal informieren (keine Dialogschleife).
            Write-AppLog -Level 'WARN' -Message ('Backuprotation nach erfolgreichem Speichern fehlgeschlagen (Best Effort) - die Arbeitszeitdaten sind gespeichert: ' + $_.Exception.Message)
            if (-not $script:App.Flags.BackupWarningShown) {
                $script:App.Flags.BackupWarningShown = $true
                if (-not $Quiet) {
                    Show-Warning -Message ('Die Arbeitszeitdaten wurden erfolgreich gespeichert. Ein Backup konnte dabei jedoch nicht aktualisiert werden. ' +
                        'Der gespeicherte Stand ist davon nicht betroffen.')
                }
            }
        }
        Clear-VaultSaveFailedState
        return $true
    }
    catch {
        # NACH dem Commit-Punkt: kein Rollback und kein false - die neue
        # Hauptdatei ist bereits gueltig geschrieben und vollstaendig geprueft.
        if ($commitCompleted) {
            Write-AppLog -Level 'WARN' -Message ('Nachgelagerter Fehler nach erfolgreich committetem Speichervorgang (Best Effort): ' + $_.Exception.Message)
            Clear-VaultSaveFailedState
            return $true
        }
        # Fehlgeschlagener Versuch VOR dem Commit: alle Metadaten aus dem
        # Snapshot zuruecksetzen und das Journal wieder auf den bisherigen
        # Stand bringen (in-place, keine Loeschung) - es bleibt kein neuerer,
        # nicht uebernommener Stand zurueck. Im kritischen Fall
        # (VAULT_SWAP_CRITICAL) bleibt das Journal mit dem neuen Stand erhalten.
        & $restoreMeta
        if ($journalTouched) {
            try {
                if ($null -ne $oldPendingBytes) {
                    Write-FileInPlace -Path $script:Paths.VaultPending -Bytes $oldPendingBytes
                }
                elseif ($null -ne $oldMainBytes) {
                    Write-FileInPlace -Path $script:Paths.VaultPending -Bytes $oldMainBytes
                }
                elseif ($null -ne $oldPendingUnreadable) {
                    # Ohne Hauptdatei gibt es keinen besseren Stand: den
                    # bisherigen Journalinhalt unveraendert zurueckschreiben.
                    Write-FileInPlace -Path $script:Paths.VaultPending -Bytes $oldPendingUnreadable
                }
                elseif (Test-Path -LiteralPath $script:Paths.VaultPending) {
                    # Erster Speichervorgang ohne bisherigen Stand: es gibt
                    # nichts zum Zurueckschreiben - das Journal wird entfernt.
                    Remove-Item -LiteralPath $script:Paths.VaultPending -Force -ErrorAction SilentlyContinue
                }
            }
            catch { }
        }
        # Spaet erkannte Fremdaenderung (Schritt 6): Hauptdatei unangetastet,
        # Journal zurueckgenommen - jetzt regulaere Konfliktbehandlung
        if ([string]$_.Exception.Message -eq 'VAULT_EXTERNAL_CHANGE') {
            & $handleExternalChange 'unmittelbar vor dem Schreiben verändert'
            return $false
        }
        Set-VaultSaveFailedState
        if (-not $Quiet -and [string]$_.Exception.Message -ne 'VAULT_SWAP_CRITICAL') {
            Show-AppError -Message 'Der Datentresor konnte nicht gespeichert werden. Der letzte gültige Stand bleibt erhalten. Die Anwendung versucht es automatisch erneut; der Zustand wird bis dahin als NICHT GESPEICHERT angezeigt.' -ErrorRecord $_
        }
        return $false
    }
    finally {
        $script:App.Flags.SaveInProgress = $false
    }
}

# Markiert den Anwendungszustand als "noch nicht gespeichert" (begrenzte
# automatische Wiederholungsversuche laufen ueber den Haupt-Timer).
function Set-VaultSaveFailedState {
    if ($script:App -and $script:App.Flags) {
        $script:App.Flags.UnsavedChanges = $true
    }
}

function Clear-VaultSaveFailedState {
    if ($script:App -and $script:App.Flags) {
        $script:App.Flags.UnsavedChanges = $false
        $script:App.Flags.SaveRetryCount = 0
    }
}

# Ueberschreibt eine Klartextdatei vor dem Loeschen mit Zufallsdaten.
# Ehrlicher Hinweis: Auf SSDs (Wear Leveling) und in Cloud-Speichern
# (Versionsverlauf, Papierkorb) ist dieses Ueberschreiben moeglicherweise
# wirkungslos - eine absolut sichere Loeschung wird NICHT versprochen.
function Remove-PlaintextFileSecure {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $length = (Get-Item -LiteralPath $Path).Length
        if ($length -gt 0) {
            $noise = [ArbeitszeitTool.VaultCrypto]::GetRandomBytes([int][math]::Min($length, 16MB))
            $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write)
            try {
                $remaining = $length
                while ($remaining -gt 0) {
                    $chunk = [int][math]::Min($remaining, $noise.Length)
                    $stream.Write($noise, 0, $chunk)
                    $remaining -= $chunk
                }
                $stream.Flush($true)
            }
            finally { $stream.Dispose() }
            [ArbeitszeitTool.VaultCrypto]::ClearBytes($noise)
        }
    }
    catch { } # Ueberschreiben ist Best Effort; geloescht wird in jedem Fall
    Remove-Item -LiteralPath $Path -Force
}

#endregion

#region ===== Datenzugriff (JSON, atomar, Backup) =====

# ConvertFrom-Json liefert PSCustomObject; intern arbeiten wir mit
# (geordneten) Hashtables und ArrayLists, damit Werte einfach aenderbar sind.
function ConvertTo-PlainObject {
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $ht = [ordered]@{}
        foreach ($prop in $InputObject.PSObject.Properties) {
            $ht[$prop.Name] = ConvertTo-PlainObject $prop.Value
        }
        return $ht
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $ht = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $ht[$key] = ConvertTo-PlainObject $InputObject[$key]
        }
        return $ht
    }
    if (($InputObject -is [System.Collections.IEnumerable]) -and ($InputObject -isnot [string])) {
        $list = New-Object System.Collections.ArrayList
        foreach ($item in $InputObject) {
            [void]$list.Add((ConvertTo-PlainObject $item))
        }
        return ,$list
    }
    return $InputObject
}

# Liest eine Klartext-JSON-Datei. Wird NUR noch fuer die einmalige Migration
# vorhandener Altdaten benoetigt - neue Daten werden nie im Klartext geschrieben.
function Read-JsonFileRaw {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = [System.IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ConvertTo-PlainObject ($raw | ConvertFrom-Json)
}

function New-EmptyWorkData {
    return [ordered]@{
        SchemaVersion = $script:Const.SchemaVersion
        LastSavedAt   = $null
        Days          = (New-Object System.Collections.ArrayList)
    }
}

# Speichert die Arbeitszeitdaten: Alle Daten (WorkData, Einstellungen, Logs)
# liegen im gemeinsamen verschluesselten Tresor und werden atomar gespeichert.
# Liefert IMMER einen booleschen Erfolg. In reinen Berechnungs-/Testkontexten
# ohne entsperrten Tresor gibt es nichts zu speichern - die Aenderung im
# Arbeitsspeicher gilt dann als erfolgreich uebernommen ($true).
function Save-WorkData {
    param([switch]$Quiet, [switch]$NoBackupRotation)
    if ($null -eq $script:App -or $null -eq $script:App.Data) { return $true }
    if ($null -eq $script:App.Vault -or -not $script:VaultSession.Unlocked) { return $true }
    return [bool](Save-Vault -Quiet:$Quiet -NoBackupRotation:$NoBackupRotation)
}

#endregion

#region ===== Einstellungen =====

function Get-DefaultSettings {
    return [ordered]@{
        SchemaVersion        = $script:Const.SchemaVersion
        RegularTime          = '07:00'      # Regelarbeitszeit (aenderbar)
        Transparency         = 92           # 30..100 Prozent
        FontSize             = 13
        WindowLeft           = $null
        WindowTop            = $null
        WindowWidth          = $null
        CompactFields        = @('Beginn', 'Netto', 'SollRestOderUeberstunden', 'MaxEnde')
        Topmost              = $true
        TopmostReassert      = $true
        KeepAliveEnabled     = $false
        KeepAliveIntervalSec = 60
        TrayIconEnabled      = $true
        ShowSeconds          = $true
        Warn945Enabled       = $true
        SoundEnabled         = $false
        StartView            = 'Kompakt'    # 'Kompakt' oder 'Erweitert'
        # Opt-in (Standard AUS): Tagesabschlussdialog bietet zusaetzlich
        # "Arbeitstag beenden und PC herunterfahren" an; der Dialog
        # "Anwendung schliessen" bietet zusaetzlich eine passende
        # Shutdown-Auswahl an. Die konkrete Auswahl gilt nur fuer den
        # jeweiligen Vorgang und wird nie vorausgewaehlt.
        ShutdownOfferEnabled = $false
        # Eigene Presets der kompakten Ansicht (nur Id/Name/Fields; keine
        # Fensterposition, Passwoerter, Radiosender oder Arbeitszeitdaten)
        CompactPresets       = (New-Object System.Collections.ArrayList)
        # Internetradio (optional; Streams werden NUR bei aktiver Wiedergabe
        # abgerufen - beim Programmstart keine automatische Wiedergabe)
        RadioStations              = (Get-DefaultRadioStations)
        RadioSelectedStationId     = $null
        RadioVolume                = 20     # 0..100 (fuer MediaPlayer auf 0.0..1.0 umgerechnet)
        RadioResumeAfterUnlock     = $true
        RadioRememberPlaybackState = $false
        RadioLastWasPlaying        = $false
    }
}

# Fuehrt geladene Einstellungen (aus dem Tresor oder einer Klartext-Migration)
# mit den Standardwerten zusammen und plausibilisiert sie.
function Get-ValidatedSettings {
    param($Loaded)
    $defaults = Get-DefaultSettings
    if ($Loaded -is [System.Collections.IDictionary]) {
        foreach ($key in @($defaults.Keys)) {
            if ($Loaded.Contains($key) -and $null -ne $Loaded[$key]) {
                $defaults[$key] = $Loaded[$key]
            }
        }
    }
    # Plausibilisierung
    if (-not (Test-TimeText $defaults['RegularTime'])) { $defaults['RegularTime'] = '07:00' }
    else {
        # Regelarbeitszeit: groesser 00:00, maximal 10:00
        $p = ([string]$defaults['RegularTime']).Split(':')
        $regMin = ([int]$p[0]) * 60 + [int]$p[1]
        if ($regMin -le 0 -or $regMin -gt $script:Const.MaxMinutes) { $defaults['RegularTime'] = '07:00' }
    }
    # Die Breite der kompakten Ansicht richtet sich ausschliesslich nach dem
    # Inhalt (SizeToContent). Ein noch vorhandener WindowWidth-Wert aus
    # aelteren Versionen wird bewusst verworfen und hat keinerlei Wirkung.
    $defaults['WindowWidth'] = $null
    $defaults['Transparency'] = [math]::Max(30, [math]::Min(100, [int]$defaults['Transparency']))
    $defaults['FontSize'] = [math]::Max(9, [math]::Min(28, [int]$defaults['FontSize']))
    $defaults['KeepAliveIntervalSec'] = [math]::Max(10, [math]::Min(600, [int]$defaults['KeepAliveIntervalSec']))
    if (@('Kompakt', 'Erweitert') -notcontains $defaults['StartView']) { $defaults['StartView'] = 'Kompakt' }
    $defaults['ShutdownOfferEnabled'] = [bool]$defaults['ShutdownOfferEnabled']
    # Unbekannte Felder werden verworfen; bleibt nichts uebrig, gilt die
    # Standardauswahl.
    $knownFields = New-Object System.Collections.ArrayList
    if ($defaults['CompactFields'] -is [System.Collections.IList]) {
        foreach ($f in @($defaults['CompactFields'])) {
            if ($script:CompactFieldDefs.Contains([string]$f)) { [void]$knownFields.Add([string]$f) }
        }
    }
    if ($knownFields.Count -eq 0) {
        $defaults['CompactFields'] = @('Beginn', 'Netto', 'SollRestOderUeberstunden', 'MaxEnde')
    }
    else {
        $defaults['CompactFields'] = $knownFields
    }
    # Eigene Presets der kompakten Ansicht: bestehende Tresore ohne Presets
    # erhalten automatisch eine leere, kompatible Liste (rueckwaertskompatibel)
    $defaults['CompactPresets'] = Get-ValidatedCompactPresets -Loaded $defaults['CompactPresets']
    # Internetradio: Vorhandene Tresore OHNE Radioeinstellungen bleiben
    # weiterhin ladbar - fehlende Werte werden hier ergaenzt (keine
    # Schemaerhoehung erforderlich). Eine bewusst LEERE Senderliste bleibt leer.
    if ($defaults['RadioStations'] -isnot [System.Collections.IList]) {
        $defaults['RadioStations'] = Get-DefaultRadioStations
    }
    else {
        $defaults['RadioStations'] = Get-ValidatedRadioStations -Loaded $defaults['RadioStations']
    }
    $defaults['RadioVolume'] = [math]::Max(0, [math]::Min(100, [int]$defaults['RadioVolume']))
    $defaults['RadioResumeAfterUnlock'] = [bool]$defaults['RadioResumeAfterUnlock']
    $defaults['RadioRememberPlaybackState'] = [bool]$defaults['RadioRememberPlaybackState']
    $defaults['RadioLastWasPlaying'] = [bool]$defaults['RadioLastWasPlaying']
    $selFound = $false
    foreach ($st in @($defaults['RadioStations'])) {
        if ([string]$st['Id'] -eq [string]$defaults['RadioSelectedStationId']) { $selFound = $true }
    }
    if (-not $selFound) {
        $defaults['RadioSelectedStationId'] = $null
        if (@($defaults['RadioStations']).Count -gt 0) {
            $defaults['RadioSelectedStationId'] = [string]$defaults['RadioStations'][0]['Id']
        }
    }
    return $defaults
}

# Einstellungen liegen im verschluesselten Tresor und werden mit ihm gespeichert.
# Liefert booleschen Erfolg (siehe Save-WorkData).
function Save-Settings {
    param([switch]$Quiet)
    if ($null -eq $script:App -or $null -eq $script:App.Settings) { return $true }
    if ($null -eq $script:App.Vault -or -not $script:VaultSession.Unlocked) { return $true }
    return [bool](Save-Vault -Quiet:$Quiet)
}

function Get-RegularMinutes {
    $text = [string]$script:App.Settings['RegularTime']
    if (-not (Test-TimeText $text)) { return 420 }
    $parts = $text.Split(':')
    return ([int]$parts[0]) * 60 + [int]$parts[1]
}

# Prueft eine Regelarbeitszeit-Eingabe: groesser 00:00, maximal 10:00.
# Liefert die Minutenzahl oder -1 bei ungueltiger Eingabe.
function Test-RegularTimeInput {
    param([string]$Text)
    if (-not (Test-TimeText $Text)) { return -1 }
    $parts = ([string]$Text).Split(':')
    $minutes = ([int]$parts[0]) * 60 + [int]$parts[1]
    if ($minutes -le 0 -or $minutes -gt $script:Const.MaxMinutes) { return -1 }
    return $minutes
}

#endregion


#region ===== Datenmodell =====

function New-WorkDayObject {
    param(
        [Parameter(Mandatory)][datetime]$Date,
        [int]$RegularMinutes
    )
    $now = Get-Date
    return [ordered]@{
        Id             = [guid]::NewGuid().ToString()
        Date           = $Date.ToString('yyyy-MM-dd')
        Status         = 'Aktiv'            # 'Aktiv' | 'Beendet'
        EarliestStart  = $null
        EndedAt        = $null
        RegularMinutes = $RegularMinutes
        MaxMinutes     = $script:Const.MaxMinutes
        MaxReached     = $false
        AutoEnded      = $false
        EndReason      = $null              # 'Manuell' | 'Tageswechsel'
        Totals         = [ordered]@{}
        Segments       = (New-Object System.Collections.ArrayList)
        ManualPauses   = (New-Object System.Collections.ArrayList)
        LockIntervals  = (New-Object System.Collections.ArrayList)
        Corrections    = (New-Object System.Collections.ArrayList)
        CreatedAt      = ConvertTo-DateTimeString $now
        ModifiedAt     = ConvertTo-DateTimeString $now
    }
}

function New-SegmentObject {
    param(
        [Parameter(Mandatory)][string]$Mode,      # 'Betrieb' | 'Homeoffice'
        [Parameter(Mandatory)][datetime]$Start,
        [datetime]$End,
        [bool]$Running = $false,
        [bool]$Manual = $false
    )
    $endText = $null
    if ($PSBoundParameters.ContainsKey('End') -and $null -ne $End) { $endText = ConvertTo-DateTimeString $End }
    return [ordered]@{
        Id        = [guid]::NewGuid().ToString()
        Mode      = $Mode
        Start     = ConvertTo-DateTimeString $Start
        End       = $endText
        Running   = $Running
        Manual    = $Manual
        Corrected = $false
        Brutto    = '00:00'
        Pause     = '00:00'
        Netto     = '00:00'
    }
}

function New-IntervalObject {
    param(
        [Parameter(Mandatory)][datetime]$Start,
        [datetime]$End
    )
    $endText = $null
    if ($PSBoundParameters.ContainsKey('End') -and $null -ne $End) { $endText = ConvertTo-DateTimeString $End }
    return [ordered]@{
        Id    = [guid]::NewGuid().ToString()
        Start = ConvertTo-DateTimeString $Start
        End   = $endText
    }
}

# Schreibt den ERFOLGSLOGEINTRAG zu einer Korrektur in das verschluesselte
# Anwendungsprotokoll (einheitliches Format). Bei transaktionalen, im
# Fehlerfall vollstaendig zurueckgerollten Benutzeraktionen wird er ERST NACH
# erfolgreich verifiziertem Speichern aufgerufen (Add-Correction -NoLog) -
# eine zurueckgerollte Aktion hinterlaesst so niemals einen Erfolgslogeintrag.
function Write-CorrectionLog {
    param(
        [Parameter(Mandatory)]$Day,
        [Parameter(Mandatory)][string]$Description,
        [string]$OldValue = '',
        [string]$NewValue = ''
    )
    Write-AppLog -Message "Korrektur ($($Day.Date)): $Description | alt: '$OldValue' | neu: '$NewValue'"
}

function Add-Correction {
    param(
        [Parameter(Mandatory)]$Day,
        [Parameter(Mandatory)][string]$Description,
        [string]$OldValue = '',
        [string]$NewValue = '',
        # Optionale Begruendung/Kommentar zur Korrektur (nicht im Protokoll)
        [string]$Comment = '',
        # -NoLog: Korrektureintrag nur im Tagesobjekt anlegen (er ist damit
        # Teil des Tages-Snapshots und wird bei einem Rollback vollstaendig
        # zurueckgenommen); den Erfolgslogeintrag schreibt der Aufrufer erst
        # nach erfolgreichem Speichern ueber Write-CorrectionLog.
        [switch]$NoLog
    )
    $corr = [ordered]@{
        Timestamp   = ConvertTo-DateTimeString (Get-Date)
        Description = $Description
        OldValue    = $OldValue
        NewValue    = $NewValue
    }
    [void](Set-ItemComment -Item $corr -Text $Comment)
    [void]$Day['Corrections'].Add($corr)
    $Day['ModifiedAt'] = ConvertTo-DateTimeString (Get-Date)
    if (-not $NoLog) {
        Write-CorrectionLog -Day $Day -Description $Description -OldValue $OldValue -NewValue $NewValue
    }
}

# Kommentare (optional) an Tag, Abschnitt, Pause, Sperrintervall und
# Korrektur: Feld 'Comment' im jeweiligen Objekt. Fehlt das Feld, gibt es
# keinen Kommentar (aeltere Tresore bleiben unveraendert ladbar). Kommentare
# veraendern keine Zeiten und zaehlen daher NICHT als Korrektur.
$script:CommentConst = @{
    MaxLength     = 1000   # maximale Zeichenzahl eines Kommentars
    PreviewLength = 60     # Kurzanzeige in Tabellen (eine Zeile)
}

# Normalisiert einen Kommentartext: Steuerzeichen (ausser Zeilenumbruch und
# Tabulator) entfernen, Zeilenenden vereinheitlichen (CRLF), Leerraum am Rand
# entfernen und die Laenge begrenzen. Liefert '' fuer "kein Kommentar".
function Get-NormalizedComment {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $t = $Text -replace "`r`n?", "`n"
    $t = [regex]::Replace($t, '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', '')
    $t = $t.Trim()
    $max = [int]$script:CommentConst.MaxLength
    if ($t.Length -gt $max) {
        # kein halbes Surrogatpaar am Schnittpunkt zuruecklassen
        if ([char]::IsHighSurrogate($t[$max - 1])) { $max-- }
        $t = $t.Substring(0, $max).TrimEnd()
    }
    return ($t -replace "`n", "`r`n")
}

function Get-ItemComment {
    param($Item)
    if ($Item -is [System.Collections.IDictionary] -and $Item.Contains('Comment') -and $null -ne $Item['Comment']) {
        return [string]$Item['Comment']
    }
    return ''
}

# Setzt (oder entfernt bei leerem Text) den Kommentar eines Objekts.
# Liefert den gespeicherten, normalisierten Text.
function Set-ItemComment {
    param([Parameter(Mandatory)]$Item, [AllowNull()][string]$Text)
    $norm = Get-NormalizedComment -Text $Text
    if ($norm -eq '') {
        if ($Item.Contains('Comment')) { $Item.Remove('Comment') }
    }
    else {
        $Item['Comment'] = $norm
    }
    return $norm
}

# Einzeilige Kurzfassung fuer Tabellen und Menues
function Get-CommentPreview {
    param([AllowNull()][string]$Text, [int]$MaxLength = 0)
    if ($MaxLength -le 0) { $MaxLength = [int]$script:CommentConst.PreviewLength }
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $t = (($Text -replace "`r`n?|`n", ' / ') -replace '\s+', ' ').Trim()
    if ($t.Length -gt $MaxLength) { $t = $t.Substring(0, $MaxLength - 1).TrimEnd() + '…' }
    return $t
}

# Setzt einen Kommentar transaktional: Schnappschuss des Tages, Aenderung,
# Speichern; bei einem Speicherfehler wird die Aenderung vollstaendig
# zurueckgenommen. Das Protokoll vermerkt nur, DASS ein Kommentar geaendert
# wurde - nicht den Inhalt. $Item ist der Tag selbst oder ein Objekt des
# Tages (Abschnitt, Pause, Sperrintervall, Korrektur). Achtung: Nach einem
# Rollback sind Referenzen auf Unterobjekte des Tages veraltet.
function Set-DayItemCommentSaved {
    param(
        [Parameter(Mandatory)]$Day,
        [Parameter(Mandatory)]$Item,
        [AllowNull()][string]$Text,
        [Parameter(Mandatory)][string]$Label
    )
    $new = Get-NormalizedComment -Text $Text
    $old = Get-ItemComment -Item $Item
    if ($new -eq $old) { return $true }
    $snapshot = Get-DaySnapshot -Day $Day
    [void](Set-ItemComment -Item $Item -Text $new)
    $Day['ModifiedAt'] = ConvertTo-DateTimeString (Get-Date)
    if (-not (Save-WorkData)) {
        Restore-DayFromSnapshot -Day $Day -Snapshot $snapshot
        Write-AppLog -Level 'WARN' -Message 'Kommentar NICHT gespeichert - Änderung zurückgenommen.'
        return $false
    }
    Write-CommentChangeLog -Day $Day -Label $Label -Old $old -New $new
    return $true
}

# Protokolliert nur, DASS ein Kommentar geaendert wurde - nie den Inhalt
function Write-CommentChangeLog {
    param([Parameter(Mandatory)]$Day, [Parameter(Mandatory)][string]$Label, [string]$Old = '', [string]$New = '')
    if ($Old -eq $New) { return }
    $what = 'geaendert'
    if ($Old -eq '') { $what = 'hinzugefuegt' }
    elseif ($New -eq '') { $what = 'entfernt' }
    Write-AppLog -Message "Kommentar ($($Day.Date)): $Label - Kommentar $what."
}

#endregion

#region ===== Berechnungs-Engine (Intervallvereinigung, Nettozeiten, Endzeiten) =====

# Vereinigt Zeitintervalle (@{Start='...';End='...'/$null}); offene Intervalle
# werden bis $Now gerechnet. Ergebnis: sortierte, ueberlappungsfreie Liste
# mit [datetime]-Werten. Verhindert doppelte Pausenabzuege.
function Merge-TimeIntervals {
    param($Intervals, [Parameter(Mandatory)][datetime]$Now)
    $list = New-Object System.Collections.ArrayList
    foreach ($iv in @($Intervals)) {
        if ($null -eq $iv) { continue }
        $s = ConvertFrom-DateTimeString $iv.Start
        if ($null -eq $s) { continue }
        $e = $Now
        if ($iv.End) { $e = ConvertFrom-DateTimeString $iv.End }
        if ($e -gt $s) { [void]$list.Add(@{ Start = $s; End = $e }) }
    }
    $sorted = @($list | Sort-Object -Property @{ Expression = { $_.Start } })
    $merged = New-Object System.Collections.ArrayList
    foreach ($iv in $sorted) {
        if ($merged.Count -gt 0 -and $iv.Start -le $merged[$merged.Count - 1].End) {
            if ($iv.End -gt $merged[$merged.Count - 1].End) {
                $merged[$merged.Count - 1].End = $iv.End
            }
        }
        else {
            [void]$merged.Add(@{ Start = $iv.Start; End = $iv.End })
        }
    }
    return ,$merged
}

# Ueberlappungsdauer eines Zeitraums mit einer vereinigten Intervallliste
function Get-OverlapDuration {
    param(
        [Parameter(Mandatory)][datetime]$Start,
        [Parameter(Mandatory)][datetime]$End,
        $MergedIntervals
    )
    $total = [TimeSpan]::Zero
    foreach ($iv in @($MergedIntervals)) {
        if ($null -eq $iv) { continue }
        $s = $Start
        if ($iv.Start -gt $s) { $s = $iv.Start }
        $e = $End
        if ($iv.End -lt $e) { $e = $iv.End }
        if ($e -gt $s) { $total += ($e - $s) }
    }
    return $total
}

# Segmente eines Tages als [datetime]-Struktur, chronologisch sortiert.
# Laufende Segmente enden rechnerisch bei $Now.
function Get-ParsedSegments {
    param([Parameter(Mandatory)]$Day, [Parameter(Mandatory)][datetime]$Now)
    $result = New-Object System.Collections.ArrayList
    foreach ($seg in @($Day.Segments)) {
        if ($null -eq $seg) { continue }
        $s = ConvertFrom-DateTimeString $seg.Start
        if ($null -eq $s) { continue }
        $e = $s
        if ($seg.End) { $e = ConvertFrom-DateTimeString $seg.End }
        elseif ($seg.Running) { $e = $Now }
        if ($e -lt $s) { $e = $s }
        [void]$result.Add(@{ Ref = $seg; Id = $seg.Id; Mode = $seg.Mode; Start = $s; End = $e; Running = [bool]$seg.Running })
    }
    return ,@($result | Sort-Object -Property @{ Expression = { $_.Start } })
}

# Wall-Clock-Fenster der festen Betriebspause: die Abschnitte der Betriebszeit,
# in denen die kumulierte Betriebs-Bruttozeit zwischen 6:00 und 6:45 liegt.
function Get-BetriebPauseWindows {
    param($BetriebSegments)
    $windows = New-Object System.Collections.ArrayList
    $pauseStart = [TimeSpan]::FromMinutes($script:Const.BetriebPauseNachMinuten)
    $pauseEnd = $pauseStart + [TimeSpan]::FromMinutes($script:Const.BetriebPauseMinutes)
    $cum = [TimeSpan]::Zero
    foreach ($seg in @($BetriebSegments)) {
        $dur = $seg.End - $seg.Start
        $segCumStart = $cum
        $segCumEnd = $cum + $dur
        $ovStart = $segCumStart
        if ($pauseStart -gt $ovStart) { $ovStart = $pauseStart }
        $ovEnd = $segCumEnd
        if ($pauseEnd -lt $ovEnd) { $ovEnd = $pauseEnd }
        if ($ovEnd -gt $ovStart) {
            [void]$windows.Add(@{
                    Start = $seg.Start + ($ovStart - $segCumStart)
                    End   = $seg.Start + ($ovEnd - $segCumStart)
                })
        }
        $cum = $segCumEnd
    }
    return ,$windows
}

# Zentrale Tagesberechnung. Reine Funktion: Tag + Bezugszeitpunkt -> alle Werte.
function Get-DayComputation {
    param(
        [Parameter(Mandatory)]$Day,
        [datetime]$Now = (Get-Date)
    )
    $segs = Get-ParsedSegments -Day $Day -Now $Now
    $betriebSegs = @($segs | Where-Object { $_.Mode -eq 'Betrieb' })
    $hoSegs = @($segs | Where-Object { $_.Mode -eq 'Homeoffice' })

    # --- Betrieb: Sperren/Pausen zaehlen weiter, feste Pause nach 6 h ---
    $betriebBrutto = [TimeSpan]::Zero
    foreach ($seg in $betriebSegs) { $betriebBrutto += ($seg.End - $seg.Start) }
    $sixHours = [TimeSpan]::FromMinutes($script:Const.BetriebPauseNachMinuten)
    $maxPause = [TimeSpan]::FromMinutes($script:Const.BetriebPauseMinutes)
    $festeAbzug = $betriebBrutto - $sixHours
    if ($festeAbzug -lt [TimeSpan]::Zero) { $festeAbzug = [TimeSpan]::Zero }
    if ($festeAbzug -gt $maxPause) { $festeAbzug = $maxPause }
    $betriebNetto = $betriebBrutto - $festeAbzug
    $pauseWindows = Get-BetriebPauseWindows -BetriebSegments $betriebSegs

    # --- Homeoffice: Sperrzeiten und manuelle Pausen als vereinigte Menge abziehen ---
    $lockMerged = Merge-TimeIntervals -Intervals $Day.LockIntervals -Now $Now
    $pauseMerged = Merge-TimeIntervals -Intervals $Day.ManualPauses -Now $Now
    $allNonWork = New-Object System.Collections.ArrayList
    foreach ($iv in @($Day.LockIntervals)) { [void]$allNonWork.Add($iv) }
    foreach ($iv in @($Day.ManualPauses)) { [void]$allNonWork.Add($iv) }
    $nonWorkMerged = Merge-TimeIntervals -Intervals $allNonWork -Now $Now

    $hoBrutto = [TimeSpan]::Zero
    $hoAbzug = [TimeSpan]::Zero
    $sperrZeit = [TimeSpan]::Zero
    $manuellePause = [TimeSpan]::Zero
    foreach ($seg in $hoSegs) {
        $hoBrutto += ($seg.End - $seg.Start)
        $hoAbzug += Get-OverlapDuration -Start $seg.Start -End $seg.End -MergedIntervals $nonWorkMerged
        $sperrZeit += Get-OverlapDuration -Start $seg.Start -End $seg.End -MergedIntervals $lockMerged
        $manuellePause += Get-OverlapDuration -Start $seg.Start -End $seg.End -MergedIntervals $pauseMerged
    }
    $hoNetto = $hoBrutto - $hoAbzug

    # --- Gesamtwerte ---
    $netto = $betriebNetto + $hoNetto
    $regular = [TimeSpan]::FromMinutes([int]$Day.RegularMinutes)
    $maxTs = [TimeSpan]::FromMinutes([int]$Day.MaxMinutes)
    $warnTs = [TimeSpan]::FromMinutes($script:Const.WarnMinutes)

    $sollRest = $regular - $netto
    if ($sollRest -lt [TimeSpan]::Zero) { $sollRest = [TimeSpan]::Zero }
    $ueberstunden = $netto - $regular
    if ($ueberstunden -lt [TimeSpan]::Zero) { $ueberstunden = [TimeSpan]::Zero }
    $maxRest = $maxTs - $netto
    if ($maxRest -lt [TimeSpan]::Zero) { $maxRest = [TimeSpan]::Zero }

    # Fruehester Beginn
    $beginn = $null
    if (@($segs).Count -gt 0) { $beginn = $segs[0].Start }

    # Laufzustand
    $runningSeg = $null
    foreach ($seg in $segs) { if ($seg.Running) { $runningSeg = $seg } }
    $runningMode = $null
    if ($runningSeg) { $runningMode = $runningSeg.Mode }

    $openLock = $null
    foreach ($iv in @($Day.LockIntervals)) { if ($null -eq $iv.End) { $openLock = $iv } }
    $openPause = $null
    foreach ($iv in @($Day.ManualPauses)) { if ($null -eq $iv.End) { $openPause = $iv } }

    # Zaehlt die Nettozeit gerade? (laufendes Segment, im HO nicht gesperrt/pausiert,
    # im Betrieb nicht innerhalb des festen Pausenfensters)
    $isCounting = $false
    $inFesterPause = $false
    if ($runningSeg -and $Day.Status -eq 'Aktiv' -and -not $Day.MaxReached) {
        if ($runningMode -eq 'Betrieb') {
            # Grenzwert: bei exakt 06:00 Betriebszeit ist die feste Pause bereits aktiv
            $inFesterPause = ($betriebBrutto -ge $sixHours -and $festeAbzug -lt $maxPause)
            $isCounting = -not $inFesterPause
        }
        else {
            $isCounting = ($null -eq $openLock -and $null -eq $openPause)
        }
    }

    # --- Endzeit-Projektion: aktueller Modus laeuft unveraendert weiter ---
    $sollEnde = $null
    $maxEnde = $null
    $endePausiert = $false
    if ($runningSeg -and $Day.Status -eq 'Aktiv' -and -not $Day.MaxReached) {
        $sollRestRaw = $regular - $netto
        $maxRestRaw = $maxTs - $netto
        if ($runningMode -eq 'Betrieb') {
            # Kuenftige feste Pause einplanen, falls noch nicht (voll) verbraucht
            $pauseStartsIn = $sixHours - $betriebBrutto
            if ($pauseStartsIn -lt [TimeSpan]::Zero) { $pauseStartsIn = [TimeSpan]::Zero }
            $pauseRemaining = $maxPause - $festeAbzug
            if ($sollRestRaw -gt [TimeSpan]::Zero) {
                $extra = [TimeSpan]::Zero
                if ($sollRestRaw -gt $pauseStartsIn) { $extra = $pauseRemaining }
                $sollEnde = $Now + $sollRestRaw + $extra
            }
            if ($maxRestRaw -gt [TimeSpan]::Zero) {
                $extra = [TimeSpan]::Zero
                if ($maxRestRaw -gt $pauseStartsIn) { $extra = $pauseRemaining }
                $maxEnde = $Now + $maxRestRaw + $extra
            }
            $endePausiert = $inFesterPause
        }
        else {
            # Homeoffice: keine kuenftigen Pausen erfinden; bereits entstandene
            # Sperr-/Pausenzeiten stecken in $netto und schieben das Ende nach hinten.
            if ($sollRestRaw -gt [TimeSpan]::Zero) { $sollEnde = $Now + $sollRestRaw }
            if ($maxRestRaw -gt [TimeSpan]::Zero) { $maxEnde = $Now + $maxRestRaw }
            $endePausiert = -not $isCounting
        }
    }

    # Warn945Enabled aus den Einstellungen; $script:App.Settings kann beim Validieren
    # eines gerade geladenen Tresors noch $null sein (Set-ActiveVault laeuft erst nach
    # erfolgreicher Strukturpruefung). Daher gegen $null absichern - sonst wuerde die
    # Tagesberechnung fehlschlagen und ein gueltiger Tresor als beschaedigt gelten.
    $warn945Enabled = $true
    if ($script:App -and $script:App.Settings) { $warn945Enabled = [bool]$script:App.Settings['Warn945Enabled'] }
    $warnActive = ($warn945Enabled -and $netto -ge $warnTs -and $netto -lt $maxTs -and -not $Day.MaxReached)

    return @{
        Segments       = $segs
        Beginn         = $beginn
        BetriebBrutto  = $betriebBrutto
        BetriebNetto   = $betriebNetto
        FesteAbzug     = $festeAbzug
        PauseWindows   = $pauseWindows
        HoBrutto       = $hoBrutto
        HoNetto        = $hoNetto
        HoAbzug        = $hoAbzug
        SperrZeit      = $sperrZeit
        ManuellePause  = $manuellePause
        Netto          = $netto
        Regular        = $regular
        SollRest       = $sollRest
        Ueberstunden   = $ueberstunden
        SollErreicht   = ($netto -ge $regular)
        MaxRest        = $maxRest
        MaxTs          = $maxTs
        SollEnde       = $sollEnde
        MaxEnde        = $maxEnde
        EndePausiert   = $endePausiert
        RunningSegment = $runningSeg
        RunningMode    = $runningMode
        OpenLock       = $openLock
        OpenPause      = $openPause
        IsCounting     = $isCounting
        InFesterPause  = $inFesterPause
        WarnActive     = $warnActive
        MaxReached     = [bool]$Day.MaxReached
    }
}

# Schreibt die berechneten Summen zurueck in das Tagesobjekt (fuer Speicherung/Export)
function Update-DayTotals {
    param([Parameter(Mandatory)]$Day, [datetime]$Now = (Get-Date))
    $comp = Get-DayComputation -Day $Day -Now $Now

    if ($comp.Beginn) { $Day['EarliestStart'] = ConvertTo-DateTimeString $comp.Beginn }

    $abweichung = $comp.Netto - $comp.Regular
    $Day['Totals'] = [ordered]@{
        Netto         = Format-Duration $comp.Netto
        Betrieb       = Format-Duration $comp.BetriebNetto
        BetriebBrutto = Format-Duration $comp.BetriebBrutto
        Homeoffice    = Format-Duration $comp.HoNetto
        FesteBetriebspause = Format-Duration $comp.FesteAbzug
        ManuellePause = Format-Duration $comp.ManuellePause
        SperrZeit     = Format-Duration $comp.SperrZeit
        PauseGesamt   = Format-Duration ($comp.FesteAbzug + $comp.HoAbzug)
        SollAbweichung = (Format-Duration $abweichung -WithSign:($abweichung.Ticks -ge 0))
    }

    # Berechnete Werte je Segment aktualisieren
    $lockMerged = Merge-TimeIntervals -Intervals $Day.LockIntervals -Now $Now
    $pauseMergedAll = New-Object System.Collections.ArrayList
    foreach ($iv in @($Day.LockIntervals)) { [void]$pauseMergedAll.Add($iv) }
    foreach ($iv in @($Day.ManualPauses)) { [void]$pauseMergedAll.Add($iv) }
    $nonWorkMerged = Merge-TimeIntervals -Intervals $pauseMergedAll -Now $Now

    foreach ($seg in $comp.Segments) {
        $brutto = $seg.End - $seg.Start
        $pause = [TimeSpan]::Zero
        if ($seg.Mode -eq 'Betrieb') {
            $pause = Get-OverlapDuration -Start $seg.Start -End $seg.End -MergedIntervals $comp.PauseWindows
        }
        else {
            $pause = Get-OverlapDuration -Start $seg.Start -End $seg.End -MergedIntervals $nonWorkMerged
        }
        $seg.Ref['Brutto'] = Format-Duration $brutto
        $seg.Ref['Pause'] = Format-Duration $pause
        $seg.Ref['Netto'] = Format-Duration ($brutto - $pause)
    }

    $Day['ModifiedAt'] = ConvertTo-DateTimeString $Now
    return $comp
}

# Zentrale, ueberall identisch verwendete Ermittlung der DARZUSTELLENDEN
# Endzeit eines Tages (Verlauf, Tagesdetails, Tageseditor, CSV-Export,
# Zusammenfassung). Prioritaet fuer beendete Tage:
#   1. gueltiges Day.EndedAt
#   2. Ende des zeitlich letzten abgeschlossenen Segments
#   3. '--:--'
# Aktive Tage liefern $OpenText. Aus fehlenden Werten ($null, leerer String,
# DateTime.MinValue, fehlendes Segmentende) wird NIEMALS 00:00 abgeleitet.
function Get-DayEndDisplayText {
    param(
        [Parameter(Mandatory)]$Day,
        [string]$OpenText = 'Offen'
    )
    if ([string]$Day.Status -ne 'Beendet') { return $OpenText }
    $ended = $null
    if ($Day.EndedAt) {
        try { $ended = ConvertFrom-DateTimeString $Day.EndedAt } catch { $ended = $null }
    }
    if ($null -ne $ended -and $ended -gt [datetime]::MinValue) { return (Format-Clock $ended) }
    $lastEnd = $null
    foreach ($seg in @($Day.Segments)) {
        if ($null -eq $seg -or -not $seg.End) { continue }
        $e = $null
        try { $e = ConvertFrom-DateTimeString $seg.End } catch { $e = $null }
        if ($null -ne $e -and $e -gt [datetime]::MinValue -and ($null -eq $lastEnd -or $e -gt $lastEnd)) { $lastEnd = $e }
    }
    if ($null -ne $lastEnd) { return (Format-Clock $lastEnd) }
    return '--:--'
}

# Reine ANZEIGE-Berechnung der Segmentwerte (Brutto/Pause/Netto) eines Tages
# zum Bezugszeitpunkt $Now. Veraendert weder Segmentdaten noch Zeitstempel,
# erzeugt nichts und loest keinen Speichervorgang aus - identische
# Berechnungsgrundlage wie Update-DayTotals/Get-DayComputation.
function Get-SegmentDisplayRows {
    param(
        [Parameter(Mandatory)]$Day,
        $Comp = $null,
        [datetime]$Now = (Get-Date)
    )
    if ($null -eq $Comp) { $Comp = Get-DayComputation -Day $Day -Now $Now }
    $nonWork = New-Object System.Collections.ArrayList
    foreach ($iv in @($Day.LockIntervals)) { [void]$nonWork.Add($iv) }
    foreach ($iv in @($Day.ManualPauses)) { [void]$nonWork.Add($iv) }
    $nonWorkMerged = Merge-TimeIntervals -Intervals $nonWork -Now $Now
    $ja = @('nein', 'ja')
    $rows = New-Object System.Collections.ArrayList
    foreach ($seg in $Comp.Segments) {
        $brutto = $seg.End - $seg.Start
        if ($seg.Mode -eq 'Betrieb') {
            $pause = Get-OverlapDuration -Start $seg.Start -End $seg.End -MergedIntervals $Comp.PauseWindows
        }
        else {
            $pause = Get-OverlapDuration -Start $seg.Start -End $seg.End -MergedIntervals $nonWorkMerged
        }
        $endText = 'läuft'
        if (-not $seg.Running) { $endText = Format-Clock $seg.End }
        [void]$rows.Add(@{
                Modus      = [string]$seg.Mode
                Beginn     = (Format-Clock $seg.Start)
                Ende       = $endText
                Brutto     = (Format-Duration $brutto)
                Pause      = (Format-Duration $pause)
                Netto      = (Format-Duration ($brutto - $pause))
                Laufend    = $ja[[int][bool]$seg.Running]
                Manuell    = $ja[[int][bool]$seg.Ref.Manual]
                Korrigiert = $ja[[int][bool]$seg.Ref.Corrected]
                Kommentar  = (Get-CommentPreview -Text (Get-ItemComment -Item $seg.Ref))
                Running    = [bool]$seg.Running
            })
    }
    return ,$rows
}

#endregion


#region ===== Tages-Aktionen (Start, Moduswechsel, Pausen, Sperren, Abschluss) =====

function Get-TodayText {
    return (Get-Date).ToString('yyyy-MM-dd')
}

function Get-ActiveDay {
    foreach ($day in @($script:App.Data.Days)) {
        if ($day.Status -eq 'Aktiv') { return $day }
    }
    return $null
}

function Get-DayByDate {
    param([string]$DateText)
    foreach ($day in @($script:App.Data.Days)) {
        if ($day.Date -eq $DateText) { return $day }
    }
    return $null
}

# Prueft, ob ein Zeitraum mit bestehenden Arbeitsabschnitten kollidiert
function Test-SegmentOverlap {
    param(
        [Parameter(Mandatory)]$Day,
        [Parameter(Mandatory)][datetime]$Start,
        $End = $null,
        [string]$ExcludeId = ''
    )
    $now = Get-Date
    foreach ($seg in @($Day.Segments)) {
        if ($null -eq $seg -or $seg.Id -eq $ExcludeId) { continue }
        $s = ConvertFrom-DateTimeString $seg.Start
        $e = $now
        if ($seg.End) { $e = ConvertFrom-DateTimeString $seg.End }
        $checkEnd = $End
        if ($null -eq $checkEnd) { $checkEnd = $now }
        if ($Start -lt $e -and $checkEnd -gt $s) { return $true }
    }
    return $false
}

# Startet einen neuen Arbeitstag mit Modus und manuell eingetragener Startzeit.
# Transaktional: Schlaegt der Speichervorgang fehl, wird der neue Tag
# vollstaendig zurueckgenommen (kein halber Zustand im Arbeitsspeicher) und
# $null geliefert - die Aktion gilt als nicht durchgefuehrt.
function Start-WorkDay {
    param(
        [Parameter(Mandatory)][string]$Mode,
        [Parameter(Mandatory)][datetime]$StartTime
    )
    $previousDay = $script:App.CurrentDay
    $day = New-WorkDayObject -Date (Get-Date).Date -RegularMinutes (Get-RegularMinutes)
    $seg = New-SegmentObject -Mode $Mode -Start $StartTime -Running $true
    [void]$day['Segments'].Add($seg)
    $day['EarliestStart'] = ConvertTo-DateTimeString $StartTime
    [void]$script:App.Data.Days.Add($day)
    $script:App.CurrentDay = $day
    Update-DayTotals -Day $day | Out-Null
    if (-not (Save-WorkData)) {
        [void]$script:App.Data.Days.Remove($day)
        $script:App.CurrentDay = $previousDay
        Write-AppLog -Level 'WARN' -Message 'Neuer Arbeitstag NICHT gespeichert - Aktion vollständig zurückgenommen.'
        return $null
    }
    Write-AppLog -Message "Neuer Arbeitstag gestartet: $($day.Date), Modus $Mode, Beginn $(Format-Clock $StartTime)"
    return $day
}

# Beendet das laufende Segment zum angegebenen Zeitpunkt
function Stop-RunningSegment {
    param([Parameter(Mandatory)]$Day, [Parameter(Mandatory)][datetime]$End)
    foreach ($seg in @($Day.Segments)) {
        if ($seg.Running) {
            $start = ConvertFrom-DateTimeString $seg.Start
            $effEnd = $End
            if ($effEnd -lt $start) { $effEnd = $start }
            $seg['End'] = ConvertTo-DateTimeString $effEnd
            $seg['Running'] = $false
            return $seg
        }
    }
    return $null
}

# Moduswechsel: bisherigen Abschnitt beenden, neuen beginnen.
# Die Luecke zwischen $EndTime und $StartTime ist bewusst keine Arbeitszeit.
# Transaktional: bei fehlgeschlagenem Speichervorgang wird der vorherige
# Tageszustand vollstaendig wiederhergestellt und $null geliefert.
function Switch-WorkMode {
    param(
        [Parameter(Mandatory)]$Day,
        [Parameter(Mandatory)][string]$NewMode,
        [Parameter(Mandatory)][datetime]$EndTime,
        [Parameter(Mandatory)][datetime]$StartTime
    )
    $snapshot = Get-DaySnapshot -Day $Day
    $oldSeg = Stop-RunningSegment -Day $Day -End $EndTime
    $oldMode = '-'
    if ($oldSeg) { $oldMode = $oldSeg.Mode }

    # Beim Verlassen des Homeoffice eine noch laufende manuelle Pause sauber
    # beenden (ohne eigenen Speichervorgang - es wird unten genau einmal gespeichert)
    if ($oldMode -eq 'Homeoffice' -and $NewMode -ne 'Homeoffice') {
        Stop-ManualPauseInterval -Day $Day -End $EndTime -Silent -NoSave | Out-Null
    }

    $newSeg = New-SegmentObject -Mode $NewMode -Start $StartTime -Running $true
    [void]$Day['Segments'].Add($newSeg)
    Update-DayTotals -Day $Day | Out-Null
    if (-not (Save-WorkData)) {
        Restore-DayFromSnapshot -Day $Day -Snapshot $snapshot
        Write-AppLog -Level 'WARN' -Message 'Moduswechsel NICHT gespeichert - Änderung vollständig zurückgenommen.'
        return $null
    }
    Write-AppLog -Message "Moduswechsel: $oldMode -> $NewMode (Ende $(Format-Clock $EndTime), Beginn $(Format-Clock $StartTime))"
    return $newSeg
}

# Benutzergesteuerte Aktion: bei fehlgeschlagenem Speichervorgang wird die
# neue Pause vollstaendig zurueckgenommen ($null = nicht durchgefuehrt).
function Start-ManualPauseInterval {
    param([Parameter(Mandatory)]$Day, [datetime]$Start = (Get-Date))
    foreach ($iv in @($Day.ManualPauses)) {
        if ($null -eq $iv.End) { return $iv }  # bereits eine offene Pause
    }
    $snapshot = Get-DaySnapshot -Day $Day
    $pause = New-IntervalObject -Start $Start
    [void]$Day['ManualPauses'].Add($pause)
    Update-DayTotals -Day $Day | Out-Null
    if (-not (Save-WorkData)) {
        Restore-DayFromSnapshot -Day $Day -Snapshot $snapshot
        Write-AppLog -Level 'WARN' -Message 'Manuelle Pause NICHT gespeichert - Änderung zurückgenommen.'
        return $null
    }
    Write-AppLog -Message "Manuelle Pause gestartet: $(Format-Clock $Start)"
    return $pause
}

# Benutzergesteuerte Aktion (ohne -NoSave): bei fehlgeschlagenem
# Speichervorgang wird das Pausenende zurueckgenommen ($false).
function Stop-ManualPauseInterval {
    param([Parameter(Mandatory)]$Day, [datetime]$End = (Get-Date), [switch]$Silent, [switch]$NoSave)
    $snapshot = $null
    if (-not $NoSave) { $snapshot = Get-DaySnapshot -Day $Day }
    $found = $false
    foreach ($iv in @($Day.ManualPauses)) {
        if ($null -eq $iv.End) {
            $start = ConvertFrom-DateTimeString $iv.Start
            $effEnd = $End
            if ($effEnd -lt $start) { $effEnd = $start }
            $iv['End'] = ConvertTo-DateTimeString $effEnd
            $found = $true
        }
    }
    if ($found) {
        if (-not $NoSave) {
            Update-DayTotals -Day $Day | Out-Null
            if (-not (Save-WorkData)) {
                Restore-DayFromSnapshot -Day $Day -Snapshot $snapshot
                Write-AppLog -Level 'WARN' -Message 'Pausenende NICHT gespeichert - Änderung zurückgenommen.'
                return $false
            }
        }
        if (-not $Silent) { Write-AppLog -Message "Manuelle Pause beendet: $(Format-Clock $End)" }
    }
    return $found
}

# Automatisches Windows-Ereignis: KEIN Rollback (der Ereigniszustand bleibt
# fachlich korrekt im Arbeitsspeicher); Speichern still, die begrenzte
# Wiederholungslogik des Haupt-Timers holt einen Fehlversuch nach.
function Start-LockInterval {
    param([Parameter(Mandatory)]$Day, [datetime]$Start = (Get-Date))
    foreach ($iv in @($Day.LockIntervals)) {
        if ($null -eq $iv.End) { return $iv }
    }
    $lock = New-IntervalObject -Start $Start
    [void]$Day['LockIntervals'].Add($lock)
    Update-DayTotals -Day $Day | Out-Null
    Save-WorkData -Quiet | Out-Null
    Write-AppLog -Message "Windows gesperrt: $(Format-Clock $Start)"
    return $lock
}

# Automatisches Windows-Ereignis: KEIN Rollback, stilles Speichern (siehe oben).
function Stop-LockInterval {
    param([Parameter(Mandatory)]$Day, [datetime]$End = (Get-Date), [switch]$NoSave, [switch]$Silent)
    $found = $false
    foreach ($iv in @($Day.LockIntervals)) {
        if ($null -eq $iv.End) {
            $start = ConvertFrom-DateTimeString $iv.Start
            $effEnd = $End
            if ($effEnd -lt $start) { $effEnd = $start }
            $iv['End'] = ConvertTo-DateTimeString $effEnd
            $found = $true
        }
    }
    if ($found) {
        if (-not $NoSave) {
            Update-DayTotals -Day $Day | Out-Null
            Save-WorkData -Quiet | Out-Null
        }
        if (-not $Silent) { Write-AppLog -Message "Windows entsperrt: $(Format-Clock $End)" }
    }
    return $found
}

# --- Snapshot-/Validierungs-Helfer fuer manuelle Korrekturen ---

# Tiefer Schnappschuss eines Tagesobjekts (JSON-Roundtrip)
function Get-DaySnapshot {
    param([Parameter(Mandatory)]$Day)
    return ($Day | ConvertTo-Json -Depth 20)
}

# Stellt ein Tagesobjekt in-place aus einem Schnappschuss wieder her
function Restore-DayFromSnapshot {
    param([Parameter(Mandatory)]$Day, [Parameter(Mandatory)][string]$Snapshot)
    $restored = ConvertTo-PlainObject ($Snapshot | ConvertFrom-Json)
    $keys = @($Day.Keys)
    foreach ($key in $keys) { $Day.Remove($key) }
    foreach ($key in $restored.Keys) { $Day[$key] = $restored[$key] }
}

# Merkt sich den aktuellen Stand des verschluesselten Protokolls (bzw. des
# Startpuffers vor dem Entsperren), damit ein fachlicher Transaktions-
# Rollback auch die waehrend der Transaktion erzeugten Logeintraege
# vollstaendig zuruecknehmen kann: Nach einem Rollback darf kein Eintrag
# bestehen bleiben, der eine nicht dauerhaft uebernommene Aenderung als
# erfolgreich darstellt.
function Get-LogMark {
    if ($script:App -and $script:App.Vault -and $script:App.Vault.Contains('Logs')) {
        return @{ Target = 'Vault'; Count = @($script:App.Vault['Logs']).Count }
    }
    return @{ Target = 'Buffer'; Count = @($script:StartupLogBuffer).Count }
}

# Entfernt alle seit der Markierung hinzugekommenen Logeintraege (nur die
# eigene Zielliste; eine zwischenzeitliche Logrotation macht die Ruecknahme
# hoechstens unvollstaendig, niemals falsch - es wird nie unter die
# Markierung hinaus geloescht).
function Restore-LogMark {
    param([Parameter(Mandatory)]$Mark)
    try {
        $list = $null
        if ($Mark.Target -eq 'Vault') {
            if ($script:App -and $script:App.Vault -and $script:App.Vault.Contains('Logs')) { $list = $script:App.Vault['Logs'] }
        }
        else { $list = $script:StartupLogBuffer }
        if ($null -eq $list) { return }
        while ($list.Count -gt [int]$Mark.Count) { $list.RemoveAt($list.Count - 1) }
    }
    catch { }
}

# Bezugszeitpunkt fuer Netto-Pruefungen: laufender Tag = jetzt, beendeter Tag = EndedAt
function Get-DayReferenceTime {
    param([Parameter(Mandatory)]$Day, [datetime]$Now = (Get-Date))
    if ($Day.Status -eq 'Beendet' -and $Day.EndedAt) {
        $ended = ConvertFrom-DateTimeString $Day.EndedAt
        if ($ended) { return $ended }
    }
    return $Now
}

# Prueft, ob die Netto-Arbeitszeit des Tages die 10-Stunden-Grenze einhaelt
function Test-DayUnderMax {
    param([Parameter(Mandatory)]$Day, [datetime]$Now = (Get-Date))
    $ref = Get-DayReferenceTime -Day $Day -Now $Now
    $comp = Get-DayComputation -Day $Day -Now $ref
    return ($comp.Netto.TotalMinutes -le ($script:Const.MaxMinutes + 0.02))
}

# Setzt MaxReached nach Korrekturen konsistent (auch Ruecknahme unter 10:00)
function Update-MaxReachedState {
    param([Parameter(Mandatory)]$Day, [datetime]$Now = (Get-Date))
    $ref = Get-DayReferenceTime -Day $Day -Now $Now
    $comp = Get-DayComputation -Day $Day -Now $ref
    $atMax = ($comp.Netto.TotalMinutes -ge ($script:Const.MaxMinutes - 0.02))
    if ([bool]$Day.MaxReached -and -not $atMax) {
        $Day['MaxReached'] = $false
        if ($script:App -and $script:App.Flags) { $script:App.Flags.MaxHandled = $false }
        Write-AppLog -Message "MaxReached fuer $($Day.Date) nach Korrektur zurueckgenommen (Netto unter 10:00)."
    }
    elseif (-not [bool]$Day.MaxReached -and $atMax -and $Day.Status -eq 'Aktiv') {
        # Erneutes Erreichen wird ueber den regulaeren Auto-Stopp behandelt
        Invoke-AutoStopIfNeeded -Day $Day -Now $Now | Out-Null
    }
}

# Validiert eine Abschlusszeit vollstaendig. Liefert '' oder eine Fehlermeldung.
# Es erfolgt keine stille Korrektur: ungueltige Eingaben werden abgelehnt.
#
# -TrimTrailingIntervals: Pausen-/Sperrintervalle werden NICHT geprueft, weil
# der Aufrufer sie beim Abschluss ueber Close-DayPartsAt exakt am Arbeitsende
# kappt bzw. erst danach beginnende Intervalle verwirft (z. B. Laptop
# zugeklappt, spaeter entsperrt, Arbeitsende rueckwirkend gesetzt). Die
# Pruefungen fuer Abschnitte, Zukunft und 10:00 bleiben unveraendert; die
# Nettozeit ist davon unabhaengig, da Intervalle nur innerhalb der
# (am Arbeitsende endenden) Abschnitte abgezogen werden.
function Test-DayEndTime {
    param(
        [Parameter(Mandatory)]$Day,
        [Parameter(Mandatory)][datetime]$End,
        [datetime]$Now = (Get-Date),
        [switch]$TrimTrailingIntervals
    )
    if ($End -gt $Now.AddMinutes(1)) {
        return "Das Arbeitsende $(Format-Clock $End) liegt in der Zukunft."
    }
    foreach ($seg in @($Day.Segments)) {
        if ($null -eq $seg) { continue }
        $s = ConvertFrom-DateTimeString $seg.Start
        if ($seg.Running) {
            if ($null -ne $s -and $End -lt $s) {
                return "Das Arbeitsende darf nicht vor dem Beginn des laufenden Abschnitts ($(Format-Clock $s)) liegen."
            }
        }
        elseif ($seg.End) {
            $e = ConvertFrom-DateTimeString $seg.End
            if ($null -ne $e -and $End -lt $e) {
                return "Das Arbeitsende darf nicht vor dem Ende eines bereits abgeschlossenen Abschnitts ($(Format-Clock $e)) liegen."
            }
        }
    }
    foreach ($listName in @('ManualPauses', 'LockIntervals')) {
        if ($TrimTrailingIntervals) { break }
        foreach ($iv in @($Day[$listName])) {
            if ($null -eq $iv) { continue }
            if ($iv.End) {
                $e = ConvertFrom-DateTimeString $iv.End
                if ($null -ne $e -and $End -lt $e) {
                    return "Das Arbeitsende darf nicht vor dem Ende eines vorhandenen Pausen- oder Sperrintervalls ($(Format-Clock $e)) liegen."
                }
            }
            else {
                $s = ConvertFrom-DateTimeString $iv.Start
                if ($null -ne $s -and $End -lt $s) {
                    return "Das Arbeitsende darf nicht vor dem Beginn eines offenen Pausen- oder Sperrintervalls ($(Format-Clock $s)) liegen."
                }
            }
        }
    }
    # Nettozeit zum Abschlusszeitpunkt darf 10:00 nicht ueberschreiten
    $comp = Get-DayComputation -Day $Day -Now $End
    if ($comp.Netto.TotalMinutes -gt ($script:Const.MaxMinutes + 0.02)) {
        return 'Mit diesem Arbeitsende würde die Netto-Arbeitszeit 10:00 Stunden überschreiten. Die Änderung wird abgelehnt.'
    }
    return ''
}

# Schliesst den Arbeitstag ab: alle offenen Intervalle beenden, Status setzen.
# EndedAt entspricht exakt der validierten und tatsaechlich verwendeten Endzeit.
function Complete-WorkDay {
    param(
        [Parameter(Mandatory)]$Day,
        [Parameter(Mandatory)][datetime]$End,
        [string]$Reason = 'Manuell',
        [bool]$AutoEnded = $false,
        [switch]$SkipValidation,  # nur fuer den automatischen Tageswechsel um 00:00
        [switch]$Quiet,           # automatische Ablaeufe: kein Fehlerdialog beim Speichern
        # Manuelles "Arbeitstag beenden" (Dialog): ueber das Arbeitsende
        # hinausreichende Pausen-/Sperrintervalle am Ende kappen bzw. erst
        # danach beginnende verwerfen (Close-DayPartsAt) statt abzulehnen.
        [switch]$TrimTrailingIntervals
    )
    if (-not $SkipValidation) {
        $endError = Test-DayEndTime -Day $Day -End $End -TrimTrailingIntervals:$TrimTrailingIntervals
        if ($endError -ne '') {
            Show-Warning -Message $endError
            return $false
        }
    }
    # Gesamte fachliche Aenderung im Speicher durchfuehren und genau EINMAL
    # speichern; bei einem Speicherfehler wird der Tag vollstaendig aus dem
    # Snapshot zurueckgerollt (kein ungewollter Zwischenstand im Tresor).
    $snapshot = Get-DaySnapshot -Day $Day
    $trimmed = $false
    $trimOld = New-Object System.Collections.ArrayList
    $trimNew = New-Object System.Collections.ArrayList
    if ($TrimTrailingIntervals) {
        # Nur nachlaufende Intervalle (Ende nach bzw. Beginn ab $End) werden
        # als Korrektur vermerkt - mit Original- und neuem Wert, damit der
        # Nachweis nachvollziehbar bleibt; das normale Schliessen offener
        # Intervalle am Arbeitsende ist keine Korrektur.
        foreach ($listName in @('ManualPauses', 'LockIntervals')) {
            $label = 'Pause'
            if ($listName -eq 'LockIntervals') { $label = 'Sperre' }
            foreach ($iv in @($Day[$listName])) {
                if ($null -eq $iv) { continue }
                $s = $null; $e = $null
                try { $s = ConvertFrom-DateTimeString $iv.Start } catch { }
                if ($iv.End) { try { $e = ConvertFrom-DateTimeString $iv.End } catch { } }
                if ($null -eq $s) { continue }
                if (-not ($s -ge $End -or ($null -ne $e -and $e -gt $End))) { continue }
                $trimmed = $true
                $origText = '{0} ab {1} (offen)' -f $label, (Format-Clock $s)
                if ($null -ne $e) { $origText = '{0} {1}-{2}' -f $label, (Format-Clock $s), (Format-Clock $e) }
                [void]$trimOld.Add($origText)
                if ($s -ge $End) { [void]$trimNew.Add($origText + ' verworfen') }
                else { [void]$trimNew.Add(('{0} {1}-{2}' -f $label, (Format-Clock $s), (Format-Clock $End))) }
            }
        }
        $trimOldText = ($trimOld -join '; ')
        $trimNewText = ((@($trimNew) + @('Arbeitsende ' + (Format-Clock $End))) -join '; ')
        $closeError = Close-DayPartsAt -Day $Day -End $End
        if ($closeError -ne '') {
            Restore-DayFromSnapshot -Day $Day -Snapshot $snapshot
            Show-Warning -Message $closeError
            return $false
        }
        if ($trimmed) {
            Add-Correction -Day $Day -Description 'Nachlaufende Pausen-/Sperrintervalle am Arbeitsende gekappt' -OldValue $trimOldText -NewValue $trimNewText -NoLog
        }
    }
    Stop-RunningSegment -Day $Day -End $End | Out-Null
    Stop-ManualPauseInterval -Day $Day -End $End -Silent -NoSave | Out-Null
    Stop-LockInterval -Day $Day -End $End -NoSave -Silent | Out-Null
    $Day['Status'] = 'Beendet'
    $Day['EndedAt'] = ConvertTo-DateTimeString $End
    $Day['EndReason'] = $Reason
    $Day['AutoEnded'] = $AutoEnded
    # Review-Status (rueckwaerts kompatibel): NEU automatisch beendete Tage
    # sind ausdruecklich pruefbeduerftig; manuell beendete Tage gelten als
    # geprueft. Alte Tage ohne diese Felder bleiben weiterhin ladbar.
    if ($AutoEnded) {
        $Day['AutoEndReviewPending'] = $true
        $Day['AutoEndReviewed'] = $false
    }
    else {
        $Day['AutoEndReviewPending'] = $false
        $Day['AutoEndReviewed'] = $true
    }
    Update-MaxReachedState -Day $Day -Now $End
    Update-DayTotals -Day $Day -Now $End | Out-Null
    # Nur wenn ein aktiver Tresor existiert, wird tatsaechlich gespeichert
    # (reine Berechnungs-/Testkontexte arbeiten ohne Tresor im Speicher).
    if ($script:App -and $script:App.Vault) {
        if (-not (Save-Vault -Quiet:$Quiet)) {
            Restore-DayFromSnapshot -Day $Day -Snapshot $snapshot
            Write-AppLog -Level 'WARN' -Message "Tagesabschluss ($($Day.Date)) NICHT gespeichert - Änderung zurückgenommen."
            return $false
        }
    }
    if ($trimmed) {
        Write-CorrectionLog -Day $Day -Description 'Nachlaufende Pausen-/Sperrintervalle am Arbeitsende gekappt' -OldValue $trimOldText -NewValue $trimNewText
    }
    Write-AppLog -Message "Tagesabschluss ($($Day.Date)): Grund '$Reason', Ende $(Format-Clock $End)"
    return $true
}

# Automatischer Stopp bei Erreichen der maximalen Arbeitszeit.
# Der Tag bleibt offen ('Aktiv'), aber es laeuft kein Abschnitt mehr.
function Invoke-AutoStopIfNeeded {
    param([Parameter(Mandatory)]$Day, [datetime]$Now = (Get-Date))
    if ($Day.MaxReached -or $Day.Status -ne 'Aktiv') { return $false }
    # Exakten Zeitpunkt des Erreichens ZENTRAL bestimmen: Pausen, Sperr-
    # intervalle und feste Betriebspause werden vollstaendig beruecksichtigt.
    # Korrekt auch nach groesseren Zeitspruengen (Standby, blockierter Timer,
    # Zeitaenderung) - keine vereinfachte Ueberschussformel mehr.
    $stopTime = Find-DayMaxNettoReachedTime -Day $Day -Cutoff $Now
    if ($null -eq $stopTime) { return $false }
    # Gesamte Aenderung im Speicher, danach genau EIN Speichervorgang
    Stop-RunningSegment -Day $Day -End $stopTime | Out-Null
    Stop-ManualPauseInterval -Day $Day -End $stopTime -Silent -NoSave | Out-Null
    $Day['MaxReached'] = $true
    Update-DayTotals -Day $Day -Now $Now | Out-Null
    # Automatisches Ereignis: Ereigniszustand bleibt im Speicher erhalten;
    # ein Fehlversuch wird ueber die Wiederholungslogik nachgeholt.
    Save-WorkData | Out-Null
    Write-AppLog -Level 'WARN' -Message "Maximale Arbeitszeit (10:00) erreicht um $(Format-Clock $stopTime) - Erfassung gestoppt."
    return $true
}

# Tageswechsel: laufenden Tag um 00:00 beenden, keinen neuen Tag starten.
# Wurde die 10-Stunden-Grenze vor Mitternacht erreicht, stoppt der Abschnitt
# rueckwirkend am korrekten Zeitpunkt (kein Netto ueber 10:00).
function Invoke-MidnightRolloverIfNeeded {
    param([Parameter(Mandatory)]$Day, [datetime]$Now = (Get-Date))
    if ($Day.Status -ne 'Aktiv') { return $false }
    $dayDate = [datetime]::ParseExact($Day.Date, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    if ($Now.Date -le $dayDate.Date) { return $false }
    # Nach einem fehlgeschlagenen Speichervorgang wird der naechste
    # automatische Versuch gedrosselt (kein Fehler- oder Konfliktkopienspam
    # im Sekundentakt des Haupt-Timers).
    if ($script:App -and $script:App.Flags -and $script:App.Flags.RolloverNextRetryAt) {
        if ((Get-Date) -lt $script:App.Flags.RolloverNextRetryAt) { return $false }
    }
    $midnight = $dayDate.Date.AddDays(1)
    Invoke-AutoStopIfNeeded -Day $Day -Now $midnight | Out-Null
    # Speicherergebnis ZWINGEND auswerten: Complete-WorkDay rollt den Tag bei
    # fehlgeschlagenem Save-Vault bereits vollstaendig aus dem Snapshot
    # zurueck. Dann gibt es KEINE Erfolgsmeldung und KEIN Erfolgslog -
    # nur eine einmalige neutrale WARN-Meldung; der Tag bleibt aktiv und es
    # wird kein neuer Arbeitstag gestartet.
    $completed = Complete-WorkDay -Day $Day -End $midnight -Reason 'Tageswechsel' -AutoEnded $true -SkipValidation -Quiet
    if (-not $completed) {
        if ($script:App -and $script:App.Flags) {
            if (-not $script:App.Flags.RolloverWarnLogged) {
                $script:App.Flags.RolloverWarnLogged = $true
                Write-AppLog -Level 'WARN' -Message "Automatischer Tagesabschluss (Tageswechsel) für $($Day.Date) konnte nicht gespeichert werden - der bisherige Zustand bleibt erhalten, ein neuer Versuch folgt automatisch."
            }
            $script:App.Flags.RolloverNextRetryAt = (Get-Date).AddSeconds(60)
        }
        else {
            Write-AppLog -Level 'WARN' -Message "Automatischer Tagesabschluss (Tageswechsel) für $($Day.Date) konnte nicht gespeichert werden - der bisherige Zustand bleibt erhalten."
        }
        return $false
    }
    if ($script:App -and $script:App.Flags) {
        $script:App.Flags.RolloverWarnLogged = $false
        $script:App.Flags.RolloverNextRetryAt = $null
    }
    Write-AppLog -Message "Automatischer Tagesabschluss um 00:00 (Tageswechsel) fuer $($Day.Date) - Bestätigung durch den Benutzer steht aus."
    return $true
}

# --- Review-Logik fuer offene bzw. automatisch beendete Vortage --------------

# Fall A der Startlogik: aktiver Arbeitstag, dessen Datum vor dem heutigen
# Datum liegt. Reine, testbare Funktion.
function Test-DayNeedsPreviousDayReview {
    param([Parameter(Mandatory)]$Day, [datetime]$Now = (Get-Date))
    if ([string]$Day.Status -ne 'Aktiv') { return $false }
    $dayDate = $null
    try { $dayDate = [datetime]::ParseExact([string]$Day.Date, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) }
    catch { return $false }
    return ($dayDate.Date -lt $Now.Date)
}

# Ermittelt den EINEN pruefbeduerftigen automatisch beendeten Tag (Fall B).
# Migrationsverhalten fuer Bestandsdaten:
#  - Tage mit AutoEndReviewPending=true (neue Logik) sind pruefbeduerftig,
#    aber nur, solange sie der zeitlich letzte gespeicherte Arbeitstag sind.
#  - OHNE Review-Felder gilt nur der juengste AutoEnded-Tag als pruefbeduerftig,
#    wenn er der letzte gespeicherte Tag ist UND sein Datum unmittelbar vor dem
#    aktuellen Startzeitpunkt liegt (Vortag). Alle aelteren historischen
#    AutoEnded-Tage ohne Review-Felder gelten als bereits geprueft - es
#    entsteht keine nachtraegliche Abfragekette.
function Get-AutoEndReviewCandidate {
    param($Days = $null, [datetime]$Now = (Get-Date))
    if ($null -eq $Days) {
        if ($null -eq $script:App -or $null -eq $script:App.Data) { return $null }
        $Days = $script:App.Data.Days
    }
    $sorted = @(@($Days) | Where-Object { $null -ne $_ } | Sort-Object -Property @{ Expression = { $_.Date } } -Descending)
    if ($sorted.Count -eq 0) { return $null }
    $newest = $sorted[0]
    if ([string]$newest.Status -ne 'Beendet') { return $null }
    if ($newest.Contains('AutoEndReviewPending')) {
        if ([bool]$newest['AutoEndReviewPending']) { return $newest }
        return $null
    }
    if ([bool]$newest['AutoEnded'] -and -not $newest.Contains('AutoEndReviewed') -and
        [string]$newest.Date -eq $Now.Date.AddDays(-1).ToString('yyyy-MM-dd')) {
        return $newest
    }
    return $null
}

# Reine, nebenwirkungsfreie Nettozeit eines Tages BIS zu einem Zeitpunkt:
# saemtliche Segmente werden am Zeitpunkt gekappt (auch bereits mit spaeterem
# Ende gespeicherte), laufende Segmente und offene Pausen-/Sperrintervalle
# laufen rechnerisch bis zum Zeitpunkt. Identische Rechenregeln wie
# Get-DayComputation (feste Betriebspause, vereinigte Nichtarbeitszeiten) -
# veraendert nichts, speichert nichts, protokolliert nichts.
function Get-DayNettoAtTime {
    param(
        [Parameter(Mandatory)]$Day,
        [Parameter(Mandatory)][datetime]$Time
    )
    $segs = Get-ParsedSegments -Day $Day -Now $Time
    $betriebBrutto = [TimeSpan]::Zero
    $hoSegs = New-Object System.Collections.ArrayList
    foreach ($seg in @($segs)) {
        $s = $seg.Start
        $e = $seg.End
        if ($e -gt $Time) { $e = $Time }
        if ($s -ge $e) { continue }
        if ($seg.Mode -eq 'Betrieb') { $betriebBrutto += ($e - $s) }
        else { [void]$hoSegs.Add(@{ Start = $s; End = $e }) }
    }
    $sixHours = [TimeSpan]::FromMinutes($script:Const.BetriebPauseNachMinuten)
    $maxPause = [TimeSpan]::FromMinutes($script:Const.BetriebPauseMinutes)
    $festeAbzug = $betriebBrutto - $sixHours
    if ($festeAbzug -lt [TimeSpan]::Zero) { $festeAbzug = [TimeSpan]::Zero }
    if ($festeAbzug -gt $maxPause) { $festeAbzug = $maxPause }
    $netto = $betriebBrutto - $festeAbzug
    $allNonWork = New-Object System.Collections.ArrayList
    foreach ($iv in @($Day.LockIntervals)) { [void]$allNonWork.Add($iv) }
    foreach ($iv in @($Day.ManualPauses)) { [void]$allNonWork.Add($iv) }
    $nonWorkMerged = Merge-TimeIntervals -Intervals $allNonWork -Now $Time
    foreach ($seg in @($hoSegs)) {
        $netto += ($seg.End - $seg.Start) - (Get-OverlapDuration -Start $seg.Start -End $seg.End -MergedIntervals $nonWorkMerged)
    }
    return $netto
}

# ZENTRALE, nebenwirkungsfreie Suche nach dem FRUEHESTEN Zeitpunkt, an dem
# die Netto-Arbeitszeit die maximale Arbeitszeit (Day.MaxMinutes) erreicht -
# sekundengenau per monotoner Binaersuche ueber Get-DayNettoAtTime. Pausen,
# Sperrintervalle, feste Betriebspause, mehrere Segmente/Moduswechsel und
# offene Intervalle werden vollstaendig beruecksichtigt. Liefert $null, wenn
# die Grenze bis $Cutoff nicht erreicht wurde. Ersetzt die fruehere
# vereinfachte Ueberschussformel, die bei Pausen/Sperrzeiten NACH dem
# tatsaechlichen Grenzzeitpunkt einen zu spaeten Zeitpunkt liefern konnte.
function Find-DayMaxNettoReachedTime {
    param(
        [Parameter(Mandatory)]$Day,
        [Parameter(Mandatory)][datetime]$Cutoff
    )
    $maxTs = [TimeSpan]::FromMinutes([int]$Day.MaxMinutes)
    # Toleranz ausschliesslich fuer Rundungsungenauigkeiten der
    # Sekundennormalisierung - keine fachliche Aufweichung der Grenze.
    $tol = [TimeSpan]::FromMilliseconds(20)
    if ((Get-DayNettoAtTime -Day $Day -Time $Cutoff) -lt $maxTs) { return $null }
    $lo = $null
    foreach ($seg in @(Get-ParsedSegments -Day $Day -Now $Cutoff)) {
        if ($null -eq $lo -or $seg.Start -lt $lo) { $lo = $seg.Start }
    }
    if ($null -eq $lo) { return $null }
    if ($lo -ge $Cutoff) { return $Cutoff }
    if ((Get-DayNettoAtTime -Day $Day -Time $lo) -ge $maxTs) { return $lo }
    # Monotone Binaersuche: die Nettozeit waechst mit dem Zeitpunkt niemals
    # rueckwaerts (Pausen-/Sperrzeitraeume halten sie hoechstens konstant).
    $loS = [long]0
    $hiS = [long][math]::Ceiling(($Cutoff - $lo).TotalSeconds)
    while (($hiS - $loS) -gt 1) {
        $midS = [long][math]::Floor(($loS + $hiS) / 2)
        if ((Get-DayNettoAtTime -Day $Day -Time ($lo.AddSeconds($midS))) -ge $maxTs) { $hiS = $midS }
        else { $loS = $midS }
    }
    $result = $lo.AddSeconds($hiS)
    if ($result -gt $Cutoff) { $result = $Cutoff }
    # Auf ganze Sekunden normalisieren; reicht die abgeschnittene Sekunde
    # rechnerisch nicht aus, gilt die naechste volle Sekunde.
    $trunc = $result.AddTicks(-($result.Ticks % [TimeSpan]::TicksPerSecond))
    if ((Get-DayNettoAtTime -Day $Day -Time $trunc) -ge ($maxTs - $tol)) { $result = $trunc }
    else { $result = $trunc.AddSeconds(1) }
    # Verifikation: am Ergebnis muss die Maximalzeit erreicht sein; defensiv
    # hoechstens sekundenweise bis $Cutoff nachruecken (Rundungsgrenzen).
    while ((Get-DayNettoAtTime -Day $Day -Time $result) -lt ($maxTs - $tol) -and $result -lt $Cutoff) {
        $result = $result.AddSeconds(1)
    }
    return $result
}

# Zeitpunkt, an dem die Netto-Arbeitszeit exakt 10:00 erreicht hat (bezogen
# auf $Cutoff). $null, wenn die Grenze bis $Cutoff nicht erreicht wurde.
# Verwendet AUSSCHLIESSLICH die zentrale exakte Zeitpunktsuche
# (Find-DayMaxNettoReachedTime) - keine vereinfachte Ueberschussformel.
function Get-DayTenHourStopTime {
    param([Parameter(Mandatory)]$Day, [Parameter(Mandatory)][datetime]$Cutoff)
    return (Find-DayMaxNettoReachedTime -Day $Day -Cutoff $Cutoff)
}

# Schliesst saemtliche laufenden/ueberlangen Bestandteile eines Tages exakt
# am uebergebenen Endzeitpunkt: laufendes Segment beenden, ueberlange
# Segmente kuerzen, offene Pausen-/Sperrintervalle schliessen, spaeter
# beginnende Intervalle entfernen. Liefert '' oder eine Fehlermeldung
# (Aufrufer arbeitet mit Snapshot und nimmt bei Fehlern alles zurueck).
function Close-DayPartsAt {
    param([Parameter(Mandatory)]$Day, [Parameter(Mandatory)][datetime]$End)
    Stop-RunningSegment -Day $Day -End $End | Out-Null
    foreach ($seg in @($Day.Segments)) {
        if ($null -eq $seg) { continue }
        $s = $null
        try { $s = ConvertFrom-DateTimeString $seg.Start } catch { }
        if ($null -eq $s) { continue }
        if ($s -ge $End) {
            return "Es existiert ein Arbeitsabschnitt, der erst nach dem gewählten Ende ($(Format-Clock $End)) beginnt. Bitte 'Tag bearbeiten' verwenden."
        }
        if ($seg.End) {
            $e = $null
            try { $e = ConvertFrom-DateTimeString $seg.End } catch { }
            if ($null -ne $e -and $e -gt $End) {
                $seg['End'] = ConvertTo-DateTimeString $End
                $seg['Corrected'] = $true
            }
        }
    }
    foreach ($listName in @('ManualPauses', 'LockIntervals')) {
        $toRemove = New-Object System.Collections.ArrayList
        foreach ($iv in @($Day[$listName])) {
            if ($null -eq $iv) { continue }
            $s = $null
            try { $s = ConvertFrom-DateTimeString $iv.Start } catch { }
            if ($null -eq $s -or $s -ge $End) { [void]$toRemove.Add($iv); continue }
            if ($null -eq $iv.End) {
                $iv['End'] = ConvertTo-DateTimeString $End
            }
            else {
                $e = $null
                try { $e = ConvertFrom-DateTimeString $iv.End } catch { }
                if ($null -ne $e -and $e -gt $End) { $iv['End'] = ConvertTo-DateTimeString $End }
            }
        }
        foreach ($iv in @($toRemove)) { [void]$Day[$listName].Remove($iv) }
    }
    return ''
}

# Vorschlag fuer das tatsaechliche Ende eines nicht ordnungsgemaess oder
# automatisch (Tageswechsel um 00:00) beendeten Tages. Statt Mitternacht wird
# der letzte belegbare Arbeitszeitpunkt vorgeschlagen:
#  1. spaetestes Abschnittsende (laufende Abschnitte bis $Cutoff, hoechstens
#     bis zum gespeicherten EndedAt)
#  2. frueher, falls die 10-Stunden-Grenze vorher erreicht wurde
#  3. reicht eine Sperre oder Pause bis an diesen Zeitpunkt heran (z. B. PC
#     gesperrt und bis Mitternacht weitergelaufen), deren Beginn - direkt
#     aneinander anschliessende Intervalle werden dabei verkettet
# Nie vor dem Arbeitsbeginn. Reine, nebenwirkungsfreie Funktion.
function Get-AutoEndSuggestedEnd {
    param([Parameter(Mandatory)]$Day, [Parameter(Mandatory)][datetime]$Cutoff)
    $limit = $Cutoff
    if ($Day.EndedAt) {
        $ended = $null
        try { $ended = ConvertFrom-DateTimeString $Day.EndedAt } catch { }
        if ($null -ne $ended -and $ended -lt $limit) { $limit = $ended }
    }
    $beginn = $null
    $workEnd = $null
    foreach ($seg in @(Get-ParsedSegments -Day $Day -Now $limit)) {
        if ($null -eq $beginn -or $seg.Start -lt $beginn) { $beginn = $seg.Start }
        $e = $seg.End
        if ($e -gt $limit) { $e = $limit }
        if ($null -eq $workEnd -or $e -gt $workEnd) { $workEnd = $e }
    }
    if ($null -eq $workEnd) { return $limit }
    $tenAt = Get-DayTenHourStopTime -Day $Day -Cutoff $workEnd
    if ($null -ne $tenAt -and $tenAt -lt $workEnd) { $workEnd = $tenAt }
    $intervals = New-Object System.Collections.ArrayList
    foreach ($listName in @('ManualPauses', 'LockIntervals')) {
        foreach ($iv in @($Day[$listName])) {
            if ($null -eq $iv) { continue }
            $s = $null
            try { $s = ConvertFrom-DateTimeString $iv.Start } catch { }
            if ($null -eq $s) { continue }
            $e = $limit
            if ($iv.End) { try { $e = ConvertFrom-DateTimeString $iv.End } catch { $e = $limit } }
            if ($null -eq $e) { $e = $limit }
            [void]$intervals.Add(@{ Start = $s; End = $e })
        }
    }
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($iv in @($intervals)) {
            if ($iv.Start -lt $workEnd -and $iv.End -ge $workEnd -and $iv.Start -ge $beginn) {
                $workEnd = $iv.Start
                $changed = $true
            }
        }
    }
    return $workEnd
}

# Bestaetigung der 10-Stunden-Wertung eines nicht ordnungsgemaess beendeten
# Tages: Das Ende wird exakt auf den Zeitpunkt gesetzt, an dem die
# Netto-Arbeitszeit 10:00 erreicht hat (manuelle Pausen, Sperrintervalle und
# die automatische Betriebspause sind in der Berechnung enthalten). Wurde die
# Grenze nie erreicht, wird das bisher angenommene Ende bestaetigt: der im
# Dialog angezeigte Vorschlag (-AssumedEnd, siehe Get-AutoEndSuggestedEnd),
# ohne Vorschlag Mitternacht bzw. das gespeicherte Ende. Liefert '' oder eine Fehlermeldung; die
# Aenderung wird genau EINMAL gespeichert und bei Fehlern vollstaendig
# zurueckgenommen (einschliesslich Review-Status).
function Complete-AutoEndTenHours {
    param([Parameter(Mandatory)]$Day, [datetime]$Now = (Get-Date), $AssumedEnd = $null)
    $dayDate = [datetime]::ParseExact([string]$Day.Date, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    $cutoff = $dayDate.Date.AddDays(1)
    if ($cutoff -gt $Now) { $cutoff = $Now }
    $snapshot = Get-DaySnapshot -Day $Day
    $logMark = Get-LogMark
    # Offene Sperrintervalle werden NICHT am alten Checkpoint beendet, sondern
    # unten von Close-DayPartsAt exakt am bestaetigten Endzeitpunkt geschlossen
    # (der Zeitraum bis zum bestaetigten Ende zaehlt damit als Sperrzeit und
    # niemals faelschlich als Arbeitszeit). Fuer die 10h-Zeitpunktberechnung
    # bleibt die 1:1-Annahme gueltig: Unter einem offenen Sperrintervall
    # waechst die Homeoffice-Nettozeit nicht weiter, die Grenze kann dort also
    # nicht erst erreicht werden; im Betrieb zaehlen Sperren ohnehin weiter.
    $stopTime = Get-DayTenHourStopTime -Day $Day -Cutoff $cutoff
    $tenReached = ($null -ne $stopTime)
    if (-not $tenReached) {
        # 10:00 wurde nicht erreicht: das bisher angenommene Ende bestaetigen
        if ($AssumedEnd -is [datetime]) { $stopTime = $AssumedEnd }
        elseif ($Day.EndedAt) { try { $stopTime = ConvertFrom-DateTimeString $Day.EndedAt } catch { } }
        if ($null -eq $stopTime) { $stopTime = $cutoff }
    }
    $closeError = Close-DayPartsAt -Day $Day -End $stopTime
    if ($closeError -ne '') {
        Restore-DayFromSnapshot -Day $Day -Snapshot $snapshot
        Restore-LogMark -Mark $logMark
        return $closeError
    }
    $Day['Status'] = 'Beendet'
    $Day['EndedAt'] = ConvertTo-DateTimeString $stopTime
    # Sachlich korrekter Abschlussgrund: nur wenn die zehn Netto-Arbeitsstunden
    # tatsaechlich erreicht wurden, wird die 10:00-Bestaetigung vermerkt.
    if ($tenReached) { $Day['EndReason'] = 'Automatisch (10:00 bestätigt)' }
    else { $Day['EndReason'] = 'Automatisch angenommenes Ende bestätigt' }
    $Day['AutoEnded'] = $true
    if ($tenReached) { $Day['MaxReached'] = $true }
    $Day['AutoEndReviewPending'] = $false
    $Day['AutoEndReviewed'] = $true
    Update-MaxReachedState -Day $Day -Now $stopTime
    Update-DayTotals -Day $Day -Now $stopTime | Out-Null
    Add-Correction -Day $Day -Description 'Automatisches Tagesende bestätigt' -NewValue ('Ende ' + (Format-Clock $stopTime)) -NoLog
    if (-not (Save-WorkData)) {
        Restore-DayFromSnapshot -Day $Day -Snapshot $snapshot
        # Auch die waehrend der Transaktion erzeugten Logeintraege zuruecknehmen:
        # kein Eintrag darf eine nicht gespeicherte Aenderung als Erfolg ausweisen.
        Restore-LogMark -Mark $logMark
        return 'Die Bestätigung konnte nicht gespeichert werden. Der vorherige Zustand wurde wiederhergestellt.'
    }
    Write-CorrectionLog -Day $Day -Description 'Automatisches Tagesende bestätigt' -NewValue ('Ende ' + (Format-Clock $stopTime))
    Write-AppLog -Message ("Automatisches Tagesende für {0} bestätigt (Ende {1})." -f $Day.Date, (Format-Clock $stopTime))
    return ''
}

# Nachtraegliche manuelle Endzeit fuer einen nicht ordnungsgemaess beendeten
# Tag. Vollstaendig validiert (nicht vor Beginn, nicht in der Zukunft, keine
# Segmentueberlappung, Netto hoechstens 10:00); die Aenderung wird genau
# EINMAL gespeichert und bei Fehlern vollstaendig zurueckgenommen.
# Liefert '' oder eine Fehlermeldung.
function Complete-AutoEndManual {
    param(
        [Parameter(Mandatory)]$Day,
        [Parameter(Mandatory)][datetime]$End,
        [datetime]$Now = (Get-Date)
    )
    if ($End -gt $Now.AddMinutes(1)) {
        return "Das Arbeitsende $($End.ToString('dd.MM.yyyy HH:mm')) liegt in der Zukunft."
    }
    $beginn = $null
    foreach ($seg in @($Day.Segments)) {
        if ($null -eq $seg) { continue }
        $s = $null
        try { $s = ConvertFrom-DateTimeString $seg.Start } catch { }
        if ($null -ne $s -and ($null -eq $beginn -or $s -lt $beginn)) { $beginn = $s }
    }
    if ($null -ne $beginn -and $End -lt $beginn) {
        return "Das Arbeitsende darf nicht vor dem Arbeitsbeginn ($($beginn.ToString('dd.MM.yyyy HH:mm'))) liegen."
    }
    $snapshot = Get-DaySnapshot -Day $Day
    $logMark = Get-LogMark
    # Ein noch offenes Sperrintervall wird von Close-DayPartsAt exakt am
    # BESTAETIGTEN Arbeitsende geschlossen (niemals vor seinem Beginn und
    # niemals nach dem bestaetigten Ende; ein erst nach dem Ende beginnendes
    # Intervall wird verworfen). Der Zeitraum bis zum bestaetigten Ende
    # zaehlt damit als Sperrzeit und nie faelschlich als Arbeitszeit.
    $closeError = Close-DayPartsAt -Day $Day -End $End
    if ($closeError -ne '') {
        Restore-DayFromSnapshot -Day $Day -Snapshot $snapshot
        Restore-LogMark -Mark $logMark
        return $closeError
    }
    # Zehn-Stunden-Regel: eine spaetere Uhrzeit ist zulaessig, wenn Pausen
    # oder Sperrintervalle die Nettozeit unter 10:00 halten.
    $comp = Get-DayComputation -Day $Day -Now $End
    if ($comp.Netto.TotalMinutes -gt ([int]$Day.MaxMinutes + 0.02)) {
        $limitAt = Get-DayTenHourStopTime -Day $Day -Cutoff $End
        Restore-DayFromSnapshot -Day $Day -Snapshot $snapshot
        Restore-LogMark -Mark $logMark
        $limitText = ''
        if ($null -ne $limitAt) { $limitText = (' Die maximale Nettozeit von 10:00 Stunden wurde bereits um {0} erreicht.' -f $limitAt.ToString('dd.MM.yyyy HH:mm')) }
        return ('Mit diesem Arbeitsende würde die Netto-Arbeitszeit 10:00 Stunden überschreiten - die Eingabe wird nicht gespeichert.' + $limitText)
    }
    $oldEnd = [string]$Day['EndedAt']
    $Day['Status'] = 'Beendet'
    $Day['EndedAt'] = ConvertTo-DateTimeString $End
    $Day['EndReason'] = 'Nachträglich manuell korrigiert'
    $Day['AutoEnded'] = $false
    $Day['AutoEndReviewPending'] = $false
    $Day['AutoEndReviewed'] = $true
    Update-MaxReachedState -Day $Day -Now $End
    Update-DayTotals -Day $Day -Now $End | Out-Null
    Add-Correction -Day $Day -Description 'Arbeitsende nachträglich manuell korrigiert' -OldValue $oldEnd -NewValue (ConvertTo-DateTimeString $End) -NoLog
    if (-not (Save-WorkData)) {
        Restore-DayFromSnapshot -Day $Day -Snapshot $snapshot
        # Kein falscher Erfolgslogeintrag nach dem Rollback (Transaktions-Log)
        Restore-LogMark -Mark $logMark
        return 'Die Korrektur konnte nicht gespeichert werden. Der vorherige Zustand (einschließlich Review-Status) wurde wiederhergestellt.'
    }
    Write-CorrectionLog -Day $Day -Description 'Arbeitsende nachträglich manuell korrigiert' -OldValue $oldEnd -NewValue (ConvertTo-DateTimeString $End)
    Write-AppLog -Message ("Arbeitsende für {0} nachträglich korrigiert: {1}" -f $Day.Date, $End.ToString('dd.MM.yyyy HH:mm'))
    return ''
}

# Prueft nach 'Tag bearbeiten', ob der Tag vollstaendig und konsistent
# beendet ist (nur dann darf er als geprueft markiert werden).
function Test-DayReviewComplete {
    param([Parameter(Mandatory)]$Day)
    if ([string]$Day.Status -ne 'Beendet') { return $false }
    $ended = $null
    if ($Day.EndedAt) { try { $ended = ConvertFrom-DateTimeString $Day.EndedAt } catch { } }
    if ($null -eq $ended) { return $false }
    foreach ($seg in @($Day.Segments)) {
        if ($seg -and [bool]$seg.Running) { return $false }
    }
    foreach ($listName in @('ManualPauses', 'LockIntervals')) {
        foreach ($iv in @($Day[$listName])) {
            if ($iv -and $null -eq $iv.End) { return $false }
        }
    }
    return (Test-DayUnderMax -Day $Day)
}

# Erkennung einer nicht rekonstruierbaren Luecke im Homeoffice nach Neustart
function Get-HomeofficeGap {
    param([Parameter(Mandatory)]$Day, [Parameter(Mandatory)]$Data, [datetime]$Now = (Get-Date))
    $running = $null
    foreach ($seg in @($Day.Segments)) {
        if ($seg.Running) { $running = $seg }
    }
    if ($null -eq $running -or $running.Mode -ne 'Homeoffice') { return $null }
    $lastSaved = ConvertFrom-DateTimeString $Data['LastSavedAt']
    if ($null -eq $lastSaved) { return $null }
    $segStart = ConvertFrom-DateTimeString $running.Start
    if ($lastSaved -lt $segStart) { $lastSaved = $segStart }
    $gap = $Now - $lastSaved
    if ($gap.TotalMinutes -lt $script:Const.HoGapPromptMinutes) { return $null }
    return @{ Start = $lastSaved; End = $Now; Segment = $running }
}

# Offene manuelle Pause, die beim letzten Beenden der Anwendung noch lief
function Get-OpenManualPause {
    param([Parameter(Mandatory)]$Day)
    foreach ($iv in @($Day.ManualPauses)) {
        if ($null -eq $iv.End) { return $iv }
    }
    return $null
}

# Sichert unmittelbar nach dem erfolgreichen Entschluesseln - und VOR jedem
# neuen Speichervorgang - die unveraenderten Werte der vorherigen Sitzung.
# Die Wiederherstellungslogik (Homeoffice-Luecke, offene Sperrintervalle,
# offene Pausen) arbeitet ausschliesslich mit diesen Werten; der neue
# Sitzungsstatus ersetzt den fachlichen Tracking-Checkpoint nicht.
# Reine, testbare Funktion.
function New-RecoveryState {
    param(
        [Parameter(Mandatory)]$Vault,
        [string]$LoadedFrom = ''
    )
    $lastSavedAt = $null
    if ($Vault['WorkData'] -is [System.Collections.IDictionary]) {
        $lastSavedAt = $Vault['WorkData']['LastSavedAt']
    }
    $runningMode = $null
    $hadOpenPause = $false
    $hadOpenLock = $false
    foreach ($day in @($Vault['WorkData']['Days'])) {
        if ($null -eq $day -or [string]$day['Status'] -ne 'Aktiv') { continue }
        foreach ($seg in @($day['Segments'])) {
            if ($seg -and [bool]$seg['Running']) { $runningMode = [string]$seg['Mode'] }
        }
        foreach ($iv in @($day['ManualPauses'])) {
            if ($iv -and $null -eq $iv['End']) { $hadOpenPause = $true }
        }
        foreach ($iv in @($day['LockIntervals'])) {
            if ($iv -and $null -eq $iv['End']) { $hadOpenLock = $true }
        }
    }
    return @{
        PreviousCleanShutdown = [bool]$Vault['CleanShutdown']
        PreviousCheckpointAt  = $Vault['LastCheckpointAt']
        PreviousLastSavedAt   = $lastSavedAt
        PreviousSessionId     = [string]$Vault['SessionId']
        PreviousRunningMode   = $runningMode
        HadOpenPause          = $hadOpenPause
        HadOpenLock           = $hadOpenLock
        LoadedFrom            = $LoadedFrom
        LoadedRevision        = [long]$Vault['Revision']
    }
}

#endregion


#region ===== WPF-Grundlagen (Theme, XAML-Lader, Fensterposition) =====

# Dunkles Theme, wird in jedes Fenster anstelle des Platzhalters eingesetzt
$script:ThemeXaml = @'
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#FFEDF2F7"/>
        </Style>
        <Style TargetType="Label">
            <Setter Property="Foreground" Value="#FFEDF2F7"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#FF2C3648"/>
            <Setter Property="Foreground" Value="#FFEDF2F7"/>
            <Setter Property="BorderBrush" Value="#FF44506A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="14,6"/>
            <Setter Property="Margin" Value="0,0,8,8"/>
            <Setter Property="MinWidth" Value="110"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#FF3A4760"/>
                                <Setter TargetName="Bd" Property="BorderBrush" Value="#FF5A6A8A"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#FF1F2735"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Bd" Property="Background" Value="#FF1C222D"/>
                                <Setter TargetName="Bd" Property="BorderBrush" Value="#FF2E3644"/>
                                <Setter Property="Foreground" Value="#FF5F6A7A"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#FF10141B"/>
            <Setter Property="Foreground" Value="#FFEDF2F7"/>
            <Setter Property="BorderBrush" Value="#FF44506A"/>
            <Setter Property="Padding" Value="4,2"/>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#FFEDF2F7"/>
            <Setter Property="Margin" Value="0,3,0,3"/>
        </Style>
        <Style TargetType="RadioButton">
            <Setter Property="Foreground" Value="#FFEDF2F7"/>
            <Setter Property="Margin" Value="0,3,0,3"/>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="MinWidth" Value="120"/>
        </Style>
        <Style TargetType="DataGrid">
            <Setter Property="Background" Value="#FF10141B"/>
            <Setter Property="Foreground" Value="#FFEDF2F7"/>
            <Setter Property="RowBackground" Value="#FF1A2130"/>
            <Setter Property="AlternatingRowBackground" Value="#FF151B27"/>
            <Setter Property="BorderBrush" Value="#FF44506A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="GridLinesVisibility" Value="None"/>
            <Setter Property="AutoGenerateColumns" Value="True"/>
            <Setter Property="IsReadOnly" Value="True"/>
            <Setter Property="CanUserAddRows" Value="False"/>
            <Setter Property="CanUserResizeRows" Value="False"/>
            <Setter Property="SelectionMode" Value="Single"/>
            <Setter Property="SelectionUnit" Value="FullRow"/>
            <Setter Property="HeadersVisibility" Value="Column"/>
            <Setter Property="RowHeaderWidth" Value="0"/>
            <Setter Property="ColumnWidth" Value="*"/>
        </Style>
        <Style TargetType="DataGridColumnHeader">
            <Setter Property="Background" Value="#FF232B3A"/>
            <Setter Property="Foreground" Value="#FFAAB8C6"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="BorderBrush" Value="#FF44506A"/>
            <Setter Property="BorderThickness" Value="0,0,0,1"/>
        </Style>
        <Style TargetType="DataGridRow">
            <Setter Property="MinHeight" Value="26"/>
        </Style>
        <Style TargetType="DataGridCell">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#FFEDF2F7"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="DataGridCell">
                        <Border Background="{TemplateBinding Background}" Padding="8,3">
                            <ContentPresenter VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="#FF2E4A6E"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="GroupBox">
            <Setter Property="Foreground" Value="#FFEDF2F7"/>
            <Setter Property="BorderBrush" Value="#FF44506A"/>
            <Setter Property="Padding" Value="8"/>
            <Setter Property="Margin" Value="0,0,0,10"/>
        </Style>
        <Style TargetType="TabControl">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderBrush" Value="#FF44506A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="4"/>
        </Style>
        <Style TargetType="TabItem">
            <Setter Property="Foreground" Value="#FFAAB8C6"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border x:Name="TabBd" Background="#FF1C222D" BorderBrush="#FF44506A"
                                BorderThickness="1,1,1,0" CornerRadius="4,4,0,0" Margin="0,0,4,0" Padding="14,7">
                            <ContentPresenter ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="TabBd" Property="Background" Value="#FF2C3648"/>
                                <Setter Property="Foreground" Value="#FFEDF2F7"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="TabBd" Property="Background" Value="#FF2A3344"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="DarkComboBoxItemStyle" TargetType="ComboBoxItem">
            <Setter Property="Foreground" Value="#FFEDF2F7"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="MinHeight" Value="26"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBoxItem">
                        <Border x:Name="ItemBd" Background="{TemplateBinding Background}"
                                Padding="{TemplateBinding Padding}" CornerRadius="3" SnapsToDevicePixels="True">
                            <ContentPresenter VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter TargetName="ItemBd" Property="Background" Value="#FF3A4760"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="ItemBd" Property="Background" Value="#FF2E4A6E"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Foreground" Value="#FF5F6A7A"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="DarkComboBoxStyle" TargetType="ComboBox">
            <Setter Property="Foreground" Value="#FFEDF2F7"/>
            <Setter Property="MinWidth" Value="120"/>
            <Setter Property="MinHeight" Value="26"/>
            <Setter Property="MaxDropDownHeight" Value="280"/>
            <Setter Property="ItemContainerStyle" Value="{StaticResource DarkComboBoxItemStyle}"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <Border x:Name="CbBd" Background="#FF10141B" BorderBrush="#FF44506A"
                                    BorderThickness="1" CornerRadius="4" SnapsToDevicePixels="True"/>
                            <Grid Margin="1">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="22"/>
                                </Grid.ColumnDefinitions>
                                <ContentPresenter x:Name="CbSelected" Grid.Column="0" Margin="8,4,4,4"
                                                  VerticalAlignment="Center" IsHitTestVisible="False"
                                                  Content="{TemplateBinding SelectionBoxItem}"
                                                  ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                                  ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}"/>
                                <Path Grid.Column="1" HorizontalAlignment="Center" VerticalAlignment="Center"
                                      Data="M 0,0 L 4,4 L 8,0" Stroke="#FFAAB8C6" StrokeThickness="1.6"/>
                            </Grid>
                            <ToggleButton x:Name="CbToggle" Focusable="False" ClickMode="Press"
                                          IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                                <ToggleButton.Template>
                                    <ControlTemplate TargetType="ToggleButton">
                                        <Border Background="Transparent"/>
                                    </ControlTemplate>
                                </ToggleButton.Template>
                            </ToggleButton>
                            <Popup x:Name="PART_Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}"
                                   AllowsTransparency="True" Focusable="False" PopupAnimation="Fade">
                                <Border Background="#FF151B27" BorderBrush="#FF44506A" BorderThickness="1"
                                        CornerRadius="4" Margin="0,2,0,0"
                                        MinWidth="{TemplateBinding ActualWidth}"
                                        MaxHeight="{TemplateBinding MaxDropDownHeight}">
                                    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                                        <ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained" Margin="2"/>
                                    </ScrollViewer>
                                </Border>
                            </Popup>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="CbBd" Property="BorderBrush" Value="#FF5A6A8A"/>
                                <Setter TargetName="CbBd" Property="Background" Value="#FF161B24"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocusWithin" Value="True">
                                <Setter TargetName="CbBd" Property="BorderBrush" Value="#FF6E80A4"/>
                            </Trigger>
                            <Trigger Property="IsDropDownOpen" Value="True">
                                <Setter TargetName="CbBd" Property="BorderBrush" Value="#FF5A6A8A"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="CbBd" Property="Background" Value="#FF1C222D"/>
                                <Setter Property="Foreground" Value="#FF5F6A7A"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ScrollBarPageButton" TargetType="RepeatButton">
            <Setter Property="Focusable" Value="False"/>
            <Setter Property="IsTabStop" Value="False"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RepeatButton">
                        <Border Background="Transparent"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ScrollBarThumb" TargetType="Thumb">
            <Setter Property="IsTabStop" Value="False"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Thumb">
                        <Border x:Name="ThumbBd" Background="#FF3C4B66" CornerRadius="4" Margin="2"/>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ThumbBd" Property="Background" Value="#FF5A6A8A"/>
                            </Trigger>
                            <Trigger Property="IsDragging" Value="True">
                                <Setter TargetName="ThumbBd" Property="Background" Value="#FF6E80A4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="ScrollBar">
            <Setter Property="Background" Value="#FF12161F"/>
            <Setter Property="Width" Value="12"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Grid Background="{TemplateBinding Background}">
                            <Track x:Name="PART_Track" IsDirectionReversed="True">
                                <Track.DecreaseRepeatButton>
                                    <RepeatButton Style="{StaticResource ScrollBarPageButton}" Command="{x:Static ScrollBar.PageUpCommand}"/>
                                </Track.DecreaseRepeatButton>
                                <Track.Thumb>
                                    <Thumb Style="{StaticResource ScrollBarThumb}"/>
                                </Track.Thumb>
                                <Track.IncreaseRepeatButton>
                                    <RepeatButton Style="{StaticResource ScrollBarPageButton}" Command="{x:Static ScrollBar.PageDownCommand}"/>
                                </Track.IncreaseRepeatButton>
                            </Track>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="Orientation" Value="Horizontal">
                    <Setter Property="Width" Value="Auto"/>
                    <Setter Property="Height" Value="12"/>
                    <Setter Property="Template">
                        <Setter.Value>
                            <ControlTemplate TargetType="ScrollBar">
                                <Grid Background="{TemplateBinding Background}">
                                    <Track x:Name="PART_Track">
                                        <Track.DecreaseRepeatButton>
                                            <RepeatButton Style="{StaticResource ScrollBarPageButton}" Command="{x:Static ScrollBar.PageLeftCommand}"/>
                                        </Track.DecreaseRepeatButton>
                                        <Track.Thumb>
                                            <Thumb Style="{StaticResource ScrollBarThumb}"/>
                                        </Track.Thumb>
                                        <Track.IncreaseRepeatButton>
                                            <RepeatButton Style="{StaticResource ScrollBarPageButton}" Command="{x:Static ScrollBar.PageRightCommand}"/>
                                        </Track.IncreaseRepeatButton>
                                    </Track>
                                </Grid>
                            </ControlTemplate>
                        </Setter.Value>
                    </Setter>
                </Trigger>
            </Style.Triggers>
        </Style>
'@

function New-XamlWindow {
    param([Parameter(Mandatory)][string]$Xaml)
    $final = $Xaml.Replace('<!--THEME-->', $script:ThemeXaml)
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$final)
    return [System.Windows.Markup.XamlReader]::Load($reader)
}

# --- Wiederverwendbare rahmenlose dunkle Titelleiste (WindowChrome) ----------

# Erzeugt eine Caption-Schaltflaeche (Minimieren/Maximieren/Schliessen) fuer
# die eigene Titelleiste. Die Schaltflaechen sind im Chrome anklickbar
# (IsHitTestVisibleInChrome) und loesen KEIN Fensterziehen aus.
function New-ChromeCaptionButton {
    param([Parameter(Mandatory)][string]$Kind)
    $btn = New-Object System.Windows.Controls.Button
    $btn.Width = 46
    $btn.Height = 30
    $btn.MinWidth = 0
    $btn.Margin = New-Object System.Windows.Thickness 0
    $btn.Padding = New-Object System.Windows.Thickness 0
    $btn.BorderThickness = New-Object System.Windows.Thickness 0
    $btn.Background = [System.Windows.Media.Brushes]::Transparent
    $btn.Style = $null   # bewusst KEIN Theme-Button-Stil (flache Caption-Optik)
    $glyphs = @{
        Min     = 'M 0,5 H 10'
        Max     = 'M 0.5,0.5 H 9.5 V 9.5 H 0.5 Z'
        Restore = 'M 2.5,0.5 H 9.5 V 7.5 H 7.5 M 0.5,2.5 H 7.5 V 9.5 H 0.5 Z'
        Close   = 'M 0,0 L 10,10 M 10,0 L 0,10'
    }
    $path = New-Object System.Windows.Shapes.Path
    $path.Data = [System.Windows.Media.Geometry]::Parse($glyphs[$Kind])
    $path.Stroke = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#FFEDF2F7'))
    $path.StrokeThickness = 1.2
    $path.Width = 10
    $path.Height = 10
    $path.VerticalAlignment = 'Center'
    $path.HorizontalAlignment = 'Center'
    $btn.Content = $path
    $hoverColor = '#33FFFFFF'
    if ($Kind -eq 'Close') { $hoverColor = '#CCE05252' }
    $btn.Add_MouseEnter({
            param($sender, $e)
            $sender.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($sender.Tag))
        })
    $btn.Add_MouseLeave({
            param($sender, $e)
            $sender.Background = [System.Windows.Media.Brushes]::Transparent
        })
    $btn.Tag = $hoverColor
    # Klarer Fokuszustand: Standard-Fokusrahmen der Buttons bleibt erhalten
    [System.Windows.Shell.WindowChrome]::SetIsHitTestVisibleInChrome($btn, $true)
    return $btn
}

# Wendet auf ein bereits aus XAML erzeugtes Fenster eine eigene dunkle
# Titelleiste mit System.Windows.Shell.WindowChrome an:
#  - Titel, Verschieben (Caption-Bereich), Doppelklick = Maximieren/
#    Wiederherstellen, Minimieren/Maximieren/Schliessen je nach Fenster
#  - Resize an Raendern/Ecken, MinWidth/MinHeight, Alt+F4, Esc (IsCancel),
#    Owner/ShowDialog, Tab-Navigation und Windows-Snap bleiben erhalten
#  - Maximierung respektiert den Monitor-Arbeitsbereich (kein WindowStyle=None;
#    die Taskleiste wird nicht ueberdeckt); beim Maximieren wird der Inhalt
#    um die Rahmendicke eingerueckt, damit nichts ausserhalb des Monitors liegt
#  - FindName der XAML-Elemente funktioniert weiterhin (NameScope bleibt am
#    Fenster registriert; der Inhalt wird lediglich visuell neu verankert)
# Ein Fehler beim Anwenden faellt kontrolliert auf den Standardrahmen zurueck.
function Add-DarkWindowChrome {
    param(
        [Parameter(Mandatory)]$Window,
        [switch]$NoMinimize,
        [switch]$NoMaximize
    )
    $orig = $null
    try {
        $chrome = New-Object System.Windows.Shell.WindowChrome
        $chrome.CaptionHeight = 32
        $chrome.ResizeBorderThickness = [System.Windows.SystemParameters]::WindowResizeBorderThickness
        $chrome.GlassFrameThickness = New-Object System.Windows.Thickness 0
        $chrome.CornerRadius = New-Object System.Windows.CornerRadius 0
        $chrome.UseAeroCaptionButtons = $false
        [System.Windows.Shell.WindowChrome]::SetWindowChrome($Window, $chrome)

        $orig = $Window.Content
        $Window.Content = $null
        $root = New-Object System.Windows.Controls.Grid
        $rowBar = New-Object System.Windows.Controls.RowDefinition
        $rowBar.Height = New-Object System.Windows.GridLength(32)
        $rowMain = New-Object System.Windows.Controls.RowDefinition
        $rowMain.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        [void]$root.RowDefinitions.Add($rowBar)
        [void]$root.RowDefinitions.Add($rowMain)

        $bar = New-Object System.Windows.Controls.Border
        $bar.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#FF10141B'))
        $bar.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#FF2A3344'))
        $bar.BorderThickness = New-Object System.Windows.Thickness 0, 0, 0, 1
        $barGrid = New-Object System.Windows.Controls.Grid
        $colTitle = New-Object System.Windows.Controls.ColumnDefinition
        $colTitle.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $colButtons = New-Object System.Windows.Controls.ColumnDefinition
        $colButtons.Width = [System.Windows.GridLength]::Auto
        [void]$barGrid.ColumnDefinitions.Add($colTitle)
        [void]$barGrid.ColumnDefinitions.Add($colButtons)

        $title = New-Object System.Windows.Controls.TextBlock
        $title.Text = [string]$Window.Title
        $title.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#FFAAB8C6'))
        $title.FontSize = 13
        $title.VerticalAlignment = 'Center'
        $title.Margin = New-Object System.Windows.Thickness 12, 0, 8, 0
        $title.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        [System.Windows.Controls.Grid]::SetColumn($title, 0)
        [void]$barGrid.Children.Add($title)

        $btnPanel = New-Object System.Windows.Controls.StackPanel
        $btnPanel.Orientation = 'Horizontal'
        [System.Windows.Controls.Grid]::SetColumn($btnPanel, 1)
        $btnMax = $null
        if (-not $NoMinimize) {
            $btnMin = New-ChromeCaptionButton -Kind 'Min'
            $btnMin.ToolTip = 'Minimieren'
            $btnMin.Add_Click({ $Window.WindowState = [System.Windows.WindowState]::Minimized }.GetNewClosure())
            [void]$btnPanel.Children.Add($btnMin)
        }
        if (-not $NoMaximize) {
            $btnMax = New-ChromeCaptionButton -Kind 'Max'
            $btnMax.ToolTip = 'Maximieren'
            $btnMax.Add_Click({
                    if ($Window.WindowState -eq [System.Windows.WindowState]::Maximized) {
                        $Window.WindowState = [System.Windows.WindowState]::Normal
                    }
                    else {
                        $Window.WindowState = [System.Windows.WindowState]::Maximized
                    }
                }.GetNewClosure())
            [void]$btnPanel.Children.Add($btnMax)
        }
        $btnClose = New-ChromeCaptionButton -Kind 'Close'
        $btnClose.ToolTip = 'Schließen'
        $btnClose.Add_Click({ $Window.Close() }.GetNewClosure())
        [void]$btnPanel.Children.Add($btnClose)
        [void]$barGrid.Children.Add($btnPanel)
        $bar.Child = $barGrid
        [System.Windows.Controls.Grid]::SetRow($bar, 0)
        [void]$root.Children.Add($bar)

        if ($null -ne $orig) {
            [System.Windows.Controls.Grid]::SetRow($orig, 1)
            [void]$root.Children.Add($orig)
        }
        $Window.Content = $root

        # Maximieren: Arbeitsbereich respektieren und den Inhalt um die
        # Fensterrahmendicke einruecken; Max-/Restore-Glyph nachfuehren.
        $Window.Add_StateChanged({
                try {
                    if ($Window.WindowState -eq [System.Windows.WindowState]::Maximized) {
                        $root.Margin = New-Object System.Windows.Thickness 7
                        if ($btnMax) {
                            $btnMax.Content.Data = [System.Windows.Media.Geometry]::Parse('M 2.5,0.5 H 9.5 V 7.5 H 7.5 M 0.5,2.5 H 7.5 V 9.5 H 0.5 Z')
                            $btnMax.ToolTip = 'Wiederherstellen'
                        }
                    }
                    else {
                        $root.Margin = New-Object System.Windows.Thickness 0
                        if ($btnMax) {
                            $btnMax.Content.Data = [System.Windows.Media.Geometry]::Parse('M 0.5,0.5 H 9.5 V 9.5 H 0.5 Z')
                            $btnMax.ToolTip = 'Maximieren'
                        }
                    }
                }
                catch { }
            }.GetNewClosure())
    }
    catch {
        # Chrome ist rein optisch: bei einem Fehler bleibt der Standardrahmen
        try {
            if ($null -ne $orig -and $null -eq $Window.Content) { $Window.Content = $orig }
        }
        catch { }
        Write-AppLog -Level 'WARN' -Message ('Eigene Fenstertitelleiste konnte nicht angewendet werden: ' + $_.Exception.Message)
    }
}

# Liefert die Monitorflaechen (naeherungsweise in WPF-Einheiten; der
# Umrechnungsfaktor wird aus dem Hauptmonitor bestimmt - bei stark
# unterschiedlicher DPI-Skalierung ist dies eine dokumentierte Naeherung).
# Der Hauptmonitor steht immer an erster Stelle.
#  Standard:     WorkingArea (ohne Taskleiste) - fuer die ERSTMALIGE
#                Standardposition.
#  -FullBounds:  vollstaendige Monitorflaeche (Screen.Bounds, inkl.
#                Taskleiste) - fuer die VALIDIERUNG einer vom Benutzer
#                gespeicherten Position. Eine absichtlich ueber der
#                Taskleiste platzierte Position ist damit gueltig.
function Get-DisplayScreens {
    param([switch]$FullBounds)
    $result = New-Object System.Collections.ArrayList
    try {
        $factor = 1.0
        $primaryPx = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
        $primaryDip = [System.Windows.SystemParameters]::PrimaryScreenWidth
        if ($primaryPx -gt 0 -and $primaryDip -gt 0) { $factor = $primaryDip / $primaryPx }
        foreach ($scr in [System.Windows.Forms.Screen]::AllScreens) {
            $wa = $scr.WorkingArea
            if ($FullBounds) { $wa = $scr.Bounds }
            $item = @{
                Left    = $wa.X * $factor
                Top     = $wa.Y * $factor
                Width   = $wa.Width * $factor
                Height  = $wa.Height * $factor
                Primary = [bool]$scr.Primary
            }
            if ($scr.Primary) { $result.Insert(0, $item) }
            else { [void]$result.Add($item) }
        }
    }
    catch { }
    if ($result.Count -eq 0) {
        $wa = [System.Windows.SystemParameters]::WorkArea
        [void]$result.Add(@{ Left = $wa.Left; Top = $wa.Top; Width = $wa.Width; Height = $wa.Height; Primary = $true })
    }
    return ,$result
}

# Prueft eine gespeicherte Fensterposition gegen die tatsaechlichen
# Monitorflaechen (nicht nur gegen das virtuelle Gesamtrechteck).
# Beruecksichtigt Monitore links/oberhalb des Hauptmonitors, Luecken
# zwischen Monitoren, entfernte Monitore und geaenderte Aufloesungen.
# Reine, testbare Funktion.
#  $Screens:        vollstaendige Monitorflaechen (Screen.Bounds) fuer die
#                   Validierung einer gespeicherten Position. Eine Position
#                   ueber der Taskleiste liegt innerhalb dieser Flaeche und
#                   wird deshalb NICHT korrigiert.
#  $DefaultScreens: Arbeitsbereiche (WorkingArea) fuer die erstmalige
#                   Standardposition; ohne Angabe wird $Screens verwendet.
function Resolve-WindowPosition {
    param(
        $Left, $Top,
        [double]$Width, [double]$Height,
        [Parameter(Mandatory)]$Screens,
        $DefaultScreens = $null
    )
    $list = @($Screens)
    if ($list.Count -eq 0) { $list = @(@{ Left = 0; Top = 0; Width = 1920; Height = 1080 }) }
    $defaultList = @($DefaultScreens)
    if ($defaultList.Count -eq 0) { $defaultList = $list }
    $primary = $defaultList[0]

    if ($null -eq $Left -or $null -eq $Top) {
        # Standard: rechts unten auf dem Hauptmonitor, knapp oberhalb der
        # Taskleiste (auf Basis des Arbeitsbereichs)
        return @{
            Left = [math]::Max($primary.Left, $primary.Left + $primary.Width - $Width - 16)
            Top  = [math]::Max($primary.Top, $primary.Top + $primary.Height - $Height - 8)
        }
    }
    $primary = $list[0]
    $l = [double]$Left
    $t = [double]$Top

    # Sichtbar, wenn mindestens 40 x 20 Einheiten des Fensters in einem
    # realen Arbeitsbereich liegen (eine Position in einer Luecke zwischen
    # Monitoren gilt damit als nicht sichtbar).
    foreach ($scr in $list) {
        $ovWidth = [math]::Min($l + $Width, $scr.Left + $scr.Width) - [math]::Max($l, $scr.Left)
        $ovHeight = [math]::Min($t + $Height, $scr.Top + $scr.Height) - [math]::Max($t, $scr.Top)
        if ($ovWidth -ge 40 -and $ovHeight -ge 20) {
            return @{ Left = $l; Top = $t }
        }
    }

    # Nicht (ausreichend) sichtbar: auf den naechstgelegenen vorhandenen
    # Monitor verschieben und dort vollstaendig einpassen.
    $winCx = $l + $Width / 2.0
    $winCy = $t + $Height / 2.0
    $best = $primary
    $bestDist = [double]::MaxValue
    foreach ($scr in $list) {
        $scrCx = $scr.Left + $scr.Width / 2.0
        $scrCy = $scr.Top + $scr.Height / 2.0
        $dist = [math]::Sqrt([math]::Pow($winCx - $scrCx, 2) + [math]::Pow($winCy - $scrCy, 2))
        if ($dist -lt $bestDist) { $bestDist = $dist; $best = $scr }
    }
    $maxLeft = $best.Left + $best.Width - $Width
    $maxTop = $best.Top + $best.Height - $Height
    $newLeft = [math]::Min([math]::Max($l, $best.Left), [math]::Max($best.Left, $maxLeft))
    $newTop = [math]::Min([math]::Max($t, $best.Top), [math]::Max($best.Top, $maxTop))
    return @{ Left = $newLeft; Top = $newTop }
}

function Set-CompactWindowPosition {
    param([Parameter(Mandatory)]$Window)
    # Die Breite der kompakten Ansicht bestimmt AUSSCHLIESSLICH der aktuell
    # sichtbare Inhalt (SizeToContent="WidthAndHeight"). Eine frueher
    # gespeicherte Fensterbreite (WindowWidth aelterer Versionen) wird nicht
    # wiederhergestellt, NIEMALS als MinWidth gesetzt und auch nicht als
    # Ersatzwert fuer die Positionsberechnung verwendet - nur so kann das
    # Fenster nach einer Verringerung der Feldauswahl wieder schrumpfen.
    $Window.MinWidth = 0
    if ($Window -is [System.Windows.Window]) {
        # Ein explizit gesetzter Width-Wert wuerde SizeToContent aushebeln -
        # entfernen, damit wieder der Inhalt die Breite bestimmt.
        try { $Window.ClearValue([System.Windows.Window]::WidthProperty) } catch { }
    }
    $w = $Window.ActualWidth
    if ($w -le 0) { $w = 560 }
    $h = $Window.ActualHeight
    if ($h -le 0) { $h = 52 }
    # Validierung gegen die VOLLSTAENDIGEN Monitorflaechen (inkl. Taskleiste),
    # Standardposition dagegen auf Basis des Arbeitsbereichs. Eine bewusst
    # ueber der Taskleiste gespeicherte Position bleibt so exakt erhalten.
    $pos = Resolve-WindowPosition -Left $script:App.Settings['WindowLeft'] -Top $script:App.Settings['WindowTop'] `
        -Width $w -Height $h -Screens (Get-DisplayScreens -FullBounds) -DefaultScreens (Get-DisplayScreens)
    $Window.Left = $pos.Left
    $Window.Top = $pos.Top
}

# Speichert die aktuelle POSITION (nur WindowLeft/WindowTop) der kompakten
# Ansicht genau dann, wenn sie sich tatsaechlich geaendert hat (kein
# Tresor-Schreiben pro Klick oder Bewegungspixel). Die Fensterbreite wird
# bewusst NICHT gespeichert: sie ergibt sich immer automatisch aus dem
# Inhalt (SizeToContent) und darf keine dauerhafte Wirkung entfalten.
# Liefert $true bei Erfolg; ein Fehler wird nur protokolliert und darf den
# Aufrufer (insbesondere das Ausblenden in den Infobereich) nie abbrechen.
function Save-CompactWindowPlacement {
    param([Parameter(Mandatory)]$Window)
    try {
        if ($null -eq $script:App.Settings) { return $false }
        $oldLeft = $script:App.Settings['WindowLeft']
        $oldTop = $script:App.Settings['WindowTop']
        $changed = $false
        if ($null -eq $oldLeft -or [math]::Abs([double]$oldLeft - $Window.Left) -gt 0.5) { $changed = $true }
        if ($null -eq $oldTop -or [math]::Abs([double]$oldTop - $Window.Top) -gt 0.5) { $changed = $true }
        if (-not $changed) { return $true }
        $script:App.Settings['WindowLeft'] = $Window.Left
        $script:App.Settings['WindowTop'] = $Window.Top
        return [bool](Save-Settings)
    }
    catch {
        Write-AppLog -Level 'WARN' -Message ('Fensterposition konnte nicht gespeichert werden: ' + $_.Exception.Message)
        return $false
    }
}

# Kompaktes Fenster in den Infobereich ausblenden (Wiederanzeige ueber das
# Tray-Symbol). Ohne Tray-Symbol wird stattdessen minimiert.
# Kompaktes Fenster in den Infobereich ausblenden. AUSNAHMESICHER und
# reentranzgeschuetzt: Hide() beendet die Anwendung NICHT (nichtmodale
# Lebensdauer ueber den Dispatcher; Timer, Radio, Aktivhaltung und
# Lock-/Unlock-Verarbeitung laufen unsichtbar weiter). Steht kein
# funktionierendes Tray-Symbol zur Verfuegung, wird stattdessen ueber die
# Taskleiste minimiert - die Anwendung bleibt in jedem Fall erreichbar.
# Kein ungefangener Fehler verlaesst diese Funktion.
function Hide-CompactWindow {
    if ($script:App.Ui.HideInProgress) { return }
    $script:App.Ui.HideInProgress = $true
    try {
        $win = $script:App.Ui.Compact
        if ($null -eq $win) { return }
        # 2. Pausen-/Sperrzeit-Details visuell verbergen
        try { Hide-PauseLockDetails } catch { }
        # 3. Position bestmoeglich sichern (Fehler bricht das Ausblenden nicht ab)
        Save-CompactWindowPlacement -Window $win | Out-Null
        # 4./5. Tray-Symbol sicherstellen und tatsaechlich pruefen (vorhanden,
        # sichtbar, nicht bereits freigegeben)
        if (-not $script:App.Ui.Tray) { Enable-TrayIcon }
        $trayOk = $false
        try { $trayOk = ($null -ne $script:App.Ui.Tray -and [bool]$script:App.Ui.Tray.Visible) }
        catch { $trayOk = $false }
        if ($trayOk) {
            # 6. erst jetzt das kompakte Fenster ausblenden
            $win.Hide()
            Write-AppLog -Message 'Kompakte Ansicht in den Infobereich ausgeblendet.'
        }
        else {
            # Fallback: ohne Tray-Symbol NICHT vollstaendig verstecken,
            # sondern ueber die Taskleiste erreichbar minimieren
            $win.ShowInTaskbar = $true
            $win.WindowState = [System.Windows.WindowState]::Minimized
            Write-AppLog -Level 'WARN' -Message 'Tray-Symbol nicht verfügbar - kompakte Ansicht wurde stattdessen über die Taskleiste minimiert.'
        }
    }
    catch {
        Write-AppLog -Level 'ERROR' -Message ('Ausblenden in den Infobereich fehlgeschlagen (Anwendung läuft weiter): ' + $_.Exception.Message)
    }
    finally {
        # 7. Ausblendstatus in jedem Fall wieder freigeben
        $script:App.Ui.HideInProgress = $false
    }
}

# Zeigt DIESELBE Fensterinstanz erneut an (kein Neuerzeugen) - funktioniert
# auch nach mehrfachem Verbergen/Anzeigen. Bringt das Fenster in den
# Vordergrund, ohne dauerhaft den Fokus zu stehlen.
function Show-CompactWindow {
    $win = $script:App.Ui.Compact
    if ($null -eq $win) { return }
    try {
        $win.WindowState = [System.Windows.WindowState]::Normal
        $win.ShowInTaskbar = -not [bool]$script:App.Settings['TrayIconEnabled']
        if (-not $win.IsVisible) { $win.Show() }
        Set-CompactWindowPosition -Window $win
        $win.Topmost = [bool]$script:App.Settings['Topmost']
        Update-CompactWindowLayout
        if ($win.Topmost) {
            try { [ArbeitszeitTool.NativeWindow]::EnsureTopmostNoActivate($script:App.Ui.Handle) } catch { }
        }
        else {
            try { $win.Activate() | Out-Null } catch { }
        }
        Invoke-MainRefresh
    }
    catch {
        Write-AppLog -Level 'WARN' -Message ('Kompakte Ansicht konnte nicht angezeigt werden: ' + $_.Exception.Message)
    }
}

# Fuehrt eine Aktion kontrolliert auf dem WPF-Dispatcher des kompakten
# Fensters aus. Ereignisse des Windows-Forms-NotifyIcon duerfen WPF-Elemente
# nicht direkt aus einem moeglicherweise fremden Thread veraendern.
function Invoke-OnUiDispatcher {
    param([Parameter(Mandatory)][scriptblock]$Action)
    try {
        $win = $script:App.Ui.Compact
        if ($win -and -not $win.Dispatcher.CheckAccess()) {
            $win.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Normal, [action]$Action) | Out-Null
        }
        else {
            & $Action
        }
    }
    catch { }
}

#endregion

#region ===== Kompakte Ansicht =====

$script:CompactXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ArbeitszeitTool"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        SizeToContent="WidthAndHeight" ResizeMode="NoResize"
        ShowInTaskbar="False" Topmost="True" ShowActivated="False">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <Border x:Name="RootBorder" CornerRadius="6" BorderThickness="1"
            BorderBrush="#66FFFFFF" Background="#F2131820" Padding="12,4,12,6">
        <StackPanel>
            <Grid>
                <!-- Seitenabstand = Breite von PnlRadio (24+2+24) + 6 Abstand, beidseitig
                     fuer die Zentrierung. Sonst ueberdeckt der Play-Button die Kopfzeile,
                     sobald die Statuszeile schmaler ist (z. B. Preset "Minimum"). -->
                <TextBlock x:Name="HeaderLine" FontFamily="Consolas" FontSize="13" Foreground="#FFAAB8C6" Text="--:--:--" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="56,0,56,0"/>
                <StackPanel x:Name="PnlRadio" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <Button x:Name="BtnRadioPlay" Width="24" Height="18" MinWidth="0" Padding="0" Margin="0"
                            Background="Transparent" BorderThickness="0" ToolTip="Radio starten">
                        <Path x:Name="PathRadioPlay" Fill="#FFAAB8C6" Stretch="Uniform" Width="9" Height="9"/>
                    </Button>
                    <Button x:Name="BtnRadioVolume" Width="24" Height="18" MinWidth="0" Padding="0" Margin="2,0,0,0"
                            Background="Transparent" BorderThickness="0" ToolTip="Lautstärke">
                        <Path Stroke="#FFAAB8C6" StrokeThickness="1.2" Fill="#FFAAB8C6" Stretch="Uniform" Width="10" Height="9"
                              Data="M 1,5 L 4,5 L 8,2 L 8,12 L 4,9 L 1,9 Z M 10,4 C 12,5.6 12,8.4 10,10"/>
                    </Button>
                </StackPanel>
                <Popup x:Name="PopRadioVolume" StaysOpen="False" Placement="Bottom" AllowsTransparency="True">
                    <Border Background="#FF1A2130" BorderBrush="#FF44506A" BorderThickness="1" CornerRadius="4" Padding="8,6">
                        <StackPanel Orientation="Horizontal">
                            <Slider x:Name="SldRadioVolume" Width="130" Minimum="0" Maximum="100" IsSnapToTickEnabled="True" TickFrequency="1" VerticalAlignment="Center"/>
                            <TextBlock x:Name="LblRadioVolume" Margin="8,0,0,0" VerticalAlignment="Center" Foreground="#FFEDF2F7" FontFamily="Consolas"/>
                        </StackPanel>
                    </Border>
                </Popup>
            </Grid>
            <TextBlock x:Name="StatusLine" FontFamily="Consolas" FontSize="13" Foreground="#FFF2F6FA" Margin="0,1,0,0" Text="..." HorizontalAlignment="Center"/>
        </StackPanel>
    </Border>
</Window>
'@

function Get-HeaderLineText {
    $now = Get-Date
    $culture = [System.Globalization.CultureInfo]::GetCultureInfo('de-DE')
    $clockFormat = 'HH:mm:ss'
    if (-not $script:App.Settings['ShowSeconds']) { $clockFormat = 'HH:mm' }
    return '{0} | KW {1} | {2}' -f $now.ToString($clockFormat), (Get-IsoWeek $now), $now.ToString('dddd, dd.MM.yyyy', $culture)
}

# Baut die zweite Zeile der kompakten Ansicht aus den konfigurierten Feldern
function Get-CompactStatusText {
    param($Comp, $Day)
    if ($null -eq $Day) {
        return 'Kein aktiver Arbeitstag | Rechtsklick: Arbeitstag starten'
    }
    $parts = New-Object System.Collections.ArrayList
    $mark = ''
    if ($Comp.EndePausiert) { $mark = '*' }
    $sollEndeText = {
        if ($Comp.SollErreicht) { return 'Soll-Ende: erreicht' }
        if ($Comp.SollEnde) { return 'Soll-Ende: ' + (Format-Clock $Comp.SollEnde) + $mark }
        return 'Soll-Ende: --:--'
    }
    $maxEndeText = {
        if ($Comp.MaxEnde) { return 'Max-Ende: ' + (Format-Clock $Comp.MaxEnde) + $mark }
        return 'Max-Ende: --:--'
    }
    foreach ($field in @($script:App.Settings['CompactFields'])) {
        switch ([string]$field) {
            'Beginn' { [void]$parts.Add('Beginn: ' + (Format-Clock $Comp.Beginn)) }
            'Netto' { [void]$parts.Add('Netto: ' + (Format-Duration $Comp.Netto)) }
            'SollRestOderUeberstunden' {
                if ($Comp.SollErreicht) { [void]$parts.Add('Überstunden: ' + (Format-Duration $Comp.Ueberstunden -WithSign)) }
                else { [void]$parts.Add('Soll-Rest: ' + (Format-Duration $Comp.SollRest)) }
            }
            'SollRest' { [void]$parts.Add('Soll-Rest: ' + (Format-Duration $Comp.SollRest)) }
            'Ueberstunden' { [void]$parts.Add('Überstunden: ' + (Format-Duration $Comp.Ueberstunden -WithSign)) }
            'MaxRest' { [void]$parts.Add('Max-Rest: ' + (Format-Duration $Comp.MaxRest)) }
            'SollEndeOderMaxEnde' {
                # vor Erreichen der Sollzeit Soll-Ende, danach Max-Ende
                if ($Comp.SollErreicht) { [void]$parts.Add((& $maxEndeText)) }
                else { [void]$parts.Add((& $sollEndeText)) }
            }
            'SollEnde' { [void]$parts.Add((& $sollEndeText)) }
            'MaxEnde' { [void]$parts.Add((& $maxEndeText)) }
            'Modus' {
                $mode = '-'
                if ($Comp.RunningMode) { $mode = $Comp.RunningMode }
                [void]$parts.Add('Modus: ' + $mode)
            }
            'Pausenstatus' {
                $status = '-'
                if ($Comp.OpenPause) { $status = 'manuelle Pause' }
                elseif ($Comp.OpenLock) { $status = 'gesperrt' }
                elseif ($Comp.InFesterPause) { $status = 'Betriebspause' }
                [void]$parts.Add('Pause: ' + $status)
            }
            'ScrollLock' {
                $state = 'aus'
                if ($script:App.Settings['KeepAliveEnabled']) { $state = 'an' }
                [void]$parts.Add('Aktivhaltung: ' + $state)
            }
            'Warnstatus' {
                $state = 'OK'
                if ($Comp.MaxReached) { $state = 'MAX' }
                elseif ($Comp.WarnActive) { $state = 'WARNUNG' }
                [void]$parts.Add('Status: ' + $state)
            }
        }
    }
    # Zustand darf nicht nur ueber Farbe vermittelt werden -> Klartext anhaengen
    if ($Day.Status -eq 'Beendet') {
        [void]$parts.Add('ARBEITSTAG BEENDET')
    }
    elseif ($Comp.MaxReached) {
        [void]$parts.Add('MAXIMALE ARBEITSZEIT ERREICHT')
    }
    elseif ($Comp.WarnActive) {
        [void]$parts.Add('WARNUNG: noch ' + (Format-Duration $Comp.MaxRest) + ' bis 10:00')
    }
    # Fehlgeschlagener Speichervorgang: Zustand ist eindeutig gekennzeichnet,
    # bis ein Wiederholungsversuch erfolgreich war (keine stille Erfolgsannahme).
    if ($script:App.Flags -and $script:App.Flags.UnsavedChanges) {
        [void]$parts.Add('NICHT GESPEICHERT')
    }
    return ($parts.ToArray() -join ' | ')
}

# Farbliche Hervorhebung der kompakten Ansicht (zusaetzlich zum Klartext)
function Set-CompactVisualState {
    param([Parameter(Mandatory)]$Window, $Comp, $Day)
    $border = $Window.FindName('RootBorder')
    $normalBorder = '#66FFFFFF'
    $normalBg = '#F2131820'
    if ($null -eq $Day -or $null -eq $Comp) {
        $border.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($normalBorder))
        $border.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($normalBg))
        return
    }
    $borderColor = $normalBorder
    $bgColor = $normalBg
    if ($Comp.MaxReached) { $borderColor = '#FFE05252'; $bgColor = '#F2331414' }
    elseif ($Comp.WarnActive) { $borderColor = '#FFE0A030'; $bgColor = '#F22E2410' }
    elseif ($Comp.OpenPause -or $Comp.OpenLock -or $Comp.InFesterPause) { $borderColor = '#FF4A90D9' }
    $border.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($borderColor))
    $border.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($bgColor))
}

function Update-CompactWindow {
    param($Comp, $Day)
    $win = $script:App.Ui.Compact
    if ($null -eq $win) { return }
    $win.FindName('HeaderLine').Text = Get-HeaderLineText
    $win.FindName('StatusLine').Text = Get-CompactStatusText -Comp $Comp -Day $Day
    Set-CompactVisualState -Window $win -Comp $Comp -Day $Day
}

function Set-CompactAppearance {
    $win = $script:App.Ui.Compact
    if ($null -eq $win) { return }
    $win.Opacity = [math]::Max(0.3, [math]::Min(1.0, ([int]$script:App.Settings['Transparency']) / 100.0))
    $win.Topmost = [bool]$script:App.Settings['Topmost']
    $fontSize = [double]$script:App.Settings['FontSize']
    $win.FindName('HeaderLine').FontSize = $fontSize
    $win.FindName('StatusLine').FontSize = $fontSize
}

# Erzwingt nach Aenderungen der Feldauswahl oder Schriftgroesse eine
# vollstaendige Neuvermessung des kompakten Fensters. SizeToContent bleibt
# "WidthAndHeight"; evtl. explizit gesetzte Width-/Height-Werte und eine
# Mindestbreite werden entfernt, damit das Fenster sowohl wachsen als auch
# wieder SCHRUMPFEN kann. Die natuerliche Mindestbreite ergibt sich allein
# aus der breiteren der beiden sichtbaren Zeilen inkl. Border-Padding.
function Update-CompactWindowLayout {
    $win = $script:App.Ui.Compact
    if ($null -eq $win) { return }
    try {
        $win.MinWidth = 0
        $win.ClearValue([System.Windows.Window]::WidthProperty)
        $win.ClearValue([System.Windows.Window]::HeightProperty)
        if ($win.Content) {
            $win.Content.InvalidateMeasure()
            $win.Content.InvalidateArrange()
        }
        $win.InvalidateMeasure()
        $win.InvalidateArrange()
        $win.UpdateLayout()
    }
    catch { }
}

#endregion

#region ===== Erweiterte Ansicht =====

$script:ExtendedXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ArbeitszeitTool - Erweiterte Ansicht"
        Width="1000" Height="660" MinWidth="760" MinHeight="480"
        Background="#FF171C24" WindowStartupLocation="CenterScreen">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Margin="0,0,0,10">
            <TextBlock x:Name="ExtHeader" FontFamily="Consolas" FontSize="15" Foreground="#FFAAB8C6"/>
            <TextBlock x:Name="ExtStatus" FontSize="17" FontWeight="Bold" Margin="0,4,0,0"/>
            <StackPanel Orientation="Horizontal" Margin="0,6,0,0">
                <TextBlock Text="Radio:" VerticalAlignment="Center" Margin="0,0,6,0" Foreground="#FFAAB8C6"/>
                <ComboBox x:Name="CmbRadioStation" Width="220" DisplayMemberPath="Name" SelectedValuePath="Id"
                          VerticalAlignment="Center" Style="{StaticResource DarkComboBoxStyle}"/>
                <Button x:Name="BtnExtRadioPlay" Width="26" Height="26" MinWidth="0" Padding="0" Margin="8,0,0,0"
                        Background="Transparent" BorderThickness="1" ToolTip="Radio starten" VerticalAlignment="Center">
                    <Path x:Name="PathExtRadioPlay" Fill="#FFEDF2F7" Stretch="Uniform" Width="10" Height="10"/>
                </Button>
                <Slider x:Name="SldExtRadioVolume" Width="120" Minimum="0" Maximum="100" IsSnapToTickEnabled="True" TickFrequency="1"
                        VerticalAlignment="Center" Margin="10,0,0,0" ToolTip="Lautstärke"/>
                <TextBlock x:Name="TxtRadioStatus" VerticalAlignment="Center" Margin="10,0,0,0" Foreground="#FFAAB8C6"/>
            </StackPanel>
        </StackPanel>
        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="330"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <GroupBox Grid.Column="0" Header="Tageswerte" Margin="0,0,10,0">
                <TextBox x:Name="ExtValues" IsReadOnly="True" BorderThickness="0" Background="Transparent"
                         FontFamily="Consolas" FontSize="14" VerticalScrollBarVisibility="Auto"/>
            </GroupBox>
            <Grid Grid.Column="1">
                <Grid.RowDefinitions>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <GroupBox Grid.Row="0" Header="Arbeitsabschnitte">
                    <DataGrid x:Name="ExtSegments"/>
                </GroupBox>
                <GroupBox Grid.Row="1">
                    <GroupBox.Header>
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="Pausen und Sperrzeiten" Foreground="#FFEDF2F7" VerticalAlignment="Center"/>
                            <Button x:Name="BtnPrivacyEye" Width="28" Height="20" MinWidth="0" Padding="0" Margin="8,0,0,0"
                                    Background="Transparent" BorderThickness="0" ToolTip="Pausen- und Sperrzeiten anzeigen">
                                <Grid>
                                    <Path Stroke="#FFAAB8C6" StrokeThickness="1.3" Fill="Transparent" Stretch="Uniform" Width="16" Height="11"
                                          Data="M 1,6 C 4,1.5 10,1.5 13,6 C 10,10.5 4,10.5 1,6 Z M 7,4.2 A 1.8,1.8 0 1 0 7,7.8 A 1.8,1.8 0 1 0 7,4.2"/>
                                    <Path x:Name="PathEyeStrike" Stroke="#FFAAB8C6" StrokeThickness="1.3" Stretch="Uniform" Width="16" Height="11"
                                          Data="M 1.5,11 L 12.5,1"/>
                                </Grid>
                            </Button>
                        </StackPanel>
                    </GroupBox.Header>
                    <DataGrid x:Name="ExtPauses"/>
                </GroupBox>
            </Grid>
        </Grid>
        <StackPanel Grid.Row="2" Margin="0,10,0,0">
            <StackPanel Orientation="Horizontal">
                <Button x:Name="BtnStartDay" Content="Arbeitstag starten" Width="160"/>
                <Button x:Name="BtnEndDay" Content="Arbeitstag beenden" Width="160"/>
                <Border Width="1" Background="#FF44506A" Margin="4,2,12,10"/>
                <Button x:Name="BtnSwitchMode" Content="Modus wechseln" Width="160"/>
                <Button x:Name="BtnPause" Content="Pause starten" Width="160"/>
                <Button x:Name="BtnComment" Content="Kommentar..." Width="160"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal">
                <Button x:Name="BtnAddSegment" Content="Abschnitt hinzufügen" Width="160"/>
                <Button x:Name="BtnEditDay" Content="Tag bearbeiten" Width="160"/>
                <Border Width="1" Background="#FF44506A" Margin="4,2,12,10"/>
                <Button x:Name="BtnHistory" Content="Verlauf" Width="160"/>
                <Button x:Name="BtnExport" Content="Export" Width="160"/>
                <Button x:Name="BtnSettings" Content="Einstellungen" Width="160"/>
            </StackPanel>
        </StackPanel>
    </Grid>
</Window>
'@

# Tabelle der Arbeitsabschnitte fuer die DataGrid-Anzeige. Die Werte werden
# rein fuer die ANZEIGE berechnet (Get-SegmentDisplayRows) - auch das laufende
# Segment zeigt damit stets aktuelles Brutto/Netto, ohne Segmentdaten zu
# veraendern oder einen Speichervorgang auszuloesen.
function Get-SegmentsTable {
    param([Parameter(Mandatory)]$Day, $Comp = $null, [datetime]$Now = (Get-Date))
    $dt = New-Object System.Data.DataTable
    foreach ($col in @('Modus', 'Beginn', 'Ende', 'Brutto', 'Pause', 'Netto', 'Laufend', 'Manuell', 'Korrigiert', 'Kommentar')) {
        [void]$dt.Columns.Add($col)
    }
    foreach ($row in (Get-SegmentDisplayRows -Day $Day -Comp $Comp -Now $Now)) {
        [void]$dt.Rows.Add($row.Modus, $row.Beginn, $row.Ende, $row.Brutto, $row.Pause, $row.Netto,
            $row.Laufend, $row.Manuell, $row.Korrigiert, $row.Kommentar)
    }
    return ,$dt
}

# Tabelle der Pausen-/Sperrintervalle inkl. der (nicht bearbeitbaren) festen Betriebspause
function Get-PausesTable {
    param([Parameter(Mandatory)]$Day, $Comp)
    $dt = New-Object System.Data.DataTable
    foreach ($col in @('Art', 'Beginn', 'Ende', 'Dauer', 'Kommentar')) { [void]$dt.Columns.Add($col) }
    $now = Get-Date
    foreach ($iv in @($Day.ManualPauses)) {
        $s = ConvertFrom-DateTimeString $iv.Start
        $e = $now
        $endText = 'läuft'
        if ($iv.End) { $e = ConvertFrom-DateTimeString $iv.End; $endText = Format-Clock $e }
        [void]$dt.Rows.Add('Manuelle Pause', (Format-Clock $s), $endText, (Format-Duration ($e - $s)), (Get-CommentPreview -Text (Get-ItemComment -Item $iv)))
    }
    foreach ($iv in @($Day.LockIntervals)) {
        $s = ConvertFrom-DateTimeString $iv.Start
        $e = $now
        $endText = 'läuft'
        if ($iv.End) { $e = ConvertFrom-DateTimeString $iv.End; $endText = Format-Clock $e }
        [void]$dt.Rows.Add('Windows-Sperre', (Format-Clock $s), $endText, (Format-Duration ($e - $s)), (Get-CommentPreview -Text (Get-ItemComment -Item $iv)))
    }
    if ($Comp) {
        foreach ($win in @($Comp.PauseWindows)) {
            if ($null -eq $win) { continue }
            [void]$dt.Rows.Add('Feste Betriebspause', (Format-Clock $win.Start), (Format-Clock $win.End), (Format-Duration ($win.End - $win.Start)), '')
        }
    }
    return ,$dt
}

# Sichtschutz: Kopie der Pausentabelle ohne konkrete Werte. Nur die Art
# bleibt lesbar; Zeiten und Kommentare werden durch neutrale Platzhalter
# ersetzt. Im verborgenen Zustand wird AUSSCHLIESSLICH diese Kopie an das
# Grid gebunden - die echten Werte gelangen so weder in die Darstellung noch
# in den Automation-Baum (Screenreader/UI Automation).
function Get-MaskedPausesTable {
    param([Parameter(Mandatory)][System.Data.DataTable]$Table)
    $masked = $Table.Clone()
    foreach ($row in $Table.Rows) {
        $comment = ''
        if ([string]$row['Kommentar'] -ne '') { $comment = '•••' }
        [void]$masked.Rows.Add([string]$row['Art'], '••:••', '••:••', '••:••', $comment)
    }
    return ,$masked
}

# Bindet die Pausentabelle der erweiterten Ansicht passend zum Sichtschutz
function Set-ExtendedPausesSource {
    $win = $script:App.Ui.Extended
    if ($null -eq $win) { return }
    $grid = $win.FindName('ExtPauses')
    if ($null -eq $grid) { return }
    $table = $script:App.Ui.ExtendedPauseTable
    if ($null -eq $table) { $grid.ItemsSource = $null; return }
    if ([bool]$script:App.UiPrivacy.PauseAndLockDetailsVisible) { $grid.ItemsSource = $table.DefaultView }
    else { $grid.ItemsSource = (Get-MaskedPausesTable -Table $table).DefaultView }
}

function Get-ExtendedValuesText {
    param($Comp, $Day)
    if ($null -eq $Day) { return "Kein aktiver Arbeitstag.`r`n`r`nÜber 'Arbeitstag starten' beginnen." }
    $lines = New-Object System.Collections.ArrayList
    $pausMark = ''
    if ($Comp.EndePausiert) { $pausMark = ' (pausiert)' }
    $sollEndeText = '--:--'
    if ($Comp.SollErreicht) { $sollEndeText = 'erreicht' }
    elseif ($Comp.SollEnde) { $sollEndeText = (Format-Clock $Comp.SollEnde) + $pausMark }
    $maxEndeText = '--:--'
    if ($Comp.MaxReached) { $maxEndeText = 'erreicht' }
    elseif ($Comp.MaxEnde) { $maxEndeText = (Format-Clock $Comp.MaxEnde) + $pausMark }
    $modusText = '-'
    if ($Comp.RunningMode) { $modusText = $Comp.RunningMode }

    [void]$lines.Add(('Datum              {0}' -f $Day.Date))
    [void]$lines.Add(('Beginn             {0}' -f (Format-Clock $Comp.Beginn)))
    [void]$lines.Add(('Ende               {0}' -f (Get-DayEndDisplayText -Day $Day -OpenText 'Offen')))
    [void]$lines.Add(('Aktueller Modus    {0}' -f $modusText))
    [void]$lines.Add('')
    [void]$lines.Add(('Netto gesamt       {0}' -f (Format-Duration $Comp.Netto)))
    [void]$lines.Add(('Regelarbeitszeit   {0}' -f (Format-Duration $Comp.Regular)))
    # Dynamische Anzeige: vor Erreichen der Sollzeit 'Soll-Rest', danach
    # 'Überstunden'. Die redundante Zeile 'Sollabweichung' (dieselbe
    # Information mit Vorzeichen) wurde bewusst entfernt; der interne
    # Berechnungswert (Totals.SollAbweichung) bleibt fuer Export/Verlauf erhalten.
    if ($Comp.SollErreicht) {
        [void]$lines.Add(('Überstunden        {0}' -f (Format-Duration $Comp.Ueberstunden -WithSign)))
    }
    else {
        [void]$lines.Add(('Soll-Rest          {0}' -f (Format-Duration $Comp.SollRest)))
    }
    [void]$lines.Add(('Max-Rest           {0}' -f (Format-Duration $Comp.MaxRest)))
    [void]$lines.Add('')
    [void]$lines.Add(('Soll-Ende          {0}' -f $sollEndeText))
    [void]$lines.Add(('Max-Ende           {0}' -f $maxEndeText))
    [void]$lines.Add('')
    [void]$lines.Add(('Betrieb brutto     {0}' -f (Format-Duration $Comp.BetriebBrutto)))
    [void]$lines.Add(('Betrieb netto      {0}' -f (Format-Duration $Comp.BetriebNetto)))
    [void]$lines.Add(('Feste Betriebspause {0}' -f (Format-Duration $Comp.FesteAbzug)))
    [void]$lines.Add(('Homeoffice netto   {0}' -f (Format-Duration $Comp.HoNetto)))
    # Sichtschutz: konkrete Pausen- und Sperrzeitwerte werden standardmaessig
    # nur maskiert angezeigt (neutraler Platzhalter in identischer Breite -
    # keine Groessen- oder Layoutaenderung). Die Werte selbst bleiben fuer die
    # Berechnung vollstaendig erhalten; die Beschriftungen bleiben sichtbar.
    $detailsVisible = $false
    if ($script:App -and $script:App.UiPrivacy) { $detailsVisible = [bool]$script:App.UiPrivacy.PauseAndLockDetailsVisible }
    $pauseText = Format-Duration $Comp.ManuellePause
    $lockText = Format-Duration $Comp.SperrZeit
    if (-not $detailsVisible) { $pauseText = '••:••'; $lockText = '••:••' }
    [void]$lines.Add(('Manuelle Pausen    {0}' -f $pauseText))
    [void]$lines.Add(('Sperrzeit          {0}' -f $lockText))
    return ($lines.ToArray() -join "`r`n")
}

function Get-DayStateText {
    param($Comp, $Day)
    if ($null -eq $Day) { return 'Kein aktiver Arbeitstag' }
    if ($Day.Status -eq 'Beendet') { return 'Arbeitstag beendet' }
    if ($Comp.MaxReached) { return 'MAXIMALE ARBEITSZEIT ERREICHT - Erfassung gestoppt' }
    if ($Comp.WarnActive) { return ('WARNUNG: 09:45 überschritten - noch ' + (Format-Duration $Comp.MaxRest) + ' bis 10:00') }
    if ($Comp.OpenPause) { return 'Manuelle Pause läuft' }
    if ($Comp.OpenLock) { return 'Windows gesperrt - Homeoffice pausiert' }
    if ($Comp.InFesterPause) { return 'Feste Betriebspause läuft' }
    if ($Comp.SollErreicht) { return ('Aktiv (' + $Comp.RunningMode + ') - Sollzeit erreicht') }
    if ($Comp.RunningMode) { return ('Aktiv - ' + $Comp.RunningMode) }
    return 'Aktiv - kein laufender Abschnitt'
}

function Update-ExtendedWindow {
    param($Comp, $Day, [switch]$Force)
    $win = $script:App.Ui.Extended
    if ($null -eq $win -or -not $win.IsVisible) { return }
    $win.FindName('ExtHeader').Text = Get-HeaderLineText
    $stateText = Get-DayStateText -Comp $Comp -Day $Day
    $statusBlock = $win.FindName('ExtStatus')
    $statusBlock.Text = $stateText
    $color = '#FF7FC97F'
    if ($null -eq $Day) { $color = '#FFAAB8C6' }
    elseif ($Day.Status -eq 'Beendet') { $color = '#FFAAB8C6' }
    elseif ($Comp.MaxReached) { $color = '#FFE05252' }
    elseif ($Comp.WarnActive) { $color = '#FFE0A030' }
    elseif ($Comp.OpenPause -or $Comp.OpenLock -or $Comp.InFesterPause) { $color = '#FF4A90D9' }
    $statusBlock.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($color))
    $win.FindName('ExtValues').Text = Get-ExtendedValuesText -Comp $Comp -Day $Day

    # Tabellen nur bei Datenaenderung vollstaendig neu aufbauen (Auswahl,
    # Scrollposition, Spaltenbreiten und Sortierung bleiben so erhalten).
    $stamp = ''
    if ($Day) { $stamp = [string]$Day.ModifiedAt + '|' + [string]$Day.Id }
    if ($Force -or $stamp -ne $script:App.Ui.ExtendedStamp) {
        $script:App.Ui.ExtendedStamp = $stamp
        $script:App.Ui.ExtendedSegTable = $null
        $script:App.Ui.ExtendedRunningRow = -1
        if ($Day) {
            $segTable = Get-SegmentsTable -Day $Day -Comp $Comp
            $win.FindName('ExtSegments').ItemsSource = $segTable.DefaultView
            $script:App.Ui.ExtendedPauseTable = Get-PausesTable -Day $Day -Comp $Comp
            Set-ExtendedPausesSource
            $script:App.Ui.ExtendedSegTable = $segTable
            for ($i = 0; $i -lt $segTable.Rows.Count; $i++) {
                if ([string]$segTable.Rows[$i]['Laufend'] -eq 'ja') { $script:App.Ui.ExtendedRunningRow = $i }
            }
        }
        else {
            $win.FindName('ExtSegments').ItemsSource = $null
            $script:App.Ui.ExtendedPauseTable = $null
            Set-ExtendedPausesSource
        }
    }
    elseif ($Day -and $null -ne $script:App.Ui.ExtendedSegTable -and $script:App.Ui.ExtendedRunningRow -ge 0) {
        # Laufende Aktualisierung des laufenden Segments im Sekundentakt des
        # Haupttimers: REINE Darstellung - nur die Zellen der laufenden Zeile
        # werden in der bestehenden DataTable aktualisiert (kein Neuaufbau,
        # keine Datenmutation, kein Save, kein Fokus-/Auswahlverlust).
        try {
            $rows = Get-SegmentDisplayRows -Day $Day -Comp $Comp
            $idx = [int]$script:App.Ui.ExtendedRunningRow
            $table = $script:App.Ui.ExtendedSegTable
            if ($idx -lt @($rows).Count -and $idx -lt $table.Rows.Count -and $rows[$idx].Running) {
                $tableRow = $table.Rows[$idx]
                foreach ($colName in @('Ende', 'Brutto', 'Pause', 'Netto')) {
                    if ([string]$tableRow[$colName] -ne [string]$rows[$idx][$colName]) {
                        $tableRow[$colName] = [string]$rows[$idx][$colName]
                    }
                }
            }
        }
        catch { }
    }

    # Kontextabhaengige Schaltflaechen
    $hasActive = ($Day -and $Day.Status -eq 'Aktiv')
    $win.FindName('BtnStartDay').IsEnabled = (-not $hasActive)
    $win.FindName('BtnSwitchMode').IsEnabled = ($hasActive -and $null -ne $Comp.RunningMode -and -not $Comp.MaxReached)
    $btnPause = $win.FindName('BtnPause')
    if ($hasActive -and $Comp.OpenPause) {
        $btnPause.Content = 'Pause beenden'
        $btnPause.IsEnabled = $true
    }
    else {
        $btnPause.Content = 'Pause starten'
        $btnPause.IsEnabled = ($hasActive -and $Comp.RunningMode -eq 'Homeoffice' -and -not $Comp.MaxReached)
    }
    $win.FindName('BtnAddSegment').IsEnabled = ($null -ne $Day)
    $win.FindName('BtnComment').IsEnabled = ($null -ne $Day)
    $win.FindName('BtnEditDay').IsEnabled = ($null -ne $Day)
    $win.FindName('BtnEndDay').IsEnabled = $hasActive
}

function Show-ExtendedWindow {
    if ($null -eq $script:App.Ui.Extended) {
        $win = New-XamlWindow -Xaml $script:ExtendedXaml
        $win.Title = "$($win.Title) (v$($script:AppVersion))"
        Add-DarkWindowChrome -Window $win
        $script:App.Ui.Extended = $win
        Register-ExtendedWindowEvents -Window $win
    }
    $win = $script:App.Ui.Extended
    # Standardzustand: Pausen-/Sperrzeit-Details sind beim Oeffnen IMMER verborgen
    Hide-PauseLockDetails
    if (-not $win.IsVisible) { $win.Show() }
    $win.Activate() | Out-Null
    Update-RadioUi
    Invoke-MainRefresh -ForceTables
}

#endregion


#region ===== Dialog-Grundlagen =====

function Show-Info {
    param([Parameter(Mandatory)][string]$Message, [string]$Title = 'ArbeitszeitTool')
    if ($script:TestMode) { return }
    [System.Windows.MessageBox]::Show($Message, $Title,
        [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
}

function Show-Warning {
    param([Parameter(Mandatory)][string]$Message, [string]$Title = 'ArbeitszeitTool - Warnung')
    if ($script:TestMode) {
        Write-AppLog -Level 'WARN' -Message ('(Testlauf) ' + $Message)
        return
    }
    [System.Windows.MessageBox]::Show($Message, $Title,
        [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
}

function Confirm-Question {
    param([Parameter(Mandatory)][string]$Message, [string]$Title = 'ArbeitszeitTool')
    if ($script:TestMode) { return $false }
    $result = [System.Windows.MessageBox]::Show($Message, $Title,
        [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    return ($result -eq [System.Windows.MessageBoxResult]::Yes)
}

function Set-DialogOwner {
    param([Parameter(Mandatory)]$Window)
    try {
        if ($script:App.Ui.Compact -and $script:App.Ui.Compact.IsVisible) {
            $Window.Owner = $script:App.Ui.Compact
            $Window.WindowStartupLocation = 'CenterOwner'
        }
    }
    catch { }
}

# HH:mm-Eingabe pruefen und mit dem Tagesdatum kombinieren. $null bei Fehler.
function Read-ValidatedTime {
    param(
        [string]$Text,
        [string]$FieldName = 'Uhrzeit',
        [datetime]$BaseDate = (Get-Date).Date
    )
    $trimmed = ([string]$Text).Trim()
    if (-not (Test-TimeText $trimmed)) {
        Show-Warning -Message "Die Eingabe '$trimmed' für '$FieldName' ist keine gültige Uhrzeit im Format HH:mm (z. B. 06:13)."
        return $null
    }
    $parts = $trimmed.Split(':')
    return $BaseDate.Date.AddHours([int]$parts[0]).AddMinutes([int]$parts[1])
}

# Plausibilitaet einer live eingetragenen Startzeit: Zukunft / grosse Zeitspanne.
# Keine stillschweigende Korrektur - der Benutzer entscheidet.
function Confirm-PlausibleTime {
    param([Parameter(Mandatory)][datetime]$Value, [string]$FieldName = 'Startzeit')
    $now = Get-Date
    if ($Value -gt $now.AddMinutes(1)) {
        return (Confirm-Question -Message "Die $FieldName $(Format-Clock $Value) liegt in der Zukunft. Trotzdem übernehmen?")
    }
    if (($now - $Value).TotalHours -gt 12) {
        return (Confirm-Question -Message "Die $FieldName $(Format-Clock $Value) liegt ungewöhnlich weit zurück (mehr als 12 Stunden). Trotzdem übernehmen?")
    }
    return $true
}

#endregion

#region ===== Dialog: Arbeitstag starten =====

$script:StartDayXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Arbeitstag starten" SizeToContent="Height" Width="380"
        Background="#FF171C24" WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Topmost="True">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <StackPanel Margin="16">
        <TextBlock Text="Arbeitsmodus:" FontWeight="Bold"/>
        <RadioButton x:Name="RbBetrieb" Content="Betrieb" IsChecked="True" Margin="0,6,0,0"/>
        <RadioButton x:Name="RbHomeoffice" Content="Homeoffice"/>
        <TextBlock Text="Arbeitsbeginn (HH:mm):" FontWeight="Bold" Margin="0,12,0,4"/>
        <TextBox x:Name="TxtStart" FontFamily="Consolas" FontSize="15"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button x:Name="BtnOk" Content="Starten" IsDefault="True"/>
            <Button x:Name="BtnCancel" Content="Abbrechen" IsCancel="True" Margin="0"/>
        </StackPanel>
    </StackPanel>
</Window>
'@

# Liefert @{ Mode; Start } oder $null bei Abbruch
function Show-StartDayDialog {
    $win = New-XamlWindow -Xaml $script:StartDayXaml
    Set-DialogOwner -Window $win
    $win.FindName('TxtStart').Text = (Get-Date).ToString('HH:mm')
    $state = @{ Result = $null }
    $win.FindName('BtnOk').Add_Click({
            $mode = 'Betrieb'
            if ($win.FindName('RbHomeoffice').IsChecked) { $mode = 'Homeoffice' }
            $start = Read-ValidatedTime -Text $win.FindName('TxtStart').Text -FieldName 'Arbeitsbeginn'
            if ($null -eq $start) { return }
            if (-not (Confirm-PlausibleTime -Value $start -FieldName 'Startzeit')) { return }
            $state.Result = @{ Mode = $mode; Start = $start }
            $win.DialogResult = $true
            $win.Close()
        })
    [void]$win.ShowDialog()
    return $state.Result
}

#endregion

#region ===== Dialog: nicht abgeschlossener Arbeitstag (Programmstart) =====

$script:ResumeXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Arbeitstag fortsetzen" SizeToContent="Height" Width="460"
        Background="#FF171C24" WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Topmost="True">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <StackPanel Margin="16">
        <TextBlock Text="Es existiert ein noch nicht abgeschlossener Arbeitstag:" FontWeight="Bold" TextWrapping="Wrap"/>
        <TextBox x:Name="TxtSummary" IsReadOnly="True" BorderThickness="0" Background="Transparent"
                 FontFamily="Consolas" Margin="0,8,0,8"/>
        <Button x:Name="BtnResume" Content="Fortsetzen (bisheriger Modus und Abschnitt laufen unverändert weiter)" Margin="0,0,0,6" HorizontalAlignment="Stretch"/>
        <Button x:Name="BtnSwitchMode" Content="Modus wechseln (bisherigen Abschnitt beenden, neuen beginnen)" Margin="0,0,0,6" HorizontalAlignment="Stretch"/>
        <Button x:Name="BtnEdit" Content="Bearbeiten" Margin="0,0,0,6" HorizontalAlignment="Stretch"/>
        <Button x:Name="BtnEnd" Content="Arbeitstag beenden" Margin="0,0,0,6" HorizontalAlignment="Stretch"/>
        <Button x:Name="BtnCancel" Content="Abbrechen" IsCancel="True" Margin="0" HorizontalAlignment="Stretch"/>
    </StackPanel>
</Window>
'@

# Liefert 'Fortsetzen' | 'ModusWechsel' | 'Bearbeiten' | 'Beenden' | 'Abbrechen'.
# "Fortsetzen" bedeutet IMMER: bisheriger Modus, bisheriger Abschnitt, keine
# neue Segment-ID. Ein neuer Abschnitt entsteht ausschliesslich ueber den
# ausdruecklichen Moduswechsel.
function Show-ResumeDialog {
    param([Parameter(Mandatory)][string]$SummaryText)
    $win = New-XamlWindow -Xaml $script:ResumeXaml
    $win.FindName('TxtSummary').Text = $SummaryText
    $state = @{ Result = 'Abbrechen' }
    $win.FindName('BtnResume').Add_Click({ $state.Result = 'Fortsetzen'; $win.Close() })
    $win.FindName('BtnSwitchMode').Add_Click({ $state.Result = 'ModusWechsel'; $win.Close() })
    $win.FindName('BtnEdit').Add_Click({ $state.Result = 'Bearbeiten'; $win.Close() })
    $win.FindName('BtnEnd').Add_Click({ $state.Result = 'Beenden'; $win.Close() })
    $win.FindName('BtnCancel').Add_Click({ $state.Result = 'Abbrechen'; $win.Close() })
    [void]$win.ShowDialog()
    return $state.Result
}

#endregion

#region ===== Dialog: nicht ordnungsgemaess beendeter Vortag (Review) =====

$script:AutoEndReviewXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Arbeitstag prüfen" SizeToContent="Height" Width="540"
        Background="#FF171C24" WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Topmost="True">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <StackPanel Margin="16">
        <TextBlock x:Name="TxtCaption" FontWeight="Bold" TextWrapping="Wrap"/>
        <TextBlock Text="Dieser Arbeitstag wurde nicht ordnungsgemäß beendet. Das automatische Ende wird nicht kommentarlos übernommen - bitte bestätigen oder korrigieren." TextWrapping="Wrap" Foreground="#FFAAB8C6" Margin="0,8,0,8"/>
        <TextBox x:Name="TxtDetail" IsReadOnly="True" BorderThickness="0" Background="Transparent"
                 FontFamily="Consolas" Margin="0,0,0,10"/>
        <Button x:Name="BtnConfirm" Content="10:00 Stunden bestätigen" Margin="0,0,0,6" HorizontalAlignment="Stretch"/>
        <Button x:Name="BtnManual" Content="Tatsächliches Arbeitsende übernehmen:" Margin="0,0,0,2" HorizontalAlignment="Stretch"/>
        <StackPanel Orientation="Horizontal" Margin="0,2,0,8">
            <TextBlock Text="Datum: " VerticalAlignment="Center"/>
            <TextBox x:Name="TxtEndDate" Width="100" FontFamily="Consolas"/>
            <TextBlock Text="  Uhrzeit: " VerticalAlignment="Center"/>
            <TextBox x:Name="TxtEndTime" Width="70" FontFamily="Consolas"/>
            <TextBlock Text="  (TT.MM.JJJJ / HH:mm - auch nach Mitternacht möglich)" Foreground="#FFAAB8C6" VerticalAlignment="Center" TextWrapping="Wrap"/>
        </StackPanel>
        <Button x:Name="BtnEdit" Content="Tag bearbeiten..." Margin="0,0,0,6" HorizontalAlignment="Stretch"/>
        <Button x:Name="BtnCancel" Content="Abbrechen" IsCancel="True" Margin="0" HorizontalAlignment="Stretch"/>
    </StackPanel>
</Window>
'@

# Liefert @{ Choice='Bestaetigen'|'ManuellesEnde'|'Bearbeiten'|'Abbrechen'; EndTime=[datetime] }.
# Das manuelle Ende wird als vollstaendiges Datum + Uhrzeit abgefragt, da das
# tatsaechliche Ende auch nach Mitternacht liegen kann.
function Show-AutoEndReviewDialog {
    param(
        [Parameter(Mandatory)]$Day,
        [Parameter(Mandatory)]$Comp,
        [Parameter(Mandatory)][datetime]$AssumedEnd,
        [bool]$TenReached = $true
    )
    $win = New-XamlWindow -Xaml $script:AutoEndReviewXaml
    $culture = [System.Globalization.CultureInfo]::GetCultureInfo('de-DE')
    $dayDate = [datetime]::ParseExact([string]$Day.Date, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    $win.FindName('TxtCaption').Text = ('Arbeitstag vom {0} prüfen' -f $dayDate.ToString('dddd, dd.MM.yyyy', $culture))
    $lines = @(
        ('Datum:                {0}' -f $dayDate.ToString('dd.MM.yyyy')),
        ('Arbeitsbeginn:        {0}' -f (Format-Clock $Comp.Beginn)),
        ('Bisherige Nettozeit:  {0}' -f (Format-Duration $Comp.Netto)),
        ('Angenommenes Ende:    {0}' -f $AssumedEnd.ToString('dd.MM.yyyy HH:mm'))
    )
    $win.FindName('TxtDetail').Text = ($lines -join "`r`n")
    if (-not $TenReached) {
        $win.FindName('BtnConfirm').Content = ('Angenommenes Ende bestätigen ({0})' -f $AssumedEnd.ToString('dd.MM.yyyy HH:mm'))
    }
    $win.FindName('TxtEndDate').Text = $AssumedEnd.ToString('dd.MM.yyyy')
    $win.FindName('TxtEndTime').Text = $AssumedEnd.ToString('HH:mm')
    $state = @{ Result = $null }
    $win.FindName('BtnConfirm').Add_Click({
            $state.Result = @{ Choice = 'Bestaetigen'; EndTime = $null }
            $win.Close()
        })
    $win.FindName('BtnManual').Add_Click({
            $deCulture = [System.Globalization.CultureInfo]::GetCultureInfo('de-DE')
            $endDate = $null
            try { $endDate = [datetime]::ParseExact(([string]$win.FindName('TxtEndDate').Text).Trim(), 'dd.MM.yyyy', $deCulture) }
            catch {
                Show-Warning -Message 'Bitte ein gültiges Datum im Format TT.MM.JJJJ angeben.'
                return
            }
            $timeText = ([string]$win.FindName('TxtEndTime').Text).Trim()
            if (-not (Test-TimeText $timeText)) {
                Show-Warning -Message "Die Eingabe '$timeText' ist keine gültige Uhrzeit im Format HH:mm."
                return
            }
            $parts = $timeText.Split(':')
            $end = $endDate.Date.AddHours([int]$parts[0]).AddMinutes([int]$parts[1])
            if ($end -gt (Get-Date)) {
                Show-Warning -Message 'Das Arbeitsende darf nicht in der Zukunft liegen.'
                return
            }
            $state.Result = @{ Choice = 'ManuellesEnde'; EndTime = $end }
            $win.Close()
        })
    $win.FindName('BtnEdit').Add_Click({ $state.Result = @{ Choice = 'Bearbeiten'; EndTime = $null }; $win.Close() })
    $win.FindName('BtnCancel').Add_Click({ $state.Result = @{ Choice = 'Abbrechen'; EndTime = $null }; $win.Close() })
    [void]$win.ShowDialog()
    if ($null -eq $state.Result) { return @{ Choice = 'Abbrechen'; EndTime = $null } }
    return $state.Result
}

# Fuehrt die ausdrueckliche Klaerung eines nicht ordnungsgemaess beendeten
# bzw. automatisch beendeten Vortags durch. Liefert $true, wenn der Tag
# vollstaendig geklaert wurde, sonst $false (Abbruch: kein neuer Arbeitstag,
# keine kommentarlose Aenderung, kein Review-Status als erledigt markiert).
#  -ChoiceResolver: nur fuer Tests - ersetzt den Dialog (erhaelt Day/Comp/
#   AssumedEnd und liefert dieselbe Struktur wie Show-AutoEndReviewDialog).
function Invoke-AutoEndReviewFlow {
    param(
        [Parameter(Mandatory)]$Day,
        [scriptblock]$ChoiceResolver = $null
    )
    while ($true) {
        $now = Get-Date
        $dayDate = [datetime]::ParseExact([string]$Day.Date, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        $cutoff = $dayDate.Date.AddDays(1)
        if ($cutoff -gt $now) { $cutoff = $now }
        $comp = Get-DayComputation -Day $Day -Now $cutoff
        # Vorschlag = letzter belegbarer Arbeitszeitpunkt (10:00-Grenze,
        # Abschnittsende oder Beginn einer bis zum Ende reichenden Sperre/
        # Pause) - nicht pauschal 00:00 des Folgetages nach dem Tageswechsel.
        $assumedEnd = Get-AutoEndSuggestedEnd -Day $Day -Cutoff $cutoff
        $tenReached = ($comp.Netto.TotalMinutes -ge ([int]$Day.MaxMinutes - 0.02))
        $choice = $null
        if ($null -ne $ChoiceResolver) { $choice = & $ChoiceResolver $Day $comp $assumedEnd }
        else { $choice = Show-AutoEndReviewDialog -Day $Day -Comp $comp -AssumedEnd $assumedEnd -TenReached $tenReached }
        switch ([string]$choice.Choice) {
            'Bestaetigen' {
                $err = Complete-AutoEndTenHours -Day $Day -Now $now -AssumedEnd $assumedEnd
                if ($err -eq '') { return $true }
                Show-Warning -Message $err
            }
            'ManuellesEnde' {
                $err = Complete-AutoEndManual -Day $Day -End $choice.EndTime -Now $now
                if ($err -eq '') { return $true }
                Show-Warning -Message $err
            }
            'Bearbeiten' {
                Show-DayEditor -Day $Day
                # Nach erfolgreicher Bearbeitung erneut pruefen; nur ein
                # vollstaendig und konsistent beendeter Tag gilt als geprueft.
                if (Test-DayReviewComplete -Day $Day) {
                    $snapshot = Get-DaySnapshot -Day $Day
                    $Day['AutoEndReviewPending'] = $false
                    $Day['AutoEndReviewed'] = $true
                    if (Save-WorkData) { return $true }
                    Restore-DayFromSnapshot -Day $Day -Snapshot $snapshot
                    Show-Warning -Message 'Der Prüfstatus konnte nicht gespeichert werden. Der vorherige Zustand wurde wiederhergestellt.'
                }
                # sonst: zurueck zur Klaerungsabfrage
            }
            default {
                # Abbrechen: keinen neuen Arbeitstag starten, den vorherigen
                # Tag nicht veraendern, Review-Status nicht als erledigt markieren.
                Write-AppLog -Message ("Klärung des Arbeitstags {0} vom Benutzer zurückgestellt." -f $Day.Date)
                return $false
            }
        }
    }
}

#endregion

#region ===== Dialog: Homeoffice-Luecke nach Neustart =====

$script:HoGapXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Homeoffice - Zeitraum ohne Aufzeichnung" SizeToContent="Height" Width="500"
        Background="#FF171C24" WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Topmost="True">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <StackPanel Margin="16">
        <TextBlock x:Name="TxtGapInfo" TextWrapping="Wrap" FontWeight="Bold"/>
        <TextBlock Text="Während die Anwendung nicht lief, konnten Sperren/Entsperren nicht erkannt werden. Wie soll der Zeitraum behandelt werden? (Es wird keine stille Annahme getroffen.)" TextWrapping="Wrap" Margin="0,8,0,10"/>
        <RadioButton x:Name="RbWork" Content="Vollständig als Arbeitszeit werten" IsChecked="True"/>
        <RadioButton x:Name="RbPause" Content="Vollständig als Pause werten"/>
        <RadioButton x:Name="RbLock" Content="Vollständig als Sperrzeit werten"/>
        <RadioButton x:Name="RbSplit" Content="Zeitraum manuell aufteilen:"/>
        <StackPanel Orientation="Horizontal" Margin="24,2,0,2">
            <TextBlock Text="Arbeitszeit bis (HH:mm): " VerticalAlignment="Center"/>
            <TextBox x:Name="TxtSplit" Width="70" FontFamily="Consolas"/>
            <TextBlock Text="  danach Pause" VerticalAlignment="Center"/>
        </StackPanel>
        <RadioButton x:Name="RbEndedAt" Content="Arbeitsabschnitt endete um:"/>
        <StackPanel Orientation="Horizontal" Margin="24,2,0,2">
            <TextBox x:Name="TxtEndedAt" Width="70" FontFamily="Consolas"/>
            <TextBlock Text="  (HH:mm) - der Tag bleibt offen, der Abschnitt wird beendet" VerticalAlignment="Center"/>
        </StackPanel>
        <RadioButton x:Name="RbEdit" Content="Aktuellen Abschnitt nachträglich bearbeiten (öffnet den Tages-Editor)"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
            <Button x:Name="BtnOk" Content="Übernehmen" IsDefault="True"/>
        </StackPanel>
    </StackPanel>
</Window>
'@

# Liefert @{ Choice='Arbeitszeit'|'Pause'|'Sperrzeit'|'Aufteilen'|'EndeteUm'|'Bearbeiten'; SplitTime=[datetime]; EndTime=[datetime] }
function Show-HoGapDialog {
    param([Parameter(Mandatory)][datetime]$GapStart, [Parameter(Mandatory)][datetime]$GapEnd)
    $win = New-XamlWindow -Xaml $script:HoGapXaml
    $win.FindName('TxtGapInfo').Text = 'Zeitraum: {0} bis {1} ({2})' -f (Format-Clock $GapStart), (Format-Clock $GapEnd), (Format-Duration ($GapEnd - $GapStart))
    $win.FindName('TxtSplit').Text = $GapStart.ToString('HH:mm')
    $win.FindName('TxtEndedAt').Text = $GapStart.ToString('HH:mm')
    $state = @{ Result = $null }
    $win.FindName('BtnOk').Add_Click({
            if ($win.FindName('RbPause').IsChecked) {
                $state.Result = @{ Choice = 'Pause'; SplitTime = $null; EndTime = $null }
            }
            elseif ($win.FindName('RbLock').IsChecked) {
                $state.Result = @{ Choice = 'Sperrzeit'; SplitTime = $null; EndTime = $null }
            }
            elseif ($win.FindName('RbSplit').IsChecked) {
                $split = Read-ValidatedTime -Text $win.FindName('TxtSplit').Text -FieldName 'Arbeitszeit bis' -BaseDate $GapStart.Date
                if ($null -eq $split) { return }
                if ($split -lt $GapStart -or $split -gt $GapEnd) {
                    Show-Warning -Message ("Die Aufteilungszeit muss zwischen {0} und {1} liegen." -f (Format-Clock $GapStart), (Format-Clock $GapEnd))
                    return
                }
                $state.Result = @{ Choice = 'Aufteilen'; SplitTime = $split; EndTime = $null }
            }
            elseif ($win.FindName('RbEndedAt').IsChecked) {
                $endedAt = Read-ValidatedTime -Text $win.FindName('TxtEndedAt').Text -FieldName 'Abschnittsende' -BaseDate $GapStart.Date
                if ($null -eq $endedAt) { return }
                if ($endedAt -lt $GapStart -or $endedAt -gt $GapEnd) {
                    Show-Warning -Message ("Das Abschnittsende muss zwischen {0} und {1} liegen." -f (Format-Clock $GapStart), (Format-Clock $GapEnd))
                    return
                }
                $state.Result = @{ Choice = 'EndeteUm'; SplitTime = $null; EndTime = $endedAt }
            }
            elseif ($win.FindName('RbEdit').IsChecked) {
                $state.Result = @{ Choice = 'Bearbeiten'; SplitTime = $null; EndTime = $null }
            }
            else {
                $state.Result = @{ Choice = 'Arbeitszeit'; SplitTime = $null; EndTime = $null }
            }
            $win.Close()
        })
    [void]$win.ShowDialog()
    if ($null -eq $state.Result) {
        # Dialog ueber X geschlossen -> keine stille Annahme, Standard = Nachbearbeitung
        return @{ Choice = 'Bearbeiten'; SplitTime = $null; EndTime = $null }
    }
    return $state.Result
}

#endregion

#region ===== Dialog: manuelle Pause lief beim Beenden noch =====

$script:PauseRecoveryXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Offene manuelle Pause" SizeToContent="Height" Width="480"
        Background="#FF171C24" WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Topmost="True">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <StackPanel Margin="16">
        <TextBlock x:Name="TxtInfo" TextWrapping="Wrap" FontWeight="Bold"/>
        <TextBlock Text="Wie soll die Pause behandelt werden?" Margin="0,8,0,10"/>
        <RadioButton x:Name="RbContinue" Content="Pause lief bis zum Neustart weiter (läuft jetzt weiter)" IsChecked="True"/>
        <RadioButton x:Name="RbEndedAt" Content="Pause endete um:"/>
        <StackPanel Orientation="Horizontal" Margin="24,2,0,2">
            <TextBox x:Name="TxtEndedAt" Width="70" FontFamily="Consolas"/>
            <TextBlock Text="  (HH:mm)" VerticalAlignment="Center"/>
        </StackPanel>
        <RadioButton x:Name="RbDiscard" Content="Pause verwerfen (Intervall löschen)"/>
        <RadioButton x:Name="RbEdit" Content="Manuell bearbeiten (öffnet den Tages-Editor)"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
            <Button x:Name="BtnOk" Content="Übernehmen" IsDefault="True"/>
        </StackPanel>
    </StackPanel>
</Window>
'@

# Liefert @{ Choice='Weiter'|'EndeteUm'|'Verwerfen'|'Bearbeiten'; EndTime=[datetime] }
function Show-PauseRecoveryDialog {
    param([Parameter(Mandatory)][datetime]$PauseStart)
    $win = New-XamlWindow -Xaml $script:PauseRecoveryXaml
    $win.FindName('TxtInfo').Text = 'Beim letzten Beenden der Anwendung lief noch eine manuelle Pause (Beginn: {0}).' -f (Format-Clock $PauseStart)
    $win.FindName('TxtEndedAt').Text = (Get-Date).ToString('HH:mm')
    $state = @{ Result = $null }
    $win.FindName('BtnOk').Add_Click({
            if ($win.FindName('RbEndedAt').IsChecked) {
                $end = Read-ValidatedTime -Text $win.FindName('TxtEndedAt').Text -FieldName 'Pausenende' -BaseDate $PauseStart.Date
                if ($null -eq $end) { return }
                if ($end -lt $PauseStart) {
                    Show-Warning -Message "Das Pausenende darf nicht vor dem Pausenbeginn ($(Format-Clock $PauseStart)) liegen."
                    return
                }
                $state.Result = @{ Choice = 'EndeteUm'; EndTime = $end }
            }
            elseif ($win.FindName('RbDiscard').IsChecked) { $state.Result = @{ Choice = 'Verwerfen'; EndTime = $null } }
            elseif ($win.FindName('RbEdit').IsChecked) { $state.Result = @{ Choice = 'Bearbeiten'; EndTime = $null } }
            else { $state.Result = @{ Choice = 'Weiter'; EndTime = $null } }
            $win.Close()
        })
    [void]$win.ShowDialog()
    if ($null -eq $state.Result) { return @{ Choice = 'Bearbeiten'; EndTime = $null } }
    return $state.Result
}

#endregion

#region ===== Dialog: Moduswechsel =====

$script:ModeSwitchXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Modus wechseln" SizeToContent="Height" Width="420"
        Background="#FF171C24" WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Topmost="True">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <StackPanel Margin="16">
        <TextBlock x:Name="TxtCurrent" FontWeight="Bold"/>
        <TextBlock Text="Neuer Modus:" Margin="0,10,0,2"/>
        <RadioButton x:Name="RbBetrieb" Content="Betrieb"/>
        <RadioButton x:Name="RbHomeoffice" Content="Homeoffice"/>
        <Grid Margin="0,10,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <TextBlock Grid.Row="0" Grid.Column="0" Text="Ende bisheriger Abschnitt (HH:mm):  " VerticalAlignment="Center"/>
            <TextBox Grid.Row="0" Grid.Column="1" x:Name="TxtEnd" Width="70" HorizontalAlignment="Left" FontFamily="Consolas"/>
            <TextBlock Grid.Row="1" Grid.Column="0" Text="Beginn neuer Abschnitt (HH:mm):  " VerticalAlignment="Center" Margin="0,6,0,0"/>
            <TextBox Grid.Row="1" Grid.Column="1" x:Name="TxtStart" Width="70" HorizontalAlignment="Left" FontFamily="Consolas" Margin="0,6,0,0"/>
        </Grid>
        <TextBlock Text="Liegt der neue Beginn nach dem Ende, gilt die Zeit dazwischen als Unterbrechung (keine Arbeitszeit)." TextWrapping="Wrap" Foreground="#FFAAB8C6" Margin="0,8,0,0"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
            <Button x:Name="BtnOk" Content="Wechseln" IsDefault="True"/>
            <Button x:Name="BtnCancel" Content="Abbrechen" IsCancel="True" Margin="0"/>
        </StackPanel>
    </StackPanel>
</Window>
'@

# Liefert @{ NewMode; End; Start } oder $null
function Show-ModeSwitchDialog {
    param([Parameter(Mandatory)]$Day, [Parameter(Mandatory)][string]$CurrentMode)
    $win = New-XamlWindow -Xaml $script:ModeSwitchXaml
    Set-DialogOwner -Window $win
    $win.FindName('TxtCurrent').Text = "Aktueller Modus: $CurrentMode"
    if ($CurrentMode -eq 'Betrieb') { $win.FindName('RbHomeoffice').IsChecked = $true }
    else { $win.FindName('RbBetrieb').IsChecked = $true }
    $nowText = (Get-Date).ToString('HH:mm')
    $win.FindName('TxtEnd').Text = $nowText
    $win.FindName('TxtStart').Text = $nowText
    $baseDate = [datetime]::ParseExact($Day.Date, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    $state = @{ Result = $null }
    $win.FindName('BtnOk').Add_Click({
            $newMode = 'Betrieb'
            if ($win.FindName('RbHomeoffice').IsChecked) { $newMode = 'Homeoffice' }
            $end = Read-ValidatedTime -Text $win.FindName('TxtEnd').Text -FieldName 'Ende bisheriger Abschnitt' -BaseDate $baseDate
            if ($null -eq $end) { return }
            $start = Read-ValidatedTime -Text $win.FindName('TxtStart').Text -FieldName 'Beginn neuer Abschnitt' -BaseDate $baseDate
            if ($null -eq $start) { return }
            if ($start -lt $end) {
                Show-Warning -Message 'Der Beginn des neuen Abschnitts darf nicht vor dem Ende des bisherigen Abschnitts liegen.'
                return
            }
            $runningStart = $null
            foreach ($seg in @($Day.Segments)) {
                if ($seg.Running) { $runningStart = ConvertFrom-DateTimeString $seg.Start }
            }
            if ($runningStart -and $end -lt $runningStart) {
                Show-Warning -Message "Das Ende darf nicht vor dem Beginn des laufenden Abschnitts ($(Format-Clock $runningStart)) liegen."
                return
            }
            if (-not (Confirm-PlausibleTime -Value $start -FieldName 'Beginnzeit')) { return }
            $state.Result = @{ NewMode = $newMode; End = $end; Start = $start }
            $win.DialogResult = $true
            $win.Close()
        })
    [void]$win.ShowDialog()
    return $state.Result
}

#endregion

#region ===== Zusammenfassung, Arbeitstag beenden, Anwendung schließen =====

function Get-DaySummaryText {
    param([Parameter(Mandatory)]$Day, [datetime]$Now = (Get-Date))
    $comp = Get-DayComputation -Day $Day -Now $Now
    $culture = [System.Globalization.CultureInfo]::GetCultureInfo('de-DE')
    $dayDate = [datetime]::ParseExact($Day.Date, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    $endText = Get-DayEndDisplayText -Day $Day -OpenText 'noch offen'
    $abweichung = $comp.Netto - $comp.Regular
    $maxText = 'nein'
    if ($comp.MaxReached) { $maxText = 'ja' }
    $lines = @(
        ('Datum:               {0}' -f $dayDate.ToString('dddd, dd.MM.yyyy', $culture)),
        ('Arbeitsbeginn:       {0}' -f (Format-Clock $comp.Beginn)),
        ('Arbeitsende:         {0}' -f $endText),
        ('Betriebszeit:        {0}' -f (Format-Duration $comp.BetriebNetto)),
        ('Homeoffice-Zeit:     {0}' -f (Format-Duration $comp.HoNetto)),
        ('Pausenzeit:          {0}  (fest {1}, manuell {2})' -f (Format-Duration ($comp.FesteAbzug + $comp.ManuellePause)), (Format-Duration $comp.FesteAbzug), (Format-Duration $comp.ManuellePause)),
        ('Sperrzeit:           {0}' -f (Format-Duration $comp.SperrZeit)),
        ('Netto-Arbeitszeit:   {0}' -f (Format-Duration $comp.Netto)),
        ('Sollzeit:            {0}' -f (Format-Duration $comp.Regular)),
        ('Plus/Minus:          {0}' -f (Format-Duration $abweichung -WithSign:($abweichung.Ticks -ge 0))),
        ('Max. Zeit erreicht:  {0}' -f $maxText)
    )
    return ($lines -join "`r`n")
}

$script:EndDayXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Arbeitstag beenden" SizeToContent="Height" Width="480"
        Background="#FF171C24" WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Topmost="True">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <StackPanel Margin="16">
        <TextBlock Text="Zusammenfassung des Arbeitstages:" FontWeight="Bold"/>
        <TextBox x:Name="TxtSummary" IsReadOnly="True" BorderThickness="0" Background="Transparent"
                 FontFamily="Consolas" Margin="0,8,0,8"/>
        <StackPanel Orientation="Horizontal">
            <TextBlock Text="Arbeitsende (HH:mm):  " VerticalAlignment="Center"/>
            <TextBox x:Name="TxtEnd" Width="70" FontFamily="Consolas"/>
        </StackPanel>
        <Button x:Name="BtnOk" Content="Arbeitstag beenden" IsDefault="True" Margin="0,14,0,6" HorizontalAlignment="Stretch"/>
        <Button x:Name="BtnOkShutdown" Content="Arbeitstag beenden und PC herunterfahren" Visibility="Collapsed" Margin="0,0,0,6" HorizontalAlignment="Stretch"/>
        <Button x:Name="BtnCancel" Content="Abbrechen" IsCancel="True" Margin="0" HorizontalAlignment="Stretch"/>
    </StackPanel>
</Window>
'@

# Liefert @{ End = [datetime]; Shutdown = [bool] } oder $null bei Abbruch.
# Die Aktion "Arbeitstag beenden und PC herunterfahren" erscheint NUR bei
# aktivierter Opt-in-Einstellung (und nie mit -NoShutdownOption); die normale
# Aktion "Arbeitstag beenden" faehrt den PC niemals herunter. Die Auswahl
# gilt nur fuer diesen Tagesabschluss und wird nicht vorausgewaehlt.
function Show-EndDayDialog {
    param(
        [Parameter(Mandatory)]$Day,
        [switch]$NoShutdownOption
    )
    $win = New-XamlWindow -Xaml $script:EndDayXaml
    Set-DialogOwner -Window $win
    $now = Get-Date
    $win.FindName('TxtSummary').Text = Get-DaySummaryText -Day $Day -Now $now
    $win.FindName('TxtEnd').Text = $now.ToString('HH:mm')
    if (-not $NoShutdownOption -and [bool]$script:App.Settings['ShutdownOfferEnabled']) {
        $win.FindName('BtnOkShutdown').Visibility = 'Visible'
    }
    $baseDate = [datetime]::ParseExact($Day.Date, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    $state = @{ Result = $null }
    $acceptEnd = {
        param([bool]$WithShutdown)
        $end = Read-ValidatedTime -Text $win.FindName('TxtEnd').Text -FieldName 'Arbeitsende' -BaseDate $baseDate
        if ($null -eq $end) { return }
        $comp = Get-DayComputation -Day $Day -Now (Get-Date)
        if ($comp.Beginn -and $end -lt $comp.Beginn) {
            Show-Warning -Message "Das Arbeitsende darf nicht vor dem Arbeitsbeginn ($(Format-Clock $comp.Beginn)) liegen."
            return
        }
        # Vollstaendige Abschlussvalidierung (keine stille Korrektur); ueber das
        # Arbeitsende hinausreichende Pausen-/Sperrintervalle kappt der
        # anschliessende Complete-WorkDay -TrimTrailingIntervals am Ende.
        $endError = Test-DayEndTime -Day $Day -End $end -TrimTrailingIntervals
        if ($endError -ne '') {
            Show-Warning -Message $endError
            return
        }
        $state.Result = @{ End = $end; Shutdown = $WithShutdown }
        $win.DialogResult = $true
        $win.Close()
    }
    $win.FindName('BtnOk').Add_Click({ & $acceptEnd $false })
    $win.FindName('BtnOkShutdown').Add_Click({ & $acceptEnd $true })
    [void]$win.ShowDialog()
    return $state.Result
}

# --- Optionaler PC-Shutdown nach Tagesabschluss (Opt-in) ---------------------

$script:ShutdownConst = @{ DelaySeconds = 5 }

# Der eigentliche Windows-Aufruf ist als Skriptblock injizierbar und
# ueberschreibbar (Tests ersetzen ihn vollstaendig). Es werden ausschliesslich
# feste, nicht benutzergesteuerte Argumente verwendet - niemals Werte aus
# Arbeitszeitdaten oder Einstellungen, kein Shell-Stringbuilding.
$script:WindowsShutdownCommand = {
    param([int]$DelaySeconds)
    $exe = Join-Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::System)) 'shutdown.exe'
    Start-Process -FilePath $exe -ArgumentList @('/s', '/t', [string]$DelaySeconds) -WindowStyle Hidden | Out-Null
}

# Fordert das Windows-Herunterfahren mit kurzer fester Verzoegerung an, damit
# die Anwendung kontrolliert schliessen kann. Automatische Tests loesen
# NIEMALS einen echten Shutdown aus - im Testmodus wird ausschliesslich ein
# Simulationsflag gesetzt. Liefert $true bei erfolgreich gestartetem Vorgang.
function Invoke-WindowsShutdownRequest {
    param([int]$DelaySeconds = -1)
    if ($DelaySeconds -lt 0) { $DelaySeconds = [int]$script:ShutdownConst.DelaySeconds }
    if ($script:TestMode) {
        # Automatische Tests loesen NIEMALS einen echten Shutdown aus. Ueber
        # SimulatedShutdownStartFails kann zusaetzlich der Fehlpfad
        # (shutdown.exe nicht startbar) gefahrlos simuliert werden.
        if ($script:App -and $script:App.Flags -and $script:App.Flags.SimulatedShutdownStartFails) { return $false }
        if ($script:App -and $script:App.Flags) {
            $script:App.Flags.SimulatedShutdownRequested = $true
            $script:App.Flags.SimulatedShutdownRequestCount++
        }
        return $true
    }
    try {
        & $script:WindowsShutdownCommand $DelaySeconds
        return $true
    }
    catch {
        Write-AppLog -Level 'ERROR' -Message ('Windows-Herunterfahren konnte nicht angefordert werden: ' + $_.Exception.Message)
        return $false
    }
}

# Gemeinsamer sicherer technischer Shutdownablauf fuer BEIDE Einstiege
# (Tagesabschluss-Dialog und Dialog "Anwendung schliessen"). Ein evtl.
# aktiver Arbeitstag ist zu diesem Zeitpunkt bereits validiert, vollstaendig
# abgeschlossen, gespeichert und verifiziert - diese Funktion beendet
# niemals selbst einen Arbeitstag und wird nie mit offenem Tag aufgerufen.
# Sichere Reihenfolge: Fensterposition bestmoeglich sichern -> tatsaechlichen
# Radio-Wiedergabestatus uebernehmen -> CleanShutdown=true -> finaler
# Save-Vault (geprueft) -> Radio kontrolliert abbauen -> Shutdown-Anforderung
# -> ERST bei erfolgreich gestarteter Anforderung CloseConfirmed=true und
# kontrolliertes Schliessen. Bei Speicherfehler, Cloudkonflikt oder
# fehlgeschlagenem Start des Shutdownprozesses wird KEIN Shutdown ausgeloest;
# die Anwendung bleibt geoeffnet und bedienbar, CleanShutdown wird wieder
# false. Die Meldungstexte sind pro Einstieg parametrisierbar (mit/ohne
# beendeten Arbeitstag); der Ablauf selbst ist identisch.
function Invoke-SafeApplicationShutdown {
    param(
        [string]$DayStateShort = 'Der Arbeitstag ist korrekt beendet',
        [string]$DayStateSaved = 'Der Arbeitstag ist korrekt beendet und gespeichert',
        [string]$SuccessLogText = 'Arbeitstag beendet - Windows-Herunterfahren angefordert, die Anwendung wird geschlossen.'
    )
    if ($null -eq $script:App.Vault -or -not $script:VaultSession.Unlocked) { return $false }
    # Fensterposition bestmoeglich sichern (ein Fehler bricht den Ablauf
    # nicht ab; ohne echtes WPF-Fenster - z. B. im Testlauf - entfaellt dies)
    try {
        $compactWin = $script:App.Ui.Compact
        if ($compactWin -is [System.Windows.Window]) { Save-CompactWindowPlacement -Window $compactWin | Out-Null }
    }
    catch { }
    try { Set-RadioLastPlayingSetting | Out-Null } catch { }
    $script:App.Vault['CleanShutdown'] = $true
    if (-not (Save-Vault)) {
        $script:App.Vault['CleanShutdown'] = $false
        Show-Warning -Message ('Der PC wird NICHT heruntergefahren, weil der finale Speichervorgang fehlgeschlagen ist (z. B. Schreibfehler oder extern veränderte Tresordatei). ' +
            $DayStateShort + '; die Anwendung bleibt geöffnet.')
        return $false
    }
    try { Clear-RadioPlayer } catch { }
    if (-not (Invoke-WindowsShutdownRequest)) {
        # Nur der Start von shutdown.exe ist fehlgeschlagen: Die Anwendung
        # bleibt geoeffnet und muss konsistent bedienbar bleiben. Der von
        # Clear-RadioPlayer gesetzte Shutdown-Sperrzustand wird deshalb
        # zurueckgenommen - Player und Handler wurden bereits sauber
        # abgebaut, ein NEUER Playerkontext ist damit wieder initialisierbar
        # (kein automatischer Neustart des Streams, kein alter Player und
        # keine alten Eventhandler werden wiederverwendet).
        try { $script:App.Radio.IsShuttingDown = $false } catch { }
        # Die Sitzung laeuft weiter: CleanShutdown=true waere jetzt FALSCH und
        # koennte bei einem spaeteren Absturz die Wiederherstellungsentscheidung
        # verfaelschen. Deshalb CleanShutdown zuruecksetzen und den korrigierten
        # Sitzungsstatus einmalig speichern (-NoTrackingCheckpoint wie beim
        # Sitzungsstart; -Quiet: genau EINE Meldung, keine Dialogschleife).
        # Der bereits gespeicherte Tagesabschluss wird dabei NICHT zurueckgerollt.
        $script:App.Vault['CleanShutdown'] = $false
        if (Save-Vault -NoTrackingCheckpoint -Quiet) {
            Show-Warning -Message ('Das Herunterfahren konnte nicht gestartet werden - der PC wird NICHT heruntergefahren. ' +
                $DayStateSaved + '; die Anwendung kann normal weiterverwendet oder geschlossen werden.')
        }
        else {
            # UnsavedChanges ist durch Save-Vault gesetzt; die begrenzte
            # automatische Wiederholung des Haupt-Timers laeuft. Keine
            # Erfolgsmeldung, keine Speicher- oder Dialogschleife.
            Write-AppLog -Level 'WARN' -Message 'Sitzungsstatus (CleanShutdown=false) nach fehlgeschlagenem Shutdownstart noch NICHT gespeichert - automatische Wiederholung läuft.'
            Show-Warning -Message ('Das Herunterfahren konnte nicht gestartet werden - der PC wird NICHT heruntergefahren. ' +
                $DayStateSaved + '. Der Sitzungsstatus konnte jedoch noch NICHT dauerhaft gespeichert werden; ' +
                'der Zustand wird als NICHT GESPEICHERT angezeigt und automatisch erneut versucht.')
        }
        return $false
    }
    Write-AppLog -Message $SuccessLogText
    $script:App.CloseConfirmed = $true
    try {
        if ($script:App.Ui.Compact) { $script:App.Ui.Compact.Close() }
        else { Stop-ApplicationDispatcher }
    }
    catch { Stop-ApplicationDispatcher }
    return $true
}

# Kompatibler Wrapper fuer den vorhandenen Tagesabschluss-Shutdown
# ("Arbeitstag beenden und PC herunterfahren"): Der Arbeitstag ist bereits
# validiert, abgeschlossen, gespeichert und verifiziert; hier folgt nur noch
# der gemeinsame sichere Shutdownablauf mit den unveraenderten Meldungen.
function Invoke-EndDayShutdown {
    return Invoke-SafeApplicationShutdown
}

$script:CloseAppXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Anwendung schließen" SizeToContent="Height" Width="480"
        Background="#FF171C24" WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Topmost="True">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <StackPanel Margin="16">
        <TextBlock x:Name="TxtTitle" Text="Zusammenfassung des aktuellen Tages:" FontWeight="Bold"/>
        <TextBox x:Name="TxtSummary" IsReadOnly="True" BorderThickness="0" Background="Transparent"
                 FontFamily="Consolas" Margin="0,8,0,8"/>
        <Button x:Name="BtnCloseOnly" Content="Nur Anwendung schließen (Arbeitstag bleibt offen)" Margin="0,0,0,6" HorizontalAlignment="Stretch"/>
        <Button x:Name="BtnEndAndClose" Content="Arbeitstag beenden und Anwendung schließen" Margin="0,0,0,6" HorizontalAlignment="Stretch"/>
        <TextBlock x:Name="TxtShutdownHint" Text="Der PC wird erst nach erfolgreichem Speichern heruntergefahren." Foreground="#FFAAB8C6" TextWrapping="Wrap" Visibility="Collapsed" Margin="0,4,0,4"/>
        <Button x:Name="BtnShutdownClose" Visibility="Collapsed" Margin="0,0,0,6" HorizontalAlignment="Stretch"/>
        <Button x:Name="BtnCancel" Content="Abbrechen" IsCancel="True" Margin="0" HorizontalAlignment="Stretch"/>
    </StackPanel>
</Window>
'@

# Liefert die Beschriftung der Shutdown-Auswahl des Schliessen-Dialogs oder
# $null, wenn die Auswahl nicht angeboten wird (ShutdownOfferEnabled=false).
# Die Beschriftung benennt bei aktivem Arbeitstag AUSDRUECKLICH auch den
# Tagesabschluss - es gibt keine Auswahl, die den PC mit offenem Arbeitstag
# herunterfaehrt.
function Get-CloseShutdownOfferText {
    param([bool]$HasActiveDay)
    if ($null -eq $script:App.Settings -or -not [bool]$script:App.Settings['ShutdownOfferEnabled']) { return $null }
    if ($HasActiveDay) { return 'Arbeitstag beenden, Anwendung schließen und PC herunterfahren' }
    return 'Anwendung schließen und PC herunterfahren'
}

# Liefert 'NurSchliessen' | 'BeendenUndSchliessen' |
# 'HerunterfahrenUndSchliessen' | 'Abbrechen'.
# Die Shutdown-Auswahl erscheint NUR bei aktivierter Opt-in-Einstellung
# ShutdownOfferEnabled (sonst vollstaendig ausgeblendet, kein reservierter
# Platz), ist nie die Standardschaltflaeche und nie vorausgewaehlt;
# "Abbrechen" bleibt per Escape/IsCancel erreichbar.
function Show-CloseAppDialog {
    param($Day)
    $win = New-XamlWindow -Xaml $script:CloseAppXaml
    Set-DialogOwner -Window $win
    if ($Day) {
        $win.FindName('TxtSummary').Text = Get-DaySummaryText -Day $Day
    }
    else {
        $win.FindName('TxtTitle').Text = 'Es läuft kein aktiver Arbeitstag.'
        $win.FindName('TxtSummary').Text = ''
        $win.FindName('BtnEndAndClose').IsEnabled = $false
    }
    $state = @{ Result = 'Abbrechen' }
    $win.FindName('BtnCloseOnly').Add_Click({ $state.Result = 'NurSchliessen'; $win.Close() })
    $win.FindName('BtnEndAndClose').Add_Click({ $state.Result = 'BeendenUndSchliessen'; $win.Close() })
    $win.FindName('BtnCancel').Add_Click({ $state.Result = 'Abbrechen'; $win.Close() })
    $shutdownText = Get-CloseShutdownOfferText -HasActiveDay ($null -ne $Day)
    if ($shutdownText) {
        $btnShutdown = $win.FindName('BtnShutdownClose')
        $btnShutdown.Content = $shutdownText
        $btnShutdown.Visibility = 'Visible'
        $win.FindName('TxtShutdownHint').Visibility = 'Visible'
        $btnShutdown.Add_Click({ $state.Result = 'HerunterfahrenUndSchliessen'; $win.Close() })
    }
    [void]$win.ShowDialog()
    return $state.Result
}

#endregion

#region ===== Dialog: Intervall bearbeiten (Abschnitte, Pausen, Sperrzeiten) =====

$script:IntervalEditXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Intervall bearbeiten" SizeToContent="Height" Width="400"
        Background="#FF171C24" WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Topmost="True">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <StackPanel Margin="16">
        <TextBlock x:Name="TxtCaption" FontWeight="Bold" Margin="0,0,0,8"/>
        <StackPanel x:Name="PnlMode">
            <TextBlock Text="Modus:"/>
            <RadioButton x:Name="RbBetrieb" Content="Betrieb"/>
            <RadioButton x:Name="RbHomeoffice" Content="Homeoffice"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
            <TextBlock Text="Beginn (HH:mm):  " VerticalAlignment="Center" Width="120"/>
            <TextBox x:Name="TxtStart" Width="70" FontFamily="Consolas"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" Margin="0,6,0,0">
            <TextBlock Text="Ende (HH:mm):  " VerticalAlignment="Center" Width="120"/>
            <TextBox x:Name="TxtEnd" Width="70" FontFamily="Consolas"/>
            <TextBlock x:Name="TxtEndHint" Text="  (leer = läuft noch)" Foreground="#FFAAB8C6" VerticalAlignment="Center"/>
        </StackPanel>
        <StackPanel x:Name="PnlItemComment" Margin="0,10,0,0">
            <TextBlock x:Name="TxtItemCommentLabel" Text="Kommentar zum Eintrag (optional):" TextWrapping="Wrap"/>
            <TextBox x:Name="TxtItemComment" AcceptsReturn="True" TextWrapping="Wrap" Height="60" Margin="0,4,0,0"
                     VerticalScrollBarVisibility="Auto" VerticalContentAlignment="Top"/>
        </StackPanel>
        <StackPanel x:Name="PnlComment" Margin="0,10,0,0">
            <TextBlock x:Name="TxtCommentLabel" Text="Kommentar (optional):" TextWrapping="Wrap"/>
            <TextBox x:Name="TxtComment" AcceptsReturn="True" TextWrapping="Wrap" Height="60" Margin="0,4,0,0"
                     VerticalScrollBarVisibility="Auto" VerticalContentAlignment="Top"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
            <Button x:Name="BtnOk" Content="Übernehmen" IsDefault="True"/>
            <Button x:Name="BtnCancel" Content="Abbrechen" IsCancel="True" Margin="0"/>
        </StackPanel>
    </StackPanel>
</Window>
'@

# Generischer Intervall-Editor.
# Liefert @{ Mode; Start=[datetime]; End=[datetime]/$null; Comment; ItemComment }
# oder $null bei Abbruch. Mit -CommentLabel erscheint ein optionales
# Kommentarfeld (z. B. Kommentar zum neuen Eintrag oder Begruendung einer
# Korrektur); mit -ItemCommentLabel zusaetzlich ein (vorbelegtes) Feld fuer
# den Kommentar des bearbeiteten Eintrags. Comment/ItemComment sind
# normalisiert ('' = kein Kommentar).
function Show-IntervalEditDialog {
    param(
        [Parameter(Mandatory)][string]$Caption,
        [Parameter(Mandatory)][datetime]$BaseDate,
        [string]$Mode = '',
        [string]$StartText = '',
        [string]$EndText = '',
        [switch]$ShowMode,
        [switch]$AllowEmptyEnd,
        [string]$CommentLabel = '',
        [string]$CommentText = '',
        [string]$ItemCommentLabel = '',
        [string]$ItemCommentText = ''
    )
    $win = New-XamlWindow -Xaml $script:IntervalEditXaml
    Set-DialogOwner -Window $win
    $win.FindName('TxtCaption').Text = $Caption
    if ($ShowMode) {
        if ($Mode -eq 'Homeoffice') { $win.FindName('RbHomeoffice').IsChecked = $true }
        else { $win.FindName('RbBetrieb').IsChecked = $true }
    }
    else {
        $win.FindName('PnlMode').Visibility = 'Collapsed'
    }
    if (-not $AllowEmptyEnd) { $win.FindName('TxtEndHint').Visibility = 'Collapsed' }
    $win.FindName('TxtStart').Text = $StartText
    $win.FindName('TxtEnd').Text = $EndText
    $win.FindName('TxtComment').MaxLength = [int]$script:CommentConst.MaxLength
    if ($CommentLabel -ne '') {
        $win.FindName('TxtCommentLabel').Text = $CommentLabel
        $win.FindName('TxtComment').Text = $CommentText
    }
    else {
        $win.FindName('PnlComment').Visibility = 'Collapsed'
    }
    $win.FindName('TxtItemComment').MaxLength = [int]$script:CommentConst.MaxLength
    if ($ItemCommentLabel -ne '') {
        $win.FindName('TxtItemCommentLabel').Text = $ItemCommentLabel
        $win.FindName('TxtItemComment').Text = $ItemCommentText
    }
    else {
        $win.FindName('PnlItemComment').Visibility = 'Collapsed'
    }
    $state = @{ Result = $null }
    $allowEmpty = [bool]$AllowEmptyEnd
    $showModeFlag = [bool]$ShowMode
    $win.FindName('BtnOk').Add_Click({
            $start = Read-ValidatedTime -Text $win.FindName('TxtStart').Text -FieldName 'Beginn' -BaseDate $BaseDate
            if ($null -eq $start) { return }
            $endInput = ([string]$win.FindName('TxtEnd').Text).Trim()
            $end = $null
            if ($endInput -ne '') {
                $end = Read-ValidatedTime -Text $endInput -FieldName 'Ende' -BaseDate $BaseDate
                if ($null -eq $end) { return }
                if ($end -lt $start) {
                    Show-Warning -Message 'Das Ende darf nicht vor dem Beginn liegen.'
                    return
                }
            }
            elseif (-not $allowEmpty) {
                Show-Warning -Message 'Bitte ein Ende im Format HH:mm angeben.'
                return
            }
            $selMode = ''
            if ($showModeFlag) {
                $selMode = 'Betrieb'
                if ($win.FindName('RbHomeoffice').IsChecked) { $selMode = 'Homeoffice' }
            }
            $state.Result = @{
                Mode        = $selMode
                Start       = $start
                End         = $end
                Comment     = (Get-NormalizedComment -Text ([string]$win.FindName('TxtComment').Text))
                ItemComment = (Get-NormalizedComment -Text ([string]$win.FindName('TxtItemComment').Text))
            }
            $win.DialogResult = $true
            $win.Close()
        })
    [void]$win.ShowDialog()
    return $state.Result
}

#endregion

#region ===== Dialog: Kommentar =====

$script:CommentXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Kommentar" SizeToContent="Height" Width="480"
        Background="#FF171C24" WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Topmost="True">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <StackPanel Margin="16">
        <TextBlock x:Name="TxtCaption" FontWeight="Bold" TextWrapping="Wrap" Margin="0,0,0,8"/>
        <StackPanel x:Name="PnlTargets" Margin="0,0,0,8"/>
        <TextBox x:Name="TxtComment" AcceptsReturn="True" AcceptsTab="False" TextWrapping="Wrap" Height="120"
                 VerticalScrollBarVisibility="Auto" VerticalContentAlignment="Top"/>
        <TextBlock x:Name="TxtCounter" Foreground="#FFAAB8C6" HorizontalAlignment="Right" Margin="0,4,0,0"/>
        <TextBlock Text="Kommentare werden verschlüsselt im Tresor gespeichert und verändern keine Arbeitszeiten. Leeres Feld = Kommentar entfernen." TextWrapping="Wrap" Foreground="#FFAAB8C6" Margin="0,4,0,0"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
            <Button x:Name="BtnOk" Content="Übernehmen"/>
            <Button x:Name="BtnCancel" Content="Abbrechen" IsCancel="True" Margin="0"/>
        </StackPanel>
    </StackPanel>
</Window>
'@

# Kommentar-Dialog fuer ein oder mehrere Ziele.
# $Targets: Liste von @{ Key; Label; Text } - bei mehr als einem Ziel wird
# per Optionsfeld gewaehlt; Eingaben je Ziel bleiben beim Umschalten erhalten.
# Liefert die GEAENDERTEN Ziele als Liste von @{ Key; Text } (normalisiert;
# leer = Kommentar entfernen) oder $null bei Abbruch.
function Show-CommentDialog {
    param(
        [Parameter(Mandatory)][string]$Caption,
        [Parameter(Mandatory)]$Targets,
        [string]$DefaultKey = ''
    )
    $targetList = @($Targets)
    if ($targetList.Count -eq 0) { return $null }
    $win = New-XamlWindow -Xaml $script:CommentXaml
    Set-DialogOwner -Window $win
    $win.FindName('TxtCaption').Text = $Caption
    $box = $win.FindName('TxtComment')
    $box.MaxLength = [int]$script:CommentConst.MaxLength
    $counter = $win.FindName('TxtCounter')
    $state = @{ Result = $null; Current = ''; Drafts = @{}; Original = @{} }
    foreach ($t in $targetList) {
        $state.Drafts[[string]$t.Key] = [string]$t.Text
        $state.Original[[string]$t.Key] = Get-NormalizedComment -Text ([string]$t.Text)
    }
    $updateCounter = {
        $counter.Text = '{0} / {1} Zeichen' -f $box.Text.Length, $box.MaxLength
    }
    $box.Add_TextChanged({ & $updateCounter })
    $select = {
        param([string]$Key)
        if ($state.Current -ne '') { $state.Drafts[$state.Current] = [string]$box.Text }
        $state.Current = $Key
        $box.Text = [string]$state.Drafts[$Key]
        $box.CaretIndex = $box.Text.Length
        & $updateCounter
    }
    if ($DefaultKey -eq '' -or -not $state.Drafts.ContainsKey($DefaultKey)) { $DefaultKey = [string]$targetList[0].Key }
    $panel = $win.FindName('PnlTargets')
    if ($targetList.Count -gt 1) {
        foreach ($t in $targetList) {
            $rb = New-Object System.Windows.Controls.RadioButton
            $rb.Content = [string]$t.Label
            $rb.GroupName = 'CommentTarget'
            $rb.Tag = [string]$t.Key
            $rb.Margin = New-Object System.Windows.Thickness(0, 0, 0, 2)
            $rb.IsChecked = ([string]$t.Key -eq $DefaultKey)
            $rb.Add_Checked({
                    param($sender, $e)
                    & $select ([string]$sender.Tag)
                })
            [void]$panel.Children.Add($rb)
        }
    }
    else {
        $panel.Visibility = 'Collapsed'
    }
    & $select $DefaultKey
    $win.FindName('BtnOk').Add_Click({
            $state.Drafts[$state.Current] = [string]$box.Text
            $changed = New-Object System.Collections.ArrayList
            foreach ($t in $targetList) {
                $key = [string]$t.Key
                $norm = Get-NormalizedComment -Text ([string]$state.Drafts[$key])
                if ($norm -ne $state.Original[$key]) { [void]$changed.Add(@{ Key = $key; Text = $norm }) }
            }
            $state.Result = $changed
            $win.DialogResult = $true
            $win.Close()
        })
    $box.Focus() | Out-Null
    [void]$win.ShowDialog()
    if ($null -eq $state.Result) { return $null }
    return ,$state.Result
}

# Ziele fuer den Kommentar zum aktuellen Arbeitstag: der Tag selbst, der
# laufende Abschnitt und eine laufende manuelle Pause. Liefert
# @{ Targets; DefaultKey; Items } - Items ordnet jedem Key das Objekt und
# eine Protokollbezeichnung zu. Standardziel ist eine laufende Pause, sonst
# der Tag. Reine Funktion (testbar).
function Get-CurrentDayCommentTargets {
    param([Parameter(Mandatory)]$Day)
    $targets = New-Object System.Collections.ArrayList
    $items = @{}
    [void]$targets.Add(@{ Key = 'Day'; Label = "Arbeitstag $($Day.Date)"; Text = (Get-ItemComment -Item $Day) })
    $items['Day'] = @{ Item = $Day; Label = 'Tag' }
    $default = 'Day'
    if ($Day.Status -eq 'Aktiv') {
        foreach ($seg in @($Day.Segments)) {
            if ($null -eq $seg -or -not [bool]$seg.Running) { continue }
            $label = 'Laufender Abschnitt: {0} seit {1}' -f $seg.Mode, (Format-Clock (ConvertFrom-DateTimeString $seg.Start))
            [void]$targets.Add(@{ Key = 'Segment'; Label = $label; Text = (Get-ItemComment -Item $seg) })
            $items['Segment'] = @{ Item = $seg; Label = "Abschnitt $($seg.Mode)" }
            break
        }
        foreach ($iv in @($Day.ManualPauses)) {
            if ($null -eq $iv -or $iv.End) { continue }
            $label = 'Laufende Pause seit {0}' -f (Format-Clock (ConvertFrom-DateTimeString $iv.Start))
            [void]$targets.Add(@{ Key = 'Pause'; Label = $label; Text = (Get-ItemComment -Item $iv) })
            $items['Pause'] = @{ Item = $iv; Label = 'Manuelle Pause' }
            $default = 'Pause'
            break
        }
    }
    return @{ Targets = $targets; DefaultKey = $default; Items = $items }
}

# Speichert die Ergebnisse des Kommentar-Dialogs (je Ziel transaktional).
# $Items ordnet jedem Key @{ Item; Label } zu (Get-CurrentDayCommentTargets).
# Nach einem fehlgeschlagenen Speichern wurde der Tag zurueckgerollt - die
# uebrigen Objektreferenzen sind dann veraltet, daher wird abgebrochen.
function Save-DayCommentResults {
    param([Parameter(Mandatory)]$Day, $Results, [Parameter(Mandatory)]$Items)
    foreach ($r in @($Results)) {
        if ($null -eq $r) { continue }
        $entry = $Items[[string]$r.Key]
        if ($null -eq $entry) { continue }
        if (-not (Set-DayItemCommentSaved -Day $Day -Item $entry.Item -Text ([string]$r.Text) -Label $entry.Label)) { return $false }
    }
    return $true
}

#endregion

#region ===== Dialog: Einstellungen =====

$script:CompactFieldDefs = [ordered]@{
    'Beginn'                   = 'Beginn'
    'Netto'                    = 'Netto-Arbeitszeit'
    'SollRestOderUeberstunden' = 'Soll-Rest / Überstunden (automatischer Wechsel)'
    'SollRest'                 = 'Soll-Rest (immer)'
    'Ueberstunden'             = 'Überstunden (immer)'
    'MaxRest'                  = 'Max-Rest'
    'SollEndeOderMaxEnde'      = 'Soll-Ende / Max-Ende (automatischer Wechsel)'
    'SollEnde'                 = 'Soll-Ende'
    'MaxEnde'                  = 'Max-Ende'
    'Modus'                    = 'Aktueller Modus'
    'Pausenstatus'             = 'Pausenstatus'
    'ScrollLock'               = 'Scroll-Lock-Aktivhaltung'
    'Warnstatus'               = 'Warnstatus'
}

# Fest eingebaute Presets der kompakten Ansicht. Sie sind weder loeschbar
# noch ueberschreibbar noch umbenennbar. 'Minimum' zeigt ausschliesslich
# neutrale Basisinformationen: aktuelle Uhrzeit, Datum und Kalenderwoche
# stehen IMMER in der Kopfzeile der kompakten Ansicht; als einziges Feld der
# Statuszeile bleibt der Warnstatus ('Status: OK/WARNUNG/MAX') sichtbar.
# Alle arbeitszeitbezogenen Detailwerte (Beginn, Netto, Soll-Rest,
# Überstunden, Soll-Ende, Max-Ende, Pausen, Sperrzeiten) sind ausgeblendet.
$script:CompactPresets = [ordered]@{
    'Standard'  = @('Beginn', 'Netto', 'SollRestOderUeberstunden', 'MaxEnde')
    'Klassisch' = @('Beginn', 'Netto', 'MaxRest', 'MaxEnde')
    'Minimum'   = @('Warnstatus')
}
$script:CompactPresetConst = @{
    MaxCustomPresets = 5
    MaxNameLength    = 40
}
$script:CompactPresetPrivacyHint = 'Das Minimum-Preset verbirgt Werte nur in der Oberfläche. Es ist keine Verschlüsselungs- oder Zugriffssperre.'

# Prueft einen Preset-Namen (getrimmt, nicht leer, max. 40 Zeichen, eindeutig
# ohne Beachtung der Gross-/Kleinschreibung, keine reservierten Namen der
# fest eingebauten Presets). Liefert '' oder eine Fehlermeldung.
function Test-CompactPresetName {
    param(
        [string]$Name,
        $ExistingPresets = $null,
        [string]$ExcludeId = ''
    )
    $trimmed = ([string]$Name).Trim()
    if ($trimmed -eq '') { return 'Der Preset-Name darf nicht leer sein.' }
    if ($trimmed.Length -gt $script:CompactPresetConst.MaxNameLength) {
        return ('Der Preset-Name darf höchstens {0} Zeichen lang sein.' -f $script:CompactPresetConst.MaxNameLength)
    }
    foreach ($reserved in @($script:CompactPresets.Keys)) {
        if ([string]::Equals($trimmed, [string]$reserved, [System.StringComparison]::OrdinalIgnoreCase)) {
            return ("Der Name '{0}' ist für ein fest eingebautes Preset reserviert." -f $trimmed)
        }
    }
    foreach ($p in @($ExistingPresets)) {
        if ($null -eq $p) { continue }
        if ([string]$p['Id'] -eq $ExcludeId) { continue }
        if ([string]::Equals($trimmed, ([string]$p['Name']).Trim(), [System.StringComparison]::OrdinalIgnoreCase)) {
            return 'Es existiert bereits ein eigenes Preset mit diesem Namen.'
        }
    }
    return ''
}

# Plausibilisiert geladene eigene Presets (rueckwaertskompatibel): unbekannte
# Feldnamen werden ignoriert, ungueltige Eintraege verworfen, hoechstens
# 5 Presets. Eine fehlende/leere Liste ergibt eine leere ArrayList.
function Get-ValidatedCompactPresets {
    param($Loaded)
    $result = New-Object System.Collections.ArrayList
    foreach ($p in @($Loaded)) {
        if ($result.Count -ge $script:CompactPresetConst.MaxCustomPresets) { break }
        if ($p -isnot [System.Collections.IDictionary]) { continue }
        $name = ([string]$p['Name']).Trim()
        if ((Test-CompactPresetName -Name $name -ExistingPresets $result) -ne '') { continue }
        $fields = New-Object System.Collections.ArrayList
        foreach ($f in @($p['Fields'])) {
            $key = [string]$f
            if ($script:CompactFieldDefs.Contains($key) -and $fields -notcontains $key) { [void]$fields.Add($key) }
        }
        if ($fields.Count -eq 0) { continue }
        $id = [string]$p['Id']
        if ([string]::IsNullOrWhiteSpace($id)) { $id = [guid]::NewGuid().ToString('N') }
        [void]$result.Add([ordered]@{ Id = $id; Name = $name; Fields = $fields })
    }
    return ,$result
}

# Aktiviert eine Feldauswahl (Preset) fuer die kompakte Ansicht. Reine
# Einstellungsaenderung: Arbeitszeitdaten werden nicht veraendert, es
# entsteht kein neuer Arbeitsabschnitt; das Fenster kann durch SizeToContent
# anschliessend auch wieder schrumpfen. Bei fehlgeschlagenem Speichern wird
# die vorherige Feldauswahl wiederhergestellt.
function Set-CompactFieldsPreset {
    param(
        [Parameter(Mandatory)]$Fields,
        [string]$PresetName = ''
    )
    $valid = New-Object System.Collections.ArrayList
    foreach ($f in @($Fields)) {
        $key = [string]$f
        if ($script:CompactFieldDefs.Contains($key) -and $valid -notcontains $key) { [void]$valid.Add($key) }
    }
    if ($valid.Count -eq 0) { return $false }
    $old = @($script:App.Settings['CompactFields'])
    $script:App.Settings['CompactFields'] = $valid
    if (-not (Save-Settings)) {
        $script:App.Settings['CompactFields'] = $old
        Update-CompactWindowLayout
        Invoke-MainRefresh
        return $false
    }
    if ($PresetName -ne '') {
        Write-AppLog -Message ("Preset '{0}' für die kompakte Ansicht aktiviert." -f $PresetName)
    }
    Update-CompactWindowLayout
    Invoke-MainRefresh
    return $true
}

# Hinweise zum Layout des Einstellungsfensters:
#  - Die Einstellungen sind in ein dunkles TabControl mit vier Bereichen
#    gegliedert (Allgemein / Kompakte Ansicht / Aktivhaltung / Internetradio) -
#    kein einziges langes vertikales Formular mehr.
#  - Feste sinnvolle Ausgangsgroesse (780 x 620 DIP) mit Min-Grenzen; die
#    maximale Hoehe wird beim Oeffnen auf den Monitor-Arbeitsbereich begrenzt
#    (Show-SettingsDialog). Das Fenster bleibt verkleinerbar.
#  - Jeder Tab besitzt bei Bedarf einen eigenen ScrollViewer; Speichern und
#    Abbrechen liegen AUSSERHALB der Tabs und bleiben immer sichtbar.
#  - Der Radio-Tab ist zweispaltig: links Senderliste mit Reihenfolge-/
#    Hinzufuegen-/Entfernen-Schaltflaechen (bei vielen Sendern scrollt die
#    LISTE, nicht das Fenster), rechts EIN gemeinsames Paar Bearbeitungs-
#    felder (Name/URL) plus Wiedergabeoptionen.
#  - Lange CheckBox-Beschriftungen sind TextBlocks mit TextWrapping="Wrap";
#    Preset- sowie Speichern-/Abbrechen-Schaltflaechen besitzen identische
#    Abmessungen (unveraenderte Testabdeckung).
#  - Beim Tabwechsel wird nichts gespeichert; erst "Speichern" uebernimmt
#    alle Aenderungen, "Abbrechen" verwirft sie in allen Tabs.
$script:SettingsXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Einstellungen" Width="780" Height="620" MinWidth="680" MinHeight="480"
        Background="#FF171C24" WindowStartupLocation="CenterScreen" ResizeMode="CanResize" Topmost="True">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TabControl Grid.Row="0" x:Name="TabSettings">
            <TabItem Header="Allgemein">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <Grid Margin="10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="1*"/>
                            <ColumnDefinition Width="1*"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel Grid.Column="0" Margin="0,0,10,0">
                            <GroupBox Header="Arbeitszeit">
                                <StackPanel>
                                    <StackPanel Orientation="Horizontal">
                                        <TextBlock Text="Regelarbeitszeit (HH:mm):  " VerticalAlignment="Center"/>
                                        <TextBox x:Name="TxtRegular" Width="70" FontFamily="Consolas"/>
                                    </StackPanel>
                                    <TextBlock Text="Fest (nicht änderbar): max. Arbeitszeit 10:00, Betriebspause 00:45 nach 06:00 Betrieb, Warnung ab 09:45." TextWrapping="Wrap" Foreground="#FFAAB8C6" Margin="0,8,0,0"/>
                                    <CheckBox x:Name="ChkWarn" Margin="0,8,0,3">
                                        <TextBlock Text="Deutliche Warnung ab 09:45 anzeigen" TextWrapping="Wrap"/>
                                    </CheckBox>
                                    <CheckBox x:Name="ChkSound">
                                        <TextBlock Text="Akustische Meldung bei 10:00 (Systemton)" TextWrapping="Wrap"/>
                                    </CheckBox>
                                    <CheckBox x:Name="ChkShutdownOffer">
                                        <TextBlock Text="Beim Beenden des Arbeitstags und beim Schließen der Anwendung Herunterfahren anbieten (die Auswahl gilt nur für den jeweiligen Vorgang)" TextWrapping="Wrap"/>
                                    </CheckBox>
                                </StackPanel>
                            </GroupBox>
                            <GroupBox Header="Sicherheit (Datentresor)">
                                <StackPanel>
                                    <Button x:Name="BtnChangePassword" Content="Verschlüsselungspasswort ändern..." HorizontalAlignment="Stretch" Margin="0,0,0,6"/>
                                    <Button x:Name="BtnShowLogs" Content="Verschlüsselte Protokolle anzeigen..." HorizontalAlignment="Stretch" Margin="0,0,0,6"/>
                                    <Button x:Name="BtnClearLogs" Content="Verschlüsselte Protokolle löschen..." HorizontalAlignment="Stretch" Margin="0,0,0,6"/>
                                    <Button x:Name="BtnStorageOverview" Content="Speicherbelegung anzeigen..." HorizontalAlignment="Stretch" Margin="0"/>
                                    <TextBlock Text="Alle Daten, Einstellungen und Protokolle liegen verschlüsselt im Datentresor. Das Passwort wird nicht gespeichert." TextWrapping="Wrap" Foreground="#FFAAB8C6" Margin="0,8,0,0"/>
                                </StackPanel>
                            </GroupBox>
                            <TextBlock x:Name="LblAppVersion" Text="" Foreground="#FFAAB8C6" Margin="0,10,0,0" HorizontalAlignment="Right"/>
                        </StackPanel>
                        <StackPanel Grid.Column="1">
                            <GroupBox Header="Fenster">
                                <StackPanel>
                                    <StackPanel Orientation="Horizontal">
                                        <TextBlock Text="Transparenz:  " VerticalAlignment="Center"/>
                                        <Slider x:Name="SldTransparency" Minimum="30" Maximum="100" Width="160" VerticalAlignment="Center" IsSnapToTickEnabled="True" TickFrequency="1"/>
                                        <TextBlock x:Name="LblTransparency" Text="" VerticalAlignment="Center" Margin="8,0,0,0"/>
                                    </StackPanel>
                                    <StackPanel Orientation="Horizontal" Margin="0,6,0,0">
                                        <TextBlock Text="Schriftgröße:  " VerticalAlignment="Center"/>
                                        <TextBox x:Name="TxtFontSize" Width="50" FontFamily="Consolas"/>
                                    </StackPanel>
                                    <CheckBox x:Name="ChkTopmost" Margin="0,8,0,3">
                                        <TextBlock Text="Immer im Vordergrund (Topmost)" TextWrapping="Wrap"/>
                                    </CheckBox>
                                    <CheckBox x:Name="ChkTopmostReassert">
                                        <TextBlock Text="Topmost regelmäßig erneut setzen (ohne Fokusdiebstahl)" TextWrapping="Wrap"/>
                                    </CheckBox>
                                    <CheckBox x:Name="ChkTray">
                                        <TextBlock Text="Symbol im Windows-Infobereich anzeigen" TextWrapping="Wrap"/>
                                    </CheckBox>
                                    <CheckBox x:Name="ChkSeconds">
                                        <TextBlock Text="Sekunden in der Uhrzeitanzeige" TextWrapping="Wrap"/>
                                    </CheckBox>
                                    <TextBlock Text="Startansicht:" Margin="0,8,0,0"/>
                                    <RadioButton x:Name="RbStartKompakt">
                                        <TextBlock Text="Kompakte Ansicht" TextWrapping="Wrap"/>
                                    </RadioButton>
                                    <RadioButton x:Name="RbStartErweitert">
                                        <TextBlock Text="Erweiterte Ansicht zusätzlich öffnen" TextWrapping="Wrap"/>
                                    </RadioButton>
                                </StackPanel>
                            </GroupBox>
                        </StackPanel>
                    </Grid>
                </ScrollViewer>
            </TabItem>
            <TabItem Header="Kompakte Ansicht">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <StackPanel Margin="10">
                        <GroupBox Header="Felder der kompakten Ansicht">
                            <StackPanel>
                                <TextBlock Text="Die kompakte Ansicht passt ihre Breite automatisch an die ausgewählten Felder an." TextWrapping="Wrap" Foreground="#FFAAB8C6" Margin="0,0,0,6"/>
                                <StackPanel x:Name="PnlFields"/>
                                <Grid Margin="0,8,0,0">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="1*"/>
                                        <ColumnDefinition Width="1*"/>
                                        <ColumnDefinition Width="1*"/>
                                    </Grid.ColumnDefinitions>
                                    <Button Grid.Column="0" x:Name="BtnPresetStandard" Content="Preset: Standard"
                                            MinWidth="0" Height="30" Margin="3,0,3,0" Padding="4,2" HorizontalAlignment="Stretch"/>
                                    <Button Grid.Column="1" x:Name="BtnPresetKlassisch" Content="Preset: Klassisch"
                                            MinWidth="0" Height="30" Margin="3,0,3,0" Padding="4,2" HorizontalAlignment="Stretch"/>
                                    <Button Grid.Column="2" x:Name="BtnPresetMinimum" Content="Preset: Minimum"
                                            MinWidth="0" Height="30" Margin="3,0,3,0" Padding="4,2" HorizontalAlignment="Stretch"
                                            ToolTip="Das Minimum-Preset verbirgt Werte nur in der Oberfläche. Es ist keine Verschlüsselungs- oder Zugriffssperre."/>
                                </Grid>
                                <TextBlock Text="Hinweis: Das Minimum-Preset (nur Uhrzeit, Datum, Kalenderwoche und Status) verbirgt Werte nur in der Oberfläche. Es ist keine Verschlüsselungs- oder Zugriffssperre." TextWrapping="Wrap" Foreground="#FFAAB8C6" Margin="0,6,0,0"/>
                            </StackPanel>
                        </GroupBox>
                        <GroupBox Header="Eigene Presets (max. 5)">
                            <StackPanel>
                                <TextBlock Text="Eigene Presets speichern eine Feldauswahl verschlüsselt im Datentresor. Übernommen wird erst mit 'Speichern'; 'Abbrechen' verwirft alle Presetänderungen." TextWrapping="Wrap" Foreground="#FFAAB8C6" Margin="0,0,0,6"/>
                                <ListBox x:Name="LstPresets" MinHeight="80" MaxHeight="140" Background="#FF10141B" Foreground="#FFEDF2F7" BorderBrush="#FF44506A"/>
                                <StackPanel Orientation="Horizontal" Margin="0,6,0,0">
                                    <TextBlock Text="Name (max. 40 Zeichen):  " VerticalAlignment="Center"/>
                                    <TextBox x:Name="TxtPresetName" Width="220" MaxLength="40"/>
                                </StackPanel>
                                <TextBlock x:Name="TxtPresetError" TextWrapping="Wrap" Foreground="#FFE05252" Margin="0,6,0,0" Visibility="Collapsed"/>
                                <Grid Margin="0,8,0,0">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="1*"/>
                                        <ColumnDefinition Width="1*"/>
                                        <ColumnDefinition Width="1*"/>
                                    </Grid.ColumnDefinitions>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                    </Grid.RowDefinitions>
                                    <Button Grid.Row="0" Grid.Column="0" x:Name="BtnPresetNew" Content="Neu (aktuelle Auswahl)" MinWidth="0" Height="28" Margin="0,0,3,4" Padding="2,2" HorizontalAlignment="Stretch"/>
                                    <Button Grid.Row="0" Grid.Column="1" x:Name="BtnPresetLoad" Content="Laden" MinWidth="0" Height="28" Margin="3,0,3,4" Padding="2,2" HorizontalAlignment="Stretch"/>
                                    <Button Grid.Row="0" Grid.Column="2" x:Name="BtnPresetOverwrite" Content="Überschreiben" MinWidth="0" Height="28" Margin="3,0,0,4" Padding="2,2" HorizontalAlignment="Stretch"/>
                                    <Button Grid.Row="1" Grid.Column="0" x:Name="BtnPresetRename" Content="Umbenennen" MinWidth="0" Height="28" Margin="0,0,3,0" Padding="2,2" HorizontalAlignment="Stretch"/>
                                    <Button Grid.Row="1" Grid.Column="1" x:Name="BtnPresetDelete" Content="Löschen" MinWidth="0" Height="28" Margin="3,0,3,0" Padding="2,2" HorizontalAlignment="Stretch"/>
                                </Grid>
                            </StackPanel>
                        </GroupBox>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
            <TabItem Header="Aktivhaltung">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <StackPanel Margin="10">
                        <GroupBox Header="Scroll-Lock-Aktivhaltung">
                            <StackPanel>
                                <CheckBox x:Name="ChkKeepAlive">
                                    <TextBlock Text="Aktivhaltung aktiv (Standard: aus)" TextWrapping="Wrap"/>
                                </CheckBox>
                                <StackPanel Orientation="Horizontal" Margin="0,6,0,0">
                                    <TextBlock Text="Intervall (Sekunden):  " VerticalAlignment="Center"/>
                                    <TextBox x:Name="TxtKeepAliveInterval" Width="60" FontFamily="Consolas"/>
                                </StackPanel>
                                <TextBlock Text="Die Aktivhaltung sendet in jedem Intervall einen kurzen Scroll-Lock-Doppelpuls (Taste kurz umschalten und wieder zurück), damit der Rechner als aktiv gilt. Es findet keine Zustandsabfrage statt; Fehler werden nur im verschlüsselten Protokoll erfasst. Hinweis: Bei einem harten Absturz exakt zwischen den beiden Tastendrücken kann die Rollen-Taste verändert bleiben. Die Nutzung muss mit den betrieblichen Vorgaben vereinbar sein." TextWrapping="Wrap" Foreground="#FFAAB8C6" Margin="0,10,0,0"/>
                            </StackPanel>
                        </GroupBox>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
            <TabItem Header="Internetradio">
                <Grid Margin="10">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="1*"/>
                        <ColumnDefinition Width="1.2*"/>
                    </Grid.ColumnDefinitions>
                    <Grid Grid.Column="0" Margin="0,0,10,0">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <TextBlock Grid.Row="0" Text="Senderliste (bei vielen Sendern scrollt die Liste):" TextWrapping="Wrap" Margin="0,0,0,4"/>
                        <ListBox Grid.Row="1" x:Name="LstRadioStations" MinHeight="140" Background="#FF10141B" Foreground="#FFEDF2F7" BorderBrush="#FF44506A"/>
                        <Grid Grid.Row="2" Margin="0,6,0,0">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="1*"/>
                                <ColumnDefinition Width="1*"/>
                            </Grid.ColumnDefinitions>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <Button Grid.Row="0" Grid.Column="0" x:Name="BtnRadioUp" Content="Nach oben" MinWidth="0" Height="28" Margin="0,0,3,4" Padding="2,2" HorizontalAlignment="Stretch"/>
                            <Button Grid.Row="0" Grid.Column="1" x:Name="BtnRadioDown" Content="Nach unten" MinWidth="0" Height="28" Margin="3,0,0,4" Padding="2,2" HorizontalAlignment="Stretch"/>
                            <Button Grid.Row="1" Grid.Column="0" x:Name="BtnRadioAdd" Content="Hinzufügen" MinWidth="0" Height="28" Margin="0,0,3,0" Padding="2,2" HorizontalAlignment="Stretch"/>
                            <Button Grid.Row="1" Grid.Column="1" x:Name="BtnRadioRemove" Content="Entfernen" MinWidth="0" Height="28" Margin="3,0,0,0" Padding="2,2" HorizontalAlignment="Stretch"/>
                        </Grid>
                    </Grid>
                    <ScrollViewer Grid.Column="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                        <StackPanel>
                            <TextBlock Text="Name (max. 80 Zeichen):"/>
                            <TextBox x:Name="TxtRadioName" MaxLength="80" Margin="0,4,0,0"/>
                            <TextBlock Text="Stream-URL (http/https, ohne Zugangsdaten):" Margin="0,8,0,0" TextWrapping="Wrap"/>
                            <TextBox x:Name="TxtRadioUrl" MaxLength="2048" Margin="0,4,0,0"/>
                            <TextBlock x:Name="TxtRadioEditError" TextWrapping="Wrap" Foreground="#FFE05252" Margin="0,6,0,0" Visibility="Collapsed"/>
                            <Grid Margin="0,8,0,0">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="1*"/>
                                    <ColumnDefinition Width="1*"/>
                                </Grid.ColumnDefinitions>
                                <Button Grid.Column="0" x:Name="BtnRadioApply" Content="Übernehmen" MinWidth="0" Height="28" Margin="0,0,3,0" Padding="2,2" HorizontalAlignment="Stretch" ToolTip="Übernimmt Name und URL in den links ausgewählten Sender"/>
                                <Button Grid.Column="1" x:Name="BtnRadioDefault" Content="Als Standard" MinWidth="0" Height="28" Margin="3,0,0,0" Padding="2,2" HorizontalAlignment="Stretch" ToolTip="Legt den links ausgewählten Sender als Standardsender fest"/>
                            </Grid>
                            <StackPanel Orientation="Horizontal" Margin="0,12,0,0">
                                <TextBlock Text="Lautstärke (0-100):  " VerticalAlignment="Center"/>
                                <TextBox x:Name="TxtRadioVolume" Width="50" FontFamily="Consolas"/>
                            </StackPanel>
                            <CheckBox x:Name="ChkRadioResume" Margin="0,10,0,3">
                                <TextBlock Text="Wiedergabe nach dem Entsperren automatisch fortsetzen (wenn sie vor dem Sperren lief)" TextWrapping="Wrap"/>
                            </CheckBox>
                            <CheckBox x:Name="ChkRadioRemember">
                                <TextBlock Text="Wiedergabestatus beim Beenden merken und beim nächsten Start fortsetzen" TextWrapping="Wrap"/>
                            </CheckBox>
                            <TextBlock Text="Hinweis: http-Streams sind nicht transportverschlüsselt. Es wird ausschließlich der gewählte Radiostream abgerufen - Arbeitszeitdaten, Einstellungen und Protokolle werden nicht übertragen." TextWrapping="Wrap" Foreground="#FFAAB8C6" Margin="0,10,0,0"/>
                        </StackPanel>
                    </ScrollViewer>
                </Grid>
            </TabItem>
        </TabControl>
        <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
            <Button x:Name="BtnOk" Content="Speichern" IsDefault="True" Width="120" Height="30" Margin="0,0,8,0" Padding="4,2"/>
            <Button x:Name="BtnCancel" Content="Abbrechen" IsCancel="True" Width="120" Height="30" Margin="0" Padding="4,2"/>
        </StackPanel>
    </Grid>
</Window>
'@

# Erzeugt ein Kontrollkaestchen, dessen Beschriftung ein TextBlock mit
# TextWrapping="Wrap" ist: lange Texte brechen um, statt rechts abgeschnitten
# zu werden. Wird fuer die dynamisch erzeugten Felder der kompakten Ansicht
# verwendet und von den internen Tests geprueft.
function New-WrappedCheckBox {
    param([Parameter(Mandatory)][string]$Text)
    $chk = New-Object System.Windows.Controls.CheckBox
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $Text
    $tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $chk.Content = $tb
    return $chk
}

function Show-SettingsDialog {
    $win = New-XamlWindow -Xaml $script:SettingsXaml
    Add-DarkWindowChrome -Window $win
    Set-DialogOwner -Window $win
    # Falls die notwendige Hoehe den Bildschirm ueberschreitet (z. B. bei
    # 150 % Skalierung), begrenzt MaxHeight das Fenster und der ScrollViewer
    # haelt alle Inhalte und Schaltflaechen erreichbar.
    try {
        $workHeight = [System.Windows.SystemParameters]::WorkArea.Height
        if ($workHeight -gt 200) { $win.MaxHeight = $workHeight - 20 }
    }
    catch { }
    $s = $script:App.Settings

    $win.FindName('LblAppVersion').Text = "Version $($script:AppVersion)"
    $win.FindName('TxtRegular').Text = [string]$s['RegularTime']
    $win.FindName('ChkWarn').IsChecked = [bool]$s['Warn945Enabled']
    $win.FindName('ChkSound').IsChecked = [bool]$s['SoundEnabled']
    $win.FindName('SldTransparency').Value = [double][int]$s['Transparency']
    $win.FindName('LblTransparency').Text = ('{0} %' -f [int]$s['Transparency'])
    $win.FindName('TxtFontSize').Text = [string]$s['FontSize']
    $win.FindName('ChkTopmost').IsChecked = [bool]$s['Topmost']
    $win.FindName('ChkTopmostReassert').IsChecked = [bool]$s['TopmostReassert']
    $win.FindName('ChkTray').IsChecked = [bool]$s['TrayIconEnabled']
    $win.FindName('ChkSeconds').IsChecked = [bool]$s['ShowSeconds']
    if ([string]$s['StartView'] -eq 'Erweitert') { $win.FindName('RbStartErweitert').IsChecked = $true }
    else { $win.FindName('RbStartKompakt').IsChecked = $true }
    $win.FindName('ChkKeepAlive').IsChecked = [bool]$s['KeepAliveEnabled']
    $win.FindName('TxtKeepAliveInterval').Text = [string]$s['KeepAliveIntervalSec']
    $win.FindName('TxtRadioVolume').Text = [string]$s['RadioVolume']
    $win.FindName('ChkRadioResume').IsChecked = [bool]$s['RadioResumeAfterUnlock']
    $win.FindName('ChkRadioRemember').IsChecked = [bool]$s['RadioRememberPlaybackState']
    $win.FindName('ChkShutdownOffer').IsChecked = [bool]$s['ShutdownOfferEnabled']

    # --- Internetradio: Arbeitskopie der Senderliste bearbeiten ---
    # Gespeichert wird erst mit "Speichern"; ungueltige Eingaben verhindert
    # bereits der Sender-Editor (Test-RadioStation). Eine leere Liste ist erlaubt.
    $radioWork = New-Object System.Collections.ArrayList
    foreach ($st in @($s['RadioStations'])) {
        [void]$radioWork.Add([ordered]@{ Id = [string]$st['Id']; Name = [string]$st['Name']; Url = [string]$st['Url'] })
    }
    $radioState = @{ SelectedId = [string]$s['RadioSelectedStationId'] }
    $lstRadio = $win.FindName('LstRadioStations')
    $refreshRadioList = {
        $keepIdx = $lstRadio.SelectedIndex
        $lstRadio.Items.Clear()
        foreach ($st in @($radioWork)) {
            $mark = ''
            if ([string]$st['Id'] -eq $radioState.SelectedId) { $mark = '   [Standard]' }
            [void]$lstRadio.Items.Add(([string]$st['Name']) + $mark)
        }
        if ($keepIdx -ge 0 -and $keepIdx -lt $lstRadio.Items.Count) { $lstRadio.SelectedIndex = $keepIdx }
    }
    # Auswahl in der Liste fuellt das GEMEINSAME Bearbeitungsfeld-Paar rechts
    # (keine eigenen Eingabefelder je Sender)
    $lstRadio.Add_SelectionChanged({
            $idx = $lstRadio.SelectedIndex
            if ($idx -lt 0 -or $idx -ge @($radioWork).Count) { return }
            $win.FindName('TxtRadioName').Text = [string]$radioWork[$idx]['Name']
            $win.FindName('TxtRadioUrl').Text = [string]$radioWork[$idx]['Url']
            $win.FindName('TxtRadioEditError').Visibility = 'Collapsed'
        })
    $showRadioError = {
        param([string]$Text)
        $blk = $win.FindName('TxtRadioEditError')
        $blk.Text = $Text
        $blk.Visibility = 'Visible'
    }
    # Liest und validiert Name/URL aus den Bearbeitungsfeldern ($null bei Fehler)
    $readRadioFields = {
        $probe = [ordered]@{
            Id   = 'pruefung'
            Name = ([string]$win.FindName('TxtRadioName').Text).Trim()
            Url  = ([string]$win.FindName('TxtRadioUrl').Text).Trim()
        }
        $err = Test-RadioStation -Station $probe
        if ($err -ne '') {
            & $showRadioError $err
            return $null
        }
        $win.FindName('TxtRadioEditError').Visibility = 'Collapsed'
        return $probe
    }
    $win.FindName('BtnRadioAdd').Add_Click({
            if (@($radioWork).Count -ge $script:RadioConst.MaxStations) {
                & $showRadioError ("Es sind höchstens {0} Radiosender möglich." -f $script:RadioConst.MaxStations)
                return
            }
            $probe = & $readRadioFields
            if ($null -eq $probe) { return }
            [void]$radioWork.Add([ordered]@{ Id = [guid]::NewGuid().ToString('N'); Name = [string]$probe['Name']; Url = [string]$probe['Url'] })
            if ([string]::IsNullOrEmpty($radioState.SelectedId)) {
                $radioState.SelectedId = [string]$radioWork[$radioWork.Count - 1]['Id']
            }
            & $refreshRadioList
            $lstRadio.SelectedIndex = $lstRadio.Items.Count - 1
        })
    $win.FindName('BtnRadioApply').Add_Click({
            $idx = $lstRadio.SelectedIndex
            if ($idx -lt 0 -or $idx -ge @($radioWork).Count) { & $showRadioError 'Bitte zuerst links einen Sender auswählen.'; return }
            $probe = & $readRadioFields
            if ($null -eq $probe) { return }
            $radioWork[$idx]['Name'] = [string]$probe['Name']
            $radioWork[$idx]['Url'] = [string]$probe['Url']
            & $refreshRadioList
        })
    $win.FindName('BtnRadioRemove').Add_Click({
            $idx = $lstRadio.SelectedIndex
            if ($idx -lt 0 -or $idx -ge @($radioWork).Count) { & $showRadioError 'Bitte zuerst links einen Sender auswählen.'; return }
            $removedId = [string]$radioWork[$idx]['Id']
            $radioWork.RemoveAt($idx)
            if ($radioState.SelectedId -eq $removedId) {
                $radioState.SelectedId = ''
                if (@($radioWork).Count -gt 0) { $radioState.SelectedId = [string]$radioWork[0]['Id'] }
            }
            & $refreshRadioList
        })
    $win.FindName('BtnRadioUp').Add_Click({
            $idx = $lstRadio.SelectedIndex
            if ($idx -le 0 -or $idx -ge @($radioWork).Count) { return }
            $tmp = $radioWork[$idx - 1]
            $radioWork[$idx - 1] = $radioWork[$idx]
            $radioWork[$idx] = $tmp
            $lstRadio.SelectedIndex = $idx - 1
            & $refreshRadioList
        })
    $win.FindName('BtnRadioDown').Add_Click({
            $idx = $lstRadio.SelectedIndex
            if ($idx -lt 0 -or $idx -ge (@($radioWork).Count - 1)) { return }
            $tmp = $radioWork[$idx + 1]
            $radioWork[$idx + 1] = $radioWork[$idx]
            $radioWork[$idx] = $tmp
            $lstRadio.SelectedIndex = $idx + 1
            & $refreshRadioList
        })
    $win.FindName('BtnRadioDefault').Add_Click({
            $idx = $lstRadio.SelectedIndex
            if ($idx -lt 0 -or $idx -ge @($radioWork).Count) { & $showRadioError 'Bitte zuerst links einen Sender auswählen.'; return }
            $radioState.SelectedId = [string]$radioWork[$idx]['Id']
            & $refreshRadioList
        })
    & $refreshRadioList
    if ($lstRadio.Items.Count -gt 0) { $lstRadio.SelectedIndex = 0 }

    $win.FindName('SldTransparency').Add_ValueChanged({
            $win.FindName('LblTransparency').Text = ('{0} %' -f [int]$win.FindName('SldTransparency').Value)
        })

    # Feld-Checkboxen aufbauen
    $panel = $win.FindName('PnlFields')
    $fieldChecks = @{}
    $selected = @($s['CompactFields'])
    foreach ($key in $script:CompactFieldDefs.Keys) {
        # Auch dynamisch erzeugte Kontrollkaestchen erhalten einen TextBlock
        # mit TextWrapping="Wrap", damit lange Beschriftungen (z. B.
        # "Soll-Rest / Überstunden (automatischer Wechsel)") umbrechen statt
        # rechts abgeschnitten zu werden.
        $chk = New-WrappedCheckBox -Text $script:CompactFieldDefs[$key]
        $chk.IsChecked = ($selected -contains $key)
        $chk.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#FFEDF2F7'))
        $chk.Margin = New-Object System.Windows.Thickness 0, 2, 0, 2
        [void]$panel.Children.Add($chk)
        $fieldChecks[$key] = $chk
    }
    $win.FindName('BtnPresetStandard').Add_Click({
            $preset = @($script:CompactPresets['Standard'])
            foreach ($key in $fieldChecks.Keys) { $fieldChecks[$key].IsChecked = ($preset -contains $key) }
        })
    $win.FindName('BtnPresetKlassisch').Add_Click({
            $preset = @($script:CompactPresets['Klassisch'])
            foreach ($key in $fieldChecks.Keys) { $fieldChecks[$key].IsChecked = ($preset -contains $key) }
        })
    $win.FindName('BtnPresetMinimum').Add_Click({
            $preset = @($script:CompactPresets['Minimum'])
            foreach ($key in $fieldChecks.Keys) { $fieldChecks[$key].IsChecked = ($preset -contains $key) }
        })

    # --- Eigene Presets: Arbeitskopie; uebernommen wird erst mit "Speichern",
    # "Abbrechen" verwirft saemtliche Presetaenderungen. Fest eingebaute
    # Presets koennen weder geloescht noch ueberschrieben noch umbenannt
    # werden (reservierte Namen; eigene Verwaltung nur fuer eigene Presets).
    $presetWork = New-Object System.Collections.ArrayList
    foreach ($p in @($s['CompactPresets'])) {
        $fieldsCopy = New-Object System.Collections.ArrayList
        foreach ($f in @($p['Fields'])) { [void]$fieldsCopy.Add([string]$f) }
        [void]$presetWork.Add([ordered]@{ Id = [string]$p['Id']; Name = [string]$p['Name']; Fields = $fieldsCopy })
    }
    $lstPresets = $win.FindName('LstPresets')
    $showPresetError = {
        param([string]$Text)
        $blk = $win.FindName('TxtPresetError')
        $blk.Text = $Text
        $blk.Visibility = 'Visible'
    }
    $clearPresetError = { $win.FindName('TxtPresetError').Visibility = 'Collapsed' }
    $refreshPresetList = {
        $keepIdx = $lstPresets.SelectedIndex
        $lstPresets.Items.Clear()
        foreach ($p in @($presetWork)) { [void]$lstPresets.Items.Add([string]$p['Name']) }
        if ($keepIdx -ge 0 -and $keepIdx -lt $lstPresets.Items.Count) { $lstPresets.SelectedIndex = $keepIdx }
    }
    $getCheckedFields = {
        $fields = New-Object System.Collections.ArrayList
        foreach ($key in $script:CompactFieldDefs.Keys) {
            if ($fieldChecks[$key].IsChecked) { [void]$fields.Add([string]$key) }
        }
        return ,$fields
    }
    $lstPresets.Add_SelectionChanged({
            $idx = $lstPresets.SelectedIndex
            if ($idx -lt 0 -or $idx -ge @($presetWork).Count) { return }
            $win.FindName('TxtPresetName').Text = [string]$presetWork[$idx]['Name']
            & $clearPresetError
        })
    $win.FindName('BtnPresetNew').Add_Click({
            if (@($presetWork).Count -ge $script:CompactPresetConst.MaxCustomPresets) {
                & $showPresetError ('Es sind höchstens {0} eigene Presets möglich.' -f $script:CompactPresetConst.MaxCustomPresets)
                return
            }
            $nameErr = Test-CompactPresetName -Name $win.FindName('TxtPresetName').Text -ExistingPresets $presetWork
            if ($nameErr -ne '') { & $showPresetError $nameErr; return }
            $fields = & $getCheckedFields
            if (@($fields).Count -eq 0) { & $showPresetError 'Bitte mindestens ein sichtbares Feld auswählen.'; return }
            [void]$presetWork.Add([ordered]@{
                    Id     = [guid]::NewGuid().ToString('N')
                    Name   = ([string]$win.FindName('TxtPresetName').Text).Trim()
                    Fields = $fields
                })
            & $clearPresetError
            & $refreshPresetList
            $lstPresets.SelectedIndex = $lstPresets.Items.Count - 1
        })
    $win.FindName('BtnPresetLoad').Add_Click({
            $idx = $lstPresets.SelectedIndex
            if ($idx -lt 0 -or $idx -ge @($presetWork).Count) { & $showPresetError 'Bitte zuerst ein eigenes Preset auswählen.'; return }
            $fields = @($presetWork[$idx]['Fields'])
            foreach ($key in $fieldChecks.Keys) { $fieldChecks[$key].IsChecked = ($fields -contains $key) }
            & $clearPresetError
        })
    $win.FindName('BtnPresetOverwrite').Add_Click({
            $idx = $lstPresets.SelectedIndex
            if ($idx -lt 0 -or $idx -ge @($presetWork).Count) { & $showPresetError 'Bitte zuerst ein eigenes Preset auswählen.'; return }
            $fields = & $getCheckedFields
            if (@($fields).Count -eq 0) { & $showPresetError 'Bitte mindestens ein sichtbares Feld auswählen.'; return }
            $presetWork[$idx]['Fields'] = $fields
            & $clearPresetError
        })
    $win.FindName('BtnPresetRename').Add_Click({
            $idx = $lstPresets.SelectedIndex
            if ($idx -lt 0 -or $idx -ge @($presetWork).Count) { & $showPresetError 'Bitte zuerst ein eigenes Preset auswählen.'; return }
            $nameErr = Test-CompactPresetName -Name $win.FindName('TxtPresetName').Text -ExistingPresets $presetWork -ExcludeId ([string]$presetWork[$idx]['Id'])
            if ($nameErr -ne '') { & $showPresetError $nameErr; return }
            $presetWork[$idx]['Name'] = ([string]$win.FindName('TxtPresetName').Text).Trim()
            & $clearPresetError
            & $refreshPresetList
        })
    $win.FindName('BtnPresetDelete').Add_Click({
            $idx = $lstPresets.SelectedIndex
            if ($idx -lt 0 -or $idx -ge @($presetWork).Count) { & $showPresetError 'Bitte zuerst ein eigenes Preset auswählen.'; return }
            $presetWork.RemoveAt($idx)
            & $clearPresetError
            & $refreshPresetList
        })
    & $refreshPresetList
    $win.FindName('BtnStorageOverview').Add_Click({ Show-StorageOverviewWindow })

    # Sicherheit: Passwort aendern / Protokolle anzeigen (nur lesend) / loeschen
    $win.FindName('BtnChangePassword').Add_Click({ Invoke-PasswordChangeFlow })
    $win.FindName('BtnShowLogs').Add_Click({ Show-LogViewerWindow })
    $win.FindName('BtnClearLogs').Add_Click({
            if (-not (Confirm-Question -Message 'Sollen alle verschlüsselten Protokolleinträge (aktuelles Protokoll und Archiv) endgültig gelöscht werden?' -Title 'Protokolle löschen')) { return }
            # Transaktionale Loeschung: Erfolgsmeldung NUR bei tatsaechlich
            # gespeicherter Loeschung; sonst vollstaendige Wiederherstellung.
            if (Clear-VaultProtocols) {
                Show-Info -Message 'Die Protokolle wurden gelöscht.'
            }
            else {
                Show-Warning -Message 'Die Löschung der Protokolle konnte nicht gespeichert werden. Die bisherigen Protokolle bleiben vollständig erhalten.'
            }
        })

    $state = @{ Saved = $false }
    $win.FindName('BtnOk').Add_Click({
            $regular = ([string]$win.FindName('TxtRegular').Text).Trim()
            # Regelarbeitszeit: gueltiges Format, groesser 00:00, maximal 10:00.
            # Bei ungueltiger Eingabe bleibt der bisherige gueltige Wert erhalten.
            $regMinutes = Test-RegularTimeInput -Text $regular
            if ($regMinutes -lt 0) {
                Show-Warning -Message "Die Regelarbeitszeit '$regular' ist ungültig. Zulässig ist eine Zeitangabe im Format HH:mm, größer als 00:00 und höchstens 10:00. Der bisherige Wert bleibt erhalten."
                return
            }
            $fontSize = 0
            if (-not [int]::TryParse(([string]$win.FindName('TxtFontSize').Text).Trim(), [ref]$fontSize) -or $fontSize -lt 9 -or $fontSize -gt 28) {
                Show-Warning -Message 'Die Schriftgröße muss eine Zahl zwischen 9 und 28 sein.'
                return
            }
            $interval = 0
            if (-not [int]::TryParse(([string]$win.FindName('TxtKeepAliveInterval').Text).Trim(), [ref]$interval) -or $interval -lt 10 -or $interval -gt 600) {
                Show-Warning -Message 'Das Scroll-Lock-Intervall muss zwischen 10 und 600 Sekunden liegen.'
                return
            }
            $fields = New-Object System.Collections.ArrayList
            foreach ($key in $script:CompactFieldDefs.Keys) {
                if ($fieldChecks[$key].IsChecked) { [void]$fields.Add($key) }
            }
            if ($fields.Count -eq 0) {
                Show-Warning -Message 'Bitte mindestens ein Feld für die kompakte Ansicht auswählen.'
                return
            }
            # Internetradio: Lautstaerke und Senderliste validieren - ungueltige
            # Eingaben werden nicht gespeichert
            $radioVol = 0
            if (-not [int]::TryParse(([string]$win.FindName('TxtRadioVolume').Text).Trim(), [ref]$radioVol) -or $radioVol -lt 0 -or $radioVol -gt 100) {
                Show-Warning -Message 'Die Radiolautstärke muss eine Zahl zwischen 0 und 100 sein.'
                return
            }
            foreach ($st in @($radioWork)) {
                $radioErr = Test-RadioStation -Station $st
                if ($radioErr -ne '') {
                    Show-Warning -Message ("Radiosender '{0}': {1}" -f [string]$st['Name'], $radioErr)
                    return
                }
            }
            # Eigene Presets final validieren (max. 5, eindeutige Namen,
            # keine reservierten Namen, nur bekannte Felder)
            $validatedPresets = Get-ValidatedCompactPresets -Loaded $presetWork
            if (@($validatedPresets).Count -ne @($presetWork).Count) {
                Show-Warning -Message 'Mindestens ein eigenes Preset ist ungültig (Name oder Felder). Bitte die Presets prüfen.'
                return
            }

            # Vollstaendiger Snapshot fuer die Ruecknahme bei fehlgeschlagenem
            # Speichervorgang (Einstellungen UND ggf. geaenderter aktueller Tag)
            $settingsSnapshot = $script:App.Settings | ConvertTo-Json -Depth 20
            $daySnapshot = $null
            $day = $script:App.CurrentDay

            $s = $script:App.Settings
            $s['RegularTime'] = $regular
            $s['Warn945Enabled'] = [bool]$win.FindName('ChkWarn').IsChecked
            $s['SoundEnabled'] = [bool]$win.FindName('ChkSound').IsChecked
            $s['ShutdownOfferEnabled'] = [bool]$win.FindName('ChkShutdownOffer').IsChecked
            $s['Transparency'] = [int]$win.FindName('SldTransparency').Value
            $s['FontSize'] = $fontSize
            $s['Topmost'] = [bool]$win.FindName('ChkTopmost').IsChecked
            $s['TopmostReassert'] = [bool]$win.FindName('ChkTopmostReassert').IsChecked
            $s['TrayIconEnabled'] = [bool]$win.FindName('ChkTray').IsChecked
            $s['ShowSeconds'] = [bool]$win.FindName('ChkSeconds').IsChecked
            $s['StartView'] = 'Kompakt'
            if ($win.FindName('RbStartErweitert').IsChecked) { $s['StartView'] = 'Erweitert' }
            $s['KeepAliveEnabled'] = [bool]$win.FindName('ChkKeepAlive').IsChecked
            $s['KeepAliveIntervalSec'] = $interval
            $s['CompactFields'] = $fields
            $s['CompactPresets'] = $validatedPresets
            $s['RadioStations'] = $radioWork
            $radioSel = [string]$radioState.SelectedId
            $radioSelFound = $false
            foreach ($st in @($radioWork)) { if ([string]$st['Id'] -eq $radioSel) { $radioSelFound = $true } }
            if (-not $radioSelFound) {
                $radioSel = $null
                if (@($radioWork).Count -gt 0) { $radioSel = [string]$radioWork[0]['Id'] }
            }
            $s['RadioSelectedStationId'] = $radioSel
            $s['RadioVolume'] = $radioVol
            $s['RadioResumeAfterUnlock'] = [bool]$win.FindName('ChkRadioResume').IsChecked
            $s['RadioRememberPlaybackState'] = [bool]$win.FindName('ChkRadioRemember').IsChecked

            # Regelarbeitszeit auch fuer den aktuell offenen Tag uebernehmen
            # (gemeinsam mit den Einstellungen in genau EINEM Speichervorgang);
            # der Erfolgslogeintrag wird erst NACH erfolgreichem Speichern
            # geschrieben (transaktionale Korrekturlogs).
            $regLogPending = $null
            if ($day -and $day.Status -eq 'Aktiv') {
                $parts = $regular.Split(':')
                $newMinutes = ([int]$parts[0]) * 60 + [int]$parts[1]
                if ([int]$day.RegularMinutes -ne $newMinutes) {
                    $daySnapshot = Get-DaySnapshot -Day $day
                    $regLogPending = @{ Old = ([string]$day.RegularMinutes + ' min'); New = ([string]$newMinutes + ' min') }
                    Add-Correction -Day $day -Description 'Regelarbeitszeit geaendert' -OldValue $regLogPending.Old -NewValue $regLogPending.New -NoLog
                    $day['RegularMinutes'] = $newMinutes
                }
            }

            $state.SaveOk = [bool](Save-Vault)
            if (-not $state.SaveOk) {
                # Fehlgeschlagener Speichervorgang: vollstaendigen Snapshot
                # wiederherstellen (Einstellungen inkl. Presets und ggf. Tag);
                # keine Erfolgsmeldung, Aktion gilt als nicht durchgefuehrt,
                # der Dialog bleibt zur Korrektur geoeffnet.
                $restored = Get-ValidatedSettings -Loaded (ConvertTo-PlainObject ($settingsSnapshot | ConvertFrom-Json))
                $script:App.Vault['Settings'] = $restored
                $script:App.Settings = $restored
                if ($null -ne $daySnapshot) { Restore-DayFromSnapshot -Day $day -Snapshot $daySnapshot }
                Invoke-SettingsApplied
                Write-AppLog -Level 'WARN' -Message 'Einstellungen NICHT gespeichert - vorheriger Zustand vollständig wiederhergestellt.'
                return
            }
            if ($null -ne $regLogPending) {
                Write-CorrectionLog -Day $day -Description 'Regelarbeitszeit geaendert' -OldValue $regLogPending.Old -NewValue $regLogPending.New
            }
            $state.Saved = $true
            $win.DialogResult = $true
            $win.Close()
        })
    [void]$win.ShowDialog()
    if ($state.Saved) {
        # $state.Saved wird nur nach ERFOLGREICHEM Save-Vault gesetzt; ein
        # Fehlversuch stellt bereits im Klick-Handler den Snapshot wieder her.
        Invoke-SettingsApplied
        Write-AppLog -Message 'Einstellungen gespeichert.'
    }
    return $state.Saved
}

#endregion


#region ===== Tages-Editor (Korrekturen) =====

$script:DayEditorXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Tag bearbeiten" Width="900" Height="780" MinWidth="720" MinHeight="600"
        Background="#FF171C24" WindowStartupLocation="CenterScreen">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Margin="0,0,0,8">
            <TextBlock x:Name="TxtHeader" FontWeight="Bold" FontSize="15"/>
            <TextBlock Text="Die feste 45-Minuten-Betriebspause wird automatisch berechnet und kann nicht bearbeitet werden. Jede Änderung wird protokolliert." TextWrapping="Wrap" Foreground="#FFAAB8C6"/>
            <DockPanel Margin="0,6,0,0">
                <Button x:Name="BtnDayComment" DockPanel.Dock="Right" Content="Tageskommentar..." MinWidth="140" Margin="8,0,0,0"/>
                <TextBlock Text="Tageskommentar: " VerticalAlignment="Center" Foreground="#FFAAB8C6"/>
                <TextBlock x:Name="TxtDayComment" VerticalAlignment="Center" TextWrapping="Wrap" MaxHeight="40" TextTrimming="CharacterEllipsis"/>
            </DockPanel>
        </StackPanel>
        <!-- Arbeitsabschnitte immer sichtbar; Pausen, Sperrintervalle und
             Aenderungsprotokoll teilen sich darunter einen Bereich mit Reitern
             (Titel inkl. Anzahl, gesetzt in $refresh). Schaltflaechen jeweils
             als Leiste unter der Tabelle. -->
        <GroupBox Grid.Row="1" Header="Arbeitsabschnitte">
            <DockPanel>
                <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,6,0,0">
                    <Button x:Name="BtnSegNew" Content="Neu" MinWidth="90" Margin="0,0,6,0"/>
                    <Button x:Name="BtnSegEdit" Content="Bearbeiten" MinWidth="90" Margin="0,0,6,0"/>
                    <Button x:Name="BtnSegDelete" Content="Löschen" MinWidth="90" Margin="0,0,6,0"/>
                    <Button x:Name="BtnSegComment" Content="Kommentar..." MinWidth="90" Margin="0"/>
                </StackPanel>
                <DataGrid x:Name="GridSegments" CanUserSortColumns="False"/>
            </DockPanel>
        </GroupBox>
        <TabControl Grid.Row="2" x:Name="TabLists" Margin="0,10,0,0">
            <TabItem x:Name="TabPauses" Header="Manuelle Pausen">
                <DockPanel Margin="4">
                    <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,6,0,0">
                        <Button x:Name="BtnPauseNew" Content="Neu" MinWidth="90" Margin="0,0,6,0"/>
                        <Button x:Name="BtnPauseEdit" Content="Bearbeiten" MinWidth="90" Margin="0,0,6,0"/>
                        <Button x:Name="BtnPauseDelete" Content="Löschen" MinWidth="90" Margin="0,0,6,0"/>
                        <Button x:Name="BtnPauseComment" Content="Kommentar..." MinWidth="90" Margin="0"/>
                    </StackPanel>
                    <DataGrid x:Name="GridPauses" CanUserSortColumns="False"/>
                </DockPanel>
            </TabItem>
            <TabItem x:Name="TabLocks" Header="Sperrintervalle" ToolTip="Zeiten mit gesperrtem Windows-Bildschirm">
                <DockPanel Margin="4">
                    <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,6,0,0">
                        <Button x:Name="BtnLockNew" Content="Neu" MinWidth="90" Margin="0,0,6,0"/>
                        <Button x:Name="BtnLockEdit" Content="Bearbeiten" MinWidth="90" Margin="0,0,6,0"/>
                        <Button x:Name="BtnLockDelete" Content="Löschen" MinWidth="90" Margin="0,0,6,0"/>
                        <Button x:Name="BtnLockComment" Content="Kommentar..." MinWidth="90" Margin="0"/>
                    </StackPanel>
                    <DataGrid x:Name="GridLocks" CanUserSortColumns="False"/>
                </DockPanel>
            </TabItem>
            <TabItem x:Name="TabCorrections" Header="Änderungsprotokoll">
                <DockPanel Margin="4">
                    <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,6,0,0">
                        <Button x:Name="BtnCorrComment" Content="Kommentar..." MinWidth="90" Margin="0"/>
                    </StackPanel>
                    <DataGrid x:Name="GridCorrections" CanUserSortColumns="False"/>
                </DockPanel>
            </TabItem>
        </TabControl>
        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
            <TextBlock x:Name="TxtNetto" VerticalAlignment="Center" FontFamily="Consolas" Margin="0,0,16,0"/>
            <Button x:Name="BtnClose" Content="Schließen" IsCancel="True" Margin="0"/>
        </StackPanel>
    </Grid>
</Window>
'@

function Get-IntervalTable {
    param($Intervals)
    $dt = New-Object System.Data.DataTable
    foreach ($col in @('Beginn', 'Ende', 'Dauer', 'Kommentar')) { [void]$dt.Columns.Add($col) }
    $now = Get-Date
    foreach ($iv in @($Intervals)) {
        if ($null -eq $iv) { continue }
        $s = ConvertFrom-DateTimeString $iv.Start
        $e = $now
        $endText = 'läuft'
        if ($iv.End) { $e = ConvertFrom-DateTimeString $iv.End; $endText = Format-Clock $e }
        [void]$dt.Rows.Add((Format-Clock $s), $endText, (Format-Duration ($e - $s)), (Get-CommentPreview -Text (Get-ItemComment -Item $iv)))
    }
    return ,$dt
}

# Tabelle des Aenderungsprotokolls (Korrekturen) eines Tages - in der
# gespeicherten Reihenfolge (Zeilenindex = Index in Day.Corrections)
function Get-CorrectionsTable {
    param($Corrections)
    $dt = New-Object System.Data.DataTable
    foreach ($col in @('Zeitpunkt', 'Änderung', 'Alt', 'Neu', 'Kommentar')) { [void]$dt.Columns.Add($col) }
    foreach ($corr in @($Corrections)) {
        if ($null -eq $corr) { continue }
        $when = [string]$corr.Timestamp
        try { $when = (ConvertFrom-DateTimeString $corr.Timestamp).ToString('dd.MM.yyyy HH:mm') } catch { }
        [void]$dt.Rows.Add($when, [string]$corr.Description, [string]$corr.OldValue, [string]$corr.NewValue,
            (Get-CommentPreview -Text (Get-ItemComment -Item $corr)))
    }
    return ,$dt
}

# Editor fuer einen (heutigen oder historischen) Arbeitstag
function Show-DayEditor {
    param([Parameter(Mandatory)]$Day)
    $win = New-XamlWindow -Xaml $script:DayEditorXaml
    Add-DarkWindowChrome -Window $win
    Set-DialogOwner -Window $win
    $baseDate = [datetime]::ParseExact($Day.Date, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    $isActive = ($Day.Status -eq 'Aktiv')
    $state = @{ SegIds = @(); PauseIds = @(); LockIds = @() }

    $refresh = {
        Update-DayTotals -Day $Day | Out-Null
        $comp = Get-DayComputation -Day $Day -Now (Get-Date)
        $win.FindName('TxtHeader').Text = 'Arbeitstag {0}  |  Status: {1}  |  Ende: {2}' -f $Day.Date, $Day.Status, (Get-DayEndDisplayText -Day $Day -OpenText 'Offen')
        $win.FindName('TxtNetto').Text = 'Netto: {0}' -f (Format-Duration $comp.Netto)
        # IDs VOR den Tabellen aktualisieren: der Kommentar-Tooltip (LoadingRow)
        # loest Zeilen ueber diese Listen auf
        $now = Get-Date
        $state.SegIds = @((Get-ParsedSegments -Day $Day -Now $now) | ForEach-Object { $_.Id })
        $state.PauseIds = @(@($Day.ManualPauses) | ForEach-Object { $_.Id })
        $state.LockIds = @(@($Day.LockIntervals) | ForEach-Object { $_.Id })
        $win.FindName('GridSegments').ItemsSource = (Get-SegmentsTable -Day $Day).DefaultView
        $win.FindName('GridPauses').ItemsSource = (Get-IntervalTable -Intervals $Day.ManualPauses).DefaultView
        $win.FindName('GridLocks').ItemsSource = (Get-IntervalTable -Intervals $Day.LockIntervals).DefaultView
        $win.FindName('GridCorrections').ItemsSource = (Get-CorrectionsTable -Corrections $Day.Corrections).DefaultView
        $win.FindName('TabPauses').Header = 'Manuelle Pausen ({0})' -f $state.PauseIds.Count
        $win.FindName('TabLocks').Header = 'Sperrintervalle ({0})' -f $state.LockIds.Count
        $win.FindName('TabCorrections').Header = 'Änderungsprotokoll ({0})' -f @(@($Day.Corrections) | Where-Object { $null -ne $_ }).Count
        $dayComment = Get-ItemComment -Item $Day
        $dayCommentBlock = $win.FindName('TxtDayComment')
        if ($dayComment -eq '') { $dayCommentBlock.Text = '(kein Kommentar)'; $dayCommentBlock.ToolTip = $null }
        else { $dayCommentBlock.Text = Get-CommentPreview -Text $dayComment -MaxLength 200; $dayCommentBlock.ToolTip = $dayComment }
    }

    $findSegment = {
        param($SegId)
        foreach ($seg in @($Day.Segments)) { if ($seg.Id -eq $SegId) { return $seg } }
        return $null
    }

    $findInterval = {
        param($ListName, $IvId)
        foreach ($iv in @($Day[$ListName])) { if ($iv.Id -eq $IvId) { return $iv } }
        return $null
    }

    # 10-Stunden-Wachhund fuer alle manuellen Korrekturen: eine Aenderung, durch
    # die die Netto-Arbeitszeit ueber 10:00 steigen wuerde, wird abgelehnt und
    # vollstaendig zurueckgenommen (keine stille Uebernahme).
    $applyTenHourGuard = {
        param([string]$Snapshot)
        if (-not (Test-DayUnderMax -Day $Day)) {
            Restore-DayFromSnapshot -Day $Day -Snapshot $Snapshot
            Show-Warning -Message 'Änderung abgelehnt: Die Netto-Arbeitszeit würde dadurch 10:00 Stunden überschreiten.'
            return $false
        }
        Update-MaxReachedState -Day $Day
        return $true
    }

    # Ende als HH:mm, offenes Ende als '' (wie im Alt-Wert der Korrektur)
    $endClockText = {
        param($End)
        if ($null -eq $End) { return '' }
        return Format-Clock $End
    }

    # Vergleich auf Minutenebene (wie im Dialog eingegeben): Sekunden eines
    # laufend erfassten Beginns gelten nicht als Aenderung
    $timesChanged = {
        param($Result, [string]$OldStartText, [string]$OldEndText, [string]$OldMode)
        if ($Result.Mode -ne $OldMode) { return $true }
        if ((Format-Clock $Result.Start) -ne $OldStartText) { return $true }
        return ((& $endClockText $Result.End) -ne $OldEndText)
    }

    # Bearbeiten ohne Zeitaenderung: nur der Kommentar des Eintrags wird
    # (transaktional) gespeichert, es entsteht keine Korrektur
    $commentOnlyEdit = {
        param($Item, $Result, [string]$OldComment, [string]$Label)
        if ($Result.Comment -ne '') {
            Show-Info -Message 'Die Zeiten wurden nicht geändert - es wird keine Korrektur protokolliert. Die Begründung wird daher nicht gespeichert.'
        }
        if ($Result.ItemComment -eq $OldComment) { return }
        [void](Set-DayItemCommentSaved -Day $Day -Item $Item -Text $Result.ItemComment -Label $Label)
        & $refresh
        Invoke-MainRefresh -ForceTables
    }

    # --- Arbeitsabschnitte ---
    $win.FindName('BtnSegNew').Add_Click({
            $result = Show-IntervalEditDialog -Caption 'Neuer Arbeitsabschnitt' -BaseDate $baseDate -ShowMode -Mode 'Homeoffice' `
                -StartText '08:00' -EndText '09:00' -AllowEmptyEnd:$isActive -CommentLabel 'Kommentar zum Abschnitt (optional):'
            if ($null -eq $result) { return }
            if (Test-SegmentOverlap -Day $Day -Start $result.Start -End $result.End) {
                Show-Warning -Message 'Der neue Abschnitt überschneidet sich mit einem vorhandenen Arbeitsabschnitt.'
                return
            }
            if ($null -eq $result.End) {
                foreach ($seg in @($Day.Segments)) {
                    if ($seg.Running) { Show-Warning -Message 'Es läuft bereits ein Abschnitt. Nur ein Abschnitt kann offen sein.'; return }
                }
            }
            $snapshot = Get-DaySnapshot -Day $Day
            $newSeg = New-SegmentObject -Mode $result.Mode -Start $result.Start -Running ($null -eq $result.End) -Manual $true
            if ($null -ne $result.End) { $newSeg['End'] = ConvertTo-DateTimeString $result.End }
            [void](Set-ItemComment -Item $newSeg -Text $result.Comment)
            [void]$Day['Segments'].Add($newSeg)
            if (-not (& $applyTenHourGuard $snapshot)) { & $refresh; return }
            $corrNewText = ('{0} {1}-{2}' -f $result.Mode, (Format-Clock $result.Start), (Format-Clock $result.End))
            Add-Correction -Day $Day -Description 'Arbeitsabschnitt manuell ergaenzt' -NewValue $corrNewText -NoLog
            if (-not (Save-WorkData)) {
                Restore-DayFromSnapshot -Day $Day -Snapshot $snapshot
                Write-AppLog -Level 'WARN' -Message 'Korrektur NICHT gespeichert - Änderung vollständig zurückgenommen.'
                & $refresh
                Invoke-MainRefresh -ForceTables
                return
            }
            Write-CorrectionLog -Day $Day -Description 'Arbeitsabschnitt manuell ergaenzt' -NewValue $corrNewText
            & $refresh
            Invoke-MainRefresh -ForceTables
        })

    $win.FindName('BtnSegEdit').Add_Click({
            $idx = $win.FindName('GridSegments').SelectedIndex
            if ($idx -lt 0 -or $idx -ge $state.SegIds.Count) { Show-Info -Message 'Bitte zuerst einen Abschnitt auswählen.'; return }
            $seg = & $findSegment $state.SegIds[$idx]
            if ($null -eq $seg) { return }
            $endText = ''
            if ($seg.End) { $endText = Format-Clock (ConvertFrom-DateTimeString $seg.End) }
            $startText = Format-Clock (ConvertFrom-DateTimeString $seg.Start)
            $oldComment = Get-ItemComment -Item $seg
            $result = Show-IntervalEditDialog -Caption 'Arbeitsabschnitt bearbeiten' -BaseDate $baseDate -ShowMode -Mode $seg.Mode `
                -StartText $startText -EndText $endText -AllowEmptyEnd:$isActive `
                -ItemCommentLabel 'Kommentar zum Abschnitt (optional):' -ItemCommentText $oldComment `
                -CommentLabel 'Begründung der Zeitänderung (optional, erscheint im Änderungsprotokoll):'
            if ($null -eq $result) { return }
            $label = "Abschnitt $($seg.Mode)"
            if (-not (& $timesChanged $result $startText $endText $seg.Mode)) {
                # Nur Kommentar geaendert: keine Korrektur, Zeiten (inkl. Sekunden) bleiben unangetastet
                & $commentOnlyEdit $seg $result $oldComment $label
                return
            }
            if (Test-SegmentOverlap -Day $Day -Start $result.Start -End $result.End -ExcludeId $seg.Id) {
                Show-Warning -Message 'Die Änderung überschneidet sich mit einem anderen Arbeitsabschnitt.'
                return
            }
            if ($null -eq $result.End) {
                foreach ($other in @($Day.Segments)) {
                    if ($other.Running -and $other.Id -ne $seg.Id) { Show-Warning -Message 'Es läuft bereits ein anderer Abschnitt.'; return }
                }
            }
            $snapshot = Get-DaySnapshot -Day $Day
            $oldText = '{0} {1}-{2}' -f $seg.Mode, (Format-Clock (ConvertFrom-DateTimeString $seg.Start)), $endText
            $seg['Mode'] = $result.Mode
            $seg['Start'] = ConvertTo-DateTimeString $result.Start
            if ($null -ne $result.End) {
                $seg['End'] = ConvertTo-DateTimeString $result.End
                $seg['Running'] = $false
            }
            else {
                $seg['End'] = $null
                $seg['Running'] = $true
            }
            $seg['Corrected'] = $true
            [void](Set-ItemComment -Item $seg -Text $result.ItemComment)
            if (-not (& $applyTenHourGuard $snapshot)) { & $refresh; return }
            $corrNewText = ('{0} {1}-{2}' -f $result.Mode, (Format-Clock $result.Start), (& $endClockText $result.End))
            Add-Correction -Day $Day -Description 'Arbeitsabschnitt korrigiert' -OldValue $oldText -NewValue $corrNewText -Comment $result.Comment -NoLog
            if (-not (Save-WorkData)) {
                Restore-DayFromSnapshot -Day $Day -Snapshot $snapshot
                Write-AppLog -Level 'WARN' -Message 'Korrektur NICHT gespeichert - Änderung vollständig zurückgenommen.'
                & $refresh
                Invoke-MainRefresh -ForceTables
                return
            }
            Write-CorrectionLog -Day $Day -Description 'Arbeitsabschnitt korrigiert' -OldValue $oldText -NewValue $corrNewText
            Write-CommentChangeLog -Day $Day -Label $label -Old $oldComment -New $result.ItemComment
            & $refresh
            Invoke-MainRefresh -ForceTables
        })

    $win.FindName('BtnSegDelete').Add_Click({
            $idx = $win.FindName('GridSegments').SelectedIndex
            if ($idx -lt 0 -or $idx -ge $state.SegIds.Count) { Show-Info -Message 'Bitte zuerst einen Abschnitt auswählen.'; return }
            $seg = & $findSegment $state.SegIds[$idx]
            if ($null -eq $seg) { return }
            $desc = '{0} {1}' -f $seg.Mode, (Format-Clock (ConvertFrom-DateTimeString $seg.Start))
            if (-not (Confirm-Question -Message "Arbeitsabschnitt '$desc' wirklich löschen?")) { return }
            $snapshot = Get-DaySnapshot -Day $Day
            [void]$Day['Segments'].Remove($seg)
            if (-not (& $applyTenHourGuard $snapshot)) { & $refresh; return }
            Add-Correction -Day $Day -Description 'Arbeitsabschnitt geloescht' -OldValue $desc -NoLog
            if (-not (Save-WorkData)) {
                Restore-DayFromSnapshot -Day $Day -Snapshot $snapshot
                Write-AppLog -Level 'WARN' -Message 'Korrektur NICHT gespeichert - Änderung vollständig zurückgenommen.'
                & $refresh
                Invoke-MainRefresh -ForceTables
                return
            }
            Write-CorrectionLog -Day $Day -Description 'Arbeitsabschnitt geloescht' -OldValue $desc
            & $refresh
            Invoke-MainRefresh -ForceTables
        })

    # --- Generische Behandlung fuer Pausen- und Sperrlisten ---
    $intervalHandler = {
        param($ListName, $IdListName, $GridName, $Action, $Label)
        $grid = $win.FindName($GridName)
        # Erfolgslogeintrag erst NACH erfolgreichem Speichern (transaktional)
        $pendingCorr = $null
        if ($Action -eq 'New') {
            $result = Show-IntervalEditDialog -Caption "Neues Intervall: $Label" -BaseDate $baseDate -StartText '12:00' -EndText '12:30' -AllowEmptyEnd:$isActive `
                -CommentLabel 'Kommentar zum Eintrag (optional):'
            if ($null -eq $result) { return }
            if ($null -eq $result.End) {
                foreach ($iv in @($Day[$ListName])) {
                    if ($null -eq $iv.End) { Show-Warning -Message "Es ist bereits ein offenes Intervall ($Label) vorhanden."; return }
                }
            }
            $snapshot = Get-DaySnapshot -Day $Day
            $newIv = New-IntervalObject -Start $result.Start
            if ($null -ne $result.End) { $newIv['End'] = ConvertTo-DateTimeString $result.End }
            [void](Set-ItemComment -Item $newIv -Text $result.Comment)
            [void]$Day[$ListName].Add($newIv)
            if (-not (& $applyTenHourGuard $snapshot)) { & $refresh; return }
            $pendingCorr = @{ Description = "$Label ergaenzt"; Old = ''; New = ('{0}-{1}' -f (Format-Clock $result.Start), (Format-Clock $result.End)) }
            Add-Correction -Day $Day -Description $pendingCorr.Description -NewValue $pendingCorr.New -NoLog
        }
        else {
            $idx = $grid.SelectedIndex
            $ids = $state[$IdListName]
            if ($idx -lt 0 -or $idx -ge $ids.Count) { Show-Info -Message 'Bitte zuerst einen Eintrag auswählen.'; return }
            $iv = & $findInterval $ListName $ids[$idx]
            if ($null -eq $iv) { return }
            $oldEndText = ''
            if ($iv.End) { $oldEndText = Format-Clock (ConvertFrom-DateTimeString $iv.End) }
            $oldText = '{0}-{1}' -f (Format-Clock (ConvertFrom-DateTimeString $iv.Start)), $oldEndText
            if ($Action -eq 'Delete') {
                if (-not (Confirm-Question -Message "Intervall '$oldText' ($Label) wirklich löschen?")) { return }
                $snapshot = Get-DaySnapshot -Day $Day
                [void]$Day[$ListName].Remove($iv)
                if (-not (& $applyTenHourGuard $snapshot)) { & $refresh; return }
                $pendingCorr = @{ Description = "$Label geloescht"; Old = $oldText; New = '' }
                Add-Correction -Day $Day -Description $pendingCorr.Description -OldValue $oldText -NoLog
            }
            else {
                $oldStartText = Format-Clock (ConvertFrom-DateTimeString $iv.Start)
                $oldComment = Get-ItemComment -Item $iv
                $result = Show-IntervalEditDialog -Caption "$Label bearbeiten" -BaseDate $baseDate `
                    -StartText $oldStartText -EndText $oldEndText -AllowEmptyEnd:$isActive `
                    -ItemCommentLabel 'Kommentar zum Eintrag (optional):' -ItemCommentText $oldComment `
                    -CommentLabel 'Begründung der Zeitänderung (optional, erscheint im Änderungsprotokoll):'
                if ($null -eq $result) { return }
                if (-not (& $timesChanged $result $oldStartText $oldEndText '')) {
                    & $commentOnlyEdit $iv $result $oldComment $Label
                    return
                }
                if ($null -eq $result.End) {
                    foreach ($other in @($Day[$ListName])) {
                        if ($null -eq $other.End -and $other.Id -ne $iv.Id) { Show-Warning -Message 'Es ist bereits ein anderes offenes Intervall vorhanden.'; return }
                    }
                }
                $snapshot = Get-DaySnapshot -Day $Day
                $iv['Start'] = ConvertTo-DateTimeString $result.Start
                if ($null -ne $result.End) { $iv['End'] = ConvertTo-DateTimeString $result.End } else { $iv['End'] = $null }
                [void](Set-ItemComment -Item $iv -Text $result.ItemComment)
                if (-not (& $applyTenHourGuard $snapshot)) { & $refresh; return }
                $pendingCorr = @{
                    Description = "$Label korrigiert"; Old = $oldText; New = ('{0}-{1}' -f (Format-Clock $result.Start), (& $endClockText $result.End))
                    CommentOld = $oldComment; CommentNew = $result.ItemComment
                }
                Add-Correction -Day $Day -Description $pendingCorr.Description -OldValue $oldText -NewValue $pendingCorr.New -Comment $result.Comment -NoLog
            }
        }
        if (-not (Save-WorkData)) {
            Restore-DayFromSnapshot -Day $Day -Snapshot $snapshot
            Write-AppLog -Level 'WARN' -Message 'Korrektur NICHT gespeichert - Änderung vollständig zurückgenommen.'
            & $refresh
            Invoke-MainRefresh -ForceTables
            return
        }
        if ($null -ne $pendingCorr) {
            Write-CorrectionLog -Day $Day -Description $pendingCorr.Description -OldValue $pendingCorr.Old -NewValue $pendingCorr.New
            if ($pendingCorr.Contains('CommentNew')) {
                Write-CommentChangeLog -Day $Day -Label $Label -Old $pendingCorr.CommentOld -New $pendingCorr.CommentNew
            }
        }
        & $refresh
        Invoke-MainRefresh -ForceTables
    }

    $win.FindName('BtnPauseNew').Add_Click({ & $intervalHandler 'ManualPauses' 'PauseIds' 'GridPauses' 'New' 'Manuelle Pause' })
    $win.FindName('BtnPauseEdit').Add_Click({ & $intervalHandler 'ManualPauses' 'PauseIds' 'GridPauses' 'Edit' 'Manuelle Pause' })
    $win.FindName('BtnPauseDelete').Add_Click({ & $intervalHandler 'ManualPauses' 'PauseIds' 'GridPauses' 'Delete' 'Manuelle Pause' })
    $win.FindName('BtnLockNew').Add_Click({ & $intervalHandler 'LockIntervals' 'LockIds' 'GridLocks' 'New' 'Sperrintervall' })
    $win.FindName('BtnLockEdit').Add_Click({ & $intervalHandler 'LockIntervals' 'LockIds' 'GridLocks' 'Edit' 'Sperrintervall' })
    $win.FindName('BtnLockDelete').Add_Click({ & $intervalHandler 'LockIntervals' 'LockIds' 'GridLocks' 'Delete' 'Sperrintervall' })
    # --- Kommentare (aendern keine Zeiten, zaehlen nicht als Korrektur) ---
    $editComment = {
        param([string]$Caption, $Item, [string]$Label)
        if ($null -eq $Item) { return }
        $res = Show-CommentDialog -Caption $Caption -Targets @(@{ Key = 'Item'; Label = $Label; Text = (Get-ItemComment -Item $Item) })
        if ($null -eq $res -or @($res).Count -eq 0) { return }
        [void](Save-DayCommentResults -Day $Day -Results $res -Items @{ Item = @{ Item = $Item; Label = $Label } })
        & $refresh
        Invoke-MainRefresh -ForceTables
    }
    $selectedId = {
        param([string]$GridName, [string]$IdListName)
        $idx = $win.FindName($GridName).SelectedIndex
        $ids = @($state[$IdListName])
        if ($idx -lt 0 -or $idx -ge $ids.Count) { Show-Info -Message 'Bitte zuerst einen Eintrag auswählen.'; return $null }
        return [string]$ids[$idx]
    }

    $win.FindName('BtnDayComment').Add_Click({
            & $editComment "Kommentar zum Arbeitstag $($Day.Date)" $Day 'Tag'
        })
    $win.FindName('BtnSegComment').Add_Click({
            $id = & $selectedId 'GridSegments' 'SegIds'
            if ($null -eq $id) { return }
            $seg = & $findSegment $id
            if ($null -eq $seg) { return }
            $caption = 'Kommentar zum Abschnitt {0} ab {1}' -f $seg.Mode, (Format-Clock (ConvertFrom-DateTimeString $seg.Start))
            & $editComment $caption $seg "Abschnitt $($seg.Mode)"
        })
    $win.FindName('BtnPauseComment').Add_Click({
            $id = & $selectedId 'GridPauses' 'PauseIds'
            if ($null -eq $id) { return }
            $iv = & $findInterval 'ManualPauses' $id
            if ($null -eq $iv) { return }
            & $editComment ('Kommentar zur Pause ab {0}' -f (Format-Clock (ConvertFrom-DateTimeString $iv.Start))) $iv 'Manuelle Pause'
        })
    $win.FindName('BtnLockComment').Add_Click({
            $id = & $selectedId 'GridLocks' 'LockIds'
            if ($null -eq $id) { return }
            $iv = & $findInterval 'LockIntervals' $id
            if ($null -eq $iv) { return }
            & $editComment ('Kommentar zum Sperrintervall ab {0}' -f (Format-Clock (ConvertFrom-DateTimeString $iv.Start))) $iv 'Sperrintervall'
        })
    $win.FindName('BtnCorrComment').Add_Click({
            $idx = $win.FindName('GridCorrections').SelectedIndex
            $list = @(@($Day.Corrections) | Where-Object { $null -ne $_ })
            if ($idx -lt 0 -or $idx -ge $list.Count) { Show-Info -Message 'Bitte zuerst eine Änderung auswählen.'; return }
            $corr = $list[$idx]
            & $editComment ('Kommentar zur Änderung: {0}' -f [string]$corr.Description) $corr 'Korrektur'
        })

    # --- Darstellung: breitere Kommentarspalte, voller Kommentar als Tooltip,
    # Doppelklick auf eine Zeile = Bearbeiten (Korrekturen: Kommentar) ---
    $itemAtRow = {
        param([string]$GridName, [int]$Index)
        if ($Index -lt 0) { return $null }
        switch ($GridName) {
            'GridSegments' { if ($Index -lt $state.SegIds.Count) { return (& $findSegment $state.SegIds[$Index]) } }
            'GridPauses' { if ($Index -lt $state.PauseIds.Count) { return (& $findInterval 'ManualPauses' $state.PauseIds[$Index]) } }
            'GridLocks' { if ($Index -lt $state.LockIds.Count) { return (& $findInterval 'LockIntervals' $state.LockIds[$Index]) } }
            'GridCorrections' {
                $list = @(@($Day.Corrections) | Where-Object { $null -ne $_ })
                if ($Index -lt $list.Count) { return $list[$Index] }
            }
        }
        return $null
    }
    $isRowClick = {
        param($Source)
        $dep = $Source
        while ($null -ne $dep -and -not ($dep -is [System.Windows.Controls.DataGridRow])) {
            if ($dep -is [System.Windows.Media.Visual]) { $dep = [System.Windows.Media.VisualTreeHelper]::GetParent($dep) }
            else { $dep = [System.Windows.LogicalTreeHelper]::GetParent($dep) }
        }
        return ($null -ne $dep)
    }
    $gridButtons = @{ GridSegments = 'BtnSegEdit'; GridPauses = 'BtnPauseEdit'; GridLocks = 'BtnLockEdit'; GridCorrections = 'BtnCorrComment' }
    foreach ($gridName in @($gridButtons.Keys)) {
        $grid = $win.FindName($gridName)
        $grid.Tag = $gridName
        $grid.Add_AutoGeneratingColumn({
                param($src, $e)
                if ($e.PropertyName -eq 'Kommentar') {
                    $e.Column.Width = New-Object System.Windows.Controls.DataGridLength(2, [System.Windows.Controls.DataGridLengthUnitType]::Star)
                }
            })
        $grid.Add_LoadingRow({
                param($src, $e)
                $item = & $itemAtRow ([string]$src.Tag) $e.Row.GetIndex()
                $text = Get-ItemComment -Item $item
                if ($text -eq '') { $e.Row.ToolTip = $null } else { $e.Row.ToolTip = $text }
            })
        $grid.Add_MouseDoubleClick({
                param($src, $e)
                if (-not (& $isRowClick $e.OriginalSource)) { return }
                $btn = $win.FindName($gridButtons[[string]$src.Tag])
                $btn.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
            })
    }

    $win.FindName('BtnClose').Add_Click({ $win.Close() })

    & $refresh
    [void]$win.ShowDialog()
    Invoke-MainRefresh -ForceTables
}

#endregion

#region ===== Verlauf =====

$script:HistoryXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Verlauf" Width="980" Height="540" MinWidth="760" MinHeight="360"
        Background="#FF171C24" WindowStartupLocation="CenterScreen">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <DataGrid Grid.Row="0" x:Name="GridDays" CanUserSortColumns="False"/>
        <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
            <Button x:Name="BtnOpen" Content="Tag bearbeiten"/>
            <Button x:Name="BtnDelete" Content="Tag löschen"/>
            <Button x:Name="BtnClose" Content="Schließen" IsCancel="True" Margin="0"/>
        </StackPanel>
    </Grid>
</Window>
'@

function Get-HistoryTable {
    param($Days)
    $dt = New-Object System.Data.DataTable
    foreach ($col in @('Datum', 'Beginn', 'Ende', 'Netto', 'Betrieb', 'Homeoffice', 'Pausen', 'Sperrzeit', 'Sollabweichung', 'Status', 'Korrekturen', 'Kommentar')) {
        [void]$dt.Columns.Add($col)
    }
    foreach ($day in @($Days)) {
        $refTime = Get-Date
        if ($day.EndedAt) { $refTime = ConvertFrom-DateTimeString $day.EndedAt }
        $comp = Get-DayComputation -Day $day -Now $refTime
        # Zentrale Endzeit-Ermittlung: aktive Tage zeigen 'Aktiv', niemals 00:00
        $endText = Get-DayEndDisplayText -Day $day -OpenText 'Aktiv'
        $abweichung = $comp.Netto - $comp.Regular
        [void]$dt.Rows.Add(
            $day.Date,
            (Format-Clock $comp.Beginn),
            $endText,
            (Format-Duration $comp.Netto),
            (Format-Duration $comp.BetriebNetto),
            (Format-Duration $comp.HoNetto),
            (Format-Duration ($comp.FesteAbzug + $comp.ManuellePause)),
            (Format-Duration $comp.SperrZeit),
            (Format-Duration $abweichung -WithSign:($abweichung.Ticks -ge 0)),
            [string]$day.Status,
            [string]@($day.Corrections).Count,
            (Get-CommentPreview -Text (Get-ItemComment -Item $day))
        )
    }
    return ,$dt
}

function Show-HistoryWindow {
    $win = New-XamlWindow -Xaml $script:HistoryXaml
    Add-DarkWindowChrome -Window $win
    Set-DialogOwner -Window $win
    $state = @{ DayIds = @() }

    $refresh = {
        $sorted = @(@($script:App.Data.Days) | Sort-Object -Property @{ Expression = { $_.Date } } -Descending)
        $state.DayIds = @($sorted | ForEach-Object { $_.Id })
        $win.FindName('GridDays').ItemsSource = (Get-HistoryTable -Days $sorted).DefaultView
    }

    $getSelectedDay = {
        $idx = $win.FindName('GridDays').SelectedIndex
        if ($idx -lt 0 -or $idx -ge $state.DayIds.Count) { return $null }
        $id = $state.DayIds[$idx]
        foreach ($day in @($script:App.Data.Days)) { if ($day.Id -eq $id) { return $day } }
        return $null
    }

    $win.FindName('BtnOpen').Add_Click({
            $day = & $getSelectedDay
            if ($null -eq $day) { Show-Info -Message 'Bitte zuerst einen Tag auswählen.'; return }
            Show-DayEditor -Day $day
            & $refresh
        })

    $win.FindName('BtnDelete').Add_Click({
            $day = & $getSelectedDay
            if ($null -eq $day) { Show-Info -Message 'Bitte zuerst einen Tag auswählen.'; return }
            $msg = "Der Arbeitstag $($day.Date) wird ENDGÜLTIG gelöscht.`r`nNetto-Arbeitszeit: $($day.Totals.Netto)`r`n`r`nWirklich löschen?"
            if (-not (Confirm-Question -Message $msg -Title 'Sicherheitsabfrage: Tag löschen')) { return }
            $wasCurrent = ($script:App.CurrentDay -and $script:App.CurrentDay.Id -eq $day.Id)
            [void]$script:App.Data.Days.Remove($day)
            if ($wasCurrent) { $script:App.CurrentDay = $null }
            if (-not (Save-WorkData)) {
                # Loeschung zuruecknehmen (Aktion gilt als nicht durchgefuehrt)
                [void]$script:App.Data.Days.Add($day)
                if ($wasCurrent) { $script:App.CurrentDay = $day }
                & $refresh
                Invoke-MainRefresh -ForceTables
                return
            }
            Write-AppLog -Level 'WARN' -Message "Arbeitstag $($day.Date) manuell geloescht."
            & $refresh
            Invoke-MainRefresh -ForceTables
        })

    $win.FindName('BtnClose').Add_Click({ $win.Close() })
    & $refresh
    [void]$win.ShowDialog()
}

#endregion

#region ===== CSV-Export =====

# CSV fuer deutsches Excel: Semikolon, UTF-8 mit BOM, deutsche Formate.
# Schutz gegen CSV-/Formelinjektion: Textfelder, die mit =, +, -, @, Tabulator,
# Wagenruecklauf oder Zeilenumbruch beginnen, werden durch ein vorangestelltes
# Apostroph neutralisiert (gilt auch fuer als Text exportierte Zeitwerte wie
# '-00:30' oder '+01:15'). Danach uebliche CSV-Maskierung.
function Get-CsvEscaped {
    param([string]$Value)
    if ($Value.Length -gt 0) {
        $first = $Value[0]
        if (@([char]'=', [char]'+', [char]'-', [char]'@', [char]9, [char]13, [char]10) -contains $first) {
            $Value = "'" + $Value
        }
    }
    if ($Value -match '[;"\r\n]') {
        return '"' + ($Value -replace '"', '""') + '"'
    }
    return $Value
}

function Export-WorkDataCsv {
    param(
        [Parameter(Mandatory)]$Days,
        [string]$Suffix = 'Export',
        [bool]$IncludeDetail = $false
    )
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    $written = New-Object System.Collections.ArrayList

    $header = @('Datum', 'Beginn', 'Ende', 'Betriebszeit', 'Homeoffice-Zeit', 'Sperrzeit', 'Pausenzeit',
        'Netto-Arbeitszeit', 'Regelarbeitszeit', 'Sollabweichung', 'Überstunden', 'Maximale Arbeitszeit',
        'Maximalzeit erreicht', 'Anzahl Korrekturen', 'Kommentar')
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add(($header -join ';'))
    $detailLines = New-Object System.Collections.ArrayList
    [void]$detailLines.Add((@('Datum', 'Modus', 'Beginn', 'Ende', 'Bruttozeit', 'Pausenzeit', 'Nettozeit', 'Manuell erfasst', 'Korrigiert', 'Kommentar') -join ';'))
    # Kommentare einzeilig (Zeilenumbrueche als ' / '), ungekuerzt
    $csvComment = { param($Item) Get-CommentPreview -Text (Get-ItemComment -Item $Item) -MaxLength ([int]$script:CommentConst.MaxLength * 4) }

    foreach ($day in @($Days | Sort-Object -Property @{ Expression = { $_.Date } })) {
        $refTime = Get-Date
        if ($day.EndedAt) { $refTime = ConvertFrom-DateTimeString $day.EndedAt }
        $comp = Get-DayComputation -Day $day -Now $refTime
        $dayDate = [datetime]::ParseExact($day.Date, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        # Dieselbe zentrale Endzeit wie in Verlauf und Zusammenfassung
        $endText = Get-DayEndDisplayText -Day $day -OpenText 'Offen'
        $abweichung = $comp.Netto - $comp.Regular
        $maxText = 'nein'
        if ($comp.MaxReached) { $maxText = 'ja' }
        $row = @(
            $dayDate.ToString('dd.MM.yyyy'),
            (Format-Clock $comp.Beginn),
            $endText,
            (Format-Duration $comp.BetriebNetto),
            (Format-Duration $comp.HoNetto),
            (Format-Duration $comp.SperrZeit),
            (Format-Duration ($comp.FesteAbzug + $comp.ManuellePause)),
            (Format-Duration $comp.Netto),
            (Format-Duration $comp.Regular),
            (Format-Duration $abweichung -WithSign:($abweichung.Ticks -ge 0)),
            (Format-Duration $comp.Ueberstunden -WithSign),
            (Format-Duration $comp.MaxTs),
            $maxText,
            [string]@($day.Corrections).Count,
            (& $csvComment $day)
        )
        [void]$lines.Add((($row | ForEach-Object { Get-CsvEscaped ([string]$_) }) -join ';'))

        if ($IncludeDetail) {
            foreach ($seg in (Get-ParsedSegments -Day $day -Now $refTime)) {
                $ja = @('nein', 'ja')
                $segEnd = Format-Clock $seg.End
                if ($seg.Running) { $segEnd = 'läuft' }
                $detailRow = @(
                    $dayDate.ToString('dd.MM.yyyy'), $seg.Mode, (Format-Clock $seg.Start), $segEnd,
                    [string]$seg.Ref.Brutto, [string]$seg.Ref.Pause, [string]$seg.Ref.Netto,
                    $ja[[int][bool]$seg.Ref.Manual], $ja[[int][bool]$seg.Ref.Corrected], (& $csvComment $seg.Ref)
                )
                [void]$detailLines.Add((($detailRow | ForEach-Object { Get-CsvEscaped ([string]$_) }) -join ';'))
            }
        }
    }

    $mainPath = Join-Path $script:Paths.Exports ("Arbeitszeiten_{0}_{1}.csv" -f $Suffix, $stamp)
    [System.IO.File]::WriteAllLines($mainPath, [string[]]$lines.ToArray(), $utf8Bom)
    [void]$written.Add($mainPath)
    if ($IncludeDetail) {
        $detailPath = Join-Path $script:Paths.Exports ("Arbeitszeiten_Detail_{0}_{1}.csv" -f $Suffix, $stamp)
        [System.IO.File]::WriteAllLines($detailPath, [string[]]$detailLines.ToArray(), $utf8Bom)
        [void]$written.Add($detailPath)
    }
    Write-AppLog -Message ('CSV-Export erstellt: ' + ($written.ToArray() -join ', '))
    return ,$written
}

$script:ExportXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="CSV-Export" SizeToContent="Height" Width="440"
        Background="#FF171C24" WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Topmost="True">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <StackPanel Margin="16">
        <TextBlock Text="Was soll exportiert werden?" FontWeight="Bold"/>
        <RadioButton x:Name="RbToday" Content="Aktueller / ausgewählter Tag" IsChecked="True" Margin="0,8,0,0"/>
        <RadioButton x:Name="RbRange" Content="Zeitraum:"/>
        <StackPanel Orientation="Horizontal" Margin="24,2,0,2">
            <TextBlock Text="von " VerticalAlignment="Center"/>
            <TextBox x:Name="TxtFrom" Width="90" FontFamily="Consolas"/>
            <TextBlock Text="  bis " VerticalAlignment="Center"/>
            <TextBox x:Name="TxtTo" Width="90" FontFamily="Consolas"/>
            <TextBlock Text="  (TT.MM.JJJJ)" Foreground="#FFAAB8C6" VerticalAlignment="Center"/>
        </StackPanel>
        <RadioButton x:Name="RbAll" Content="Alle Daten"/>
        <CheckBox x:Name="ChkDetail" Margin="0,10,0,0">
            <TextBlock Text="Zusätzlich Detail-Export (eine Zeile pro Arbeitsabschnitt)" TextWrapping="Wrap"/>
        </CheckBox>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
            <Button x:Name="BtnOk" Content="Exportieren" IsDefault="True" Width="120" Height="30" Margin="0,0,8,0" Padding="4,2"/>
            <Button x:Name="BtnCancel" Content="Abbrechen" IsCancel="True" Width="120" Height="30" Margin="0" Padding="4,2"/>
        </StackPanel>
    </StackPanel>
</Window>
'@

function Show-ExportDialog {
    if (@($script:App.Data.Days).Count -eq 0) {
        Show-Info -Message 'Es sind noch keine Arbeitstage vorhanden.'
        return
    }
    $win = New-XamlWindow -Xaml $script:ExportXaml
    Set-DialogOwner -Window $win
    $today = Get-Date
    $win.FindName('TxtFrom').Text = $today.AddDays(-30).ToString('dd.MM.yyyy')
    $win.FindName('TxtTo').Text = $today.ToString('dd.MM.yyyy')
    $win.FindName('BtnOk').Add_Click({
            $detail = [bool]$win.FindName('ChkDetail').IsChecked
            $days = $null
            $suffix = ''
            if ($win.FindName('RbAll').IsChecked) {
                $days = @($script:App.Data.Days)
                $suffix = 'Alle'
            }
            elseif ($win.FindName('RbRange').IsChecked) {
                $from = $null
                $to = $null
                $deCulture = [System.Globalization.CultureInfo]::GetCultureInfo('de-DE')
                try {
                    $from = [datetime]::ParseExact(([string]$win.FindName('TxtFrom').Text).Trim(), 'dd.MM.yyyy', $deCulture)
                    $to = [datetime]::ParseExact(([string]$win.FindName('TxtTo').Text).Trim(), 'dd.MM.yyyy', $deCulture)
                }
                catch {
                    Show-Warning -Message 'Bitte gültige Datumswerte im Format TT.MM.JJJJ angeben.'
                    return
                }
                if ($to -lt $from) {
                    Show-Warning -Message "Das Enddatum darf nicht vor dem Anfangsdatum liegen."
                    return
                }
                $days = @(@($script:App.Data.Days) | Where-Object {
                        $d = [datetime]::ParseExact($_.Date, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
                        $d -ge $from.Date -and $d -le $to.Date
                    })
                $suffix = '{0}-{1}' -f $from.ToString('yyyyMMdd'), $to.ToString('yyyyMMdd')
            }
            else {
                $day = $script:App.CurrentDay
                if ($null -eq $day) {
                    $sorted = @(@($script:App.Data.Days) | Sort-Object -Property @{ Expression = { $_.Date } } -Descending)
                    if ($sorted.Count -gt 0) { $day = $sorted[0] }
                }
                if ($null -eq $day) {
                    Show-Warning -Message 'Kein Tag zum Exportieren vorhanden.'
                    return
                }
                $days = @($day)
                $suffix = $day.Date
            }
            if (@($days).Count -eq 0) {
                Show-Warning -Message 'Im gewählten Zeitraum liegen keine Arbeitstage.'
                return
            }
            # Deutliche Warnung: CSV-Exporte sind die einzige erlaubte
            # unverschluesselte Ausnahme und erfordern eine ausdrueckliche
            # Bestaetigung des Benutzers.
            $warnText = ("Die exportierte CSV-Datei ist nicht verschlüsselt und kann von anderen Personen " +
                "oder Cloud-Diensten gelesen werden.`r`n`r`nSoll der Export trotzdem erstellt werden?")
            if (-not (Confirm-Question -Message $warnText -Title 'Unverschlüsselter CSV-Export')) { return }
            try {
                $files = Export-WorkDataCsv -Days $days -Suffix $suffix -IncludeDetail $detail
                Show-Info -Message ("Export abgeschlossen:`r`n`r`n" + (($files | ForEach-Object { [string]$_ }) -join "`r`n") +
                    "`r`n`r`nHinweis: Die Dateien sind unverschlüsselt.")
            }
            catch {
                Show-AppError -Message 'Der CSV-Export ist fehlgeschlagen.' -ErrorRecord $_
            }
            $win.Close()
        })
    [void]$win.ShowDialog()
}

#endregion


#region ===== Speicheruebersicht (nur lesend) =====

# Schreibgeschuetzte Speicheruebersicht. Sie greift AUSSCHLIESSLICH auf die
# fest definierten Pfade Data, Recovery und Exports unterhalb von
# PSScriptRoot zu ($script:Paths), liest keine Dateiinhalte (nur Metadaten
# wie FileInfo.Length und die bereits im Arbeitsspeicher entsperrten
# Vaultdaten fuer Zaehlwerte), folgt keinen Reparse Points, erzeugt keine
# Klartextdatei, protokolliert keine Speicherinformationen und veraendert,
# loescht, verschiebt, komprimiert oder archiviert NICHTS.

# Groesse einer einzelnen fest definierten Datei ($null = nicht vorhanden
# oder Reparse Point). Nur Metadaten, kein Lesen des Inhalts.
function Get-FileStorageSize {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $fi = New-Object System.IO.FileInfo $Path
        if (-not $fi.Exists) { return $null }
        if (($fi.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $null }
        return [long]$fi.Length
    }
    catch { return $null }
}

# Anzahl und Gesamtgroesse der Dateien EINES fest definierten Ordners
# (nur oberste Ebene; Reparse Points werden weder verfolgt noch mitgezaehlt).
function Get-FolderStorageInfo {
    param([Parameter(Mandatory)][string]$Path)
    $info = @{ Exists = $false; FileCount = 0; TotalBytes = [long]0 }
    try {
        $dir = New-Object System.IO.DirectoryInfo $Path
        if (-not $dir.Exists) { return $info }
        if (($dir.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $info }
        $info.Exists = $true
        foreach ($file in $dir.EnumerateFiles('*', [System.IO.SearchOption]::TopDirectoryOnly)) {
            try {
                if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                $info.FileCount = $info.FileCount + 1
                $info.TotalBytes = [long]$info.TotalBytes + [long]$file.Length
            }
            catch { }
        }
    }
    catch {
        # Neutraler Hinweis ohne vollstaendige Pfade; andere Werte bleiben nutzbar
        Write-AppLog -Level 'WARN' -Message 'Speicherübersicht: Ein Ordner konnte nicht vollständig ermittelt werden.'
    }
    return $info
}

# Verstaendliche Groessenanzeige (Byte/KB/MB/GB, deutsches Zahlenformat).
function Format-ByteSize {
    param($Bytes)
    if ($null -eq $Bytes) { return 'Nicht vorhanden' }
    $b = [double]$Bytes
    $de = [System.Globalization.CultureInfo]::GetCultureInfo('de-DE')
    if ($b -lt 1KB) { return [string]::Format($de, '{0:N0} Byte', $b) }
    if ($b -lt 1MB) { return [string]::Format($de, '{0:N1} KB', $b / 1KB) }
    if ($b -lt 1GB) { return [string]::Format($de, '{0:N1} MB', $b / 1MB) }
    return [string]::Format($de, '{0:N2} GB', $b / 1GB)
}

# Ermittelt alle Werte der Speicheruebersicht (reine, testbare Funktion;
# keinerlei Schreibzugriffe).
function Get-StorageOverviewData {
    $data = @{
        VaultMain      = Get-FileStorageSize -Path $script:Paths.VaultFile
        VaultBackup1   = Get-FileStorageSize -Path $script:Paths.VaultBackup1
        VaultBackup2   = Get-FileStorageSize -Path $script:Paths.VaultBackup2
        VaultPending   = Get-FileStorageSize -Path $script:Paths.VaultPending
        VaultPrev      = Get-FileStorageSize -Path $script:Paths.VaultPrev
        DataFolder     = (Get-FolderStorageInfo -Path $script:Paths.Data)
        RecoveryFolder = (Get-FolderStorageInfo -Path $script:Paths.Recovery)
        ExportsFolder  = (Get-FolderStorageInfo -Path $script:Paths.Exports)
        MaxFileBytes   = [long]$script:VaultConst.MaxFileBytes
        VaultPercent   = $null
        Days           = 0
        ActiveDays     = 0
        Segments       = 0
        Pauses         = 0
        Locks          = 0
        LogsCurrent    = 0
        LogsArchived   = 0
        LogLimitCurrent  = [int]$script:Const.MaxLogEntries
        LogLimitArchived = [int]$script:Const.MaxArchivedEntries
    }
    if ($null -ne $data.VaultMain -and $data.MaxFileBytes -gt 0) {
        $data.VaultPercent = [math]::Round(100.0 * [double]$data.VaultMain / [double]$data.MaxFileBytes, 1)
    }
    try {
        if ($script:App -and $script:App.Vault) {
            $counts = Get-WorkDataCounts -Work $script:App.Vault['WorkData']
            $data.Days = [int]$counts.Days
            $data.Segments = [int]$counts.Segments
            $data.Pauses = [int]$counts.Pauses
            $data.Locks = [int]$counts.Locks
            foreach ($day in @($script:App.Vault['WorkData']['Days'])) {
                if ($day -and [string]$day['Status'] -eq 'Aktiv') { $data.ActiveDays = $data.ActiveDays + 1 }
            }
            $data.LogsCurrent = @($script:App.Vault['Logs']).Count
            foreach ($block in @($script:App.Vault['LogArchives'])) {
                if ($block) { $data.LogsArchived = $data.LogsArchived + @($block.Entries).Count }
            }
        }
    }
    catch { }
    return $data
}

# Baut den Anzeigetext der Speicheruebersicht (reine, testbare Funktion).
function Get-StorageOverviewText {
    param([Parameter(Mandatory)]$Data)
    $de = [System.Globalization.CultureInfo]::GetCultureInfo('de-DE')
    $folderText = {
        param($Info)
        if (-not $Info.Exists) { return 'Nicht vorhanden (0 Dateien / 0 Byte)' }
        return ('{0} Datei(en), {1}' -f $Info.FileCount, (Format-ByteSize $Info.TotalBytes))
    }
    $limitText = 'Nicht vorhanden'
    if ($null -ne $Data.VaultMain) {
        $limitText = ('{0} von {1} ({2} %)' -f (Format-ByteSize $Data.VaultMain), (Format-ByteSize $Data.MaxFileBytes), [string]::Format($de, '{0:N1}', [double]$Data.VaultPercent))
    }
    $lines = @(
        'Tresordaten',
        ('  Haupttresor (vault.azt):     {0}' -f (Format-ByteSize $Data.VaultMain)),
        ('  Backup 1:                    {0}' -f (Format-ByteSize $Data.VaultBackup1)),
        ('  Backup 2:                    {0}' -f (Format-ByteSize $Data.VaultBackup2)),
        ('  Pending:                     {0}' -f (Format-ByteSize $Data.VaultPending)),
        ('  Vorheriger Stand (prev):     {0}' -f (Format-ByteSize $Data.VaultPrev)),
        ('  Data gesamt:                 {0}' -f (& $folderText $Data.DataFolder)),
        ('  Tresorgrenze:                {0}' -f $limitText),
        '',
        ('Recovery:                      {0}' -f (& $folderText $Data.RecoveryFolder)),
        ('Exports:                       {0}' -f (& $folderText $Data.ExportsFolder)),
        '  Hinweis: Exportdateien sind unverschlüsselt.',
        '',
        'Datenbestand',
        ('  Arbeitstage:                 {0} (davon aktiv: {1})' -f $Data.Days, $Data.ActiveDays),
        ('  Arbeitsabschnitte:           {0}' -f $Data.Segments),
        ('  Manuelle Pausen:             {0}' -f $Data.Pauses),
        ('  Sperrintervalle:             {0}' -f $Data.Locks),
        '',
        'Protokolle',
        ('  Aktuelle Einträge:           {0} (max. {1})' -f $Data.LogsCurrent, [string]::Format($de, '{0:N0}', $Data.LogLimitCurrent)),
        ('  Archivierte Einträge:        {0} (max. {1})' -f $Data.LogsArchived, [string]::Format($de, '{0:N0}', $Data.LogLimitArchived)),
        ('  Gesamt:                      {0}' -f ($Data.LogsCurrent + $Data.LogsArchived)),
        '',
        'Tresordaten werden verschlüsselt, aber nicht komprimiert.'
    )
    return ($lines -join "`r`n")
}

$script:StorageOverviewXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Speicherbelegung (nur Ansicht)" Width="520" Height="560" MinWidth="440" MinHeight="420"
        Background="#FF171C24" WindowStartupLocation="CenterScreen">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBox Grid.Row="0" x:Name="TxtStorage" IsReadOnly="True" BorderThickness="0" Background="Transparent"
                 FontFamily="Consolas" FontSize="13" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
        <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
            <Button x:Name="BtnStorageRefresh" Content="Aktualisieren"/>
            <Button x:Name="BtnStorageClose" Content="Schließen" IsCancel="True" Margin="0"/>
        </StackPanel>
    </Grid>
</Window>
'@

# Oeffnet die schreibgeschuetzte Speicheruebersicht. Werte werden NUR beim
# Oeffnen und bei "Aktualisieren" ermittelt (keine automatische
# Aktualisierung im Sekundentakt). Es werden keine Dateinamen aus Recovery
# oder Exports angezeigt. Ein Fehler bei einzelnen Werten beendet weder das
# Fenster noch die Arbeitszeiterfassung.
function Show-StorageOverviewWindow {
    try {
        $win = New-XamlWindow -Xaml $script:StorageOverviewXaml
        Add-DarkWindowChrome -Window $win -NoMinimize -NoMaximize
        Set-DialogOwner -Window $win
        $refresh = {
            try {
                $win.FindName('TxtStorage').Text = Get-StorageOverviewText -Data (Get-StorageOverviewData)
            }
            catch {
                $win.FindName('TxtStorage').Text = 'Die Speicherbelegung konnte nicht vollständig ermittelt werden.'
                Write-AppLog -Level 'WARN' -Message 'Speicherübersicht: Ermittlung fehlgeschlagen.'
            }
        }
        $win.FindName('BtnStorageRefresh').Add_Click({ & $refresh })
        $win.FindName('BtnStorageClose').Add_Click({ $win.Close() })
        & $refresh
        [void]$win.ShowDialog()
    }
    catch {
        Show-AppError -Message 'Die Speicherübersicht konnte nicht geöffnet werden.' -ErrorRecord $_
    }
}

#endregion

#region ===== Log-Viewer (nur lesend) =====

# Schreibgeschuetzte Ansicht der verschluesselten Protokolle. Gelesen wird
# AUSSCHLIESSLICH aus App.Vault['Logs'] und App.Vault['LogArchives'] im
# Arbeitsspeicher - es entsteht keine temporaere Klartextdatei. Der Viewer
# veraendert keine Logs; die vorhandene Loeschfunktion bleibt unveraendert.
# Ein Fehler im Viewer beendet weder Arbeitszeiterfassung noch Tresor oder
# Anwendung (alle Pfade sind lokal abgesichert).

# Sammelt Logeintraege aus aktuellem Protokoll und Archiven (nur LESEND),
# neueste zuerst, optional nach Level und Suchtext gefiltert und
# mengenbegrenzt. Reine, testbare Funktion.
function Get-LogViewEntries {
    param(
        [Parameter(Mandatory)]$Vault,
        [string]$SearchText = '',
        $Levels = $null,        # z. B. @('INFO','WARN'); $null = alle Level
        [int]$MaxCount = 500
    )
    $all = New-Object System.Collections.ArrayList
    foreach ($block in @($Vault['LogArchives'])) {
        if ($null -eq $block) { continue }
        foreach ($entry in @($block.Entries)) {
            if ($entry) { [void]$all.Add($entry) }
        }
    }
    foreach ($entry in @($Vault['Logs'])) {
        if ($entry) { [void]$all.Add($entry) }
    }
    # Archive liegen chronologisch VOR dem aktuellen Protokoll und beide
    # Listen sind chronologisch sortiert: rueckwaerts durchlaufen ergibt
    # die neuesten Eintraege zuerst.
    $result = New-Object System.Collections.ArrayList
    $needle = ([string]$SearchText).Trim()
    for ($i = $all.Count - 1; $i -ge 0; $i--) {
        $entry = $all[$i]
        $level = [string]$entry['Level']
        if ($null -ne $Levels -and (@($Levels) -notcontains $level)) { continue }
        if ($needle -ne '') {
            $hay = ([string]$entry['Timestamp'] + ' ' + $level + ' ' + [string]$entry['Message'])
            if ($hay.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        }
        [void]$result.Add([pscustomobject]@{
                Zeitpunkt = [string]$entry['Timestamp']
                Level     = $level
                Meldung   = [string]$entry['Message']
            })
        if ($result.Count -ge $MaxCount) { break }
    }
    return ,$result
}

# Entfernt potenziell sensible Bestandteile aus einer Logmeldung fuer den
# bewusst ausgeloesten UNVERSCHLUESSELTEN Export: vollstaendige http-/https-
# Adressen (z. B. Radiostream-URLs mit moeglichen Tokens) werden ersetzt und
# bekannte lokale Pfade (Toolpfad, Temp, Benutzerprofil) werden bestmoeglich
# anonymisiert. Passwoerter und Schluessel gelangen designbedingt nie in das
# Protokoll - dies ist eine zusaetzliche Absicherung. Die verschluesselten
# internen Logs bleiben unveraendert; technische Fehlermeldungen koennen
# trotz Anonymisierung Systeminformationen enthalten. Reine, testbare Funktion.
function Get-SanitizedLogMessage {
    param([string]$Message)
    $result = [regex]::Replace([string]$Message, '(?i)\bhttps?://\S+', '[URL entfernt]')
    $replaceLiteralPath = {
        param([string]$Text, [string]$Path, [string]$Token)
        if ([string]::IsNullOrWhiteSpace($Path)) { return $Text }
        $trimmed = ([string]$Path).TrimEnd('\')
        if ($trimmed.Length -lt 4) { return $Text }
        return [regex]::Replace($Text, [regex]::Escape($trimmed), $Token, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    # Reihenfolge: spezifischster Pfad zuerst (der Toolpfad kann unter Temp
    # oder dem Benutzerprofil liegen; Temp liegt meist im Benutzerprofil).
    try { $result = & $replaceLiteralPath $result ([string]$script:Paths.Root) '[TOOLPFAD]' } catch { }
    try { $result = & $replaceLiteralPath $result ([System.IO.Path]::GetTempPath()) '[TEMP-PFAD]' } catch { }
    try { $result = & $replaceLiteralPath $result ([string]$env:TEMP) '[TEMP-PFAD]' } catch { }
    try { $result = & $replaceLiteralPath $result ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)) '[BENUTZERPROFIL]' } catch { }
    try { $result = & $replaceLiteralPath $result ([string]$env:USERPROFILE) '[BENUTZERPROFIL]' } catch { }
    # Generisch: beliebige Laufwerk:\Users\<Name>-Pfade (auch fremde Profile)
    $result = [regex]::Replace($result, '(?i)[a-z]:\\Users\\[^\\/:*?"<>|\s]+', '[BENUTZERPROFIL]')
    return $result
}

$script:LogViewerXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Verschlüsselte Protokolle (nur Ansicht)" Width="900" Height="560" MinWidth="700" MinHeight="400"
        Background="#FF171C24" WindowStartupLocation="CenterScreen">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,8">
            <TextBlock Text="Suche:  " VerticalAlignment="Center"/>
            <TextBox x:Name="TxtLogSearch" Width="240" VerticalAlignment="Center"/>
            <Button x:Name="BtnLogRefresh" Content="Aktualisieren" MinWidth="0" Width="110" Height="26" Margin="8,0,16,0" Padding="4,2" VerticalAlignment="Center"/>
            <CheckBox x:Name="ChkLogInfo" IsChecked="True" VerticalAlignment="Center" Margin="0,0,10,0">
                <TextBlock Text="INFO"/>
            </CheckBox>
            <CheckBox x:Name="ChkLogWarn" IsChecked="True" VerticalAlignment="Center" Margin="0,0,10,0">
                <TextBlock Text="WARN"/>
            </CheckBox>
            <CheckBox x:Name="ChkLogError" IsChecked="True" VerticalAlignment="Center">
                <TextBlock Text="ERROR"/>
            </CheckBox>
        </StackPanel>
        <DataGrid Grid.Row="1" x:Name="GridLogs" CanUserSortColumns="False"/>
        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
            <TextBlock x:Name="TxtLogCount" VerticalAlignment="Center" Foreground="#FFAAB8C6" Margin="0,0,16,0"/>
            <Button x:Name="BtnLogMore" Content="Weitere 500 anzeigen"/>
            <Button x:Name="BtnLogExport" Content="Protokolle exportieren..."/>
            <Button x:Name="BtnLogClose" Content="Schließen" IsCancel="True" Margin="0"/>
        </StackPanel>
    </Grid>
</Window>
'@

# Oeffnet den schreibgeschuetzten Protokoll-Viewer (aktuelle und archivierte
# Eintraege gemeinsam, neueste zuerst, zunaechst 500 Eintraege).
function Show-LogViewerWindow {
    try {
        if ($null -eq $script:App -or $null -eq $script:App.Vault) {
            Show-Info -Message 'Es ist kein entsperrter Datentresor vorhanden.'
            return
        }
        $win = New-XamlWindow -Xaml $script:LogViewerXaml
        Add-DarkWindowChrome -Window $win
        Set-DialogOwner -Window $win
        $state = @{ Loaded = 0; PageSize = 500 }
        $getLevels = {
            $lv = New-Object System.Collections.ArrayList
            if ($win.FindName('ChkLogInfo').IsChecked) { [void]$lv.Add('INFO') }
            if ($win.FindName('ChkLogWarn').IsChecked) { [void]$lv.Add('WARN') }
            if ($win.FindName('ChkLogError').IsChecked) { [void]$lv.Add('ERROR') }
            # Alle drei Level ausgewaehlt = keine Einschraenkung (dann sind
            # auch sonstige Level wie 'ALT' aus der Migration sichtbar)
            if ($lv.Count -eq 3) { return $null }
            return ,$lv
        }
        $refresh = {
            param([bool]$More = $false)
            try {
                if (-not $More) { $state.Loaded = 0 }
                $want = $state.Loaded + $state.PageSize
                $entries = Get-LogViewEntries -Vault $script:App.Vault `
                    -SearchText ([string]$win.FindName('TxtLogSearch').Text) `
                    -Levels (& $getLevels) -MaxCount $want
                $state.Loaded = @($entries).Count
                $win.FindName('GridLogs').ItemsSource = $entries
                $win.FindName('TxtLogCount').Text = ('{0} Einträge (neueste zuerst)' -f $state.Loaded)
                # Weitere Seiten nur anbieten, wenn die letzte Seite voll war
                $win.FindName('BtnLogMore').IsEnabled = ($state.Loaded -ge $want)
            }
            catch {
                Write-AppLog -Level 'ERROR' -Message ('Protokoll-Viewer: Aktualisierung fehlgeschlagen: ' + $_.Exception.Message)
            }
        }
        $win.FindName('BtnLogRefresh').Add_Click({ & $refresh $false })
        $win.FindName('TxtLogSearch').Add_KeyDown({
                param($sender, $e)
                if ($e.Key -eq [System.Windows.Input.Key]::Enter) { & $refresh $false }
            })
        foreach ($chkName in @('ChkLogInfo', 'ChkLogWarn', 'ChkLogError')) {
            $win.FindName($chkName).Add_Click({ & $refresh $false })
        }
        $win.FindName('BtnLogMore').Add_Click({ & $refresh $true })
        $win.FindName('BtnLogExport').Add_Click({
                try {
                    $entries = @($win.FindName('GridLogs').ItemsSource)
                    if ($entries.Count -eq 0) {
                        Show-Info -Message 'Es sind keine Einträge zum Exportieren vorhanden.'
                        return
                    }
                    # Export NUR nach ausdruecklicher Warnung und Bestaetigung;
                    # niemals automatisch (z. B. bei Fehlern).
                    $warnText = ("Der Protokollexport ist UNVERSCHLÜSSELT und wird ausschließlich im Ordner 'Exports' gespeichert. " +
                        "Exportiert werden die aktuell angezeigten {0} Einträge; vollständige Internetadressen (z. B. Stream-URLs) sowie bekannte lokale Pfade (Toolpfad, Benutzerprofil, Temp) werden bestmöglich anonymisiert. " +
                        "Technische Fehlermeldungen können trotzdem Systeminformationen enthalten.`r`n`r`n" +
                        'Soll der Export trotzdem erstellt werden?') -f $entries.Count
                    if (-not (Confirm-Question -Message $warnText -Title 'Unverschlüsselter Protokollexport')) { return }
                    if (-not (Test-Path -LiteralPath $script:Paths.Exports)) {
                        New-Item -ItemType Directory -Path $script:Paths.Exports -Force | Out-Null
                    }
                    $lines = New-Object System.Collections.ArrayList
                    [void]$lines.Add('Zeitpunkt;Level;Meldung')
                    foreach ($e in $entries) {
                        [void]$lines.Add(('{0};{1};{2}' -f (Get-CsvEscaped ([string]$e.Zeitpunkt)), (Get-CsvEscaped ([string]$e.Level)), (Get-CsvEscaped (Get-SanitizedLogMessage ([string]$e.Meldung)))))
                    }
                    $exportPath = Join-Path $script:Paths.Exports ('Protokoll_Export_{0}.csv' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
                    [System.IO.File]::WriteAllLines($exportPath, [string[]]$lines.ToArray(), (New-Object System.Text.UTF8Encoding($true)))
                    Write-AppLog -Message ('Protokolle unverschlüsselt exportiert: ' + (Split-Path $exportPath -Leaf))
                    Show-Info -Message ("Der Export wurde erstellt:`r`n`r`n" + $exportPath + "`r`n`r`nHinweis: Die Datei ist unverschlüsselt.")
                }
                catch {
                    Show-AppError -Message 'Der Protokollexport ist fehlgeschlagen. Es wurde nichts exportiert.' -ErrorRecord $_
                }
            })
        $win.FindName('BtnLogClose').Add_Click({ $win.Close() })
        & $refresh $false
        [void]$win.ShowDialog()
    }
    catch {
        # Ein Fehler im Viewer darf weder Erfassung noch Tresor noch Anwendung beenden
        Show-AppError -Message 'Der Protokoll-Viewer konnte nicht geöffnet werden.' -ErrorRecord $_
    }
}

#endregion

#region ===== Passwort-Dialoge und Tresor-Ablaeufe =====

$script:PasswordXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ArbeitszeitTool" SizeToContent="Height" Width="480"
        Background="#FF171C24" WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Topmost="True">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <StackPanel Margin="16">
        <TextBlock x:Name="TxtCaption" FontWeight="Bold" FontSize="15" TextWrapping="Wrap"/>
        <TextBlock x:Name="TxtInfo" TextWrapping="Wrap" Foreground="#FFAAB8C6" Margin="0,8,0,0"/>
        <TextBlock x:Name="LblPw1" Text="Passwort:" Margin="0,12,0,4"/>
        <PasswordBox x:Name="Pw1" FontSize="15" Padding="4,3" Background="#FF10141B" Foreground="#FFEDF2F7" BorderBrush="#FF44506A" MaxLength="256"/>
        <TextBlock x:Name="LblPw2" Text="Passwort wiederholen:" Margin="0,10,0,4"/>
        <PasswordBox x:Name="Pw2" FontSize="15" Padding="4,3" Background="#FF10141B" Foreground="#FFEDF2F7" BorderBrush="#FF44506A" MaxLength="256"/>
        <TextBlock x:Name="TxtError" TextWrapping="Wrap" Foreground="#FFE05252" Margin="0,10,0,0" Visibility="Collapsed"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button x:Name="BtnOk" Content="OK" IsDefault="True"/>
            <Button x:Name="BtnCancel" Content="Abbrechen" IsCancel="True" Margin="0"/>
        </StackPanel>
        <Button x:Name="BtnReset" Content="Passwort vergessen? Neuen leeren Datentresor anlegen..." Margin="0,10,0,0"
                HorizontalAlignment="Stretch" Visibility="Collapsed"/>
    </StackPanel>
</Window>
'@

# Zeitkonstanter Vergleich zweier SecureStrings (fuer die Passwort-Wiederholung)
function Test-SecureStringsEqual {
    param([Parameter(Mandatory)][securestring]$A, [Parameter(Mandatory)][securestring]$B)
    $bytesA = ConvertTo-PasswordBytes -Secure $A
    $bytesB = ConvertTo-PasswordBytes -Secure $B
    try {
        return [ArbeitszeitTool.VaultCrypto]::FixedTimeEquals($bytesA, $bytesB)
    }
    finally {
        [ArbeitszeitTool.VaultCrypto]::ClearBytes($bytesA)
        [ArbeitszeitTool.VaultCrypto]::ClearBytes($bytesB)
    }
}

# Generischer Passwortdialog (WPF PasswordBox).
# Liefert @{ Password = [securestring]; Reset = [bool] } oder $null bei Abbruch.
#  -Confirmed:  zweites Feld (Wiederholung) + Passwortregeln erzwingen
#  -AllowReset: Schaltflaeche "Neuen leeren Datentresor anlegen..." anbieten
function Show-PasswordDialog {
    param(
        [Parameter(Mandatory)][string]$Caption,
        [string]$Title = 'ArbeitszeitTool - Datentresor',
        [string]$Info = '',
        [string]$OkText = 'OK',
        [switch]$Confirmed,
        [switch]$AllowReset
    )
    $win = New-XamlWindow -Xaml $script:PasswordXaml
    $win.Title = $Title
    $win.FindName('TxtCaption').Text = $Caption
    if ($Info -ne '') { $win.FindName('TxtInfo').Text = $Info }
    else { $win.FindName('TxtInfo').Visibility = 'Collapsed' }
    $win.FindName('BtnOk').Content = $OkText
    if (-not $Confirmed) {
        $win.FindName('LblPw2').Visibility = 'Collapsed'
        $win.FindName('Pw2').Visibility = 'Collapsed'
    }
    if ($AllowReset) { $win.FindName('BtnReset').Visibility = 'Visible' }
    $confirmedFlag = [bool]$Confirmed
    $state = @{ Result = $null }
    $showError = {
        param([string]$Text)
        $err = $win.FindName('TxtError')
        $err.Text = $Text
        $err.Visibility = 'Visible'
    }
    $win.FindName('BtnOk').Add_Click({
            $pw1 = $win.FindName('Pw1').SecurePassword
            if ($confirmedFlag) {
                $policyError = Test-PasswordPolicy -Secure $pw1
                if ($policyError -ne '') { & $showError $policyError; return }
                $pw2 = $win.FindName('Pw2').SecurePassword
                if (-not (Test-SecureStringsEqual -A $pw1 -B $pw2)) {
                    & $showError 'Die beiden Passwörter stimmen nicht überein.'
                    return
                }
            }
            elseif ($pw1.Length -eq 0) {
                & $showError 'Bitte das Passwort eingeben.'
                return
            }
            $state.Result = @{ Password = $pw1.Copy(); Reset = $false }
            $win.Close()
        })
    $win.FindName('BtnReset').Add_Click({
            $state.Result = @{ Password = $null; Reset = $true }
            $win.Close()
        })
    $win.Add_ContentRendered({ $win.FindName('Pw1').Focus() | Out-Null })
    [void]$win.ShowDialog()
    # Klartext in den PasswordBoxen verwerfen
    try { $win.FindName('Pw1').Clear(); $win.FindName('Pw2').Clear() } catch { }
    return $state.Result
}

# Verknuepft den entsperrten Tresor mit dem Anwendungszustand
function Set-ActiveVault {
    param([Parameter(Mandatory)]$Vault)
    $Vault['Settings'] = Get-ValidatedSettings -Loaded $Vault['Settings']
    if ($Vault['Logs'] -isnot [System.Collections.IList]) { $Vault['Logs'] = New-Object System.Collections.ArrayList }
    if (-not $Vault.Contains('LogArchives') -or $Vault['LogArchives'] -isnot [System.Collections.IList]) {
        $Vault['LogArchives'] = New-Object System.Collections.ArrayList
    }
    $script:App.Vault = $Vault
    $script:App.Data = $Vault['WorkData']
    $script:App.Settings = $Vault['Settings']
    Move-StartupLogToVault
}

# Erfasst nach dem Entsperren die Referenz auf die Hauptdatei fuer die
# Erkennung externer Aenderungen (Cloud-Synchronisierung):
#  - Der SHA-256-Hash der vorhandenen vault.azt wird IMMER erfasst - auch
#    wenn der Stand aus Pending/Backup1/Backup2 geladen wurde und auch bei
#    einer beschaedigten Hauptdatei. Der Hash beschreibt den Bytezustand
#    der Datei, nicht ihre inhaltliche Verwendbarkeit.
#  - Zusaetzlich wird festgehalten, ob die Hauptdatei beim Laden existierte.
#  - Der Hash ist nur dann $null, wenn beim Entsperren keine Hauptdatei
#    vorhanden war (oder die Hash-Berechnung selbst fehlschlug; dieser Fall
#    wird beim Speichern konservativ als "nicht vergleichbar" behandelt).
function Set-VaultLoadReference {
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][long]$Revision
    )
    $script:App.LoadedFrom = $Kind
    $script:App.VaultLoadedRevision = $Revision
    $script:App.VaultFileExistedAtLoad = (Test-Path -LiteralPath $script:Paths.VaultFile)
    $script:App.VaultFileHash = $null
    if ($script:App.VaultFileExistedAtLoad) {
        try { $script:App.VaultFileHash = Get-FileSha256Hex -Path $script:Paths.VaultFile } catch { }
    }
}

# Prueft alle Tresordateien (Haupt, Pending, Backups) kryptografisch und
# strukturell. Die Schluessel werden pro Salt nur einmal abgeleitet.
function Get-VaultCandidates {
    param([Parameter(Mandatory)][byte[]]$PasswordBytes)
    $files = @(
        @{ Path = $script:Paths.VaultFile; Kind = 'Haupt' },
        @{ Path = $script:Paths.VaultPending; Kind = 'Pending' },
        @{ Path = $script:Paths.VaultBackup1; Kind = 'Backup1' },
        @{ Path = $script:Paths.VaultBackup2; Kind = 'Backup2' }
    )
    $keyCache = @{}
    $candidates = New-Object System.Collections.ArrayList
    foreach ($file in $files) {
        if (-not (Test-Path -LiteralPath $file.Path)) { continue }
        $entry = @{ Path = $file.Path; Kind = $file.Kind; Valid = $false; Vault = $null; Keys = $null; Salt = $null; Iterations = 0; Revision = [long]-1 }
        try {
            $container = Read-VaultContainerFromFile -Path $file.Path
            $cacheKey = [Convert]::ToBase64String($container.Salt) + '|' + $container.Iterations
            if (-not $keyCache.ContainsKey($cacheKey)) {
                $keyCache[$cacheKey] = Get-VaultKeysFromPassword -PasswordBytes $PasswordBytes -Salt $container.Salt -Iterations $container.Iterations
            }
            $keys = $keyCache[$cacheKey]
            $vault = Read-VaultFromFile -Path $file.Path -AesKey $keys.Aes -HmacKey $keys.Hmac
            $entry.Valid = $true
            $entry.Vault = $vault
            $entry.Keys = $keys
            $entry.Salt = $container.Salt
            $entry.Iterations = $container.Iterations
            $entry.Revision = [long]$vault['Revision']
        }
        catch { }
        [void]$candidates.Add($entry)
    }
    return @{ Candidates = $candidates; KeyCache = $keyCache }
}

# Gibt alle abgeleiteten Schluessel eines Scans frei - ausser dem ausgewaehlten
function Clear-UnusedScanKeys {
    param($KeyCache, $KeepKeys)
    foreach ($keys in @($KeyCache.Values)) {
        if ($null -ne $KeepKeys -and [object]::ReferenceEquals($keys, $KeepKeys)) { continue }
        Clear-VaultKeys -Keys $keys
    }
}

$script:CrashRecoveryXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Wiederherstellung" SizeToContent="Height" Width="540"
        Background="#FF171C24" WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Topmost="True">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <StackPanel Margin="16">
        <TextBlock Text="Die Anwendung wurde zuvor nicht ordnungsgemäß beendet. Ein gültiger Wiederherstellungsstand wurde gefunden." FontWeight="Bold" TextWrapping="Wrap"/>
        <TextBlock x:Name="TxtDetail" TextWrapping="Wrap" Margin="0,10,0,12" Foreground="#FFAAB8C6"/>
        <Button x:Name="BtnNewest" Content="Neuesten gültigen Stand verwenden" Margin="0,0,0,6" HorizontalAlignment="Stretch"/>
        <Button x:Name="BtnMain" Content="Bisherigen Hauptstand verwenden" Margin="0,0,0,6" HorizontalAlignment="Stretch"/>
        <Button x:Name="BtnCancel" Content="Vorgang abbrechen" IsCancel="True" Margin="0" HorizontalAlignment="Stretch"/>
    </StackPanel>
</Window>
'@

# Liefert 'Neuester' | 'Haupt' | 'Abbrechen'
function Show-CrashRecoveryDialog {
    param([string]$Detail, [bool]$MainAvailable = $true)
    $win = New-XamlWindow -Xaml $script:CrashRecoveryXaml
    $win.FindName('TxtDetail').Text = $Detail
    if (-not $MainAvailable) { $win.FindName('BtnMain').IsEnabled = $false }
    $state = @{ Result = 'Abbrechen' }
    $win.FindName('BtnNewest').Add_Click({ $state.Result = 'Neuester'; $win.Close() })
    $win.FindName('BtnMain').Add_Click({ $state.Result = 'Haupt'; $win.Close() })
    $win.FindName('BtnCancel').Add_Click({ $state.Result = 'Abbrechen'; $win.Close() })
    [void]$win.ShowDialog()
    return $state.Result
}

# Erstellt einen neuen Tresor (Erststart, Reset oder Migration).
# Fragt das Passwort zweimal ab und uebernimmt optional vorhandene Daten.
# Liefert $true bei Erfolg (Sitzung entsperrt, Tresor gespeichert).
function Invoke-VaultCreationFlow {
    param(
        [string]$Caption = 'Neues Passwort für den Datentresor festlegen',
        $WorkData = $null,
        $Settings = $null,
        $LegacyLogEntries = $null
    )
    Assert-VaultCryptoReady
    $info = ('Mindestens {0} Zeichen; empfohlen werden mindestens 16 zufällige Zeichen. ' -f $script:VaultConst.MinPasswordLen) +
        'Leerzeichen, Sonderzeichen und Unicode sind erlaubt. Das Passwort wird NICHT gespeichert und muss bei jedem ' +
        'Programmstart eingegeben werden. Es gibt kein Masterpasswort und keine Wiederherstellungsmöglichkeit - ' +
        'ohne Passwort sind die Daten unwiederbringlich verloren.'
    $result = Show-PasswordDialog -Caption $Caption -Info $info -OkText 'Tresor erstellen' -Confirmed
    if ($null -eq $result -or $null -eq $result.Password) { return $false }
    $pwdBytes = ConvertTo-PasswordBytes -Secure $result.Password
    $keys = $null
    try {
        $salt = [ArbeitszeitTool.VaultCrypto]::GetRandomBytes($script:VaultConst.SaltBytes)
        $keys = Get-VaultKeysFromPassword -PasswordBytes $pwdBytes -Salt $salt -Iterations $script:VaultConst.Iterations
    }
    finally {
        # Klartext-Passwortbytes so kurz wie moeglich im Speicher halten
        [ArbeitszeitTool.VaultCrypto]::ClearBytes($pwdBytes)
        $result.Password.Dispose()
    }
    $vault = New-VaultDataObject
    if ($null -ne $WorkData) { $vault['WorkData'] = $WorkData }
    if ($null -ne $Settings) { $vault['Settings'] = Get-ValidatedSettings -Loaded $Settings }
    if ($null -ne $LegacyLogEntries) {
        foreach ($entry in @($LegacyLogEntries)) { [void]$vault['Logs'].Add($entry) }
    }
    $structErrors = Test-VaultStructure -Vault $vault
    if (@($structErrors).Count -gt 0) {
        Clear-VaultKeys -Keys $keys
        Show-AppError -Message ("Der Datentresor konnte nicht erstellt werden, weil die Daten ungültig sind:`r`n- " + (@($structErrors) -join "`r`n- "))
        return $false
    }
    Set-VaultSessionKeys -Keys $keys -Salt $salt -Iterations $script:VaultConst.Iterations
    Set-ActiveVault -Vault $vault
    Set-VaultLoadReference -Kind 'Neu' -Revision ([long]$vault['Revision'])
    Write-AppLog -Message 'Neuer Datentresor erstellt.'
    if (-not (Save-Vault)) {
        Clear-VaultSessionKeys
        $script:App.Vault = $null
        return $false
    }
    return $true
}

# "Passwort vergessen": Nach zwei ausdruecklichen Bestaetigungen wird der
# bestehende (weiterhin verschluesselte) Tresor unter einem neutralen
# GUID-Namen archiviert und ein neuer leerer Tresor angelegt.
function Invoke-VaultResetFlow {
    $warn1 = ('Es gibt kein Masterpasswort, keine Hintertür und keinen Wiederherstellungsschlüssel. ' +
        "Ohne das korrekte Passwort sind die verschlüsselten Daten NICHT wiederherstellbar.`r`n`r`n" +
        'Der bisherige Datentresor wird nicht gelöscht, sondern verschlüsselt im Ordner "Recovery" archiviert. ' +
        "Mit einem wiedergefundenen Passwort kann er später erneut geöffnet werden.`r`n`r`n" +
        'Soll wirklich ein neuer leerer Datentresor angelegt werden?')
    if (-not (Confirm-Question -Message $warn1 -Title 'Neuen leeren Datentresor anlegen')) { return $false }
    $warn2 = ('Letzte Bestätigung: Der neue Datentresor beginnt vollständig leer. ' +
        "Die bisherigen Daten bleiben nur mit dem alten Passwort lesbar.`r`n`r`nJetzt fortfahren?")
    if (-not (Confirm-Question -Message $warn2 -Title 'Neuen leeren Datentresor anlegen')) { return $false }

    if (-not (Test-Path -LiteralPath $script:Paths.Recovery)) {
        New-Item -ItemType Directory -Path $script:Paths.Recovery -Force | Out-Null
    }
    # Archivieren mit GUID-Namen (bewusst ohne Zeitstempel im Dateinamen).
    # Auch vault.prev.azt und der Transaktionsstatus werden mit beiseite
    # gelegt, damit die Start-Reparatur spaeter keinen alten Stand zurueckholt.
    $moved = New-Object System.Collections.ArrayList
    try {
        if (Test-Path -LiteralPath $script:Paths.VaultTxn) {
            Remove-Item -LiteralPath $script:Paths.VaultTxn -Force -ErrorAction SilentlyContinue
        }
    }
    catch { }
    $resetPaths = New-Object System.Collections.ArrayList
    foreach ($base in @($script:Paths.VaultFile, $script:Paths.VaultPending, $script:Paths.VaultBackup1, $script:Paths.VaultBackup2, $script:Paths.VaultPrev)) {
        [void]$resetPaths.Add($base)
        [void]$resetPaths.Add($base + '.old')
        [void]$resetPaths.Add($base + '.new')
    }
    foreach ($path in @($resetPaths)) {
        if (Test-Path -LiteralPath $path) {
            $target = Join-Path $script:Paths.Recovery ('vault-unreadable-{0}.azt' -f ([guid]::NewGuid().ToString()))
            Move-Item -LiteralPath $path -Destination $target -Force
            [void]$moved.Add(@{ Original = $path; Archive = $target })
        }
    }
    if (Invoke-VaultCreationFlow -Caption 'Passwort für den neuen leeren Datentresor festlegen') {
        return $true
    }
    # Anlage abgebrochen oder fehlgeschlagen: archivierte Dateien zurueckholen,
    # damit der bisherige Zustand vollstaendig erhalten bleibt.
    foreach ($entry in @($moved)) {
        try {
            if ((Test-Path -LiteralPath $entry.Archive) -and -not (Test-Path -LiteralPath $entry.Original)) {
                Move-Item -LiteralPath $entry.Archive -Destination $entry.Original -Force
            }
        }
        catch { }
    }
    return $false
}

# Entsperrt den vorhandenen Tresor (Passwortabfrage bei jedem Programmstart).
# Behandelt Absturz-Wiederherstellung: Der neueste gueltige Stand wird anhand
# der hoechsten internen (HMAC-geschuetzten) Revision ermittelt - niemals
# anhand des Dateidatums.
function Invoke-VaultUnlockFlow {
    Assert-VaultCryptoReady
    while ($true) {
        $result = Show-PasswordDialog -Caption 'Datentresor entsperren' -OkText 'Entsperren' `
            -Info 'Bitte das Tresor-Passwort eingeben. Ohne Passwort sind die Daten nicht zugänglich.' -AllowReset
        if ($null -eq $result) { return $false }
        if ($result.Reset) {
            if (Invoke-VaultResetFlow) { return $true }
            continue
        }
        $pwdBytes = ConvertTo-PasswordBytes -Secure $result.Password
        $scan = $null
        try {
            $scan = Get-VaultCandidates -PasswordBytes $pwdBytes
        }
        finally {
            [ArbeitszeitTool.VaultCrypto]::ClearBytes($pwdBytes)
            $result.Password.Dispose()
        }
        $candidates = @($scan.Candidates)
        $valid = @($candidates | Where-Object { $_.Valid })
        if ($valid.Count -eq 0) {
            Clear-UnusedScanKeys -KeyCache $scan.KeyCache -KeepKeys $null
            Show-Warning -Message $script:VaultNeutralError -Title 'Datentresor'
            continue
        }
        # Neuester gueltiger Stand = hoechste Revision (bei Gleichstand: Haupt vor
        # Pending vor Backup1 vor Backup2 - Reihenfolge der Kandidatenliste)
        $main = $null
        foreach ($cand in $valid) { if ($cand.Kind -eq 'Haupt') { $main = $cand } }
        $newest = $valid[0]
        foreach ($cand in $valid) { if ($cand.Revision -gt $newest.Revision) { $newest = $cand } }

        $selected = $null
        $mainUnclean = ($main -and -not [bool]$main.Vault['CleanShutdown'])
        $newerElsewhere = ($main -and $newest.Revision -gt $main.Revision)
        if ($null -eq $main) {
            # Hauptdatei fehlt oder ist beschaedigt, aber ein gueltiges Backup existiert
            $detail = ("Die Hauptdatei des Tresors ist nicht lesbar oder fehlt. Neuester gültiger Stand: {0} (Revision {1})." -f $newest.Kind, $newest.Revision)
            $choice = Show-CrashRecoveryDialog -Detail $detail -MainAvailable $false
            if ($choice -eq 'Abbrechen') { Clear-UnusedScanKeys -KeyCache $scan.KeyCache -KeepKeys $null; return $false }
            $selected = $newest
            Write-AppLog -Level 'WARN' -Message ("Hauptdatei unbrauchbar - Wiederherstellung aus {0} (Revision {1})." -f $newest.Kind, $newest.Revision)
        }
        elseif ($newerElsewhere -or $mainUnclean) {
            $detailParts = New-Object System.Collections.ArrayList
            if ($mainUnclean) { [void]$detailParts.Add('Der letzte Programmlauf wurde nicht ordnungsgemäß beendet.') }
            if ($newerElsewhere) { [void]$detailParts.Add(("Es wurde ein neuerer gültiger Stand gefunden: {0} (Revision {1}, Hauptstand: Revision {2})." -f $newest.Kind, $newest.Revision, $main.Revision)) }
            else { [void]$detailParts.Add(("Neuester gültiger Stand: {0} (Revision {1})." -f $newest.Kind, $newest.Revision)) }
            $choice = Show-CrashRecoveryDialog -Detail ($detailParts.ToArray() -join ' ')
            switch ($choice) {
                'Neuester' { $selected = $newest }
                'Haupt' { $selected = $main }
                default { Clear-UnusedScanKeys -KeyCache $scan.KeyCache -KeepKeys $null; return $false }
            }
            Write-AppLog -Level 'WARN' -Message ("Wiederherstellung nach unsauberem Ende: Stand '{0}' (Revision {1}) gewählt." -f $selected.Kind, $selected.Revision)
        }
        else {
            $selected = $main
        }

        Clear-UnusedScanKeys -KeyCache $scan.KeyCache -KeepKeys $selected.Keys
        Set-VaultSessionKeys -Keys $selected.Keys -Salt $selected.Salt -Iterations $selected.Iterations
        Set-ActiveVault -Vault $selected.Vault
        # Quelle des geladenen Standes und Referenz auf die Hauptdatei merken:
        # dient der Wiederherstellung (RecoveryState) und der Erkennung
        # externer Dateiaenderungen beim naechsten Speichern. Der Hash der
        # Hauptdatei wird auch beim Laden aus Pending/Backup erfasst.
        Set-VaultLoadReference -Kind ([string]$selected.Kind) -Revision ([long]$selected.Revision)
        if ($selected.Kind -ne 'Haupt' -and $script:App.VaultFileExistedAtLoad) {
            Write-AppLog -Level 'WARN' -Message ("Bewusste Wiederherstellung: Stand '{0}' geladen; die vorhandene Hauptdatei wird beim nächsten Speichern als explizit erkannter Wiederherstellungsvorgang ersetzt, sofern sie unverändert ist." -f $selected.Kind)
        }
        Write-AppLog -Message ("Datentresor entsperrt (Stand: {0}, Revision {1})." -f $selected.Kind, $selected.Revision)
        return $true
    }
}

# --- Migration vorhandener Klartextdaten -------------------------------------

function Get-LegacyPlaintextFiles {
    $files = New-Object System.Collections.ArrayList
    foreach ($path in @($script:Paths.LegacyWork, $script:Paths.LegacyBackup, $script:Paths.LegacySettings, $script:Paths.LegacyLog)) {
        if (Test-Path -LiteralPath $path) { [void]$files.Add($path) }
    }
    foreach ($item in @(Get-ChildItem -LiteralPath $script:Paths.Data -Filter 'worktime.corrupt.*.json' -File -ErrorAction SilentlyContinue)) {
        [void]$files.Add($item.FullName)
    }
    return ,$files
}

function Test-VaultFilesPresent {
    foreach ($path in @($script:Paths.VaultFile, $script:Paths.VaultPending, $script:Paths.VaultBackup1, $script:Paths.VaultBackup2)) {
        if (Test-Path -LiteralPath $path) { return $true }
    }
    return $false
}

# Zaehlt die fachlichen Bestandteile einer WorkData-Struktur (Tage, Segmente,
# Pausen, Sperrintervalle, Korrekturen). Dient dem Vorher/Nachher-Vergleich
# bei Migration und Import. Reine, testbare Funktion.
function Get-WorkDataCounts {
    param([Parameter(Mandatory)]$Work)
    $counts = @{ Days = 0; Segments = 0; Pauses = 0; Locks = 0; Corrections = 0 }
    foreach ($day in @($Work['Days'])) {
        if ($null -eq $day) { continue }
        $counts.Days++
        $counts.Segments += @($day['Segments']).Count
        $counts.Pauses += @($day['ManualPauses']).Count
        $counts.Locks += @($day['LockIntervals']).Count
        $counts.Corrections += @($day['Corrections']).Count
    }
    return $counts
}

# Liest und validiert EINE Klartext-Arbeitszeitdatei vollstaendig.
# Liefert die nutzbare Struktur oder $null (fehlend, leer oder unbrauchbar).
function Read-LegacyWorkFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $work = $null
    try { $work = Read-JsonFileRaw -Path $Path } catch { return $null }
    if ($null -eq $work -or $work -isnot [System.Collections.IDictionary]) { return $null }
    if (-not $work.Contains('Days') -or $null -eq $work['Days']) { return $null }
    if ($work['Days'] -isnot [System.Collections.IList]) {
        $tmp = New-Object System.Collections.ArrayList
        [void]$tmp.Add($work['Days'])
        $work['Days'] = $tmp
    }
    foreach ($day in @($work['Days'])) {
        if ($day -isnot [System.Collections.IDictionary]) { return $null }
        if (-not $day.Contains('Date') -or [string]$day['Date'] -notmatch '^\d{4}-\d{2}-\d{2}$') { return $null }
    }
    return $work
}

# Liest und validiert die Klartext-Altdaten. Reihenfolge der Datenquellen:
#   1. worktime.json - lesen und vollstaendig validieren
#   2. falls fehlend, leer oder unbrauchbar: worktime.backup.json - lesen
#      und vollstaendig validieren
# Es wird eindeutig festgehalten, welche Quelle verwendet wurde (Source),
# welche Dateien tatsaechlich uebernommen wurden (UsedFiles) und wie viele
# Tage/Segmente/Pausen/Sperrintervalle/Korrekturen enthalten sind (Counts).
# Wirft nur, wenn Altdaten vorhanden, aber KEINE Quelle verwendbar ist.
function Read-LegacyPlaintextData {
    $work = $null
    $source = 'leer'
    $usedFiles = New-Object System.Collections.ArrayList
    $primaryExists = (Test-Path -LiteralPath $script:Paths.LegacyWork)
    $backupExists = (Test-Path -LiteralPath $script:Paths.LegacyBackup)
    if ($primaryExists) {
        $work = Read-LegacyWorkFile -Path $script:Paths.LegacyWork
        if ($null -ne $work) {
            $source = 'worktime.json'
            [void]$usedFiles.Add($script:Paths.LegacyWork)
        }
    }
    if ($null -eq $work -and $backupExists) {
        $work = Read-LegacyWorkFile -Path $script:Paths.LegacyBackup
        if ($null -ne $work) {
            $source = 'worktime.backup.json'
            [void]$usedFiles.Add($script:Paths.LegacyBackup)
        }
    }
    if ($null -eq $work) {
        if ($primaryExists -or $backupExists) {
            throw 'Weder worktime.json noch worktime.backup.json enthalten verwendbare Arbeitszeitdaten. Es wurde nichts verändert.'
        }
        $work = New-EmptyWorkData
    }
    $work['SchemaVersion'] = $script:Const.SchemaVersion

    $settings = $null
    if (Test-Path -LiteralPath $script:Paths.LegacySettings) {
        try { $settings = Read-JsonFileRaw -Path $script:Paths.LegacySettings } catch { $settings = $null }
        if ($null -ne $settings) { [void]$usedFiles.Add($script:Paths.LegacySettings) }
    }

    # Altes Klartextprotokoll als Logeintraege uebernehmen (danach wird die
    # Klartextdatei ueberschrieben und geloescht)
    $logEntries = New-Object System.Collections.ArrayList
    if (Test-Path -LiteralPath $script:Paths.LegacyLog) {
        try {
            foreach ($line in [System.IO.File]::ReadAllLines($script:Paths.LegacyLog)) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                [void]$logEntries.Add([ordered]@{
                        Timestamp = ''
                        Level     = 'ALT'
                        Message   = $line
                    })
            }
            [void]$usedFiles.Add($script:Paths.LegacyLog)
        }
        catch { }
    }
    return @{
        WorkData   = $work
        Settings   = $settings
        LogEntries = $logEntries
        Source     = $source
        UsedFiles  = $usedFiles
        Counts     = (Get-WorkDataCounts -Work $work)
    }
}

# Archiviert eine nicht uebernommene Altdatei vollstaendig verschluesselt in
# den Recovery-Bereich (GUID-Name, kein Klartext, keine Zeitangaben im Namen)
# und entfernt erst danach das Original. Schlaegt die Archivierung fehl,
# bleibt die Datei unveraendert liegen. Liefert $true bei Erfolg.
function Move-LegacyFileToEncryptedRecovery {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    try {
        $rawContent = [System.IO.File]::ReadAllText($Path)
        $archive = [ordered]@{
            OriginalName = (Split-Path $Path -Leaf)
            Content      = $rawContent
        } | ConvertTo-Json -Depth 5
        $target = Protect-TextToRecovery -PlainText $archive -Prefix 'legacy'
        if ($null -eq $target) { return $false }
        # Archiv verifizieren, bevor das Original entfernt wird
        $verify = Read-VaultContainerFromFile -Path $target
        Unprotect-VaultContainer -Container $verify -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey | Out-Null
        Remove-PlaintextFileSecure -Path $Path
        Write-AppLog -Message ('Nicht übernommene Altdatei verschlüsselt archiviert: ' + (Split-Path $Path -Leaf))
        return $true
    }
    catch {
        Write-AppLog -Level 'WARN' -Message ('Altdatei konnte nicht archiviert werden und bleibt unverändert liegen: ' + $Path)
        return $false
    }
}

# Vollstaendige Migration:
#   1. Klartext lesen und vollstaendig validieren (worktime.json, bei Bedarf
#      worktime.backup.json als alternative Datenquelle)
#   2. verschluesselten Tresor erzeugen (Pending -> Verifikation -> Uebernahme)
#   3. Tresor erneut lesen und vollstaendig pruefen
#   4. Datenzahlen (Tage/Segmente/Pausen/Sperrintervalle/Korrekturen) vor und
#      nach der Migration vergleichen
#   5. verschluesseltes Backup erstellen und pruefen
#   6. erst danach die TATSAECHLICH uebernommenen Klartextquellen entfernen
# Nicht uebernommene Altdateien werden niemals geloescht: sie werden entweder
# vollstaendig verschluesselt in den Recovery-Bereich archiviert oder bleiben
# unveraendert liegen. Bei jedem Fehler bleiben alle Originale erhalten.
function Invoke-PlaintextMigration {
    $legacyFiles = Get-LegacyPlaintextFiles
    Show-Info -Message ("Es wurden unverschlüsselte Daten einer früheren Version gefunden:`r`n`r`n" +
        ((@($legacyFiles) | ForEach-Object { [string]$_ }) -join "`r`n") +
        "`r`n`r`nDiese Daten werden jetzt in einen verschlüsselten Datentresor übernommen. " +
        "Dazu wird ein neues Passwort festgelegt. Übernommene Klartextdateien werden erst nach " +
        'erfolgreicher Prüfung des Tresors überschrieben und gelöscht; nicht übernommene Dateien ' +
        'werden verschlüsselt archiviert oder bleiben unverändert liegen.') -Title 'Migration in den Datentresor'

    $legacy = $null
    try {
        $legacy = Read-LegacyPlaintextData
    }
    catch {
        Show-AppError -Message ('Die vorhandenen Klartextdaten konnten nicht gelesen werden. Es wurde nichts verändert. Details: ' + $_.Exception.Message)
        return $false
    }
    if (-not (Invoke-VaultCreationFlow -Caption 'Passwort für den neuen Datentresor festlegen (Migration)' `
                -WorkData $legacy.WorkData -Settings $legacy.Settings -LegacyLogEntries $legacy.LogEntries)) {
        return $false
    }
    # Tresor erneut lesen, vollstaendig pruefen und die Datenzahlen mit der
    # Klartextquelle vergleichen; danach verschluesseltes Backup + Pruefung.
    try {
        $verifyVault = Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        $countsAfter = Get-WorkDataCounts -Work $verifyVault['WorkData']
        foreach ($key in @('Days', 'Segments', 'Pauses', 'Locks', 'Corrections')) {
            if ([int]$countsAfter[$key] -ne [int]$legacy.Counts[$key]) {
                throw ("Datenzahlenvergleich fehlgeschlagen ({0}: vorher {1}, nachher {2})." -f $key, $legacy.Counts[$key], $countsAfter[$key])
            }
        }
        [System.IO.File]::Copy($script:Paths.VaultFile, $script:Paths.VaultBackup1, $true)
        Read-VaultFromFile -Path $script:Paths.VaultBackup1 -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey | Out-Null
    }
    catch {
        Show-AppError -Message 'Die Prüfung des neuen Tresors oder des verschlüsselten Backups ist fehlgeschlagen. Die Klartextdateien bleiben unverändert.' -ErrorRecord $_
        return $false
    }
    # Erst jetzt: die tatsaechlich uebernommenen Klartextquellen ueberschreiben
    # und loeschen.
    $usedList = @($legacy.UsedFiles)
    foreach ($path in $usedList) {
        try { Remove-PlaintextFileSecure -Path $path }
        catch { Write-AppLog -Level 'WARN' -Message ("Klartextdatei konnte nicht entfernt werden: {0}" -f $path) }
    }
    # Nicht uebernommene Altdateien (z. B. worktime.backup.json bei intakter
    # Hauptdatei, worktime.corrupt.*.json): NICHT loeschen, sondern
    # verschluesselt archivieren - oder unveraendert liegen lassen.
    $leftBehind = New-Object System.Collections.ArrayList
    foreach ($path in @($legacyFiles)) {
        if ($usedList -contains $path) { continue }
        if (-not (Test-Path -LiteralPath $path)) { continue }
        if (-not (Move-LegacyFileToEncryptedRecovery -Path $path)) {
            [void]$leftBehind.Add($path)
        }
    }
    try {
        if ((Test-Path -LiteralPath $script:Paths.LegacyLogDir) -and @(Get-ChildItem -LiteralPath $script:Paths.LegacyLogDir -Force -ErrorAction SilentlyContinue).Count -eq 0) {
            Remove-Item -LiteralPath $script:Paths.LegacyLogDir -Force
        }
    }
    catch { }
    Write-AppLog -Message ('Migration abgeschlossen (Quelle: {0}): {1} Datei(en) übernommen, {2} Tag(e) migriert.' -f $legacy.Source, $usedList.Count, $legacy.Counts.Days)
    $leftText = ''
    if ($leftBehind.Count -gt 0) {
        $leftText = "`r`n`r`nFolgende Dateien konnten nicht archiviert werden und bleiben unverändert liegen:`r`n" + ($leftBehind.ToArray() -join "`r`n")
    }
    $doneText = ("Die Migration wurde erfolgreich abgeschlossen (Datenquelle: {0}). Alle Daten liegen jetzt verschlüsselt im Datentresor.{1}`r`n`r`n" -f $legacy.Source, $leftText) +
        'Wichtige Hinweise: Auf SSDs kann das Überschreiben der alten Dateien durch Wear Leveling wirkungslos sein. ' +
        'Cloud-Speicher können ältere Versionen oder gelöschte Dateien behalten - bereits synchronisierte ' +
        'Klartextversionen (Papierkorb, Versionsverlauf) müssen gegebenenfalls manuell oder durch die zuständige IT entfernt werden.'
    Show-Info -Message $doneText -Title 'Migration abgeschlossen'
    return $true
}

$script:VaultConflictXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Verschlüsselte und unverschlüsselte Daten gefunden" SizeToContent="Height" Width="560"
        Background="#FF171C24" WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Topmost="True">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <StackPanel Margin="16">
        <TextBlock Text="Es sind sowohl ein verschlüsselter Datentresor als auch unverschlüsselte Altdaten vorhanden." FontWeight="Bold" TextWrapping="Wrap"/>
        <TextBlock x:Name="TxtDetail" TextWrapping="Wrap" Margin="0,10,0,12" Foreground="#FFAAB8C6"/>
        <Button x:Name="BtnVault" Content="Verschlüsselten Tresor verwenden (Altdaten bleiben unverändert liegen)" Margin="0,0,0,6" HorizontalAlignment="Stretch"/>
        <Button x:Name="BtnImport" Content="Klartextdaten kontrolliert in den Tresor importieren" Margin="0,0,0,6" HorizontalAlignment="Stretch"/>
        <Button x:Name="BtnCancel" Content="Vorgang abbrechen" IsCancel="True" Margin="0" HorizontalAlignment="Stretch"/>
    </StackPanel>
</Window>
'@

# Liefert 'Tresor' | 'Import' | 'Abbrechen'
function Show-VaultConflictDialog {
    param([string]$Detail)
    $win = New-XamlWindow -Xaml $script:VaultConflictXaml
    $win.FindName('TxtDetail').Text = $Detail
    $state = @{ Result = 'Abbrechen' }
    $win.FindName('BtnVault').Add_Click({ $state.Result = 'Tresor'; $win.Close() })
    $win.FindName('BtnImport').Add_Click({ $state.Result = 'Import'; $win.Close() })
    $win.FindName('BtnCancel').Add_Click({ $state.Result = 'Abbrechen'; $win.Close() })
    [void]$win.ShowDialog()
    return $state.Result
}

# Fachlicher Fingerabdruck eines Tagesobjekts - unabhaengig von IDs und
# Erzeugungszeitstempeln. Verglichen werden: Datum, Status, Abschlusszeit,
# Regelarbeitszeit, Segmente (Modus, Beginn, Ende, Laufstatus), manuelle
# Pausen, Sperrintervalle, Korrekturen und Nettozeiten (Totals).
# Reine, testbare Funktion.
function Get-DayContentFingerprint {
    param([Parameter(Mandatory)]$Day)
    $segs = New-Object System.Collections.ArrayList
    foreach ($seg in @($Day['Segments'])) {
        if ($null -eq $seg) { continue }
        [void]$segs.Add(('{0}|{1}|{2}|{3}|{4}' -f [string]$seg['Mode'], [string]$seg['Start'], [string]$seg['End'], [bool]$seg['Running'], (Get-ItemComment -Item $seg)))
    }
    $pauses = New-Object System.Collections.ArrayList
    foreach ($iv in @($Day['ManualPauses'])) {
        if ($null -eq $iv) { continue }
        [void]$pauses.Add(('{0}|{1}|{2}' -f [string]$iv['Start'], [string]$iv['End'], (Get-ItemComment -Item $iv)))
    }
    $locks = New-Object System.Collections.ArrayList
    foreach ($iv in @($Day['LockIntervals'])) {
        if ($null -eq $iv) { continue }
        [void]$locks.Add(('{0}|{1}|{2}' -f [string]$iv['Start'], [string]$iv['End'], (Get-ItemComment -Item $iv)))
    }
    $corrections = New-Object System.Collections.ArrayList
    foreach ($corr in @($Day['Corrections'])) {
        if ($null -eq $corr) { continue }
        [void]$corrections.Add(('{0}|{1}|{2}|{3}|{4}' -f [string]$corr['Timestamp'], [string]$corr['Description'], [string]$corr['OldValue'], [string]$corr['NewValue'], (Get-ItemComment -Item $corr)))
    }
    $totalsJson = ''
    if ($Day['Totals'] -is [System.Collections.IDictionary] -and @($Day['Totals'].Keys).Count -gt 0) {
        $totalsJson = ($Day['Totals'] | ConvertTo-Json -Depth 5 -Compress)
    }
    $norm = [ordered]@{
        Date           = [string]$Day['Date']
        Status         = [string]$Day['Status']
        EndedAt        = [string]$Day['EndedAt']
        RegularMinutes = [string]$Day['RegularMinutes']
        Comment        = (Get-ItemComment -Item $Day)
        Segments       = @($segs.ToArray() | Sort-Object)
        Pauses         = @($pauses.ToArray() | Sort-Object)
        Locks          = @($locks.ToArray() | Sort-Object)
        Corrections    = @($corrections.ToArray() | Sort-Object)
        Totals         = $totalsJson
    }
    return ($norm | ConvertTo-Json -Depth 6 -Compress)
}

function Test-DayContentEqual {
    param([Parameter(Mandatory)]$A, [Parameter(Mandatory)]$B)
    return ((Get-DayContentFingerprint -Day $A) -eq (Get-DayContentFingerprint -Day $B))
}

$script:ImportConflictXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Importkonflikt" SizeToContent="Height" Width="600"
        Background="#FF171C24" WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Topmost="True">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <StackPanel Margin="16">
        <TextBlock x:Name="TxtCaption" FontWeight="Bold" TextWrapping="Wrap"/>
        <TextBlock Text="Für dieses Datum existieren unterschiedliche Inhalte im Tresor und in den Klartextdaten. Es erfolgt kein stilles Überspringen - bitte auswählen, wie verfahren werden soll:" TextWrapping="Wrap" Margin="0,8,0,10"/>
        <TextBox x:Name="TxtCompare" IsReadOnly="True" BorderThickness="0" Background="Transparent"
                 FontFamily="Consolas" FontSize="12" TextWrapping="Wrap" Margin="0,0,0,10" MaxHeight="220" VerticalScrollBarVisibility="Auto"/>
        <Button x:Name="BtnKeepVault" Content="Vorhandenen Tresortag behalten (Import dieses Tages überspringen)" Margin="0,0,0,6" HorizontalAlignment="Stretch"/>
        <Button x:Name="BtnTakeImport" Content="Importierten Tag übernehmen (Tresortag wird verschlüsselt archiviert)" Margin="0,0,0,6" HorizontalAlignment="Stretch"/>
        <Button x:Name="BtnArchiveBoth" Content="Beide Varianten verschlüsselt archivieren (Tresortag bleibt aktiv)" Margin="0,0,0,6" HorizontalAlignment="Stretch"/>
        <Button x:Name="BtnCancel" Content="Import abbrechen (alles bleibt unverändert)" IsCancel="True" Margin="0" HorizontalAlignment="Stretch"/>
    </StackPanel>
</Window>
'@

# Kurzbeschreibung eines Tages fuer die Konfliktanzeige
function Get-DayConflictSummary {
    param([Parameter(Mandatory)]$Day)
    $segCount = @($Day['Segments']).Count
    $netto = '-'
    if ($Day['Totals'] -is [System.Collections.IDictionary] -and $Day['Totals'].Contains('Netto')) {
        $netto = [string]$Day['Totals']['Netto']
    }
    $summary = ('Status {0} | {1} Abschnitt(e) | {2} Pause(n) | {3} Sperrintervall(e) | {4} Korrektur(en) | Netto {5}' -f `
            [string]$Day['Status'], $segCount, @($Day['ManualPauses']).Count, @($Day['LockIntervals']).Count, @($Day['Corrections']).Count, $netto)
    $comment = Get-ItemComment -Item $Day
    if ($comment -ne '') { $summary += ' | Kommentar: ' + (Get-CommentPreview -Text $comment -MaxLength 40) }
    return $summary
}

# Liefert 'Behalten' | 'Uebernehmen' | 'Archivieren' | 'Abbrechen'
function Show-ImportConflictDialog {
    param(
        [Parameter(Mandatory)][string]$DateText,
        [Parameter(Mandatory)]$VaultDay,
        [Parameter(Mandatory)]$ImportDay
    )
    $win = New-XamlWindow -Xaml $script:ImportConflictXaml
    $win.FindName('TxtCaption').Text = ('Konflikt beim Import: Für den {0} existieren zwei unterschiedliche Stände.' -f $DateText)
    $win.FindName('TxtCompare').Text = ("Tresor:  {0}`r`nImport:  {1}" -f (Get-DayConflictSummary -Day $VaultDay), (Get-DayConflictSummary -Day $ImportDay))
    $state = @{ Result = 'Abbrechen' }
    $win.FindName('BtnKeepVault').Add_Click({ $state.Result = 'Behalten'; $win.Close() })
    $win.FindName('BtnTakeImport').Add_Click({ $state.Result = 'Uebernehmen'; $win.Close() })
    $win.FindName('BtnArchiveBoth').Add_Click({ $state.Result = 'Archivieren'; $win.Close() })
    $win.FindName('BtnCancel').Add_Click({ $state.Result = 'Abbrechen'; $win.Close() })
    [void]$win.ShowDialog()
    return $state.Result
}

# Kontrollierter Import von Klartextdaten in den bereits entsperrten Tresor.
# Tage mit bereits vorhandenem Datum werden vollstaendig inhaltlich verglichen:
#  - identischer Inhalt: kein doppelter Import (kein Datenverlust moeglich)
#  - abweichender Inhalt: der Benutzer entscheidet (behalten / uebernehmen /
#    beide verschluesselt archivieren / Import abbrechen)
# Beim Abbruch oder bei einem Fehler werden WorkData, Logs und alle weiteren
# veraenderten Tresorbereiche vollstaendig zurueckgesetzt; die Klartextquellen
# bleiben erhalten. Vor dem Entfernen der Klartextquellen wird jede Datei
# vollstaendig verschluesselt im Recovery-Bereich archiviert.
#  -ConflictResolver: nur fuer Tests - ersetzt den Konfliktdialog.
function Invoke-PlaintextImportIntoVault {
    param([scriptblock]$ConflictResolver = $null)
    $legacy = $null
    try { $legacy = Read-LegacyPlaintextData }
    catch {
        Show-AppError -Message ('Die Klartextdaten konnten nicht gelesen werden. Es wurde nichts verändert. Details: ' + $_.Exception.Message)
        return $false
    }
    $vault = $script:App.Vault
    # Vollstaendiger Snapshot aller Bereiche, die der Import veraendern kann
    $workSnapshot = $vault['WorkData'] | ConvertTo-Json -Depth 30
    $logsSnapshot = ConvertTo-Json -InputObject @($vault['Logs']) -Depth 10
    $logArchSnapshot = ConvertTo-Json -InputObject @($vault['LogArchives']) -Depth 10
    $restoreListFromJson = {
        param([string]$Json)
        $obj = ConvertTo-PlainObject ($Json | ConvertFrom-Json)
        if ($obj -is [System.Collections.IList]) { return ,$obj }
        $list = New-Object System.Collections.ArrayList
        if ($null -ne $obj) { [void]$list.Add($obj) }
        return ,$list
    }
    $restoreVault = {
        $vault['WorkData'] = ConvertTo-PlainObject ($workSnapshot | ConvertFrom-Json)
        $script:App.Data = $vault['WorkData']
        $vault['Logs'] = (& $restoreListFromJson $logsSnapshot)
        $vault['LogArchives'] = (& $restoreListFromJson $logArchSnapshot)
    }
    $daysList = $vault['WorkData']['Days']
    $existingByDate = @{}
    foreach ($day in @($daysList)) { $existingByDate[[string]$day.Date] = $day }
    $imported = 0
    $identical = New-Object System.Collections.ArrayList
    $kept = New-Object System.Collections.ArrayList
    $replaced = New-Object System.Collections.ArrayList
    $archived = New-Object System.Collections.ArrayList
    foreach ($legacyDay in @($legacy.WorkData['Days'])) {
        $dateText = [string]$legacyDay.Date
        if (-not $existingByDate.ContainsKey($dateText)) {
            [void]$daysList.Add($legacyDay)
            $imported++
            continue
        }
        $vaultDay = $existingByDate[$dateText]
        if (Test-DayContentEqual -A $vaultDay -B $legacyDay) {
            [void]$identical.Add($dateText)
            continue
        }
        # Inhaltlicher Konflikt: kein stilles Ueberspringen
        $choice = 'Abbrechen'
        if ($null -ne $ConflictResolver) { $choice = & $ConflictResolver $dateText $vaultDay $legacyDay }
        else { $choice = Show-ImportConflictDialog -DateText $dateText -VaultDay $vaultDay -ImportDay $legacyDay }
        if ($choice -eq 'Behalten') {
            [void]$kept.Add($dateText)
        }
        elseif ($choice -eq 'Uebernehmen') {
            $archTarget = Protect-TextToRecovery -PlainText ($vaultDay | ConvertTo-Json -Depth 20) -Prefix 'import-day'
            if ($null -eq $archTarget) {
                & $restoreVault
                Show-AppError -Message 'Der bisherige Tresortag konnte nicht verschlüsselt archiviert werden. Der Import wurde vollständig zurückgesetzt.'
                return $false
            }
            $idx = $daysList.IndexOf($vaultDay)
            if ($idx -ge 0) { $daysList[$idx] = $legacyDay } else { [void]$daysList.Add($legacyDay) }
            [void]$replaced.Add($dateText)
        }
        elseif ($choice -eq 'Archivieren') {
            $arch1 = Protect-TextToRecovery -PlainText ($vaultDay | ConvertTo-Json -Depth 20) -Prefix 'import-day'
            $arch2 = Protect-TextToRecovery -PlainText ($legacyDay | ConvertTo-Json -Depth 20) -Prefix 'import-day'
            if ($null -eq $arch1 -or $null -eq $arch2) {
                & $restoreVault
                Show-AppError -Message 'Die verschlüsselte Archivierung der beiden Varianten ist fehlgeschlagen. Der Import wurde vollständig zurückgesetzt.'
                return $false
            }
            [void]$archived.Add($dateText)
        }
        else {
            # Import abbrechen: alle Tresorbereiche vollstaendig zuruecksetzen,
            # Klartextquellen bleiben unveraendert erhalten.
            & $restoreVault
            Write-AppLog -Message 'Klartext-Import vom Benutzer abgebrochen - alle Änderungen zurückgesetzt.'
            Show-Info -Message 'Der Import wurde abgebrochen. Der Tresor und die Klartextdateien sind unverändert.' -Title 'Import abgebrochen'
            return $false
        }
    }
    foreach ($entry in @($legacy.LogEntries)) { [void]$vault['Logs'].Add($entry) }
    $structErrors = Test-VaultStructure -Vault $vault
    if (@($structErrors).Count -gt 0) {
        & $restoreVault
        Show-AppError -Message ("Der Import wurde abgebrochen, weil die zusammengeführten Daten ungültig wären:`r`n- " + (@($structErrors) -join "`r`n- ") + "`r`n`r`nAlle Tresorbereiche wurden zurückgesetzt; die Klartextdateien bleiben unverändert erhalten.")
        return $false
    }
    if (-not (Save-Vault)) {
        & $restoreVault
        return $false
    }
    # Erst nach erfolgreicher Speicherung + Verifikation: jede Klartextquelle
    # vollstaendig verschluesselt archivieren und erst danach entfernen.
    $importLegacyFiles = Get-LegacyPlaintextFiles
    foreach ($path in @($importLegacyFiles)) {
        Move-LegacyFileToEncryptedRecovery -Path $path | Out-Null
    }
    $detailParts = New-Object System.Collections.ArrayList
    if ($identical.Count -gt 0) { [void]$detailParts.Add('Bereits identisch vorhanden: ' + ($identical.ToArray() -join ', ')) }
    if ($kept.Count -gt 0) { [void]$detailParts.Add('Tresorstand behalten: ' + ($kept.ToArray() -join ', ')) }
    if ($replaced.Count -gt 0) { [void]$detailParts.Add('Importstand übernommen: ' + ($replaced.ToArray() -join ', ')) }
    if ($archived.Count -gt 0) { [void]$detailParts.Add('Beide Varianten archiviert: ' + ($archived.ToArray() -join ', ')) }
    $detailText = ''
    if ($detailParts.Count -gt 0) { $detailText = "`r`n`r`n" + ($detailParts.ToArray() -join "`r`n") }
    Write-AppLog -Message ("Klartext-Import abgeschlossen: {0} Tag(e) neu übernommen, {1} identisch, {2} Konflikt(e) aufgelöst." -f $imported, $identical.Count, ($kept.Count + $replaced.Count + $archived.Count))
    Show-Info -Message ("Der Import wurde abgeschlossen: {0} Arbeitstag(e) neu übernommen.{1}`r`n`r`nDie Klartextquellen wurden verschlüsselt im Ordner 'Recovery' archiviert und anschließend entfernt." -f $imported, $detailText) -Title 'Import abgeschlossen'
    return $true
}

# --- Passwort aendern (transaktional) ----------------------------------------

$script:ChangePasswordXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Verschlüsselungspasswort ändern" SizeToContent="Height" Width="480"
        Background="#FF171C24" WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Topmost="True">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <StackPanel Margin="16">
        <TextBlock Text="Verschlüsselungspasswort ändern" FontWeight="Bold" FontSize="15"/>
        <TextBlock Text="Alle Tresordateien (einschließlich Backups und der mit dem bisherigen Passwort lesbaren Dateien im Ordner Recovery) werden mit dem neuen Passwort neu verschlüsselt. Der Vorgang ist abgesichert: Schlägt ein Schritt fehl, bleibt der bisherige Tresor mit dem bisherigen Passwort vollständig erhalten." TextWrapping="Wrap" Foreground="#FFAAB8C6" Margin="0,8,0,0"/>
        <TextBlock Text="Aktuelles Passwort:" Margin="0,12,0,4"/>
        <PasswordBox x:Name="PwCurrent" FontSize="15" Padding="4,3" Background="#FF10141B" Foreground="#FFEDF2F7" BorderBrush="#FF44506A" MaxLength="256"/>
        <TextBlock Text="Neues Passwort (mindestens 12 Zeichen, empfohlen 16+ zufällige Zeichen):" Margin="0,10,0,4" TextWrapping="Wrap"/>
        <PasswordBox x:Name="PwNew" FontSize="15" Padding="4,3" Background="#FF10141B" Foreground="#FFEDF2F7" BorderBrush="#FF44506A" MaxLength="256"/>
        <TextBlock Text="Neues Passwort wiederholen:" Margin="0,10,0,4"/>
        <PasswordBox x:Name="PwNew2" FontSize="15" Padding="4,3" Background="#FF10141B" Foreground="#FFEDF2F7" BorderBrush="#FF44506A" MaxLength="256"/>
        <TextBlock x:Name="TxtError" TextWrapping="Wrap" Foreground="#FFE05252" Margin="0,10,0,0" Visibility="Collapsed"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button x:Name="BtnOk" Content="Passwort ändern" IsDefault="True"/>
            <Button x:Name="BtnCancel" Content="Abbrechen" IsCancel="True" Margin="0"/>
        </StackPanel>
    </StackPanel>
</Window>
'@

# Inhalt der neutralen Transaktionsdatei vault.txn. Es werden AUSSCHLIESSLICH
# logische Bezeichnungen (Haupt/Backup1/Backup2) gespeichert - KEINE absoluten
# Pfade, die Benutzername oder Cloud-Ordnernamen offenlegen koennten. Beim
# Einlesen (Repair-VaultTransactionState) werden ohnehin nur die intern fest
# bekannten Pfade verwendet; es werden niemals Pfade aus vault.txn uebernommen.
# Reine, testbare Funktion.
function New-VaultTxnContent {
    param([Parameter(Mandatory)]$Prepared)
    return ([ordered]@{
            Id    = [guid]::NewGuid().ToString()
            Kind  = 'Reencryption'
            Phase = 'Apply'
            Files = @(@($Prepared) | ForEach-Object { [string]$_.Kind })
        } | ConvertTo-Json)
}

# Verschluesselt alle vorhandenen Tresordateien transaktional mit neuen
# Schluesseln um. Liefert '' bei Erfolg, sonst eine Fehlermeldung.
# Reine Dateilogik (auch von den Tests verwendet).
function Invoke-VaultReencryption {
    param(
        [Parameter(Mandatory)][byte[]]$OldPasswordBytes,
        [Parameter(Mandatory)][byte[]]$NewAesKey,
        [Parameter(Mandatory)][byte[]]$NewHmacKey,
        [Parameter(Mandatory)][byte[]]$NewSalt,
        [Parameter(Mandatory)][int]$NewIterations
    )
    $targets = New-Object System.Collections.ArrayList
    $keyCache = @{}
    $mainSeen = $false
    foreach ($info in @(
            @{ Path = $script:Paths.VaultFile; Kind = 'Haupt' },
            @{ Path = $script:Paths.VaultBackup1; Kind = 'Backup1' },
            @{ Path = $script:Paths.VaultBackup2; Kind = 'Backup2' })) {
        if (-not (Test-Path -LiteralPath $info.Path)) { continue }
        try {
            $container = Read-VaultContainerFromFile -Path $info.Path
            $cacheKey = [Convert]::ToBase64String($container.Salt) + '|' + $container.Iterations
            if (-not $keyCache.ContainsKey($cacheKey)) {
                $keyCache[$cacheKey] = Get-VaultKeysFromPassword -PasswordBytes $OldPasswordBytes -Salt $container.Salt -Iterations $container.Iterations
            }
            $keys = $keyCache[$cacheKey]
            $vault = Read-VaultFromFile -Path $info.Path -AesKey $keys.Aes -HmacKey $keys.Hmac
            [void]$targets.Add(@{ Path = $info.Path; Vault = $vault; Kind = $info.Kind })
            if ($info.Kind -eq 'Haupt') { $mainSeen = $true }
        }
        catch {
            if ($info.Kind -eq 'Haupt') {
                Clear-UnusedScanKeys -KeyCache $keyCache -KeepKeys $null
                return $script:VaultNeutralError
            }
            # Nicht entschluesselbares Backup: verschluesselt archivieren statt blockieren
            try {
                if (-not (Test-Path -LiteralPath $script:Paths.Recovery)) {
                    New-Item -ItemType Directory -Path $script:Paths.Recovery -Force | Out-Null
                }
                $archive = Join-Path $script:Paths.Recovery ('vault-unreadable-{0}.azt' -f ([guid]::NewGuid().ToString()))
                Move-Item -LiteralPath $info.Path -Destination $archive -Force
                Write-AppLog -Level 'WARN' -Message ('Passwortänderung: {0} war mit dem bisherigen Passwort nicht lesbar und wurde unverändert nach Recovery verschoben ({1}).' -f $info.Kind, (Split-Path $archive -Leaf))
            }
            catch {
                Write-AppLog -Level 'WARN' -Message ('Passwortänderung: {0} ist mit dem bisherigen Passwort nicht lesbar und konnte nicht nach Recovery verschoben werden; die Datei bleibt unverändert liegen.' -f $info.Kind)
            }
        }
    }
    Clear-UnusedScanKeys -KeyCache $keyCache -KeepKeys $null
    if (-not $mainSeen) { return $script:VaultNeutralError }

    # Phase A: alle neuen Dateien vollstaendig in einem separaten
    # Transaktionsbereich (.new-Dateien) erstellen und jede einzelne mit dem
    # neuen Passwort erneut oeffnen und validieren. Der alte Haupttresor
    # bleibt dabei vollstaendig unveraendert.
    $prepared = New-Object System.Collections.ArrayList
    try {
        foreach ($target in @($targets)) {
            $newPath = $target.Path + '.new'
            Write-VaultToFile -Path $newPath -Vault $target.Vault -AesKey $NewAesKey -HmacKey $NewHmacKey -Salt $NewSalt -Iterations $NewIterations
            Read-VaultFromFile -Path $newPath -AesKey $NewAesKey -HmacKey $NewHmacKey | Out-Null
            [void]$prepared.Add(@{ Orig = $target.Path; New = $newPath; Kind = $target.Kind })
        }
    }
    catch {
        foreach ($p in @($prepared)) {
            try { Remove-Item -LiteralPath $p.New -Force -ErrorAction SilentlyContinue } catch { }
        }
        return ('Die neu verschlüsselten Dateien konnten nicht erstellt oder geprüft werden. Der bisherige Tresor bleibt unverändert. Details: ' + $_.Exception.Message)
    }

    # Neutraler Transaktionsstatus (ohne Arbeitszeitdaten): erlaubt es dem
    # naechsten Programmstart, einen unterbrochenen Vorgang zu erkennen und
    # fortzusetzen oder zurueckzusetzen.
    try {
        [System.IO.File]::WriteAllText($script:Paths.VaultTxn, (New-VaultTxnContent -Prepared $prepared), (New-Object System.Text.UTF8Encoding($true)))
    }
    catch { }

    # Phase B: atomare Uebernahme mit Ruecksicherung im Fehlerfall.
    # Die Backups werden zuerst ausgetauscht, die HAUPTDATEI ZULETZT.
    # Die .old-Dateien (vollstaendiger alter Stand) bleiben erhalten, bis die
    # neue Hauptdatei abschliessend erneut validiert wurde.
    $applyOrder = New-Object System.Collections.ArrayList
    foreach ($p in @($prepared)) { if ($p.Kind -ne 'Haupt') { [void]$applyOrder.Add($p) } }
    foreach ($p in @($prepared)) { if ($p.Kind -eq 'Haupt') { [void]$applyOrder.Add($p) } }
    $done = New-Object System.Collections.ArrayList
    try {
        foreach ($p in @($applyOrder)) {
            $oldAside = $p.Orig + '.old'
            Move-Item -LiteralPath $p.Orig -Destination $oldAside -Force
            $entry = @{ Orig = $p.Orig; Old = $oldAside; Applied = $false }
            [void]$done.Add($entry)
            Move-Item -LiteralPath $p.New -Destination $p.Orig -Force
            $entry.Applied = $true
        }
        # Abschlusspruefung: Die neue Hauptdatei muss sich mit dem neuen
        # Passwort erneut oeffnen lassen, BEVOR alte Dateien entfernt werden.
        Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $NewAesKey -HmacKey $NewHmacKey | Out-Null
        # Das dauerhafte Journal darf keinen Stand mit dem alten Passwort
        # behalten: in-place mit der neuen Hauptdatei ueberschreiben (keine
        # Loeschung im Cloud-Ordner). Ein Fehler hier rollt die bereits
        # validierte Umverschluesselung nicht zurueck.
        if (Test-Path -LiteralPath $script:Paths.VaultPending) {
            try {
                if ($script:TestMode -and $script:App -and $script:App.Flags.TestFailJournalMirror) {
                    throw (New-Object System.IO.IOException 'TESTHOOK: Journalspiegel deaktiviert')
                }
                Write-FileInPlace -Path $script:Paths.VaultPending -Bytes ([System.IO.File]::ReadAllBytes($script:Paths.VaultFile))
            }
            catch {
                Write-AppLog -Level 'WARN' -Message 'Journal (vault.pending.azt) konnte nach der Passwortänderung nicht neu geschrieben werden; es wird beim nächsten Speichern ersetzt.'
            }
        }
        foreach ($d in @($done)) {
            try { Remove-Item -LiteralPath $d.Old -Force -ErrorAction SilentlyContinue } catch { }
        }
        try { Remove-Item -LiteralPath $script:Paths.VaultTxn -Force -ErrorAction SilentlyContinue } catch { }
        return ''
    }
    catch {
        $applyError = $_.Exception.Message
        # Ruecknahme wird ueberprueft: nur wenn jede Zieldatei wieder ihren
        # alten Stand traegt, darf "wiederhergestellt" gemeldet werden.
        $rollbackOk = $true
        $reverse = @($done)
        [array]::Reverse($reverse)
        foreach ($d in $reverse) {
            try {
                if ($d.Applied -and (Test-Path -LiteralPath $d.Orig)) {
                    Move-Item -LiteralPath $d.Orig -Destination ($d.Orig + '.new') -Force
                }
                if ($script:TestMode -and $script:App -and $script:App.Flags.TestFailReencryptRollback) {
                    throw (New-Object System.IO.IOException 'TESTHOOK: Ruecknahme der Umbenennung deaktiviert')
                }
                if (Test-Path -LiteralPath $d.Old) {
                    Move-Item -LiteralPath $d.Old -Destination $d.Orig -Force
                }
            }
            catch { $rollbackOk = $false }
            if (-not (Test-Path -LiteralPath $d.Orig)) { $rollbackOk = $false }
        }
        foreach ($p in @($prepared)) {
            try { Remove-Item -LiteralPath $p.New -Force -ErrorAction SilentlyContinue } catch { }
        }
        if (-not $rollbackOk) {
            # vault.txn bleibt bewusst liegen (unklarer Dateisatz); Start-
            # Reparatur und Bereinigung nach dem Entsperren uebernehmen.
            Write-AppLog -Level 'ERROR' -Message ('Passwortänderung: Übernahme fehlgeschlagen UND Rücknahme unvollständig: ' + $applyError)
            return ('Die Übernahme der neu verschlüsselten Dateien ist fehlgeschlagen, und der bisherige Zustand konnte NICHT vollständig wiederhergestellt werden. ' +
                'Bitte die Anwendung beenden und neu starten - beim Start werden die beiseitegelegten Dateien (.old/.new) erkannt und repariert. ' +
                'Das bisherige Passwort bleibt bis dahin gültig. Details: ' + $applyError)
        }
        try { Remove-Item -LiteralPath $script:Paths.VaultTxn -Force -ErrorAction SilentlyContinue } catch { }
        return ('Die Übernahme der neu verschlüsselten Dateien ist fehlgeschlagen; der bisherige Zustand wurde wiederhergestellt. Details: ' + $applyError)
    }
}

# Ueberschreibt eine vorhandene Datei in-place NUR, wenn ihr aktueller Inhalt
# noch dem uebergebenen SHA-256-Referenzwert entspricht (Schutz vor einer
# zwischenzeitlichen externen Aenderung, z. B. durch OneDrive/SharePoint).
# Pruefung und Schreiben laufen ueber DENSELBEN exklusiv geoeffneten
# Dateihandle - zwischen Pruefung und Ueberschreiben kann kein anderer
# Prozess die Datei veraendern. Die Datei wird weder geloescht noch umbenannt
# (Cloud-Ordner sehen nur eine neue Version derselben Datei).
# Nur fuer die seltene Passwortaenderung (Recovery-Ordner) - der regulaere
# Speicherzyklus verwendet unveraendert Write-FileInPlace.
# Liefert $true (geschrieben) oder $false (Konflikt, nichts geschrieben);
# technische Fehler werden als Ausnahme weitergereicht.
function Write-FileInPlaceIfUnchanged {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][string]$ExpectedSha256
    )
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            try {
                $sha = [System.Security.Cryptography.SHA256]::Create()
                try { $currentHash = [System.BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '' }
                finally { $sha.Dispose() }
                if ($currentHash -ne $ExpectedSha256) { return $false }
                $stream.Position = 0
                $stream.Write($Bytes, 0, $Bytes.Length)
                $stream.SetLength($Bytes.Length)
                $stream.Flush($true)
            }
            finally { $stream.Dispose() }
            return $true
        }
        catch [System.IO.IOException] {
            if ($attempt -ge 3 -or $_.Exception -is [System.IO.DirectoryNotFoundException] -or
                $_.Exception -is [System.IO.FileNotFoundException]) { throw }
            Start-Sleep -Milliseconds 150
        }
    }
}

# Ordnet eine Datei ein, deren Containerformat ungueltig ist (nur fuer den
# Bericht, keine Entscheidung ueber Dateioperationen): traegt der Dateianfang
# die Formatkennung, ist es ein beschaedigter Tresorcontainer ('Corrupt'),
# sonst eine fremde Datei ohne Tresorformat ('NotContainer').
# Zugriffsfehler werden weitergereicht.
function Get-RecoveryContainerDefectKind {
    param([Parameter(Mandatory)][string]$Path)
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        $buffer = New-Object byte[] 512
        $count = $fs.Read($buffer, 0, $buffer.Length)
    }
    finally { $fs.Dispose() }
    $head = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $count)
    if ($head -match ('"Magic"\s*:\s*"' + $script:VaultConst.Magic + '"')) { return 'Corrupt' }
    return 'NotContainer'
}

# Neutrale Kurzbezeichnung eines technischen Fehlers fuer Bericht und
# Protokoll (keine Pfade, keine Inhalte).
function Get-RecoveryErrorText {
    param($Exception)
    # .NET-Methodenaufrufe liefern den eigentlichen Fehler als InnerException
    while ($Exception -is [System.Management.Automation.MethodException] -and $null -ne $Exception.InnerException) {
        $Exception = $Exception.InnerException
    }
    if ($Exception -is [System.UnauthorizedAccessException]) { return 'Zugriff verweigert' }
    if ($Exception -is [System.IO.FileNotFoundException]) { return 'Datei nicht mehr vorhanden' }
    if ($Exception -is [System.IO.DirectoryNotFoundException]) { return 'Ordner nicht mehr vorhanden' }
    if ($Exception -is [System.IO.IOException]) { return 'Datei gesperrt oder Lese-/Schreibfehler' }
    if ($Exception -is [System.InvalidOperationException] -and $Exception.Message -eq 'VAULT_NEWER') { return 'neueres Containerformat' }
    if ($Exception -is [System.InvalidOperationException] -and $Exception.Message -eq 'VAULT_INVALID') { return 'Prüfung des Ergebnisses fehlgeschlagen' }
    return ('technischer Fehler: ' + $Exception.GetType().Name)
}

# Verschluesselt nach einer erfolgreichen Passwortaenderung alle Container im
# Recovery-Ordner neu, die sich mit dem BISHERIGEN Passwort oeffnen lassen
# (Cloud-Konfliktkopien, Archive von Alt-/Importdaten, beiseitegelegte
# Tresorstaende). Ohne diesen Schritt blieben sie mit dem alten Passwort
# lesbar. Der Klartext wird auf Containerebene unveraendert uebernommen
# (auch Nicht-Tresorinhalte wie legacy-Archive).
# Jede Datei wird genau einer Kategorie zugeordnet:
#  - Reencrypted:  neu verschluesselt und geprueft
#  - Foreign:      gueltiger Container, den das bisherige Passwort nicht
#                  oeffnet (anderes Passwort, z. B. bewusst archivierter
#                  Tresor eines frueheren Passworts, oder manipuliert - per
#                  HMAC nicht unterscheidbar) -> bewusst unveraendert
#  - Corrupt:      Tresorcontainer mit zerstoertem Format -> unveraendert
#  - NotContainer: Datei ohne Tresorformat -> unveraendert
#  - Failed:       technischer Fehler (gesperrt, Zugriff verweigert, Ordner
#                  nicht auflistbar, extern veraendert, ...) - die Datei ist
#                  moeglicherweise WEITERHIN mit dem bisherigen Passwort
#                  lesbar; die Passwortaenderung gilt damit nur als teilweise
#                  erfolgreich
#  - CleanupFailed: neu verschluesselt, nur die temporaere Kopie '<Datei>.new'
#                  (neues Passwort, gleicher Inhalt) liess sich nicht entfernen
# Ablauf je Datei - nur bei der seltenen Passwortaenderung, nie im
# regulaeren Speicherzyklus: SHA-256-Referenz bilden -> entschluesseln ->
# neu verschluesseln -> als NEUE Kopie '<Datei>.new' schreiben (niemals eine
# vorhandene ueberschreiben) und pruefen -> Original nur bei unveraendertem
# Referenzwert in-place ueberschreiben und pruefen -> Kopie entfernen. Bei
# einem Abbruch liegt immer mindestens eine vollstaendige Fassung vor; Reste
# erkennt Resolve-RecoveryReencryptionLeftovers beim naechsten Start.
# Liefert @{ Reencrypted = <int>; Skipped = <int> (Foreign+Corrupt+
# NotContainer); Foreign/Corrupt/NotContainer/CleanupFailed = <Dateinamen>;
# Failed = <'Dateiname: Grund'> }.
function Invoke-RecoveryReencryption {
    param(
        [Parameter(Mandatory)][byte[]]$OldPasswordBytes,
        [Parameter(Mandatory)][byte[]]$NewAesKey,
        [Parameter(Mandatory)][byte[]]$NewHmacKey,
        [Parameter(Mandatory)][byte[]]$NewSalt,
        [Parameter(Mandatory)][int]$NewIterations
    )
    $result = @{
        Reencrypted   = 0
        Skipped       = 0
        Foreign       = (New-Object System.Collections.ArrayList)
        Corrupt       = (New-Object System.Collections.ArrayList)
        NotContainer  = (New-Object System.Collections.ArrayList)
        Failed        = (New-Object System.Collections.ArrayList)
        CleanupFailed = (New-Object System.Collections.ArrayList)
    }
    if (-not (Test-Path -LiteralPath $script:Paths.Recovery)) { return $result }
    # Ein nicht auflistbarer Ordner ist ein Fehler, kein leerer Ordner
    $files = $null
    try {
        if ($script:TestMode -and $script:App -and $script:App.Flags.TestFailRecoveryList) {
            throw (New-Object System.UnauthorizedAccessException 'TESTHOOK: Auflistung des Recovery-Ordners verweigert')
        }
        $files = @(Get-ChildItem -LiteralPath $script:Paths.Recovery -Filter '*.azt' -File -ErrorAction Stop)
    }
    catch {
        [void]$result.Failed.Add('Ordner Recovery: Inhalt nicht auflistbar (' + (Get-RecoveryErrorText -Exception $_.Exception) + ')')
        return $result
    }
    $keyCache = @{}
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    try {
        foreach ($file in $files) {
            # Der Win32-Filter trifft auch laengere Endungen - exakt pruefen
            if ($file.Extension -ne '.azt') { continue }
            $copyPath = $file.FullName + '.new'
            # Eine Restkopie eines frueheren, nicht eindeutig aufgeloesten
            # Vorgangs wird niemals ueberschrieben
            if (Test-Path -LiteralPath $copyPath) {
                [void]$result.Failed.Add($file.Name + ': unklare Restdatei ' + $file.Name + '.new eines früheren Vorgangs vorhanden - nicht verändert')
                continue
            }
            # 1. Referenzwert und Entschluesselung - jede Fehlerursache getrennt
            $plain = $null
            $oldKeys = $null
            $refHash = $null
            $stage = 'Lesen'
            try {
                if ($script:TestMode -and $script:App -and $script:App.Flags.TestRecoveryDenyRead -and $file.Name -eq $script:App.Flags.TestRecoveryDenyRead) {
                    throw (New-Object System.UnauthorizedAccessException 'TESTHOOK: Lesezugriff verweigert')
                }
                $refHash = Get-FileSha256Hex -Path $file.FullName
                if ($null -eq $refHash) { throw (New-Object System.IO.FileNotFoundException $file.Name) }
                $stage = 'Format'
                $container = Read-VaultContainerFromFile -Path $file.FullName
                $stage = 'Schluessel'
                $cacheKey = [Convert]::ToBase64String($container.Salt) + '|' + $container.Iterations
                if (-not $keyCache.ContainsKey($cacheKey)) {
                    $keyCache[$cacheKey] = Get-VaultKeysFromPassword -PasswordBytes $OldPasswordBytes -Salt $container.Salt -Iterations $container.Iterations
                }
                $oldKeys = $keyCache[$cacheKey]
                $stage = 'Entschluesseln'
                $plain = Unprotect-VaultContainer -Container $container -AesKey $oldKeys.Aes -HmacKey $oldKeys.Hmac
            }
            catch {
                $ex = $_.Exception
                $isInvalid = ($ex -is [System.InvalidOperationException] -and $ex.Message -eq 'VAULT_INVALID')
                if ($isInvalid -and $stage -eq 'Entschluesseln') {
                    # HMAC passt nicht: anderes Passwort (oder manipuliert)
                    [void]$result.Foreign.Add($file.Name)
                }
                elseif ($isInvalid -and $stage -eq 'Format') {
                    try {
                        if ((Get-RecoveryContainerDefectKind -Path $file.FullName) -eq 'Corrupt') { [void]$result.Corrupt.Add($file.Name) }
                        else { [void]$result.NotContainer.Add($file.Name) }
                    }
                    catch { [void]$result.Failed.Add($file.Name + ': ' + (Get-RecoveryErrorText -Exception $_.Exception)) }
                }
                else {
                    # Technischer Fehler: NICHT als regulaeres Ueberspringen werten
                    [void]$result.Failed.Add($file.Name + ': ' + (Get-RecoveryErrorText -Exception $ex))
                }
                continue
            }
            # 2. Neu verschluesseln, Kopie anlegen, Original bedingt ueberschreiben
            $copyCreated = $false
            $committed = $false
            $failReason = ''
            try {
                $containerJson = Protect-VaultContainer -PlainText $plain -AesKey $NewAesKey -HmacKey $NewHmacKey -Salt $NewSalt -Iterations $NewIterations
                $preamble = $utf8Bom.GetPreamble()
                $body = $utf8Bom.GetBytes($containerJson)
                $bytes = New-Object byte[] ($preamble.Length + $body.Length)
                [System.Array]::Copy($preamble, 0, $bytes, 0, $preamble.Length)
                [System.Array]::Copy($body, 0, $bytes, $preamble.Length, $body.Length)
                $verifyCopy = {
                    param([string]$Path)
                    $check = Unprotect-VaultContainer -Container (Read-VaultContainerFromFile -Path $Path) -AesKey $NewAesKey -HmacKey $NewHmacKey
                    if (-not [string]::Equals($check, $plain, [System.StringComparison]::Ordinal)) {
                        throw (New-Object System.InvalidOperationException 'VAULT_INVALID')
                    }
                }
                # CreateNew: eine zwischenzeitlich entstandene Datei gleichen
                # Namens wird nie ueberschrieben
                $copyStream = New-Object System.IO.FileStream($copyPath, [System.IO.FileMode]::CreateNew,
                    [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                $copyCreated = $true
                try {
                    $copyStream.Write($bytes, 0, $bytes.Length)
                    $copyStream.Flush($true)
                }
                finally { $copyStream.Dispose() }
                & $verifyCopy $copyPath
                if ($script:TestMode -and $script:App -and $script:App.Flags.TestFailRecoveryWrite) {
                    throw (New-Object System.IO.IOException 'TESTHOOK: Neuverschluesselung in Recovery deaktiviert')
                }
                if ($script:TestMode -and $script:App -and $script:App.Flags.TestRecoveryBeforeCommit) {
                    & $script:App.Flags.TestRecoveryBeforeCommit $file.FullName
                }
                if (-not (Write-FileInPlaceIfUnchanged -Path $file.FullName -Bytes $bytes -ExpectedSha256 $refHash)) {
                    $failReason = 'zwischenzeitlich extern verändert (Konflikt) - nicht überschrieben'
                    throw (New-Object System.InvalidOperationException 'RECOVERY_CONFLICT')
                }
                & $verifyCopy $file.FullName
                $committed = $true
            }
            catch {
                if ($failReason -eq '') { $failReason = 'Neuverschlüsselung fehlgeschlagen (' + (Get-RecoveryErrorText -Exception $_.Exception) + ')' }
                [void]$result.Failed.Add($file.Name + ': ' + $failReason)
                # Die eigene Pruefkopie nur entfernen, wenn das Original noch
                # vollstaendig mit dem bisherigen Passwort und identischem
                # Inhalt lesbar ist - sonst bleibt sie als vollstaendige Fassung.
                if ($copyCreated) {
                    try {
                        $orig = Unprotect-VaultContainer -Container (Read-VaultContainerFromFile -Path $file.FullName) -AesKey $oldKeys.Aes -HmacKey $oldKeys.Hmac
                        if ([string]::Equals($orig, $plain, [System.StringComparison]::Ordinal) -and (Test-Path -LiteralPath $copyPath)) {
                            Remove-Item -LiteralPath $copyPath -Force
                        }
                    }
                    catch { }
                }
            }
            if (-not $committed) { continue }
            # 3. Bereinigung getrennt bewerten: die Neuverschluesselung ist
            #    bereits vollstaendig und geprueft abgeschlossen
            $result.Reencrypted++
            try {
                if ($script:TestMode -and $script:App -and $script:App.Flags.TestFailRecoveryCleanup) {
                    throw (New-Object System.IO.IOException 'TESTHOOK: Entfernen der Pruefkopie deaktiviert')
                }
                Remove-Item -LiteralPath $copyPath -Force
            }
            catch { [void]$result.CleanupFailed.Add($file.Name + '.new') }
        }
    }
    finally {
        Clear-UnusedScanKeys -KeyCache $keyCache -KeepKeys $null
    }
    $result.Skipped = $result.Foreign.Count + $result.Corrupt.Count + $result.NotContainer.Count
    return $result
}

# Neutraler Transaktionsstatus fuer die Recovery-Phase einer
# Passwortaenderung (gleiche Datei vault.txn, keine Pfade/Dateinamen). Er
# wird nach der erfolgreichen Umverschluesselung des Tresors geschrieben und
# erst nach Abschluss der Recovery-Neuverschluesselung entfernt. Findet der
# naechste Start ihn vor, wurde der Vorgang unterbrochen: Dateien in Recovery
# koennen dann noch mit dem bisherigen Passwort lesbar sein.
function Set-RecoveryReencryptionMarker {
    $content = [ordered]@{
        Id    = [guid]::NewGuid().ToString()
        Kind  = 'RecoveryReencryption'
        Phase = 'Recovery'
        Files = @()
    } | ConvertTo-Json
    [System.IO.File]::WriteAllText($script:Paths.VaultTxn, $content, (New-Object System.Text.UTF8Encoding($true)))
}

# Reine Lesefunktion: $true, wenn vault.txn den Marker einer unterbrochenen
# Recovery-Neuverschluesselung traegt. Muss VOR
# Complete-VaultTransactionCleanup aufgerufen werden (diese entfernt vault.txn).
function Test-RecoveryReencryptionInterrupted {
    if (-not (Test-Path -LiteralPath $script:Paths.VaultTxn)) { return $false }
    try {
        $txn = [System.IO.File]::ReadAllText($script:Paths.VaultTxn) | ConvertFrom-Json
        return ([string]$txn.Kind -eq 'RecoveryReencryption')
    }
    catch { return $false }
}

# Liest eine Datei mit den Sitzungsschluesseln. Liefert @{ State; Text }:
#  'Session'  lesbar, Text = Klartext
#  'OtherKey' gueltiger Container mit anderem Salt/anderen Iterationen
#             (anderes bzw. bisheriges Passwort)
#  'Damaged'  gueltiges Format mit dem Salt der Sitzung, aber ungueltigem
#             HMAC - typisch fuer ein abgebrochenes In-place-Ueberschreiben
#             mit dem eigenen neuen Stand (Kopf neu, Rest alt)
#  'Invalid'  Containerformat zerstoert
# Zugriffsfehler werden weitergereicht (keine Entscheidung auf unsicherer Basis).
function Get-RecoveryFileState {
    param([Parameter(Mandatory)][string]$Path)
    try { $container = Read-VaultContainerFromFile -Path $Path }
    catch [System.InvalidOperationException] {
        if ($_.Exception.Message -eq 'VAULT_INVALID') { return @{ State = 'Invalid'; Text = $null } }
        return @{ State = 'OtherKey'; Text = $null }
    }
    if (-not [ArbeitszeitTool.VaultCrypto]::FixedTimeEquals($container.Salt, $script:VaultSession.Salt) -or
        [int]$container.Iterations -ne [int]$script:VaultSession.Iterations) {
        return @{ State = 'OtherKey'; Text = $null }
    }
    try { $text = Unprotect-VaultContainer -Container $container -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey }
    catch [System.InvalidOperationException] { return @{ State = 'Damaged'; Text = $null } }
    return @{ State = 'Session'; Text = $text }
}

# Loest nach dem Entsperren Reste einer unterbrochenen Recovery-
# Neuverschluesselung ('<Datei>.azt.new') auf - NUR wenn eindeutig ist,
# welcher Stand gueltig ist; alles andere bleibt unveraendert und wird
# gemeldet:
#  - Kopie und Original mit aktuellem Passwort lesbar, identischer Inhalt
#    (Abbruch beim Aufraeumen)              -> Kopie entfernen
#  - Kopie vollstaendig gueltig, Original zerstoert bzw. mit dem eigenen
#    Salt angerissen (Abbruch beim Ueberschreiben) -> Original in-place aus der
#                                              Kopie herstellen, pruefen,
#                                              dann Kopie entfernen
#  - Kopie unvollstaendig/nicht lesbar, Original noch mit anderem Passwort,
#    Original fehlt, Inhalte verschieden oder Zugriffsfehler -> UNKLAR:
#    beide Dateien bleiben byteidentisch erhalten
# Liefert @{ Completed = <Namen>; Removed = <Namen>; Unclear = <'Name: Grund'> }.
function Resolve-RecoveryReencryptionLeftovers {
    $result = @{
        Completed = (New-Object System.Collections.ArrayList)
        Removed   = (New-Object System.Collections.ArrayList)
        Unclear   = (New-Object System.Collections.ArrayList)
    }
    if (-not $script:VaultSession.Unlocked) { return $result }
    if (-not (Test-Path -LiteralPath $script:Paths.Recovery)) { return $result }
    $copies = $null
    try { $copies = @(Get-ChildItem -LiteralPath $script:Paths.Recovery -Filter '*.azt.new' -File -ErrorAction Stop) }
    catch {
        [void]$result.Unclear.Add('Ordner Recovery: Inhalt nicht auflistbar (' + (Get-RecoveryErrorText -Exception $_.Exception) + ')')
        return $result
    }
    foreach ($copy in $copies) {
        if (-not $copy.Name.EndsWith('.azt.new', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $origPath = $copy.FullName.Substring(0, $copy.FullName.Length - 4)
        $origName = Split-Path $origPath -Leaf
        try {
            $copyState = Get-RecoveryFileState -Path $copy.FullName
            if ($copyState.State -ne 'Session') {
                [void]$result.Unclear.Add($copy.Name + ': Kopie unvollständig oder nicht mit dem aktuellen Passwort lesbar')
                continue
            }
            if (-not (Test-Path -LiteralPath $origPath)) {
                [void]$result.Unclear.Add($copy.Name + ': Originaldatei fehlt')
                continue
            }
            $origState = Get-RecoveryFileState -Path $origPath
            if ($origState.State -eq 'Session') {
                if ([string]::Equals($origState.Text, $copyState.Text, [System.StringComparison]::Ordinal)) {
                    Remove-Item -LiteralPath $copy.FullName -Force
                    [void]$result.Removed.Add($copy.Name)
                }
                else {
                    [void]$result.Unclear.Add($copy.Name + ': Inhalt weicht vom Original ab')
                }
                continue
            }
            if ($origState.State -eq 'OtherKey') {
                [void]$result.Unclear.Add($origName + ': noch mit einem anderen Passwort verschlüsselt; neu verschlüsselte Kopie ' + $copy.Name + ' vorhanden')
                continue
            }
            # Original zerstoert ('Invalid'/'Damaged'), Kopie vollstaendig:
            # die Kopie ist der einzige vollstaendige Stand -> wiederherstellen
            $origHash = Get-FileSha256Hex -Path $origPath
            $copyBytes = [System.IO.File]::ReadAllBytes($copy.FullName)
            if (-not (Write-FileInPlaceIfUnchanged -Path $origPath -Bytes $copyBytes -ExpectedSha256 $origHash)) {
                [void]$result.Unclear.Add($origName + ': während der Prüfung extern verändert')
                continue
            }
            $check = Get-RecoveryFileState -Path $origPath
            if ($check.State -ne 'Session' -or -not [string]::Equals($check.Text, $copyState.Text, [System.StringComparison]::Ordinal)) {
                [void]$result.Unclear.Add($origName + ': Wiederherstellung nicht bestätigt - Kopie bleibt erhalten')
                continue
            }
            [void]$result.Completed.Add($origName)
            Remove-Item -LiteralPath $copy.FullName -Force
        }
        catch {
            [void]$result.Unclear.Add($copy.Name + ': ' + (Get-RecoveryErrorText -Exception $_.Exception))
        }
    }
    return $result
}

# Startpruefung nach dem Entsperren: loest Reste einer unterbrochenen
# Recovery-Neuverschluesselung auf und informiert, wenn Dateien in Recovery
# moeglicherweise noch mit dem bisherigen Passwort lesbar sind.
#  -Interrupted: Ergebnis von Test-RecoveryReencryptionInterrupted.
# Liefert den Hinweistext ('' = nichts zu melden).
function Invoke-RecoveryStartupCheck {
    param([bool]$Interrupted = $false)
    $res = Resolve-RecoveryReencryptionLeftovers
    foreach ($name in @($res.Completed)) { Write-AppLog -Level 'WARN' -Message ('Recovery: unterbrochene Neuverschlüsselung abgeschlossen, Datei aus geprüfter Kopie wiederhergestellt: ' + $name) }
    foreach ($name in @($res.Removed)) { Write-AppLog -Message ('Recovery: verbliebene Prüfkopie mit identischem Inhalt entfernt: ' + $name) }
    foreach ($entry in @($res.Unclear)) { Write-AppLog -Level 'WARN' -Message ('Recovery: unklarer Zwischenstand, Dateien unverändert belassen: ' + $entry) }
    $text = ''
    if ($Interrupted) {
        Write-AppLog -Level 'WARN' -Message 'Die Neuverschlüsselung des Recovery-Ordners bei der letzten Passwortänderung wurde unterbrochen.'
        $notCurrent = New-Object System.Collections.ArrayList
        try {
            if (Test-Path -LiteralPath $script:Paths.Recovery) {
                foreach ($f in @(Get-ChildItem -LiteralPath $script:Paths.Recovery -Filter '*.azt' -File -ErrorAction Stop)) {
                    if ($f.Extension -ne '.azt') { continue }
                    if (-not (Test-VaultFileAuthentication -Path $f.FullName)) { [void]$notCurrent.Add($f.Name) }
                }
            }
        }
        catch { [void]$notCurrent.Add('Ordner Recovery: Inhalt nicht auflistbar') }
        $text = 'Die letzte Passwortänderung wurde abgeschlossen, die anschließende Neuverschlüsselung des Ordners ''Recovery'' jedoch unterbrochen (z. B. Absturz oder Stromausfall).'
        if ($notCurrent.Count -gt 0) {
            $text += ("`r`n`r`nFolgende Dateien im Ordner 'Recovery' sind nicht mit dem aktuellen Passwort verschlüsselt und können daher noch mit dem BISHERIGEN Passwort lesbar sein " +
                "(darunter ggf. auch bewusst archivierte Bestände eines anderen Passworts):`r`n") + ($notCurrent -join "`r`n")
        }
    }
    if ($res.Unclear.Count -gt 0) {
        if ($text -ne '') { $text += "`r`n`r`n" }
        $text += ("Im Ordner 'Recovery' liegen Zwischenstände einer unterbrochenen Neuverschlüsselung, deren gültiger Stand nicht eindeutig feststeht. " +
            "Sie wurden NICHT verändert oder gelöscht:`r`n") + (@($res.Unclear) -join "`r`n")
    }
    if ($text -ne '') {
        $text += "`r`n`r`nAlle Dateien bleiben unverändert erhalten. Details stehen im Protokoll."
    }
    return $text
}

# Prueft nach einer Passwortaenderung, welche Tresordateien im Ordner Data
# (Haupt, Journal, Backups sowie .old/.new-Reste) NICHT mit den neuen
# Sitzungsschluesseln authentifizierbar sind - sie koennten noch mit dem
# bisherigen Passwort lesbar sein. Reine Lesefunktion, liefert Dateinamen.
function Get-PasswordChangeDataResidue {
    $residue = New-Object System.Collections.ArrayList
    foreach ($path in @($script:Paths.VaultFile, $script:Paths.VaultPending, $script:Paths.VaultBackup1, $script:Paths.VaultBackup2)) {
        foreach ($candidate in @($path, ($path + '.old'), ($path + '.new'))) {
            if (-not (Test-Path -LiteralPath $candidate)) { continue }
            if (-not (Test-VaultFileAuthentication -Path $candidate)) { [void]$residue.Add((Split-Path $candidate -Leaf)) }
        }
    }
    return ,$residue
}

# Erstellt aus den Teilergebnissen einer Passwortaenderung (nach erfolgreicher
# Umverschluesselung des Tresors) Status und Meldungstext. Reine Funktion.
#  Status 'Vollstaendig'            - alles umgestellt und bereinigt
#         'VollstaendigBereinigung' - alles umgestellt, nur temporaere Kopien
#                                     (neues Passwort) nicht entfernt
#         'Teilweise'               - mindestens eine Datei ist moeglicher-
#                                     weise weiterhin mit dem bisherigen
#                                     Passwort lesbar oder nicht pruefbar
#  SaveOk = $false ergaenzt den Hinweis auf den fehlgeschlagenen
#  abschliessenden Speichervorgang (Level dann immer 'Warning').
# Liefert @{ Status; Level ('Info'|'Warning'); Message }.
function Get-PasswordChangeReport {
    param(
        [bool]$SaveOk = $true,
        [Parameter(Mandatory)]$Recovery,
        $DataResidue = @()
    )
    # Fehlende Listen zaehlen als leer (@($null) haette sonst ein Element)
    $failed = @($Recovery.Failed | Where-Object { $null -ne $_ })
    $cleanup = @($Recovery.CleanupFailed | Where-Object { $null -ne $_ })
    $residue = @($DataResidue | Where-Object { $null -ne $_ })
    $kept = @($Recovery.Foreign | Where-Object { $null -ne $_ }).Count + @($Recovery.Corrupt | Where-Object { $null -ne $_ }).Count +
        @($Recovery.NotContainer | Where-Object { $null -ne $_ }).Count
    $status = 'Vollstaendig'
    if ($failed.Count -gt 0 -or $residue.Count -gt 0) { $status = 'Teilweise' }
    elseif ($cleanup.Count -gt 0) { $status = 'VollstaendigBereinigung' }

    $text = ''
    if ($status -eq 'Teilweise') {
        $text = 'Das Verschlüsselungspasswort wurde geändert, die Umstellung ist jedoch NUR TEILWEISE erfolgreich.'
        if ($residue.Count -gt 0) {
            $text += ("`r`n`r`nACHTUNG: Folgende Dateien im Ordner 'Data' sind nicht mit dem neuen Passwort verschlüsselt bzw. nicht prüfbar und können weiterhin mit dem BISHERIGEN Passwort lesbar sein:`r`n") +
                ($residue -join "`r`n")
        }
        if ($failed.Count -gt 0) {
            $text += ("`r`n`r`nACHTUNG: {0} Datei(en) im Ordner 'Recovery' konnten nicht geprüft oder neu verschlüsselt werden und können weiterhin mit dem BISHERIGEN Passwort lesbar sein:`r`n" -f $failed.Count) +
                ($failed -join "`r`n") + "`r`nDiese Dateien bleiben unverändert erhalten. Bitte die Ursache prüfen (z. B. Sperre durch eine Synchronisierung oder fehlende Berechtigung); nicht mehr benötigte Dateien können manuell entfernt werden."
        }
    }
    else {
        $text = 'Das Verschlüsselungspasswort wurde erfolgreich geändert; alle mit dem bisherigen Passwort lesbaren Dateien wurden neu verschlüsselt.'
    }
    if ($cleanup.Count -gt 0) {
        $text += ("`r`n`r`nHinweis: Folgende temporäre Kopien konnten nicht entfernt werden. Sie enthalten dieselben Daten, verschlüsselt mit dem NEUEN Passwort, und werden beim nächsten Start automatisch entfernt:`r`n") +
            ($cleanup -join "`r`n")
    }
    if ($kept -gt 0) {
        $text += ("`r`n`r`n{0} Datei(en) im Ordner 'Recovery' gehören nicht zum bisherigen Passwort (z. B. bewusst archivierte Bestände), sind beschädigt oder keine Tresordateien und wurden bewusst unverändert gelassen (Details im Protokoll)." -f $kept)
    }
    $level = 'Info'
    if ($status -eq 'Teilweise') { $level = 'Warning' }
    if (-not $SaveOk) {
        $level = 'Warning'
        $text += ("`r`n`r`nDer anschließende reguläre Tresorspeichervorgang ist jedoch FEHLGESCHLAGEN - der Zustand wird als " +
            'NICHT GESPEICHERT angezeigt und automatisch erneut versucht.')
    }
    $text += "`r`n`r`nHinweis: Frühere Dateiversionen im Versionsverlauf oder Papierkorb eines Cloud-Speichers bleiben mit dem bisherigen Passwort lesbar."
    return @{ Status = $status; Level = $level; Message = $text }
}

# Erkennt beim Programmstart Zwischenzustaende einer unterbrochenen
# Passwortaenderung oder eines unterbrochenen Speichervorgangs (.new-, .old-,
# .prev-Dateien, Transaktionsstatus) und stellt einen eindeutig benannten
# Dateisatz her, BEVOR das Passwort abgefragt wird:
#  - fehlt eine Zieldatei und existiert ihre .old-Datei: .old zurueckholen
#  - fehlt eine Zieldatei und existiert nur ihre .new-Datei: .new uebernehmen
#  - fehlt vault.azt und existiert vault.prev.azt: prev zurueckholen
# Verbleibende .new-/.old-Dateien werden nach dem Entsperren kontrolliert
# aufgeraeumt (Complete-VaultTransactionCleanup) - niemals stillschweigend
# geloescht, sondern in den Recovery-Bereich archiviert.
function Repair-VaultTransactionState {
    $repaired = $false
    try {
        if ((Test-Path -LiteralPath $script:Paths.VaultPrev) ) {
            if (-not (Test-Path -LiteralPath $script:Paths.VaultFile)) {
                Move-Item -LiteralPath $script:Paths.VaultPrev -Destination $script:Paths.VaultFile -Force
                $repaired = $true
            }
        }
        foreach ($path in @($script:Paths.VaultFile, $script:Paths.VaultBackup1, $script:Paths.VaultBackup2)) {
            $oldPath = $path + '.old'
            $newPath = $path + '.new'
            if (-not (Test-Path -LiteralPath $path)) {
                if (Test-Path -LiteralPath $oldPath) {
                    Move-Item -LiteralPath $oldPath -Destination $path -Force
                    $repaired = $true
                }
                elseif (Test-Path -LiteralPath $newPath) {
                    Move-Item -LiteralPath $newPath -Destination $path -Force
                    $repaired = $true
                }
            }
        }
    }
    catch { }
    if ($repaired) {
        Write-AppLog -Level 'WARN' -Message 'Zwischenzustand einer unterbrochenen Passwortänderung oder Speicherung beim Start erkannt und repariert.'
    }
    return $repaired
}

# Raeumt nach dem erfolgreichen Entsperren verbliebene .new-/.old-/.prev-
# Dateien und den Transaktionsstatus kontrolliert auf:
#  - Dateien, die mit den aktuellen Sitzungsschluesseln verwendbar sind und
#    deren Ziel fehlt oder unbrauchbar ist, werden uebernommen
#  - alle uebrigen Reste werden verschluesselt in den Recovery-Bereich
#    verschoben (kein gemischter, dauerhaft unklarer Dateisatz; nichts wird
#    geloescht, bevor die aktuelle Hauptdatei validiert wurde - das hat das
#    Entsperren bereits geleistet)
function Complete-VaultTransactionCleanup {
    if (-not $script:VaultSession.Unlocked) { return }
    $mainReplaced = $false
    foreach ($path in @($script:Paths.VaultFile, $script:Paths.VaultBackup1, $script:Paths.VaultBackup2)) {
        foreach ($suffix in @('.old', '.new')) {
            $leftover = $path + $suffix
            if (-not (Test-Path -LiteralPath $leftover)) { continue }
            # Vollstaendige Pruefung: nur eine nachweislich strukturell
            # verwendbare Restdatei darf ein Ziel ersetzen.
            $targetUsable = Test-VaultFileFullyUsable -Path $path
            $leftoverUsable = Test-VaultFileFullyUsable -Path $leftover
            if ($leftoverUsable -and -not $targetUsable) {
                # Rest ist mit dem aktuellen Passwort nutzbar, Ziel nicht:
                # Rest uebernehmen, unbrauchbares Ziel archivieren.
                try {
                    if (Test-Path -LiteralPath $path) { Move-FileToRecovery -Path $path -Prefix 'vault-unreadable' | Out-Null }
                    Move-Item -LiteralPath $leftover -Destination $path -Force
                    if ($path -eq $script:Paths.VaultFile) { $mainReplaced = $true }
                    Write-AppLog -Level 'WARN' -Message ('Rest einer unterbrochenen Passwortänderung übernommen: ' + (Split-Path $path -Leaf))
                }
                catch { }
            }
            else {
                try {
                    Move-FileToRecovery -Path $leftover -Prefix 'vault-txnrest' | Out-Null
                    Write-AppLog -Message ('Rest einer unterbrochenen Passwortänderung in Recovery archiviert: ' + (Split-Path $leftover -Leaf))
                }
                catch { }
            }
        }
    }
    if (Test-Path -LiteralPath $script:Paths.VaultPrev) {
        try { Move-FileToRecovery -Path $script:Paths.VaultPrev -Prefix 'vault-prev' | Out-Null } catch { }
    }
    if (Test-Path -LiteralPath $script:Paths.VaultTxn) {
        try { Remove-Item -LiteralPath $script:Paths.VaultTxn -Force -ErrorAction SilentlyContinue } catch { }
    }
    # Hat die Bereinigung selbst die Hauptdatei ersetzt: die neue Hauptdatei
    # vollstaendig validieren und die Referenz (Hash, Existenz, Revision)
    # aktualisieren. Die eigene Transaktionsbereinigung darf beim naechsten
    # Speichern NICHT faelschlich als externe Cloud-Aenderung gelten.
    # (LoadedFrom bleibt bewusst unveraendert: stammt der geladene Stand aus
    # einem Backup, laeuft der naechste Speichervorgang weiterhin als
    # explizit erkannter Wiederherstellungsvorgang mit Vollpruefung.)
    if ($mainReplaced -and $script:App) {
        try {
            $adopted = Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
            $script:App.VaultFileHash = Get-FileSha256Hex -Path $script:Paths.VaultFile
            $script:App.VaultFileExistedAtLoad = $true
            $script:App.VaultLoadedRevision = [long]$adopted['Revision']
        }
        catch {
            Write-AppLog -Level 'WARN' -Message 'Die übernommene Hauptdatei konnte nicht erneut validiert werden; die Referenz wurde nicht aktualisiert.'
        }
    }
}

# Prueft vor einer Passwortaenderung, ob die Hauptdatei seit dem letzten
# Laden/Speichern unveraendert ist (gleicher Massstab wie Save-Vault).
# Ohne diese Pruefung wuerde eine extern (z. B. per Cloud-Synchronisierung)
# veraenderte vault.azt stillschweigend neu verschluesselt und als eigener
# Stand uebernommen. Reine Lesefunktion, liefert $true/$false.
function Test-VaultMainFileUnchanged {
    if ($null -eq $script:App -or -not $script:App.VaultFileHash) { return $false }
    try { return ((Get-FileSha256Hex -Path $script:Paths.VaultFile) -eq $script:App.VaultFileHash) }
    catch { return $false }
}

# Zweiter Teil einer Passwortaenderung, NACHDEM Invoke-VaultReencryption den
# Tresor erfolgreich umgestellt und die Sitzung die neuen Schluessel hat:
#  1. Transaktionsstatus der Recovery-Phase setzen (Abbruch erkennbar)
#  2. abschliessend regulaer speichern (Save-Vault, unveraendert)
#  3. verbliebene .old/.new-Reste im Ordner Data (bisheriges Passwort) wie
#     bei der Startbereinigung nach Recovery sichern, damit sie im
#     naechsten Schritt mit umgestellt werden
#  4. Recovery-Container neu verschluesseln
#  5. Data-Ordner auf nicht umgestellte Dateien pruefen
#  6. Transaktionsstatus entfernen, Ergebnis bewerten und protokollieren
# Liefert den Bericht von Get-PasswordChangeReport (Status/Level/Message).
function Complete-PasswordChangeFollowUp {
    param([Parameter(Mandatory)][byte[]]$OldPasswordBytes)
    try { Set-RecoveryReencryptionMarker }
    catch { Write-AppLog -Level 'WARN' -Message 'Passwortänderung: Transaktionsstatus der Recovery-Phase konnte nicht geschrieben werden.' }
    $saveOk = Save-Vault
    foreach ($path in @($script:Paths.VaultFile, $script:Paths.VaultBackup1, $script:Paths.VaultBackup2)) {
        foreach ($suffix in @('.old', '.new')) {
            $leftover = $path + $suffix
            if (-not (Test-Path -LiteralPath $leftover)) { continue }
            try {
                $target = Move-FileToRecovery -Path $leftover -Prefix 'vault-txnrest'
                Write-AppLog -Level 'WARN' -Message ('Passwortänderung: nicht entfernter Rest {0} nach Recovery gesichert ({1}).' -f (Split-Path $leftover -Leaf), (Split-Path $target -Leaf))
            }
            catch {
                Write-AppLog -Level 'WARN' -Message ('Passwortänderung: Rest {0} konnte nicht nach Recovery gesichert werden.' -f (Split-Path $leftover -Leaf))
            }
        }
    }
    try {
        $recovery = Invoke-RecoveryReencryption -OldPasswordBytes $OldPasswordBytes `
            -NewAesKey $script:VaultSession.AesKey -NewHmacKey $script:VaultSession.HmacKey `
            -NewSalt $script:VaultSession.Salt -NewIterations $script:VaultSession.Iterations
    }
    catch {
        Write-AppLog -Level 'ERROR' -Message ('Passwortänderung: Recovery-Ordner konnte nicht verarbeitet werden: ' + $_.Exception.Message)
        $recovery = @{ Reencrypted = 0; Skipped = 0; Foreign = @(); Corrupt = @(); NotContainer = @(); CleanupFailed = @()
            Failed = @('Ordner Recovery: nicht verarbeitbar (' + (Get-RecoveryErrorText -Exception $_.Exception) + ')') }
    }
    Write-AppLog -Message ('Passwortänderung - Recovery: {0} neu verschlüsselt, {1} anderes Passwort, {2} beschädigt, {3} keine Tresordatei (jeweils bewusst unverändert), {4} fehlgeschlagen, {5} Prüfkopie(n) nicht entfernt.' -f
        $recovery.Reencrypted, @($recovery.Foreign).Count, @($recovery.Corrupt).Count, @($recovery.NotContainer).Count, @($recovery.Failed).Count, @($recovery.CleanupFailed).Count)
    foreach ($pair in @(@{ List = $recovery.Foreign; Label = 'anderes Passwort' }, @{ List = $recovery.Corrupt; Label = 'beschädigt' }, @{ List = $recovery.NotContainer; Label = 'keine Tresordatei' })) {
        if (@($pair.List).Count -gt 0) {
            Write-AppLog -Message ('Passwortänderung - Recovery bewusst unverändert ({0}): {1}' -f $pair.Label, (@($pair.List) -join ', '))
        }
    }
    if (@($recovery.Failed).Count -gt 0) {
        Write-AppLog -Level 'WARN' -Message ('Passwortänderung - Recovery NICHT umgestellt (ggf. weiterhin mit dem bisherigen Passwort lesbar): ' + (@($recovery.Failed) -join ' | '))
    }
    if (@($recovery.CleanupFailed).Count -gt 0) {
        Write-AppLog -Level 'WARN' -Message ('Passwortänderung - Recovery: Prüfkopien (neues Passwort) nicht entfernt: ' + (@($recovery.CleanupFailed) -join ', '))
    }
    $residue = Get-PasswordChangeDataResidue
    if ($residue.Count -gt 0) {
        Write-AppLog -Level 'WARN' -Message ('Passwortänderung - Data: nicht mit dem neuen Passwort verschlüsselt bzw. nicht prüfbar: ' + ($residue -join ', '))
    }
    try { Remove-Item -LiteralPath $script:Paths.VaultTxn -Force -ErrorAction SilentlyContinue } catch { }
    $report = Get-PasswordChangeReport -SaveOk $saveOk -Recovery $recovery -DataResidue $residue
    Write-AppLog -Message ('Passwortänderung abgeschlossen, Status: ' + $report.Status)
    return $report
}

function Invoke-PasswordChangeFlow {
    if (-not $script:VaultSession.Unlocked) { return }
    $win = New-XamlWindow -Xaml $script:ChangePasswordXaml
    Set-DialogOwner -Window $win
    $state = @{ Current = $null; NewPw = $null }
    $showError = {
        param([string]$Text)
        $err = $win.FindName('TxtError')
        $err.Text = $Text
        $err.Visibility = 'Visible'
    }
    $win.FindName('BtnOk').Add_Click({
            $current = $win.FindName('PwCurrent').SecurePassword
            if ($current.Length -eq 0) { & $showError 'Bitte das aktuelle Passwort eingeben.'; return }
            $newPw = $win.FindName('PwNew').SecurePassword
            $policyError = Test-PasswordPolicy -Secure $newPw
            if ($policyError -ne '') { & $showError $policyError; return }
            if (-not (Test-SecureStringsEqual -A $newPw -B $win.FindName('PwNew2').SecurePassword)) {
                & $showError 'Die beiden neuen Passwörter stimmen nicht überein.'
                return
            }
            $state.Current = $current.Copy()
            $state.NewPw = $newPw.Copy()
            $win.Close()
        })
    [void]$win.ShowDialog()
    try { $win.FindName('PwCurrent').Clear(); $win.FindName('PwNew').Clear(); $win.FindName('PwNew2').Clear() } catch { }
    if ($null -eq $state.Current) { return }

    $oldPwdBytes = $null
    $newPwdBytes = $null
    $newKeys = $null
    try {
        $oldPwdBytes = ConvertTo-PasswordBytes -Secure $state.Current
        # 1./2. Aktuelles Passwort durch HMAC-Pruefung/Entschluesselung der
        # Hauptdatei validieren
        try {
            $container = Read-VaultContainerFromFile -Path $script:Paths.VaultFile
            $checkKeys = Get-VaultKeysFromPassword -PasswordBytes $oldPwdBytes -Salt $container.Salt -Iterations $container.Iterations
            try { Unprotect-VaultContainer -Container $container -AesKey $checkKeys.Aes -HmacKey $checkKeys.Hmac | Out-Null }
            finally { Clear-VaultKeys -Keys $checkKeys }
        }
        catch {
            Show-Warning -Message $script:VaultNeutralError -Title 'Passwort ändern'
            return
        }
        # 3./4. Keine Umverschluesselung einer extern veraenderten Hauptdatei
        if (-not (Test-VaultMainFileUnchanged)) {
            Show-Warning -Message ('Die Tresordatei wurde seit dem Entsperren außerhalb dieser Anwendung verändert (z. B. durch eine Cloud-Synchronisierung) ' +
                'oder ihr Prüfwert ist nicht verfügbar. Das Passwort wurde NICHT geändert. Bitte die Anwendung neu starten und den Vorgang danach wiederholen.') -Title 'Passwort ändern'
            return
        }
        # 5. Neue Salt- und Schluesselwerte erzeugen
        $newPwdBytes = ConvertTo-PasswordBytes -Secure $state.NewPw
        $newSalt = [ArbeitszeitTool.VaultCrypto]::GetRandomBytes($script:VaultConst.SaltBytes)
        $newKeys = Get-VaultKeysFromPassword -PasswordBytes $newPwdBytes -Salt $newSalt -Iterations $script:VaultConst.Iterations
        # 6.-10. Alle Tresordateien transaktional neu verschluesseln
        $errorText = Invoke-VaultReencryption -OldPasswordBytes $oldPwdBytes `
            -NewAesKey $newKeys.Aes -NewHmacKey $newKeys.Hmac -NewSalt $newSalt -NewIterations $script:VaultConst.Iterations
        if ($errorText -ne '') {
            Clear-VaultKeys -Keys $newKeys
            Show-Warning -Message $errorText -Title 'Passwort ändern'
            return
        }
        # Sitzungsschluessel auf das neue Passwort umstellen
        Set-VaultSessionKeys -Keys $newKeys -Salt $newSalt -Iterations $script:VaultConst.Iterations
        $newKeys = $null   # Eigentum an die Sitzung uebergeben
        # Die Umverschluesselung hat die Hauptdatei ausserhalb von Save-Vault
        # neu geschrieben: Referenzhash nachziehen, damit der eigene Vorgang
        # nicht faelschlich als externe Aenderung erkannt wird.
        try { $script:App.VaultFileHash = Get-FileSha256Hex -Path $script:Paths.VaultFile } catch { }
        $script:App.VaultFileExistedAtLoad = $true
        Write-AppLog -Message 'Verschlüsselungspasswort geändert; alle Tresordateien wurden neu verschlüsselt.'
        # Abschliessendes Speichern, Recovery-Neuverschluesselung und
        # Ergebnisbewertung (Complete-PasswordChangeFollowUp). Die
        # Neuverschluesselung des Tresors selbst ist bereits transaktional
        # abgeschlossen und bleibt in jedem Fall gueltig.
        $report = Complete-PasswordChangeFollowUp -OldPasswordBytes $oldPwdBytes
        if ($report.Level -eq 'Info') { Show-Info -Message $report.Message -Title 'Passwort ändern' }
        else { Show-Warning -Message $report.Message -Title 'Passwort ändern' }
    }
    finally {
        if ($oldPwdBytes) { [ArbeitszeitTool.VaultCrypto]::ClearBytes($oldPwdBytes) }
        if ($newPwdBytes) { [ArbeitszeitTool.VaultCrypto]::ClearBytes($newPwdBytes) }
        if ($newKeys) { Clear-VaultKeys -Keys $newKeys }
        $state.Current.Dispose()
        $state.NewPw.Dispose()
    }
}

#endregion

#region ===== Anwendungszustand =====

# Zustand der Scroll-Lock-Aktivhaltung: nur noch die Protokolldrosselung.
# Es gibt KEINE Zustandsmaschine mehr - der Doppelpuls laeuft vollstaendig
# gekapselt im C#-Hintergrund; der Parallelschutz liegt ebenfalls im C#
# (Interlocked.CompareExchange in NativeInput).
function New-KeepAliveState {
    return @{
        ConsecutiveErrors = 0   # aufeinanderfolgende fehlgeschlagene Pulse (Drosselung)
    }
}

function Initialize-AppState {
    $script:App = @{
        Vault               = $null   # entschluesselter Tresorinhalt (nur im Arbeitsspeicher)
        Data                = $null   # Verweis auf Vault.WorkData
        Settings            = $null   # Verweis auf Vault.Settings
        CurrentDay          = $null
        ShuttingDown        = $false
        CloseConfirmed      = $false
        # Hash der zuletzt geladenen/geschriebenen verschluesselten Hauptdatei
        # und deren interne Revision (Erkennung externer Aenderungen).
        # Der Hash wird beim Entsperren IMMER erfasst, wenn eine Hauptdatei
        # existiert - auch beim Laden aus Pending/Backup und auch bei einer
        # beschaedigten Hauptdatei. Er ist nur $null, wenn beim Entsperren
        # keine Hauptdatei vorhanden war.
        VaultFileHash       = $null
        # Existierte die Hauptdatei beim Entsperren? (Erkennung extern neu
        # angelegter oder entfernter Dateien vor dem naechsten Speichern)
        VaultFileExistedAtLoad = $false
        VaultLoadedRevision = $null
        # Quelle des geladenen Standes ('Haupt'|'Pending'|'Backup1'|'Backup2'|'Neu')
        LoadedFrom          = ''
        # Unveraenderte Werte der VORHERIGEN Sitzung (siehe New-RecoveryState);
        # wird unmittelbar nach dem Entschluesseln und VOR dem ersten
        # Speichervorgang der neuen Sitzung befuellt.
        RecoveryState       = $null
        Ui                  = @{ Compact = $null; Extended = $null; ExtendedStamp = ''; ExtendedSegTable = $null; ExtendedPauseTable = $null; ExtendedRunningRow = -1; Tray = $null; TrayItems = @{}; MenuItems = @{}; Handle = [IntPtr]::Zero; HideInProgress = $false }
        Timers              = @{ Main = $null; KeepAlive = $null }
        KeepAlive           = (New-KeepAliveState)
        # Zentraler Zustand des Internetradios: Es ist zu jedem Zeitpunkt
        # hoechstens EIN MediaPlayer aktiv. Jede Oeffnungsanforderung erhaelt
        # einen eigenen Playerkontext (Instanz + RequestId + Sender + Stream),
        # dessen Ereignishandler beim Austausch explizit entfernt werden.
        Radio               = @{
            Player               = $null        # aktuelle MediaPlayer-Instanz (Verweis aus PlayerContext)
            PlayerContext        = $null        # @{ Player; RequestId; StationId; Url; Handlers; HandlersRemoved }
            DesiredState         = 'Stopped'    # 'Stopped'|'Paused'|'Playing'
            ActualState          = 'Gestoppt'   # Anzeige: Gestoppt|Verbinden|Wiedergabe|Puffern|Pausiert|Fehler
            SelectedStationId    = $null
            CurrentRequestId     = [long]0      # fortlaufend; entwertet veraltete Ereignisse alter Player
            OpenRequestId        = [long]0      # RequestId der letzten Open-Anforderung
            WasPlayingBeforeLock = $false
            SuspendedByLock      = $false
            LastError            = ''
            IsShuttingDown       = $false
            VolumeSavePending    = $false       # gedrosseltes Nachspeichern der Lautstaerke
            UiUpdating           = $false       # verhindert Ereignis-Rueckkopplungen der UI
            StationStamp         = ''           # Neuaufbau der Sender-ComboBox nur bei Aenderung
        }
        # Sichtschutz: Pausen-/Sperrzeit-Details sind beim Start IMMER verborgen;
        # der Zustand wird niemals sitzungsuebergreifend gespeichert.
        UiPrivacy           = @{ PauseAndLockDetailsVisible = $false }
        Counters            = @{ Tick = 0; LastSaveTick = 0 }
        # SaveBlockedReason/SaveBlockedLogged: kontrollierte Blockade weiterer
        # Speichervorgaenge (fehlender Referenzhash nach Commit bzw. kritischer
        # Schreibfehler der Hauptdatei). BackupWarningShown: einmalige neutrale
        # Benutzerinfo bei fehlgeschlagener Best-Effort-Backuprotation.
        # TestFail*: reine Testhooks fuer -RunTests (nur bei $script:TestMode
        # wirksam, im normalen Programmbetrieb vollstaendig inaktiv).
        Flags               = @{ Warn945Logged = $false; MaxHandled = $false; SaveInProgress = $false; UnsavedChanges = $false; SaveRetryCount = 0; ActiveDayDecisionCompleted = $false; SimulatedShutdownRequested = $false; SimulatedShutdownRequestCount = 0; SimulatedShutdownStartFails = $false; RolloverWarnLogged = $false; RolloverNextRetryAt = $null; SaveBlockedReason = ''; SaveBlockedLogged = $false; BackupWarningShown = $false; TestFailMainWrite = $false; TestFailMainRestore = $false; TestFailBackupCopy = $false; TestFailBackup1Write = $false; TestFailPostCommitHash = $false; TestFailJournalMirror = $false; TestFailRecoveryWrite = $false; TestFailReencryptRollback = $false; TestFailRecoveryList = $false; TestRecoveryDenyRead = ''; TestRecoveryBeforeCommit = $null; TestFailRecoveryCleanup = $false; TestFailConflictCopy = $false; LastConflictCopySaved = $null; TestBeforeMainWrite = $null }
    }
}

function Reset-DayFlags {
    $script:App.Flags.Warn945Logged = $false
    $script:App.Flags.MaxHandled = $false
}

#endregion

#region ===== Zentrale Aktualisierung und Haupt-Timer =====

function Invoke-MainRefresh {
    param([switch]$ForceTables)
    $day = $script:App.CurrentDay
    $comp = $null
    if ($day) { $comp = Get-DayComputation -Day $day -Now (Get-Date) }
    Update-CompactWindow -Comp $comp -Day $day
    Update-ExtendedWindow -Comp $comp -Day $day -Force:$ForceTables
    Update-TrayText -Comp $comp -Day $day
}

# Der regelmaessige Tracking-Checkpoint wird nur gebraucht, solange die
# Nettozeit von beobachteten Zeitraeumen abhaengt: laufender Homeoffice-
# Abschnitt (Sperren/Pausen werden dort abgezogen) oder offene manuelle Pause.
# Im Betrieb laeuft die Zeit anhand der Zeitstempel weiter und eine Windows-
# Sperre wird nur protokolliert - Beginn und Ende speichern ohnehin sofort.
# Ein Checkpoint waehrend einer Sperre im Betrieb wuerde nur alle 30 s die
# Tresordatei schreiben (Cloud-Versionen, die auf Sperrzeiten hindeuten).
# Reine, testbare Funktion.
function Test-TrackingCheckpointNeeded {
    param([Parameter(Mandatory)]$Comp)
    return ($Comp.RunningMode -eq 'Homeoffice' -or $null -ne $Comp.OpenPause)
}

function Invoke-MainTick {
    try {
        $script:App.Counters.Tick++
        Invoke-SessionEventDrain
        $day = $script:App.CurrentDay
        if ($day -and $day.Status -eq 'Aktiv') {
            if (Invoke-MidnightRolloverIfNeeded -Day $day) {
                Show-Info -Message ('Der Arbeitstag wurde um 00:00 Uhr automatisch beendet (Tageswechsel). ' +
                    'Das automatische Ende wird nicht kommentarlos übernommen: Vor dem Start eines neuen Arbeitstags muss es bestätigt oder korrigiert werden.')
            }
            else {
                $comp = Get-DayComputation -Day $day -Now (Get-Date)
                if ($comp.WarnActive -and -not $script:App.Flags.Warn945Logged) {
                    $script:App.Flags.Warn945Logged = $true
                    Write-AppLog -Level 'WARN' -Message 'Vorwarnung: 09:45 Netto-Arbeitszeit erreicht.'
                }
                if ((Invoke-AutoStopIfNeeded -Day $day) -and -not $script:App.Flags.MaxHandled) {
                    $script:App.Flags.MaxHandled = $true
                    if ($script:App.Settings['SoundEnabled']) {
                        try { [System.Media.SystemSounds]::Exclamation.Play() } catch { }
                    }
                }
            }
        }
        Invoke-MainRefresh
        # Regelmaessiger Checkpoint, damit der Tracking-Checkpoint
        # (WorkData.LastSavedAt) fuer die Homeoffice-Lueckenerkennung aktuell
        # bleibt. Bewusst begrenzt, um die Oberflaeche nicht zu blockieren:
        #  - nur ein Speichervorgang gleichzeitig (SaveInProgress-Sperre)
        #  - kein Checkpoint, wenn in den letzten 30 s bereits gespeichert wurde
        #  - nur wenn der Checkpoint fachlich gebraucht wird (siehe
        #    Test-TrackingCheckpointNeeded) - im Betrieb auch NICHT waehrend
        #    einer Windows-Sperre
        #  - ohne Backuprotation: Backups entstehen nur bei fachlichen
        #    Wechseln, nicht bei jedem Checkpoint (OneDrive-Datenmenge)
        if ($day -and $day.Status -eq 'Aktiv' -and ($script:App.Counters.Tick % 30) -eq 0 -and
            -not $script:App.Flags.SaveInProgress -and
            ($script:App.Counters.Tick - $script:App.Counters.LastSaveTick) -ge 30) {
            $comp = Get-DayComputation -Day $day -Now (Get-Date)
            if (Test-TrackingCheckpointNeeded -Comp $comp) {
                Update-DayTotals -Day $day | Out-Null
                Save-WorkData -Quiet -NoBackupRotation | Out-Null
                $script:App.Counters.LastSaveTick = $script:App.Counters.Tick
            }
        }
        # Begrenzte automatische Wiederholung nach einem fehlgeschlagenen
        # Speichervorgang (still; der Zustand ist sichtbar als NICHT GESPEICHERT)
        if ($script:App.Flags.UnsavedChanges -and -not $script:App.Flags.SaveInProgress -and
            $script:App.Flags.SaveRetryCount -lt 3 -and ($script:App.Counters.Tick % 60) -eq 30) {
            $script:App.Flags.SaveRetryCount++
            if (Save-Vault -Quiet) {
                Write-AppLog -Message 'Automatischer Wiederholungsversuch: Speichern nachgeholt.'
                $script:App.Counters.LastSaveTick = $script:App.Counters.Tick
            }
            elseif ($script:App.Flags.SaveRetryCount -ge 3) {
                Write-AppLog -Level 'ERROR' -Message 'Automatische Speicherwiederholung nach 3 Versuchen aufgegeben - manuelle Aktion erforderlich.'
            }
        }
        # Topmost ohne Aktivierung erneut durchsetzen
        if ([bool]$script:App.Settings['Topmost'] -and [bool]$script:App.Settings['TopmostReassert'] -and ($script:App.Counters.Tick % 15) -eq 0) {
            [ArbeitszeitTool.NativeWindow]::EnsureTopmostNoActivate($script:App.Ui.Handle)
        }
        # Gedrosseltes Nachspeichern einer per Slider/Mausrad geaenderten
        # Radiolautstaerke (kein Tresor-Schreiben pro Pixelbewegung)
        if ($script:App.Radio.VolumeSavePending -and -not $script:App.Flags.SaveInProgress -and ($script:App.Counters.Tick % 10) -eq 0) {
            $script:App.Radio.VolumeSavePending = $false
            Save-Vault -Quiet -NoBackupRotation | Out-Null
        }
    }
    catch {
        Write-AppLog -Level 'ERROR' -Message ("Fehler im Hauptzyklus: " + $_.Exception.Message)
    }
}

#endregion

#region ===== Windows-Sitzungsereignisse (Sperren / Entsperren) =====

# Der C#-SessionMonitor puffert die Ereignisse mit exakten Zeitstempeln;
# hier werden sie im UI-Thread verarbeitet. Im Betriebsmodus werden die
# Intervalle nur protokolliert - abgezogen wird ausschliesslich, was
# Homeoffice-Abschnitte ueberlappt (siehe Berechnungs-Engine).
function Invoke-SessionEventDrain {
    $events = [ArbeitszeitTool.SessionMonitor]::Drain()
    if ($events.Length -eq 0) { return }
    foreach ($ev in $events) {
        $time = [datetime]$ev[0]
        $kind = [string]$ev[1]
        # Sichtschutz und Internetradio reagieren UNABHAENGIG vom Arbeitstag
        # auf Sperren/Entsperren; Fehler dort duerfen die Lock-Erfassung der
        # Arbeitszeit niemals beeinflussen (daher separat abgesichert).
        if ($kind -eq 'Lock') {
            try { Hide-PauseLockDetails } catch { }
            try { Invoke-RadioLock } catch { }
        }
        else {
            try { Invoke-RadioUnlock } catch { }
        }
        $day = $script:App.CurrentDay
        if ($null -eq $day -or $day.Status -ne 'Aktiv') {
            Write-AppLog -Message "Sitzungsereignis '$kind' ohne aktiven Arbeitstag - ignoriert."
            continue
        }
        if ($kind -eq 'Lock') {
            Start-LockInterval -Day $day -Start $time | Out-Null
        }
        else {
            Stop-LockInterval -Day $day -End $time | Out-Null
        }
    }
    Invoke-MainRefresh -ForceTables
}

#endregion

#region ===== Scroll-Lock-Aktivhaltung =====

# Einfacher, entkoppelter Doppelpuls OHNE Zustandspruefung im Produktivbetrieb:
# Der periodische Timer stoesst lediglich einen vollstaendig in C# gekapselten
# Hintergrund-Doppelpuls an (Key Down/Up, ca. 200 ms Pause, Key Down/Up) -
# ausserhalb des WPF-Dispatcher-Threads (ThreadPool), Parallelschutz ueber
# Interlocked.CompareExchange. Die zwei Tastendruecke stellen im Normalfall
# den vorherigen Umschaltzustand wieder her; eine explizite
# Zustandsvalidierung (Vorher-/Nachher-Abfrage des Tastenzustands) findet im
# normalen Betrieb NICHT statt - sie ist ausschliesslich dem optionalen
# manuellen Diagnosetest (-RunScrollLockManualTest) vorbehalten.
# Fehler (SendInput, INPUT-Struktur) dienen nur der Diagnose: sie werden
# gedrosselt im verschluesselten Protokoll erfasst, beenden weder Anwendung
# noch Haupttimer, deaktivieren KeepAliveEnabled nicht, speichern keine
# Einstellungen, oeffnen keinen Dialog und beeinflussen die
# Arbeitszeiterfassung nicht.
# AKZEPTIERTE TECHNISCHE GRENZE (ehrlich dokumentiert): Bei hartem
# Prozessabbruch, Stromausfall oder Betriebssystemabsturz GENAU zwischen den
# beiden Tastendruecken - ebenso bei einem fehlgeschlagenen zweiten
# SendInput-Aufruf - kann Scroll Lock veraendert zurueckbleiben. Das
# beeintraechtigt die Arbeitszeiterfassung nicht.

$script:KeepAliveConst = @{
    PulseGapMs     = 200   # Abstand der beiden Tastendruecke (Standard 200 ms; das C# klemmt auf 100-300 ms)
    ShutdownWaitMs = 500   # maximale Wartezeit auf einen laufenden Puls beim Programmende
}

function Test-KeepAliveShouldRun {
    if (-not [bool]$script:App.Settings['KeepAliveEnabled']) { return $false }
    if ([ArbeitszeitTool.SessionMonitor]::IsLocked) { return $false }
    $day = $script:App.CurrentDay
    if ($null -eq $day -or $day.Status -ne 'Aktiv') { return $false }
    if ($day.MaxReached) { return $false }
    foreach ($seg in @($day.Segments)) {
        if ($seg.Running) { return $true }
    }
    return $false
}

# Holt die Diagnoseergebnisse abgeschlossener Doppelpulse aus dem C#-Puffer
# und protokolliert sie GEDROSSELT im verschluesselten Protokoll:
#  - der erste fehlgeschlagene Puls wird protokolliert
#  - danach nur jeder zehnte aufeinanderfolgende Fehler
#  - der erste danach wieder erfolgreiche Puls wird einmal protokolliert
# ($Entries ist fuer Tests injizierbar; sonst wird der C#-Puffer geleert.)
function Invoke-ScrollLockPulseLogDrain {
    param($Entries = $null)
    if ($null -eq $Entries) {
        try { $Entries = [ArbeitszeitTool.NativeInput]::DrainPulseResults() } catch { return }
    }
    $ka = $script:App.KeepAlive
    foreach ($entry in @($Entries)) {
        $text = [string]$entry
        if ($text.StartsWith('OK')) {
            if ($ka.ConsecutiveErrors -gt 0) {
                Write-AppLog -Message ('Scroll-Lock-Puls nach ' + $ka.ConsecutiveErrors + ' Fehler(n) wieder erfolgreich (' + $text + ').')
            }
            $ka.ConsecutiveErrors = 0
        }
        else {
            $ka.ConsecutiveErrors++
            if ($ka.ConsecutiveErrors -eq 1 -or ($ka.ConsecutiveErrors % 10) -eq 0) {
                Write-AppLog -Level 'WARN' -Message ('Scroll-Lock-Puls fehlgeschlagen (' + $ka.ConsecutiveErrors + '. Mal in Folge): ' + $text)
            }
        }
    }
}

# Wird vom periodischen Timer aufgerufen und stoesst NUR den C#-Doppelpuls
# an. Laeuft bereits ein Puls oder ist die INPUT-Groesse unerwartet, passiert
# nichts weiter - kein Fehlerdialog, keine Einstellungsaenderung, keine
# automatische Deaktivierung; der naechste regulaere Intervall versucht es
# erneut.
function Invoke-KeepAliveCycle {
    try {
        Invoke-ScrollLockPulseLogDrain
        if (-not (Test-KeepAliveShouldRun)) { return }
        [void][ArbeitszeitTool.NativeInput]::StartScrollLockPulse([int]$script:KeepAliveConst.PulseGapMs)
    }
    catch {
        # Nur protokollieren - weder Haupttimer noch Anwendung beenden
        Write-AppLog -Level 'ERROR' -Message ('Scroll-Lock-Puls konnte nicht gestartet werden: ' + $_.Exception.Message)
    }
}

# Beim regulaeren Programmende: keine neuen Pulse mehr (die Timer sind dann
# gestoppt), hoechstens KURZ auf einen laufenden Doppelpuls warten - das
# Beenden wird nicht dauerhaft blockiert. Es wird kein Tastenzustand
# abgefragt und keine Umschaltung anhand eines vermuteten Zustands
# durchgefuehrt.
function Wait-ScrollLockPulseCompletion {
    param([int]$MaxWaitMs = -1)
    if ($MaxWaitMs -lt 0) { $MaxWaitMs = [int]$script:KeepAliveConst.ShutdownWaitMs }
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while ([ArbeitszeitTool.NativeInput]::IsPulseRunning() -and $sw.ElapsedMilliseconds -lt $MaxWaitMs) {
            Start-Sleep -Milliseconds 25
        }
    }
    catch { }
}

#endregion

#region ===== Internetradio (optional, EIN zentraler MediaPlayer) =====

# Optionale Internetradio-Funktion mit genau EINER zentralen Instanz von
# System.Windows.Media.MediaPlayer (keine externen Player, Module oder
# Bibliotheken). Alle Ansichten (kompakt, erweitert, Tray, Einstellungen)
# verwenden denselben zentralen Playerzustand ($script:App.Radio).
# NETZWERK/DATENSCHUTZ: Nur der ausgewaehlte Radiostream wird vom
# Streamanbieter abgerufen - Arbeitszeitdaten, Einstellungen und Protokolle
# werden NIEMALS uebertragen. Der Streamanbieter sieht technisch uebliche
# Verbindungsdaten (IP-Adresse, Zeitpunkt, Playeranfrage). Ohne gestartetes
# Radio findet aufgrund dieser Funktion keine Streamverbindung statt.
# Radiofehler beeinflussen weder die Arbeitszeiterfassung noch Scroll Lock,
# Speichervorgaenge oder die Passwortaenderung; es gibt keine automatische
# Endlos-Wiederverbindung - ein manueller Play-Klick versucht es erneut.

$script:RadioConst = @{
    MaxStations   = 100
    MaxNameLength = 80
    MaxUrlLength  = 2048
}

# WPF-Path-Geometrien (bewusst keine schriftartabhaengigen Unicode-Symbole)
$script:RadioGlyphs = @{
    Play  = 'M 2,1 L 2,13 L 12,7 Z'
    Pause = 'M 2,1 L 5.5,1 L 5.5,13 L 2,13 Z M 8.5,1 L 12,1 L 12,13 L 8.5,13 Z'
}

# Initiale Senderliste: bewusst LEER - es werden keine Sender voreingestellt.
# Eigene Sender werden in den Einstellungen (Tab Internetradio) angelegt.
function Get-DefaultRadioStations {
    $list = New-Object System.Collections.ArrayList
    return ,$list
}

# Prueft EINEN Sender vollstaendig. Liefert '' oder eine Fehlermeldung.
# Zulaessig sind ausschliesslich absolute http-/https-Adressen ohne
# eingebettete Zugangsdaten (kein file/ftp/javascript/data, kein lokaler
# Pfad, kein UNC-Pfad). HTTP bleibt erlaubt, da die Standardstreams HTTP
# verwenden (Hinweis auf fehlende Transportverschluesselung in der GUI).
function Test-RadioStation {
    param($Station)
    if ($Station -isnot [System.Collections.IDictionary]) { return 'Ungültiger Sendereintrag.' }
    $id = [string]$Station['Id']
    $name = [string]$Station['Name']
    $url = [string]$Station['Url']
    if ([string]::IsNullOrWhiteSpace($id)) { return 'Die Sender-ID fehlt.' }
    if ([string]::IsNullOrWhiteSpace($name)) { return 'Der Sendername darf nicht leer sein.' }
    if ($name.Length -gt $script:RadioConst.MaxNameLength) {
        return ('Der Sendername darf höchstens {0} Zeichen lang sein.' -f $script:RadioConst.MaxNameLength)
    }
    if ([string]::IsNullOrWhiteSpace($url)) { return 'Die Stream-URL darf nicht leer sein.' }
    if ($url.Length -gt $script:RadioConst.MaxUrlLength) {
        return ('Die Stream-URL darf höchstens {0} Zeichen lang sein.' -f $script:RadioConst.MaxUrlLength)
    }
    $uri = $null
    if (-not [Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$uri)) {
        return 'Die Stream-URL ist keine gültige absolute Adresse.'
    }
    if (@('http', 'https') -notcontains $uri.Scheme.ToLowerInvariant()) {
        return 'Es sind ausschließlich http- und https-Adressen zulässig.'
    }
    if (-not [string]::IsNullOrEmpty($uri.UserInfo)) {
        return 'URLs mit eingebetteten Zugangsdaten (user:passwort@host) sind nicht zulässig.'
    }
    return ''
}

# Plausibilisiert eine geladene Senderliste: ungueltige Eintraege werden
# verworfen, doppelte IDs entfernt, die Anzahl wird begrenzt. Eine LEERE
# Liste ist ausdruecklich erlaubt.
function Get-ValidatedRadioStations {
    param($Loaded)
    $result = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($st in @($Loaded)) {
        if ($result.Count -ge $script:RadioConst.MaxStations) { break }
        if ((Test-RadioStation -Station $st) -ne '') { continue }
        $id = [string]$st['Id']
        if ($seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        [void]$result.Add([ordered]@{ Id = $id; Name = [string]$st['Name']; Url = [string]$st['Url'] })
    }
    return ,$result
}

function Get-RadioStationById {
    param($Id)
    foreach ($st in @($script:App.Settings['RadioStations'])) {
        if ([string]$st['Id'] -eq [string]$Id) { return $st }
    }
    return $null
}

# Erstellt fuer EINE Oeffnungsanforderung eine neue MediaPlayer-Instanz samt
# Playerkontext (Instanz + RequestId/Generation + Sender-ID + Streamadresse).
# Die Ereignishandler erfassen genau DIESEN Kontext (Closure); die
# Delegate-Referenzen werden zentral im Kontext gespeichert, damit sie beim
# Austausch der Instanz explizit wieder entfernt werden koennen.
function New-RadioPlayerContext {
    param(
        [Parameter(Mandatory)][long]$RequestId,
        [Parameter(Mandatory)][string]$StationId,
        [Parameter(Mandatory)][string]$Url
    )
    $player = New-Object System.Windows.Media.MediaPlayer
    $ctx = @{
        Player          = $player
        RequestId       = [long]$RequestId
        StationId       = $StationId
        Url             = $Url
        Handlers        = $null
        HandlersRemoved = $false
    }
    $onOpened = { param($s, $e) Invoke-RadioMediaOpened -Context $ctx }.GetNewClosure()
    $onFailed = { param($s, $e) Invoke-RadioMediaFailed -Context $ctx }.GetNewClosure()
    $onEnded = { param($s, $e) Invoke-RadioMediaEnded -Context $ctx }.GetNewClosure()
    $onBufStart = { param($s, $e) Invoke-RadioBufferingStarted -Context $ctx }.GetNewClosure()
    $onBufEnd = { param($s, $e) Invoke-RadioBufferingEnded -Context $ctx }.GetNewClosure()
    $handlers = @{
        Opened   = [System.EventHandler]$onOpened
        Failed   = [System.EventHandler[System.Windows.Media.ExceptionEventArgs]]$onFailed
        Ended    = [System.EventHandler]$onEnded
        BufStart = [System.EventHandler]$onBufStart
        BufEnd   = [System.EventHandler]$onBufEnd
    }
    $player.add_MediaOpened($handlers.Opened)
    $player.add_MediaFailed($handlers.Failed)
    $player.add_MediaEnded($handlers.Ended)
    $player.add_BufferingStarted($handlers.BufStart)
    $player.add_BufferingEnded($handlers.BufEnd)
    $ctx.Handlers = $handlers
    return $ctx
}

# Baut einen Playerkontext AUSNAHMESICHER ab: saemtliche registrierten
# Handler explizit entfernen, danach Stop() und Close(), zuletzt die globalen
# Referenzen freigeben - aber NUR, wenn sie noch auf genau diese Instanz
# zeigen. Fehler bei der Bereinigung beenden die Anwendung nicht.
function Clear-RadioPlayerContext {
    param($Context)
    if ($null -eq $Context) { return }
    $player = $Context.Player
    if ($player -and $Context.Handlers -and -not $Context.HandlersRemoved) {
        try { $player.remove_MediaOpened($Context.Handlers.Opened) } catch { }
        try { $player.remove_MediaFailed($Context.Handlers.Failed) } catch { }
        try { $player.remove_MediaEnded($Context.Handlers.Ended) } catch { }
        try { $player.remove_BufferingStarted($Context.Handlers.BufStart) } catch { }
        try { $player.remove_BufferingEnded($Context.Handlers.BufEnd) } catch { }
    }
    $Context.HandlersRemoved = $true
    try { if ($player) { $player.Stop() } } catch { }
    try { if ($player) { $player.Close() } } catch { }
    try {
        $radio = $script:App.Radio
        if ($radio) {
            if ($radio.PlayerContext -and [object]::ReferenceEquals($radio.PlayerContext, $Context)) {
                $radio.PlayerContext = $null
            }
            if ($radio.Player -and $player -and [object]::ReferenceEquals($radio.Player, $player)) {
                $radio.Player = $null
            }
        }
    }
    catch { }
    $Context.Player = $null
}

# MediaPlayer.Open arbeitet asynchron: NUR die aktuellste gueltige
# Open-Anforderung darf die Wiedergabe starten. Ein verspaetetes
# MediaOpened-Ereignis nach Pause/Stop/Senderwechsel/Lock/Programmende
# wird ueber die fortlaufende RequestId erkannt und ignoriert.
function Test-RadioOpenStillValid {
    param([Parameter(Mandatory)][long]$RequestId)
    $radio = $script:App.Radio
    if ($radio.IsShuttingDown) { return $false }
    if ($RequestId -ne [long]$radio.CurrentRequestId) { return $false }
    if ($radio.DesiredState -ne 'Playing') { return $false }
    return $true
}

# Vollstaendige Gueltigkeitspruefung eines Radioereignisses anhand des im
# Handler erfassten Playerkontexts. Nur wenn RequestId, Playerinstanz und
# Sender weiterhin dem aktuellen Zustand entsprechen und die Anwendung nicht
# beendet wird, darf das Ereignis den Radiozustand veraendern. Ereignisse
# eines alten Players werden vollstaendig ignoriert.
function Test-RadioEventStillValid {
    param($Context)
    try {
        if ($null -eq $script:App -or $null -eq $script:App.Radio) { return $false }
        $radio = $script:App.Radio
        if ($radio.IsShuttingDown) { return $false }
        if ($null -eq $Context -or $null -eq $Context.Player) { return $false }
        if ($null -eq $radio.PlayerContext) { return $false }
        if (-not [object]::ReferenceEquals($Context.Player, $radio.PlayerContext.Player)) { return $false }
        if ($null -eq $radio.Player -or -not [object]::ReferenceEquals($Context.Player, $radio.Player)) { return $false }
        if ([long]$Context.RequestId -ne [long]$radio.CurrentRequestId) { return $false }
        if ([string]$Context.StationId -ne [string]$radio.SelectedStationId) { return $false }
        return $true
    }
    catch { return $false }
}

function Invoke-RadioMediaOpened {
    param($Context = $null)
    try {
        if (-not (Test-RadioEventStillValid -Context $Context)) { return }
        if (-not (Test-RadioOpenStillValid -RequestId ([long]$Context.RequestId))) { return }
        $radio = $script:App.Radio
        $radio.Player.Volume = ([math]::Max(0, [math]::Min(100, [int]$script:App.Settings['RadioVolume']))) / 100.0
        $radio.Player.Play()
        $radio.ActualState = 'Wiedergabe'
        $radio.LastError = ''
        Update-RadioUi
    }
    catch {
        Write-AppLog -Level 'WARN' -Message ('Internetradio: Start der Wiedergabe fehlgeschlagen: ' + $_.Exception.Message)
    }
}

function Invoke-RadioMediaFailed {
    param($Context = $null)
    try {
        if (-not (Test-RadioEventStillValid -Context $Context)) { return }
        $radio = $script:App.Radio
        $radio.ActualState = 'Fehler'
        $radio.DesiredState = 'Stopped'
        $radio.SuspendedByLock = $false
        $radio.LastError = 'Der Stream konnte nicht wiedergegeben werden.'
        # BEWUSST ohne Stream-URL (koennte Tokens/Parameter enthalten):
        # nur Sendername, Sender-ID und neutrale Meldung protokollieren.
        $station = Get-RadioStationById -Id $radio.SelectedStationId
        $nameText = '-'
        if ($station) { $nameText = [string]$station['Name'] }
        Write-AppLog -Level 'WARN' -Message ("Internetradio: Wiedergabefehler bei Sender '{0}' (ID {1})." -f $nameText, [string]$radio.SelectedStationId)
        Clear-RadioPlayerContext -Context $Context
        Update-RadioUi
    }
    catch { }
}

function Invoke-RadioMediaEnded {
    param($Context = $null)
    try {
        if (-not (Test-RadioEventStillValid -Context $Context)) { return }
        $radio = $script:App.Radio
        $radio.ActualState = 'Gestoppt'
        $radio.DesiredState = 'Stopped'
        Write-AppLog -Message 'Internetradio: Der Stream wurde vom Anbieter beendet.'
        Clear-RadioPlayerContext -Context $Context
        Update-RadioUi
    }
    catch { }
}

function Invoke-RadioBufferingStarted {
    param($Context = $null)
    try {
        if (-not (Test-RadioEventStillValid -Context $Context)) { return }
        if ($script:App.Radio.DesiredState -eq 'Playing') {
            $script:App.Radio.ActualState = 'Puffern'
            Update-RadioUi
        }
    }
    catch { }
}

function Invoke-RadioBufferingEnded {
    param($Context = $null)
    try {
        if (-not (Test-RadioEventStillValid -Context $Context)) { return }
        if ($script:App.Radio.DesiredState -eq 'Playing') {
            $script:App.Radio.ActualState = 'Wiedergabe'
            Update-RadioUi
        }
    }
    catch { }
}

# Oeffnet einen Sender asynchron (Play erfolgt erst im gueltigen
# MediaOpened-Ereignis an der aktuellen Live-Position). Jede Anforderung
# erhaelt eine neue RequestId und einen eigenen Playerkontext; der bisherige
# Player wird vorher samt Handlern explizit abgebaut.
function Open-RadioStation {
    param([Parameter(Mandatory)]$Station)
    $radio = $script:App.Radio
    if ($radio.IsShuttingDown) { return $false }
    $err = Test-RadioStation -Station $Station
    if ($err -ne '') {
        $radio.LastError = $err
        $radio.ActualState = 'Fehler'
        Update-RadioUi
        return $false
    }
    # Veraltete Ereignisse entwerten und den alten Player sicher abbauen
    $radio.CurrentRequestId = [long]$radio.CurrentRequestId + 1
    $radio.OpenRequestId = [long]$radio.CurrentRequestId
    Clear-RadioPlayerContext -Context $radio.PlayerContext
    $ctx = $null
    try {
        $ctx = New-RadioPlayerContext -RequestId $radio.CurrentRequestId `
            -StationId ([string]$Station['Id']) -Url ([string]$Station['Url'])
        $ctx.Player.Volume = ([math]::Max(0, [math]::Min(100, [int]$script:App.Settings['RadioVolume']))) / 100.0
        $radio.PlayerContext = $ctx
        $radio.Player = $ctx.Player
        $radio.SelectedStationId = [string]$Station['Id']
        $radio.DesiredState = 'Playing'
        $radio.ActualState = 'Verbinden'
        $radio.LastError = ''
        $ctx.Player.Open([Uri][string]$Station['Url'])
        Update-RadioUi
        return $true
    }
    catch {
        if ($ctx) { Clear-RadioPlayerContext -Context $ctx }
        $radio.ActualState = 'Fehler'
        $radio.DesiredState = 'Stopped'
        $radio.LastError = 'Der Sender konnte nicht geöffnet werden.'
        Write-AppLog -Level 'WARN' -Message ("Internetradio: Öffnen fehlgeschlagen bei Sender '{0}' (ID {1})." -f [string]$Station['Name'], [string]$Station['Id'])
        Update-RadioUi
        return $false
    }
}

function Start-RadioPlayback {
    $radio = $script:App.Radio
    $station = Get-RadioStationById -Id $script:App.Settings['RadioSelectedStationId']
    if ($null -eq $station) {
        $radio.ActualState = 'Gestoppt'
        $radio.LastError = 'Kein gültiger Radiosender ausgewählt.'
        Update-RadioUi
        return $false
    }
    $radio.SuspendedByLock = $false
    return (Open-RadioStation -Station $station)
}

# "Pause" bei einem Livestream: Wiedergabe stoppt; bei erneutem Play wird
# der Stream neu geoeffnet und startet an der aktuellen Live-Position
# (kein veralteter Audiopuffer nach laengeren Pausen).
function Pause-RadioPlayback {
    $radio = $script:App.Radio
    $radio.DesiredState = 'Paused'
    $radio.CurrentRequestId = [long]$radio.CurrentRequestId + 1   # veraltete Ereignisse entwerten
    $radio.SuspendedByLock = $false
    Clear-RadioPlayerContext -Context $radio.PlayerContext
    $radio.ActualState = 'Pausiert'
    Update-RadioUi
}

function Stop-RadioPlayback {
    $radio = $script:App.Radio
    $radio.DesiredState = 'Stopped'
    $radio.CurrentRequestId = [long]$radio.CurrentRequestId + 1
    $radio.SuspendedByLock = $false
    $radio.WasPlayingBeforeLock = $false
    Clear-RadioPlayerContext -Context $radio.PlayerContext
    $radio.ActualState = 'Gestoppt'
    Update-RadioUi
}

# Play-/Pause-Umschalter (kompakte Ansicht, erweiterte Ansicht, Menues)
function Switch-RadioPlayback {
    try {
        if ($script:App.Radio.DesiredState -eq 'Playing') { Pause-RadioPlayback }
        else { [void](Start-RadioPlayback) }
    }
    catch { Write-AppLog -Level 'WARN' -Message ('Internetradio: Umschalten fehlgeschlagen: ' + $_.Exception.Message) }
}

# Lautstaerke 0..100 (Prozent) -> MediaPlayer.Volume 0.0..1.0. Mit -NoSave
# wird nur der Speicher-/Playerwert gesetzt und ein gedrosseltes
# Nachspeichern vorgemerkt (kein Tresor-Schreiben pro Slider-Pixel).
function Set-RadioVolume {
    param([Parameter(Mandatory)][int]$Percent, [switch]$NoSave)
    $Percent = [math]::Max(0, [math]::Min(100, $Percent))
    $script:App.Settings['RadioVolume'] = $Percent
    try { if ($script:App.Radio.Player) { $script:App.Radio.Player.Volume = $Percent / 100.0 } } catch { }
    if ($NoSave) { $script:App.Radio.VolumeSavePending = $true }
    else {
        $script:App.Radio.VolumeSavePending = $false
        Save-Settings -Quiet | Out-Null
    }
    Update-RadioUi
}

# Senderauswahl: waehrend aktiver Wiedergabe wird der alte Stream gestoppt
# und der neue geoeffnet; im pausierten/gestoppten Zustand aendert sich nur
# die Auswahl (kein automatischer Start).
function Select-RadioStation {
    param([Parameter(Mandatory)]$Id, [switch]$NoSave)
    $station = Get-RadioStationById -Id $Id
    if ($null -eq $station) { return }
    if ([string]$script:App.Settings['RadioSelectedStationId'] -eq [string]$Id -and $script:App.Radio.SelectedStationId -eq [string]$Id) {
        return
    }
    $script:App.Settings['RadioSelectedStationId'] = [string]$Id
    $script:App.Radio.SelectedStationId = [string]$Id
    if ($script:App.Radio.DesiredState -eq 'Playing') {
        [void](Open-RadioStation -Station $station)
    }
    if (-not $NoSave) { Save-Settings -Quiet | Out-Null }
    Update-RadioUi
}

# Reine, testbare Entscheidung nach dem Speichern der Einstellungen:
# Wie ist mit einem gerade LAUFENDEN Sender umzugehen?
#  - Radio war nicht aktiv: nichts automatisch starten ('Nichts')
#  - laufender Sender entfernt: gueltigen Ersatzsender oeffnen ('Ersatz')
#    oder sicher stoppen ('Stopp')
#  - anderer Sender als Standard/Auswahl gewaehlt: kontrolliert auf den
#    ausgewaehlten Sender wechseln ('Ersatz') - die Oberflaeche zeigt sonst
#    Sender B an, waehrend Sender A laeuft
#  - URL des laufenden Senders geaendert: kontrolliert neu oeffnen ('NeuOeffnen')
#  - unveraendert: Stream laeuft weiter ('Weiter')
function Get-RadioSettingsChangeAction {
    param(
        [bool]$WasPlaying,
        [string]$OpenStationId,
        [string]$OpenUrl
    )
    if (-not $WasPlaying) { return @{ Kind = 'Nichts'; Station = $null } }
    $selectedId = [string]$script:App.Settings['RadioSelectedStationId']
    $openStation = Get-RadioStationById -Id $OpenStationId
    if ($null -eq $openStation) {
        $replacement = Get-RadioStationById -Id $selectedId
        if ($null -ne $replacement) { return @{ Kind = 'Ersatz'; Station = $replacement } }
        return @{ Kind = 'Stopp'; Station = $null }
    }
    if ($selectedId -ne $OpenStationId) {
        $selected = Get-RadioStationById -Id $selectedId
        if ($null -ne $selected) { return @{ Kind = 'Ersatz'; Station = $selected } }
    }
    if ([string]$openStation['Url'] -ne [string]$OpenUrl) {
        return @{ Kind = 'NeuOeffnen'; Station = $openStation }
    }
    return @{ Kind = 'Weiter'; Station = $openStation }
}

# Bildschirmsperre: Radio anhalten und den Zustand fuer die automatische
# Fortsetzung merken. Fehler hier duerfen die Homeoffice-Lock-Erfassung
# nicht beeinflussen (Aufruf ist im Session-Drain abgesichert).
function Invoke-RadioLock {
    try {
        $radio = $script:App.Radio
        $wasActive = ($radio.DesiredState -eq 'Playing')
        $radio.WasPlayingBeforeLock = $wasActive
        if ($wasActive) {
            $radio.SuspendedByLock = $true
            $radio.DesiredState = 'Paused'
            $radio.CurrentRequestId = [long]$radio.CurrentRequestId + 1
            Clear-RadioPlayerContext -Context $radio.PlayerContext
            $radio.ActualState = 'Pausiert'
        }
        Update-RadioUi
    }
    catch { }
}

# Reine, testbare Entscheidung: Nur automatisch fortsetzen, wenn die
# Einstellung aktiv ist, das Radio unmittelbar vor dem Sperren lief, die
# Unterbrechung durch die Sperre erfolgte (kein manueller Stop) und die
# Anwendung nicht beendet wird.
function Test-RadioShouldResumeAfterUnlock {
    $radio = $script:App.Radio
    if (-not [bool]$script:App.Settings['RadioResumeAfterUnlock']) { return $false }
    if (-not $radio.WasPlayingBeforeLock) { return $false }
    if (-not $radio.SuspendedByLock) { return $false }
    if ($radio.IsShuttingDown) { return $false }
    return $true
}

function Invoke-RadioUnlock {
    try {
        if (Test-RadioShouldResumeAfterUnlock) {
            $script:App.Radio.SuspendedByLock = $false
            $script:App.Radio.WasPlayingBeforeLock = $false
            # Denselben Sender neu oeffnen; Play erfolgt im gueltigen
            # MediaOpened-Ereignis an der aktuellen Live-Position.
            [void](Start-RadioPlayback)
        }
        else {
            Update-RadioUi
        }
    }
    catch { }
}

# Bestimmt den tatsaechlichen Wiedergabestatus und schreibt ihn in die
# Einstellungen im Arbeitsspeicher. Wird VOR dem gepruefteten finalen
# Save-Vault aufgerufen (Invoke-CloseFlow bzw. Shutdown-Ablauf), damit ein
# ungeprueftes Cleanup-Speichern nicht die einzige Quelle dieses Werts ist.
function Set-RadioLastPlayingSetting {
    if ($null -eq $script:App -or $null -eq $script:App.Settings) { return $false }
    $remember = [bool]$script:App.Settings['RadioRememberPlaybackState']
    $value = ($remember -and $script:App.Radio.DesiredState -eq 'Playing')
    $script:App.Settings['RadioLastWasPlaying'] = $value
    return $value
}

# Regulaeres Programmende: 1. keine neuen Anforderungen, 2. RequestId
# erhoehen (alte Events ungueltig), 3. Wiedergabestatus uebernehmen,
# 4. Handler entfernen, Stop, Close und Referenzen freigeben. Eine Ausnahme
# hier darf den finalen Speichervorgang NICHT verhindern (Aufruf abgesichert).
function Clear-RadioPlayer {
    $radio = $script:App.Radio
    $radio.IsShuttingDown = $true
    $radio.CurrentRequestId = [long]$radio.CurrentRequestId + 1
    try { Set-RadioLastPlayingSetting | Out-Null } catch { }
    Clear-RadioPlayerContext -Context $radio.PlayerContext
    $radio.Player = $null
    $radio.DesiredState = 'Stopped'
    $radio.ActualState = 'Gestoppt'
}

# Synchronisiert ALLE Radio-Bedienelemente (kompakt, erweitert) mit dem
# zentralen Playerzustand. Saemtliche Zugriffe sind gegen fehlende Fenster
# und Elemente abgesichert; Fehler beeinflussen nichts anderes.
function Update-RadioUi {
    try {
        $radio = $script:App.Radio
        $stations = @($script:App.Settings['RadioStations'])
        $hasStations = ($stations.Count -gt 0)
        $isPlaying = ($radio.DesiredState -eq 'Playing')
        $glyph = $script:RadioGlyphs.Play
        if ($isPlaying) { $glyph = $script:RadioGlyphs.Pause }
        $playTip = 'Radio starten'
        if ($isPlaying) { $playTip = 'Radio pausieren' }
        else {
            $station = Get-RadioStationById -Id $script:App.Settings['RadioSelectedStationId']
            if ($station) { $playTip = ('Radio starten: ' + [string]$station['Name']) }
        }
        if (-not $hasStations) { $playTip = 'Keine Radiosender konfiguriert' }
        $volTip = ('Lautstärke: {0} %' -f [int]$script:App.Settings['RadioVolume'])

        $cw = $script:App.Ui.Compact
        if ($cw) {
            $btn = $cw.FindName('BtnRadioPlay')
            if ($btn) {
                $btn.IsEnabled = $hasStations
                $btn.ToolTip = $playTip
                $cw.FindName('PathRadioPlay').Data = [System.Windows.Media.Geometry]::Parse($glyph)
                $cw.FindName('BtnRadioVolume').ToolTip = $volTip
                $lbl = $cw.FindName('LblRadioVolume')
                if ($lbl) { $lbl.Text = ('{0} %' -f [int]$script:App.Settings['RadioVolume']) }
            }
        }
        $ew = $script:App.Ui.Extended
        if ($ew) {
            $radio.UiUpdating = $true
            try {
                $cmb = $ew.FindName('CmbRadioStation')
                if ($cmb) {
                    $stamp = (@($stations | ForEach-Object { [string]$_['Id'] + '~' + [string]$_['Name'] }) -join '|')
                    if ($stamp -ne [string]$radio.StationStamp) {
                        $radio.StationStamp = $stamp
                        $items = New-Object System.Collections.ArrayList
                        foreach ($st in $stations) {
                            [void]$items.Add([pscustomobject]@{ Id = [string]$st['Id']; Name = [string]$st['Name'] })
                        }
                        $cmb.ItemsSource = $items
                    }
                    $cmb.SelectedValue = [string]$script:App.Settings['RadioSelectedStationId']
                    $cmb.IsEnabled = $hasStations
                    # Sehr lange Sendernamen werden abgeschnitten dargestellt -
                    # der Tooltip zeigt den vollstaendigen Namen
                    $selStation = Get-RadioStationById -Id $script:App.Settings['RadioSelectedStationId']
                    if ($selStation) { $cmb.ToolTip = [string]$selStation['Name'] } else { $cmb.ToolTip = $null }
                    $btnE = $ew.FindName('BtnExtRadioPlay')
                    $btnE.IsEnabled = $hasStations
                    $btnE.ToolTip = $playTip
                    $ew.FindName('PathExtRadioPlay').Data = [System.Windows.Media.Geometry]::Parse($glyph)
                    $sld = $ew.FindName('SldExtRadioVolume')
                    if ([math]::Abs($sld.Value - [int]$script:App.Settings['RadioVolume']) -gt 0.5) {
                        $sld.Value = [int]$script:App.Settings['RadioVolume']
                    }
                    $statusText = [string]$radio.ActualState
                    if (-not $hasStations) { $statusText = 'Keine Sender konfiguriert' }
                    $ew.FindName('TxtRadioStatus').Text = $statusText
                }
            }
            finally { $radio.UiUpdating = $false }
        }
    }
    catch { }
}

# Radio-Menuepunkte (WPF-Kontextmenue und Tray) mit dem zentralen Zustand
# synchronisieren; das Sender-Untermenue wird bei jedem Oeffnen neu aufgebaut.
function Update-RadioMenuItems {
    try {
        $stations = @($script:App.Settings['RadioStations'])
        $isPlaying = ($script:App.Radio.DesiredState -eq 'Playing')
        $playHeader = 'Radio starten'
        if ($isPlaying) { $playHeader = 'Radio pausieren' }
        $selId = [string]$script:App.Settings['RadioSelectedStationId']

        $items = $script:App.Ui.MenuItems
        if ($items.Contains('RadioPlay')) {
            $items['RadioPlay'].Header = $playHeader
            $items['RadioPlay'].IsEnabled = ($stations.Count -gt 0)
        }
        if ($items.Contains('RadioStations')) {
            $sub = $items['RadioStations']
            $sub.Items.Clear()
            foreach ($st in $stations) {
                $mi = New-Object System.Windows.Controls.MenuItem
                $mi.Header = [string]$st['Name']
                $mi.IsCheckable = $true
                $mi.IsChecked = ([string]$st['Id'] -eq $selId)
                $id = [string]$st['Id']
                $mi.Add_Click({ Select-RadioStation -Id $id }.GetNewClosure())
                [void]$sub.Items.Add($mi)
            }
            $sub.IsEnabled = ($stations.Count -gt 0)
        }
        $trayItems = $script:App.Ui.TrayItems
        if ($trayItems.Contains('RadioPlay')) {
            $trayItems['RadioPlay'].Text = $playHeader
            $trayItems['RadioPlay'].Enabled = ($stations.Count -gt 0)
        }
        if ($trayItems.Contains('RadioStations')) {
            $tsub = $trayItems['RadioStations']
            $tsub.DropDownItems.Clear()
            foreach ($st in $stations) {
                $ti = New-Object System.Windows.Forms.ToolStripMenuItem
                $ti.Text = [string]$st['Name']
                $ti.Checked = ([string]$st['Id'] -eq $selId)
                $id = [string]$st['Id']
                $ti.Add_Click({ Invoke-OnUiDispatcher -Action { Select-RadioStation -Id $id } }.GetNewClosure())
                [void]$tsub.DropDownItems.Add($ti)
            }
            $tsub.Enabled = ($stations.Count -gt 0)
        }
    }
    catch { }
}

#endregion

#region ===== Sichtschutz: Pausen- und Sperrzeiten in der erweiterten Ansicht =====

# Persoenliche Detailwerte zu Pausen und Bildschirmsperren werden in der
# erweiterten Ansicht standardmaessig VERBORGEN (BlurEffect auf der Tabelle,
# neutrale Platzhalter in den Tageswerten). Es handelt sich ausschliesslich
# um einen VISUELLEN Sichtschutz: die Daten bleiben unveraendert im
# Arbeitsspeicher und im verschluesselten Tresor erhalten und werden
# weiterhin korrekt fuer die Arbeitszeitberechnung verwendet. Der Zustand
# "gerade sichtbar" wird NIEMALS sitzungsuebergreifend gespeichert.

# Zentraler Sichtbarkeitszustand - keine eigene Umschaltlogik je Textfeld
function Set-PauseLockDetailsVisibility {
    param([Parameter(Mandatory)][bool]$Visible)
    $script:App.UiPrivacy.PauseAndLockDetailsVisible = $Visible
    Update-PauseLockPrivacyUi
    # Maskierte Textwerte der Tageswerte sofort aktualisieren (nur Anzeige;
    # Tabellen/Intervalle werden dabei NICHT neu aufgebaut - der Stamp der
    # erweiterten Ansicht bleibt unveraendert)
    try {
        if ($script:App.Ui.Extended -and $script:App.Ui.Extended.IsVisible) { Invoke-MainRefresh }
    }
    catch { }
}

function Switch-PauseLockDetailsVisibility {
    Set-PauseLockDetailsVisibility (-not [bool]$script:App.UiPrivacy.PauseAndLockDetailsVisible)
}

function Hide-PauseLockDetails {
    if ([bool]$script:App.UiPrivacy.PauseAndLockDetailsVisible) {
        Set-PauseLockDetailsVisibility $false
    }
    else {
        Update-PauseLockPrivacyUi
    }
}

# Wendet den zentralen Sichtbarkeitszustand auf ALLE betroffenen Elemente an:
#  - Datenquelle: verborgen = maskierte Kopie (Get-MaskedPausesTable), damit
#    keine echten Werte im Automation-Baum stehen; sichtbar = echte Tabelle
#  - BlurEffect auf der Pausen-/Sperrzeiten-Tabelle (nur dieser Container,
#    nicht das gesamte Fenster; Beschriftungen bleiben scharf)
#  - IsHitTestVisible=false verhindert Auswahl-, Fokus- und Tooltip-
#    Offenlegung der verborgenen Zeilen
#  - neutrale AutomationProperties (keine konkreten Zeiten fuer Screenreader)
#  - Auge-Symbol (geoeffnet/durchgestrichen) und Tooltip
# Das Ein-/Ausblenden veraendert weder Fenstergroesse noch Tabellenlayout
# und loest keinen Tresorspeichervorgang aus.
function Update-PauseLockPrivacyUi {
    $win = $script:App.Ui.Extended
    if ($null -eq $win) { return }
    try {
        $visible = [bool]$script:App.UiPrivacy.PauseAndLockDetailsVisible
        # Datenquelle zuerst: verborgen = nur maskierte Kopie gebunden
        Set-ExtendedPausesSource
        $grid = $win.FindName('ExtPauses')
        if ($grid) {
            if ($visible) {
                $grid.Effect = $null
                $grid.IsHitTestVisible = $true
                [System.Windows.Automation.AutomationProperties]::SetName($grid, 'Pausen und Sperrzeiten')
            }
            else {
                $blur = New-Object System.Windows.Media.Effects.BlurEffect
                $blur.Radius = 9
                $grid.Effect = $blur
                $grid.IsHitTestVisible = $false
                [System.Windows.Automation.AutomationProperties]::SetName($grid, 'Pausen- und Sperrzeiten verborgen')
            }
        }
        $strike = $win.FindName('PathEyeStrike')
        $eyeBtn = $win.FindName('BtnPrivacyEye')
        if ($strike -and $eyeBtn) {
            if ($visible) {
                $strike.Visibility = 'Collapsed'
                $eyeBtn.ToolTip = 'Pausen- und Sperrzeiten verbergen'
            }
            else {
                $strike.Visibility = 'Visible'
                $eyeBtn.ToolTip = 'Pausen- und Sperrzeiten anzeigen'
            }
        }
    }
    catch { }
}

#endregion

#region ===== Aktionen (Menue / Schaltflaechen) =====

function Invoke-StartDayFlow {
    $current = Get-ActiveDay
    if ($current) {
        Show-Info -Message 'Es läuft bereits ein aktiver Arbeitstag.'
        return
    }
    # Ein automatisch beendeter Vortag muss VOR dem Start eines neuen
    # Arbeitstags ausdruecklich geklaert werden; Abbruch startet keinen Tag.
    $reviewDay = Get-AutoEndReviewCandidate
    if ($null -ne $reviewDay) {
        if (-not (Invoke-AutoEndReviewFlow -Day $reviewDay)) { return }
        Invoke-MainRefresh -ForceTables
    }
    $existing = Get-DayByDate -DateText (Get-TodayText)
    if ($existing -and $existing.MaxReached) {
        Show-Warning -Message 'Für heute wurde die maximale Arbeitszeit von 10:00 Stunden bereits erreicht. Es kann kein weiterer Abschnitt gestartet werden.'
        return
    }
    $result = Show-StartDayDialog
    if ($null -eq $result) { return }
    if ($existing) {
        if (-not (Confirm-Question -Message 'Für heute existiert bereits ein beendeter Arbeitstag. Soll er wieder geöffnet und ein neuer Abschnitt angefügt werden?')) { return }
        if (Test-SegmentOverlap -Day $existing -Start $result.Start -End $null) {
            Show-Warning -Message 'Die Startzeit überschneidet sich mit einem vorhandenen Arbeitsabschnitt dieses Tages.'
            return
        }
        $reopenSnapshot = Get-DaySnapshot -Day $existing
        $previousCurrent = $script:App.CurrentDay
        $existing['Status'] = 'Aktiv'
        $existing['EndedAt'] = $null
        $existing['EndReason'] = $null
        $existing['AutoEnded'] = $false
        $existing['AutoEndReviewPending'] = $false
        $seg = New-SegmentObject -Mode $result.Mode -Start $result.Start -Running $true
        [void]$existing['Segments'].Add($seg)
        $reopenText = ('{0} ab {1}' -f $result.Mode, (Format-Clock $result.Start))
        Add-Correction -Day $existing -Description 'Arbeitstag wieder geöffnet' -NewValue $reopenText -NoLog
        $script:App.CurrentDay = $existing
        Update-DayTotals -Day $existing | Out-Null
        if (-not (Save-WorkData)) {
            Restore-DayFromSnapshot -Day $existing -Snapshot $reopenSnapshot
            $script:App.CurrentDay = $previousCurrent
            Write-AppLog -Level 'WARN' -Message 'Wiedereröffnung des Arbeitstags NICHT gespeichert - Änderung zurückgenommen.'
            Invoke-MainRefresh -ForceTables
            return
        }
        Write-CorrectionLog -Day $existing -Description 'Arbeitstag wieder geöffnet' -NewValue $reopenText
    }
    else {
        Start-WorkDay -Mode $result.Mode -StartTime $result.Start | Out-Null
    }
    Reset-DayFlags
    Invoke-MainRefresh -ForceTables
}

function Invoke-ModeSwitchFlow {
    $day = $script:App.CurrentDay
    if ($null -eq $day -or $day.Status -ne 'Aktiv') {
        Show-Info -Message 'Es läuft kein aktiver Arbeitstag.'
        return
    }
    $comp = Get-DayComputation -Day $day -Now (Get-Date)
    if ($null -eq $comp.RunningMode) {
        Show-Info -Message 'Es läuft aktuell kein Arbeitsabschnitt.'
        return
    }
    $result = Show-ModeSwitchDialog -Day $day -CurrentMode $comp.RunningMode
    if ($null -eq $result) { return }
    Switch-WorkMode -Day $day -NewMode $result.NewMode -EndTime $result.End -StartTime $result.Start | Out-Null
    Invoke-MainRefresh -ForceTables
}

function Invoke-TogglePauseFlow {
    $day = $script:App.CurrentDay
    if ($null -eq $day -or $day.Status -ne 'Aktiv') {
        Show-Info -Message 'Es läuft kein aktiver Arbeitstag.'
        return
    }
    $comp = Get-DayComputation -Day $day -Now (Get-Date)
    if ($comp.OpenPause) {
        Stop-ManualPauseInterval -Day $day | Out-Null
    }
    elseif ($comp.RunningMode -eq 'Homeoffice') {
        Start-ManualPauseInterval -Day $day | Out-Null
    }
    else {
        Show-Info -Message 'Der manuelle Pausenknopf ist nur im Homeoffice-Modus vorgesehen. Im Betrieb läuft die Zeit nach den Betriebsregeln weiter.'
        return
    }
    Invoke-MainRefresh -ForceTables
}

function Invoke-EndDayFlow {
    $day = $script:App.CurrentDay
    if ($null -eq $day -or $day.Status -ne 'Aktiv') {
        Show-Info -Message 'Es läuft kein aktiver Arbeitstag.'
        return
    }
    $result = Show-EndDayDialog -Day $day
    if ($null -eq $result) { return }
    $completed = Complete-WorkDay -Day $day -End $result.End -Reason 'Manuell' -TrimTrailingIntervals
    # Nach dem Tagesabschluss werden die Pausen-/Sperrzeit-Details wieder verborgen
    Hide-PauseLockDetails
    Invoke-MainRefresh -ForceTables
    # Nur die ausdruecklich gewaehlte Schaltflaeche loest den Shutdown aus -
    # und NUR nach vollstaendig erfolgreichem, verifiziertem Tagesabschluss.
    if ($result.Shutdown -and $completed) {
        Invoke-EndDayShutdown | Out-Null
    }
}

function Invoke-AddSegmentFlow {
    $day = $script:App.CurrentDay
    if ($null -eq $day) {
        Show-Info -Message 'Es ist kein Arbeitstag vorhanden. Bitte zuerst einen Arbeitstag starten.'
        return
    }
    $baseDate = [datetime]::ParseExact($day.Date, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    $result = Show-IntervalEditDialog -Caption 'Arbeitsabschnitt manuell erfassen (z. B. Homeoffice 08:00 bis 09:30)' `
        -BaseDate $baseDate -ShowMode -Mode 'Homeoffice' -StartText '08:00' -EndText '09:30' -CommentLabel 'Kommentar zum Abschnitt (optional):'
    if ($null -eq $result) { return }
    if (Test-SegmentOverlap -Day $day -Start $result.Start -End $result.End) {
        Show-Warning -Message 'Der Abschnitt überschneidet sich mit einem vorhandenen Arbeitsabschnitt.'
        return
    }
    $snapshot = Get-DaySnapshot -Day $day
    $seg = New-SegmentObject -Mode $result.Mode -Start $result.Start -End $result.End -Manual $true
    [void](Set-ItemComment -Item $seg -Text $result.Comment)
    [void]$day['Segments'].Add($seg)
    # 10-Stunden-Grenze: Aenderungen ueber 10:00 Netto werden abgelehnt
    if (-not (Test-DayUnderMax -Day $day)) {
        Restore-DayFromSnapshot -Day $day -Snapshot $snapshot
        Show-Warning -Message 'Änderung abgelehnt: Die Netto-Arbeitszeit würde dadurch 10:00 Stunden überschreiten.'
        return
    }
    Update-MaxReachedState -Day $day
    $newSegText = ('{0} {1}-{2}' -f $result.Mode, (Format-Clock $result.Start), (Format-Clock $result.End))
    Add-Correction -Day $day -Description 'Arbeitsabschnitt manuell erfasst' -NewValue $newSegText -NoLog
    Update-DayTotals -Day $day | Out-Null
    if (Save-WorkData) {
        Write-CorrectionLog -Day $day -Description 'Arbeitsabschnitt manuell erfasst' -NewValue $newSegText
    }
    else {
        Restore-DayFromSnapshot -Day $day -Snapshot $snapshot
        Write-AppLog -Level 'WARN' -Message 'Manuell erfasster Abschnitt NICHT gespeichert - Änderung zurückgenommen.'
    }
    Invoke-MainRefresh -ForceTables
}

# Kommentar zum aktuellen Arbeitstag (Kontextmenue, Tray, erweiterte
# Ansicht): wahlweise zum Tag, zum laufenden Abschnitt oder zur laufenden
# Pause. Fruehere Abschnitte, Sperrintervalle und Korrekturen werden im
# Tages-Editor kommentiert.
function Invoke-CommentFlow {
    $day = $script:App.CurrentDay
    if ($null -eq $day) {
        Show-Info -Message 'Es ist kein Arbeitstag vorhanden. Bitte zuerst einen Arbeitstag starten.'
        return
    }
    $info = Get-CurrentDayCommentTargets -Day $day
    $res = Show-CommentDialog -Caption 'Kommentar zum aktuellen Arbeitstag' -Targets $info.Targets -DefaultKey $info.DefaultKey
    if ($null -eq $res -or @($res).Count -eq 0) { return }
    [void](Save-DayCommentResults -Day $day -Results $res -Items $info.Items)
    Invoke-MainRefresh -ForceTables
}

function Invoke-ToggleKeepAlive {
    # Deaktivieren startet keine neuen Pulse mehr (Test-KeepAliveShouldRun);
    # ein bereits begonnener Doppelpuls beendet sich regulaer im Hintergrund.
    # Es wird KEIN Tastenzustand abgefragt und keine zusaetzliche Umschaltung
    # anhand eines vermuteten Zustands durchgefuehrt.
    $oldValue = [bool]$script:App.Settings['KeepAliveEnabled']
    $script:App.Settings['KeepAliveEnabled'] = -not $oldValue
    if (-not (Save-Settings)) {
        # Benutzeraktion: bei fehlgeschlagenem Speichern zuruecknehmen
        $script:App.Settings['KeepAliveEnabled'] = $oldValue
        Invoke-MainRefresh
        return
    }
    $state = 'deaktiviert'
    if ($script:App.Settings['KeepAliveEnabled']) { $state = 'aktiviert' }
    Write-AppLog -Message "Scroll-Lock-Aktivhaltung $state."
    Invoke-MainRefresh
}

# Zentraler Close-Flow (Fensterschaltflaeche, Kontextmenue, Tray, Alt+F4).
# Liefert genau eines der Ergebnisse:
#   'Abbrechen'         - Fenster bleibt geoeffnet, CloseConfirmed bleibt false
#   'NormalSchliessen'  - der Closing-Handler darf regulaer schliessen
#   'ShutdownGestartet' - der gemeinsame Shutdownpfad hat CloseConfirmed und
#                         das kontrollierte Schliessen bereits uebernommen;
#                         der Closing-Handler darf KEINEN zweiten
#                         Schliessvorgang ausloesen
function Invoke-CloseFlow {
    $day = $script:App.CurrentDay
    $activeDay = $null
    if ($day -and $day.Status -eq 'Aktiv') { $activeDay = $day }
    $choice = Show-CloseAppDialog -Day $activeDay
    return Invoke-CloseChoice -Choice $choice -ActiveDay $activeDay
}

# Fuehrt die im Schliessen-Dialog getroffene Auswahl aus (ohne UI testbar).
# "Nur Anwendung schliessen": Der Tag bleibt Aktiv, der laufende Abschnitt
# bleibt UNVERAENDERT (gleiche Segment-ID, Start unveraendert, End=null,
# Running=true, keine neue Segmentanzahl) - im Betrieb zaehlt die Zeit des
# geplanten Neustarts normal als Arbeitszeit weiter. Vor dem Schliessen wird
# CleanShutdown=true gesetzt und der finale Stand MIT Ergebnispruefung
# gespeichert; schlaegt das fehl, kann der Benutzer wiederholen oder das
# Schliessen abbrechen (keine stille Erfolgsannahme).
function Invoke-CloseChoice {
    param([string]$Choice, $ActiveDay)
    if ($Choice -eq 'Abbrechen') { return 'Abbrechen' }
    if ($Choice -eq 'HerunterfahrenUndSchliessen') {
        # Sicherheitsnetz: Ohne aktivierte Opt-in-Einstellung gibt es keinen
        # Shutdownpfad (der Dialog bietet die Auswahl dann gar nicht an).
        if ($null -eq $script:App.Settings -or -not [bool]$script:App.Settings['ShutdownOfferEnabled']) { return 'Abbrechen' }
        if (Invoke-CloseDialogShutdown -ActiveDay $ActiveDay) { return 'ShutdownGestartet' }
        return 'Abbrechen'
    }
    if ($Choice -eq 'BeendenUndSchliessen' -and $ActiveDay) {
        if (-not (Complete-WorkDay -Day $ActiveDay -End (Get-Date) -Reason 'Manuell')) { return 'Abbrechen' }
    }
    if ($null -eq $script:App.Vault -or -not $script:VaultSession.Unlocked) { return 'NormalSchliessen' }
    # Tatsaechlichen Radio-Wiedergabestatus VOR dem gepruefteten finalen
    # Speichervorgang bestimmen (der spaetere Cleanup-Save ist nicht die
    # einzige Speicherung dieses Werts).
    try { Set-RadioLastPlayingSetting | Out-Null } catch { }
    # Finaler Speichervorgang VOR dem Schliessen (CleanShutdown=true)
    while ($true) {
        $script:App.Vault['CleanShutdown'] = $true
        if (Save-Vault) { break }
        $script:App.Vault['CleanShutdown'] = $false
        $retry = Confirm-Question -Message ('Der finale Speichervorgang des Datentresors ist fehlgeschlagen. ' +
            "Die Daten wurden NICHT gespeichert.`r`n`r`nErneut versuchen? (Nein = Schließen abbrechen, die Anwendung bleibt geöffnet)") `
            -Title 'Speichern fehlgeschlagen'
        if (-not $retry) { return 'Abbrechen' }
    }
    return 'NormalSchliessen'
}

# Shutdown-Auswahl aus dem Schliessen-Dialog: Ein aktiver Arbeitstag wird
# ZUERST vollstaendig validiert und beendet (Complete-WorkDay mit der
# aktuellen Zeit als beabsichtigtem Arbeitsende, KEINE -SkipValidation);
# NUR nach erfolgreichem, gespeichertem Tagesabschluss folgt der gemeinsame
# sichere Shutdownablauf. Es gibt keinen Pfad, der den PC mit offenem bzw.
# aktivem Arbeitstag herunterfaehrt. Liefert $true, wenn die
# Shutdown-Anforderung erfolgreich gestartet wurde.
function Invoke-CloseDialogShutdown {
    param($ActiveDay)
    if ($ActiveDay) {
        if (-not (Complete-WorkDay -Day $ActiveDay -End (Get-Date) -Reason 'Manuell')) {
            # Complete-WorkDay hat den konkreten Grund bereits gemeldet;
            # hier nur die neutrale Folge: kein Shutdown, kein Schliessen.
            Show-Warning -Message ('Der PC wird NICHT heruntergefahren, weil der Arbeitstag nicht beendet werden konnte. ' +
                'Die Anwendung bleibt geöffnet.')
            return $false
        }
        # UI-Zustand bestmoeglich aktualisieren (die Anwendung bleibt bei
        # einem spaeteren Fehler des Shutdownablaufs geoeffnet und bedienbar)
        try { Hide-PauseLockDetails } catch { }
        try { Invoke-MainRefresh -ForceTables } catch { }
        return Invoke-SafeApplicationShutdown
    }
    return Invoke-SafeApplicationShutdown `
        -DayStateShort 'Es wurden keine Arbeitszeitdaten verändert' `
        -DayStateSaved 'Es wurden keine Arbeitszeitdaten verändert' `
        -SuccessLogText 'Windows-Herunterfahren angefordert, die Anwendung wird geschlossen.'
}

#endregion

#region ===== Kontextmenue (kompaktes Fenster) und Tray =====

function Add-WpfMenuItem {
    param($Menu, [string]$Key, [string]$Header, [scriptblock]$OnClick)
    $item = New-Object System.Windows.Controls.MenuItem
    $item.Header = $Header
    $item.Add_Click($OnClick)
    [void]$Menu.Items.Add($item)
    $script:App.Ui.MenuItems[$Key] = $item
    return $item
}

function New-CompactContextMenu {
    $menu = New-Object System.Windows.Controls.ContextMenu
    Add-WpfMenuItem -Menu $menu -Key 'Extended' -Header 'Erweiterte Ansicht öffnen' -OnClick { Show-ExtendedWindow } | Out-Null
    Add-WpfMenuItem -Menu $menu -Key 'StartDay' -Header 'Arbeitstag starten...' -OnClick { Invoke-StartDayFlow } | Out-Null
    Add-WpfMenuItem -Menu $menu -Key 'SwitchMode' -Header 'Modus wechseln...' -OnClick { Invoke-ModeSwitchFlow } | Out-Null
    Add-WpfMenuItem -Menu $menu -Key 'Pause' -Header 'Pause starten' -OnClick { Invoke-TogglePauseFlow } | Out-Null
    Add-WpfMenuItem -Menu $menu -Key 'Comment' -Header 'Kommentar...' -OnClick { Invoke-CommentFlow } | Out-Null
    $keepAliveItem = Add-WpfMenuItem -Menu $menu -Key 'KeepAlive' -Header 'Scroll-Lock-Aktivhaltung' -OnClick { Invoke-ToggleKeepAlive }
    $keepAliveItem.IsCheckable = $true
    # Ansichts-Presets der kompakten Ansicht (fest eingebaute inkl. 'Minimum'
    # und eigene Presets; das Untermenue wird bei jedem Oeffnen neu aufgebaut)
    $presetSub = New-Object System.Windows.Controls.MenuItem
    $presetSub.Header = 'Ansichts-Preset'
    $script:App.Ui.MenuItems['CompactPresets'] = $presetSub
    [void]$menu.Items.Add($presetSub)
    [void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
    Add-WpfMenuItem -Menu $menu -Key 'RadioPlay' -Header 'Radio starten' -OnClick { Switch-RadioPlayback } | Out-Null
    $radioSub = New-Object System.Windows.Controls.MenuItem
    $radioSub.Header = 'Radiosender'
    $script:App.Ui.MenuItems['RadioStations'] = $radioSub
    [void]$menu.Items.Add($radioSub)
    [void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
    Add-WpfMenuItem -Menu $menu -Key 'Hide' -Header 'In den Infobereich ausblenden' -OnClick { Hide-CompactWindow } | Out-Null
    Add-WpfMenuItem -Menu $menu -Key 'Minimize' -Header 'Minimieren' -OnClick {
        $win = $script:App.Ui.Compact
        if ($win) {
            $win.ShowInTaskbar = $true
            $win.WindowState = [System.Windows.WindowState]::Minimized
        }
    } | Out-Null
    [void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
    Add-WpfMenuItem -Menu $menu -Key 'EndDay' -Header 'Arbeitstag beenden...' -OnClick { Invoke-EndDayFlow } | Out-Null
    Add-WpfMenuItem -Menu $menu -Key 'History' -Header 'Verlauf...' -OnClick { Show-HistoryWindow } | Out-Null
    Add-WpfMenuItem -Menu $menu -Key 'Export' -Header 'Export...' -OnClick { Show-ExportDialog } | Out-Null
    Add-WpfMenuItem -Menu $menu -Key 'Settings' -Header 'Einstellungen...' -OnClick { Show-SettingsDialog | Out-Null } | Out-Null
    [void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
    Add-WpfMenuItem -Menu $menu -Key 'Close' -Header 'Anwendung schließen' -OnClick { $script:App.Ui.Compact.Close() } | Out-Null
    $menu.Add_Opened({ Update-MenuState })
    return $menu
}

function Update-MenuState {
    $day = $script:App.CurrentDay
    $hasActive = ($day -and $day.Status -eq 'Aktiv')
    $comp = $null
    if ($hasActive) { $comp = Get-DayComputation -Day $day -Now (Get-Date) }

    $pauseHeader = 'Pause starten'
    $pauseEnabled = $false
    if ($comp) {
        if ($comp.OpenPause) { $pauseHeader = 'Pause beenden'; $pauseEnabled = $true }
        elseif ($comp.RunningMode -eq 'Homeoffice' -and -not $comp.MaxReached) { $pauseEnabled = $true }
    }

    $items = $script:App.Ui.MenuItems
    if ($items.Count -gt 0) {
        $items['StartDay'].IsEnabled = (-not $hasActive)
        $items['SwitchMode'].IsEnabled = ($hasActive -and $comp -and $null -ne $comp.RunningMode -and -not $comp.MaxReached)
        $items['Pause'].Header = $pauseHeader
        $items['Pause'].IsEnabled = $pauseEnabled
        $items['Comment'].IsEnabled = ($null -ne $day)
        $items['KeepAlive'].IsChecked = [bool]$script:App.Settings['KeepAliveEnabled']
        $items['EndDay'].IsEnabled = $hasActive
    }

    $trayItems = $script:App.Ui.TrayItems
    if ($trayItems.Count -gt 0) {
        $trayItems['StartDay'].Enabled = (-not $hasActive)
        $trayItems['SwitchMode'].Enabled = ($hasActive -and $comp -and $null -ne $comp.RunningMode -and -not $comp.MaxReached)
        $trayItems['Pause'].Text = $pauseHeader
        $trayItems['Pause'].Enabled = $pauseEnabled
        $trayItems['Comment'].Enabled = ($null -ne $day)
        $trayItems['KeepAlive'].Checked = [bool]$script:App.Settings['KeepAliveEnabled']
        $trayItems['EndDay'].Enabled = $hasActive
    }

    # Radio-Menuepunkte (beide Menues) mit dem zentralen Zustand abgleichen
    Update-RadioMenuItems
    # Preset-Untermenue der kompakten Ansicht neu aufbauen
    Update-CompactPresetMenu
}

# Baut das Preset-Untermenue der kompakten Ansicht neu auf: fest eingebaute
# Presets (Standard/Klassisch/Minimum) plus eigene Presets. Das Aktivieren
# eines Presets veraendert ausschliesslich die Feldauswahl (Einstellungen) -
# niemals Arbeitszeitdaten.
function Update-CompactPresetMenu {
    try {
        $items = $script:App.Ui.MenuItems
        if (-not $items.Contains('CompactPresets')) { return }
        $sub = $items['CompactPresets']
        $sub.Items.Clear()
        $currentFields = @($script:App.Settings['CompactFields'])
        $addPreset = {
            param([string]$Name, $Fields, [bool]$BuiltIn)
            $mi = New-Object System.Windows.Controls.MenuItem
            $mi.Header = $Name
            $mi.IsCheckable = $true
            $presetFields = @($Fields)
            $mi.IsChecked = (($presetFields -join '|') -eq ($currentFields -join '|'))
            if ($Name -eq 'Minimum') { $mi.ToolTip = $script:CompactPresetPrivacyHint }
            $capturedName = $Name
            $capturedFields = $presetFields
            $mi.Add_Click({ Set-CompactFieldsPreset -Fields $capturedFields -PresetName $capturedName | Out-Null }.GetNewClosure())
            [void]$sub.Items.Add($mi)
        }
        foreach ($name in @($script:CompactPresets.Keys)) {
            & $addPreset ([string]$name) $script:CompactPresets[$name] $true
        }
        $customs = @($script:App.Settings['CompactPresets'])
        if ($customs.Count -gt 0) {
            [void]$sub.Items.Add((New-Object System.Windows.Controls.Separator))
            foreach ($p in $customs) {
                if ($null -eq $p) { continue }
                & $addPreset ([string]$p['Name']) @($p['Fields']) $false
            }
        }
    }
    catch { }
}

function Enable-TrayIcon {
    if ($script:App.Ui.Tray) { return }
    try {
        $icon = New-Object System.Windows.Forms.NotifyIcon
        $icon.Icon = [System.Drawing.SystemIcons]::Application
        $icon.Text = 'ArbeitszeitTool'
        $menu = New-Object System.Windows.Forms.ContextMenuStrip
        $trayItems = @{}
        $addItem = {
            param($Key, $Text, $Handler)
            $item = New-Object System.Windows.Forms.ToolStripMenuItem
            $item.Text = $Text
            $item.Add_Click($Handler)
            [void]$menu.Items.Add($item)
            $trayItems[$Key] = $item
        }
        # Alle NotifyIcon-/Windows-Forms-Ereignisse fuehren WPF-Aktionen
        # kontrolliert ueber den Dispatcher des kompakten Fensters aus
        # (Invoke-OnUiDispatcher) - keine direkten WPF-Zugriffe aus einem
        # moeglicherweise fremden Ereignisthread.
        & $addItem 'Extended' 'Erweiterte Ansicht öffnen' { Invoke-OnUiDispatcher -Action { Show-ExtendedWindow } }
        & $addItem 'Compact' 'Kompakte Ansicht anzeigen' { Invoke-OnUiDispatcher -Action { Show-CompactWindow } }
        & $addItem 'HideCompact' 'Kompakte Ansicht ausblenden' { Invoke-OnUiDispatcher -Action { Hide-CompactWindow } }
        & $addItem 'StartDay' 'Arbeitstag starten...' { Invoke-OnUiDispatcher -Action { Invoke-StartDayFlow } }
        & $addItem 'SwitchMode' 'Modus wechseln...' { Invoke-OnUiDispatcher -Action { Invoke-ModeSwitchFlow } }
        & $addItem 'Pause' 'Pause starten' { Invoke-OnUiDispatcher -Action { Invoke-TogglePauseFlow } }
        & $addItem 'Comment' 'Kommentar...' { Invoke-OnUiDispatcher -Action { Invoke-CommentFlow } }
        & $addItem 'KeepAlive' 'Scroll-Lock-Aktivhaltung' { Invoke-OnUiDispatcher -Action { Invoke-ToggleKeepAlive } }
        & $addItem 'RadioPlay' 'Radio starten' { Invoke-OnUiDispatcher -Action { Switch-RadioPlayback } }
        $radioTraySub = New-Object System.Windows.Forms.ToolStripMenuItem
        $radioTraySub.Text = 'Radiosender'
        [void]$menu.Items.Add($radioTraySub)
        $trayItems['RadioStations'] = $radioTraySub
        & $addItem 'EndDay' 'Arbeitstag beenden...' { Invoke-OnUiDispatcher -Action { Invoke-EndDayFlow } }
        & $addItem 'Settings' 'Einstellungen...' { Invoke-OnUiDispatcher -Action { Show-SettingsDialog | Out-Null } }
        [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        & $addItem 'Close' 'Anwendung schließen' { Invoke-OnUiDispatcher -Action { if ($script:App.Ui.Compact) { $script:App.Ui.Compact.Close() } } }
        $menu.Add_Opening({ Invoke-OnUiDispatcher -Action { Update-MenuState } })
        $icon.ContextMenuStrip = $menu
        $icon.Add_DoubleClick({ Invoke-OnUiDispatcher -Action { Show-CompactWindow } })
        $icon.Visible = $true
        $script:App.Ui.Tray = $icon
        $script:App.Ui.TrayItems = $trayItems
    }
    catch {
        Write-AppLog -Level 'WARN' -Message ('Tray-Symbol konnte nicht erstellt werden: ' + $_.Exception.Message)
    }
}

function Disable-TrayIcon {
    $icon = $script:App.Ui.Tray
    if ($null -eq $icon) { return }
    try {
        $icon.Visible = $false
        $icon.Dispose()
    }
    catch { }
    $script:App.Ui.Tray = $null
    $script:App.Ui.TrayItems = @{}
}

function Update-TrayText {
    param($Comp, $Day)
    $icon = $script:App.Ui.Tray
    if ($null -eq $icon) { return }
    $text = 'ArbeitszeitTool - kein aktiver Arbeitstag'
    if ($Comp -and $Day) {
        if ($Day.Status -eq 'Beendet') {
            $text = 'Beendet | Netto ' + (Format-Duration $Comp.Netto)
        }
        elseif ($Comp.SollErreicht) {
            $text = 'Netto ' + (Format-Duration $Comp.Netto) + ' | Überstunden ' + (Format-Duration $Comp.Ueberstunden -WithSign)
        }
        else {
            $text = 'Netto ' + (Format-Duration $Comp.Netto) + ' | Soll-Rest ' + (Format-Duration $Comp.SollRest)
        }
    }
    if ($text.Length -gt 63) { $text = $text.Substring(0, 63) }
    try { $icon.Text = $text } catch { }
}

#endregion

#region ===== Fenster-Ereignisse =====

function Register-CompactWindowEvents {
    param([Parameter(Mandatory)]$Window)

    $Window.ContextMenu = New-CompactContextMenu

    $Window.Add_MouseLeftButtonDown({
            param($sender, $e)
            # Klicks auf die Radio-Bedienelemente duerfen KEIN DragMove des
            # Fensters ausloesen (Buttons behandeln ihre Ereignisse zwar
            # selbst, dies ist die zusaetzliche Absicherung).
            $dep = $e.OriginalSource -as [System.Windows.DependencyObject]
            $radioPanel = $sender.FindName('PnlRadio')
            while ($dep) {
                if ($dep -eq $radioPanel) { return }
                if ($dep -is [System.Windows.Window]) { break }
                $dep = [System.Windows.Media.VisualTreeHelper]::GetParent($dep)
            }
            if ($e.ClickCount -eq 2) {
                Show-ExtendedWindow
                return
            }
            # DragMove blockiert bis zum Loslassen der Maustaste; gespeichert
            # wird genau EINMAL nach dem Ende des Ziehens - und nur, wenn sich
            # die Position tatsaechlich geaendert hat.
            try { $sender.DragMove() } catch { }
            Save-CompactWindowPlacement -Window $sender | Out-Null
        })

    # --- Internetradio: Bedienelemente der kompakten Ansicht ---
    $Window.FindName('BtnRadioPlay').Add_Click({ Switch-RadioPlayback })
    $Window.FindName('BtnRadioVolume').Add_Click({
            param($sender, $e)
            try {
                $win = $script:App.Ui.Compact
                $pop = $win.FindName('PopRadioVolume')
                if ($pop.IsOpen) { $pop.IsOpen = $false; return }
                $pop.PlacementTarget = $win.FindName('BtnRadioVolume')
                $win.FindName('SldRadioVolume').Value = [int]$script:App.Settings['RadioVolume']
                $win.FindName('LblRadioVolume').Text = ('{0} %' -f [int]$script:App.Settings['RadioVolume'])
                $pop.IsOpen = $true
            }
            catch { }
        })
    # Mausrad ueber dem Lautsprechersymbol veraendert die Lautstaerke
    $Window.FindName('BtnRadioVolume').Add_MouseWheel({
            param($sender, $e)
            try {
                $delta = 5
                if ($e.Delta -lt 0) { $delta = -5 }
                Set-RadioVolume -Percent ([int]$script:App.Settings['RadioVolume'] + $delta) -NoSave
            }
            catch { }
        })
    $Window.FindName('SldRadioVolume').Add_ValueChanged({
            param($sender, $e)
            try {
                Set-RadioVolume -Percent ([int]$sender.Value) -NoSave
                $script:App.Ui.Compact.FindName('LblRadioVolume').Text = ('{0} %' -f [int]$sender.Value)
            }
            catch { }
        })
    # Speichern erst beim Schliessen des Popups (kein Tresor-Schreiben pro Pixel)
    $Window.FindName('PopRadioVolume').Add_Closed({
            try {
                if ($script:App.Radio.VolumeSavePending) {
                    $script:App.Radio.VolumeSavePending = $false
                    Save-Settings -Quiet | Out-Null
                }
            }
            catch { }
        })

    $Window.Add_SourceInitialized({
            param($sender, $e)
            $script:App.Ui.Handle = (New-Object System.Windows.Interop.WindowInteropHelper $sender).Handle
        })

    $Window.Add_ContentRendered({
            param($sender, $e)
            Set-CompactWindowPosition -Window $sender
        })

    # Nach dem Wiederherstellen aus der Taskleiste die Taskleisten-Sichtbarkeit
    # wieder an die Tray-Einstellung koppeln
    $Window.Add_StateChanged({
            param($sender, $e)
            if ($sender.WindowState -eq [System.Windows.WindowState]::Normal) {
                $sender.ShowInTaskbar = -not [bool]$script:App.Settings['TrayIconEnabled']
            }
        })

    $Window.Add_Closing({
            param($sender, $e)
            if ($script:App.CloseConfirmed -or $script:App.ShuttingDown) { return }
            $e.Cancel = $true
            $sender.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [action] {
                    $closeResult = Invoke-CloseFlow
                    if ($closeResult -eq 'NormalSchliessen') {
                        $script:App.CloseConfirmed = $true
                        # Position vor dem regulaeren Beenden sichern
                        Save-CompactWindowPlacement -Window $script:App.Ui.Compact | Out-Null
                        $script:App.Ui.Compact.Close()
                    }
                    # 'ShutdownGestartet': Der gemeinsame Shutdownpfad hat
                    # CloseConfirmed gesetzt und das Fenster bereits
                    # kontrolliert geschlossen - hier darf KEIN zweiter
                    # Schliessvorgang folgen (kein doppelter Close-Flow,
                    # kein doppelter Dispatcher-Shutdown).
                    # 'Abbrechen': Das Fenster bleibt geoeffnet,
                    # CloseConfirmed bleibt false.
                }) | Out-Null
        })

    $Window.Add_Closed({
            # Nur ein ENDGUELTIG geschlossenes kompaktes Fenster beendet die
            # Anwendung (Hide() loest dieses Ereignis nicht aus): Dispatcher
            # kontrolliert herunterfahren.
            Stop-ApplicationDispatcher
        })
}

function Register-ExtendedWindowEvents {
    param([Parameter(Mandatory)]$Window)
    $Window.Add_Closing({
            param($sender, $e)
            # Beim Schliessen/Ausblenden werden die Pausen-/Sperrzeit-Details
            # automatisch wieder verborgen
            Hide-PauseLockDetails
            if (-not $script:App.ShuttingDown) {
                $e.Cancel = $true
                $sender.Hide()
            }
        })
    $Window.Add_StateChanged({
            param($sender, $e)
            if ($sender.WindowState -eq [System.Windows.WindowState]::Minimized) {
                Hide-PauseLockDetails
            }
        })
    # Fokusverlust: nach 60 Sekunden ohne Aktivierung automatisch wieder
    # verbergen (der Timer beeinflusst ausschliesslich die Darstellung)
    if ($null -eq $script:App.Timers['PrivacyHide']) {
        $privacyTimer = New-Object System.Windows.Threading.DispatcherTimer
        $privacyTimer.Interval = [TimeSpan]::FromSeconds(60)
        $privacyTimer.Add_Tick({
                try { $script:App.Timers['PrivacyHide'].Stop() } catch { }
                Hide-PauseLockDetails
            })
        $script:App.Timers['PrivacyHide'] = $privacyTimer
    }
    $Window.Add_Deactivated({
            try { $script:App.Timers['PrivacyHide'].Stop(); $script:App.Timers['PrivacyHide'].Start() } catch { }
        })
    $Window.Add_Activated({
            try { $script:App.Timers['PrivacyHide'].Stop() } catch { }
        })
    $Window.FindName('BtnPrivacyEye').Add_Click({ Switch-PauseLockDetailsVisibility })

    # --- Internetradio: Bedienelemente der erweiterten Ansicht ---
    $Window.FindName('BtnExtRadioPlay').Add_Click({ Switch-RadioPlayback })
    $Window.FindName('CmbRadioStation').Add_SelectionChanged({
            param($sender, $e)
            try {
                if ($script:App.Radio.UiUpdating) { return }
                if ($null -ne $sender.SelectedValue) { Select-RadioStation -Id ([string]$sender.SelectedValue) }
            }
            catch { }
        })
    $Window.FindName('SldExtRadioVolume').Add_ValueChanged({
            param($sender, $e)
            try {
                if ($script:App.Radio.UiUpdating) { return }
                Set-RadioVolume -Percent ([int]$sender.Value) -NoSave
            }
            catch { }
        })
    # Speichern erst nach dem Ende der Sliderbewegung (gedrosselt)
    $Window.FindName('SldExtRadioVolume').Add_LostMouseCapture({
            try {
                if ($script:App.Radio.VolumeSavePending) {
                    $script:App.Radio.VolumeSavePending = $false
                    Save-Settings -Quiet | Out-Null
                }
            }
            catch { }
        })
    $Window.FindName('BtnStartDay').Add_Click({ Invoke-StartDayFlow })
    $Window.FindName('BtnSwitchMode').Add_Click({ Invoke-ModeSwitchFlow })
    $Window.FindName('BtnPause').Add_Click({ Invoke-TogglePauseFlow })
    $Window.FindName('BtnComment').Add_Click({ Invoke-CommentFlow })
    $Window.FindName('BtnAddSegment').Add_Click({ Invoke-AddSegmentFlow })
    $Window.FindName('BtnEditDay').Add_Click({
            if ($script:App.CurrentDay) { Show-DayEditor -Day $script:App.CurrentDay }
            else { Show-Info -Message 'Es ist kein Arbeitstag vorhanden.' }
        })
    $Window.FindName('BtnHistory').Add_Click({ Show-HistoryWindow })
    $Window.FindName('BtnExport').Add_Click({ Show-ExportDialog })
    $Window.FindName('BtnSettings').Add_Click({ Show-SettingsDialog | Out-Null })
    $Window.FindName('BtnEndDay').Add_Click({ Invoke-EndDayFlow })
}

#endregion

#region ===== Timer, Einstellungen anwenden, Bereinigung =====

function Start-AppTimers {
    # Es existiert genau EINE Timerinstanz mit genau EINEM Tick-Handler je
    # Timer. Mehrfache Aufrufe (z. B. durch wiederholtes Aktivieren der
    # Aktivhaltung) duerfen keine zusaetzlichen Timer oder Handler anlegen.
    if ($script:App.Timers.Main) { return }
    $main = New-Object System.Windows.Threading.DispatcherTimer
    $main.Interval = [TimeSpan]::FromSeconds(1)
    $main.Add_Tick({ Invoke-MainTick })
    $main.Start()
    $script:App.Timers.Main = $main

    # Der Minuten-Timer darf dauerhaft laufen: Test-KeepAliveShouldRun prueft
    # in jedem Zyklus sauber, ob er arbeiten darf.
    $keepAlive = New-Object System.Windows.Threading.DispatcherTimer
    $keepAlive.Interval = [TimeSpan]::FromSeconds([int]$script:App.Settings['KeepAliveIntervalSec'])
    $keepAlive.Add_Tick({ Invoke-KeepAliveCycle })
    $keepAlive.Start()
    $script:App.Timers.KeepAlive = $keepAlive
}

function Stop-AppTimers {
    foreach ($key in @($script:App.Timers.Keys)) {
        $timer = $script:App.Timers[$key]
        if ($timer) {
            try { $timer.Stop() } catch { }
        }
    }
}

# Wird nach dem Speichern der Einstellungen aufgerufen
function Invoke-SettingsApplied {
    Set-CompactAppearance
    if ($script:App.Timers.KeepAlive) {
        $script:App.Timers.KeepAlive.Interval = [TimeSpan]::FromSeconds([int]$script:App.Settings['KeepAliveIntervalSec'])
    }
    # Eine ueber die Einstellungen deaktivierte Rollen-Funktion startet keine
    # neuen Pulse mehr (Test-KeepAliveShouldRun); ein bereits laufender
    # Doppelpuls beendet sich regulaer im Hintergrund. Kein Tastenzustand
    # wird abgefragt, keine zusaetzliche Umschaltung durchgefuehrt.
    if ([bool]$script:App.Settings['TrayIconEnabled']) { Enable-TrayIcon }
    else { Disable-TrayIcon }
    $win = $script:App.Ui.Compact
    if ($win) {
        $win.ShowInTaskbar = -not [bool]$script:App.Settings['TrayIconEnabled']
    }
    # Internetradio: geaenderte Einstellungen auf den zentralen Zustand
    # anwenden. Massgeblich ist der TATSAECHLICH geoeffnete Sender samt
    # Streamadresse (Playerkontext) - nicht nur die gespeicherte Auswahl.
    try {
        $radio = $script:App.Radio
        $wasPlaying = ($radio.DesiredState -eq 'Playing')
        $openStationId = ''
        $openUrl = ''
        if ($radio.PlayerContext) {
            $openStationId = [string]$radio.PlayerContext.StationId
            $openUrl = [string]$radio.PlayerContext.Url
        }
        if ($radio.Player) {
            $radio.Player.Volume = ([math]::Max(0, [math]::Min(100, [int]$script:App.Settings['RadioVolume']))) / 100.0
        }
        $action = Get-RadioSettingsChangeAction -WasPlaying $wasPlaying -OpenStationId $openStationId -OpenUrl $openUrl
        switch ([string]$action.Kind) {
            'NeuOeffnen' { [void](Open-RadioStation -Station $action.Station) }
            'Ersatz' { [void](Open-RadioStation -Station $action.Station) }
            'Stopp' { Stop-RadioPlayback }
            default {
                # 'Weiter' (Stream laeuft unveraendert) bzw. 'Nichts'
                # (Radio war pausiert/gestoppt: nicht automatisch starten)
                $radio.SelectedStationId = [string]$script:App.Settings['RadioSelectedStationId']
            }
        }
        Update-RadioUi
    }
    catch { }
    Invoke-MainRefresh -ForceTables
    # Feldauswahl oder Schriftgroesse koennen sich geaendert haben:
    # Layout der kompakten Ansicht vollstaendig neu vermessen, damit das
    # Fenster auch wieder schrumpfen kann.
    Update-CompactWindowLayout
}

# Beendet die Anwendung kontrolliert beim ECHTEN Programmende: alle Fenster
# schliessen, Tray-Symbol entfernen und den WPF-Dispatcher herunterfahren
# (beendet Dispatcher::Run in Start-Application). Invoke-AppCleanup laeuft
# danach AUSSCHLIESSLICH im finally des Haupteinstiegs. Ein blosses
# Verbergen des kompakten Fensters ruft diese Funktion niemals auf.
function Stop-ApplicationDispatcher {
    $script:App.ShuttingDown = $true
    try {
        if ($script:App.Ui.Extended) { $script:App.Ui.Extended.Close() }
    }
    catch { }
    try { Disable-TrayIcon } catch { }
    try {
        $disp = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
        if (-not $disp.HasShutdownStarted) {
            $disp.BeginInvokeShutdown([System.Windows.Threading.DispatcherPriority]::Background)
        }
    }
    catch { }
}

function Invoke-AppCleanup {
    $script:App.ShuttingDown = $true
    # Ab jetzt keine neuen Scroll-Lock-Pulse mehr (threadsicher im C#)
    try { [ArbeitszeitTool.NativeInput]::BeginShutdown() } catch { }
    Stop-AppTimers
    try { [ArbeitszeitTool.SessionMonitor]::Stop() } catch { }
    # Hoechstens kurz (max. ~500 ms) auf einen laufenden Doppelpuls warten;
    # das Beenden wird nicht dauerhaft blockiert (siehe Wait-Funktion).
    Wait-ScrollLockPulseCompletion
    # Internetradio kontrolliert beenden - eine Ausnahme hier darf den
    # finalen Speichervorgang NICHT verhindern
    try { Clear-RadioPlayer } catch { }
    try { Hide-PauseLockDetails } catch { }
    try {
        if ($script:App.Ui.Extended) { $script:App.Ui.Extended.Close() }
    }
    catch { }
    Disable-TrayIcon
    try {
        if ($script:App.Vault -and $script:VaultSession.Unlocked) {
            $day = $script:App.CurrentDay
            if ($day -and $day.Status -eq 'Aktiv') {
                Update-DayTotals -Day $day | Out-Null
            }
            Write-AppLog -Message 'Programmende.'
            # Regulaeres Programmende: CleanShutdown setzen und final speichern
            $script:App.Vault['CleanShutdown'] = $true
            Save-Vault | Out-Null
        }
    }
    catch { }
    # Sitzungsschluessel beim Programmende ueberschreiben (Array.Clear).
    # Hinweis: In verwaltetem .NET-Speicher ist kein absolut garantiertes
    # Loeschen saemtlicher zwischenzeitlicher Stringkopien moeglich.
    Clear-VaultSessionKeys
    # Einzelinstanz-Sperre erst NACH dem finalen Speichern freigeben
    Exit-SingleInstance
}

#endregion


#region ===== Start, Wiederherstellung und Haupteinstieg =====

# Offene Sperrintervalle aus einer frueheren Sitzung deterministisch schliessen:
# gesichert ist nur, dass bis zum letzten TRACKING-Checkpoint der vorherigen
# Sitzung gesperrt war. Es wird der unveraenderte vorherige Wert aus dem
# RecoveryState verwendet - nicht der bereits neu gespeicherte Sitzungsstatus.
# Ein offenes Sperrintervall wird dadurch niemals bis zum aktuellen
# Programmstart verlaengert.
function Close-StaleOpenLocks {
    param([Parameter(Mandatory)]$Day)
    $lastSavedText = $null
    if ($script:App -and $script:App.Data) { $lastSavedText = $script:App.Data['LastSavedAt'] }
    if ($script:App -and $script:App.RecoveryState) { $lastSavedText = $script:App.RecoveryState.PreviousLastSavedAt }
    $lastSaved = ConvertFrom-DateTimeString $lastSavedText
    foreach ($iv in @($Day.LockIntervals)) {
        if ($null -ne $iv.End) { continue }
        $start = ConvertFrom-DateTimeString $iv.Start
        $end = $lastSaved
        if ($null -eq $end -or $end -lt $start) { $end = $start }
        $iv['End'] = ConvertTo-DateTimeString $end
        Write-AppLog -Level 'WARN' -Message ("Offenes Sperrintervall nach Neustart geschlossen ({0} - {1})." -f (Format-Clock $start), (Format-Clock $end))
    }
}

# Fuegt fuer eine nicht beobachtete Zeitluecke ein Pausen- oder Sperrintervall
# in den VORHANDENEN Tag ein. Es wird dabei NIEMALS ein neuer
# Arbeitsabschnitt erzeugt oder ein bestehender beendet. Reine, testbare
# Funktion (speichert nicht selbst).
function Add-GapInterval {
    param(
        [Parameter(Mandatory)]$Day,
        [Parameter(Mandatory)][ValidateSet('Pause', 'Sperrzeit')][string]$Kind,
        [Parameter(Mandatory)][datetime]$Start,
        [Parameter(Mandatory)][datetime]$End
    )
    $iv = New-IntervalObject -Start $Start -End $End
    if ($Kind -eq 'Pause') { [void]$Day['ManualPauses'].Add($iv) }
    else { [void]$Day['LockIntervals'].Add($iv) }
    Add-Correction -Day $Day -Description ("Luecke nach Neustart als {0} gewertet" -f $Kind) -NewValue ('{0}-{1}' -f (Format-Clock $Start), (Format-Clock $End))
    return $iv
}

# Behandelt eine beim letzten Beenden noch offene manuelle Pause
function Invoke-OpenPauseRecovery {
    param([Parameter(Mandatory)]$Day)
    $openPause = Get-OpenManualPause -Day $Day
    if ($null -eq $openPause) { return }
    $pauseStart = ConvertFrom-DateTimeString $openPause.Start
    $choice = Show-PauseRecoveryDialog -PauseStart $pauseStart
    switch ($choice.Choice) {
        'Weiter' {
            Write-AppLog -Message 'Wiederherstellung: manuelle Pause läuft weiter.'
        }
        'EndeteUm' {
            $openPause['End'] = ConvertTo-DateTimeString $choice.EndTime
            Add-Correction -Day $Day -Description 'Pausenende nach Neustart gesetzt' -NewValue (Format-Clock $choice.EndTime)
        }
        'Verwerfen' {
            [void]$Day['ManualPauses'].Remove($openPause)
            Add-Correction -Day $Day -Description 'Offene Pause nach Neustart verworfen' -OldValue (Format-Clock $pauseStart)
        }
        'Bearbeiten' {
            Show-DayEditor -Day $Day
        }
    }
    Update-DayTotals -Day $Day | Out-Null
    # Die real getroffene Entscheidung bleibt uebernommen; bei einem
    # Speicherfehler wird aber KEIN Erfolg behauptet (Save-Vault informiert
    # den Benutzer neutral, der Zustand ist als NICHT GESPEICHERT markiert
    # und die automatische Wiederholung laeuft).
    if (-not (Save-WorkData)) {
        Write-AppLog -Level 'WARN' -Message 'Wiederherstellungsentscheidung (offene Pause) übernommen, aber noch NICHT gespeichert - automatische Wiederholung läuft.'
    }
}

# Behandelt die Zeitluecke eines laufenden Homeoffice-Abschnitts, in der
# Sperren/Entsperren nicht beobachtbar war. Massgeblich ist der unveraenderte
# Tracking-Checkpoint der VORHERIGEN Sitzung (RecoveryState) - nicht der
# bereits neu gespeicherte Sitzungsstatus. Es wird zwingend nachgefragt.
# WICHTIG: Keine Auswahl erzeugt einen neuen Arbeitsabschnitt; nur die
# ausdrueckliche Angabe "Abschnitt endete um" beendet den bestehenden.
function Invoke-HomeofficeGapRecovery {
    param([Parameter(Mandatory)]$Day)
    if (Get-OpenManualPause -Day $Day) { return }
    $gapData = $script:App.Data
    if ($script:App.RecoveryState) {
        $gapData = @{ LastSavedAt = $script:App.RecoveryState.PreviousLastSavedAt }
    }
    $gap = Get-HomeofficeGap -Day $Day -Data $gapData -Now (Get-Date)
    if ($null -eq $gap) { return }
    $choice = Show-HoGapDialog -GapStart $gap.Start -GapEnd $gap.End
    switch ($choice.Choice) {
        'Arbeitszeit' {
            # Bestehenden Abschnitt unveraendert weiterlaufen lassen
            Write-AppLog -Message 'Wiederherstellung: Luecke vollstaendig als Arbeitszeit gewertet.'
        }
        'Pause' {
            Add-GapInterval -Day $Day -Kind 'Pause' -Start $gap.Start -End $gap.End | Out-Null
        }
        'Sperrzeit' {
            Add-GapInterval -Day $Day -Kind 'Sperrzeit' -Start $gap.Start -End $gap.End | Out-Null
        }
        'Aufteilen' {
            if ($choice.SplitTime -lt $gap.End) {
                $iv = New-IntervalObject -Start $choice.SplitTime -End $gap.End
                [void]$Day['ManualPauses'].Add($iv)
            }
            Add-Correction -Day $Day -Description 'Luecke nach Neustart aufgeteilt' -NewValue ('Arbeit bis {0}, danach Pause bis {1}' -f (Format-Clock $choice.SplitTime), (Format-Clock $gap.End))
        }
        'EndeteUm' {
            # NUR auf ausdrueckliche Benutzerangabe wird der Abschnitt beendet
            Stop-RunningSegment -Day $Day -End $choice.EndTime | Out-Null
            Add-Correction -Day $Day -Description 'Abschnittsende nach Neustart gesetzt' -NewValue (Format-Clock $choice.EndTime)
        }
        'Bearbeiten' {
            Show-DayEditor -Day $Day
        }
    }
    Update-DayTotals -Day $Day | Out-Null
    # Kein falscher Erfolg: die Lueckenentscheidung bleibt uebernommen, ein
    # Speicherfehler wird aber sichtbar gemacht (NICHT GESPEICHERT + Retry).
    if (-not (Save-WorkData)) {
        Write-AppLog -Level 'WARN' -Message 'Homeoffice-Lückenentscheidung übernommen, aber noch NICHT gespeichert - automatische Wiederholung läuft.'
    }
}

# SAUBERER regulaerer Neustart (PreviousCleanShutdown = true) mit
# "Fortsetzen": derselbe Tag und derselbe laufende Abschnitt werden
# UNVERAENDERT weiterverwendet - keine neue Segment-ID, kein neuer
# Timeslot, kein Stop-RunningSegment, kein Moduswechsel. Im Betrieb zaehlt
# die Zeit des geplanten Neustarts normal als Arbeitszeit weiter. Im
# Homeoffice wird ausschliesslich die nicht beobachtete Zeitluecke behandelt
# (Pause/Sperrzeit/Aufteilen/ausdrueckliches Ende - niemals ein neuer
# Abschnitt). Danach 10-Stunden-Grenze pruefen und neuen Checkpoint speichern.
function Invoke-CleanResume {
    param([Parameter(Mandatory)]$Day)
    if (Get-OpenManualPause -Day $Day) {
        Invoke-OpenPauseRecovery -Day $Day
    }
    $comp = Get-DayComputation -Day $Day -Now (Get-Date)
    if ($comp.RunningMode -eq 'Homeoffice') {
        Invoke-HomeofficeGapRecovery -Day $Day
    }
    Invoke-AutoStopIfNeeded -Day $Day | Out-Null
    Update-MaxReachedState -Day $Day
    Update-DayTotals -Day $Day | Out-Null
    # Erfolgslog NUR bei tatsaechlich gespeichertem Checkpoint; sonst bleibt
    # der Zustand sichtbar als NICHT GESPEICHERT (automatische Wiederholung).
    if (Save-WorkData) {
        Write-AppLog -Message 'Arbeitstag nach regulärem Neustart unverändert fortgesetzt (kein neuer Abschnitt).'
    }
    else {
        Write-AppLog -Level 'WARN' -Message 'Arbeitstag fortgesetzt, aber der neue Checkpoint wurde noch NICHT gespeichert - automatische Wiederholung läuft.'
    }
}

# ABSTURZ-Wiederherstellung (PreviousCleanShutdown = false): offene Pause,
# Homeoffice-Luecke und 10-Stunden-Grenze behandeln (bestehendes Verhalten;
# arbeitet mit dem RecoveryState der vorherigen Sitzung). Auch hier entsteht
# ohne ausdruecklichen Moduswechsel niemals ein neuer Arbeitsabschnitt.
function Invoke-CrashRecovery {
    param([Parameter(Mandatory)]$Day)
    Invoke-OpenPauseRecovery -Day $Day
    Invoke-HomeofficeGapRecovery -Day $Day
    Invoke-AutoStopIfNeeded -Day $Day | Out-Null
    Update-MaxReachedState -Day $Day
    # Wiederherstellung abgeschlossen: erst JETZT wird der neue regulaere
    # Tracking-Checkpoint gespeichert (WorkData.LastSavedAt = jetzt).
    Update-DayTotals -Day $Day | Out-Null
    if (Save-WorkData) {
        Write-AppLog -Message 'Absturzwiederherstellung abgeschlossen.'
    }
    else {
        Write-AppLog -Level 'WARN' -Message 'Absturzwiederherstellung übernommen, aber noch NICHT gespeichert - automatische Wiederholung läuft.'
    }
}

# Der Start-Dialog fuer einen neuen Arbeitstag darf NUR erscheinen, wenn
# saemtliche Startentscheidungen abgeschlossen sind und tatsaechlich kein
# aktiver Tag existiert. Reine, testbare Funktion.
function Test-ShouldOfferStartDay {
    if ($null -eq $script:App) { return $false }
    if ($script:App.ShuttingDown) { return $false }
    if (-not $script:App.Flags.ActiveDayDecisionCompleted) { return $false }
    # Solange ein automatisch beendeter Vortag noch nicht geklaert wurde,
    # darf kein neuer Arbeitstag angeboten werden (auch nicht ueber einen
    # verspaeteten Dispatcher-Aufruf).
    if ($null -ne (Get-AutoEndReviewCandidate)) { return $false }
    return ($null -eq (Get-ActiveDay))
}

# Markiert den Beginn der neuen Sitzung (neue SessionId, CleanShutdown=false)
# und speichert mit -NoTrackingCheckpoint. Liefert das ECHTE Speicherergebnis -
# schlaegt es fehl, darf die Anwendung nicht produktiv starten.
function Invoke-SessionStartSave {
    $script:App.Vault['SessionId'] = [guid]::NewGuid().ToString()
    $script:App.Vault['CleanShutdown'] = $false
    return [bool](Save-Vault -NoTrackingCheckpoint)
}

# Einzelinstanz je Datenordner: Zwei gleichzeitig laufende
# Instanzen auf denselben Tresordateien koennten sich gegenseitig Aenderungen
# ueberschreiben. Benannter Mutex in der Windows-Sitzung; der Name wird aus
# dem Hash des vollstaendigen Datenpfads gebildet (keine Pfad-/Benutzernamen
# im Objektnamen). Grenzen: schuetzt nicht gegen andere Rechner bzw. Sync-
# Clients (dafuer: Hash-Pruefung in Save-Vault) und nicht, wenn derselbe
# Ordner ueber verschiedene Pfade (z. B. Laufwerksbuchstabe vs. UNC) geoeffnet
# wird. Ein verwaister Mutex (Absturz) gilt als frei.
function Get-SingleInstanceMutexName {
    $fullPath = [System.IO.Path]::GetFullPath($script:Paths.Data).TrimEnd('\').ToLowerInvariant()
    $hash = Get-BytesSha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes($fullPath))
    return ('Local\ArbeitszeitTool-' + $hash.Substring(0, 32))
}

function Enter-SingleInstance {
    $mutex = New-Object System.Threading.Mutex($false, (Get-SingleInstanceMutexName))
    $acquired = $false
    try { $acquired = $mutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $acquired = $true }
    if (-not $acquired) {
        $mutex.Dispose()
        return $false
    }
    $script:InstanceMutex = $mutex
    return $true
}

function Exit-SingleInstance {
    if ($null -eq $script:InstanceMutex) { return }
    try { $script:InstanceMutex.ReleaseMutex() } catch { }
    try { $script:InstanceMutex.Dispose() } catch { }
    $script:InstanceMutex = $null
}

function Start-Application {
    Initialize-Folders

    if (-not (Enter-SingleInstance)) {
        try {
            [System.Windows.MessageBox]::Show(
                ("Das ArbeitszeitTool läuft bereits mit diesem Datenordner.`r`n`r`n" +
                    "Bitte die bereits geöffnete Instanz verwenden (ggf. im Infobereich der Taskleiste). " +
                    "Zwei gleichzeitig laufende Instanzen könnten sich gegenseitig Änderungen überschreiben."),
                'ArbeitszeitTool - bereits gestartet',
                [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        }
        catch { }
        return
    }

    # Ohne funktionsfaehige SHA256-Kryptografie werden keine Dateien veraendert
    # und keine schwaechere Verschluesselung verwendet.
    if (-not $script:VaultCryptoReady) {
        try {
            [System.Windows.MessageBox]::Show(
                ("Die benötigten .NET-Kryptografiefunktionen (PBKDF2 mit SHA256) stehen auf diesem System nicht zur Verfügung. " +
                    "Erforderlich ist .NET Framework 4.7.2 oder neuer (in Windows 10/11 enthalten).`r`n`r`n" +
                    "Es wurden keine Dateien verändert. Technischer Hinweis: " + $script:VaultCryptoError),
                'ArbeitszeitTool - Verschlüsselung nicht verfügbar',
                [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
        }
        catch { }
        return
    }

    Write-AppLog -Message '================ Programmstart ================'

    # Zwischenzustaende einer unterbrochenen Passwortaenderung oder eines
    # unterbrochenen Speichervorgangs (.new/.old/.prev/Transaktionsstatus)
    # werden VOR der Passwortabfrage erkannt und repariert. Die Referenz auf
    # die Hauptdatei (Hash/Existenz) wird erst DANACH beim Entsperren erfasst
    # und ist damit automatisch aktuell.
    Repair-VaultTransactionState | Out-Null

    # 1. Tresor entsperren, erstellen oder Altdaten migrieren
    $vaultPresent = Test-VaultFilesPresent
    $legacyFiles = Get-LegacyPlaintextFiles
    $legacyPresent = (@($legacyFiles).Count -gt 0)

    if (-not $vaultPresent -and -not $legacyPresent) {
        # Erststart: Passwort zweimal abfragen, dann leeren Tresor erstellen
        if (-not (Invoke-VaultCreationFlow -Caption 'Willkommen! Bitte ein Passwort für den neuen Datentresor festlegen.')) {
            return
        }
    }
    elseif (-not $vaultPresent) {
        # Nur Klartext-Altdaten vorhanden: einmalige Migration
        if (-not (Invoke-PlaintextMigration)) { return }
    }
    else {
        $conflictChoice = 'Tresor'
        if ($legacyPresent) {
            # Verschluesselte und unverschluesselte Daten gleichzeitig vorhanden:
            # nichts automatisch ueberschreiben oder zusammenfuehren
            $detail = ("Gefundene Klartextdateien:`r`n" + ((@($legacyFiles) | ForEach-Object { [string]$_ }) -join "`r`n"))
            $conflictChoice = Show-VaultConflictDialog -Detail $detail
            if ($conflictChoice -eq 'Abbrechen') { return }
        }
        if (-not (Invoke-VaultUnlockFlow)) { return }
        if ($conflictChoice -eq 'Import') {
            Invoke-PlaintextImportIntoVault | Out-Null
        }
    }

    # Nach dem Entsperren: verbliebene Reste einer unterbrochenen
    # Passwortaenderung kontrolliert fortsetzen bzw. archivieren. Wird dabei
    # die Hauptdatei ersetzt, aktualisiert die Bereinigung selbst Hash,
    # Existenz und Revision der Referenz (keine falsche Cloud-Erkennung).
    # Die Markierung einer unterbrochenen Recovery-Neuverschluesselung wird
    # VOR der Bereinigung gelesen (diese entfernt vault.txn).
    $recoveryInterrupted = Test-RecoveryReencryptionInterrupted
    Complete-VaultTransactionCleanup
    $recoveryNotice = Invoke-RecoveryStartupCheck -Interrupted $recoveryInterrupted
    if ($recoveryNotice -ne '') { Show-Warning -Message $recoveryNotice -Title 'Recovery-Ordner prüfen' }

    # 2. Unmittelbar nach dem erfolgreichen Entschluesseln und VOR jedem neuen
    # Speichervorgang: die unveraenderten Werte der vorherigen Sitzung sichern
    # (CleanShutdown, Tracking-Checkpoint, SessionId, laufender Abschnitt,
    # offene Intervalle, Quelle und Revision). Die Entscheidung zwischen
    # regulaerem Neustart und unerwartetem Abbruch basiert AUSSCHLIESSLICH
    # auf diesen Werten.
    $script:App.RecoveryState = New-RecoveryState -Vault $script:App.Vault -LoadedFrom $script:App.LoadedFrom

    # 3./4. Aktiven Tag SOFORT auf den geladenen Daten erkennen und zuweisen -
    # vor jedem Startdialog und vor jeder weiteren Startlogik.
    $active = Get-ActiveDay
    if ($active) { $script:App.CurrentDay = $active }

    # 5.-8. Sitzungsbeginn markieren (neue SessionId, CleanShutdown=false) und
    # das Speicherergebnis PRUEFEN: schlaegt es fehl, beginnt keine
    # ungesicherte Arbeitszeiterfassung und kein neuer Arbeitstag.
    if (-not (Invoke-SessionStartSave)) {
        Show-AppError -Message ('Die neue Sitzung konnte nicht im Datentresor gespeichert werden. ' +
            'Um keine ungesicherte Arbeitszeiterfassung zu beginnen, wird die Anwendung beendet. ' +
            'Bitte die Ursache prüfen (z. B. Schreibrechte oder eine im Ordner Recovery gesicherte Cloud-Konfliktdatei) und die Anwendung erneut starten.')
        return
    }

    [ArbeitszeitTool.SessionMonitor]::Start()

    # 9. Aktiven Tag behandeln (vor dem Aufbau der Oberflaeche)
    if ($active -and (Test-DayNeedsPreviousDayReview -Day $active)) {
        # Fall A: aktiver Arbeitstag aus einem frueheren Datum. Er wird NICHT
        # kommentarlos mit 10:00 gewertet oder an Mitternacht beendet, sondern
        # ausdruecklich geklaert (Bestaetigen / tatsaechliches Ende / Bearbeiten).
        # WICHTIG: Offene Sperrintervalle werden hier NICHT vorab veraendert -
        # sie werden erst innerhalb der tatsaechlich gewaehlten, erfolgreich
        # bestaetigten Abschlussaktion transaktional geschlossen. Bei
        # 'Abbrechen' bleibt der Tag dadurch vollstaendig unveraendert; auch
        # der spaetere Cleanup-Speichervorgang schreibt dann nur den
        # unveraenderten Zustand.
        $script:App.CurrentDay = $active
        if (-not (Invoke-AutoEndReviewFlow -Day $active)) {
            # Abbruch: kein neuer Arbeitstag, der Vortag bleibt unveraendert -
            # kontrollierte Rueckkehr zum Ausgangszustand (Programmende).
            Write-AppLog -Message 'Programmstart abgebrochen: nicht abgeschlossener Vortag wurde nicht geklärt.'
            return
        }
        $active = $null
    }
    elseif ($null -eq $active) {
        # Fall B: automatisch beendeter Vortag mit offener Bestaetigung.
        # Die Klaerung erfolgt VOR dem Angebot eines neuen Arbeitstags; bei
        # Abbruch bleibt die Anwendung geoeffnet, blockiert aber den Start
        # eines neuen Tages (Test-ShouldOfferStartDay).
        $reviewDay = Get-AutoEndReviewCandidate
        if ($null -ne $reviewDay) {
            $script:App.CurrentDay = $reviewDay
            Invoke-AutoEndReviewFlow -Day $reviewDay | Out-Null
        }
    }
    if ($active) {
        # Fall C: normaler Neustart am selben Kalendertag - unveraendert,
        # keine zusaetzliche Abfrage.
        Close-StaleOpenLocks -Day $active
        $cleanRestart = [bool]$script:App.RecoveryState.PreviousCleanShutdown
        $choice = Show-ResumeDialog -SummaryText (Get-DaySummaryText -Day $active)
        switch ($choice) {
            'Fortsetzen' {
                $script:App.CurrentDay = $active
                # Klar getrennte Pfade: sauberer regulaerer Neustart
                # (kein neuer Abschnitt) vs. Absturzwiederherstellung.
                if ($cleanRestart) { Invoke-CleanResume -Day $active }
                else { Invoke-CrashRecovery -Day $active }
                Write-AppLog -Message 'Arbeitstag fortgesetzt.'
            }
            'ModusWechsel' {
                # Ausdruecklicher Moduswechsel: NUR hierdurch entsteht ein
                # neuer Arbeitsabschnitt (bisheriger endet zum bestaetigten
                # Wechselzeitpunkt).
                $script:App.CurrentDay = $active
                if ($cleanRestart) { Invoke-CleanResume -Day $active }
                else { Invoke-CrashRecovery -Day $active }
                Invoke-ModeSwitchFlow
            }
            'Bearbeiten' {
                $script:App.CurrentDay = $active
                Show-DayEditor -Day $active
            }
            'Beenden' {
                $script:App.CurrentDay = $active
                # Beim Programmstart wird kein Shutdown angeboten (die
                # Oberflaeche ist noch nicht aufgebaut)
                $endResult = Show-EndDayDialog -Day $active -NoShutdownOption
                if ($endResult) { Complete-WorkDay -Day $active -End $endResult.End -Reason 'Manuell' -TrimTrailingIntervals | Out-Null }
            }
            default {
                Write-AppLog -Message 'Programmstart vom Benutzer abgebrochen.'
                return
            }
        }
    }
    else {
        # Heutigen (bereits beendeten) Tag zur Anzeige laden
        $today = Get-DayByDate -DateText (Get-TodayText)
        if ($today) { $script:App.CurrentDay = $today }
    }

    # Alle Startentscheidungen sind abgeschlossen: erst ab jetzt darf der
    # Start-Dialog fuer einen neuen Arbeitstag angeboten werden.
    $script:App.Flags.ActiveDayDecisionCompleted = $true

    # 10. Oberflaeche aufbauen
    $compact = New-XamlWindow -Xaml $script:CompactXaml
    $script:App.Ui.Compact = $compact
    Register-CompactWindowEvents -Window $compact
    Set-CompactAppearance
    $compact.ShowInTaskbar = -not [bool]$script:App.Settings['TrayIconEnabled']
    if ([bool]$script:App.Settings['TrayIconEnabled']) { Enable-TrayIcon }
    Start-AppTimers
    Invoke-MainRefresh -ForceTables
    Update-RadioUi

    # Optional gemerkten Radio-Wiedergabestatus fortsetzen (Standard: aus;
    # beim Programmstart findet sonst keine automatische Wiedergabe statt)
    if ([bool]$script:App.Settings['RadioRememberPlaybackState'] -and [bool]$script:App.Settings['RadioLastWasPlaying']) {
        try { [void](Start-RadioPlayback) } catch { }
    }

    if ([string]$script:App.Settings['StartView'] -eq 'Erweitert') {
        Show-ExtendedWindow
    }

    # Kein aktiver Tag? Direkt den Start-Dialog anbieten (abbrechbar).
    # Die Pruefung erfolgt doppelt: beim Einplanen UND beim Ausfuehren -
    # ein verspaeteter Dispatcher-Aufruf kann so niemals zusaetzlich einen
    # Startdialog neben einem aktiven Tag ausloesen.
    if (Test-ShouldOfferStartDay) {
        $compact.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::ApplicationIdle, [action] {
                if (Test-ShouldOfferStartDay) {
                    Invoke-StartDayFlow
                }
            }) | Out-Null
    }

    # Nichtmodale Lebensdauersteuerung: Das kompakte Fenster ist KEIN modaler
    # Lebensdauer-Anker mehr. Hide() (Ausblenden in den Infobereich) beendet
    # die Anwendung nicht; Timer, Radio, Scroll-Lock-Aktivhaltung und
    # Lock-/Unlock-Verarbeitung laufen unsichtbar weiter. Die Anwendung endet
    # erst, wenn Stop-ApplicationDispatcher den Dispatcher herunterfaehrt
    # (nach ENDGUELTIG bestaetigtem Schliessen) - erst danach laeuft
    # Invoke-AppCleanup im finally des Haupteinstiegs.
    $compact.Show()
    [System.Windows.Threading.Dispatcher]::Run()
}

# ===== Einstieg =====

# Testeinstieg (tests\Run-Tests.ps1): nur Definitionen bereitstellen
if ($DefinitionsOnly) { return }

# Seit 1.4.0 liegen die Tests nicht mehr in dieser Datei. Bewusst KEIN
# Rueckfall auf den normalen Programmstart.
if ($RunTests -or $RunScrollLockManualTest) {
    Write-Host 'Die Tests sind seit Version 1.4.0 nicht mehr Teil von ArbeitszeitTool.ps1.'
    Write-Host 'Sie liegen im Entwicklungs-Repository unter tests\ (nicht im ZIP-Download):'
    Write-Host '  powershell.exe -NoProfile -File .\tests\Run-Tests.ps1'
    Write-Host '  powershell.exe -NoProfile -File .\tests\Run-Tests.ps1 -ScrollLockManual'
    exit 2
}

Initialize-AppState
try {
    Start-Application
}
catch {
    Show-AppError -Message 'Unerwarteter Fehler - die Anwendung wird beendet.' -ErrorRecord $_
}
finally {
    Invoke-AppCleanup
}

#endregion
