# Changelog

Alle Änderungen am ArbeitszeitTool, neueste Version zuerst. Die aktuelle Version steht in
`ArbeitszeitTool.ps1` (`$script:AppVersion`). Diese Datei gehört zum Repository, ist aber
nicht Teil des ZIP-Downloads.

## 1.5.4 – 02.11.2026 – Passwortwechsel gegen konkurrierende Schreiber

Security-Audit vom 02.11.2026, Befund AZT-SEC-02.

- **Problem:** Die Vorprüfung „Hauptdatei unverändert" galt nur für ihren Zeitpunkt. Danach
  wurden die Dateien bedingungslos ausgetauscht und die `.old`-Rücksicherung gelöscht. Ein
  zwischenzeitlich eingetroffener Cloud-Sync-Stand ging verloren – ebenso, wenn er schon vor
  dem Einlesen eintraf, weil der Referenzhash danach neu aus der Datei gelesen wurde.
- Die Umverschlüsselung liest jede Datei genau einmal. Weicht die Hauptdatei vom Stand der
  Sitzung ab, bricht der Passwortwechsel ab, bevor etwas verändert wird.
- Austausch nur, wenn die Datei noch dem gelesenen Stand entspricht: Hashvergleich und
  Umbenennen laufen unter einem Handle, das fremde Schreiber aussperrt. `.new` wird nie über
  eine fremd angelegte Datei gesetzt; die Rücknahme ersetzt keine fremden Stände, `.old`-Kopien
  bleiben dann erhalten.
- Abschlussprüfung, Journalspiegel und Referenzhash entstehen aus den eigenen, geprüften Bytes.
- Nachschärfung AZT-SEC-01: Die Referenz auf die Hauptdatei wird nur noch aus dem Scan gesetzt;
  eine Tresor-Neuanlage gilt ausdrücklich als „keine Hauptdatei vorhanden".

## 1.5.3 – 02.11.2026 – Referenzhash aus dem gelesenen Tresorstand

Security-Audit vom 02.11.2026, Befund AZT-SEC-01.

- **Problem:** Beim Entsperren wurde der Inhalt im Kandidatenscan gelesen, der Referenzhash der
  Hauptdatei aber später durch erneutes Öffnen gebildet. Ersetzte ein Cloud-Sync die Datei
  dazwischen (z. B. während der Wiederherstellungsdialog offen war), überschrieb das nächste
  Speichern den neueren Stand ohne Konfliktmeldung.
- Jede Tresordatei wird genau einmal gelesen (Größenprüfung unter demselben Handle); Prüfung,
  Inhalt und Hash stammen aus diesem einen Byte-Stand.
- Hat sich die Hauptdatei nach der Auswahl verändert, fordert die Anwendung zum erneuten
  Entsperren auf und lädt den aktuellen Stand. Spätere Änderungen erkennt das Speichern als
  Konflikt (fremder Stand bleibt erhalten, eigener Stand wird in `Recovery` gesichert).
- Die Journalprüfung beim Speichern arbeitet ebenfalls auf einem einzigen Byte-Stand.

## 1.5.2 – 02.11.2026 – Speicherzyklus ohne Einfrieren

GitHub-Issue #2: Das Fenster fror alle 30 Sekunden für mehrere Sekunden ein.

- Gemessene Dauer des 30-Sekunden-Checkpoints (synthetische Tresore, lokal; auf einem
  Netzlaufwerk jeweils etwa 10–20 % mehr):

  | Tresor | vorher | nachher |
  |---|---|---|
  | klein (2 Tage, 300 Protokolleinträge, 0,1 MB) | 300 ms | 50 ms |
  | mittel (60 Tage, 2.000 Protokolleinträge, 1,2 MB) | 3.000 ms | 630 ms |
  | groß (250 Tage, 25.000 Protokolleinträge, 14 MB) | 25 s | 3,1 s |

- Umwandlung der eingelesenen JSON-Daten in C# statt rekursiv in PowerShell (28× schneller,
  identisches Ergebnis; die PowerShell-Fassung bleibt als Rückfall).
- Große Byte-Arrays ohne `[Parameter(Mandatory)]`: PowerShell prüfte dabei jedes einzelne Byte
  auf `$null` (0,6 s pro Aufruf bei 14 MB). Leere Arrays werden weiterhin abgelehnt.
- Die Hauptdatei wird nach dem Schreiben nicht mehr ein zweites Mal vollständig entschlüsselt:
  sie ist per SHA-256 nachweislich byte-identisch mit dem vollständig geprüften Journal.
- Unverändert: Journal, In-place-Schreiben, Erkennung externer Änderungen, Tresorformat.

## 1.5.1 – 02.11.2026 – Absturz bei Tagen mit mehreren Abschnitten

- **Fehler seit 1.0.0:** Bei Tagen mit mindestens zwei Abschnitten (z. B. nach einem
  Moduswechsel) wurde die Abschnittsliste als ein einziges Element verarbeitet. Folgen:
  - Absturz bei jedem Start in der Klärung eines nicht beendeten Vortags
    („Unerwarteter Fehler – die Anwendung wird beendet")
  - der 10-Stunden-Stopp schlug im Hintergrund jede Sekunde fehl (kein Stopp, keine
    Anzeigeaktualisierung, Protokollflut)
- Der Fehlerdialog zeigt zusätzlich eine technische Kurzmeldung.
- Unverändert: Tresorformat, Datenmodell, gespeicherte Daten.

## 1.5.0 – 02.11.2026 – Teilabschnitte zwischen den Pausen

GitHub-Issue #3.

- Tages-Editor: neuer Reiter **Teilabschnitte** mit den Arbeitsphasen zwischen den Pausen je
  Abschnitt (Beginn, Ende, Dauer). Im Homeoffice trennen manuelle Pausen und Windows-Sperren,
  im Betrieb die feste Betriebspause. Die Summe entspricht dem Netto des Abschnitts. Berechnet
  wird nur, solange der Reiter ausgewählt ist.
- CSV-Export: Option „Teilabschnitte als eigene Datei" (`Arbeitszeiten_Teilabschnitte_*.csv`);
  die Detail-Datei bleibt unverändert.
- Unverändert: erweiterte Ansicht, Sichtschutz, Datenmodell, Berechnung, Speicherung.

## 1.4.1 – 27.10.2026 – Verlauf: Doppelklick und horizontales Scrollen

- Doppelklick auf einen Tag im Verlauf öffnet „Tag bearbeiten".
- Spalten in natürlicher Breite mit horizontaler Scrollleiste; Kommentar vollständig in einer
  Zeile, voller Kommentar mit Zeilenumbrüchen als Tooltip.

## 1.4.0 – 27.10.2026 – Testsuite ausgelagert

- Testsuite nach `tests\` verschoben (Einstieg `tests\Run-Tests.ps1`); die Anwendung schrumpft
  um rund ein Viertel.
- Neuer Schalter `-DefinitionsOnly` für den Testeinstieg (kein Programmstart).
- `-RunTests` / `-RunScrollLockManualTest` zeigen nur noch einen Hinweis.
- `tests\`, `.gitattributes` und `.gitignore` sind nicht Teil des ZIP-Downloads.

## 1.3.6 – 27.10.2026 – Kalenderdatum validieren

- Die Strukturprüfung lehnt unmögliche Kalenderdaten ab (z. B. 2026-02-30), statt später
  Export und Tages-Editor abstürzen zu lassen.

## 1.3.5 – 27.10.2026 – Konkurrierende Tresorzugriffe

- Hauptdatei wird nur geschrieben, wenn sie noch dem geprüften Stand entspricht; Prüfung und
  Schreiben laufen unter einem Handle. Fremdänderungen bleiben erhalten.
- Referenzhash nach dem Speichern aus den eigenen Bytes.
- Nur eine Instanz pro Datenordner; ein zweiter Start zeigt einen Hinweis.

## 1.3.4 – 27.10.2026 – Sichtschutz auch für UI Automation

- Im verborgenen Zustand wird nur eine maskierte Kopie der Pausen-/Sperrtabelle angezeigt; die
  echten Werte gelangen nicht mehr in den Automation-Baum (Screenreader).

## 1.3.3 – 27.10.2026 – Konfliktsicherung ehrlich melden

- Bei einer externen Änderung wird die Sicherung des eigenen Standes nach `Recovery` per Hash
  geprüft; „gesichert" wird nur noch bei Erfolg gemeldet, sonst eine deutliche Fehlermeldung.

## 1.3.2 – 27.10.2026 – Tages-Editor: Layout und Kommentarzugang

- Arbeitsabschnitte oben, darunter Reiter für Pausen, Sperrintervalle und Änderungsprotokoll;
  Schaltflächen vollständig sichtbar.
- „Bearbeiten" zeigt und ändert auch den Kommentar; reine Kommentaränderungen erzeugen keine
  Korrektur. Doppelklick auf eine Zeile öffnet die Bearbeitung.

## 1.3.1 – 27.10.2026 – Kompaktfeld Soll-Ende / Max-Ende

- Neues Feld für die kompakte Ansicht: bis zum Erreichen der Sollzeit das Soll-Ende, danach
  automatisch das Max-Ende.

## 1.3.0 – 27.10.2026 – Kommentare

- Optionale Kommentare an Tag, Abschnitt, Pause, Sperrintervall und Korrektur (bis 1000
  Zeichen), verschlüsselt im Tresor; ältere Tresore laden unverändert.
- Kommentarspalte in Tabellen, Verlauf und CSV-Export (mit Formelschutz).
- Änderungsprotokoll im Tages-Editor; Korrekturen mit optionaler Begründung.

## 1.2.0 – 27.10.2026 – Scroll-Lock-Aktivhaltung als Opt-in zurück

- Die Aktivhaltung aus 1.0.0 ist wieder enthalten, aber standardmäßig **aus**.
- Hinweis: Das Skript enthält damit wieder Code zur Tastatureingabe-Simulation. Einsatz mit
  IT/Sicherheit abstimmen.

## 1.1.1 – 22.10.2026 – Nachbesserung Recovery-Neuverschlüsselung

- Jede Datei im Ordner `Recovery` wird beim Passwortwechsel eindeutig eingeordnet (neu
  verschlüsselt / anderes Passwort / beschädigt / keine Tresordatei / fehlgeschlagen).
- Originale werden nur überschrieben, wenn sie seit dem Lesen unverändert sind.
- Unterbrochene Recovery-Phase wird beim Start erkannt; Abschlussmeldung unterscheidet
  vollständig und teilweise.

## 1.1.0 – 22.10.2026 – Security-Review, Scroll-Lock-Aktivhaltung entfernt

- Passwortwechsel verschlüsselt auch die mit dem bisherigen Passwort lesbaren Dateien im Ordner
  `Recovery` neu; kein Passwortwechsel bei extern veränderter Tresordatei.
- Unvollständige Rücknahme eines gescheiterten Passwortwechsels wird ehrlich gemeldet.
- Scroll-Lock-Aktivhaltung vollständig entfernt (in 1.2.0 als Opt-in zurück).
- STA-Neustart über den festen Systempfad von `powershell.exe`.

## 1.0.0 – 21.10.2026 – Erste Veröffentlichung

- Verschlüsselter Datentresor (AES-256-CBC + HMAC-SHA256, PBKDF2 mit 600.000 Iterationen),
  Erfassung von Betrieb und Homeoffice, Pausen, Sperrzeiten, Korrekturen, CSV-Export.
- Optionales Herunterfahren des PCs beim Schließen der Anwendung (standardmäßig aus); ein
  aktiver Arbeitstag wird vorher vollständig beendet, bei Speicherfehlern kein Shutdown.
