;===================================================
; T-Junction ABM with 4-phase signals + simple NSGA-II stub
; Added: per-lane random-car speed plotting
; NOTE: In the Interface, add a plot named:
;   1) "Car Count Per Lane"   (already used by your model)
;   2) "Lane Speeds (random cars)"  (new, for speed traces)
;===================================================

globals [
  lane-start-locations
  traffic-light-timer
  nsga2-pop
  traffic-light-phase        ;; "phase1" .. "phase4"
  red-duration               ;; ticks red lasts (optimized)
  green-duration             ;; ticks green lasts (optimized)

  ;; (declared but unused per-lane durations kept here for compatibility)
  green-duration-phase1
  green-duration-phase2
  green-duration-phase3
  green-duration-phase4
  red-duration-phase1
  red-duration-phase2
  red-duration-phase3
  red-duration-phase4

  traffic-light-cycle-count  ;; completed-cycle counter
  waiting-times

  ;; NEW for speed plotting
  lane-names                 ;; ["lane-1" ...]
  tracked-lane-who           ;; list of who-ids per lane (or -1 if none tracked yet)
]

turtles-own [
  speed
  destination
  action
  previous-meaning
  target-heading
]

patches-own[
  meaning
  traffic-light-state   ;; "red", "green", "yellow", or ""
]

breed [cars car]
breed [traffic-lights traffic-light]

cars-own [
  speed
  destination
  action
]

;=====================
; SETUP / GO
;=====================

to setup
  ca
  draw-road
  init-lane-start-locations
  set waiting-times []
  set traffic-light-timer 0
  set red-duration 260
  set green-duration 800
  set traffic-light-phase "phase1"
  set traffic-light-cycle-count 0

  ;; NEW: initialize lane names + tracking array
  set lane-names ["lane-1" "lane-2" "lane-3" "lane-4" "lane-5" "lane-7"]
  set tracked-lane-who n-values length lane-names [ -1 ]

  setup-traffic-lights
  reset-ticks
  clear-output
  clear-all-plots
  place-random-cars 0
  ;show-coordinates-with-dots
end

to go
  if ticks >= 18000 [ stop ]

  spawn-cars
  update-traffic-lights
  move-cars

  plot-car-counts                 ;; existing per-lane counts
  ;;plot-waiting-time-tick        ;; optional waiting-time plot
  plot-lane-speed-samples         ;; NEW: per-lane random-car speeds

  tick

  if traffic-light-cycle-count > 0 and traffic-light-cycle-count mod 5 = 0 [
    nsga2-optimize
    set traffic-light-cycle-count 0
  ]
end

;=====================
; DRAWING ROAD / LANES
;=====================

to draw-line [start-x start-y direction line-color gap len]
  create-turtles 1 [
    setxy start-x start-y
    hide-turtle
    set color line-color
    set heading direction
    let steps len
    while [steps > 0] [
      pen-up
      forward gap
      pen-down
      forward (1 - gap)
      set steps steps - 1
    ]
    die
  ]
end

to draw-road
  ask patches [
    set pcolor white - 2
    set meaning "blank"
  ]

  ;; Main vertical road border
  ask patches with [abs pxcor <= 4 and pycor <= 11 and pycor >= -18] [
    set pcolor brown + 1
    set meaning "road-main-vertical"
  ]

  ;; Main horizontal road border
  ask patches with [pycor >= 3 and pycor <= 11 and abs pxcor <= 30] [
    set pcolor brown + 1
    set meaning "road-horizontal-top"
  ]

  ;; Horizontal roads
  ask patches with [pycor >= 4 and pycor <= 10 and abs pxcor <= 30] [
    set pcolor gray
  ]

  ;; Vertical roads
  ask patches with [abs pxcor <= 3 and pycor <= 10 and pycor >= -18] [
    set pcolor gray
  ]

  ;; Junction area
  ask patches with [pycor >= 4 and pycor <= 10 and abs pxcor <= 3] [
    set pcolor gray - 1
    set meaning "junction"
  ]

  ;; Lane markings
  draw-line -31 7 90 white 0 27
  draw-line -31 9 90 white 0.5 27
  draw-line 3 5 90 white 0.5 28
  draw-line 4 7 90 white 0 28
  draw-line -1.0 -18 0 white 0.5 21
  draw-line 1.5 -18 0 white 0 21
  draw-line -29 5 90 white 0.5 25

  ;; Mark lanes
  ask patches with [pxcor = -2] [ set meaning "lane-4" ]
  ask patches with [pxcor = 0]  [ set meaning "lane-5" ]
  ask patches with [pycor = 4]  [ set meaning "lane-3" ]
  ask patches with [pycor = 8]  [ set meaning "lane-2" ]
  ask patches with [pxcor = 2]  [ set meaning "lane-6" ]
  ask patches with [pycor = 10] [ set meaning "lane-1" ]
  ask patches with [pycor = 6]  [ set meaning "lane-7" ]
end

;=====================
; CARS
;=====================

to place-random-cars [num-cars-per-lane]
  let lane-list ["lane-1" "lane-2" "lane-3" "lane-4" "lane-5" "lane-7"]
  foreach lane-list [lane-name ->
    let lane-patches patches with [meaning = lane-name and not any? turtles-here]
    let patches-to-use n-of (min list num-cars-per-lane (count lane-patches)) lane-patches
    ask patches-to-use [
      sprout-cars 1 [
        set speed 0.05
        set destination one-of ["left" "right" "straight"]
        set action "moving"
        set previous-meaning [meaning] of patch-here
        if meaning = "lane-1" [ set heading 90 ]
        if meaning = "lane-2" [ set heading 90 ]
        if meaning = "lane-3" [ set heading 270 ]
        if meaning = "lane-4" [ set heading 0 ]
        if meaning = "lane-5" [ set heading 0 ]
        if meaning = "lane-7" [ set heading 270 ]
      ]
    ]
  ]
end

to move-cars
  ask cars [
    let current-meaning [meaning] of patch-here
    let patch-in-front patch-ahead 1
    let car-ahead nobody
    let traffic-light-ahead nobody

    if patch-in-front != nobody [
      set car-ahead one-of cars-on patch-in-front
      set traffic-light-ahead one-of traffic-lights-on patch-in-front
    ]

    let need-to-stop? false
    if traffic-light-ahead != nobody and [traffic-light-state] of traffic-light-ahead = "red" [
      set need-to-stop? true
    ]
    if car-ahead != nobody and [speed] of car-ahead < 0.1 [
      set need-to-stop? true
    ]

    ifelse need-to-stop? [ set speed 0 ] [ set speed 0.1 ]

    ifelse action = "turning" [
      let heading_diff (target-heading - heading + 360) mod 360
      ifelse heading_diff < 180 [
        set heading (heading + 5) mod 360
      ] [
        set heading (heading - 5) mod 360
      ]
      fd speed * 0.5
      let angle_diff abs ((heading - target-heading + 360) mod 360)
      if angle_diff < 5 [
        set heading target-heading
        set action "moving"
      ]
    ] [
      fd speed
    ]

    ;; remove out of bounds
    if (previous-meaning = "lane-1" and xcor > 29) or
       (previous-meaning = "lane-3" and xcor < -30) or
       (previous-meaning = "lane-7" and xcor < -30) or
       (previous-meaning = "lane-4" and ycor > 11) or
       (previous-meaning = "lane-5" and ycor > 11) or
       (previous-meaning = "lane-6" and ycor < -16) [
      die
    ]

    ;; turning logic
    if action != "turning" and previous-meaning = "lane-4" and current-meaning = "lane-3" [
      set action "turning"
      set target-heading (heading - 90) mod 360
    ]
    if action != "turning" and previous-meaning = "lane-5" and current-meaning = "lane-1" [
      set action "turning"
      set target-heading (heading + 90) mod 360
    ]
    if action != "turning" and previous-meaning = "lane-3" and current-meaning = "lane-6" [
      set action "turning"
      set target-heading (heading - 90) mod 360
    ]
    if action != "turning" and previous-meaning = "lane-2" and current-meaning = "lane-6" [
      set action "turning"
      set target-heading (heading + 90) mod 360
    ]

    set previous-meaning current-meaning
  ]
end

;=====================
; SPAWNING
;=====================

to init-lane-start-locations
  set lane-start-locations [
    ["lane-1" -30 10 90 30 0]
    ["lane-2" -30 8  90 50 0]
    ["lane-3"  30 4  270 30 0]
    ["lane-4"  -2 -16 0 35 0]
    ["lane-5"   0 -16 0 45 0]
    ["lane-7"  30 6  270 30 0]
  ]
end

to spawn-cars
  let new-lane-starts []
  foreach lane-start-locations [ lane ->
    let lane-name     item 0 lane
    let x             item 1 lane
    let y             item 2 lane
    let lane-heading  item 3 lane
    let interval      item 4 lane
    let ticks-since   item 5 lane

    if ticks-since >= interval [
      ask patch x y [
        if not any? turtles-here [
          sprout-cars 1 [
            set speed 0.1
            set destination one-of ["left" "right" "straight"]
            set action "moving"
            set previous-meaning [meaning] of patch-here
            set heading lane-heading
          ]
          set ticks-since 0
        ]
      ]
    ]
    set ticks-since ticks-since + 1
    set new-lane-starts lput (list lane-name x y lane-heading interval ticks-since) new-lane-starts
  ]
  set lane-start-locations new-lane-starts
end

;=====================
; OPTIONAL LABELS / WAIT TIME
;=====================

to show-coordinates-with-dots
  ask patches [ set plabel "" ]
  ask patches with [(pxcor mod 5 = 0) and (pycor mod 5 = 0)] [
    set plabel (word "(" pxcor ", " pycor ")")
    set plabel-color black
    set pcolor gray - 1
  ]
end

to plot-waiting-time-tick
  let avg-wait 0
  if any? cars [
    set avg-wait mean [ifelse-value speed = 0 [1] [0]] of cars
  ]
  set-current-plot "Average Waiting Time"
  set-current-plot-pen "default"
  plotxy ticks avg-wait
end

;=====================
; TRAFFIC LIGHTS
;=====================

to setup-traffic-lights
  ask traffic-lights [ die ]
  ask patches [ set traffic-light-state "" ]

  create-traffic-lights 1 [ set shape "circle" set size 1.5 setxy  0  4 set color red set traffic-light-state "red" ]
  create-traffic-lights 1 [ set shape "circle" set size 1.5 setxy  3  4 set color red set traffic-light-state "red" ]
  create-traffic-lights 1 [ set shape "circle" set size 1.5 setxy -3  8 set color red set traffic-light-state "red" ]
  create-traffic-lights 1 [ set shape "circle" set size 1.5 setxy -3 10 set color red set traffic-light-state "red" ]
  create-traffic-lights 1 [ set shape "circle" set size 1.5 setxy  3  6 set color red set traffic-light-state "red" ]
end

to update-traffic-lights
  set traffic-light-timer traffic-light-timer + 1

  if traffic-light-phase = "phase1" [
    if traffic-light-timer >= green-duration [
      set traffic-light-phase "phase2"
      set traffic-light-timer 0
    ]
    ask traffic-lights with [pycor = 10 or pycor = 8] [
      set traffic-light-state "green"
      set color green
    ]
    ask traffic-lights with [not (pycor = 10 or pycor = 8)] [
      set traffic-light-state "red"
      set color red
    ]
  ]

  if traffic-light-phase = "phase2" [
    if traffic-light-timer >= green-duration [
      set traffic-light-phase "phase3"
      set traffic-light-timer 0
    ]
    ask traffic-lights with [pxcor = 0 or pxcor = -2 or pycor = 4] [
      set traffic-light-state "green"
      set color green
    ]
    ask traffic-lights with [not (pxcor = 0 or pxcor = -2 or pycor = 4)] [
      set traffic-light-state "red"
      set color red
    ]
  ]

  if traffic-light-phase = "phase3" [
    if traffic-light-timer >= green-duration [
      set traffic-light-phase "phase4"
      set traffic-light-timer 0
    ]
    ask traffic-lights with [pycor = 4] [
      set traffic-light-state "green"
      set color green
    ]
    ask traffic-lights with [not (pycor = 4)] [
      set traffic-light-state "red"
      set color red
    ]
  ]

  if traffic-light-phase = "phase4" [
    if traffic-light-timer >= green-duration [
      set traffic-light-phase "phase1"
      set traffic-light-timer 0
      set traffic-light-cycle-count traffic-light-cycle-count + 1
    ]
    ask traffic-lights with [pycor = 10 or (pycor = 4 and pxcor = 3) or pycor = 6] [
      set traffic-light-state "green"
      set color green
    ]
    ask traffic-lights with [not (pycor = 10 or (pycor = 4 and pxcor = 3) or pycor = 6)] [
      set traffic-light-state "red"
      set color red
    ]
  ]
end

;=====================
; NSGA-II (very simplified/stub)
;=====================

to nsga2-optimize
  ;; initialize population if empty: 6 candidates [R, G]
  if not is-list? nsga2-pop [
    set nsga2-pop n-values 6 [list (random 600 + 200) (random 600 + 200)]
  ]

  ;; evaluate objectives: [candidate avg-wait queue-length]
  let fits []
  foreach nsga2-pop [cand ->
    let r item 0 cand
    let g item 1 cand
    set red-duration r
    set green-duration g

    ;; WARNING: calling go from here advances the model and may re-enter optimizer
    ;; (kept as in your original code)
    repeat 200 [ go ]

    let avg-wait mean [ifelse-value speed = 0 [1] [0]] of cars
    let qlen count cars with [speed = 0]
    set fits lput (list cand avg-wait qlen) fits
  ]

  ;; fast non-dominated sorting (two-objective)
  let fronts []
  let remaining fits
  while [length remaining > 0] [
    let nd []
    foreach remaining [f ->
      let dominated? false
      foreach remaining [g ->
        if g != f [
          if (item 1 g <= item 1 f) and (item 2 g <= item 2 f) and
             ((item 1 g < item 1 f) or (item 2 g < item 2 f)) [
            set dominated? true
          ]
        ]
      ]
      if not dominated? [ set nd lput f nd ]
    ]
    set fronts lput nd fronts

    let new-remaining []
    foreach remaining [r -> if not member? r nd [ set new-remaining lput r new-remaining ]]
    set remaining new-remaining
  ]

  ;; collect new population (greedy by sum of objectives within each front)
  let newpop []
  foreach fronts [front ->
    let sorted sort-by [[a b] -> (item 1 a + item 2 a) < (item 1 b + item 2 b)] front
    set newpop sentence newpop map [a -> item 0 a] sorted
    if length newpop >= 6 [ stop ]
  ]

  ;; mutation (bounded jitter)
  set nsga2-pop map [cand ->
    ifelse-value (random-float 1 < 0.3)
      [ list
          max list 200 (min list 800 (item 0 cand + random 101 - 50))
          max list 200 (min list 800 (item 1 cand + random 101 - 50))
      ]
      [ cand ]
  ] newpop

  ;; update global red/green durations (take first)
  set red-duration item 0 first nsga2-pop
  set green-duration item 1 first nsga2-pop
end

;=====================
; PLOTTING
;=====================

to plot-car-counts
  let lanes ["lane-1" "lane-2" "lane-3" "lane-4" "lane-5" "lane-7"]
  set-current-plot "Car Count Per Lane"
  foreach lanes [ lane-name ->
    let count-cars-on-lane count cars with [previous-meaning = lane-name or [meaning] of patch-here = lane-name]
    set-current-plot-pen lane-name
    plotxy ticks count-cars-on-lane
  ]
end

;; NEW: plot one random car's speed per lane; persists tracking across ticks.
to plot-lane-speed-samples
  ;; Try to use the dedicated plot; if missing, fall back so we don't crash.
  carefully [ set-current-plot "Lane Speeds (random car)" ]
  [ set-current-plot "Car Count Per Lane" ]

  foreach (range length lane-names) [ i ->
    let laneName   item i lane-names
    let whoTracked item i tracked-lane-who
    let c nobody

    ;; keep tracking same car if alive
    if (whoTracked != -1) and any? cars with [who = whoTracked] [
      set c turtle whoTracked
    ]

    ;; otherwise sample a car in / last seen on this lane
    if (c = nobody) [
      let cand one-of cars with [[meaning] of patch-here = laneName or previous-meaning = laneName]
      if cand != nobody [
        set c cand
        set tracked-lane-who replace-item i tracked-lane-who [who] of c
      ]
    ]

    ;; speed value
    let s 0
    if (c != nobody) [ set s [speed] of c ]

    ;; ensure a pen exists with this lane name
    carefully [ set-current-plot-pen laneName ]
    [
      create-temporary-plot-pen laneName
      set-current-plot-pen laneName
    ]

    plotxy ticks s
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
278
12
1286
562
-1
-1
16.4
1
10
1
1
1
0
1
1
1
-30
30
-16
16
0
0
1
ticks
30.0

BUTTON
16
25
82
58
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
115
25
178
58
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
11
110
211
260
congestion over time
ticks
Number of stopped cars (queue length)
0.0
1000.0
0.0
100.0
true
false
"" ""
PENS
"queue length" 1.0 0 -16777216 true "" "plot count cars with [speed = 0]"

MONITOR
13
303
101
348
Red Duration
red-duration
17
1
11

MONITOR
137
305
235
350
Green Duration
green-duration
17
1
11

MONITOR
13
373
147
418
Average Waiting Cars
mean [ifelse-value speed = 0 [1] [0]] of cars
17
1
11

MONITOR
15
442
102
487
queue length
count cars with [speed = 0]
17
1
11

MONITOR
123
443
236
488
Traffic-light-Cycle
traffic-light-cycle-count
17
1
11

MONITOR
14
515
145
560
Best NSGA candidate
first nsga2-pop
17
1
11

PLOT
1311
38
1689
268
Car Count Per Lane
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"lane-1" 1.0 0 -6759204 true "" "plot count cars with [previous-meaning = \"lane-1\" or [meaning] of patch-here = \"lane-1\"]"
"lane-2" 1.0 0 -15040220 true "" "plot count cars with [previous-meaning = \"lane-2\" or [meaning] of patch-here = \"lane-2\"]"
"lane-3" 1.0 0 -1184463 true "" "plot count cars with [previous-meaning = \"lane-3\" or [meaning] of patch-here = \"lane-3\"]"
"lane-4" 1.0 0 -5298144 true "" "plot count cars with [previous-meaning = \"lane-4\" or [meaning] of patch-here = \"lane-4\"]"
"lane-5" 1.0 0 -955883 true "" "plot count cars with [previous-meaning = \"lane-5\" or [meaning] of patch-here = \"lane-5\"]"
"lane-7" 1.0 0 -10141563 true "" "plot count cars with [previous-meaning = \"lane-7\" or [meaning] of patch-here = \"lane-7\"]"

PLOT
1316
291
1515
441
Lane Speeds (random car)
ticks
NIL
0.0
10.0
0.0
0.12
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot count turtles"

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
