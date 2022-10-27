const string AUTOSAVEGHOSTS_SCRIPT_TXT = """
declare Text G_PreviousMapUid;

// logging function, should be "MLHook_LogMe_" + PageUID
Void MLHookLog(Text msg) {
    SendCustomEvent("MLHook_LogMe_AutosaveGhosts", [msg]);
}

/// Convert a C++ array to a script array
Integer[] ToScriptArray(Integer[] _Array) {
	return _Array;
}

declare Boolean MapChanged;

Void CheckMapChange() {
    if (Map != Null && Map.MapInfo.MapUid != G_PreviousMapUid) {
        G_PreviousMapUid = Map.MapInfo.MapUid;
        MapChanged = True;
    } else {
        MapChanged = False;
    }
}

// settings and stuff from angelscript
declare Text CurrentDateText;
declare Boolean SetCurrentDateText;
declare Text MapNameSafe;
declare Boolean SetMapNameSafe;

Void CheckIncoming() {
    declare Text[][] MLHook_Inbound_AutosaveGhosts for ClientUI;
    foreach (Event in MLHook_Inbound_AutosaveGhosts) {
        if (Event.count < 2) {
            MLHookLog("Skipped unknown incoming event: " ^ Event);
            continue;
        } else if (Event[0] == "CurrentDateText") {
            CurrentDateText = Event[1];
            SetCurrentDateText = True;
        } else if (Event[0] == "MapNameSafe") {
            MapNameSafe = Event[1];
            SetMapNameSafe = True;
        } else {
            MLHookLog("Skipped unknown incoming event: " ^ Event);
            continue;
        }
        MLHookLog("Processed Incoming Event: "^Event[0]);
    }
    MLHook_Inbound_AutosaveGhosts = [];
}

Text GetGhostFileName(CGhost Ghost) {
    declare Text Name = Ghost.Nickname;
    declare Integer GTime = Ghost.Result.Time;
    declare Text TheDate = System.CurrentLocalDateText;
    TheDate = CurrentDateText;
    declare Text MapName = MapNameSafe;
    return "AutosavedGhosts\\" ^ MapName ^ "\\" ^ TheDate ^ "-" ^ MapName ^ "-" ^ Name ^ "-" ^ GTime ^ "ms.Replay.gbx";
}

declare Boolean[Ident] SeenGhosts;
declare Integer[][][Integer] SeenTimes;
declare Integer NbLastSeen;

// will only return true for a ghost the first time it is seen
Boolean ShouldSaveGhost(CGhost Ghost) {
    if (SeenGhosts.existskey(Ghost.Id)) return False; // we've seen this ghost
    SeenGhosts[Ghost.Id] = True; // this should act to help quickly filter this ghost out from consideration again
    if (Ghost.Nickname != LocalUser.Name) return False; // only save the local user's ghosts; and not 'Personal Best' (b/c they're already saved)
    if (!SeenTimes.existskey(Ghost.Result.Time)) return True; // we don't have this time
    declare Integer[] GhostCPs = ToScriptArray(Ghost.Result.Checkpoints);
    foreach (CpTimes in SeenTimes[Ghost.Result.Time]) { // inside the for loop we'll return if we find a reason to not save this ghost
        if (CpTimes.count != GhostCPs.count) continue; // CPs differ so can't be the same
        declare Boolean IsIdentical = True;
        for (i, 0, CpTimes.count) {
            if (CpTimes[i] != GhostCPs[i]) { // if CP times differ, we'll always hit this
                IsIdentical = False; // so the ghosts differ
                break;
            }
        }
        if (IsIdentical) return False; // if we find a match, return
    }
    return True; // if we get here, we haven't seen this ghost before
}

Void RecordSeen(CGhost Ghost) {
    SeenGhosts[Ghost.Id] = True;
    if (!SeenTimes.existskey(Ghost.Result.Time)) {
        SeenTimes[Ghost.Result.Time] = [];
    }
    SeenTimes[Ghost.Result.Time].add(ToScriptArray(Ghost.Result.Checkpoints));
}

Void CheckGhostsCPData() {
    // wait for current date and map name from AS before saving ghosts.
    if (!SetCurrentDateText || !SetMapNameSafe) return;

    // if (DataFileMgr == Null) return;
    // if (DataFileMgr.Ghosts == Null) return;
    declare Integer NbGhosts = DataFileMgr.Ghosts.count;
    if (NbGhosts == NbLastSeen) { return; }
    MLHookLog("DataFileMgr.Ghosts found " ^ (NbGhosts - NbLastSeen) ^ " new ghosts.");
    NbLastSeen = NbGhosts;
    declare CGhost[] GhostsToSave;
    foreach (Ghost in DataFileMgr.Ghosts) {
        if (ShouldSaveGhost(Ghost)) {
            RecordSeen(Ghost);
            GhostsToSave.add(Ghost);
        }
    }
    foreach (Ghost in GhostsToSave) {
        DataFileMgr.Replay_Save(GetGhostFileName(Ghost), Map, Ghost);
    }
}

Void ResetGhostsState() {
    NbLastSeen = 0;
    SeenGhosts.clear();
    SeenTimes.clear();
    SetMapNameSafe = False;
    SetCurrentDateText = False;
}

Void OnMapChange() {
    ResetGhostsState();
}


main() {
    declare Integer LoopCounter = 0;
    MLHookLog("Starting AutosaveGhosts Feed");
    while (True) {
        yield;
        CheckGhostsCPData();
        CheckMapChange();
        if (MapChanged) OnMapChange();
        LoopCounter += 1;
        if (LoopCounter > 120 && LoopCounter % 60 == 0) {
        }
        if (LoopCounter % 60 == 2) {
            CheckIncoming();
        }
    }
}
""";