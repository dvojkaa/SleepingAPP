# SleepTracker

Jednoduchá appka pro soukromé sledování chrápání a zvuků ze spánku. Přes noc
poslouchá mikrofon, a jakmile zaslechne zvuk (chrápání, mluvení ze spánku...),
uloží si ho jako krátký zvukový klip. Ráno appka ukáže přehled noci – graf
hlasitosti v čase a seznam klipů k přehrání. Žádný účet, žádný server, žádný
cloud – všechna data (zvukové nahrávky i jejich seznam) zůstávají jen v
telefonu, ve složce appky.

Appka je určená k instalaci přes kabel z Macu přímo na konkrétní iPhone
(sideloading přes Xcode), ne přes App Store. Appka má vlastní ikonku
(měsíc + zvukové vlny) v `SleepTracker/Assets.xcassets/AppIcon.appiconset`.

## TL;DR – co přesně udělat na Macu

```bash
brew install xcodegen
cd cesta/k/SleepingAPP
xcodegen generate
open SleepTracker.xcodeproj
```

V Xcode: klikni na projekt → target `SleepTracker` → **Signing &
Capabilities** → u **Team** vyber svoje Apple ID → připoj iPhone kabelem →
nahoře vyber iPhone jako cíl místo simulátoru → stiskni **Run** (▶).

Na telefonu pak jednou potvrď "Trust This Computer?" a v **Nastavení →
Obecné → VPN a správa zařízení** potvrď důvěru svému Apple ID, jinak appka
nepůjde spustit. Detailní rozpis všech kroků (včetně toho, co dělat při
chybách a jak appku po 7 dnech znovu nahrát) je níže.

## Co budeš potřebovat

- Mac s nainstalovaným Xcode (z App Storu, zdarma)
- [Homebrew](https://brew.sh) (pokud ho ještě nemáš)
- Apple ID (stačí běžný, bezplatný účet – není potřeba platit za Apple
  Developer Program)
- iPhone a kabel na propojení s Makem

## 1. Vygenerování Xcode projektu

Tento repozitář neobsahuje přímo `.xcodeproj` soubor (ten se negeneruje
ručně), ale `project.yml` popis pro nástroj [XcodeGen](https://github.com/yonaskolb/XcodeGen),
který `.xcodeproj` vytvoří za tebe. Díky tomu je repo čisté a projekt se dá
kdykoliv znovu vygenerovat.

V Terminálu spusť:

```bash
brew install xcodegen
cd cesta/k/SleepingAPP
xcodegen generate
```

Tím vznikne soubor `SleepTracker.xcodeproj`. Otevři ho (dvojklikem, nebo
`open SleepTracker.xcodeproj`).

## 2. Nastavení podpisu appky (Signing)

1. V Xcode klikni v levém panelu na projekt `SleepTracker` (úplně nahoře).
2. Vyber target `SleepTracker` a záložku **Signing & Capabilities**.
3. U pole **Team** vyber svoje Apple ID. Pokud tam ještě není, klikni na
   "Add an Account..." a přihlas se svým běžným Apple ID – bezplatný účet
   stačí.
4. Pokud Xcode nahlásí, že bundle identifier `com.example.sleeptracker` už
   někdo používá ("Failed to register bundle identifier"), změň ho v
   `project.yml` (klíč `PRODUCT_BUNDLE_IDENTIFIER`) na něco unikátního, např.
   `com.tvoje-jmeno.sleeptracker`, ulož a znovu spusť `xcodegen generate`.

## 3. Nahrání appky do telefonu

1. Připoj iPhone k Macu kabelem.
2. V telefonu může vyskočit dotaz "Trust This Computer?" – potvrď.
3. Nahoře v Xcode, v liště se zařízeními (vedle tlačítka Run/Stop), vyber
   svůj iPhone jako cíl (místo simulátoru).
4. Stiskni **Run** (▶) v levém horním rohu Xcode.
5. Xcode appku zkompiluje a nahraje do telefonu. Může se objevit chyba o
   podpisu – v tom případě se vrať ke kroku 2.

### Důležité: první spuštění na telefonu

Při prvním spuštění appka na telefonu **nepůjde otevřít** a telefon ukáže
hlášku, že vývojáři appky nevěříš. To je normální u appek nahraných mimo App
Store. Vyřeš to takto:

1. Na iPhonu jdi do **Nastavení → Obecné → VPN a správa zařízení**.
2. Pod "Vývojářská aplikace" (Developer App) najdi svůj Apple ID a klepni na
   **Důvěřovat** (Trust).
3. Appku pak spusť normálně klepnutím na ikonu.

## 4. Důležité upozornění: appka vyprší po 7 dnech

Appky nahrané na telefon přes **bezplatné** Apple ID fungují jen **7 dní**
od nahrání, pak se přestanou spouštět. Po týdnu appku jednoduše znovu nahraj:

1. Připoj telefon kabelem k Macu.
2. Otevři projekt v Xcode (pokud není otevřený).
3. Stiskni znovu **Run** (▶) stejně jako v kroku 3.

Appce to nijak neuškodí – všechna uložená data (noci, klipy) v appce zůstanou
zachovaná, přepíše se jen spustitelný soubor appky samotné.

(Pokud by to časem začalo být otravné, řešením je placený Apple Developer
Program za 99 $/rok, který appky nahrané na vlastní zařízení nijak časově
neomezuje – ale pro soukromé použití to není nutné.)

## 5. Mikrofon a nastavení telefonu

- Při prvním spuštění appka požádá o **povolení mikrofonu**. Je potřeba ho
  povolit, jinak appka nemůže nic nahrávat. (Dá se změnit i později v
  Nastavení → SleepTracker → Mikrofon.)
- Appka má zapnutý tzv. "background audio" režim, takže pokračuje v
  nahrávání i po zamčení displeje (uzamčená obrazovka appku nevypne). Přesto
  doporučujeme na noc buď:
  - nastavit **Auto-Lock** na delší dobu nebo "Nikdy" (Nastavení → Displej a
    jas → Auto-Lock), nebo
  - nechat appku prostě spuštěnou s nahráváním a telefon nechat zapojený do
    nabíječky (nahrávání přes noc stojí baterii).

## Jak appka funguje

1. V appce klepni na **"+"** (Nová noc) a pak na **"Začít noc"**.
2. Appka celou noc poslouchá mikrofon, ale **neukládá si nepřetržitou
   nahrávku** – technicky sice musí průběžně nahrávat, aby mohla měřit
   hlasitost, ale dokud nic nepřekročí práh, jde jen o pár minut dlouhý
   dočasný soubor, který se stále dokola zahazuje a nikdy se neuloží. Jakmile
   hlasitost přesáhne práh (typický zvuk jako chrápání nebo mluvení), appka
   začne ukládat samostatný klip. Klip skončí až po pár sekundách ticha (aby
   se neuřízl konec chrápání nebo věty).
3. Ráno klepni na **"Ukončit noc"**.
4. Noc se objeví v seznamu historie s datem a délkou spánku. Po otevření
   detailu noci uvidíš graf hlasitosti jednotlivých klipů v čase a pod ním
   seznam všech klipů – každý s časem, délkou a tlačítkem přehrát/pauza.

Všechna data (zvuky i jejich seznam) se ukládají pouze lokálně v telefonu
(SwiftData + soubory ve složce appky `Documents/Nights/...`). Appka
nepotřebuje internetové připojení ani žádný účet.

## Laditelné prahy citlivosti

Appka rozhoduje o tom, co je "dost hlasité na to, aby to uložila jako klip",
podle konstant v souboru `SleepTracker/AudioMonitorService.swift`, v `enum
Threshold`:

- `startDB` – hlasitost (v dB), při které appka začne nahrávat nový klip
  (výchozí -30 dB).
- `endDB` – pod touto hlasitostí appka považuje situaci za "ticho" (výchozí
  -40 dB, nižší než startDB kvůli hysterezi).
- `silenceHoldToEndClip` – jak dlouho musí být ticho, než appka klip skutečně
  ukončí (výchozí 2.5 s, aby se neuřízl konec zvuku).
- `minimumClipDuration` – kratší klipy se zahodí jako šum (výchozí 1 s).

Pokud appka zachytává příliš mnoho/málo, uprav tato čísla a appku znovu
nahraj do telefonu (krok 3).
