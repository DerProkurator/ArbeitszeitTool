# ArbeitszeitTool

Lokale Arbeitszeit-Erfassung für Windows 10/11 als portables PowerShell-Skript mit WPF-Oberfläche.
Keine Installation, keine externen Module, keine Internetverbindung, keine Telemetrie, keine Adminrechte.

**Alle gespeicherten Daten sind verschlüsselt.** Arbeitstage, Arbeitsabschnitte, Pausen- und
Sperrzeiten, Korrekturen, Soll-/Überstundenwerte, Einstellungen (inkl. Regelarbeitszeit),
Anwendungsprotokolle, Backups und Wiederherstellungsdaten liegen ausschließlich in einem
verschlüsselten Datentresor. Die einzige erlaubte unverschlüsselte Ausnahme sind bewusst
erstellte CSV-Exporte (nach ausdrücklicher Warnung und Bestätigung).

## Voraussetzungen

- Windows 10 oder Windows 11
- Windows PowerShell 5.1 (auf beiden Systemen vorinstalliert)
- .NET Framework 4.7.2 oder neuer (in Windows 10/11 enthalten) — wird beim Start geprüft;
  fehlt die benötigte SHA256-Funktion, startet die Anwendung mit einer verständlichen
  Fehlermeldung **nicht** und verändert keine Dateien (kein stiller Rückfall auf SHA1)
- Keine weiteren Komponenten erforderlich

## Start der Anwendung

Im Ordner der Anwendung (Rechtsklick → „In Terminal öffnen" oder über eine Verknüpfung):

```
powershell.exe -Sta -NoProfile -File .\ArbeitszeitTool.ps1
```

Ohne sichtbares Konsolenfenster (blitzt beim Start kurz auf):

```
powershell.exe -WindowStyle Hidden -Sta -NoProfile -File .\ArbeitszeitTool.ps1
```

Testmodus (ohne Oberfläche, führt die internen Testfälle in temporären Testordnern aus):

```
powershell.exe -NoProfile -File .\ArbeitszeitTool.ps1 -RunTests
```

**Hinweis zur Ausführungsrichtlinie:** Die Anwendung verwendet **keinen**
`-ExecutionPolicy Bypass` und verändert die Ausführungsrichtlinie nicht. Verhindert die
geltende Unternehmensrichtlinie die Skriptausführung, wird diese Vorgabe nicht umgangen —
bitte den zulässigen Startweg mit der zuständigen IT abstimmen (z. B. signierte Skripte
oder eine für den Benutzer freigegebene Richtlinie).

## Aufbau des Ordners

```
ArbeitszeitTool\
    ArbeitszeitTool.ps1        Hauptanwendung (alles in einer Datei, UTF-8 mit BOM)
    README.md                  diese Datei (UTF-8 mit BOM)
    Data\
        vault.azt              verschlüsselter Datentresor (Arbeitszeiten, Einstellungen, Protokolle)
        vault.backup1.azt      verschlüsseltes Backup (vorletzter gültiger Stand)
        vault.backup2.azt      verschlüsseltes Backup (vorvorletzter gültiger Stand)
        vault.pending.azt      nur kurzzeitig während eines Speichervorgangs (ebenfalls verschlüsselt)
        vault.prev.azt         nur kurzzeitig: beiseitegelegter alter Hauptstand während der Übernahme
        vault.txn              nur kurzzeitig: neutraler Transaktionsstatus einer Passwortänderung
                               (enthält keine Arbeitszeitdaten)
    Recovery\
        vault-unreadable-<GUID>.azt   archivierte, weiterhin verschlüsselte unbrauchbare Tresordateien
        vault-<GUID>.azt              verschlüsselte Konfliktkopien (z. B. nach externer Dateiänderung)
        legacy-<GUID>.azt             verschlüsselt archivierte, nicht übernommene Klartext-Altdateien
        import-day-<GUID>.azt         verschlüsselt archivierte Tagesvarianten aus Importkonflikten
    Exports\                   CSV-Exporte (unverschlüsselt, nur auf ausdrücklichen Wunsch)
```

Alle Ordner werden bei Bedarf automatisch angelegt. Der Ordner ist portabel und kann
komplett verschoben/kopiert werden. Die Dateinamen sind bewusst **stabil und neutral**
(keine Datums-/Uhrzeitangaben), Wiederherstellungsdateien verwenden GUIDs.

## Verschlüsselung (Datentresor)

### Verfahren und Parameter

| Baustein | Verfahren |
|---|---|
| Passwortableitung (KDF) | PBKDF2-HMAC-SHA256, 600.000 Iterationen |
| Salt | 32 kryptografisch zufällige Bytes (Mindestanforderung 16) |
| Schlüsselmaterial | 64 Byte: die ersten 32 Byte sind der AES-Schlüssel, die zweiten 32 Byte der HMAC-Schlüssel (zwei getrennte Schlüssel) |
| Verschlüsselung | AES-256-CBC mit PKCS#7-Padding |
| Initialisierungsvektor | 16 neue kryptografisch zufällige Bytes **pro Verschlüsselungsvorgang** |
| Integritätsschutz | HMAC-SHA256 über Formatkennung, Formatversion, KDF-Verfahren, Iterationszahl, Salt, IV und Ciphertext (Encrypt-then-MAC) |
| Zufall | ausschließlich `RandomNumberGenerator` (niemals `System.Random`) |

Der HMAC wird **immer vor** einem Entschlüsselungsversuch mit einem zeitkonstanten
Bytevergleich geprüft (eigene Implementierung, da `CryptographicOperations.FixedTimeEquals`
im .NET Framework nicht verfügbar ist). Es wird niemals zuerst entschlüsselt und danach
die Integrität geprüft.

### Containerformat

`vault.azt` ist ein JSON-Container, der ausschließlich kryptografische Metadaten und
Base64-kodierte verschlüsselte Daten enthält — keine Arbeitszeitwerte, keine
Klartext-Zeitstempel:

```
Magic       "AZTVAULT"           eindeutige Formatkennung
Version     1                    Container-Version (versionierbar für spätere Parameter-Anhebungen)
Kdf         "PBKDF2-HMAC-SHA256"
Iterations  600000
Salt        Base64
IV          Base64
Ciphertext  Base64
Hmac        Base64
```

Der entschlüsselte Inhalt (JSON mit `SchemaVersion`, `Revision`, `SessionId`,
`CleanShutdown`, `LastCheckpointAt`, `WorkData`, `Settings`, `Logs`, `LogArchives`,
`ModifiedAt`) existiert **ausschließlich im Arbeitsspeicher** und wird niemals als
Klartextdatei geschrieben — auch nicht temporär.

**Hinweis:** Algorithmus, Containerformat, Salt und IV müssen nicht geheim sein.
Die Sicherheit beruht allein auf dem Passwort.

## Passwort

- Das Passwort wird **bei jedem Programmstart** abgefragt und **nirgends gespeichert** —
  nicht im Skript, nicht in Einstellungen, nicht in der Registry, nicht in Umgebungs-
  variablen, nicht im Protokoll, nicht per DPAPI.
- Mindestlänge 12 Zeichen (empfohlen: mindestens 16 zufällige Zeichen), Maximallänge 256.
  Leerzeichen, Sonderzeichen und Unicode sind erlaubt; das Passwort wird niemals
  getrimmt oder unbemerkt verändert. Es gibt keine erzwungenen Zeichenklassen-Regeln.
- Beim ersten Start (bzw. bei der Migration) wird das Passwort zweimal abgefragt und
  verglichen, erst danach wird der Tresor erstellt.
- Nach erfolgreicher Entschlüsselung läuft die Anwendung ohne erneute Passwortabfrage
  weiter; die 30-Sekunden-Checkpoints verwenden die abgeleiteten Sitzungsschlüssel
  (PBKDF2 wird dafür nicht erneut berechnet).
- Nach der Schlüsselableitung werden Klartextreferenzen entfernt und die verwendeten
  Byte-/Zeichenpuffer überschrieben; beim Programmende und beim Passwortwechsel werden
  die Schlüsselfelder mit `Array.Clear` überschrieben. **Ehrlicher Hinweis:** In
  verwaltetem .NET-Speicher ist kein absolut garantiertes Löschen sämtlicher
  zwischenzeitlicher Stringkopien möglich (z. B. interne Kopien der WPF-PasswordBox).

### Falsches Passwort

Bei falschem Passwort **oder** beschädigtem Tresor erscheint immer dieselbe neutrale
Meldung: „Das Passwort ist falsch oder der Datentresor ist beschädigt." Es ist von außen
nicht unterscheidbar, ob das Passwort falsch, der HMAC ungültig, der Ciphertext verändert,
das Padding ungültig oder die innere Struktur beschädigt ist. Fehlversuche werden nicht
unverschlüsselt protokolliert; vorhandene Daten werden durch Fehlversuche nicht verändert.
Es gibt keine Sperre nach einer bestimmten Anzahl von Versuchen.

### Passwort vergessen

Es gibt **kein Masterpasswort, keine Hintertür, keine Wiederherstellungsfrage und keinen
Recovery-Key**. Ohne das korrekte Passwort sind die verschlüsselten Daten nicht
wiederherstellbar. Im Entsperrdialog kann nach zwei ausdrücklichen Bestätigungen ein
**neuer leerer Datentresor** angelegt werden; der bisherige Tresor wird dabei nicht
gelöscht, sondern verschlüsselt unter `Recovery\vault-unreadable-<GUID>.azt` archiviert
und kann mit einem wiedergefundenen Passwort später erneut geöffnet werden.

### Passwort ändern

Einstellungen → „Verschlüsselungspasswort ändern...": Das aktuelle Passwort wird erneut
abgefragt und per Entschlüsselung validiert, das neue Passwort zweimal eingegeben. Der
Vorgang ist ein nachvollziehbarer mehrstufiger Ablauf:

1. Alle neuen Dateien werden vollständig in einem separaten Transaktionsbereich
   (`*.new`-Dateien) erstellt und jede einzelne mit dem neuen Passwort erneut geöffnet
   und validiert; der alte Haupttresor bleibt dabei unverändert.
2. Ein neutraler Transaktionsstatus (`vault.txn`, ohne Arbeitszeitdaten) markiert die
   Übernahmephase.
3. Die Backups werden zuerst ausgetauscht, die **Hauptdatei zuletzt**. Die `*.old`-Dateien
   (vollständiger alter Stand) bleiben erhalten, bis die neue Hauptdatei abschließend
   erneut validiert wurde — erst dann werden sie entfernt.

Wird der Vorgang hart unterbrochen (Absturz, Stromausfall), erkennt der nächste
Programmstart die Zwischenzustände: fehlende Zieldateien werden aus `*.old`- bzw.
`*.new`-Dateien wiederhergestellt, und nach dem Entsperren werden verbliebene Reste
kontrolliert übernommen oder verschlüsselt in den `Recovery`-Ordner archiviert — es
verbleibt kein gemischter, dauerhaft unklarer Dateisatz, und es wird nichts gelöscht,
bevor die aktuelle Hauptdatei validiert wurde. Schlägt ein Schritt fehl, bleibt der
bisherige Tresor mit dem bisherigen Passwort vollständig erhalten.

## Migration vorhandener Klartextdaten

Beim ersten Start der neuen Version erkennt die Anwendung vorhandene Klartextdateien der
Vorversion (`worktime.json`, `worktime.backup.json`, `settings.json`, `application.log`,
`worktime.corrupt.*.json`) automatisch:

1. Information über die bevorstehende Migration
2. neues Passwort zweimal abfragen
3. `worktime.json` lesen und vollständig validieren; ist sie nicht vorhanden, leer oder
   unbrauchbar, wird **`worktime.backup.json` als alternative Datenquelle** gelesen und
   vollständig validiert — die tatsächlich verwendete Quelle wird festgehalten
4. Daten im Arbeitsspeicher zusammenführen und verschlüsselt über eine temporäre
   **verschlüsselte** Pending-Datei schreiben, erneut entschlüsseln und prüfen
5. den neuen Tresor erneut lesen und die **Datenzahlen** (Tage, Abschnitte, Pausen,
   Sperrintervalle, Korrekturen) mit der Klartextquelle vergleichen; danach
   verschlüsseltes Backup erzeugen und prüfen
6. **erst nach erfolgreicher Verifikation** werden ausschließlich die **tatsächlich
   übernommenen** Klartextquellen überschrieben und gelöscht

Nicht übernommene Altdateien (z. B. `worktime.backup.json` bei intakter Hauptdatei oder
`worktime.corrupt.*.json`) werden **niemals einfach gelöscht**: Sie werden vollständig
verschlüsselt in den `Recovery`-Ordner archiviert (`legacy-<GUID>.azt`, Archiv wird vor
dem Entfernen des Originals verifiziert) oder bleiben unverändert liegen.

Es entsteht während der Migration niemals eine unverschlüsselte Zwischendatei. Schlägt
ein Schritt fehl, bleiben die Originaldateien unverändert erhalten.

Sind verschlüsselte **und** unverschlüsselte Daten gleichzeitig vorhanden, wird nichts
automatisch überschrieben oder zusammengeführt; die Anwendung bietet die Auswahl:
verschlüsselten Tresor verwenden / Klartextdaten kontrolliert importieren / abbrechen.

**Import in einen bestehenden Tresor:** Tage, deren Datum bereits im Tresor existiert,
werden vollständig inhaltlich verglichen (Abschnitte, Modi, Beginn/Ende, Pausen,
Sperrzeiten, Korrekturen, Nettozeiten, Abschlussstatus). Bei identischem Inhalt wird der
Tag nicht doppelt importiert. Bei Unterschieden gibt es **kein stilles Überspringen** —
der Benutzer wählt pro Konflikt: vorhandenen Tresortag behalten / importierten Tag
übernehmen (bisheriger Tag wird verschlüsselt archiviert) / beide Varianten verschlüsselt
archivieren / Import abbrechen. Beim Abbruch oder bei einem Fehler werden WorkData,
Protokolle und alle weiteren veränderten Tresorbereiche vollständig zurückgesetzt und
die Klartextquellen bleiben erhalten. Vor dem Entfernen wird jede Klartextquelle
vollständig verschlüsselt im `Recovery`-Ordner archiviert.

**Grenzen der sicheren Löschung (bitte lesen):**

- Auf SSDs kann das Überschreiben durch Wear Leveling wirkungslos sein.
- Cloud-Speicher können ältere Versionen oder gelöschte Dateien behalten.
- Bereits synchronisierte Klartextversionen können durch das Skript nicht rückwirkend
  entfernt werden — Cloud-Papierkorb und Versionsverlauf ggf. selbst löschen oder die
  zuständige IT einbeziehen.

## Cloud-Metadaten

Die Verschlüsselung schützt nur den **Dateiinhalt**. Ein Cloud-Anbieter oder Arbeitgeber
kann weiterhin erkennen: dass eine Datei existiert, Dateiname, Dateigröße,
Änderungszeitpunkt, Synchronisationsvorgänge und möglicherweise ältere Dateiversionen.
Deshalb verwendet die Anwendung stabile, neutrale Dateinamen ohne Datums-/Uhrzeitangaben.

## Sicheres Speichern, Checkpoints und Absturzsicherheit

- Gespeichert wird sofort nach jeder relevanten Änderung (Start/Ende von Arbeitstag und
  Abschnitt, Moduswechsel, Pausen, Sperren/Entsperren, Korrekturen, Einstellungen,
  Erreichen von 09:45/10:00). Der regelmäßige 30-Sekunden-Checkpoint läuft nur, wenn er
  fachlich gebraucht wird (laufender Homeoffice-Abschnitt oder offenes Sperr-/
  Pausenintervall — er hält den Tracking-Checkpoint für die Lückenerkennung aktuell);
  im reinen Betriebsmodus läuft die Zeit anhand der Zeitstempel ohnehin korrekt weiter.
  Es läuft immer nur **ein** Speichervorgang gleichzeitig (keine Überlappung), und ein
  Checkpoint wird übersprungen, wenn in den letzten 30 Sekunden bereits gespeichert wurde.
- Jeder Speichervorgang: im Speicher validieren → Metadaten-Snapshot anlegen → Revision
  erhöhen → verschlüsseln → `vault.pending.azt` schreiben → Pending-Datei erneut lesen,
  HMAC prüfen, entschlüsseln und strukturell validieren → prüfen, ob `vault.azt` seit dem
  letzten Laden **extern verändert** wurde (siehe unten) → Pending-Datei atomar per
  `File.Replace` als neue Hauptdatei übernehmen (alter Stand wird beiseitegelegt,
  robuster Move-Fallback) → neue Hauptdatei **erneut öffnen und prüfen** → **erst
  danach** Backuprotation. In die Backupkette gelangen ausschließlich nachweislich
  verwendbare Dateien (Containerprüfung + HMAC): eine beschädigte alte Hauptdatei wird
  niemals als `backup1` weiterkopiert, ein unbrauchbares `backup1` überschreibt niemals
  `backup2` — unbrauchbare Dateien wandern neutral in den `Recovery`-Ordner. Wurde die
  Anwendung aus Pending/Backup1/Backup2 geöffnet, wird dieser Stand kontrolliert als
  neuer Hauptstand übernommen, ohne den einzigen gültigen Backupstand zu überschreiben.
- Schlägt ein Speichervorgang fehl, werden **alle** zuvor veränderten Metadaten
  (Revision, `LastCheckpointAt`, `ModifiedAt`, `WorkData.LastSavedAt`, `CleanShutdown`)
  aus dem Snapshot vollständig zurückgesetzt. Der Benutzer wird sichtbar informiert, der
  Zustand wird in der kompakten Ansicht als „NICHT GESPEICHERT" gekennzeichnet, und die
  Anwendung versucht das Speichern bis zu dreimal automatisch erneut. Mehrstufige
  Aktionen (z. B. Arbeitstag beenden) führen die gesamte Änderung im Speicher durch,
  speichern genau einmal und rollen bei einem Fehler vollständig zurück.
- **Externe Dateiänderungen (Cloud-Synchronisierung):** Vor dem Ersetzen von `vault.azt`
  wird anhand des Hashes der zuletzt geladenen/geschriebenen Datei (Revision als
  zusätzliches Merkmal) geprüft, ob die Datei außerhalb der Anwendung verändert wurde.
  Ist das der Fall, wird sie **nicht überschrieben**: Der eigene Stand wird verschlüsselt
  unter einem neutralen GUID-Namen (`Recovery\vault-<GUID>.azt`, keine Arbeitszeitdaten
  im Dateinamen) gesichert, der Benutzer informiert und keine automatische
  Zusammenführung durchgeführt.
- Die bestehende `vault.azt` wird **niemals** direkt überschrieben; mindestens zwei
  vorherige gültige verschlüsselte Stände bleiben erhalten. Ein Absturz während des
  Schreibens beschädigt weder die letzte gültige Hauptdatei noch die Backups.
- Jeder Stand trägt eine monoton steigende, HMAC-geschützte **Revision** sowie
  `SessionId`, `LastCheckpointAt` und `CleanShutdown`. Beim Start wird `CleanShutdown`
  auf `false` gesetzt und gespeichert, beim regulären Ende auf `true`.
- **Wiederherstellungszeitpunkt:** Unmittelbar nach dem Entschlüsseln — und **vor** dem
  ersten Speichervorgang der neuen Sitzung — werden die unveränderten Werte der
  vorherigen Sitzung gesichert (voriger `CleanShutdown`, voriger Checkpoint, voriger
  Tracking-Checkpoint `WorkData.LastSavedAt`, laufender Modus, offene Pause, offenes
  Sperrintervall, Quelle des geladenen Standes). Das Sitzungsstart-Speichern aktualisiert
  den fachlichen Tracking-Checkpoint bewusst **nicht**; die gesamte Wiederherstellung
  (Homeoffice-Lücke, offene Sperrintervalle, offene Pausen) rechnet mit den vorherigen
  Werten. Erst nach Abschluss der Wiederherstellungsfragen wird der neue reguläre
  Tracking-Checkpoint gespeichert. Eine Homeoffice-Lücke kann dadurch nicht unbemerkt
  als Arbeitszeit gewertet und ein offenes Sperrintervall nicht bis zum Programmstart
  verlängert werden.
- Beim Start werden Hauptdatei, Pending-Datei und beide Backups kryptografisch und
  strukturell geprüft. Der neueste gültige Stand wird **anhand der höchsten Revision**
  ermittelt — niemals anhand des Dateidatums. Nach einem unsauberen Ende oder bei einem
  neueren gültigen Pending-Stand erscheint: „Die Anwendung wurde zuvor nicht ordnungsgemäß
  beendet. Ein gültiger Wiederherstellungsstand wurde gefunden." mit der Auswahl
  neuester Stand / bisheriger Hauptstand / abbrechen. Bei vorhandenen
  Wiederherstellungsdateien wird niemals automatisch ein leerer Tresor angelegt.
- **Betrieb:** Nach Absturz/Neustart wird die Zeit exakt aus den gespeicherten
  Zeitstempeln fortgeführt; wurde die 10-Stunden-Grenze während der Ausfallzeit erreicht,
  wird der Abschnitt rückwirkend am korrekten Zeitpunkt gestoppt.
- **Homeoffice:** Für die nicht rekonstruierbare Zeit seit dem letzten Checkpoint wird
  zwingend nachgefragt (Arbeitszeit / Pause / Sperrzeit / manuell aufteilen / Abschnitt
  endete um HH:mm / nachbearbeiten) — es gibt keine stillen Annahmen. Eine beim Absturz
  offene manuelle Pause wird ebenfalls abgefragt. Überlappende Pausen- und Sperrzeiten
  werden auch nach einer Wiederherstellung nur einmal abgezogen (Intervallvereinigung).

**Grenzen:** Änderungen seit dem letzten erfolgreichen Checkpoint können bei einem harten
Abbruch verloren gehen (maximal ~30 Sekunden bei laufendem Tag). Verschlüsselung ersetzt
kein Backup — der gesamte Ordner sollte regelmäßig gesichert werden. Cloud-Dienste können
ältere Versionen oder Konfliktkopien behalten.

## Verschlüsseltes Protokoll

Es gibt keine `application.log` mehr. Sämtliche Ereignisse (Programmstart/-ende,
Tagesstart/-abschluss, Moduswechsel, Sperren/Entsperren, Pausen, Korrekturen, Warnungen,
Fehler, Speichervorgänge, Migrationen, Passwortänderungen) werden **im Tresor**
gespeichert. Passwörter, Schlüssel, Salts oder Ciphertexte erscheinen niemals im
Protokoll. Fehler vor dem Entsperren werden nur in der Oberfläche angezeigt und nicht in
eine Diagnosedatei geschrieben. Das Protokoll ist auf 5.000 aktuelle Einträge begrenzt;
ältere Einträge wandern in ein ebenfalls verschlüsseltes Archiv im Tresor (Obergrenze
20.000 Einträge). Einstellungen → „Verschlüsselte Protokolle löschen..." entfernt
Protokoll und Archiv manuell.

## Bedienung

**Kompakte Ansicht** (Standard): schmale, zweizeilige Anzeige ohne Fensterrahmen.

```
15:32:18 | KW 28 | Freitag, 10.07.2026
Beginn: 06:12 | Netto: 06:36 | Soll-Rest: 00:24 | Max-Ende: 16:57
```

- **Ziehen mit der linken Maustaste**: Fenster verschieben (Position und Breite werden
  gespeichert und beim nächsten Start wieder angewendet)
- **Doppelklick**: erweiterte Ansicht öffnen
- **Rechtsklick**: Kontextmenü (Arbeitstag starten/beenden, Modus wechseln, Pause,
  Aktivhaltung, in den Infobereich ausblenden, minimieren, Verlauf, Export,
  Einstellungen, Anwendung schließen)
- Ein `*` hinter einer Endzeit bedeutet: die Prognose ist pausiert (z. B. laufende
  Homeoffice-Pause)

Eine **gespeicherte** Fensterposition wird gegen die **vollständigen Monitorflächen**
(inkl. Taskleiste, `Screen.Bounds`) geprüft: Eine bewusst über der Windows-Taskleiste
platzierte kompakte Ansicht bleibt beim nächsten Start **exakt** dort und wird niemals
automatisch nach oben korrigiert. Verschoben wird nur, wenn die Position tatsächlich
außerhalb aller vorhandenen Monitore liegt oder nahezu unsichtbar wäre (auch Monitore
links/oberhalb des Hauptmonitors, Lücken zwischen Monitoren, entfernte Monitore,
geänderte Auflösungen). Die **erstmalige Standardposition** verwendet weiterhin den
Arbeitsbereich (oberhalb der Taskleiste). Gespeichert wird die Position genau einmal nach
dem Ende des Ziehens sowie vor dem Ausblenden in den Infobereich und vor dem regulären
Beenden — nicht bei jedem Bewegungspixel und nur bei tatsächlicher Änderung. Bei stark
unterschiedlicher DPI-Skalierung mehrerer Monitore ist die Umrechnung eine Näherung über
den Hauptmonitor.

**Erweiterte Ansicht**: alle Tageswerte, Liste der Arbeitsabschnitte, Pausen und
Sperrzeiten, Korrekturfunktionen, Verlauf, Export, Einstellungen, Arbeitstag beenden.

**Arbeitstag starten**: Modus (Betrieb/Homeoffice) wählen und den Arbeitsbeginn manuell
im Format `HH:mm` eintragen. Der Beginn wird nie automatisch gesetzt und kann jederzeit
nachträglich korrigiert werden („Tag bearbeiten").

**Feste Grenzen** (nicht über die Einstellungen änderbar): Warnung ab 09:45,
automatischer Stopp bei exakt 10:00 Netto-Stunden, Betriebspause 00:45 ab exakt 06:00
Betriebszeit. Die **Regelarbeitszeit** ist einstellbar, muss größer als 00:00 sein und
darf höchstens 10:00 betragen; ungültige Eingaben werden abgelehnt und der bisherige
Wert bleibt erhalten.

Die 10-Stunden-Grenze wird nach **jeder** Änderung neu geprüft (Timer, Moduswechsel,
manuelle Eingaben, Bearbeitung von Abschnitten/Pausen/Sperrzeiten, Import, Migration,
Wiederherstellung, Neustart, Änderung des Arbeitsbeginns, Tagesabschluss). Eine manuelle
Änderung, durch die die Netto-Arbeitszeit über 10:00 steigen würde, wird abgelehnt und
vollständig zurückgenommen. Nach einer Korrektur unter 10:00 wird `MaxReached` konsistent
zurückgenommen. Abschlusszeiten werden vollständig validiert (nicht vor laufenden oder
abgeschlossenen Abschnitten, nicht vor Pausen-/Sperrintervallen, nicht in der Zukunft,
kein Netto über 10:00); es gibt keine stillen Zeitkorrekturen.

## Unterschied Betrieb und Homeoffice

| | Betrieb | Homeoffice |
|---|---|---|
| Berechnungsbasis | eingetragene Zeitstempel | tatsächliche aktive Zeit |
| Windows-Sperre | Zeit läuft weiter | Zeit pausiert automatisch |
| Manueller Pausenknopf | nicht vorgesehen | vorhanden |
| Mittagspause | fest 45 Min. ab 6 h Betriebszeit | keine automatische Pause |

Ein Tag darf beliebig zwischen den Modi wechseln („Modus wechseln"). Die Zeit zwischen
Ende des alten und Beginn des neuen Abschnitts gilt als Unterbrechung (keine Arbeitszeit).
Die 6-Stunden-Grenze für die Betriebspause zählt nur Betriebszeit (die Pause ist ab
**exakt** 06:00 Betriebszeit aktiv); die 10-Stunden-Grenze gilt für die gesamte
Netto-Arbeitszeit des Tages. Überlappen sich im Homeoffice eine manuelle Pause und eine
Windows-Sperre, wird der Zeitraum nur **einmal** abgezogen.

## Scroll-Lock-Aktivhaltung

Optional (standardmäßig aktiv) betätigt die Anwendung bei laufendem Arbeitstag alle
60 Sekunden die Rollen-Taste (Scroll Lock) per `SendInput`, zwei Umschaltungen im Abstand
von ca. 300 ms, nicht blockierend über Timer. Die Zustandsmaschine ist abgesichert:

- Vor jedem Zyklus wird der tatsächliche Zustand gelesen und gemerkt; das Ergebnis
  **jeder** `SendInput`-Umschaltung wird geprüft.
- Weicht der Endzustand vom Ausgangszustand ab, erfolgt sofort ein begrenzter
  Wiederherstellungsversuch; schlägt auch dieser fehl, wird die Aktivhaltung automatisch
  **deaktiviert**, eine sichtbare Warnung angezeigt und der Fehler verschlüsselt
  protokolliert.
- Beim Programmende wird der Ausgangszustand mit einer begrenzten Anzahl Wiederholungen
  wiederhergestellt (keine Endlosschleife).
- **Grenze:** Bei Prozessabsturz, erzwungenem `Stop-Process`, Stromausfall oder
  Windows-Absturz ist keine Wiederherstellungsgarantie möglich — dann ggf. die
  Rollen-Taste manuell prüfen.

> **Wichtig:** Die Nutzung dieser Funktion muss mit den IT- und Sicherheitsvorgaben des
> jeweiligen Unternehmens abgestimmt sein. Die Anwendung verändert keine
> Gruppenrichtlinien, Sicherheitssoftware oder erzwungene Unternehmensvorgaben.

## CSV-Export

Erweiterte Ansicht bzw. Kontextmenü → **Export**: aktueller Tag, frei wählbarer Zeitraum
oder alle Daten. CSV-Dateien sind die **einzige unverschlüsselte Ausnahme**. Vor jedem
Export erscheint die Warnung: „Die exportierte CSV-Datei ist nicht verschlüsselt und kann
von anderen Personen oder Cloud-Diensten gelesen werden." — der Export erfolgt nur nach
ausdrücklicher Bestätigung und niemals automatisch. Passwort und Schlüssel werden niemals
exportiert.

Alle Textfelder sind gegen **CSV-/Formelinjektion** geschützt: Werte, die mit `=`, `+`,
`-`, `@`, Tabulator, Wagenrücklauf oder Zeilenumbruch beginnen (auch als Text exportierte
Zeitwerte wie `-00:30`), werden durch ein vorangestelltes Apostroph neutralisiert.
Format für deutsches Excel: Semikolon-getrennt, UTF-8 mit BOM, deutsche Datums-/
Zeitformate. Der Dateiname darf wie bisher Datum/Zeitraum enthalten, da der Benutzer den
Export bewusst veranlasst. Die Dateien landen im Ordner `Exports\`.

## Datenvalidierung und Schema

Der Tresorcontainer wird zusätzlich plausibilisiert, **bevor** sein Inhalt eingelesen
wird: Dateien über 100 MB werden vor `ReadAllText` abgelehnt, übermäßig große
Base64-Felder vor der Dekodierung verworfen, für Container-Version 1 muss das Salt exakt
32 Byte lang sein, der IV exakt 16 Byte, der HMAC exakt 32 Byte, der Ciphertext darf
nicht leer sein und muss durch 16 teilbar sein, die Iterationszahl muss im vorgesehenen
Bereich liegen, unbekannte Container- und neuere Schema-Versionen werden abgelehnt. Bei
einer nicht verarbeitbaren Datei wird keine vorhandene Datei automatisch überschrieben.

Beim Laden wird nicht nur gültiges JSON geprüft, sondern u. a.: Containerkennung und
-version, KDF-Verfahren, zulässige Iterationszahl, Salt-/IV-/HMAC-Längen, Schema-Version
des Inhalts, Pflichtfelder, gültige Tages-/Abschnitts-/Intervallobjekte, Modi und
Zeitstempel, Start ≤ Ende, keine Überlappungen, höchstens ein aktiver Tag / ein laufender
Abschnitt / eine offene Pause / ein offenes Sperrintervall, Regelarbeitszeit im zulässigen
Bereich und keine Nettozeit über 10:00. Unbekannte oder neuere Schema-Versionen werden
**nicht** stillschweigend geöffnet. Bei ungültigen Daten wird nichts automatisch
überschrieben; die verschlüsselten Backups werden geprüft und eine Wiederherstellung
angeboten — stille Korrekturen finden nicht statt.

## Testmodus

`-RunTests` führt 69 Testfälle (160 Prüfungen) ohne Oberfläche aus, u. a.: Berechnungs-
Engine (Betriebspause inkl. Randwerte 05:59:59/06:00:00/06:44:59/06:45:00, Homeoffice-
Abzüge, Überlappungen, Überstunden, 09:45/10:00), Verschlüsselung (Roundtrip inkl.
Unicode und deutscher Prüftexte, falsches Passwort, manipulierter Ciphertext/HMAC/Header,
zufällige IVs, unterschiedliche Ciphertexte bei gleichem Klartext), kein Klartext/
Passwort in Dateien, Migration (inkl. `worktime.backup.json` als alternative Quelle,
Erhalt nicht übernommener Dateien, verschlüsselte Archivierung), Importkonflikte bei
gleichem Datum mit vollständigem Rollback, Passwortänderung inkl. Unterbrechung
(`.new`-/`.old`-Reste, Startreparatur), Backup-Wiederherstellung aus Backup2 mit
anschließendem Speichern (der einzige gültige Backupstand wird nicht überschrieben),
Metadaten-Rollback bei Speicherfehlern, Erkennung externer Dateiänderungen,
Container-Härtung (übergroße Dateien, falsche Salt-Länge), Pending-/Revision-/
CleanShutdown-Logik, Schema-Ablehnung, Regelarbeitszeit- und 10-Stunden-Validierung,
MaxReached-Rücknahme, EndedAt-Validierung, CSV-Formelinjektion, Scroll-Lock-
Fehlerbehandlung, Fensterbreite, Taskleisten-Position und Monitor-Lücken, UTF-8-BOM der
Skript- und README-Datei sowie Layoutprüfungen des Einstellungs- und Exportdialogs
(umbruchfähige Beschriftungen, identische Preset- und OK/Abbrechen-Schaltflächen,
vollständige Sichtbarkeit; WPF layoutet skalierungsunabhängig in DIPs, die Prüfungen
gelten daher für 100/125/150 % gleichermaßen — die Fensterhöhe wird zur Laufzeit durch
MaxHeight und einen ScrollViewer begrenzt). Exit-Code 0 = alle bestanden.

Die Tests arbeiten ausschließlich in temporären Testordnern und verändern keine echten
Benutzerdaten. Hinweis: Die Scroll-Lock-Tests 15/16 betätigen die Taste tatsächlich kurz
und stellen den Ausgangszustand wieder her; die Krypto-Tests dauern wegen der 600.000
PBKDF2-Iterationen einige Sekunden.

## Zeichenkodierung

`ArbeitszeitTool.ps1` und `README.md` sind als **UTF-8 mit BOM** gespeichert. Nur so
stellt Windows PowerShell 5.1 deutsche Sonderzeichen (ä, ö, ü, ß) zuverlässig dar —
beim Bearbeiten mit anderen Editoren unbedingt beibehalten. CSV-Exporte werden als UTF-8
mit BOM erzeugt; Tresorinhalte werden vor der Verschlüsselung explizit als UTF-8 kodiert
und nach der Entschlüsselung als UTF-8 dekodiert (unabhängig von der ANSI-Codepage).

## Bekannte technische Grenzen

- Während die Anwendung **nicht läuft**, können Sperr-/Entsperr-Ereignisse nicht
  beobachtet werden — daher die verpflichtende Nachfrage bei Homeoffice-Lücken.
- Änderungen seit dem letzten Checkpoint (max. ~30 s) können bei hartem Abbruch verloren
  gehen; der letzte vollständig geschriebene, kryptografisch geprüfte Stand bleibt erhalten.
- Ohne Passwort keine Daten: Es gibt bewusst keine Wiederherstellungsmöglichkeit.
- Die kompakte Ansicht passt ihre Größe automatisch an; die gespeicherte Breite wird als
  Mindestbreite wieder angewendet (kein freies Aufziehen per Maus).
- Ein Arbeitstag entspricht einem Kalendertag; um 00:00 Uhr wird automatisch beendet.
- Bei sehr restriktiven Unternehmensrichtlinien kann `SendInput` unterbunden sein; die
  Aktivhaltung deaktiviert sich dann mit sichtbarer Warnung, die übrige Anwendung
  arbeitet normal weiter.
- Verschlüsselung ersetzt kein Backup: den Ordner regelmäßig sichern (die Tresordateien
  sind auch im Backup verschlüsselt).

## Hinweis zu betrieblichen IT- und Sicherheitsvorgaben

Dieses Werkzeug dient der persönlichen Arbeitszeiterfassung. Der Einsatz auf
Firmengeräten — insbesondere die Scroll-Lock-Aktivhaltung — sollte vorab mit den
geltenden IT-, Sicherheits- und Arbeitszeitregelungen des Unternehmens abgestimmt
werden. Die Anwendung sendet keine Daten nach außen und protokolliert keine Inhalte
anderer Anwendungen.


---

## Internetradio, Netzwerk und Datenschutz (neu)

Die Anwendung besitzt mit dem optionalen **Internetradio** erstmals eine
ausgehende Netzwerkfunktion. Die Aussage „keine Cloud" gilt weiterhin für
alle Arbeitszeitdaten – ergänzend gilt eindeutig:

- **Arbeitszeitdaten werden nicht übertragen.** Auch Einstellungen und
  Protokolle werden nicht übertragen; sie liegen ausschließlich im lokalen,
  verschlüsselten Datentresor.
- Es wird **ausschließlich der ausgewählte Radiostream** direkt vom
  Streamanbieter abgerufen (ein zentraler `System.Windows.Media.MediaPlayer`,
  keine externen Player oder Bibliotheken).
- Der Streamanbieter sieht dabei technisch übliche Verbindungsdaten:
  IP-Adresse, Zeitpunkt und die Playeranfrage.
- Unternehmensproxy, Firewall oder Virenschutz können den Stream blockieren –
  das löst nur einen neutralen Radiofehler aus und beeinträchtigt die
  Arbeitszeiterfassung nicht.
- **Ohne gestartetes Radio findet aufgrund dieser Funktion keine
  Streamverbindung statt.** Beim Programmstart erfolgt standardmäßig keine
  automatische Wiedergabe.
- Die Nutzung von Internetradio und Scroll-Lock-Aktivhaltung muss mit den
  betrieblichen Vorgaben vereinbar sein.

### Bedienung

- **Kompakte Ansicht:** Play-/Pause-Symbol und Lautsprechersymbol oben rechts;
  das Lautsprechersymbol öffnet ein kleines Lautstärke-Popup (0–100 %),
  Mausrad über dem Symbol ändert die Lautstärke ebenfalls.
- **Erweiterte Ansicht:** Sender-Auswahl, Play/Pause, Lautstärkeregler und
  Statusanzeige (Gestoppt / Verbinden / Wiedergabe / Puffern / Pausiert / Fehler).
- **Einstellungen → Internetradio:** Sender anzeigen, hinzufügen, bearbeiten,
  entfernen, verschieben, Standardsender festlegen; Lautstärke; „nach dem
  Entsperren automatisch fortsetzen"; „Wiedergabestatus beim Beenden merken".
- **Tray-/Kontextmenü:** Radio starten/pausieren und Senderwahl.
- Die Senderliste wird **ausschließlich verschlüsselt im Tresor** gespeichert
  (keine separate Klartextdatei). Zulässig sind nur absolute http-/https-URLs
  ohne eingebettete Zugangsdaten; Hinweis: http-Streams sind nicht
  transportverschlüsselt. Stream-URLs werden nicht protokolliert (nur
  Sendername/-ID und neutrale Fehlermeldungen).
- Bei Bildschirmsperre pausiert das Radio; nach dem Entsperren wird es nur
  fortgesetzt, wenn es unmittelbar vor dem Sperren lief und die Option aktiv
  ist. „Pause" bei Livestreams bedeutet: Beim erneuten Start wird der Stream
  neu geöffnet und läuft an der aktuellen Live-Position (kein alter Puffer).

## Sichtschutz für Pausen- und Sperrzeiten (neu)

In der **erweiterten Ansicht** werden die konkreten Pausen- und
Sperrzeitwerte (Summen, Intervall-Beginn/-Ende/-Dauer) standardmäßig
**verborgen** dargestellt: die Tabelle „Pausen und Sperrzeiten" wird
unscharf gezeichnet (WPF-BlurEffect), die Summenwerte zeigen neutrale
Platzhalter (`••:••`). Beschriftungen bleiben lesbar.

- Das **Auge-Symbol** neben „Pausen und Sperrzeiten" blendet die Werte
  bewusst ein bzw. wieder aus (nur Darstellung – keine Daten- oder
  Speicheränderung, keine Neuberechnung, keine Größenänderung des Fensters).
- Automatisch **wieder verborgen** wird bei: Windows-Sperre, Schließen oder
  Minimieren der erweiterten Ansicht, Ausblenden in den Infobereich,
  Tagesabschluss, Programmende sowie 60 Sekunden nach Fokusverlust.
- Nach dem Entsperren von Windows bleiben die Werte verborgen, bis das Auge
  erneut angeklickt wird. Der Zustand „gerade sichtbar" wird niemals
  sitzungsübergreifend gespeichert.
- Verborgene Werte werden auch nicht über Tooltips, Auswahl/Fokus oder
  AutomationProperties (Screenreader) offengelegt; die Berechnung verwendet
  die Werte intern unverändert weiter.

## Verhalten bei regulärem Neustart (präzisiert)

- „**Nur Anwendung schließen (Arbeitstag bleibt offen)**": Der laufende
  Abschnitt bleibt vollständig unverändert (gleiche Segment-ID, Start
  unverändert, kein Ende). Vor dem Schließen wird `CleanShutdown=true`
  gesetzt und der Tresor final gespeichert – schlägt das fehl, kann
  wiederholt oder das Schließen abgebrochen werden.
- „**Fortsetzen**" nach einem regulären Neustart verwendet denselben Tag und
  denselben laufenden Abschnitt weiter – im **Betrieb** zählt die Zeit des
  geplanten Neustarts normal als Arbeitszeit; es entsteht **kein** neuer
  Timeslot. Im **Homeoffice** wird nur die nicht beobachtete Zeitlücke
  behandelt (Arbeitszeit / Pause / Sperrzeit / Aufteilen / ausdrückliches
  Abschnittsende / Bearbeiten) – auch hier entsteht nie automatisch ein
  neuer Abschnitt.
- Ein neuer Abschnitt entsteht ausschließlich über den ausdrücklichen
  „**Modus wechseln**"-Weg (auch direkt im Fortsetzen-Dialog wählbar).
- Schlägt die Speicherung der neuen Sitzungsmarkierung beim Start fehl,
  startet die Anwendung nicht produktiv, sondern meldet den Fehler und
  beendet sich kontrolliert.
- Die Absturzwiederherstellung (`CleanShutdown=false`) bleibt unverändert
  erhalten (Homeoffice-Lücke, offene Pausen, offene Sperrintervalle,
  10-Stunden-Grenze, voriger Tracking-Checkpoint).

## Scroll-Lock-Aktivhaltung (finaler Stand)

Die Aktivhaltung ist ein einfacher, vollständig entkoppelter **Doppelpuls**:
Tastendruck (Down+Up) → ca. 200 ms → Tastendruck (Down+Up), ausgeführt in C#
auf einem ThreadPool-Thread (nie auf dem WPF-UI-Thread), mit
Interlocked-Parallelschutz. Im Produktivbetrieb findet **keine**
Scroll-Lock-Zustandsabfrage statt; Fehler werden nur gedrosselt im
verschlüsselten Protokoll erfasst und deaktivieren die Funktion nicht.
Der automatische Testlauf (`-RunTests`) sendet **niemals** echte Eingaben
(vollständige Simulation); echte Tastendrücke gibt es nur im normalen
Betrieb und im ausdrücklich bestätigten `-RunScrollLockManualTest`.

**Ehrliche Grenze:** Bei `Stop-Process -Force`, Stromausfall oder einem
Prozess-/Systemabsturz exakt zwischen den beiden Tastendrücken – ebenso bei
einem fehlgeschlagenen zweiten SendInput – kann der Scroll-Lock-Zustand
verändert zurückbleiben. Das ist bei einem zustandslosen Doppelpuls nicht
vollständig ausschließbar und beeinträchtigt die Arbeitszeiterfassung nicht.

## Transaktionsdatei `vault.txn`

`vault.txn` enthält nur noch neutrale logische Bezeichnungen
(`Haupt`, `Backup1`, `Backup2`) – keine absoluten Pfade mehr, die
Benutzername oder Cloud-Ordnernamen offenlegen könnten. Beim Einlesen werden
ausschließlich die intern fest bekannten Pfade verwendet.

## Bedienoberflaeche (Aktualisierung)

- **Einstellungen mit Tabs:** Das Einstellungsfenster ist in vier Bereiche gegliedert (Allgemein / Kompakte Ansicht / Aktivhaltung / Internetradio) mit fester Ausgangsgroesse (780x620), begrenzt auf den Monitor-Arbeitsbereich. Speichern/Abbrechen bleiben immer sichtbar; erst "Speichern" uebernimmt Aenderungen aus allen Tabs, "Abbrechen" verwirft sie. Die Sender werden links in einer scrollenden Liste verwaltet und rechts ueber ein gemeinsames Name/URL-Feldpaar bearbeitet ("Uebernehmen").
- **In den Infobereich ausblenden:** Das Ausblenden beendet die Anwendung nicht mehr (nichtmodale Fensterlebensdauer). Timer, Arbeitszeiterfassung, Radio, Aktivhaltung und Lock-/Unlock-Verarbeitung laufen unsichtbar weiter; die Wiederanzeige erfolgt per Tray-Doppelklick oder Tray-Menue. Ist kein Tray-Symbol verfuegbar, wird stattdessen ueber die Taskleiste minimiert.
- **Radio-Senderauswahl:** Die Sender-ComboBox der erweiterten Ansicht verwendet jetzt das dunkle Anwendungsthema (inkl. Dropdown, max. Hoehe 280, Tooltip fuer lange Sendernamen).
## Protokoll-Viewer (neu)

Unter **Einstellungen -> Allgemein -> Sicherheit (Datentresor)** oeffnet
"Verschluesselte Protokolle anzeigen..." einen schreibgeschuetzten Viewer:
aktuelle und archivierte Eintraege gemeinsam (neueste zuerst, zunaechst 500,
"Weitere 500 anzeigen"), mit Suchfeld und INFO/WARN/ERROR-Filtern. Die Daten
werden ausschliesslich aus dem entschluesselten Tresor im Arbeitsspeicher
gelesen - es entsteht keine temporaere Klartextdatei, und der Viewer
veraendert keine Protokolle. Optional koennen die aktuell angezeigten
Eintraege nach ausdruecklicher Warnung UNVERSCHLUESSELT in den Ordner
"Exports" exportiert werden (UTF-8 mit BOM; vollstaendige Internetadressen
wie Stream-URLs werden dabei entfernt). Die Loeschfunktion bleibt unveraendert.