# The voice: what to record

The turns of a way are said aloud in recordings of the owner's voice — see
`Rattatee/Core/Guide.swift`. This is the dictionary: seventeen phrases, each in
English, Estonian, Russian and Azerbaijani, sixty-eight recordings in all.

**The words are the code's.** Each phrase is one string in
`Rattatee/Seed/strings.json`, under the key in the second column, and the
recording says that string word for word: the phone's own voice reads the
same string wherever a recording is missing, so a language says the same
thing before it is recorded and after. The tables below are those strings,
and the strings check in `.github/workflows/ios.yml` fails when one of them
and strings.json part. A figure is said as words — **In 200 metres** is
"In two hundred metres".

The app joins them. Before a corner it plays **In 200 metres** and then the
turn; at the corner it plays the turn alone. So each phrase is recorded on
its own, as a whole sentence, with no "and then".

A tunnel is said like a turn, at its entrance. Where it starts just past
a corner — the Veerenni path under the railway turns left into it — the
two are played one after the other, **Turn left** then **Enter the
tunnel**, so the second does not cut the first off.

Off the way, the voice reassures as well as warns, at the owner's word: a
rider with the phone in a pocket cannot see that the app is already finding
a new way, so **You're off the way** and **Going the wrong way** each say
that one will be found, and when it comes, **New way found** says it was.
Those two have a full stop in the middle: keep the pause there as short as
a comma's, since the long pauses are where the take is cut.

| File | Key | English (`en-`) | Estonian (`et-`) | Russian (`ru-`) | Azerbaijani (`az-`) |
|---|---|---|---|---|---|
| `soon` | `turnSoon` | In 200 metres | 200 meetri pärast | Через 200 метров | 200 metrdən sonra |
| `left` | `turnLeft` | Turn left | Pööra vasakule | Поверните налево | Sola dön |
| `right` | `turnRight` | Turn right | Pööra paremale | Поверните направо | Sağa dön |
| `keep-left` | `turnKeepLeft` | Keep left | Hoia vasakule | Держитесь левее | Solda qal |
| `keep-right` | `turnKeepRight` | Keep right | Hoia paremale | Держитесь правее | Sağda qal |
| `straight` | `turnStraight` | Go straight | Sõida otse | Езжайте прямо | Düz get |
| `around` | `turnAround` | Turn around | Pööra ümber | Развернитесь | Geri dön |
| `arrive` | `turnArrive` | You have arrived | Oled kohal | Вы на месте | Çatdın |
| `tunnel` | `turnTunnel` | Enter the tunnel | Sõida tunnelisse | Въезжайте в тоннель | Tunelə gir |
| `off` | `clipOff` | You're off the way. Don't worry, we'll find a new one | Oled teelt maas. Ära muretse, leiame uue | Вы сошли с пути. Не волнуйтесь, мы найдём новый | Yoldan çıxdın. Narahat olma, yenisini tapacağıq |
| `wrong-way` | `clipWrongWay` | Going the wrong way. Turn around, or we'll find a new one | Vale suund. Pööra ümber või leiame uue | Вы едете не в ту сторону. Развернитесь, или мы найдём новый путь | Yanlış istiqamətdə gedirsən. Geri dön, ya da yenisini tapacağıq |
| `new-way` | `clipNewWay` | New way found, let's go | Uus tee leitud, lähme | Новый путь найден, поехали | Yeni yol tapıldı, gedək |
| `train` | `clipTrain` | Your train leaves from here | Sinu rong läheb siit | Ваш поезд отходит отсюда | Qatarın buradan gedir |
The train is said once, on the platform of a way by train, where the
ride to the station would otherwise have said "You have arrived". It
cannot say which train or when — a recording only says what was recorded
— so the row on screen does: *Train RE34 at 09:31 to Kitseküla*. Until
2026-11-23 the phone's own voice read that row, which in Estonian and
Azerbaijani was nothing at all.

## The greeting

When a new ride starts — not on a resume — one line is said for the time
of day on the phone's clock (`Guide.greet`), before any turn. A turn that
comes while it is still playing cuts it off.

| File | When | Key | English (`en-`) | Estonian (`et-`) | Russian (`ru-`) | Azerbaijani (`az-`) |
|---|---|---|---|---|---|---|
| `morning` | 05:00–11:59 | `greetMorning` | Good morning, let's go | Tere hommikust, lähme | Доброе утро, поехали | Sabahın xeyir, gedək |
| `afternoon` | 12:00–17:59 | `greetAfternoon` | Good afternoon, let's go | Tere päevast, lähme | Добрый день, поехали | Günortan xeyir, gedək |
| `evening` | 18:00–21:59 | `greetEvening` | Good evening, let's go | Tere õhtust, lähme | Добрый вечер, поехали | Axşamın xeyir, gedək |
| `late` | 22:00–04:59 | `greetLate` | Riding late, let's go | Liiga hilja? Lähme ikka! | Поздновато, поехали | Gecə gəzintisi, getdik! |
There is nothing for a roundabout, on purpose: the app is for a bike, which
is mostly on the path beside one. Where the way does go through one, the row
on screen says so — "Roundabout, exit 2" — and the voice says nothing.

The wording is yours to change, and the string changes first: put the
words you mean to say into strings.json, in this table with them, and
record that. A recording that says something else is a voice that is not
according to the code.

**Recorded so far: Azerbaijani, English and Estonian, the fifteen phrases
before the train**, on 2026-11-18, each language in one take, when off the
way and the wrong way were the warning alone. Russian is still to do, and
in every language the train, the new way and the two reassurances; all
four are to be recorded again whole, so that each stays one take. Until a
phrase is, the phone's voice reads its string, and the recordings already
made of off the way and the wrong way say only their first sentence.

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

Until a file is there, that phrase's string is read by the phone's own
voice in English and Russian and is silent in Estonian and Azerbaijani,
which iOS has no voice for. A language is all or nothing a sentence: "In
200 metres" recorded and "Turn left" not is read whole by the phone,
rather than in two voices.

## Adding a phrase

A new phrase is a new `Clip` in `Guide.swift` with its string in
`Clip.words`, the string in strings.json in all four languages, a row here,
four recordings and a new build. A new kind of turn is also a word in the website's
`/api/route` — `TURNS` in its `functions/api/route.js` — and an installed
app is silent at a word it does not know.
