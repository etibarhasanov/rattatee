# The voice: what to record

The turns of a way are said aloud in recordings of the owner's voice — see
`Rattatee/Core/Guide.swift`. This is the dictionary: seventeen phrases, each in
English, Estonian, Russian and Azerbaijani, sixty-eight recordings in all.

The app joins them. Before a corner it plays **In 200 metres** and then the
turn; at the corner it plays the turn alone. So each phrase is recorded on
its own, as a whole sentence, with no "and then".

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
| `off` | You're off the way | Oled teelt kõrvale kaldunud | Вы сошли с пути | Yoldan çıxdın |
| `wrong-way` | Going the wrong way | Sõidad vales suunas | Вы едете не в ту сторону | Yanlış istiqamətdə gedirsən |
| `back-on` | Back on the way | Oled jälle teel | Вы снова на пути | Yola qayıtdın |
| `new-way` | Found a new way | Leidsin uue tee | Новый путь найден | Yeni yol tapıldı |
| `finish` | Ride over, well done | Sõit läbi, tubli | Поездка окончена, молодец | Sürüş bitdi, afərin |

`back-on` is said when a rider who was told `off` or `wrong-way` is on the
way again by themselves (`Guide.back`), so the warning has an end;
`new-way` when the app has found a new way instead (`Guide.found`), and its
first turn follows as any way's does; `finish` when Finish is pressed, after
the radio has stopped (`Guide.farewell`), with or without somewhere to go.
Their words for the phone's voice are `voiceBackOn`, `voiceNewWay` and
`voiceFinish` in `Rattatee/Seed/strings.json`.

## The greeting

When a new ride starts — not on a resume — one line is said for the time
of day on the phone's clock (`Guide.greet`), before any turn. A turn that
comes while it is still playing cuts it off.

| File | When | English (`en-`) | Estonian (`et-`) | Russian (`ru-`) | Azerbaijani (`az-`) |
|---|---|---|---|---|---|
| `morning` | 05:00–11:59 | Good morning, let's go | Tere hommikust, lähme | Доброе утро, поехали | Sabahın xeyir, gedək |
| `afternoon` | 12:00–17:59 | Good afternoon, let's go | Tere päevast, lähme | Добрый день, поехали | Günortan xeyir, gedək |
| `evening` | 18:00–21:59 | Good evening, let's go | Tere õhtust, lähme | Добрый вечер, поехали | Axşamın xeyir, gedək |
| `late` | 22:00–04:59 | Riding late, let's go | Hilja juba, lähme | Поздновато, поехали | Gec saatdır, gedək |

The words the phone reads until these are recorded are the `greet…` keys
in `Rattatee/Seed/strings.json`; change them there too if you say it
differently.

There is nothing for a roundabout, on purpose: the app is for a bike, which
is mostly on the path beside one. Where the way does go through one, the row
on screen says so — "Roundabout, exit 2" — and the voice says nothing.

The wording is yours to change: say a phrase the way you would say it, and
it is right. Only the meaning has to match the file.

**Recorded so far: Azerbaijani and English**, the first eight of each, on
2026-11-17. Fifty-two are left, and the sheet below is all of them. Until
they are recorded the phone's voice reads them in English and Russian.

## The sheet: what is left, in reading order

One take a language, top to bottom, two seconds between lines. The file
name is in brackets so whoever cuts the take knows what each line becomes.

**English — nine left**

1. You're off the way *(off)*
2. Going the wrong way *(wrong-way)*
3. Back on the way *(back-on)*
4. Found a new way *(new-way)*
5. Ride over, well done *(finish)*
6. Good morning, let's go *(morning)*
7. Good afternoon, let's go *(afternoon)*
8. Good evening, let's go *(evening)*
9. Riding late, let's go *(late)*

**Azerbaijani — nine left**

1. Yoldan çıxdın *(off)*
2. Yanlış istiqamətdə gedirsən *(wrong-way)*
3. Yola qayıtdın *(back-on)*
4. Yeni yol tapıldı *(new-way)*
5. Sürüş bitdi, afərin *(finish)*
6. Sabahın xeyir, gedək *(morning)*
7. Günortan xeyir, gedək *(afternoon)*
8. Axşamın xeyir, gedək *(evening)*
9. Gec saatdır, gedək *(late)*

**Estonian — all seventeen**

1. Kahesaja meetri pärast *(soon)*
2. Pööra vasakule *(left)*
3. Pööra paremale *(right)*
4. Hoia vasakule *(keep-left)*
5. Hoia paremale *(keep-right)*
6. Sõida otse *(straight)*
7. Pööra ümber *(around)*
8. Oled kohal *(arrive)*
9. Oled teelt kõrvale kaldunud *(off)*
10. Sõidad vales suunas *(wrong-way)*
11. Oled jälle teel *(back-on)*
12. Leidsin uue tee *(new-way)*
13. Sõit läbi, tubli *(finish)*
14. Tere hommikust, lähme *(morning)*
15. Tere päevast, lähme *(afternoon)*
16. Tere õhtust, lähme *(evening)*
17. Hilja juba, lähme *(late)*

**Russian — all seventeen**

1. Через двести метров *(soon)*
2. Поверните налево *(left)*
3. Поверните направо *(right)*
4. Держитесь левее *(keep-left)*
5. Держитесь правее *(keep-right)*
6. Езжайте прямо *(straight)*
7. Развернитесь *(around)*
8. Вы на месте *(arrive)*
9. Вы сошли с пути *(off)*
10. Вы едете не в ту сторону *(wrong-way)*
11. Вы снова на пути *(back-on)*
12. Новый путь найден *(new-way)*
13. Поездка окончена, молодец *(finish)*
14. Доброе утро, поехали *(morning)*
15. Добрый день, поехали *(afternoon)*
16. Добрый вечер, поехали *(evening)*
17. Поздновато, поехали *(late)*

Cross a line off here, in the same commit as its file, so this stays the
list of what is left.

## Recording

- Voice Memos on an iPhone, in a quiet room, the phone a hand's width from
  your mouth. No wind, no street.
- The easy way is **one recording a language**: read the phrases down
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
