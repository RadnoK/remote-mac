# RemoteMac

Aplikacja w pasku menu macOS do szybkiego łączenia się ze zdalnymi Makami przez
wbudowany Screen Sharing. Zastępuje ręczne wpisywanie adresów IP w Finderze
(⌘K), pokazując maszyny po nazwie.

## Co robi

- wyświetla Maki z Tailscale automatycznie, po nazwie
- pokazuje, czy maszyna jest dostępna i czy Screen Sharing nasłuchuje
- odświeża status w tle co 30 sekund, więc kropki są aktualne, zanim jeszcze
  otworzysz menu
- łączy przez Screen Sharing jednym kliknięciem
- otwiera SSH w wybranym terminalu — obsługiwane są Ghostty, iTerm2, Terminal
  i Warp; w wyborze terminala pojawiają się tylko te faktycznie zainstalowane
  na tej maszynie
- otwiera pliki przez SMB, kopiuje adres IP
- szybkie wyszukiwanie w stylu Spotlight

## Wymagania

- macOS 15 lub nowszy
- Tailscale (dowolna wersja — App Store lub standalone)
- Screen Sharing włączony na maszynach docelowych
  (Ustawienia systemowe → Ogólne → Udostępnianie → Zarządzanie zdalne)

## Budowanie

```bash
./Scripts/build-app.sh
open ~/Applications/RemoteMac.app
```

Aplikacja jest podpisywana certyfikatem Developer ID. Bez podpisu uprawnienia
systemowe resetowałyby się przy każdym przebudowaniu, a start przy logowaniu nie
działałby wcale.

## Testy

```bash
swift test
```

## Konfiguracja

Ustawienia trzymane są w czytelnym pliku JSON, który można edytować ręcznie:

```
~/Library/Application Support/io.eightlines.remotemac/settings.json
```

Hasła nie są tam przechowywane — Screen Sharing zapamiętuje je w Keychainie
macOS.

## Uwagi

- **Warp** celowo nie pozwala uruchomić komendy automatycznie. Aplikacja otwiera
  Warp i kopiuje komendę do schowka.
- **Terminal.app** wymaga zgody na automatyzację przy pierwszym użyciu.
  Ghostty i iTerm2 nie wymagają żadnych uprawnień.
- Otwarty port 5900 oznacza, że Screen Sharing nasłuchuje — nie gwarantuje, że
  logowanie się powiedzie.
- Brak globalnego skrótu klawiszowego — aplikację otwiera się klikając ikonę
  w pasku menu.
