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
 Tests:    powershell.exe -NoProfile -File .\ArbeitszeitTool.ps1 -RunTests
 Manuell:  powershell.exe -NoProfile -File .\ArbeitszeitTool.ps1 -RunScrollLockManualTest
           (optionaler, systemabhaengiger Scroll-Lock-Integrationstest mit
            ECHTEN Tastendruecken - laeuft nur nach ausdruecklicher Bestaetigung)

 Hinweis: Es wird keine ExecutionPolicy umgangen oder veraendert.
 Verhindert die Unternehmensrichtlinie die Skriptausfuehrung, ist der
 zulaessige Startweg mit der zustaendigen IT abzustimmen.
==================================================================
 AENDERUNGSJOURNAL
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
    [switch]$RunTests,
    [switch]$RunScrollLockManualTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Off

#region ===== Initialisierung: STA, Assemblies, Interop =====

# WPF benoetigt einen STA-Thread. powershell.exe startet ab v3 standardmaessig
# in STA; falls nicht (z. B. Sonderfaelle), Neustart mit -Sta.
# Bewusst ohne -ExecutionPolicy: geltende Richtlinien werden nicht umgangen.
if (-not $RunTests -and -not $RunScrollLockManualTest -and [System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-Sta', '-NoProfile', '-File', "`"$PSCommandPath`"")
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
$script:AppVersion = '1.0.0'

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

# Atomarer Speichervorgang des aktiven Tresors (Sitzungsschluessel):
#   1. Validierung im Speicher              2. Metadaten-Snapshot anlegen
#   3. Revision erhoehen, Zeitstempel       4. vault.pending.azt schreiben
#   5. pending erneut lesen, HMAC pruefen, entschluesseln, validieren
#   6. Pruefen, ob vault.azt seit dem letzten Laden extern veraendert wurde
#      (Cloud-Synchronisierung) - dann NICHT ueberschreiben
#   7. pending atomar als neue Hauptdatei uebernehmen (alter Stand beiseite)
#   8. neue Hauptdatei erneut oeffnen und pruefen
#   9. ERST DANACH Backups rotieren - ausschliesslich nachweislich
#      verwendbare Dateien; unbrauchbare Dateien wandern nach Recovery
# Bei jedem Fehler werden saemtliche zuvor veraenderten Metadaten
# (Revision, LastCheckpointAt, ModifiedAt, WorkData.LastSavedAt) aus dem
# Snapshot wiederhergestellt; die letzte gueltige Datei bleibt erhalten.
#  -NoTrackingCheckpoint: WorkData.LastSavedAt (fachlicher Tracking-
#   Checkpoint fuer die Homeoffice-Wiederherstellung) NICHT aktualisieren.
#  -Quiet: keine Fehlerdialoge (fuer automatische Wiederholungsversuche).
#  -NoBackupRotation: reine Zwischenspeicherung (30-Sekunden-Checkpoint,
#   Radiolautstaerke). Die Hauptdatei wird ohne Beiseitelegen des alten
#   Standes ersetzt, backup1/backup2 bleiben unveraendert. Backups rotieren
#   damit nur bei fachlichen Wechseln (Modus, Pause, Sperre, Arbeitsende,
#   Korrekturen, Schliessen) - in Cloud-Ordnern (OneDrive) entstehen so nicht
#   alle 30 s neue Backup-Versionen bzw. Papierkorbeintraege. Wurde der Stand
#   aus Pending/Backup geladen, wird trotzdem regulaer rotiert.
function Save-Vault {
    param(
        [switch]$NoTrackingCheckpoint,
        [switch]$Quiet,
        [switch]$NoBackupRotation
    )
    if ($null -eq $script:App -or $null -eq $script:App.Vault) { return $false }
    if (-not $script:VaultSession.Unlocked) { return $false }
    # Kontrollierte Blockade: Nach einem kritischen Dateiaustauschfehler oder
    # einem fehlenden Referenzhash der committeten Hauptdatei wird NICHT
    # ungeschuetzt weitergeschrieben (keine zuverlaessige externe
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
    $prevAside = $null
    # Commit-Punkt: Der Speichervorgang gilt als dauerhaft committed, sobald
    # die neue Hauptdatei uebernommen UND vollstaendig geprueft wurde. Ab dann
    # duerfen nachgelagerte Fehler (Backuprotation, Referenzdaten) weder false
    # liefern noch Metadaten zuruecksetzen noch einen fachlichen Rollback der
    # aufrufenden Aktion ausloesen.
    $commitCompleted = $false
    # Nur im kritischen Fallbackfehlerfall: Pending-Datei (neuer Stand) darf
    # dann NICHT entfernt werden - alle Dateien bleiben unangetastet.
    $preservePending = $false
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
        # 4. verschluesselte Pending-Datei schreiben
        Write-VaultToFile -Path $script:Paths.VaultPending -Vault $vault `
            -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey `
            -Salt $script:VaultSession.Salt -Iterations $script:VaultSession.Iterations
        # 5. Pending-Datei erneut lesen, HMAC pruefen, entschluesseln, validieren
        $verify = Read-VaultFromFile -Path $script:Paths.VaultPending `
            -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        if ([long]$verify['Revision'] -ne [long]$vault['Revision']) {
            throw (New-Object System.InvalidOperationException 'VAULT_INVALID')
        }
        # 6. Externe Veraenderungen der Hauptdatei erkennen (z. B. Cloud-
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
            $currentHash = Get-FileSha256Hex -Path $script:Paths.VaultFile
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
        if ($externalChange -ne '') {
            # Vorhandene Dateien nicht ueberschreiben; eigenen (verschluesselten)
            # Stand neutral in Recovery sichern; keine automatische Zusammenfuehrung.
            $conflictPath = $null
            try {
                if (-not (Test-Path -LiteralPath $script:Paths.Recovery)) {
                    New-Item -ItemType Directory -Path $script:Paths.Recovery -Force | Out-Null
                }
                $conflictPath = Join-Path $script:Paths.Recovery ('vault-{0}.azt' -f ([guid]::NewGuid().ToString()))
                Move-Item -LiteralPath $script:Paths.VaultPending -Destination $conflictPath -Force
            }
            catch { }
            & $restoreMeta
            Set-VaultSaveFailedState
            # Keine automatische Wiederholung: sie wuerde nur weitere
            # Konfliktkopien erzeugen - der Benutzer muss entscheiden.
            $script:App.Flags.SaveRetryCount = 3
            Write-AppLog -Level 'WARN' -Message ("Externe Änderung der Tresordatei erkannt ({0}) - Speichern abgebrochen, eigener Stand in Recovery gesichert." -f $externalChange)
            if (-not $Quiet) {
                Show-Warning -Message (("Die Tresordatei wurde außerhalb dieser Anwendung verändert ({0}), z. B. durch eine Cloud-Synchronisierung. " -f $externalChange) +
                    "Vorhandene Dateien wurden NICHT überschrieben. Der aktuelle lokale Stand wurde verschlüsselt im Ordner 'Recovery' gesichert:`r`n`r`n" +
                    [string]$conflictPath + "`r`n`r`nEs findet keine automatische Zusammenführung statt. Bitte die Anwendung neu starten und den gewünschten Stand wählen.")
            }
            return $false
        }
        # Hauptdatei ist unveraendert (oder existierte weder beim Laden noch jetzt).
        #  - Stand aus der Hauptdatei geladen: der alte Hauptstand wurde beim
        #    Entsperren bereits vollstaendig validiert -> rotationsfaehig.
        #  - Stand bewusst aus Pending/Backup geladen (Auswahl im
        #    Wiederherstellungsdialog): das Ersetzen der unveraenderten alten
        #    Hauptdatei ist ein EXPLIZIT erkannter Wiederherstellungsvorgang,
        #    kein gewoehnlicher Speichervorgang. Die alte Hauptdatei gelangt
        #    nur nach vollstaendiger Pruefung in die Backupkette.
        $mainKnownGood = ($mainExists -and $script:App.LoadedFrom -eq 'Haupt')
        $skipRotation = ($NoBackupRotation -and $mainKnownGood)
        if ($mainExists -and $script:App.LoadedFrom -ne 'Haupt') {
            Write-AppLog -Level 'WARN' -Message ("Wiederherstellungsvorgang: Der aus '{0}' geladene Stand ersetzt die unveränderte bisherige Hauptdatei." -f $script:App.LoadedFrom)
        }
        # 7. Neue Hauptdatei atomar uebernehmen, alten Stand beiseite legen
        if ($mainExists) {
            $prevAside = $script:Paths.VaultPrev
            # Eine bereits vorhandene vault.prev.azt wird NIEMALS unbesehen
            # ueberschrieben: gueltige Staende werden als 'vault-prev',
            # unbrauchbare als 'vault-unreadable' neutral nach Recovery
            # verschoben (keine Klartextdatei, GUID-Name).
            if (Test-Path -LiteralPath $prevAside) {
                try {
                    $prevLeftPrefix = 'vault-unreadable'
                    if (Test-VaultFileFullyUsable -Path $prevAside) { $prevLeftPrefix = 'vault-prev' }
                    Move-FileToRecovery -Path $prevAside -Prefix $prevLeftPrefix | Out-Null
                    Write-AppLog -Message 'Vorhandene vault.prev.azt vor dem Speichern neutral in Recovery gesichert.'
                }
                catch { }
            }
            $replaceOk = $false
            try {
                if ($script:TestMode -and $script:App.Flags.TestFailReplace) {
                    throw (New-Object System.IO.IOException 'TESTHOOK: File.Replace deaktiviert')
                }
                if ($skipRotation) {
                    # Ohne Sicherungsdatei: kein vault.prev.azt, keine
                    # Backuprotation (Schritt 9 entfaellt mangels prev).
                    [System.IO.File]::Replace($script:Paths.VaultPending, $script:Paths.VaultFile, [NullString]::Value)
                }
                else {
                    [System.IO.File]::Replace($script:Paths.VaultPending, $script:Paths.VaultFile, $prevAside)
                }
                $replaceOk = $true
            }
            catch { $replaceOk = $false }
            if (-not $replaceOk) {
                # Robuster Fallback, falls File.Replace nicht moeglich ist.
                # Der Fallback ist selbst wiederherstellbar: schlaegt der
                # zweite Schritt fehl, wird die bisherige Hauptdatei SOFORT
                # wieder hergestellt und vollstaendig validiert.
                Move-Item -LiteralPath $script:Paths.VaultFile -Destination $prevAside -Force
                $fallbackOk = $false
                try {
                    if ($script:TestMode -and $script:App.Flags.TestFailFallbackMove) {
                        throw (New-Object System.IO.IOException 'TESTHOOK: Fallback-Move deaktiviert')
                    }
                    Move-Item -LiteralPath $script:Paths.VaultPending -Destination $script:Paths.VaultFile -Force
                    $fallbackOk = $true
                }
                catch { $fallbackOk = $false }
                if (-not $fallbackOk) {
                    $restoredOk = $false
                    try {
                        if ($script:TestMode -and $script:App.Flags.TestFailFallbackRestore) {
                            throw (New-Object System.IO.IOException 'TESTHOOK: Fallback-Restore deaktiviert')
                        }
                        Move-Item -LiteralPath $prevAside -Destination $script:Paths.VaultFile -Force
                        Read-VaultFromFile -Path $script:Paths.VaultFile `
                            -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey | Out-Null
                        $restoredOk = $true
                    }
                    catch { $restoredOk = $false }
                    if ($restoredOk) {
                        try { $script:App.VaultFileHash = Get-FileSha256Hex -Path $script:Paths.VaultFile } catch { }
                        Write-AppLog -Level 'WARN' -Message 'Dateiaustausch fehlgeschlagen - die bisherige Hauptdatei wurde sofort wiederhergestellt und validiert.'
                        throw (New-Object System.InvalidOperationException 'VAULT_SWAP_FAILED')
                    }
                    # Kritischer Fall: auch die sofortige Wiederherstellung ist
                    # fehlgeschlagen. Ab hier KEINE weiteren Schreibversuche;
                    # saemtliche noch vorhandenen verschluesselten Dateien
                    # (einschliesslich der Pending-Datei mit dem neuen Stand
                    # und vault.prev.azt mit dem alten Stand) bleiben
                    # unangetastet - die Startreparatur stellt den Zustand
                    # beim naechsten Programmstart wieder her.
                    $preservePending = $true
                    $script:App.Flags.SaveBlockedReason = 'Die Hauptdatei des Tresors konnte nach einem fehlgeschlagenen Dateiaustausch nicht wiederhergestellt werden. Es werden keine weiteren Schreibversuche unternommen.'
                    $script:App.Flags.SaveRetryCount = 3
                    Write-AppLog -Level 'ERROR' -Message 'KRITISCH: Dateiaustausch UND sofortige Wiederherstellung der Hauptdatei fehlgeschlagen - weitere Speichervorgänge werden blockiert.'
                    Show-AppError -Message ('Der Speichervorgang ist fehlgeschlagen und die bisherige Tresordatei konnte nicht automatisch wiederhergestellt werden. ' +
                        'Es werden keine weiteren Schreibversuche unternommen; alle vorhandenen verschlüsselten Dateien (einschließlich des neuen Standes als Pending-Datei) bleiben unverändert erhalten. ' +
                        'Der Zustand wird als NICHT GESPEICHERT angezeigt. Bitte die Anwendung neu starten - beim nächsten Start wird der Dateizustand repariert bzw. der gewünschte Stand zur Auswahl angeboten.')
                    throw (New-Object System.InvalidOperationException 'VAULT_SWAP_CRITICAL')
                }
            }
        }
        else {
            Move-Item -LiteralPath $script:Paths.VaultPending -Destination $script:Paths.VaultFile -Force
        }
        # 8. Neue Hauptdatei erneut oeffnen und vollstaendig pruefen
        try {
            $verifyMain = Read-VaultFromFile -Path $script:Paths.VaultFile `
                -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
            if ([long]$verifyMain['Revision'] -ne [long]$vault['Revision']) {
                throw (New-Object System.InvalidOperationException 'VAULT_INVALID')
            }
        }
        catch {
            # Uebernahme rueckgaengig machen: alter Hauptstand kommt zurueck
            if ($prevAside -and (Test-Path -LiteralPath $prevAside)) {
                try {
                    if (Test-Path -LiteralPath $script:Paths.VaultFile) {
                        Remove-Item -LiteralPath $script:Paths.VaultFile -Force -ErrorAction SilentlyContinue
                    }
                    Move-Item -LiteralPath $prevAside -Destination $script:Paths.VaultFile -Force
                }
                catch { }
            }
            throw
        }
        # ----- COMMIT-PUNKT ERREICHT -----
        # Die neue Hauptdatei wurde uebernommen und vollstaendig geprueft
        # (Authentizitaet, Entschluesselung, JSON, Struktur, Revision).
        $commitCompleted = $true
        # Referenzdaten nach dem Commit (Best Effort - niemals Rollback):
        # Kann der Referenzhash der bereits gueltig gespeicherten Hauptdatei
        # nicht ermittelt werden, bleibt der Speichervorgang erfolgreich;
        # weitere Speichervorgaenge werden aber kontrolliert blockiert.
        $newMainHash = $null
        try {
            if ($script:TestMode -and $script:App.Flags.TestFailPostCommitHash) {
                throw (New-Object System.IO.IOException 'TESTHOOK: Referenzhash deaktiviert')
            }
            $newMainHash = Get-FileSha256Hex -Path $script:Paths.VaultFile
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
        # 9. Backuprotation NACH erfolgreicher Uebernahme und Pruefung.
        #    Rotationsentscheidungen beruhen IMMER auf der VOLLSTAENDIGEN
        #    Pruefung (Test-VaultFileFullyUsable): eine lediglich HMAC-gueltige,
        #    aber strukturell ungueltige Datei darf niemals ein anderes
        #    gueltiges Backup ueberschreiben. Unbrauchbare Dateien werden
        #    neutral nach Recovery verschoben. ($mainKnownGood ist zulaessig:
        #    der alte Hauptstand wurde beim Entsperren vollstaendig validiert
        #    und ist seither nachweislich unveraendert.)
        #    Die gesamte Rotation ist NACH dem Commit reine Best-Effort-
        #    Arbeit: ein Fehler hier macht den committeten Hauptspeicherstand
        #    NICHT rueckgaengig, Save-Vault liefert weiterhin true.
        try {
            if ($prevAside -and (Test-Path -LiteralPath $prevAside)) {
                $prevUsable = $mainKnownGood
                if (-not $prevUsable) { $prevUsable = Test-VaultFileFullyUsable -Path $prevAside }
                if ($prevUsable) {
                    if (Test-Path -LiteralPath $script:Paths.VaultBackup1) {
                        if (Test-VaultFileFullyUsable -Path $script:Paths.VaultBackup1) {
                            if ($script:TestMode -and $script:App.Flags.TestFailBackupCopy) {
                                throw (New-Object System.IO.IOException 'TESTHOOK: Backupkopie deaktiviert')
                            }
                            [System.IO.File]::Copy($script:Paths.VaultBackup1, $script:Paths.VaultBackup2, $true)
                        }
                        else {
                            # Unbrauchbares Backup1 darf Backup2 nicht ueberschreiben
                            try { Move-FileToRecovery -Path $script:Paths.VaultBackup1 -Prefix 'vault-unreadable' | Out-Null } catch { }
                        }
                    }
                    if ($script:TestMode -and $script:App.Flags.TestFailPrevToBackup1) {
                        throw (New-Object System.IO.IOException 'TESTHOOK: Prev-nach-Backup1 deaktiviert')
                    }
                    # Vorhandenes Backup1 per File.Replace ersetzen statt per
                    # Move-Item -Force: Letzteres LOESCHT das Ziel zuerst, was
                    # Cloud-Ordner (OneDrive) als Loeschung in den Papierkorb
                    # uebernehmen. File.Replace wird als neue Version erkannt.
                    if (Test-Path -LiteralPath $script:Paths.VaultBackup1) {
                        [System.IO.File]::Replace($prevAside, $script:Paths.VaultBackup1, [NullString]::Value)
                    }
                    else {
                        Move-Item -LiteralPath $prevAside -Destination $script:Paths.VaultBackup1
                    }
                }
                else {
                    # Eine beschaedigte alte Hauptdatei wird NICHT als Backup1 weiterkopiert
                    try { Move-FileToRecovery -Path $prevAside -Prefix 'vault-unreadable' | Out-Null } catch { }
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
        # Hauptdatei ist bereits gueltig uebernommen und vollstaendig geprueft.
        if ($commitCompleted) {
            Write-AppLog -Level 'WARN' -Message ('Nachgelagerter Fehler nach erfolgreich committetem Speichervorgang (Best Effort): ' + $_.Exception.Message)
            Clear-VaultSaveFailedState
            return $true
        }
        # Fehlgeschlagener Versuch VOR dem Commit: alle Metadaten aus dem
        # Snapshot zuruecksetzen, Pending-Datei (verschluesselt) entfernen,
        # bestehende Dateien unveraendert. Im kritischen Fallbackfehlerfall
        # (VAULT_SWAP_CRITICAL) bleibt auch die Pending-Datei unangetastet.
        & $restoreMeta
        if (-not $preservePending) {
            try {
                if (Test-Path -LiteralPath $script:Paths.VaultPending) {
                    Remove-Item -LiteralPath $script:Paths.VaultPending -Force -ErrorAction SilentlyContinue
                }
            }
            catch { }
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
    if ($defaults['CompactFields'] -isnot [System.Collections.IList] -or @($defaults['CompactFields']).Count -eq 0) {
        $defaults['CompactFields'] = @('Beginn', 'Netto', 'SollRestOderUeberstunden', 'MaxEnde')
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
        # -NoLog: Korrektureintrag nur im Tagesobjekt anlegen (er ist damit
        # Teil des Tages-Snapshots und wird bei einem Rollback vollstaendig
        # zurueckgenommen); den Erfolgslogeintrag schreibt der Aufrufer erst
        # nach erfolgreichem Speichern ueber Write-CorrectionLog.
        [switch]$NoLog
    )
    [void]$Day['Corrections'].Add([ordered]@{
            Timestamp   = ConvertTo-DateTimeString (Get-Date)
            Description = $Description
            OldValue    = $OldValue
            NewValue    = $NewValue
        })
    $Day['ModifiedAt'] = ConvertTo-DateTimeString (Get-Date)
    if (-not $NoLog) {
        Write-CorrectionLog -Day $Day -Description $Description -OldValue $OldValue -NewValue $NewValue
    }
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
function Test-DayEndTime {
    param(
        [Parameter(Mandatory)]$Day,
        [Parameter(Mandatory)][datetime]$End,
        [datetime]$Now = (Get-Date)
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
        [switch]$Quiet            # automatische Ablaeufe: kein Fehlerdialog beim Speichern
    )
    if (-not $SkipValidation) {
        $endError = Test-DayEndTime -Day $Day -End $End
        if ($endError -ne '') {
            Show-Warning -Message $endError
            return $false
        }
    }
    # Gesamte fachliche Aenderung im Speicher durchfuehren und genau EINMAL
    # speichern; bei einem Speicherfehler wird der Tag vollstaendig aus dem
    # Snapshot zurueckgerollt (kein ungewollter Zwischenstand im Tresor).
    $snapshot = Get-DaySnapshot -Day $Day
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
            'SollEnde' {
                if ($Comp.SollErreicht) { [void]$parts.Add('Soll-Ende: erreicht') }
                elseif ($Comp.SollEnde) {
                    $mark = ''
                    if ($Comp.EndePausiert) { $mark = '*' }
                    [void]$parts.Add('Soll-Ende: ' + (Format-Clock $Comp.SollEnde) + $mark)
                }
                else { [void]$parts.Add('Soll-Ende: --:--') }
            }
            'MaxEnde' {
                if ($Comp.MaxEnde) {
                    $mark = ''
                    if ($Comp.EndePausiert) { $mark = '*' }
                    [void]$parts.Add('Max-Ende: ' + (Format-Clock $Comp.MaxEnde) + $mark)
                }
                else { [void]$parts.Add('Max-Ende: --:--') }
            }
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
    foreach ($col in @('Modus', 'Beginn', 'Ende', 'Brutto', 'Pause', 'Netto', 'Laufend', 'Manuell', 'Korrigiert')) {
        [void]$dt.Columns.Add($col)
    }
    foreach ($row in (Get-SegmentDisplayRows -Day $Day -Comp $Comp -Now $Now)) {
        [void]$dt.Rows.Add($row.Modus, $row.Beginn, $row.Ende, $row.Brutto, $row.Pause, $row.Netto,
            $row.Laufend, $row.Manuell, $row.Korrigiert)
    }
    return ,$dt
}

# Tabelle der Pausen-/Sperrintervalle inkl. der (nicht bearbeitbaren) festen Betriebspause
function Get-PausesTable {
    param([Parameter(Mandatory)]$Day, $Comp)
    $dt = New-Object System.Data.DataTable
    foreach ($col in @('Art', 'Beginn', 'Ende', 'Dauer')) { [void]$dt.Columns.Add($col) }
    $now = Get-Date
    foreach ($iv in @($Day.ManualPauses)) {
        $s = ConvertFrom-DateTimeString $iv.Start
        $e = $now
        $endText = 'läuft'
        if ($iv.End) { $e = ConvertFrom-DateTimeString $iv.End; $endText = Format-Clock $e }
        [void]$dt.Rows.Add('Manuelle Pause', (Format-Clock $s), $endText, (Format-Duration ($e - $s)))
    }
    foreach ($iv in @($Day.LockIntervals)) {
        $s = ConvertFrom-DateTimeString $iv.Start
        $e = $now
        $endText = 'läuft'
        if ($iv.End) { $e = ConvertFrom-DateTimeString $iv.End; $endText = Format-Clock $e }
        [void]$dt.Rows.Add('Windows-Sperre', (Format-Clock $s), $endText, (Format-Duration ($e - $s)))
    }
    if ($Comp) {
        foreach ($win in @($Comp.PauseWindows)) {
            if ($null -eq $win) { continue }
            [void]$dt.Rows.Add('Feste Betriebspause', (Format-Clock $win.Start), (Format-Clock $win.End), (Format-Duration ($win.End - $win.Start)))
        }
    }
    return ,$dt
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
            $win.FindName('ExtPauses').ItemsSource = (Get-PausesTable -Day $Day -Comp $Comp).DefaultView
            $script:App.Ui.ExtendedSegTable = $segTable
            for ($i = 0; $i -lt $segTable.Rows.Count; $i++) {
                if ([string]$segTable.Rows[$i]['Laufend'] -eq 'ja') { $script:App.Ui.ExtendedRunningRow = $i }
            }
        }
        else {
            $win.FindName('ExtSegments').ItemsSource = $null
            $win.FindName('ExtPauses').ItemsSource = $null
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
        # Vollstaendige Abschluss- und Intervallvalidierung (keine stille Korrektur)
        $endError = Test-DayEndTime -Day $Day -End $end
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
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
            <Button x:Name="BtnOk" Content="Übernehmen" IsDefault="True"/>
            <Button x:Name="BtnCancel" Content="Abbrechen" IsCancel="True" Margin="0"/>
        </StackPanel>
    </StackPanel>
</Window>
'@

# Generischer Intervall-Editor.
# Liefert @{ Mode; Start=[datetime]; End=[datetime]/$null } oder $null bei Abbruch
function Show-IntervalEditDialog {
    param(
        [Parameter(Mandatory)][string]$Caption,
        [Parameter(Mandatory)][datetime]$BaseDate,
        [string]$Mode = '',
        [string]$StartText = '',
        [string]$EndText = '',
        [switch]$ShowMode,
        [switch]$AllowEmptyEnd
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
            $state.Result = @{ Mode = $selMode; Start = $start; End = $end }
            $win.DialogResult = $true
            $win.Close()
        })
    [void]$win.ShowDialog()
    return $state.Result
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
                                    <TextBlock Text="Aktivhaltung aktiv (Standard: ein)" TextWrapping="Wrap"/>
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
        Title="Tag bearbeiten" Width="860" Height="620" MinWidth="700" MinHeight="480"
        Background="#FF171C24" WindowStartupLocation="CenterScreen">
    <Window.Resources>
<!--THEME-->
    </Window.Resources>
    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Margin="0,0,0,8">
            <TextBlock x:Name="TxtHeader" FontWeight="Bold" FontSize="15"/>
            <TextBlock Text="Die feste 45-Minuten-Betriebspause wird automatisch berechnet und kann nicht bearbeitet werden. Jede Änderung wird protokolliert." TextWrapping="Wrap" Foreground="#FFAAB8C6"/>
        </StackPanel>
        <GroupBox Grid.Row="1" Header="Arbeitsabschnitte">
            <DockPanel>
                <StackPanel DockPanel.Dock="Right" Margin="8,0,0,0">
                    <Button x:Name="BtnSegNew" Content="Neu" MinWidth="90"/>
                    <Button x:Name="BtnSegEdit" Content="Bearbeiten" MinWidth="90" Margin="0,6,0,0"/>
                    <Button x:Name="BtnSegDelete" Content="Löschen" MinWidth="90" Margin="0,6,0,0"/>
                </StackPanel>
                <DataGrid x:Name="GridSegments" CanUserSortColumns="False"/>
            </DockPanel>
        </GroupBox>
        <GroupBox Grid.Row="2" Header="Manuelle Pausen">
            <DockPanel>
                <StackPanel DockPanel.Dock="Right" Margin="8,0,0,0">
                    <Button x:Name="BtnPauseNew" Content="Neu" MinWidth="90"/>
                    <Button x:Name="BtnPauseEdit" Content="Bearbeiten" MinWidth="90" Margin="0,6,0,0"/>
                    <Button x:Name="BtnPauseDelete" Content="Löschen" MinWidth="90" Margin="0,6,0,0"/>
                </StackPanel>
                <DataGrid x:Name="GridPauses" CanUserSortColumns="False"/>
            </DockPanel>
        </GroupBox>
        <GroupBox Grid.Row="3" Header="Sperrintervalle (Windows-Sperre)">
            <DockPanel>
                <StackPanel DockPanel.Dock="Right" Margin="8,0,0,0">
                    <Button x:Name="BtnLockNew" Content="Neu" MinWidth="90"/>
                    <Button x:Name="BtnLockEdit" Content="Bearbeiten" MinWidth="90" Margin="0,6,0,0"/>
                    <Button x:Name="BtnLockDelete" Content="Löschen" MinWidth="90" Margin="0,6,0,0"/>
                </StackPanel>
                <DataGrid x:Name="GridLocks" CanUserSortColumns="False"/>
            </DockPanel>
        </GroupBox>
        <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
            <TextBlock x:Name="TxtNetto" VerticalAlignment="Center" FontFamily="Consolas" Margin="0,0,16,0"/>
            <Button x:Name="BtnClose" Content="Schließen" IsCancel="True" Margin="0"/>
        </StackPanel>
    </Grid>
</Window>
'@

function Get-IntervalTable {
    param($Intervals)
    $dt = New-Object System.Data.DataTable
    foreach ($col in @('Beginn', 'Ende', 'Dauer')) { [void]$dt.Columns.Add($col) }
    $now = Get-Date
    foreach ($iv in @($Intervals)) {
        if ($null -eq $iv) { continue }
        $s = ConvertFrom-DateTimeString $iv.Start
        $e = $now
        $endText = 'läuft'
        if ($iv.End) { $e = ConvertFrom-DateTimeString $iv.End; $endText = Format-Clock $e }
        [void]$dt.Rows.Add((Format-Clock $s), $endText, (Format-Duration ($e - $s)))
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
        $win.FindName('GridSegments').ItemsSource = (Get-SegmentsTable -Day $Day).DefaultView
        $win.FindName('GridPauses').ItemsSource = (Get-IntervalTable -Intervals $Day.ManualPauses).DefaultView
        $win.FindName('GridLocks').ItemsSource = (Get-IntervalTable -Intervals $Day.LockIntervals).DefaultView
        $now = Get-Date
        $state.SegIds = @((Get-ParsedSegments -Day $Day -Now $now) | ForEach-Object { $_.Id })
        $state.PauseIds = @(@($Day.ManualPauses) | ForEach-Object { $_.Id })
        $state.LockIds = @(@($Day.LockIntervals) | ForEach-Object { $_.Id })
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

    # --- Arbeitsabschnitte ---
    $win.FindName('BtnSegNew').Add_Click({
            $result = Show-IntervalEditDialog -Caption 'Neuer Arbeitsabschnitt' -BaseDate $baseDate -ShowMode -Mode 'Homeoffice' `
                -StartText '08:00' -EndText '09:00' -AllowEmptyEnd:$isActive
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
            $result = Show-IntervalEditDialog -Caption 'Arbeitsabschnitt bearbeiten' -BaseDate $baseDate -ShowMode -Mode $seg.Mode `
                -StartText (Format-Clock (ConvertFrom-DateTimeString $seg.Start)) -EndText $endText -AllowEmptyEnd:$isActive
            if ($null -eq $result) { return }
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
            if (-not (& $applyTenHourGuard $snapshot)) { & $refresh; return }
            $corrNewText = ('{0} {1}-{2}' -f $result.Mode, (Format-Clock $result.Start), (Format-Clock $result.End))
            Add-Correction -Day $Day -Description 'Arbeitsabschnitt korrigiert' -OldValue $oldText -NewValue $corrNewText -NoLog
            if (-not (Save-WorkData)) {
                Restore-DayFromSnapshot -Day $Day -Snapshot $snapshot
                Write-AppLog -Level 'WARN' -Message 'Korrektur NICHT gespeichert - Änderung vollständig zurückgenommen.'
                & $refresh
                Invoke-MainRefresh -ForceTables
                return
            }
            Write-CorrectionLog -Day $Day -Description 'Arbeitsabschnitt korrigiert' -OldValue $oldText -NewValue $corrNewText
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
            $result = Show-IntervalEditDialog -Caption "Neues Intervall: $Label" -BaseDate $baseDate -StartText '12:00' -EndText '12:30' -AllowEmptyEnd:$isActive
            if ($null -eq $result) { return }
            if ($null -eq $result.End) {
                foreach ($iv in @($Day[$ListName])) {
                    if ($null -eq $iv.End) { Show-Warning -Message "Es ist bereits ein offenes Intervall ($Label) vorhanden."; return }
                }
            }
            $snapshot = Get-DaySnapshot -Day $Day
            $newIv = New-IntervalObject -Start $result.Start
            if ($null -ne $result.End) { $newIv['End'] = ConvertTo-DateTimeString $result.End }
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
                $result = Show-IntervalEditDialog -Caption "$Label bearbeiten" -BaseDate $baseDate `
                    -StartText (Format-Clock (ConvertFrom-DateTimeString $iv.Start)) -EndText $oldEndText -AllowEmptyEnd:$isActive
                if ($null -eq $result) { return }
                if ($null -eq $result.End) {
                    foreach ($other in @($Day[$ListName])) {
                        if ($null -eq $other.End -and $other.Id -ne $iv.Id) { Show-Warning -Message 'Es ist bereits ein anderes offenes Intervall vorhanden.'; return }
                    }
                }
                $snapshot = Get-DaySnapshot -Day $Day
                $iv['Start'] = ConvertTo-DateTimeString $result.Start
                if ($null -ne $result.End) { $iv['End'] = ConvertTo-DateTimeString $result.End } else { $iv['End'] = $null }
                if (-not (& $applyTenHourGuard $snapshot)) { & $refresh; return }
                $pendingCorr = @{ Description = "$Label korrigiert"; Old = $oldText; New = ('{0}-{1}' -f (Format-Clock $result.Start), (Format-Clock $result.End)) }
                Add-Correction -Day $Day -Description $pendingCorr.Description -OldValue $oldText -NewValue $pendingCorr.New -NoLog
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
    foreach ($col in @('Datum', 'Beginn', 'Ende', 'Netto', 'Betrieb', 'Homeoffice', 'Pausen', 'Sperrzeit', 'Sollabweichung', 'Status', 'Korrekturen')) {
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
            [string]@($day.Corrections).Count
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
        'Maximalzeit erreicht', 'Anzahl Korrekturen')
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add(($header -join ';'))
    $detailLines = New-Object System.Collections.ArrayList
    [void]$detailLines.Add((@('Datum', 'Modus', 'Beginn', 'Ende', 'Bruttozeit', 'Pausenzeit', 'Nettozeit', 'Manuell erfasst', 'Korrigiert') -join ';'))

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
            [string]@($day.Corrections).Count
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
                    $ja[[int][bool]$seg.Ref.Manual], $ja[[int][bool]$seg.Ref.Corrected]
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
        [void]$segs.Add(('{0}|{1}|{2}|{3}' -f [string]$seg['Mode'], [string]$seg['Start'], [string]$seg['End'], [bool]$seg['Running']))
    }
    $pauses = New-Object System.Collections.ArrayList
    foreach ($iv in @($Day['ManualPauses'])) {
        if ($null -eq $iv) { continue }
        [void]$pauses.Add(('{0}|{1}' -f [string]$iv['Start'], [string]$iv['End']))
    }
    $locks = New-Object System.Collections.ArrayList
    foreach ($iv in @($Day['LockIntervals'])) {
        if ($null -eq $iv) { continue }
        [void]$locks.Add(('{0}|{1}' -f [string]$iv['Start'], [string]$iv['End']))
    }
    $corrections = New-Object System.Collections.ArrayList
    foreach ($corr in @($Day['Corrections'])) {
        if ($null -eq $corr) { continue }
        [void]$corrections.Add(('{0}|{1}|{2}|{3}' -f [string]$corr['Timestamp'], [string]$corr['Description'], [string]$corr['OldValue'], [string]$corr['NewValue']))
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
    return ('Status {0} | {1} Abschnitt(e) | {2} Pause(n) | {3} Sperrintervall(e) | {4} Korrektur(en) | Netto {5}' -f `
            [string]$Day['Status'], $segCount, @($Day['ManualPauses']).Count, @($Day['LockIntervals']).Count, @($Day['Corrections']).Count, $netto)
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
        <TextBlock Text="Alle Tresordateien (einschließlich Backups) werden mit dem neuen Passwort neu verschlüsselt. Der Vorgang ist abgesichert: Schlägt ein Schritt fehl, bleibt der bisherige Tresor mit dem bisherigen Passwort vollständig erhalten." TextWrapping="Wrap" Foreground="#FFAAB8C6" Margin="0,8,0,0"/>
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
            }
            catch { }
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
        foreach ($d in @($done)) {
            try { Remove-Item -LiteralPath $d.Old -Force -ErrorAction SilentlyContinue } catch { }
        }
        try { Remove-Item -LiteralPath $script:Paths.VaultTxn -Force -ErrorAction SilentlyContinue } catch { }
        return ''
    }
    catch {
        $reverse = @($done)
        [array]::Reverse($reverse)
        foreach ($d in $reverse) {
            try {
                if ($d.Applied -and (Test-Path -LiteralPath $d.Orig)) {
                    Move-Item -LiteralPath $d.Orig -Destination ($d.Orig + '.new') -Force
                }
                if (Test-Path -LiteralPath $d.Old) {
                    Move-Item -LiteralPath $d.Old -Destination $d.Orig -Force
                }
            }
            catch { }
        }
        foreach ($p in @($prepared)) {
            try { Remove-Item -LiteralPath $p.New -Force -ErrorAction SilentlyContinue } catch { }
        }
        try { Remove-Item -LiteralPath $script:Paths.VaultTxn -Force -ErrorAction SilentlyContinue } catch { }
        return ('Die Übernahme der neu verschlüsselten Dateien ist fehlgeschlagen; der bisherige Zustand wurde wiederhergestellt. Details: ' + $_.Exception.Message)
    }
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
        # Ergebnis des ABSCHLIESSENDEN Speichervorgangs pruefen. Die
        # Neuverschluesselung selbst ist bereits transaktional abgeschlossen
        # und bleibt in jedem Fall gueltig - sie wird hier nicht zurueckgesetzt.
        if (Save-Vault) {
            Show-Info -Message 'Das Verschlüsselungspasswort wurde erfolgreich geändert.' -Title 'Passwort ändern'
        }
        else {
            Show-Warning -Message ('Das Passwort wurde erfolgreich geändert und alle Tresordateien wurden bereits neu verschlüsselt. ' +
                'Der anschließende reguläre Tresorspeichervorgang ist jedoch FEHLGESCHLAGEN - der Zustand wird als ' +
                'NICHT GESPEICHERT angezeigt und automatisch erneut versucht.') -Title 'Passwort ändern'
        }
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
        Ui                  = @{ Compact = $null; Extended = $null; ExtendedStamp = ''; ExtendedSegTable = $null; ExtendedRunningRow = -1; Tray = $null; TrayItems = @{}; MenuItems = @{}; Handle = [IntPtr]::Zero; HideInProgress = $false }
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
        # Dateiaustauschfehler). BackupWarningShown: einmalige neutrale
        # Benutzerinfo bei fehlgeschlagener Best-Effort-Backuprotation.
        # TestFail*: reine Testhooks fuer -RunTests (nur bei $script:TestMode
        # wirksam, im normalen Programmbetrieb vollstaendig inaktiv).
        Flags               = @{ Warn945Logged = $false; MaxHandled = $false; SaveInProgress = $false; UnsavedChanges = $false; SaveRetryCount = 0; ActiveDayDecisionCompleted = $false; SimulatedShutdownRequested = $false; SimulatedShutdownRequestCount = 0; SimulatedShutdownStartFails = $false; RolloverWarnLogged = $false; RolloverNextRetryAt = $null; SaveBlockedReason = ''; SaveBlockedLogged = $false; BackupWarningShown = $false; TestFailReplace = $false; TestFailFallbackMove = $false; TestFailFallbackRestore = $false; TestFailBackupCopy = $false; TestFailPrevToBackup1 = $false; TestFailPostCommitHash = $false }
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
        #  - nur wenn der Checkpoint fachlich gebraucht wird: laufender
        #    Homeoffice-Abschnitt oder offenes Sperr-/Pausenintervall. Im
        #    reinen Betriebsmodus laeuft die Zeit anhand der Zeitstempel
        #    weiter; jede fachliche Aenderung speichert ohnehin sofort.
        #  - ohne Backuprotation: Backups entstehen nur bei fachlichen
        #    Wechseln, nicht bei jedem Checkpoint (OneDrive-Datenmenge)
        if ($day -and $day.Status -eq 'Aktiv' -and ($script:App.Counters.Tick % 30) -eq 0 -and
            -not $script:App.Flags.SaveInProgress -and
            ($script:App.Counters.Tick - $script:App.Counters.LastSaveTick) -ge 30) {
            $comp = Get-DayComputation -Day $day -Now (Get-Date)
            $checkpointNeeded = ($comp.RunningMode -eq 'Homeoffice' -or $null -ne $comp.OpenLock -or $null -ne $comp.OpenPause)
            if ($checkpointNeeded) {
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
    $completed = Complete-WorkDay -Day $day -End $result.End -Reason 'Manuell'
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
        -BaseDate $baseDate -ShowMode -Mode 'Homeoffice' -StartText '08:00' -EndText '09:30'
    if ($null -eq $result) { return }
    if (Test-SegmentOverlap -Day $day -Start $result.Start -End $result.End) {
        Show-Warning -Message 'Der Abschnitt überschneidet sich mit einem vorhandenen Arbeitsabschnitt.'
        return
    }
    $snapshot = Get-DaySnapshot -Day $day
    $seg = New-SegmentObject -Mode $result.Mode -Start $result.Start -End $result.End -Manual $true
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
        $items['KeepAlive'].IsChecked = [bool]$script:App.Settings['KeepAliveEnabled']
        $items['EndDay'].IsEnabled = $hasActive
    }

    $trayItems = $script:App.Ui.TrayItems
    if ($trayItems.Count -gt 0) {
        $trayItems['StartDay'].Enabled = (-not $hasActive)
        $trayItems['SwitchMode'].Enabled = ($hasActive -and $comp -and $null -ne $comp.RunningMode -and -not $comp.MaxReached)
        $trayItems['Pause'].Text = $pauseHeader
        $trayItems['Pause'].Enabled = $pauseEnabled
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
}

#endregion


#region ===== Interne Tests (-RunTests) =====

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
    $slSource = [System.IO.File]::ReadAllText($PSCommandPath)
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
        & $assert 'Test 25b: vault.azt vorhanden, keine Pending-Datei zurueckgeblieben' 'True False' ("$(Test-Path -LiteralPath $script:Paths.VaultFile) $(Test-Path -LiteralPath $script:Paths.VaultPending)")
        & $assert 'Test 25c: Backup1 nach zweitem Speichern vorhanden' 'True' ([string](Test-Path -LiteralPath $script:Paths.VaultBackup1))
        & $assert 'Test 25d: Revision monoton steigend' '2' ([string]$script:App.Vault['Revision'])
        $b1HashBefore = Get-FileSha256Hex -Path $script:Paths.VaultBackup1
        $b2ExistsBefore = Test-Path -LiteralPath $script:Paths.VaultBackup2
        $savedNoRot = Save-Vault -NoBackupRotation
        $b1HashAfter = Get-FileSha256Hex -Path $script:Paths.VaultBackup1
        & $assert 'Test 25f: Checkpoint ohne Backuprotation - gespeichert, Backup1 unveraendert, kein Backup2, kein prev' "True|True|$b2ExistsBefore|False|3" ("$savedNoRot|$($b1HashBefore -eq $b1HashAfter)|$(Test-Path -LiteralPath $script:Paths.VaultBackup2)|$(Test-Path -LiteralPath $script:Paths.VaultPrev)|$(([long](Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey)['Revision']))")
        $savedRot = Save-Vault
        & $assert 'Test 25g: fachliches Speichern rotiert wieder (Backup1 = Stand des Checkpoints)' 'True|False|True' ("$savedRot|$($b1HashAfter -eq (Get-FileSha256Hex -Path $script:Paths.VaultBackup1))|$(Test-Path -LiteralPath $script:Paths.VaultBackup2)")
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

        # --- Test 30: Fehlgeschlagene Passwortaenderung erhaelt den alten Tresor ---
        $failError = Invoke-VaultReencryption -OldPasswordBytes $wrongPwdBytes `
            -NewAesKey $keys.Aes -NewHmacKey $keys.Hmac -NewSalt $salt -NewIterations $iter
        $mainIntact = $true
        try { Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $newKeys.Aes -HmacKey $newKeys.Hmac | Out-Null }
        catch { $mainIntact = $false }
        & $assert 'Test 30a: falsches aktuelles Passwort wird neutral abgelehnt' 'True' ([string]($failError -eq $script:VaultNeutralError))
        & $assert 'Test 30b: bisheriger Tresor bleibt vollstaendig erhalten' 'True' ([string]$mainIntact)
        # Fuer die Folgetests zurueck auf das Testpasswort wechseln
        $backError = Invoke-VaultReencryption -OldPasswordBytes $newPwdBytes `
            -NewAesKey $keys.Aes -NewHmacKey $keys.Hmac -NewSalt $salt -NewIterations $iter
        & $assert 'Test 30c: Ruecknahme der Passwortaenderung erfolgreich' '' $backError
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
        $bomBytes = Get-Content -LiteralPath $PSCommandPath -Encoding Byte -TotalCount 3
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
        & $assert 'Test 63c: eigener Stand als neutrale Konfliktdatei (GUID) in Recovery gesichert' 'True' ([string]($recCountAfter -gt $recCountBefore))
        Clear-VaultSaveFailedState
        $script:App.VaultFileHash = Get-FileSha256Hex -Path $script:Paths.VaultFile

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
            $script:App.Ui.Extended = $null
            $privWin.Close()
        }
        catch {
            $script:App.Ui.Extended = $null
            Write-Host ('[SKIP] Test 83 (Sichtschutz-UI): in dieser Umgebung nicht ausfuehrbar: ' + $_.Exception.Message) -ForegroundColor Yellow
        }

        # --- Test 84: Ausblenden in den Infobereich beendet die Anwendung nicht ---
        $saSource = [System.IO.File]::ReadAllText($PSCommandPath)
        # LastIndexOf: die ECHTE Funktion liegt nach dem Testbereich - die
        # Suchbegriffe kommen sonst zuerst im Testquelltext selbst vor
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
        $src101 = [System.IO.File]::ReadAllText($PSCommandPath)
        $loneLf101 = [regex]::IsMatch($src101, '(?<!\r)\n')
        & $assert 'Test 101: ArbeitszeitTool.ps1 verwendet durchgaengig CRLF-Zeilenenden' 'False' ([string]$loneLf101)

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
        # Fehler beim Verschieben von prev nach Backup1 (ebenfalls nach dem
        # Commit); die vom vorigen Test liegengebliebene vault.prev.azt wird
        # dabei zuerst neutral in Recovery gesichert (nicht ueberschrieben).
        $prevRec108 = @(Get-ChildItem -LiteralPath $script:Paths.Recovery -Filter 'vault-prev-*.azt' -File -ErrorAction SilentlyContinue).Count
        $script:App.Flags.TestFailPrevToBackup1 = $true
        $save108e = Save-Vault
        $script:App.Flags.TestFailPrevToBackup1 = $false
        $prevRec108b = @(Get-ChildItem -LiteralPath $script:Paths.Recovery -Filter 'vault-prev-*.azt' -File -ErrorAction SilentlyContinue).Count
        & $assert 'Test 108e: Prev->Backup1-Fehler nach dem Commit - true, Hauptdatei vollstaendig gueltig' 'True|True' ("$save108e|$(Test-VaultFileFullyUsable -Path $script:Paths.VaultFile)")
        & $assert 'Test 108f: vorhandene vault.prev.azt wurde neutral in Recovery gesichert (nicht ueberschrieben)' 'True' ([string]($prevRec108b -gt $prevRec108))
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

        # --- Tests 109: abgesicherter Dateiaustausch-Fallback ---
        $rev109 = [long]$script:App.Vault['Revision']
        $script:App.Flags.TestFailReplace = $true
        $save109a = Save-Vault
        $script:App.Flags.TestFailReplace = $false
        $main109 = Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        & $assert 'Test 109a: File.Replace-Fehler mit erfolgreichem Fallback erzeugt gueltige neue Hauptdatei' "True|$($rev109 + 1)" ("$save109a|$($main109['Revision'])")
        # Fallback: zweiter Move schlaegt fehl -> alte Hauptdatei SOFORT zurueck
        $revBefore109 = [long]$script:App.Vault['Revision']
        $script:App.Flags.TestFailReplace = $true
        $script:App.Flags.TestFailFallbackMove = $true
        $save109b = Save-Vault -Quiet
        $script:App.Flags.TestFailReplace = $false
        $script:App.Flags.TestFailFallbackMove = $false
        $main109b = Read-VaultFromFile -Path $script:Paths.VaultFile -AesKey $script:VaultSession.AesKey -HmacKey $script:VaultSession.HmacKey
        & $assert 'Test 109b: Fehler beim zweiten Move stellt die alte Hauptdatei sofort wieder her' "False|$revBefore109|$revBefore109" ("$save109b|$($main109b['Revision'])|$($script:App.Vault['Revision'])")
        & $assert 'Test 109c: kein Pending-Rest, keine prev-Datei, Zustand NICHT GESPEICHERT' 'False|False|True' ("$(Test-Path -LiteralPath $script:Paths.VaultPending)|$(Test-Path -LiteralPath $script:Paths.VaultPrev)|$($script:App.Flags.UnsavedChanges)")
        Clear-VaultSaveFailedState
        # Kritischer Fallbackfehler: auch die sofortige Wiederherstellung
        # schlaegt fehl -> keine weiteren Schreibversuche, alles unangetastet
        $revBefore109d = [long]$script:App.Vault['Revision']
        $script:App.Flags.TestFailReplace = $true
        $script:App.Flags.TestFailFallbackMove = $true
        $script:App.Flags.TestFailFallbackRestore = $true
        $save109d = Save-Vault -Quiet
        $script:App.Flags.TestFailReplace = $false
        $script:App.Flags.TestFailFallbackMove = $false
        $script:App.Flags.TestFailFallbackRestore = $false
        & $assert 'Test 109d: kritischer Fallbackfehler - false, Blockade gesetzt, Pending (neuer Stand) bleibt erhalten' 'False|True|True' ("$save109d|$([string]$script:App.Flags.SaveBlockedReason -ne '')|$(Test-Path -LiteralPath $script:Paths.VaultPending)")
        & $assert 'Test 109e: alter Stand liegt unangetastet als vault.prev.azt fuer die Startreparatur bereit' 'False|True' ("$(Test-Path -LiteralPath $script:Paths.VaultFile)|$(Test-Path -LiteralPath $script:Paths.VaultPrev)")
        Repair-VaultTransactionState | Out-Null
        & $assert 'Test 109f: Startreparatur stellt die Hauptdatei aus vault.prev.azt wieder her' 'True|True' ("$(Test-Path -LiteralPath $script:Paths.VaultFile)|$(Test-VaultFileFullyUsable -Path $script:Paths.VaultFile)")
        $script:App.Flags.SaveBlockedReason = ''
        $script:App.Flags.SaveBlockedLogged = $false
        Clear-VaultSaveFailedState
        $save109g = Save-Vault
        & $assert 'Test 109g: nach Reparatur und Aufhebung der Blockade speichert der Tresor wieder' "True|$($revBefore109d + 1)" ("$save109g|$($script:App.Vault['Revision'])")

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

        Clear-VaultKeys -Keys $keys
        [ArbeitszeitTool.VaultCrypto]::ClearBytes($testPwdBytes)
        [ArbeitszeitTool.VaultCrypto]::ClearBytes($wrongPwdBytes)
    }
    finally {
        [ArbeitszeitTool.NativeInput]::TestFailMode = 0
        Clear-VaultSessionKeys
        $script:Paths = $origPaths
        Initialize-AppState
        foreach ($dir in @($testRoot, $testRoot2, $testRoot3, $testRoot4)) {
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

function Start-Application {
    Initialize-Folders

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
    Complete-VaultTransactionCleanup

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
                if ($endResult) { Complete-WorkDay -Day $active -End $endResult.End -Reason 'Manuell' | Out-Null }
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

if ($RunTests) {
    # Tests arbeiten ausschliesslich in temporaeren Testordnern und veraendern
    # keine echten Benutzerdaten (siehe Invoke-InternalTests).
    Initialize-AppState
    $exitCode = Invoke-InternalTests
    exit $exitCode
}

if ($RunScrollLockManualTest) {
    # Optionaler manueller Integrationstest mit echten Tastendruecken -
    # laeuft nur nach ausdruecklicher Bestaetigung (siehe Funktion).
    Initialize-AppState
    $script:App.Settings = Get-DefaultSettings
    $exitCode = Invoke-ScrollLockManualTest
    exit $exitCode
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