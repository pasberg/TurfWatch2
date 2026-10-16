# TurfWatch2 — urtavlekomplikation (ingen App Group behövs)

`TurfComplication.swift` är en **självständig** komplikation: den hämtar sin egen
statistik direkt från Turf-API:t. Användarnamnet anges som konstanten
`kUsername` högst upp i filen (byt till ditt). Därför behövs **ingen App Group,
inget konfigurations-intent och inget betalt Apple-konto**.

Den använder den klassiska `StaticConfiguration` + `TimelineProvider`, som är
stabil och fungerar oavsett SDK-version.

Koden ligger här men är **inte** tillagd i Xcode-projektet, eftersom en
komplikation måste köra i ett eget *Widget Extension*-target.

## 1. Ta bort App Group (om du la till den)

Om du hann lägga till App Group-capability på `TurfWatch2 Watch App`:
markera target → **Signing & Capabilities** → ta bort **App Groups**
(papperskorgen). Den behövs inte längre och ger bara en röd varning på
gratiskonto.

## 2. Skapa Widget Extension-targetet

1. **File → New → Target…**
2. Välj **watchOS → Widget Extension**. Namnge det t.ex. `TurfComplication`.
3. **Avmarkera** "Include Configuration App Intent" (vi använder en statisk
   widget — användarnamnet sätts i koden).
4. **Activate** schemat när Xcode frågar.

Radera de genererade extra-filerna (`TurfComplicationBundle.swift`,
`AppIntent.swift`, `TurfComplicationControl.swift`) och ersätt den genererade
`TurfComplication.swift` med filen här. Byt `kUsername` till ditt Turf-namn.

Xcode skapar en mapp med en genererad widget-fil. **Ersätt** innehållet i den
genererade `.swift`-filen med innehållet i `TurfComplication.swift` här
(eller radera den genererade filen och dra in den här i target-mappen).

> Targetets deployment target ska vara watchOS 10.0 (samma som appen).

## 3. Bygg och lägg till på urtavlan

1. Kör appen/komplikationen i simulatorn.
2. Tryck och håll på urtavlan → **Edit** → välj en komplikationsplats →
   välj **Turf**.
3. Öppna komplikationens inställningar och skriv in ditt **Turf-användarnamn**
   (standard är "Ventruce"). Den hämtar sedan statistiken själv.

## Vad som visas

| Familj | Innehåll |
|---|---|
| Inline | `24 p/h · 6 zoner` |
| Circular | mätare med p/h |
| Rectangular | användarnamn, p/h, poäng, antal zoner |
| Corner | p/h |

Komplikationen uppdateras ca var 20:e minut och när appen körts (appen anropar
`WidgetCenter.reloadAllTimelines()`).

## Felsökning

- **Nollor:** kontrollera att användarnamnet är rätt stavat i komplikationens
  inställningar, och att nätverk finns. Är Turf-API:t rate-limitat (429) visas
  senast kända värden tills nästa lyckade hämtning.
- **Byggfel om `containerBackground`/App Intents:** kräver watchOS 10+.
