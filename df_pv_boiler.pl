{
[+10] or [vicvebus227:GridStatus] or [vicbat225:soc] or [vicbat225:batteryCurrent.av] or [Temp5_Boiler_oben:temperature] or [$SELF:time_pv_limit_start] or [$SELF:time_pv_limit_end] or [$SELF:time_boiler_block_start] or [$SELF:time_boiler_block_end] or [$SELF:peakpower] or [$SELF:bat_soc_min_peak] or [$SELF:battery_control] or [$SELF:boiler_control] or [$SELF:circulation_enable];;

## =========================================================================
## ===== CONFIG & CONSTANTS (ZENTRALE NUMERISCHE PARAMETER) ================
## =========================================================================
my $DEBUG                   = 1;;      # 1 = Logging aktiv, 0 = aus
my $DEBUG2                  = 1;;      # 1 = Boiler-Timer-Logging aktiv, 0 = aus
my $DEBUG3                  = 0;;      # 1 = PV-Boiler-Einschaltbedingungen protokollieren, 0 = aus
my $MIN_SWITCH_TIME         = 7;;      # Mindestzeit zwischen Zustandswechseln (Sekunden)

# --- Batterie Schwellenwerte & Limits ---
my $BAT_SOC_MIN_NORMAL      = 10;;     # [%] Minimum SOC im Normalbetrieb
my $BAT_SOC_RECHARGE_TRIGGER= 20;;     # [%] Nachladen vom Grid starten wenn SOC < 20%
my $BAT_MAX_PV_CHARGE_PWR   = 1500;;   # [W] Maximale PV-Ladeleistung von 04:00 - 12:00 Uhr
my $BAT_GRID_RECHARGE_PWR   = 1500;;   # [W] Feste Ziel-Ladeleistung aus dem Netz (positiv)
my $BAT_DISCHARGE_CURR_MAX  = -15;;    # [A] Max. negativer Batteriestrom bevor Boiler reduziert wird
my $BAT_DISCHARGE_CURR_RECOVERY = -12;; # [A] Freigabeschwelle nach Batteriestrom-Schutz

# --- Grid & Power Limits ---
my $GRID_SETPOINT_ZERO      = 0;;      # [W] Nulleinspeisung / Standard GridSetpoint
my $GRID_FEEDIN_THRESHOLD   = -1300;;  # [W] Mindest-Einspeiseleistung für Boiler-Einschaltung (negativ)
my $PHASE_POWER_LIMIT       = 1500;;   # [W] Max. erlaubter Verbrauch pro Phase (ACConsumpLx)
my $BOILER_PHASE_RESERVE_PWR = 1000;;  # [W] Leistungsreserve je Heizstab vor dem Einschalten

# --- Boiler Schwellenwerte ---
my $BOILER_TEMP_MAX         = 60;;     # [°C] Max. Boiler-Temperatur oben für Abschaltung
my $BOILER_SOC_PV_ON_MIN    = 25;;     # [%] Min. SOC für PV-Boilerheizen
my $BOILER_SOC_PV_ON_MAX    = 85;;     # [%] Max. SOC für PV-Boilerheizen
my $BOILER_SOC_OFF_TRIGGER  = 87;;     # [%] SOC-Schaltschwelle für Abschaltung bei unzureichender Ladung

# --- Zeit- & Verzögerungssteuerung ---
my $DELAY_BOILER_PHASE_ON   = 60;;     # [s] Einschaltverzögerung zwischen zwei Heizstab-Phasen
my $DELAY_BOILER_PROTECT    = 300;;    # [s] Schutzverzögerung bei Überstrom / Entladung / SOC-Drop
my $DELAY_BOILER_OVERTEMP   = 1800;;   # [s] Sperrzeit bei Boiler-Übertemperatur (> 60°C = 30 Minuten)

# FHEMWEB setup once (replace df_pv_boiler with this device's name):
# attr df_pv_boiler readingList time_pv_limit_start time_pv_limit_end time_boiler_block_start time_boiler_block_end temp_reheat peakpower bat_soc_min_peak battery_control boiler_control circulation_enable
# attr df_pv_boiler setList time_pv_limit_start:time time_pv_limit_end:time time_boiler_block_start:time time_boiler_block_end:time temp_reheat:slider,30,1,59 peakpower:slider,0,100,10000 bat_soc_min_peak:slider,0,1,100 battery_control:off,PVonly,PVpeakshaving boiler_control:off,manuell,PV,Pellets circulation_enable:off,on
# deleteattr df_pv_boiler webCmd
# attr df_pv_boiler uiTable {package ui_Table}\
# "Zeitfenster"|"Wert"\
# "PV-Limit Start"|WID([$SELF:time_pv_limit_start],"time")\
# "PV-Limit Ende"|WID([$SELF:time_pv_limit_end],"time")\
# "Boiler-Sperre Start"|WID([$SELF:time_boiler_block_start],"time")\
# "Boiler-Sperre Ende"|WID([$SELF:time_boiler_block_end],"time")\
# "Peakpower"|WID([$SELF:peakpower],"slider,0,100,10000")\
# "SOC-Minimum Peakshaving"|WID([$SELF:bat_soc_min_peak],"slider,0,1,100")\
# "Batterie-Steuerung"|WID([$SELF:battery_control],"select,off,PVonly,PVpeakshaving")\
# "Boiler-Steuerung"|WID([$SELF:boiler_control],"select,off,manuell,PV,Pellets")\
# "Zirkulationsfreigabe"|WID([$SELF:circulation_enable],"uzsuToggle,off,on")

my $readConfig = sub {
    my ($reading, $default) = @_;;
    my $value = ReadingsVal("$SELF", $reading, "");;
    if ($value eq "") {
        $value = $default;;
        set_Reading($reading, $value, 1);;
    }
    return $value;;
};;

# Zeitfenster
my $cfg_time_pv_limit_start     = $readConfig->("time_pv_limit_start", "04:00");;
my $cfg_time_pv_limit_end       = $readConfig->("time_pv_limit_end", "12:00");;
my $cfg_time_boiler_block_start = $readConfig->("time_boiler_block_start", "04:00");;
my $cfg_time_boiler_block_end   = $readConfig->("time_boiler_block_end", "11:00");;

# --- Dynamische Variablen mit Fallback-Defaults ---
my $cfg_temp_reheat       = $readConfig->("temp_reheat", 50);; # [°C] Vorzeitige Freigabe nach Übertemperatur
my $cfg_peakpower           = $readConfig->("peakpower", 2800);; # [W] Peakshaving-Schwelle
my $cfg_bat_soc_min_peak    = $readConfig->("bat_soc_min_peak", 30);; # [%] Minimum SOC bei Peakshaving
my $cfg_battery_control     = $readConfig->("battery_control", "off");; # Werte: off, PVonly, PVpeakshaving
my $cfg_boiler_control      = $readConfig->("boiler_control", "off");; # Werte: off, manuell, PV, Pellets
my $cfg_circulation_enable  = $readConfig->("circulation_enable", "off");; # Werte: off, on

my $now = time();;

## =========================================================================
## ===== HELPERS ===========================================================
## =========================================================================
my $logAction = sub { Log 3, "ENERGY_MGR: @_" if $DEBUG };;

my $fhemSet = sub {
    my ($dev, $reading, $target) = @_;;
    if (!defined $target) {
        $target = $reading;;
        $reading = "state";;
    }
    my $current = ReadingsVal($dev, $reading, "");;
    my $sameValue = $current eq $target;;
    if ($reading eq "ESS_minsoc"
        && $current =~ /^-?\d+(?:\.\d+)?$/
        && $target =~ /^-?\d+(?:\.\d+)?$/) {
        $sameValue = $current * 10 == $target;;
    }
    if (!$sameValue) {
        if ($reading eq "ESS_minsoc") {
            my $scaledTarget = sprintf("%g", $target / 10);;
            $logAction->("ACTION: set $dev $reading ${scaledTarget}% (vorher: ${current}%)");;
        } else {
            $logAction->("ACTION: set $dev $reading $target (vorher: $current)");;
        }
        if ($reading eq "state") { fhem("set $dev $target");; }
        else { fhem("set $dev $reading $target");; }
    }
};;

my $getRandomOffPhase = sub {
    my ($l1, $l2, $l3, $powerL1, $powerL2, $powerL3, $blockedL1, $blockedL2, $blockedL3) = @_;;
    my @offPhases = ();;
    push @offPhases, "L1" if (!$l1 && $now >= $blockedL1 && $powerL1 + $BOILER_PHASE_RESERVE_PWR <= $PHASE_POWER_LIMIT);;
    push @offPhases, "L2" if (!$l2 && $now >= $blockedL2 && $powerL2 + $BOILER_PHASE_RESERVE_PWR <= $PHASE_POWER_LIMIT);;
    push @offPhases, "L3" if (!$l3 && $now >= $blockedL3 && $powerL3 + $BOILER_PHASE_RESERVE_PWR <= $PHASE_POWER_LIMIT);;
    return undef if (!@offPhases);;
    return $offPhases[rand @offPhases];;
};;

## =========================================================================
## ===== DATA FETCHING & SANITIZATION =======================================
## =========================================================================
my ($sec,$min,$hour,$mday,$mon,$year) = localtime($now);;
my $timeHM = sprintf("%02d:%02d", $hour, $min);;

my $boilerBlockedTime   = ($timeHM ge $cfg_time_boiler_block_start && $timeHM lt $cfg_time_boiler_block_end) ? 1 : 0;;
my $pvChargeLimitedTime = ($timeHM ge $cfg_time_pv_limit_start     && $timeHM lt $cfg_time_pv_limit_end)   ? 1 : 0;;

my $rawBatState    = ReadingsVal("$SELF", "bat_state", "BAT_CONTROL_OFF");;
my $sanitizedBat   = ($rawBatState =~ /^(BAT_CONTROL_OFF|BAT_NORMOPER|BAT_PEAKSHAVING|BAT_GRID_RECHARGE)$/) ? $rawBatState : "BAT_CONTROL_OFF";;

my $rawBoilerState = ReadingsVal("$SELF", "boiler_state", "BOILER_CONTROL_OFF");;
my $sanitizedBoiler = ($rawBoilerState =~ /^(BOILER_CONTROL_OFF|BOILER_MANUAL|BOILER_PV_HEAT|BOILER_PELLETS_HEAT|BOILER_SAFETY_LOCK)$/) ? $rawBoilerState : "BOILER_CONTROL_OFF";;

my $data = {
    gridStatus     => ReadingsNum("vicvebus227", "GridStatus", 0),
    pvPower        => ReadingsNum("vicsys100_i2", "PVACL1Power", 0) + ReadingsNum("vicsys100_i2", "PVACL2Power", 0) + ReadingsNum("vicsys100_i2", "PVACL3Power", 0) + ReadingsNum("vicsys100_i2", "PVDCPower", 0),
    gridPower      => ReadingsNum("vicsys100_i2", "GridL1", 0) + ReadingsNum("vicsys100_i2", "GridL2", 0) + ReadingsNum("vicsys100_i2", "GridL3", 0),
    acConsL1       => ReadingsNum("vicsys100_i2", "ACConsumpL1", 0),
    acConsL2       => ReadingsNum("vicsys100_i2", "ACConsumpL2", 0),
    acConsL3       => ReadingsNum("vicsys100_i2", "ACConsumpL3", 0),
    houseCons      => ReadingsNum("vicsys100_i2", "ACConsumpL1", 0) + ReadingsNum("vicsys100_i2", "ACConsumpL2", 0) + ReadingsNum("vicsys100_i2", "ACConsumpL3", 0),

    soc            => ReadingsNum("vicbat225", "soc", 0),
    batCurrent     => ReadingsNum("vicbat225", "batteryCurrent.av", 0),
    batChargeUp    => ReadingsNum("$SELF", "batteryChargeUp", 0),
    essMinSoc       => ReadingsNum("vicsys100_i2", "ESS_minsoc", 10),

    tempOben       => ReadingsNum("Temp5_Boiler_oben", "temperature", 0),
    tempUnten      => ReadingsNum("Temp6_Boiler_unten", "temperature", 0),
    gpioCirc       => (ReadingsVal("gpio04Circ", "state", "off") eq "on") ? 1 : 0,
    gpioL1         => (ReadingsVal("gpio22L1", "state", "off") eq "on") ? 1 : 0,
    gpioL2         => (ReadingsVal("gpio06L2", "state", "off") eq "on") ? 1 : 0,
    gpioL3         => (ReadingsVal("gpio26L3", "state", "off") eq "on") ? 1 : 0,

    batState       => $sanitizedBat,
    boilerState    => $sanitizedBoiler,
    lastBatChange  => ReadingsNum("$SELF", "lastBatChangeTs", 0),
    lastBoilerChg  => ReadingsNum("$SELF", "lastBoilerChangeTs", 0),
    boilerOvertempLockUntil => ReadingsNum("$SELF", "boilerOvertempLockUntilTs", 0),
    boilerInterPhaseUntil => ReadingsNum("$SELF", "boilerInterPhaseUntilTs", 0),
    boilerPhaseL1BlockedUntil => ReadingsNum("$SELF", "boilerPhaseL1BlockedUntilTs", 0),
    boilerPhaseL2BlockedUntil => ReadingsNum("$SELF", "boilerPhaseL2BlockedUntilTs", 0),
    boilerPhaseL3BlockedUntil => ReadingsNum("$SELF", "boilerPhaseL3BlockedUntilTs", 0),
    batteryCurrentProtectUntil => ReadingsNum("$SELF", "batteryCurrentProtectUntilTs", 0),
};;

if (ReadingsNum("$SELF", "boilerLockUntilTs", 0) != 0) {
    set_Reading("boilerLockUntilTs", 0, 1);;
}

if ($data->{tempOben} <= $cfg_temp_reheat && $data->{boilerOvertempLockUntil} != 0) {
    Log 1, "ENERGY_MGR: over-temperature lock cleared at reheat temperature $data->{tempOben} C" if ($DEBUG2 == 1);;
    set_Reading("boilerOvertempLockUntilTs", 0, 1);;
    $data->{boilerOvertempLockUntil} = 0;;
}

my $boilerLowSocNoCharge = $data->{soc} < $BOILER_SOC_OFF_TRIGGER
    && $data->{batChargeUp} == 0
    && $data->{soc} <= $BOILER_SOC_PV_ON_MAX;;

my $setEssMinSoc = sub {
    my ($target) = @_;;
    if ($data->{essMinSoc} != $target) {
        $fhemSet->("vicsys100_i2", "ESS_minsoc", $target * 10);;
    }
};;

## =========================================================================
## ===== 1. BATTERIE STATE MACHINE (LiFePO4 14kWh) =========================
## =========================================================================
my %batStates = (
    BAT_CONTROL_OFF => {
        next => sub {
            return "BAT_NORMOPER" if ($cfg_battery_control eq "PVonly");
            return "BAT_PEAKSHAVING" if ($cfg_battery_control eq "PVpeakshaving");
            return "BAT_CONTROL_OFF";
        },
        action => sub {
            $setEssMinSoc->(10);;
            $fhemSet->("vicsys100_i2", "GridSetpoint", $GRID_SETPOINT_ZERO);;
        }
    },
    BAT_NORMOPER => {
        next => sub {
            return "BAT_CONTROL_OFF" if ($cfg_battery_control eq "off");
            return "BAT_PEAKSHAVING" if ($cfg_battery_control eq "PVpeakshaving");
            return "BAT_NORMOPER";
        },
        action => sub {
            $setEssMinSoc->(10);;
            if ($pvChargeLimitedTime) {
                my $pvSurplus = $data->{pvPower} - $data->{houseCons};;
                if ($pvSurplus > $BAT_MAX_PV_CHARGE_PWR) {
                    my $feedInSetpoint = -1 * ($pvSurplus - $BAT_MAX_PV_CHARGE_PWR);;
                    $fhemSet->("vicsys100_i2", "GridSetpoint", sprintf("%.0f", $feedInSetpoint));;
                } else {
                    $fhemSet->("vicsys100_i2", "GridSetpoint", $GRID_SETPOINT_ZERO);;
                }
            } else {
                $fhemSet->("vicsys100_i2", "GridSetpoint", $GRID_SETPOINT_ZERO);;
            }
        }
    },
    BAT_PEAKSHAVING => {
        next => sub {
            return "BAT_CONTROL_OFF" if ($cfg_battery_control eq "off");
            return "BAT_NORMOPER" if ($cfg_battery_control eq "PVonly");
            return "BAT_GRID_RECHARGE" if ($data->{soc} < $BAT_SOC_RECHARGE_TRIGGER);;
            return "BAT_PEAKSHAVING";
        },
        action => sub {
            $setEssMinSoc->($cfg_bat_soc_min_peak);;
            my $gridSetpoint = $GRID_SETPOINT_ZERO;;
            if ($pvChargeLimitedTime) {
                my $pvSurplus = $data->{pvPower} - $data->{houseCons};;
                if ($pvSurplus > $BAT_MAX_PV_CHARGE_PWR) {
                    $gridSetpoint = -1 * ($pvSurplus - $BAT_MAX_PV_CHARGE_PWR);;
                }
            }
            $gridSetpoint = $cfg_peakpower if (!$pvChargeLimitedTime && $data->{gridPower} > $cfg_peakpower);;
            $fhemSet->("vicsys100_i2", "GridSetpoint", sprintf("%.0f", $gridSetpoint));;
        }
    },
    BAT_GRID_RECHARGE => {
        next => sub {
            return "BAT_CONTROL_OFF" if ($cfg_battery_control eq "off");
            return "BAT_NORMOPER" if ($cfg_battery_control eq "PVonly");
            return "BAT_PEAKSHAVING" if ($data->{soc} >= $cfg_bat_soc_min_peak);;
            return "BAT_GRID_RECHARGE";
        },
        action => sub {
            $setEssMinSoc->(10);;
            my $targetGridPower = $data->{houseCons} + $BAT_GRID_RECHARGE_PWR;;
            if ($targetGridPower > $cfg_peakpower) {
                $fhemSet->("vicsys100_i2", "GridSetpoint", sprintf("%.0f", $cfg_peakpower));;
            } else {
                $fhemSet->("vicsys100_i2", "GridSetpoint", sprintf("%.0f", $targetGridPower));;
            }
        }
    }
);;

## =========================================================================
## ===== 2. BOILER STATE MACHINE (150L Warmwasser) =========================
## =========================================================================
my %boilerStates = (
    BOILER_CONTROL_OFF => {
        next => sub {
            return "BOILER_MANUAL"  if ($cfg_boiler_control eq "manuell");
            return "BOILER_PV_HEAT" if ($cfg_boiler_control eq "PV");
            return "BOILER_PELLETS_HEAT" if ($cfg_boiler_control eq "Pellets");
            return "BOILER_CONTROL_OFF";
        },
        action => sub {
            $fhemSet->("gpio22L1", "off");;
            $fhemSet->("gpio06L2", "off");;
            $fhemSet->("gpio26L3", "off");;
            set_Reading("boilerOvertempLockUntilTs", 0, 1) if ($data->{boilerOvertempLockUntil} != 0);;
            set_Reading("boilerInterPhaseUntilTs", 0, 1) if ($data->{boilerInterPhaseUntil} != 0);;
        }
    },
    BOILER_MANUAL => {
        next => sub {
            return "BOILER_CONTROL_OFF" if ($cfg_boiler_control eq "off");
            return "BOILER_PV_HEAT" if ($cfg_boiler_control eq "PV");
            return "BOILER_PELLETS_HEAT" if ($cfg_boiler_control eq "Pellets");
            return "BOILER_MANUAL";
        },
        action => sub {
            set_Reading("boilerOvertempLockUntilTs", 0, 1) if ($data->{boilerOvertempLockUntil} != 0);;
            set_Reading("boilerInterPhaseUntilTs", 0, 1) if ($data->{boilerInterPhaseUntil} != 0);;
            if ($data->{gpioL1} && $data->{acConsL1} > $PHASE_POWER_LIMIT) {
                $fhemSet->("gpio22L1", "off");;
                set_Reading("boilerPhaseL1BlockedUntilTs", $now + $DELAY_BOILER_PROTECT, 1);;
            }
            if ($data->{gpioL2} && $data->{acConsL2} > $PHASE_POWER_LIMIT) {
                $fhemSet->("gpio06L2", "off");;
                set_Reading("boilerPhaseL2BlockedUntilTs", $now + $DELAY_BOILER_PROTECT, 1);;
            }
            if ($data->{gpioL3} && $data->{acConsL3} > $PHASE_POWER_LIMIT) {
                $fhemSet->("gpio26L3", "off");;
                set_Reading("boilerPhaseL3BlockedUntilTs", $now + $DELAY_BOILER_PROTECT, 1);;
            }
        }
    },
    BOILER_PV_HEAT => {
        next => sub {
            return "BOILER_CONTROL_OFF" if ($cfg_boiler_control eq "off");
            return "BOILER_SAFETY_LOCK" if ($now < $data->{boilerOvertempLockUntil}
                && $data->{tempOben} > $cfg_temp_reheat);;
            return "BOILER_PV_HEAT";
        },
        action => sub {
            if ($DEBUG3 == 1) {
                my $gridModeOk = $data->{gridStatus} == 0;;
                my $timeWindowOk = !$boilerBlockedTime;;
                my $overtempLockOk = $now >= $data->{boilerOvertempLockUntil}
                    || $data->{tempOben} <= $cfg_temp_reheat;;
                my $interPhaseOk = $now >= $data->{boilerInterPhaseUntil};;
                my $batteryCooldownOk = $now >= $data->{batteryCurrentProtectUntil};;
                my $feedInOk = $data->{gridPower} < $GRID_FEEDIN_THRESHOLD;;
                my $batteryChargingOk = $data->{batChargeUp} == 1
                    || $data->{soc} > $BOILER_SOC_PV_ON_MAX;;
                my $socOk = $data->{soc} > $BOILER_SOC_PV_ON_MIN;;
                my $batteryCurrentOk = $data->{batCurrent} >= $BAT_DISCHARGE_CURR_RECOVERY;;
                my $temperatureOk = $data->{tempOben} <= $BOILER_TEMP_MAX;;
                my $socProtectionOk = !$boilerLowSocNoCharge;;
                my $phaseLoadOk = !(
                    ($data->{gpioL1} && $data->{acConsL1} > $PHASE_POWER_LIMIT)
                    || ($data->{gpioL2} && $data->{acConsL2} > $PHASE_POWER_LIMIT)
                    || ($data->{gpioL3} && $data->{acConsL3} > $PHASE_POWER_LIMIT)
                );;
                my $phaseL1Available = !$data->{gpioL1}
                    && $now >= $data->{boilerPhaseL1BlockedUntil}
                    && $data->{acConsL1} + $BOILER_PHASE_RESERVE_PWR <= $PHASE_POWER_LIMIT;;
                my $phaseL2Available = !$data->{gpioL2}
                    && $now >= $data->{boilerPhaseL2BlockedUntil}
                    && $data->{acConsL2} + $BOILER_PHASE_RESERVE_PWR <= $PHASE_POWER_LIMIT;;
                my $phaseL3Available = !$data->{gpioL3}
                    && $now >= $data->{boilerPhaseL3BlockedUntil}
                    && $data->{acConsL3} + $BOILER_PHASE_RESERVE_PWR <= $PHASE_POWER_LIMIT;;

                Log 1, sprintf(
                    "ENERGY_MGR: PV_HEAT checks: gridStatus=%s[%s], blockedTime=%s[%s], overtempLockUntil=%s[%s], interPhaseUntil=%s[%s], batteryCooldownUntil=%s[%s]",
                    $data->{gridStatus}, $gridModeOk ? "OK" : "NO",
                    $boilerBlockedTime, $timeWindowOk ? "OK" : "NO",
                    $data->{boilerOvertempLockUntil}, $overtempLockOk ? "OK" : "NO",
                    $data->{boilerInterPhaseUntil}, $interPhaseOk ? "OK" : "NO",
                    $data->{batteryCurrentProtectUntil}, $batteryCooldownOk ? "OK" : "NO"
                );;
                Log 1, sprintf(
                    "ENERGY_MGR: PV_HEAT checks: gridPower=%.0fW (< %.0f [%s]), chargeUp=%s (need 1 [%s]), SOC=%.1f%% (> %.1f [%s]), batteryCurrent=%.1fA (>= %.1f [%s]), tempOben=%.1fC (<= %.1f [%s]), lowSOCProtection=%s, activePhaseLoad=%s",
                    $data->{gridPower}, $GRID_FEEDIN_THRESHOLD, $feedInOk ? "OK" : "NO",
                    $data->{batChargeUp}, $batteryChargingOk ? "OK" : "NO",
                    $data->{soc}, $BOILER_SOC_PV_ON_MIN, $socOk ? "OK" : "NO",
                    $data->{batCurrent}, $BAT_DISCHARGE_CURR_RECOVERY, $batteryCurrentOk ? "OK" : "NO",
                    $data->{tempOben}, $BOILER_TEMP_MAX, $temperatureOk ? "OK" : "NO",
                    $socProtectionOk ? "OK" : "TRIP", $phaseLoadOk ? "OK" : "TRIP"
                );;
                Log 1, sprintf(
                    "ENERGY_MGR: PV_HEAT phases: L1=%s gpio=%d load=%.0fW blockedUntil=%s, L2=%s gpio=%d load=%.0fW blockedUntil=%s, L3=%s gpio=%d load=%.0fW blockedUntil=%s (reserve=%dW, limit=%dW)",
                    $phaseL1Available ? "AVAILABLE" : "BLOCKED", $data->{gpioL1}, $data->{acConsL1}, $data->{boilerPhaseL1BlockedUntil},
                    $phaseL2Available ? "AVAILABLE" : "BLOCKED", $data->{gpioL2}, $data->{acConsL2}, $data->{boilerPhaseL2BlockedUntil},
                    $phaseL3Available ? "AVAILABLE" : "BLOCKED", $data->{gpioL3}, $data->{acConsL3}, $data->{boilerPhaseL3BlockedUntil},
                    $BOILER_PHASE_RESERVE_PWR, $PHASE_POWER_LIMIT
                );;
            }

            # Temp Oben > 60°C -> Abschaltung + 30 min Sperre
            if ($data->{tempOben} > $BOILER_TEMP_MAX) {
                $fhemSet->("gpio22L1", "off");;
                $fhemSet->("gpio06L2", "off");;
                $fhemSet->("gpio26L3", "off");;
                Log 1, "ENERGY_MGR: boilerOvertempLockUntilTs set until " . ($now + $DELAY_BOILER_OVERTEMP) if ($DEBUG2 == 1);;
                set_Reading("boilerOvertempLockUntilTs", $now + $DELAY_BOILER_OVERTEMP, 1);;
                return;;
            }

            # Niedriger SOC ohne Ladung -> Heizstäbe aus, solange die Bedingung gilt
            if ($boilerLowSocNoCharge) {
                my $heatingActive = $data->{gpioL1} || $data->{gpioL2} || $data->{gpioL3};;
                $fhemSet->("gpio22L1", "off");;
                $fhemSet->("gpio06L2", "off");;
                $fhemSet->("gpio26L3", "off");;
                Log 1, "ENERGY_MGR: low-SOC/no-charge condition switched boiler heating off (SOC=$data->{soc}%, chargeUp=$data->{batChargeUp})" if ($DEBUG2 == 1 && $heatingActive);;
                return;;
            }

            # Phasenüberstrom -> nur betroffene Phase aus, weitere Einschaltungen 300s sperren
            my $phaseOverload = 0;;
            if ($data->{gpioL1} && $data->{acConsL1} > $PHASE_POWER_LIMIT) {
                $fhemSet->("gpio22L1", "off");;
                set_Reading("boilerPhaseL1BlockedUntilTs", $now + $DELAY_BOILER_PROTECT, 1);;
                $phaseOverload = 1;;
            }
            if ($data->{gpioL2} && $data->{acConsL2} > $PHASE_POWER_LIMIT) {
                $fhemSet->("gpio06L2", "off");;
                set_Reading("boilerPhaseL2BlockedUntilTs", $now + $DELAY_BOILER_PROTECT, 1);;
                $phaseOverload = 1;;
            }
            if ($data->{gpioL3} && $data->{acConsL3} > $PHASE_POWER_LIMIT) {
                $fhemSet->("gpio26L3", "off");;
                set_Reading("boilerPhaseL3BlockedUntilTs", $now + $DELAY_BOILER_PROTECT, 1);;
                $phaseOverload = 1;;
            }
            if ($phaseOverload) {
                Log 1, "ENERGY_MGR: phase-specific overload cooldown set for 300 seconds" if ($DEBUG2 == 1);;
                return;;
            }

            # Batteriestrom-Schutz: eine Phase abschalten und weitere Eingriffe 300s sperren
            if ($data->{batCurrent} < $BAT_DISCHARGE_CURR_MAX
                && $now >= $data->{batteryCurrentProtectUntil}
                && ($data->{gpioL1} || $data->{gpioL2} || $data->{gpioL3})) {
                if ($data->{gpioL3}) { $fhemSet->("gpio26L3", "off");; }
                elsif ($data->{gpioL2}) { $fhemSet->("gpio06L2", "off");; }
                elsif ($data->{gpioL1}) { $fhemSet->("gpio22L1", "off");; }
                Log 1, "ENERGY_MGR: batteryCurrentProtectUntilTs set until " . ($now + $DELAY_BOILER_PROTECT) if ($DEBUG2 == 1);;
                set_Reading("batteryCurrentProtectUntilTs", $now + $DELAY_BOILER_PROTECT, 1);;
                return;;
            }

            # LOGIK: NETZPARALLELBETRIEB
            if ($data->{gridStatus} == 0) {
                if (!$boilerBlockedTime
                    && !$boilerLowSocNoCharge
                    && $now >= $data->{boilerInterPhaseUntil}
                    && $now >= $data->{batteryCurrentProtectUntil}) {
                    if ($data->{gridPower} < $GRID_FEEDIN_THRESHOLD 
                      && ($data->{batChargeUp} == 1
                          || $data->{soc} > $BOILER_SOC_PV_ON_MAX)
                                            && $data->{soc} > $BOILER_SOC_PV_ON_MIN
                                            && $data->{batCurrent} >= $BAT_DISCHARGE_CURR_RECOVERY) {
                        my $nextPhase = $getRandomOffPhase->(
                            $data->{gpioL1}, $data->{gpioL2}, $data->{gpioL3},
                            $data->{acConsL1}, $data->{acConsL2}, $data->{acConsL3},
                            $data->{boilerPhaseL1BlockedUntil},
                            $data->{boilerPhaseL2BlockedUntil},
                            $data->{boilerPhaseL3BlockedUntil}
                        );;
                        if (defined $nextPhase) {
                            $fhemSet->("gpio22L1", "on") if ($nextPhase eq "L1");;
                            $fhemSet->("gpio06L2", "on") if ($nextPhase eq "L2");;
                            $fhemSet->("gpio26L3", "on") if ($nextPhase eq "L3");;
                            Log 1, "ENERGY_MGR: boilerInterPhaseUntilTs set until " . ($now + $DELAY_BOILER_PHASE_ON) if ($DEBUG2 == 1);;
                            set_Reading("boilerInterPhaseUntilTs", $now + $DELAY_BOILER_PHASE_ON, 1);;
                        }
                    }
                }
            }
            # LOGIK: INSELBETRIEB
            elsif ($data->{gridStatus} == 2) {
                # Platzhalter für Inselbetrieb
            }
        }
    },
    BOILER_PELLETS_HEAT => {
        next => sub {
            return "BOILER_CONTROL_OFF" if ($cfg_boiler_control eq "off");
            return "BOILER_MANUAL" if ($cfg_boiler_control eq "manuell");
            return "BOILER_PV_HEAT" if ($cfg_boiler_control eq "PV");
            return "BOILER_PELLETS_HEAT";
        },
        action => sub {
            $fhemSet->("gpio22L1", "off");;
            $fhemSet->("gpio06L2", "off");;
            $fhemSet->("gpio26L3", "off");;
        }
    },
    BOILER_SAFETY_LOCK => {
        next => sub {
            return "BOILER_CONTROL_OFF" if ($cfg_boiler_control eq "off");
            return "BOILER_MANUAL" if ($cfg_boiler_control eq "manuell");
            if ($cfg_boiler_control eq "PV") {
                return "BOILER_PV_HEAT" if ($now >= $data->{boilerOvertempLockUntil}
                    || $data->{tempOben} <= $cfg_temp_reheat);;
            }
            return "BOILER_SAFETY_LOCK";
        },
        action => sub {
            $fhemSet->("gpio22L1", "off");;
            $fhemSet->("gpio06L2", "off");;
            $fhemSet->("gpio26L3", "off");;
        }
    }
);;

## =========================================================================
## ===== TRANSITION LOGIC ==================================================
## =========================================================================
my $curBatState = $data->{batState};;
my $newBatState = $batStates{$curBatState}->{next}->();;
if ($newBatState ne $curBatState) {
    if ($newBatState eq "BAT_CONTROL_OFF"
        || $curBatState eq "BAT_CONTROL_OFF"
        || ($now - $data->{lastBatChange}) >= $MIN_SWITCH_TIME) {
        $logAction->("[BAT TRANSITION] $curBatState -> $newBatState");;
        set_Reading("bat_state", $newBatState, 1);;
        set_Reading("lastBatChangeTs", $now, 1);;
    } else {
        $newBatState = $curBatState;;
    }
}

my $curBoilerState = $data->{boilerState};;
my $newBoilerState = $boilerStates{$curBoilerState}->{next}->();;
if ($newBoilerState ne $curBoilerState) {
    if ($newBoilerState eq "BOILER_CONTROL_OFF"
        || $newBoilerState eq "BOILER_MANUAL"
        || $curBoilerState eq "BOILER_CONTROL_OFF"
        || $curBoilerState eq "BOILER_MANUAL"
        || ($now - $data->{lastBoilerChg}) >= $MIN_SWITCH_TIME) {
        $logAction->("[BOILER TRANSITION] $curBoilerState -> $newBoilerState");;
        set_Reading("boiler_state", $newBoilerState, 1);;
        set_Reading("lastBoilerChangeTs", $now, 1);;
    } else {
        $newBoilerState = $curBoilerState;;
    }
}

## =========================================================================
## ===== EXECUTE ACTIONS & READINGS ========================================
## =========================================================================
if ($batStates{$newBatState}) {
    $batStates{$newBatState}->{action}->();;
}

if ($boilerStates{$newBoilerState}) {
    $boilerStates{$newBoilerState}->{action}->();;
}

my $batsoc = $data->{soc};;
my $previousBatSoc = ReadingsVal("$SELF", "batteryPreviousSoc", "");;
my $batteryChargeUp = ReadingsVal("$SELF", "batteryChargeUp", "");;
if ($batteryChargeUp !~ /^[01]$/) {
    set_Reading("batteryChargeUp", 0, 1);;
}
if ($previousBatSoc !~ /^-?\d+(?:\.\d+)?$/) {
    set_Reading("batteryPreviousSoc", $batsoc, 1);;
} elsif ($batsoc > $previousBatSoc) {
    set_Reading("batteryChargeUp", 1, 1);;
    set_Reading("batteryPreviousSoc", $batsoc, 1);;
} elsif ($batsoc < $previousBatSoc) {
    set_Reading("batteryChargeUp", 0, 1);;
    set_Reading("batteryPreviousSoc", $batsoc, 1);;
}

if (!$data->{gpioCirc}
    && $cfg_circulation_enable eq "on"
    && $data->{tempUnten} < 40
    && $data->{tempOben} > 48
    && ($data->{gpioL1} || $data->{gpioL2} || $data->{gpioL3})) {
    $fhemSet->("gpio04Circ", "on");;
}
elsif ($data->{gpioCirc} && $data->{tempUnten} > 50) {
    $fhemSet->("gpio04Circ", "off");;
}
elsif ($data->{gpioCirc} && !$data->{gpioL1} && !$data->{gpioL2} && !$data->{gpioL3}) {
    $fhemSet->("gpio04Circ", "off");;
    Log 1, "circ off3";;
}
elsif ($data->{gpioCirc} && $cfg_circulation_enable eq "off") {
    fhem("set circulation 0");;
    $fhemSet->("gpio04Circ", "off");;
    Log 1, "circ off2";;
}

set_Reading("visual_bat", "$newBatState | SOC=$data->{soc}% | GridPwr=$data->{gridPower}W", 1);;
set_Reading("visual_boiler", "$newBoilerState | T_Oben=$data->{tempOben}°C | Relays=" . $data->{gpioL1} . $data->{gpioL2} . $data->{gpioL3}, 1);;
}
