import Foundation

/// A visual language for agent cards. The picked design changes only the design
/// section of the copied agent instructions. The card rules never change with it.
enum CardDesign: String, CaseIterable, Identifiable, Sendable {
    case paperPoster
    case swiss
    case editorial
    case monoLedger
    case none

    static let defaultDesign: CardDesign = .paperPoster

    var id: String { rawValue }

    var name: String {
        switch self {
        case .paperPoster: "Paper poster"
        case .swiss: "Swiss"
        case .editorial: "Editorial"
        case .monoLedger: "Mono ledger"
        case .none: "None"
        }
    }

    var summary: String {
        switch self {
        case .paperPoster: "Warm paper, bold rules, a splash of color."
        case .swiss: "Bare grid, one red signal, nothing painted."
        case .editorial: "A broadsheet digest in a serif face."
        case .monoLedger: "A terminal readout in a mono face."
        case .none: "The agent picks its own look."
        }
    }

    /// The design section appended to the copied agent instructions.
    /// `nil` adds no section; the agent chooses its own look.
    var instructionSection: String? {
        switch self {
        case .paperPoster:
            """
            ## Design — Paper poster
            - Paint a warm paper ground and start the card with a heavy 4px ink rule.
            - Type is Helvetica Neue. Masthead: a two-line uppercase tracked title on the left, a stacked uppercase date block on the right.
            - Tabs are 16px bold sentence case. The active tab is ink with a 3px blue underline; inactive tabs are gray.
            - Color has fixed jobs. Blue marks everything interactive: tab underline, + expanders, action tags. Red-orange marks urgency only. Yellow is a highlighter for one key line. Solid blue or red full-bleed blocks are for alert-style cards only, two at most. Most cards need no blocks at all.
            - Rows: bold title, gray sentence-case sub-line, hairline separators. Sections open with a 3px ink rule and an uppercase tracked label. Use thin 2px bars for percentages and simple geometric shapes (circles, squares) for icons — never emoji.
            - Give each card one personality element that fits its job: a timeline spine with dots for a schedule, monogram stamps for senders, a geometric sun for weather, checkbox squares for tasks. Cards must feel like one family, not one template.
            - Tokens: :root{color-scheme:light dark;--paper:#f2efe6;--ink:#141310;--soft:#5d5850;--faint:#8a8478;--hair:rgba(20,19,16,.16);--track:rgba(20,19,16,.18);--blue:#2743e0;--red:#d84a24;--yellow:#ecd25c} and under prefers-color-scheme: dark {--paper:#1a1813;--ink:#f2efe6;--soft:#b8b2a3;--faint:#857f70;--hair:rgba(242,239,230,.2);--track:rgba(242,239,230,.25);--blue:#6d84ff;--red:#ff7350;--yellow:#e8cf57}. Solid blocks keep fixed backgrounds in both schemes: blue #2743e0, red #d84a24, white text.
            - Body: font 13.5px/1.4 "Helvetica Neue"; tabular numerals; padding 20px 18px 28px.
            """
        case .swiss:
            """
            ## Design — Swiss International
            - Paint nothing behind the content. No page background, no surfaces, no boxes, no pills. Structure comes from rules and the type scale only.
            - Type is Helvetica Neue with tabular numerals. Big things track tight (headline -0.02em); small labels track loose (uppercase micro-labels at +0.12 to +0.16em).
            - Three rule strengths only: 3px ink for the masthead and the closing note, 1px ink for section boundaries, a hairline between rows.
            - One accent: signal red. It marks IDs, live status, and the one thing that matters. If half the card is red, nothing is. Green and red variants exist only for good and bad deltas.
            - Masthead: uppercase 17px headline over a tracked micro-label, a red stamp on the right. Rows: 14.5px title, uppercase micro metadata line, right-aligned status column.
            - A range scale is a 1px line with end ticks, never a filled bar. Stat strips are big figures over tracked captions.
            - Tokens: :root{color-scheme:light dark;--ink:#000;--soft:#4e5155;--faint:#85888c;--rule:rgba(0,0,0,.86);--hair:rgba(0,0,0,.15);--accent:#d81f14;--pos:#07752f;--neg:#c01a12} and under prefers-color-scheme: dark {--ink:#fff;--soft:#abaeb2;--faint:#76797d;--rule:rgba(255,255,255,.86);--hair:rgba(255,255,255,.18);--accent:#ff4f42;--pos:#3ddc7f;--neg:#ff6a5e}.
            - Body: transparent background; font 14px/1.4 "Helvetica Neue"; padding 24px 18px 30px.
            """
        case .editorial:
            """
            ## Design — Editorial serif
            - A broadsheet digest. Type is ui-serif / New York / Georgia throughout, on a transparent ground with warm ink.
            - The masthead opens with a 4px double rule; the closing note repeats it. Section labels are small caps with a thin rule. Row separators are hairlines.
            - Headlines are 23px serif in sentence case. Metadata is italic, never uppercase. Times and secondary figures are italic too.
            - One accent: burgundy. It marks small-caps identifiers, urgent times, and the key phrase in the note. Everything else is ink and warm gray.
            - Keep the density of a printed digest: 16px row titles, generous line height, no icons, no bars except the 1px tick scale.
            - Tokens: :root{color-scheme:light dark;--ink:#191511;--soft:#5c5548;--faint:#8d8577;--rule:rgba(25,21,17,.8);--hair:rgba(25,21,17,.16);--accent:#9e2b25} and under prefers-color-scheme: dark {--ink:#f2ede4;--soft:#b7ad9e;--faint:#837c6f;--rule:rgba(242,237,228,.75);--hair:rgba(242,237,228,.2);--accent:#ff8f7d}.
            - Body: transparent background; font 15px/1.5 ui-serif, "New York", Georgia, serif; tabular numerals; padding 26px 20px 32px.
            """
        case .monoLedger:
            """
            ## Design — Mono ledger
            - A terminal readout. Type is ui-monospace / SF Mono everywhere, on a transparent ground.
            - Rules: 2px solid ink for the masthead and the note, 1px solid for section boundaries, 1px dashed hairlines between rows.
            - Labels are uppercase, tracked wide (+0.12 to +0.18em), and small (9 to 10px). Section labels open with an accent "//" prefix. Body text is 12.5px.
            - One accent: amber. It marks identifiers, live values, and the "//" prefixes. Nothing else is colored.
            - Everything aligns like a ledger: tabular numerals, right-aligned value columns, dotted or dashed leaders where a row needs them. No icons, no filled bars.
            - Tokens: :root{color-scheme:light dark;--ink:#0d0d0d;--soft:#52555a;--faint:#888c91;--rule:rgba(13,13,13,.85);--hair:rgba(13,13,13,.2);--accent:#9a4a00} and under prefers-color-scheme: dark {--ink:#e9e9e9;--soft:#a3a7ad;--faint:#74787e;--rule:rgba(233,233,233,.8);--hair:rgba(233,233,233,.25);--accent:#ffab24}.
            - Body: transparent background; font 12.5px/1.5 ui-monospace, "SF Mono", Menlo, monospace; padding 24px 16px 30px.
            """
        case .none:
            nil
        }
    }

    /// The same weather example rendered in this design, shown in the picker.
    var previewHTML: String {
        switch self {
        case .paperPoster:
            """
            <!doctype html><html lang="en"><head><meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1"><style>
            *{box-sizing:border-box}html,body{margin:0;padding:0;overflow-x:hidden}
            :root{color-scheme:light dark;--paper:#f2efe6;--ink:#141310;--soft:#5d5850;--faint:#8a8478;
            --hair:rgba(20,19,16,.16);--blue:#2743e0;--yellow:#ecd25c}
            @media (prefers-color-scheme:dark){:root{--paper:#1a1813;--ink:#f2efe6;--soft:#b8b2a3;
            --faint:#857f70;--hair:rgba(242,239,230,.2);--blue:#6d84ff;--yellow:#e8cf57}}
            body{background:var(--paper);color:var(--ink);border-top:4px solid var(--ink);
            padding:18px 16px 24px;font:400 13.5px/1.4 "Helvetica Neue",Helvetica,sans-serif;
            font-variant-numeric:tabular-nums}
            .top{display:flex;justify-content:space-between;gap:12px}
            h1{margin:0;font-size:17px;font-weight:800;letter-spacing:.08em;text-transform:uppercase;line-height:1.3}
            .st{font-size:9.5px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;text-align:right;line-height:1.7}
            .seg{display:flex;gap:22px;margin-top:12px;border-bottom:1px solid var(--hair)}
            .seg b{font-size:15px;padding:8px 0;border-bottom:3px solid var(--blue)}
            .seg span{font-size:15px;font-weight:700;color:var(--faint);padding:8px 0}
            .hero{display:flex;justify-content:space-between;align-items:center}
            .big{font-size:64px;font-weight:800;letter-spacing:-.05em}
            .sun{width:72px;height:72px;position:relative}
            .sun::before{content:"";position:absolute;left:0;bottom:0;width:38px;height:38px;border-radius:50%;background:var(--blue)}
            .sun::after{content:"";position:absolute;right:0;top:0;width:60px;height:60px;border-radius:50%;background:var(--yellow)}
            .k{display:flex;gap:16px;font-size:10px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--soft)}
            .lbl{margin-top:16px;border-top:3px solid var(--ink);border-bottom:1px solid var(--hair);
            padding:7px 0 6px;font-size:10px;font-weight:800;letter-spacing:.14em;text-transform:uppercase}
            .rw{display:flex;justify-content:space-between;gap:10px;padding:8px 0;border-bottom:1px solid var(--hair)}
            .rw b{font-size:13px}.rw i{font-style:normal;color:var(--soft);font-size:11px}
            .rw .t{font-weight:700}
            </style></head><body>
            <div class="top"><h1>New York<br>10021</h1><div class="st">Thursday<br>August 6</div></div>
            <div class="seg"><b>Today</b><span>This week</span></div>
            <div class="hero"><div class="big">78&deg;</div><div class="sun"></div></div>
            <div class="k"><span>Feels <b>82&deg;</b></span><span>High <b>84&deg;</b></span><span>Low <b>68&deg;</b></span></div>
            <div class="lbl">Hour by hour</div>
            <div class="rw"><span class="t">9A</span><b>Partly sunny</b><i>79&deg; &middot; 4%</i></div>
            <div class="rw"><span class="t">1P</span><b>Building clouds</b><i>84&deg; &middot; 10%</i></div>
            <div class="rw"><span class="t">5P</span><b>Thunderstorms</b><i>80&deg; &middot; 70%</i></div>
            </body></html>
            """
        case .swiss:
            """
            <!doctype html><html lang="en"><head><meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1"><style>
            *{box-sizing:border-box}html,body{margin:0;padding:0;overflow-x:hidden;background:transparent}
            :root{color-scheme:light dark;--ink:#000;--soft:#4e5155;--faint:#85888c;
            --rule:rgba(0,0,0,.86);--hair:rgba(0,0,0,.15);--accent:#d81f14}
            @media (prefers-color-scheme:dark){:root{--ink:#fff;--soft:#abaeb2;--faint:#76797d;
            --rule:rgba(255,255,255,.86);--hair:rgba(255,255,255,.18);--accent:#ff4f42}}
            body{color:var(--ink);padding:20px 16px 24px;font:400 14px/1.4 "Helvetica Neue",Helvetica,sans-serif;
            font-variant-numeric:tabular-nums}
            .top{display:flex;justify-content:space-between;gap:12px;border-top:3px solid var(--rule);padding-top:7px}
            h1{margin:0;font-size:16px;font-weight:700;letter-spacing:-.02em;text-transform:uppercase}
            .loc{margin-top:3px;font-size:9.5px;font-weight:500;letter-spacing:.15em;text-transform:uppercase;color:var(--faint)}
            .st{font-size:9.5px;font-weight:700;letter-spacing:.14em;text-transform:uppercase;color:var(--accent);text-align:right}
            .big{display:flex;align-items:baseline;gap:8px;margin-top:18px}
            .big b{font-size:56px;font-weight:700;letter-spacing:-.055em;line-height:.9}
            .big i{font-style:normal;font-size:11px;font-weight:700;letter-spacing:.14em;text-transform:uppercase;color:var(--faint)}
            .lbl{margin-top:18px;padding-bottom:4px;border-bottom:1px solid var(--rule);
            font-size:9px;font-weight:700;letter-spacing:.16em;text-transform:uppercase;color:var(--faint)}
            .rw{display:grid;grid-template-columns:38px 1fr 56px;gap:10px;padding:9px 0;border-bottom:1px solid var(--hair)}
            .dy{font-size:9.5px;font-weight:700;letter-spacing:.13em;text-transform:uppercase}
            .c{font-size:12.5px;font-weight:500;color:var(--soft)}
            .r{text-align:right;font-size:9.5px;font-weight:700;letter-spacing:.08em}
            .r b{color:var(--accent)}
            </style></head><body>
            <div class="top"><div><h1>Weather</h1><div class="loc">Upper East Side</div></div><div class="st">70% rain</div></div>
            <div class="big"><b>78&deg;</b><i>Feels 82 &middot; humidity 74%</i></div>
            <div class="lbl">7-day &middot; range 64&ndash;88</div>
            <div class="rw"><span class="dy">Thu</span><span class="c">T-storms after 3 PM</span><span class="r"><b>84 / 68</b></span></div>
            <div class="rw"><span class="dy">Fri</span><span class="c">Morning showers</span><span class="r">81 / 66</span></div>
            <div class="rw"><span class="dy">Sat</span><span class="c">Partly cloudy</span><span class="r">79 / 64</span></div>
            <div class="rw"><span class="dy">Sun</span><span class="c">Sunny</span><span class="r">83 / 66</span></div>
            </body></html>
            """
        case .editorial:
            """
            <!doctype html><html lang="en"><head><meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1"><style>
            *{box-sizing:border-box}html,body{margin:0;padding:0;overflow-x:hidden;background:transparent}
            :root{color-scheme:light dark;--ink:#191511;--soft:#5c5548;--faint:#8d8577;
            --rule:rgba(25,21,17,.8);--hair:rgba(25,21,17,.16);--accent:#9e2b25}
            @media (prefers-color-scheme:dark){:root{--ink:#f2ede4;--soft:#b7ad9e;--faint:#837c6f;
            --rule:rgba(242,237,228,.75);--hair:rgba(242,237,228,.2);--accent:#ff8f7d}}
            body{color:var(--ink);padding:20px 18px 26px;font:400 15px/1.5 ui-serif,"New York",Georgia,serif;
            font-variant-numeric:tabular-nums}
            .top{display:flex;justify-content:space-between;gap:12px;border-top:4px double var(--rule);padding-top:9px}
            h1{margin:0;font-size:21px;font-weight:700;line-height:1.1}
            .loc{margin-top:3px;font-size:12px;font-style:italic;color:var(--faint)}
            .st{font-size:11.5px;font-style:italic;color:var(--accent);text-align:right}
            .big{display:flex;align-items:baseline;gap:9px;margin-top:16px}
            .big b{font-size:50px;font-weight:600;letter-spacing:-.02em;line-height:.95}
            .big i{font-size:12.5px;font-style:italic;color:var(--soft)}
            .lbl{margin-top:16px;padding-bottom:4px;border-bottom:1px solid var(--rule);
            font-size:11px;font-weight:600;font-variant-caps:all-small-caps;letter-spacing:.14em;color:var(--faint)}
            .rw{display:grid;grid-template-columns:40px 1fr 54px;gap:10px;padding:9px 0;border-bottom:1px solid var(--hair)}
            .dy{font-size:11px;font-weight:700;font-variant-caps:all-small-caps;letter-spacing:.12em}
            .c{font-size:13px;font-style:italic;color:var(--soft)}
            .r{text-align:right;font-size:12px;font-style:italic;color:var(--soft)}
            .r b{color:var(--accent);font-weight:600}
            </style></head><body>
            <div class="top"><div><h1>Weather</h1><div class="loc">Upper East Side &middot; 7:45 AM</div></div><div class="st">70% rain</div></div>
            <div class="big"><b>78&deg;</b><i>feels 82 &middot; humidity 74%</i></div>
            <div class="lbl">The week ahead</div>
            <div class="rw"><span class="dy">Thu</span><span class="c">T-storms after 3 PM</span><span class="r"><b>84 / 68</b></span></div>
            <div class="rw"><span class="dy">Fri</span><span class="c">Morning showers</span><span class="r">81 / 66</span></div>
            <div class="rw"><span class="dy">Sat</span><span class="c">Partly cloudy</span><span class="r">79 / 64</span></div>
            <div class="rw"><span class="dy">Sun</span><span class="c">Sunny</span><span class="r">83 / 66</span></div>
            </body></html>
            """
        case .monoLedger:
            """
            <!doctype html><html lang="en"><head><meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1"><style>
            *{box-sizing:border-box}html,body{margin:0;padding:0;overflow-x:hidden;background:transparent}
            :root{color-scheme:light dark;--ink:#0d0d0d;--soft:#52555a;--faint:#888c91;
            --rule:rgba(13,13,13,.85);--hair:rgba(13,13,13,.2);--accent:#9a4a00}
            @media (prefers-color-scheme:dark){:root{--ink:#e9e9e9;--soft:#a3a7ad;--faint:#74787e;
            --rule:rgba(233,233,233,.8);--hair:rgba(233,233,233,.25);--accent:#ffab24}}
            body{color:var(--ink);padding:20px 14px 24px;font:400 12.5px/1.5 ui-monospace,"SF Mono",Menlo,monospace;
            font-variant-numeric:tabular-nums}
            .top{display:flex;justify-content:space-between;gap:12px;border-top:2px solid var(--rule);padding-top:8px}
            h1{margin:0;font-size:14px;font-weight:700;letter-spacing:.06em;text-transform:uppercase}
            .loc{margin-top:3px;font-size:9px;font-weight:500;letter-spacing:.12em;text-transform:uppercase;color:var(--faint)}
            .st{font-size:9px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--accent);text-align:right}
            .big{display:flex;align-items:baseline;gap:8px;margin-top:16px}
            .big b{font-size:44px;font-weight:700;letter-spacing:-.04em;line-height:.95}
            .big i{font-style:normal;font-size:9px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--faint)}
            .lbl{margin-top:16px;padding-bottom:4px;border-bottom:1px solid var(--rule);
            font-size:8.5px;font-weight:700;letter-spacing:.18em;text-transform:uppercase;color:var(--faint)}
            .lbl s{text-decoration:none;color:var(--accent)}
            .rw{display:grid;grid-template-columns:36px 1fr 54px;gap:10px;padding:8px 0;border-bottom:1px dashed var(--hair)}
            .dy{font-size:9.5px;font-weight:700;letter-spacing:.1em;text-transform:uppercase}
            .c{font-size:11px;color:var(--soft)}
            .r{text-align:right;font-size:10px;font-weight:700}
            .r b{color:var(--accent)}
            </style></head><body>
            <div class="top"><div><h1>Weather</h1><div class="loc">Upper East Side</div></div><div class="st">70% rain</div></div>
            <div class="big"><b>78&deg;</b><i>Feels 82 &middot; hum 74%</i></div>
            <div class="lbl"><s>//</s> 7-day &middot; range 64&ndash;88</div>
            <div class="rw"><span class="dy">Thu</span><span class="c">T-storms after 3 PM</span><span class="r"><b>84/68</b></span></div>
            <div class="rw"><span class="dy">Fri</span><span class="c">Morning showers</span><span class="r">81/66</span></div>
            <div class="rw"><span class="dy">Sat</span><span class="c">Partly cloudy</span><span class="r">79/64</span></div>
            <div class="rw"><span class="dy">Sun</span><span class="c">Sunny</span><span class="r">83/66</span></div>
            </body></html>
            """
        case .none:
            """
            <h2>Weather — Thu Aug 6</h2>
            <p><b>78°</b> now, feels 82°. High 84°, low 68°. Thunderstorms after 3 PM, 70% chance.</p>
            <ul>
              <li>Thu — T-storms after 3 PM, 84/68</li>
              <li>Fri — Morning showers, 81/66</li>
              <li>Sat — Partly cloudy, 79/64</li>
              <li>Sun — Sunny, 83/66</li>
            </ul>
            <p>The agent chooses its own layout and style.</p>
            """
        }
    }
}
