# RemoteMac — design

**Data:** 2026-09-04
**Status:** zatwierdzony do implementacji

## Problem

Łączenie się do zdalnych Maków przez Finder Cmd+K wymaga pamiętania, który adres
Tailscale należy do której maszyny. Lista "Favorite Servers" pokazuje wyłącznie
`vnc://100.123.34.96:5900` — bez nazw. Przy dwóch maszynach to uciążliwe, przy
większej liczbie nieużywalne.

## Rozwiązanie

Aplikacja w pasku menu, która wyświetla zdalne Maki po nazwie, ze wskaźnikiem
dostępności, i uruchamia wbudowany w macOS Screen Sharing jednym kliknięciem.
Dodatkowo otwiera sesję SSH w wybranym terminalu.

Nie budujemy własnego klienta VNC ani własnego protokołu. Aplikacja jest
launcherem i katalogiem maszyn.

## Zakres

**Wchodzi:**

- lista Maków z Tailscale, automatyczna, po nazwie
- ręcznie dodawane hosty spoza tailnetu
- wskaźnik dostępności (online + czy Screen Sharing nasłuchuje)
- uruchomienie Screen Sharing (`vnc://`)
- uruchomienie SSH w konfigurowalnym terminalu
- kopiowanie IP/nazwy, otwarcie `smb://`, ręczny test dostępności
- szybkie wyszukiwanie w stylu Spotlight
- start przy logowaniu

**Nie wchodzi (YAGNI):**

- własny klient VNC
- agent/demon na zdalnych maszynach
- przechowywanie haseł VNC (zostaje w Keychainie macOS)
- globalny skrót klawiszowy (wymaga uprawnień Accessibility)
- Wake-on-LAN
- zdalne włączanie Screen Sharing

## Fakty zweryfikowane empirycznie

Wszystkie ustalenia poniżej pochodzą z uruchomionych komend na maszynie
docelowej (macOS 26.6.2, build 25G83, Xcode 26.6, Swift 6.3.3), zweryfikowanych
niezależnie przez drugą parę agentów.

### Tailscale

| Fakt | Wartość |
|---|---|
| Ścieżka CLI | `/Applications/Tailscale.app/Contents/MacOS/Tailscale` |
| `/usr/local/bin/tailscale` | nie istnieje |
| Wersja | 1.102.3, build z Mac App Store (sandboxowany) |
| Bundle ID | `io.tailscale.ipn.macos` |
| Czas wywołania | 44–46 ms (rozgrzane) |

**Pułapki:**

1. `TAILSCALE_BE_CLI=1` jest obowiązkowe przy wywołaniu z `.app`. Binarka
   rozpoznaje tryb CLI po środowisku (`TERM`), którego `.app` nie ma — bez tej
   zmiennej próbuje uruchomić GUI i zwraca `CLIError error 3`. Zmienna jest
   czuła na wartość: `0` zawodzi tak samo jak brak.
2. Komunikat błędu trafia na **stdout**, a **kod wyjścia to 0**. Awarii nie da
   się wykryć po exit code. Jedyny wiarygodny test: dekodowanie JSON.
3. CLI potrafi wejść w trwały stan zawieszenia (0 bajtów wyjścia) przy w pełni
   sprawnym demonie. Wymagany twardy timeout i **trzy** stany: poprawny JSON /
   błąd GUI / brak odpowiedzi. Brak odpowiedzi to "nieznany", nie "rozłączony".
4. `p.terminate()` nie zawsze wystarcza do ubicia zawieszonego dziecka.

**Struktura JSON:**

- `Peer` to słownik kluczowany `nodekey:<hex>`, nie tablica — iterować po
  `.values()`.
- `Self` **nie znajduje się** w `Peer`. Pełna lista Maków to
  `Peer.values() + [Self]`.
- `OS` ma wartość dokładnie `"macOS"` (nie `darwin`, nie `macos`).
- `DNSName` kończy się kropką i wymaga obcięcia. Pierwszy segment daje czystą
  nazwę zdatną do SSH (`konrads-mac-mini`).
- `HostName` zawiera znak U+2019 (typograficzny apostrof) na urządzeniach
  Apple — nie jest bezpieczny dla DNS. `Self.HostName` używa prostego
  apostrofu, więc występują obie formy.
- `LastSeen` równe `0001-01-01T00:00:00Z` (zerowy czas Go) oznacza, że peer
  jest online. Sensowne tylko przy `Online == false`.
- `Tags` jest **nieobecne** (klucz nie występuje) dla urządzeń użytkownika, nie
  `null`. Dekodować jako `[String]?`.
- `Self` nie ma klucza `Tags` w ogóle.
- iPhone raportuje `HostName == "localhost"` — kolejny powód, by preferować
  `DNSName`.
- `Version` w JSON to forma długa (`1.102.3-t9329c3677-…`), inna niż w bundlu.

### Screen Sharing

- Ścieżka: `/System/Applications/Utilities/Screen Sharing.app`. Historyczna
  `/System/Library/CoreServices/Applications/` **nie istnieje na macOS 26**.
- Uruchomienie przez `NSWorkspace.shared.open(URL(string: "vnc://<ip>"))`.
  Nie hardkodujemy ścieżki — LaunchServices rozwiązuje schemat `vnc`.
- Hasło obsługuje Keychain macOS; aplikacja nie dotyka sekretów.

### Sprawdzanie dostępności

Oba Maki użytkownika (100.123.34.96, 100.108.216.101) mają otwarty port 5900 i
zwracają prawdziwy baner `RFB 003.889` — Screen Sharing rzeczywiście działa.

**Pułapki `NWConnection`:**

1. Odrzucone połączenie zgłaszane jest jako `.waiting`
   (`POSIXErrorCode(61): Connection refused`), **nie** `.failed`. Bez obsługi
   `.waiting` każdy zamknięty port blokuje na pełny timeout (2 s zamiast
   0,008 s).
2. Obsługa `.waiting` **nie wystarcza**. Host nieosiągalny (śpiący Mac) nie
   emituje żadnego stanu po `.preparing` — śledzenie przez 25 s nie dało nic.
   Zewnętrzny timeout z `cancel()` obsługuje cały ten przypadek i jest
   obowiązkowy.
3. Trzeci przypadek `.waiting` to błąd DNS (`-65554: NoSuchRecord`, 0,117 s).
   Wymaga odrębnego komunikatu, bo naprawa jest inna niż przy zamkniętym porcie.
4. Ryzyko fałszywego negatywu zweryfikowane: 40 kolejnych prób do żywego hosta,
   `.waiting` nie wystąpił ani razu przed `.ready`.

Otwarty port oznacza "Screen Sharing nasłuchuje", **nie** "połączysz się" —
maszyna z dostępem ograniczonym do wybranych użytkowników również nasłuchuje i
odpowiada banerem.

### SSH

Klucze między Makami użytkownika **nie są skonfigurowane**:

```
ssh -o BatchMode=yes 100.123.34.96   → Permission denied (publickey)
ssh -o BatchMode=yes 100.108.216.101 → brak wpisu w known_hosts
```

Dlatego SSH jest ścieżką opcjonalną, wykrywaną w tle, nigdy wymaganą.

`ConnectTimeout` **nie ogranicza fazy autoryzacji** — przy hoście pytającym o
hasło ssh wisiał 8 s mimo `ConnectTimeout=3` i stdin z `/dev/null`. Wymagane
`BatchMode=yes` plus zewnętrzny timeout. `NumberOfPasswordPrompts=0` jest
zbędne, bo `BatchMode` już to obejmuje.

Gdy klucze zadziałają, jedno wywołanie `ioreg` daje użytkownika i stan blokady:

- `IOConsoleUsers[0]` → `kCGSSessionUserNameKey`, `kCGSSessionOnConsoleKey`
- `IOConsoleLocked` → blokada ekranu

`CGSSessionScreenIsLocked` nie zwraca nic na macOS 26. `CGSession` nie istnieje.
`Quartz` niedostępny w systemowym `/usr/bin/python3`.

### Terminale

| Terminal | Bundle ID | Wywołanie | TCC |
|---|---|---|---|
| Ghostty | `com.mitchellh.ghostty` | `open -na Ghostty --args -e ssh user@host` | brak |
| iTerm2 | `com.googlecode.iterm2` | `open -na iTerm --args "--command=ssh user@host"` | brak |
| Terminal | `com.apple.Terminal` | osascript `do script` | AppleEvents |
| Warp | `dev.warp.Warp-Stable` | otwarcie + schowek | brak |

**Ustalenia:**

- iTerm2 przyjmuje `--command=X` **wyłącznie w formie ze znakiem równości**.
  Forma ze spacją uruchamia aplikację i nic nie wykonuje.
- Ghostty i iTerm2 są równorzędne — obie ścieżki bez okna uprawnień.
- Warp **celowo** nie pozwala wykonać komendy. Jego własna dokumentacja
  (`Contents/Resources/bundled/skills/warpctrl/SKILL.md`) mówi, że Warp Control
  jedynie wstawia tekst i nie udostępnia akcji zatwierdzającej. Dodatkowo tryb
  ten jest domyślnie wyłączony na kanale Stable. Stąd: otwarcie Warpa plus
  komenda w schowku.
- Semantyka cytowania różni się: Ghostty `-e` przyjmuje tablicę argv (bez
  powłoki), iTerm przepuszcza string przez `/usr/bin/login … $SHELL -c`. Nazwa
  hosta z metaznakami to wektor wstrzyknięcia na ścieżce iTerma. Escapowanie
  osobne per backend.
- `open -na` tworzy **drugą instancję iTerma** przy każdym uruchomieniu. Gdy
  aplikacja już działa, pomijać `-n`.
- Schemat `ssh://` przechwytuje **Termius** — nie używać `open ssh://`.
  Termius dodany jako świadomie wspierany backend.
- Wykrywanie przez `NSWorkspace.urlForApplication(withBundleIdentifier:)`, nie
  przez ścieżki (Terminal mieszka w `/System/Applications/Utilities/`).
- `AEDeterminePermissionToAutomateTarget(…, askUserIfNeeded: false)` pozwala
  sprawdzić uprawnienie AppleEvents **bez** wywołania systemowego okna. Cel musi
  działać; nie wywoływać z main thread. Błąd `-1743` to `errAEEventNotPermitted`.

### Pakowanie i podpisywanie

**Aplikacja musi być podpisana Developer ID, nie ad-hoc.**

- Ad-hoc: Designated Requirement to goły hash zawartości i zmienia się przy
  każdym przebudowaniu (`c48daa9c…` → `df468329…` po zmianie jednej linii).
  Uprawnienia TCC i Keychain resetują się po każdym buildzie.
- Developer ID: DR pinuje bundle ID i Team ID. CDHash się zmienia, DR pozostaje
  bajtowo identyczny.

Niezmiennikiem jest bundle ID **plus** Team ID — DR zawiera
`leaf[subject.OU] = "7S3F9767BM"`. Reissue certyfikatu pod innym Team ID
zresetuje uprawnienia mimo stałego bundle ID.

W keychainie znajdują się **dwa** certyfikaty o tej samej nazwie, przez co
`codesign --sign "<nazwa>"` kończy się błędem `ambiguous`. Skrypt buildu
rozwiązuje tożsamość przez SHA-1.

`--deep` jest **wycofane dla podpisywania** od macOS 13 i nie wnosi nic dla
bundla z jedną binarką — pominąć.

**Aplikacja nie może być sandboxowana.** Nie dlatego, że sandbox blokuje
`Process` (nie blokuje — zweryfikowane działającym sandboxowanym `.app`), lecz
dlatego, że Tailscale sam jest sandboxowany i uruchomiony z sandboxowanego
rodzica **zawiesza się bezterminowo** w `_libsecinit_appsandbox`. `run()`
kończy się sukcesem, wyjątku nie ma, proces wisi. Wyjątek entitlementu na
odczyt kontenera Tailscale nie pomaga.

`SMAppService` wymaga podpisu — nagłówek SDK: *"Apps that use SMAppService APIs
must be code signed"*, w przeciwnym razie `kSMErrorInvalidSignature`.
Notaryzacja nie jest wymagana dla aplikacji głównej (dotyczy LaunchDaemonów).

### API

Zweryfikowane w SDK MacOSX26.5:

- `MenuBarExtra` — macOS 13+. `extension MenuBarExtra: Sendable` jest oznaczone
  `@available(*, unavailable)`.
- `.menuBarExtraStyle(.window)` — wymagane. Styl `.menu` renderuje `NSMenu`, co
  ogranicza zawartość do elementów menu; kolorowe wskaźniki statusu i własne
  wiersze wymagają `.window`.
- `Settings<Content>: Scene` — macOS 11+. `EnvironmentValues.openSettings` —
  macOS 14+.
- `SMAppService.mainApp`, `register()`, `unregister()`, `.status` — macOS 13+.
  Obsłużyć `.requiresApproval` i `openSystemSettingsLoginItems()`.
- Brak modułu `Subprocess` w SDK — to osobny pakiet SwiftPM.

Aplikacja budowana jest SDK 26 przy `LSMinimumSystemVersion` 15.0, więc każde
API dostępne dopiero od 26 wymaga `if #available`.

## Architektura

```
remote-mac/
  Package.swift              # swift-tools 6.2, .macOS(.v15), swiftLanguageMode(.v6)
  Sources/RemoteMac/
    App.swift                # MenuBarExtra + Settings
    Model/
      Host.swift             # tożsamość hosta, źródło (tailscale | manual)
      HostStatus.swift       # online | offline | unknown | listening
      AppSettings.swift      # Codable, zapis do JSON
    Clients/
      TailscaleClient.swift  # status --json → [Host]
      ProbeClient.swift      # NWConnection TCP 5900
      SSHStatusClient.swift  # opcjonalny, ioreg przez ssh
      LauncherClient.swift   # vnc://, terminale, smb://
    Store/
      HostStore.swift        # @Observable, scalanie źródeł, odświeżanie
    Views/
      MenuView.swift
      HostRow.swift
      SettingsView.swift
      QuickSwitcher.swift
  Resources/Info.plist       # LSUIElement=true
  Scripts/build-app.sh
  Tests/RemoteMacTests/
```

Klienty ukryte za protokołami, więc testy używają atrap zamiast prawdziwego
`ssh`, `nc` czy Tailscale.

### Przepływ danych

1. `HostStore` wywołuje `TailscaleClient` (timeout, `TAILSCALE_BE_CLI=1`).
2. Wynik filtrowany do `OS == "macOS"`, łączony z `Self` i hostami ręcznymi.
3. Dla każdego hosta równolegle `ProbeClient` sprawdza port 5900.
4. Jeśli SSH dostępne — `SSHStatusClient` dokłada użytkownika i stan blokady.
5. Widok renderuje listę; każdy host ma własny, niezależny stan.

Odświeżanie przy otwarciu menu (probe trwa 0,01 s) oraz w tle co 30 s.

### Info.plist

```xml
<key>CFBundleIdentifier</key><string>io.eightlines.remotemac</string>
<key>CFBundleExecutable</key><string>RemoteMac</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSAppleEventsUsageDescription</key>
<string>RemoteMac otwiera sesje SSH w wybranym przez Ciebie terminalu.</string>
```

### Podprocesy

`swift-subprocess` 1.0.0 zamiast Foundation `Process`. Powód nie jest taki, że
`Process` się nie kompiluje — kompiluje się czysto pod Swift 6. Powodem jest
zakleszczenie: `run()` → `waitUntilExit()` → `readDataToEndOfFile()` zawiesza
się przy wyjściu przekraczającym bufor pipe'a (~64 KB), co zreprodukowano na
200 KB. `swift-subprocess` drenuje pipe'y asynchronicznie i buduje się bez
ostrzeżeń pod `.swiftLanguageMode(.v6)` i `.strictMemorySafety()`.

Środowisko podprocesu: `ProcessInfo.processInfo.environment` **scalone** z
nadpisaniami, nie podmienione.

### Ustawienia

`~/Library/Application Support/io.eightlines.remotemac/settings.json`, zapis
atomowy, `.prettyPrinted` + `.sortedKeys`. Przechowuje wybrany terminal, nazwę
użytkownika SSH per host (domyślnie `radnok`), hosty ręczne, hosty ukryte.
Bez haseł.

Wybór JSON zamiast `UserDefaults` wynika z wymagania ręcznej edycji —
`UserDefaults` to binarny plist za `cfprefsd`, który nadpisuje zmiany z zewnątrz.

## Obsługa błędów

| Sytuacja | Zachowanie |
|---|---|
| Tailscale nie działa / `BackendState != Running` | baner "Tailscale rozłączony", hosty ręczne działają |
| CLI nie odpowiada (0 bajtów) | status "nieznany", nie "offline" |
| Mac offline lub śpi | wyszarzony wiersz, timeout nie blokuje UI |
| Port 5900 zamknięty | "Screen Sharing wyłączony" |
| Błąd DNS | "Nie znaleziono hosta" — komunikat odrębny od zamkniętego portu |
| SSH bez kluczy | akcja SSH dostępna, dodatkowy status pominięty |
| Brak terminala | podpowiedź wyboru innego w ustawieniach |
| AppleEvents odrzucone (-1743) | własne wyjaśnienie z instrukcją `tccutil reset` |

Żadna awaria pojedynczego hosta nie może zablokować menu — każdy probe ma
własny timeout i wykonuje się równolegle.

## Testy

Logika oddzielona od I/O, testowalna bez sieci:

- parser JSON Tailscale na prawdziwych fixture'ach: apostrof U+2019,
  `HostName: "localhost"`, zerowy czas Go w `LastSeen`, brakujący klucz `Tags`,
  `Self` poza `Peer`
- wykrycie błędu GUI Tailscale przy kodzie wyjścia 0
- budowanie komend per terminal, w tym escapowanie metaznaków (różne dla
  Ghostty i iTerma)
- maszyna stanów statusu: online / offline / nieznany / nasłuchuje
- scalanie hostów z Tailscale z hostami ręcznymi, deduplikacja po IP

## Skrypt buildu

```bash
swift build -c release
APP="$HOME/Applications/RemoteMac.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/RemoteMac "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
CERT_SHA=$(security find-identity -v -p codesigning \
  | awk '/Developer ID Application.*7S3F9767BM/{print $2; exit}')
codesign --force --options runtime --sign "$CERT_SHA" \
  --identifier io.eightlines.remotemac "$APP"
```

Bundle ID i `--identifier` są ustalone raz i nie zmieniają się nigdy — od tego
zależy stabilność uprawnień. Aplikacja instalowana jest do stałej lokalizacji,
bo przeniesienie po rejestracji psuje pozycję startową.
