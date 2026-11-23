# The voice: what to record

The turns of a way are said aloud in recordings of the owner's voice — see
`Rattatee/Core/Guide.swift`. This is the dictionary: sixteen phrases, each in
English, Estonian, Russian and Azerbaijani, sixty-four recordings in all.

The app joins them. Before a corner it plays **In 200 metres** and then the
turn; at the corner it plays the turn alone. So each phrase is recorded on
its own, as a whole sentence, with no "and then".

A tunnel is said like a turn, at its entrance. Where it starts just past
a corner — the Veerenni path under the railway turns left into it — the
two are played one after the other, **Turn left** then **Enter the
tunnel**, so the second does not cut the first off.

| File | English (`en-`) | Estonian (`et-`) | Russian (`ru-`) | Azerbaijani (`az-`) |
|---|---|---|---|---|
| `soon` | In two hundred metres | Kahesaja meetri pärast | Через двести метров | İki yüz metrdən sonra |
| `left` | Turn left | Pööra vasakule | Поверните налево | Sola dön |
| `right` | Turn right | Pööra paremale | Поверните направо | Sağa dön |
| `keep-left` | Keep left | Hoia vasakule | Держитесь левее | Solda qal |
| `keep-right` | Keep right | Hoia paremale | Держитесь правее | Sağda qal |
| `straight` | Go straight | Sõida otse | Езжайте прямо | Düz get |
| `around` | Turn around | Pööra ümber | Развернитесь | Geri dön |
| `arrive` | You have arrived | Oled kohal | Вы на месте | Çatdın |
| `tunnel` | Enter the tunnel | Sõida tunnelisse | Въезжайте в тоннель | Tunelə gir |
| `off` | You're off the way | Oled teelt maas | Вы сошли с пути | Yoldan çıxdın |
| `wrong-way` | Going the wrong way | Vale suund | Вы едете не в ту сторону | Yanlış istiqamətdə gedirsən |
| `train` | Your train leaves from here | Sinu rong läheb siit | Ваш поезд отходит отсюда | Qatarın buradan gedir |

The train is said once, on the platform of a way by train, where the
ride to the station would otherwise have said "You have arrived". It
cannot say which train or when — a recording only says what was recorded
— so the row on screen does: *Train RE34 at 09:31 to Kitseküla*. Until
it was recorded the phone's own voice read that row, which in Estonian
and Azerbaijani was nothing at all.

## The greeting

When a new ride starts — not on a resume — one line is said for the time
of day on the phone's clock (`Guide.greet`), before any turn. A turn that
comes while it is still playing cuts it off.

| File | When | English (`en-`) | Estonian (`et-`) | Russian (`ru-`) | Azerbaijani (`az-`) |
|---|---|---|---|---|---|
| `morning` | 05:00–11:59 | Good morning, let's go | Tere hommikust, lähme | Доброе утро, поехали | Sabahın xeyir, gedək |
| `afternoon` | 12:00–17:59 | Good afternoon, let's go | Tere päevast, lähme | Добрый день, поехали | Günortan xeyir, gedək |
| `evening` | 18:00–21:59 | Good evening, let's go | Tere õhtust, lähme | Добрый вечер, поехали | Axşamın xeyir, gedək |
| `late` | 22:00–04:59 | Riding late, let's go | Liiga hilja? Lähme ikka! | Поздновато, поехали | Gecə gəzintisi, getdik! |

The words the phone reads until these are recorded are the `greet…` keys
in `Rattatee/Seed/strings.json`; change them there too if you say it
differently.

There is nothing for a roundabout, on purpose: the app is for a bike, which
is mostly on the path beside one. Where the way does go through one, the row
on screen says so — "Roundabout, exit 2" — and the voice says nothing.

The wording is yours to change: say a phrase the way you would say it, and
it is right. Only the meaning has to match the file.

**Recorded so far: Azerbaijani, English and Estonian, all but the
train**, on 2026-11-18, each language in one take. Russian is still to do,
and the train in every language; all four are to be recorded again whole,
so that each stays one take. Until a phrase is, the phone's voice reads it.

## Recording

- Voice Memos on an iPhone, in a quiet room, the phone a hand's width from
  your mouth. No wind, no street.
- The easy way is **one recording a language**: read the phrases down
  the column, in the order of the table, with a clear pause of two seconds
  between them. They are cut apart afterwards.
- Say each a little slower and louder than talking. It will be heard from a
  pocket, over traffic.
- Once each. The session that cuts them apart cannot listen, so it
  counts them: a phrase said twice moves every name after it along by
  one. A slip is a fresh take from the top, not the line said again.

## Where they go

Cut, trimmed of silence and levelled, each phrase is one file in
`Rattatee/Voice/`, named for its language and the first column:

```
Rattatee/Voice/en-soon.m4a
Rattatee/Voice/et-left.m4a
Rattatee/Voice/ru-keep-right.m4a
Rattatee/Voice/az-arrive.m4a
```

AAC in an `.m4a`, mono. The folder is flat because the project's
synchronised group copies every resource to the top of the bundle, where two
files called `left.m4a` would be one.

Until a file is there, that phrase is read by the phone's own voice in
English and Russian and is silent in Estonian and Azerbaijani, which iOS has
no voice for. A
language is all or nothing a sentence: "In 200 metres" recorded and "Turn
left" not is read whole by the phone, rather than in two voices.

## Adding a phrase

A new phrase is a new `Clip` in `Guide.swift`, a row here, four recordings
and a new build. A new kind of turn is also a word in the website's
`/api/route` — `TURNS` in its `functions/api/route.js` — and an installed
app is silent at a word it does not know.
