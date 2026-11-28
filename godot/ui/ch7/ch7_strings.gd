class_name Ch7Strings
extends RefCounted
## Chapter 7 UI strings (registered by GridUi.load_strings beside GridStrings.S). Keys must be unique across chapters: prefix them C7_.
const S := {
	"C7_SPENT": "%s of %s", "C7_PANEL": "Chapter 7 controls", "C7_PREVIEW_NONE": "the plants appear after Run (hydro and solar are fixed for the day)", "C7_UNIT_MW": "MW", "C7_VS": "clears at %d ms vs target %d ms", "C7_PREVIEW": "preview: solar and hydro only; the other plants appear after Run",
	"C7_Z": "Z = %s pu", "C7_T1": "T1, T2: Z = %s pu each", "C7_G27_GLOSS": "pu: a fraction of the 100 MVA base. X''d: the generator's sub-transient reactance, how hard it feeds a fault (pu). P_m: turbine power (pu). P_max: the most electrical power the network can carry (pu). delta_0: the rotor's starting angle (deg). lambda: the price of the next MWh ($/MWh).",
	"C7_LEG_TOTALS": "total clearing time %s s", "C7_LEG_SPARE": "tightest gap between relays, minus the 0.3 s needed: %s s (below 0 = two relays too close)", "C7_HIDE_NOTE": "The formulas are hidden: try the numbers from the givens first.",
	"C7_GIV_CAP": "GIVENS (everything you need)", "C7_GIV_BASE": "Base %d MVA, %d kV: 1 pu of current = %s kA.", "C7_GIV_GRID": "Grid at 132 kV: fault level %d MVA, so Z = %s pu.", "C7_GIV_T": "Each of 2 transformers: %d MVA, Z = %s %%, so Z = %s pu.",
	"C7_GIV_G": "Each of 2 generators: %s MVA, X''d = %s, so Z = %s pu.", "C7_GIV_COUPLER": "Coupler %s%s.", "C7_GIV_CHAIN": "Think: the grid and its transformer are one source branch, each generator another. Z_th = all branches in parallel at the busbar; I_f = 1 / Z_th pu, then x kA per pu.",
	"C7_GIV_R": ", reactor %s pu",
	"C7_G27_A": "Faults (100 MVA base, pre-fault V = 1.0 pu): gen X''d %s, X2 %s, X0 %s (blocked by the delta); transformer X = %s; line X1 = %s ohm, X0 = %s ohm at %d kV.", "C7_G27_A2": "3-phase at the line end: Z1 = gen + T + line. SLG: Z1 + Z2 + Z0, with the line X0 and the transformer X0 = its X.",
	"C7_G27_B": "Unit %d: C = %s + %s P + %s P^2 ($/h), %d to %d MW.", "C7_G27_B2": "Lambda no limits: demand %d MW, ignore the limits. Lambda with limits: demand %d MW, clip each unit to its range, then re-solve the rest.",
	"C7_G27_C": "Swing at %d Hz: H = %s s, P_m = %s pu, P_max = %s pu before and after, terminal fault (P during = 0).",
	"C7_G27_D": "Grown board (L23 plus one 80 MVA transformer and one 31.25 MVA generator), at the 33 kV section on 100 MVA: Z1 %s, Z2 %s, Z0 %s pu; I_b = %s kA. I_3ph = I_b / Z1, I_slg = 3 I_b / (Z1 + Z2 + Z0); rate the breakers for the larger of the two.",
	"C7_WO_L27_1": "Breakers rated at least the larger of the 3-phase and the SLG fault of the grown board", "C7_WO_L27_2": "Tonight's dispatch adds up to 1000 MW with every unit inside its limits", "C7_WO_L27_3": "A prediction written before you run",
	"C7_LAMP_L27_2": "Right-sized breakers and a near-optimal dispatch", "C7_LAMP_L27_3": "The least-cost dispatch (equal lambda) and 4 of 5 predictions within 2 %", "C7_KIT_CAP": "build incl. starting kit", "C7_MARGIN2": "spare over the 0.3 s interval: %s s",
	"C7_FN_ps17": "I = V/Z_th; kA = pu x base/(1.73 kV)", "C7_FN_ps18": "I_a = 3V / (Z1 + Z2 + Z0)", "C7_FN_ps20": "equal lambda, no limits", "C7_FN_ps21": "equal lambda, then clip to limits", "C7_FN_ps24": "t = sqrt(4H(d_cr-d_0)/(w P_m))",
	"C7_G24_PICK": "Pickup (I_s): the current at which the relay starts timing; keep it above 1.25 x the load.", "C7_G24_TMS": "TMS: the time multiplier, a dial that slides the whole curve up (slower) or down (faster).", "C7_G24_CT": "CT: the current transformer that feeds the relay; pickup is a % of its rating.",
	"C7_G24_CURVE": "SI: gentle, easy to grade but slow. VI/EI: much faster at big currents. To tighten the total, try VI or EI with smaller TMS values that still keep every gap above 0.3 s.",
	"C7_G25_TARGET": "Target: clear in under %d ms (the critical clearing time).", "C7_G25_Z1": "Zone 1: trips a fault on the first 80 % of the line at once (30 ms).", "C7_G25_Z2": "Zone 2: reaches 120 % of the line but waits 350 ms for the next relay to act first.", "C7_G25_IDMT": "Inverse-time: the bigger the current, the faster it trips; TMS slides the curve.",
	"C7_G26_LAMBDA": "Lambda: the price of the next MWh, the cost of the plant that would supply it.", "C7_G26_CORR": "Corridor: the one 220 kV wire between north and city; its limit is 450 MW.", "C7_MWH": "$%s/MWh", "C7_LAMP_SCORE": "Score ≤ %s", "C7_LAMP_SCORE3": "Score ≤ %s%s",
	"C7_GLOSS_IF": "I_f: the fault current, the biggest current the breaker has to interrupt.", "C7_GLOSS_PU": "pu: per-unit, a fraction of the 100 MVA base power (1 pu of current = 1.75 kA at 33 kV).", "C7_GLOSS_REACTOR": "Reactor: a coil in the bus section that adds impedance, so a fault pulls less current.",
	"C7_GLOSS_PM": "P_m: the push of the turbine (mechanical power). delta: how far the rotor runs ahead of the grid. Faster clearing keeps delta small.", "C7_CLEAR_SUM": "= relay %d + breaker %d ms (%d cycles)",
	"C7_FORMULA_CAP": "FORMULA CARD (try the numbers first)", "C7_SHOW": "show formulas", "C7_HIDE": "hide formulas",
	"C7_F1": "3-phase fault: I_f = V / Z_th, then kA = pu x 100 MVA / (1.732 x kV). Z_th = Z_grid + Z_transformer + Z_line, in per-unit.",
	"C7_F2": "SLG fault: I_a = 3 V / (Z1 + Z2 + Z0). A delta winding blocks Z0, so only the grounded path counts.",
	"C7_F3": "Equal lambda: every unit not at a limit runs where dC/dP = lambda; add the P(lambda) of all units until they sum to demand.",
	"C7_F4": "Critical clearing (terminal fault): t = sqrt(4 H (d_cr - d_0) / (w_s P_m)), cos d_cr = (P_m (pi - 2 d_0) - P_max cos d_0 ... see equal areas).",
	"C7_F5": "A unit at its limit is fixed; the others share the rest at one lambda. Check each limit again after the shares are found.",
	"C7_UNIT_kA": "kA", "C7_UNIT_usd": "$/MWh", "C7_UNIT_s": "s", "C7_LEG_CURVES": "relay curves", "C7_LIMIT_ALL": "conductor I2t limits: 100, 70, 50 mm2",
	"C7_PREDICT": "Your prediction", "C7_PREDICT_KA": "your prediction: I_f at the feeder", "C7_PREDICT_DCR": "your prediction: δ_cr, deg", "C7_PREDICT_LAM": "your prediction: city lambda at 20:00, $/MWh",
	# L23 / L27 board
	"C7_GRID": "grid 132 kV", "C7_SEC_A": "section A", "C7_SEC_B": "section B", "C7_COUPLER": "coupler", "C7_OPEN": "open", "C7_CLOSED": "closed", "C7_FEEDER": "feeder F1",
	"C7_FAULT": "3-phase fault", "C7_RATED": "rated %s kA", "C7_DUTY": "must break %s kA", "C7_HIDDEN": "(run it to see it)", "C7_ESTATE_DARK": "ESTATE DARK",
	"C7_BREAKERS": "BREAKERS (kA, each)", "C7_COUPLER_CAP": "BUS COUPLER", "C7_REACTOR_CAP": "BUS-SECTION REACTOR (pu)", "C7_XFMR_CAP": "TRANSFORMER IMPEDANCE (%)",
	"C7_N1_OK": "if a transformer trips, the estate still gets %s pu voltage", "C7_N1_BAD": "a transformer trip is not covered", "C7_FAULT_KA": "%s kA  (%s MVA)", "C7_ZTH": "Z_th %s pu", "C7_NONE": "none",
	"C7_TABLE": "Who breaks what", "C7_NO_REACTOR": "0",
	# L24
	"C7_TC_X": "current, A", "C7_TC_Y": "time, s", "C7_RELAY": "R%d", "C7_IS": "I_s %s A", "C7_TMS": "TMS", "C7_CURVE_CAP": "CURVE (all)", "C7_PICKUP_CAP": "PICKUP, % of CT (all)", "C7_RELAY_CAP": "TIME MULTIPLIER (R1 substation to R4 far end)",
	"C7_TOTAL": "total %s s", "C7_MARGIN": "tightest interval %s s (needs %s)", "C7_LIMIT": "conductor limit %d mm²", "C7_LOCKED": "The build is locked while the clock runs. Stop the clock to change it.",
	# L25
	"C7_PDELTA": "Electrical power against rotor angle", "C7_PM": "P_m", "C7_PRE": "before", "C7_DURING": "during the fault", "C7_POST": "after", "C7_A1": "A1: speeds the rotor up", "C7_A2": "A2: slows it down",
	"C7_RELAY_CAP2": "RELAY", "C7_BREAKER_CAP": "BREAKER (cycles)", "C7_RECLOSE_CAP": "AUTO-RECLOSE", "C7_CLEAR": "clears at %d ms", "C7_TCR": "critical %d ms", "C7_MARGIN_MS": "margin %d ms", "C7_STABLE": "keeps step", "C7_SLIPS": "slips a pole",
	"C7_SWING": "Rotor angle against time",
	# L26
	"C7_MODE_CAP": "DISPATCH RULE", "C7_WINDOW_CAP": "COMMITMENT: hours and $ per MWh (click to change the hours)", "C7_STACK": "Generation by hour, MW", "C7_DEMAND": "demand", "C7_FLOW": "corridor flow", "C7_LAMBDA": "lambda, $/MWh",
	"C7_LAM_G": "north", "C7_LAM_S": "city", "C7_COST": "day cost %s", "C7_TRIP": "corridor tripped at %s", "C7_OFF": "off", "C7_HYDRO": "hydro", "C7_SOLAR": "solar", "C7_CORRIDOR": "corridor limit %d MW",
	"C7_LEG_STACK": "generation", "C7_PLANT_coalsub": "sub coal", "C7_PLANT_coalsc": "super coal", "C7_PLANT_ccgt": "CCGT", "C7_PLANT_ocgt": "OCGT",
	"C7_MODE_merit": "cheapest first", "C7_MODE_lambda": "equal lambda", "C7_MODE_corridor": "lambda + corridor",
	# L27
	"C7_EXAM": "Exam questions", "C7_SHEET": "Exam sheet", "C7_SHEET_MORE": "scroll for more", "C7_SHEET_TOP": "scroll up for more", "C7_Q_ps17": "3-phase fault, kA", "C7_Q_ps18": "SLG fault, kA", "C7_Q_ps20": "lambda, no limits, $/MWh", "C7_Q_ps21": "lambda, limits binding, $/MWh", "C7_Q_ps22": "lambda with losses, $/MWh", "C7_Q_ps24": "critical clearing time at 60 Hz, s",
	"C7_ANSWER": "answer %s", "C7_DISPATCH_CAP": "TONIGHT'S DISPATCH, MW (unit 1, 2, 3)", "C7_BOARD_KA": "grown board: 3-phase %s kA, SLG %s kA", "C7_DISPATCH_SUM": "sum %s of %d MW", "C7_UNIT": "unit %d  (%d to %d)",
}
