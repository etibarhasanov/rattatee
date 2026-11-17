# The voice: what to record

The turns of a way are said aloud in recordings of the owner's voice — see
`Rattatee/Core/Guide.swift`. This is the dictionary: twelve phrases, each in
English, Estonian and Russian, thirty-six recordings in all.

The app joins them. Before a corner it plays **In 200 metres** and then the
turn; at the corner it plays the turn alone. So each phrase is recorded on
its own, as a whole sentence, with no "and then".

| File | English (`en-`) | Estonian (`et-`) | Russian (`ru-`) |
|---|---|---|---|
| `soon` | In two hundred metres | Kahesaja meetri pärast | Через двести метров |
| `left` | Turn left | Pööra vasakule | Поверните налево |
| `right` | Turn right | Pööra paremale | Поверните направо |
| `keep-left` | Keep left | Hoia vasakule | Держитесь левее |
| `keep-right` | Keep right | Hoia paremale | Держитесь правее |
| `straight` | Go straight | Sõida otse | Езжайте прямо |
| `around` | Turn around | Pööra ümber | Развернитесь |
| `roundabout-1` | At the roundabout, take the first exit | Ringristmikul vali esimene väljasõit | На круговом движении — первый съезд |
| `roundabout-2` | At the roundabout, take the second exit | Ringristmikul vali teine väljasõit | На круговом движении — второй съезд |
| `roundabout-3` | At the roundabout, take the third exit | Ringristmikul vali kolmas väljasõit | На круговом движении — третий съезд |
| `roundabout` | Go through the roundabout | Sõida läbi ringristmiku | Проезжайте круговое движение |
| `arrive` | You have arrived | Oled kohal | Вы на месте |

`roundabout` on its own is for a fourth exit or later, and for one the
router did not count.

The wording is yours to change: say a phrase the way you would say it, and
it is right. Only the meaning has to match the file.

## Recording

- Voice Memos on an iPhone, in a quiet room, the phone a hand's width from
  your mouth. No wind, no street.
- The easy way is **one recording a language**: read the twelve phrases down
  the column, in the order of the table, with a clear pause of two seconds
  between them. They are cut apart afterwards.
- Say each a little slower and louder than talking. It will be heard from a
  pocket, over traffic.
- Twice each is fine; the better one is kept.

## Where they go

Cut, trimmed of silence and levelled, each phrase is one file in
`Rattatee/Voice/`, named for its language and the first column:

```
Rattatee/Voice/en-soon.m4a
Rattatee/Voice/et-left.m4a
Rattatee/Voice/ru-roundabout-2.m4a
```

AAC in an `.m4a`, mono. The folder is flat because the project's
synchronised group copies every resource to the top of the bundle, where two
files called `left.m4a` would be one.

Until a file is there, that phrase is read by the phone's own voice in
English and Russian and is silent in Estonian, which iOS has no voice for. A
language is all or nothing a sentence: "In 200 metres" recorded and "Turn
left" not is read whole by the phone, rather than in two voices.

## Adding a phrase

A new phrase is a new `Clip` in `Guide.swift`, a row here, three recordings
and a new build. A new kind of turn is also a word in the website's
`/api/route` — `TURNS` in its `functions/api/route.js` — and an installed
app is silent at a word it does not know.
