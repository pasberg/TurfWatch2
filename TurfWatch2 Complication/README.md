# TurfWatch2 — urtavlekomplikation

Koden för komplikationen (`TurfComplication.swift`) ligger här men är **inte**
tillagd i Xcode-projektet, eftersom en komplikation måste köra i ett eget
*Widget Extension*-target. Följ stegen nedan för att aktivera den.

## 1. Lägg till ett Widget Extension-target

1. I Xcode: **File → New → Target…**
2. Välj **watchOS → Widget Extension**. Namnge det t.ex. `TurfComplication`.
3. Avmarkera "Include Configuration App Intent" (vi använder en statisk widget).
4. När Xcode frågar om att aktivera schemat: **Activate**.

Xcode skapar en mapp med en genererad widget-fil. **Ersätt** innehållet i den
genererade `.swift`-filen med innehållet i `TurfComplication.swift` här (eller
radera den genererade filen och dra in den här i target-mappen).

## 2. Dela data mellan appen och komplikationen (App Group)

Komplikationen läser statistik som appen skriver via en delad **App Group**.

1. Markera projektet → välj **appens** target (`TurfWatch2 Watch App`) →
   **Signing & Capabilities → + Capability → App Groups**.
2. Lägg till gruppen: `group.com.pasberg.TurfWatch2`
   (samma sträng som `AppState.appGroup`).
3. Upprepa för **komplikationens** target: lägg till App Groups och samma grupp.

> Byter du grupp-id, uppdatera `AppState.appGroup` och `appGroup` i
> `TurfComplication.swift` så de matchar.

## 3. Bygg och lägg till på urtavlan

1. Kör appen en gång så den hämtar din profil (den skriver statistik till
   App Group-lagringen).
2. Tryck och håll på urtavlan → **Edit** → välj en komplikationsplats →
   välj **Turf**.

## Vad som visas

| Familj | Innehåll |
|---|---|
| Inline | `24 p/h · 6 zoner` |
| Circular | mätare med p/h |
| Rectangular | p/h, poäng, antal zoner + närmaste zon |
| Corner | p/h |

Komplikationen uppdateras när appen hämtar ny data (den anropar
`WidgetCenter.reloadAllTimelines()`), och minst var 15:e minut.

## Felsökning

- **Tomt/nollor:** kör appen i förgrunden en gång så den hinner skriva data,
  och kontrollera att **exakt samma** App Group-id finns på båda targets.
- **Byggfel om `containerBackground`:** kräver watchOS 10+. Projektets
  deployment target är redan 10.0.
