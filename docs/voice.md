# The voice: what to record

The turns of a way are said aloud in recordings of the owner's voice — see
`Rattatee/Core/Guide.swift` — and in Russian by a made one, Dmitri's. This
is the dictionary: fifteen phrases, each in English, Estonian, Russian and
Azerbaijani, sixty recordings in all.

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

**Recorded: Azerbaijani, English and Estonian, all fifteen of each**, on
2026-11-18, each language in one take; and on 2026-11-23 twenty-four of
them again, Estonian whole — see **Said again** below.

**Russian is made, not recorded.** At the owner's word on 2026-11-23 it is
said by Dmitri, an open voice for Piper (`ru_RU-dmitri-medium`), rather
than the phone's voice or a Russian speaker. Its model card gives the
recordings it learnt from as NabuCasa's `voice-datasets`, CC0, and says it
was fine-tuned from Piper's US English lessac voice, whose recordings have
a licence of their own — written for research, as far as could be told on
2026-11-23 without reaching the page. The owner knew that and chose it.
It was made with Piper 1.8.0 (`pip install piper-tts`), one phrase at a
time, `--length-scale 1.1`, each line of the Russian column ending in a
full stop and the greetings in "!" — but for `off`, which is "Вы сошли с
пути!" at `--length-scale 1.2`, since with a full stop it ran "сошли с"
into "сошлись". Then it was finished like the recordings (**Cutting**).

## Said again

On 2026-11-23 nine of the first recordings were found to have lost a
quiet sound at an edge when they were cut, three to have a stray sound or
word in them and two to say a part faintly. The owner said them again the
same day, in this order, in one memo, once each — and with them all of
Estonian, which they chose to say again whole rather than mend five of
fifteen:

| Clip | Say | What was wrong |
|---|---|---|
| `en-keep-left` | Keep left | the "ft" was cut off |
| `en-off` | You're off the way | it says "You're way off the way" |
| `en-late` | Riding late, let's go | a "huh" between the halves |
| `et-soon` | Kahesaja meetri pärast | "kahe" is swallowed |
| `et-left` | Pööra vasakule | — |
| `et-right` | Pööra paremale | "Pöö" is faint |
| `et-keep-left` | Hoia vasakule | — |
| `et-keep-right` | Hoia paremale | — |
| `et-straight` | Sõida otse | — |
| `et-around` | Pööra ümber | — |
| `et-arrive` | Oled kohal | the L was cut off |
| `et-tunnel` | Sõida tunnelisse | — |
| `et-off` | Oled teelt maas | — |
| `et-wrong-way` | Vale suund | cut at both ends |
| `et-morning` | Tere hommikust, lähme | — |
| `et-afternoon` | Tere päevast, lähme | — |
| `et-evening` | Tere õhtust, lähme | — |
| `et-late` | Liiga hilja? Lähme ikka! | a "hõõ" between the halves |
| `az-keep-right` | Sağda qal | the S was cut off |
| `az-wrong-way` | Yanlış istiqamətdə gedirsən | the end was cut off |
| `az-morning` | Sabahın xeyir, gedək | the end of *gedək* was cut off |
| `az-afternoon` | Günortan xeyir, gedək | the same, and "Gün" is faint |
| `az-evening` | Axşamın xeyir, gedək | the end of *gedək* was cut off |
| `az-late` | Gecə gəzintisi, getdik! | the end was cut off |

They were found without listening: by Whisper, an open speech recogniser,
writing down what each file says, and by where sound is still going when
a file stops. Whisper is weak in Azerbaijani and writes Estonian "õ" as
"e", so a clip not in this list is not proven right — only not shown wrong.

The new take was cut as **Cutting** says, and checked the same way: every
file now ends in the room's silence, and Whisper writes each back as its
line, near enough for its weak languages. Five were said with a stop in
the middle — "Riding late, let's go", "Hoia paremale", "Sõida
tunnelisse" and the Azerbaijani afternoon and evening — which is cut to
0.3 s, from the silence either side. Three were trimmed by hand: lip
clicks before `et-morning` and a breath before `en-late`, and the breath
out that follows `az-late` for most of a second, which is faded over
120 ms from just after the K of *getdik*. `et-late` keeps a quiet trailing
sound after "hilja?", at about a twentieth of the words' loudness; the
first take had it too, so it is taken to be how the question is said.

## Recording

- Voice Memos on an iPhone, in a quiet room, the phone a hand's width from
  your mouth. No wind, no street.
- The easy way is **one recording a language**: read the phrases down
  the column, in the order of the table, with a clear pause of two seconds
  between them. They are cut apart afterwards.
- Say each a little slower and louder than talking. It will be heard from a
  pocket, over traffic.
- Twice each is fine; the better one is kept.
- Say the last sound right out — the T of *left*, the K of *gedək*, the L
  of *kohal* — and only then stop. A sound let fade is the one the cutting
  loses.
- A greeting is one breath, with no stop at the comma: a long one there
  sounds like two phrases.
- Several languages can go in one memo, in the order of the list, with
  five seconds of silence between languages and two before stopping.

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

### Cutting

A memo is cut apart at its pauses. Each phrase is then trimmed to where its
sound first and last rises above 45 dB under its loudest moment, with 0.12 s
kept before and 0.15 s after; high-passed at 80 Hz; brought to an average of
-16.5 dB under a limiter at -1 dB; faded in over 15 ms and out over 30 ms;
and kept as mono AAC at 64 kb/s, 44.1 kHz.

The first takes were trimmed a tenth of a second either side of where a
phrase was *loud*, about 20 dB under its peak. A K, a T, an L or an S at
either end is quieter than that, so nine of them lost one — which is why
the floor is now 45 dB down.

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
