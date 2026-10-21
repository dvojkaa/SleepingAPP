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
4. Pokud Xcode nahlásí, že bundle identifier `com.kratina.vojta.SleepTracker`
   už někdo používá ("Failed to register bundle identifier"), změň ho v
   `project.yml` (klíč `PRODUCT_BUNDLE_IDENTIFIER`) na něco jiného
   unikátního, ulož, aktualizuj i `bundleIdentifier` v
   `altstore-source.json` (ať sedí se SideStore zdrojem) a znovu spusť
   `xcodegen generate`.

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
   seznam všech klipů – každý s časem, délkou, tlačítkem přehrát/pauza a
   barevným štítkem s rozpoznaným typem zvuku (chrápání, mluvení, prdění
   nebo "Jiný zvuk").

Rozpoznání typu zvuku appka dělá přímo na telefonu (Apple's `SoundAnalysis`
framework), bez internetu a bez dalšího oprávnění navíc – běží na pozadí po
uložení každého klipu, proto klip chvilku po vzniku ukazuje "Zpracovává
se…", než se štítek dopočítá.

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
  ukončí (výchozí 5.5 s). Čím vyšší hodnota, tím méně se krátké pauzy mezi
  zvuky (např. nádechy mezi chrápáním) rozsekávají na spoustu samostatných
  klipů – appka prostě nahrává o pár sekund déle, než si je jistá, že zvuk
  fakt skončil.
- `minimumClipDuration` – kratší klipy se zahodí jako šum (výchozí 1 s).

Pokud appka zachytává příliš mnoho/málo, uprav tato čísla a appku znovu
nahraj do telefonu (krok 3).

Podobně jde doladit i rozpoznávání typu zvuku – v souboru
`SleepTracker/SoundClassifierService.swift`, v `enum Threshold`:

- `minimumClassificationConfidence` – pod touto jistotou (výchozí 0.4, tedy
  40 %) appka klip radši označí jako "Jiný zvuk", i kdyby systémový
  klasifikátor tipoval chrápání/mluvení/prdění.
- `analysisWindowDurationSeconds` – délka analytického okna (výchozí 1.5 s).
- `analysisOverlapFactor` – jak moc se po sobě jdoucí okna překrývají
  (výchozí 0.5, tedy každé další okno se posune o polovinu své délky) – vyšší
  hodnota znamená víc (pomalejších) výsledků na stejně dlouhý klip.

## Alternativa bez kabelu a bez 7denní expirace: SideStore

Postup výše (Xcode + kabel) je nejjednodušší na první vyzkoušení, ale appka
po 7 dnech vyprší a musíš ji znovu nahrát z Macu. Pokud chceš appku používat
dlouhodobě na dvou telefonech (tvém i přítelkynině) a nechceš kvůli tomu
každý týden sedat k počítači, použij místo toho
[SideStore](https://sidestore.io) – appku, která appky podepsané tvým
bezplatným Apple ID umí sama obnovovat na pozadí přes Wi-Fi, bez trvalé
závislosti na počítači (počítač je potřeba jen jednou, při úvodním spárování
každého telefonu).

### Jak appku vydávat přes SideStore

Tenhle repozitář obsahuje:

- `.github/workflows/release.yml` – GitHub Actions workflow, který appku
  sestaví na macOS runneru **bez nutnosti vlastního Macu** (nepodepsaný
  `.ipa`, SideStore appku podepíše sama při instalaci) a nahraje ji jako
  GitHub Release.
- `altstore-source.json` – tzv. "source" soubor, katalog appek pro
  AltStore/SideStore. Obsahuje odkaz na nejnovější `.ipa` a appka si ho umí
  pravidelně stahovat, aby věděla, že je k dispozici nová verze.

Vydání nové verze:

1. Commitni změny appky do `main`.
2. Vytvoř a pushni git tag ve tvaru `vX.Y.Z`, např.:
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```
   (nebo spusť workflow ručně v GitHub UI pod záložkou **Actions**, včetně
   zadání verze – hodí se, když nechceš tagovat).
3. Workflow appku sestaví, vytvoří GitHub Release s přiloženým `.ipa` a
   automaticky aktualizuje `altstore-source.json` v `main` s odkazem na
   novou verzi.

### Jak appku přidat na telefon (tvůj i přítelkynin)

1. Nainstaluj SideStore podle návodu na [sidestore.io](https://sidestore.io)
   (jednorázově vyžaduje počítač na spárování zařízení).
2. V SideStore přidej zdroj (source) s touto URL:
   ```
   https://raw.githubusercontent.com/dvojkaa/SleepingAPP/main/altstore-source.json
   ```
3. Appka "SleepTracker" se objeví v seznamu – nainstaluj ji přímo ze
   SideStore.
4. Při vydání nové verze appky (viz výše) stačí v SideStore kliknout na
   **Update** – bez kabelu, bez Xcode.

Pozor: pokud v `project.yml` změníš `PRODUCT_BUNDLE_IDENTIFIER`, uprav
stejnou hodnotu i v `bundleIdentifier` v `altstore-source.json`, ať appka
jde přes SideStore rozpoznat jako aktualizaci stávající appky, ne jako
novou appku vedle ní.
