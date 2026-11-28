class_name Ch8Strings
extends RefCounted
## Chapter 8 UI strings (registered by GridUi.load_strings beside GridStrings.S). Keys must be unique across chapters: prefix them C8_.
const S := {
	"C8_PANEL": "Chapter 8 controls", "C8_PAN_MORE": "drag or scroll: more below \u2193", "C8_PAN_UP": "drag or scroll: more above \u2191",
	# shared
	"C8_ALL": "all", "C8_OFF": "off", "C8_ON": "on", "C8_V": "%s V", "C8_KM": "%s km", "C8_KW": "%s kW", "C8_HOMES": "%d", "C8_AMPS": "%s of %s A", "C8_PER_KM": "%s", "C8_SUBSTATION": "11 kV",
	"C8_X_KM": "km along the feeder", "C8_Y_V": "customer voltage, V", "C8_BAND_LO": "lowest allowed %s V", "C8_BAND_HI": "highest allowed %s V",
	"C8_DIAG_NOTE": "dot: green when both voltages are in band; bar: current against the wire's rating", "C8_REG_SHORT": "REG", "C8_REG_AT": "holds %s pu", "C8_TAP_AT": "tap %s %%",
	# the 3D countryside (chips on the places)
	"C8_SCALE": "%s km of feeder, drawn compressed", "C8_SUB_PIN": "Substation, 11 kV", "C8_REG_PIN": "Regulator, holds %s pu", "C8_REG_STEPS": "%d steps at peak",
	"C8_PIN_YR": "%s min a year", "C8_BLAME_PIN": "Most to blame: %s", "C8_SW_PIN": "%s switch", "C8_FUSE_PIN": "fuse on", "C8_HOMES_PIN": "%d homes",
	"C8_SHOTS_PIN": "%d fast shots", "C8_LINK_PIN": "%s  fuse %d A", "C8_FUSE_SAVED": "saved", "C8_FUSE_BLOWN": "blown", "C8_FUSE_IDLE": "not tried",
	"C8_TX_TRIP": "trips at %s:00", "C8_HOT_PIN": "hot spot %s °C, limit %d °C", "C8_BUS_PIN": "bus section, %s", "C8_DR_PIN": "demand response: %d homes dimmed", "C8_TIE_PIN": "tie: %s",
	"C8_OLTC_PIN": "tap changer, step %d at noon", "C8_PANELS": "%d panels", "C8_NOON_PIN": "noon %s", "C8_FAULTS_YR3": "%s/yr",
	# L31
	"C8_SECTION_CAP": "SECTION (N5 is the far end)", "C8_WIRE_CAP": "WIRE of that section (price per km)", "C8_TAP_CAP": "TRANSFORMER TAP, % (off-load)", "C8_REG_CAP": "REGULATOR in the line to N2 / N3 (%s), set point pu",
	"C8_PEAK": "peak", "C8_LIGHT": "light", "C8_PEAK_NAME": "evening peak", "C8_LIGHT_NAME": "light load (%d %%)", "C8_L31_TITLE": "READING THE FEEDER",
	"C8_L31_OK": "every customer is inside the band at peak and at light load", "C8_L31_LOW": "lowest %s V at %s (floor %s V)",
	"C8_L31_MIN": "Lowest at peak: %s V at %s (floor %s V, margin %s V).", "C8_L31_MAX": "Highest at light load: %s V at %s (ceiling %s V, margin %s V).",
	"C8_L31_LOSS": "Wire losses at peak: %s %% of the energy (%s kW).", "C8_L31_HAND": "The textbook sum of the drops, (R P + X Q) / V, says %s %% to the far end; the full solve, with the current growing as the voltage falls, says %s %%.",
	"C8_L31_REG": "Regulator at %s holds %s pu: %d steps of 0.625 %% at peak, %d at light load (of %d).",
	"C8_L31_GLOSS_TAP": "A tap moves a customer by the same % at peak and at light load: it only fits the spread between them.", "C8_L31_GLOSS_REG": "Wire and a regulator shrink the drop itself. Wire costs by the km; the regulator is one price, and it does not cut losses.",
	# L32
	"C8_KIND_CAP": "SWITCH (price each), tap a site", "C8_SITE_CAP": "SITE: head of T2-T4 (at most %d)", "C8_FREE": "free", "C8_NONE": "none", "C8_MANUAL": "manual", "C8_REMOTE": "remote", "C8_FUSE_CAP": "FUSE a spur (%s)", "C8_TIE_CAP": "TIE to the next feeder", "C8_TIE": "tie",
	"C8_SAIFI": "SAIFI", "C8_SAIDI": "SAIDI", "C8_CAIDI": "CAIDI", "C8_ENS": "ENS, MWh", "C8_L32_USED": "sectionalisers used: %d of %d",
	"C8_FUSE_SHORT": "fuse", "C8_BARE": "bare", "C8_NEXT_FEEDER": "next feeder", "C8_TIE_INFO": "tie: %d kW back in %d min", "C8_NO_TIE": "no tie: wait for the repair",
	"C8_L32_NOTE": "a fault is repaired in %s h; a manual switch takes %d h, a remote one %d min (five minutes or less is not counted)", "C8_HEAT_CAP": "EXPECTED OUTAGE PER SECTION: minutes a year added to SAIDI, and faults a year (redder = more to blame)",
	"C8_MIN_YR": "%s min", "C8_FAULTS_YR": "%s faults/yr", "C8_TARGET_MAX": "target: at most %s", "C8_STAR_MAX": "lamp 3: at most %s", "C8_CAIDI_EQ": "= SAIDI / SAIFI",
	"C8_G_SAIFI": "how often the average customer loses power in a year", "C8_G_SAIDI": "minutes a year the average customer is without power", "C8_G_CAIDI": "how long each interruption lasts, on average", "C8_G_ENS": "energy not supplied: what the outages cost in MWh",
	# L33
	"C8_PICKUP_CAP": "pickup, A", "C8_FAST_CAP": "fast dial", "C8_SLOW_CAP": "slow dial", "C8_SHOTS_CAP": "fast shots", "C8_SPUR_CAP": "%s %d A", "C8_TC_X": "fault current, A", "C8_TC_Y": "time to operate, s",
	"C8_PICKUP_LINE": "pickup %s A", "C8_LOAD_LINE": "load %s A", "C8_LEG": "CURVES", "C8_LEG_FAST": "recloser fast (%d shots)", "C8_LEG_SLOW": "recloser slow", "C8_LEG_MELT": "fuse minimum melt", "C8_LEG_CLEAR": "fuse total clearing",
	"C8_SPUR_LINE": "%s link %d A: fast margin %s s, slow margin %s s; carries its load: %s; melts at its smallest fault: %s; faults %d to %d A.", "C8_YES": "yes", "C8_NO": "no",
	"C8_WORST": "Tightest margin %s s; lamp 3 needs at least %s s everywhere.", "C8_BLOWS": "Fuses blown by temporary faults: %s a year (%d %% of faults are temporary).",
	"C8_L33_GLOSS1": "Fast: the recloser must trip before the fuse starts to melt (the dashed curve), so a temporary fault is gone and the fuse is saved.", "C8_L33_GLOSS2": "Slow: it must wait for the fuse's total clearing time (solid), so a permanent fault is cleared by the spur's own fuse and not by a feeder lockout.",
	"C8_SLOW_TAG": "slow", "C8_FAST_TAG": "fast",
	"C8_KIND_ok": "Coordinated: the fuses are saved from temporary faults and clear the permanent ones.", "C8_KIND_miscoordination": "Miscoordinated: a curve pair crosses over a spur's fault range.", "C8_KIND_nuisance": "Nuisance trips: the pickup is under 1.25 times the head load.",
	"C8_KIND_fuseLoad": "A fuse link is too small for its spur's load.", "C8_KIND_blind": "A fuse link is too big to melt at its spur's smallest fault.", "C8_KIND_fuseBlown": "A fast curve is slower than a fuse's melt curve: the fuse blows for a temporary fault.",
	# L34
	"C8_SIZE_CAP": "transformers", "C8_BUS_CAP": "bus section", "C8_TIE_XFER_CAP": "tie transfer", "C8_DR_CAP": "demand response", "C8_MVA": "%s MVA", "C8_BUS_H": "%d h", "C8_AUTO": "auto",
	"C8_SMALL": "small", "C8_LARGE": "large", "C8_THERMO": "SURVIVOR'S THERMOMETER", "C8_LIMIT_C": "%d °C", "C8_C": "%s °C", "C8_HOT_AT": "peak at %s",
	"C8_DAYS": "%s days", "C8_LOL": "life lost that day", "C8_LOL_LAMPS": "lamp 2: at most %s days. lamp 3: at most %s days.", "C8_HOUR": "hour of the day", "C8_Y_C": "temperature, °C", "C8_Y_MVA": "MVA",
	"C8_PROT": "protection trips the unit at %d °C", "C8_TRIP_TAG": "trip", "C8_BACK_TAG": "all load back", "C8_LEG_HOT": "hot spot (winding)", "C8_LEG_OIL": "top oil", "C8_LEG_LOAD": "load", "C8_LEG_SERVED": "served",
	"C8_LIM15": "survivor carries up to 1.5 x rating = %s MVA", "C8_FIRM_TAG": "firm capacity %s MVA",
	"C8_L34_TITLE": "READING THE DAY", "C8_FIRM_LINE": "%d units of %s MVA are %s MVA in all. Firm capacity is the total minus the largest unit, %s MVA, against a peak of %s MVA.",
	"C8_TRIP_LINE": "At %s:00 the worst transformer trips. The survivor may carry up to %s MVA for a while; the rest of the load is shed until a bus-section close, a tie transfer or demand response brings it back.",
	"C8_BACK_LINE": "All load is back %s h after the trip.", "C8_NOT_BACK": "Not all load is back within %s h.", "C8_UNSERVED": "Energy shed meanwhile: %s MWh.",
	"C8_L34_OK": "the survivor stays under its limit and everyone is back in time", "C8_L34_HOT": "the survivor passes its limit: its protection trips it and the substation goes dark", "C8_L34_LATE": "not all load is back in time",
	"C8_L34_GLOSS_AGE": "Insulation ages 2 times faster for every 6 C of hot-spot above 98 C: a short hot emergency can cost days of life.", "C8_L34_GLOSS_FIRM": "No single purchase carries the peak: add what rides through (size, a tie, demand response) and watch the thermometer.",
	# L35
	"C8_PV_CAP": "PV queue, kW", "C8_OLTC_CAP": "set point, pu", "C8_INV_CAP": "inverters", "C8_HEAD_CAP": "head wire N1-N2", "C8_LDC": "line-drop comp", "C8_VOLTVAR": "volt-var",
	"C8_HOST_LINE": "connecting %s kW; the feeder hosts %s kW", "C8_NOON": "noon", "C8_EVENING": "evening", "C8_NOON_NAME": "noon: sun, light load", "C8_EVE_NAME": "evening: peak, no sun",
	"C8_L35_TITLE": "NOON AGAINST EVENING", "C8_L35_NOON": "At noon the highest customer is %s V at %s (ceiling %s V, margin %s V).", "C8_L35_BACK": "At noon %s kW flows back up the feeder to the substation: reverse flow.", "C8_L35_FWD": "At noon %s kW still flows out from the substation: no reverse flow.",
	"C8_L35_EVE": "In the evening the lowest customer is %s V at %s (floor %s V, margin %s V).", "C8_L35_HOST": "Hosting capacity: %s kW, limited by %s. You connect %s kW; the council needs at least %s kW.",
	"C8_L35_OLTC": "Tap changer: step %d at noon (source %s pu), step %d in the evening (source %s pu).", "C8_L35_VV": "Inverters absorb %s kvar at noon.",
	"C8_LIMBY_voltage": "voltage", "C8_LIMBY_current": "wire current", "C8_LIMBY_none": "nothing in the range", "C8_LIMBY_base-case": "the base case",
	"C8_L35_GLOSS1": "Reverse flow lifts the voltage toward the roofs: the drop is (R P + X Q) / V with the real power P now negative.", "C8_L35_GLOSS2": "Line-drop compensation lowers the source when power flows back and raises it under load; volt-var inverters absorb vars as the voltage climbs.",
	# L36
	"C8_QS_dropPct": "far-end voltage drop", "C8_QS_saifi": "SAIFI", "C8_QS_saidi": "SAIDI", "C8_U_dropPct": "%", "C8_U_saifi": "per yr", "C8_U_saidi": "min/yr", "C8_WHY_CAP": "WHY: which equation governs the drop along a feeder?",
	"C8_WHY_RIGHT": "right: R with P, X with Q", "C8_WHY_WRONG": "not that one", "C8_GIV_CAP": "GIVENS (everything you need)", "C8_DIAG_CAP": "THE FEEDER", "C8_ANS_CAP": "YOUR PREDICTIONS AND THE ENGINE'S ANSWERS",
	"C8_G_LINE": "An %d kV three-phase feeder of %s wire: R = %s ohm/km, X = %s ohm/km.", "C8_G_SEC": "Section %s: %s km, %d customers, load %s kW and %s kvar, %s.",
	"C8_DEV_none": "no device ahead of it", "C8_DEV_manual": "a manual switch ahead of it", "C8_DEV_fuse": "a fuse at its tap", "C8_DEV_SHORT_manual": "manual", "C8_DEV_SHORT_fuse": "fuse",
	"C8_G_FAULTS": "Faults: %s per km per year, anywhere on the line. A fault takes %s h to repair; a manual switch takes %s h to operate.", "C8_G_LOAD": "%s kW + %s kvar",
	"C8_G_TASK": "Predict the far-end voltage drop in percent (the textbook sum of (R P + X Q) / V^2 over the sections), SAIFI in interruptions per customer per year and SAIDI in minutes per customer per year (IEEE 1366). Then name the equation behind the drop.",
	"C8_G_THINK": "Work it by hand: each section carries the load of everything beyond it. Faults on a section interrupt everything behind the nearest device ahead of it until it is repaired or switched round.",
	"C8_SHEET_Q": "Your predictions", "C8_YOURS": "your guess: %s", "C8_NO_GUESS": "no guess yet", "C8_ANSWER": "answer %s", "C8_OFF_BY": "off by %s %%", "C8_MADE": "predictions made: %d of 3",
	# lamp conditions (work_order.lamp_texts reads TH_<threshold>): the star conditions of L31-L36, named so the lamps say what they ask
	"TH_lossMax": "Line losses \u2264\u00a0%s\u00a0%%", "TH_ensStar": "Energy not supplied \u2264\u00a0%s MWh a year", "TH_marginStar": "Every fuse saved with \u2265\u00a0%s s to spare",
	"TH_lolMid": "Transformer life lost \u2264\u00a0%s days", "TH_lolMax": "Transformer life lost \u2264\u00a0%s days", "TH_pvStar": "Host \u2265\u00a0%s kW of rooftop solar",
	"TH_boughtMin": "Fix the voltage with kit, not with a lower solar limit", "TH_errOk": "Every prediction within\u00a0%s\u00a0%%", "TH_whyRight": "The \u201cwhy\u201d card right",
	"C8_LAMP_PCT": "Worst prediction error \u2264 %s\u00a0%%", "C8_LAMP_PCT3": "Worst prediction error \u2264 %s\u00a0%%%s",
}
