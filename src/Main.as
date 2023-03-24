const string PageUID = "AutosaveGhosts";
uint g_numSaved = 0;
bool permissionsOkay = false;

void Main() {
    CheckRequiredPermissions();
    MLHook::RequireVersionApi('0.3.2');
    @hook = AutosaveGhostEvents();
    startnew(InitCoro);
}

void CheckRequiredPermissions() {
    permissionsOkay = Permissions::CreateLocalReplay()
        && Permissions::PlayAgainstReplay()
        && Permissions::OpenReplayEditor();
    if (!permissionsOkay) {
        NotifyWarn("You appear not to have club access.\n\nThis plugin won't work, sorry :(.");
        while(true) { sleep(10000); } // do nothing forever
    }
}

void OnDestroyed() { _Unload(); }
void OnDisabled() { _Unload(); }
void _Unload() {
    trace('_Unload, unloading hooks and removing injected ML');
    // MLHook::UnregisterMLHooksAndRemoveInjectedML();
    MLHook::UnregisterMLHookFromAll(hook);
    MLHook::RemoveInjectedMLFromPlayground(PageUID);
}

AutosaveGhostEvents@ hook = null;
void InitCoro() {
    if (!permissionsOkay) return;
    // MLHook::RegisterMLHook(hook);
    MLHook::RegisterMLHook(hook, PageUID + "_SavedGhost");
    sleep(50);
    // ml load
    MLHook::InjectManialinkToPlayground(PageUID, AUTOSAVEGHOSTS_SCRIPT_TXT, true);
    startnew(MainCoro);
    sleep(200);
    UpdateAllMLVariables(); // send stuff to ML in case we're loading while in a map; but wait a few frames
}

void MainCoro() {
    if (!permissionsOkay) return;
    startnew(WatchForValidationReplays);
    while (true) {
        yield();
        if (lastMap != CurrentMap) {
            lastMap = CurrentMap;
            OnMapChange();
        }
    }
}

void WatchForValidationReplays() {
    while (true) {
        yield();
        if (!S_SaveValidationReplays || !S_AutosaveActive) continue;
        // check for editor too b/c we only care about validation replays here
        auto editor = cast<CGameCtnEditorFree>(GetApp().Editor);
        auto pgScript = cast<CSmArenaRulesMode>(GetApp().PlaygroundScript);
        if (editor is null || pgScript is null) continue;
        CheckForNewGhosts(pgScript.DataFileMgr);
    }
}

dictionary seenValidationGhosts;
uint lastNbValidationGhosts;
void CheckForNewGhosts(CGameDataFileManagerScript@ dfm) {
    if (lastNbValidationGhosts == dfm.Ghosts.Length) return;
    lastNbValidationGhosts = dfm.Ghosts.Length;
    trace('nb validation ghosts: ' + lastNbValidationGhosts);
    CGameGhostScript@[] toSave;
    for (uint i = 0; i < dfm.Ghosts.Length; i++) {
        auto ghost = dfm.Ghosts[i];
        if (seenValidationGhosts.Exists(ghost.IdName)) continue;
        seenValidationGhosts[ghost.IdName] = true;
        auto time = ghost.Result.Time;
        if (seenValidationGhosts.Exists('time:' + time)) continue;
        seenValidationGhosts['time:' + time] = true;
        toSave.InsertLast(ghost);
    }
    for (uint i = 0; i < toSave.Length; i++) {
        auto ghost = toSave[i];
        auto savePath = GetValidationGhostFileName(ghost);
        dfm.Replay_Save(savePath, GetApp().RootMap, ghost);
        g_numSaved++;
        NotifySaved(savePath);
        yield();
    }
}

const string GetValidationGhostFileName(CGameGhostScript@ ghost) {
    string name = StripFormatCodes(ghost.Nickname);
    auto time = ghost.Result.Time;
    auto date = GetApp().PlaygroundScript.System.CurrentLocalDateText.Replace("/", "-").Replace(":", "-");
    auto mapName = StripFormatCodes(GetApp().RootMap.MapInfo.Name);
    return "AutosavedGhosts\\" + mapName + "-validation\\" + date + "-" + mapName + "-" + name + "-" + time + "ms.Replay.gbx";
}

void OnMapChange() {
    startnew(UpdateAllMLVariables);
}

void UpdateAllMLVariables() {
    UpdateMLAutosaveActive();
}

void ToggleAutosaveActive() {
    S_AutosaveActive = !S_AutosaveActive;
    UpdateMLAutosaveActive();
}

// crucially: used in UpdateMLAutosaveActive
bool get_AutosaveCurrentlyActive() {
    if (!S_AutosaveActive) return false;
    if (S_DisableForLocal && GetApp().PlaygroundScript !is null) return false;
    auto si = cast<CTrackManiaNetworkServerInfo>(GetApp().Network.ServerInfo);
    // don't save if we're in an archivist game mode
    if (si is null || si.CurGameModeStr.Contains("_Archivist_")) return false;
    return true;
}

void UpdateMLAutosaveActive() {
    MLHook::Queue_MessageManialinkPlayground(PageUID, {"AutosaveActive", AutosaveCurrentlyActive ? "True" : "False"});
}

void ForceSaveAllGhosts() {
    NotifyForceSave();
    MLHook::Queue_MessageManialinkPlayground(PageUID, {"ResetAndSaveAll"});
    UpdateAllMLVariables();
}

/* Hook Outgoing Notification Events */
class AutosaveGhostEvents : MLHook::HookMLEventsByType {
    AutosaveGhostEvents() {
        super(PageUID);
        startnew(CoroutineFunc(this.MainCoro));
    }

    MLHook::PendingEvent@[] pending;
    void MainCoro() {
        while (true) {
            yield();
            while (pending.Length > 0) {
                ProcessEvent(pending[pending.Length - 1]);
                pending.RemoveLast();
            }
        }
    }

    void OnEvent(MLHook::PendingEvent@ event) override {
        pending.InsertLast(event);
    }

    void ProcessEvent(MLHook::PendingEvent@ event) {
        if (event.type.EndsWith("SavedGhost")) {
            OnSavedGhost(event);
        }
    }

    void OnSavedGhost(MLHook::PendingEvent@ event) {
        g_numSaved++;
        if (event.data.Length < 0) {
            warn("OnSavedGhost didn't get a file name!");
        } else {
            NotifySaved(event.data[0]);
        }
    }

    // void OnSavedGhost(MLHook::PendingEvent@ event) {
    // }
}

void NotifySaved(const string &in filename) {
    string msg = "Saved ghost and replay: " + filename;
    UI::ShowNotification(Meta::ExecutingPlugin().Name, msg, vec4(.1, .6, .3, .3), 7500);
    trace(msg);
}
void NotifyForceSave() {
    string msg = "Force-saving all of your ghosts (if none show up, there probably are none atm)";
    UI::ShowNotification(Meta::ExecutingPlugin().Name, msg, vec4(.1, .6, .3, .3), 7500);
    trace(msg);
}

void NotifyWarn(const string &in msg) {
    UI::ShowNotification(Meta::ExecutingPlugin().Name, msg, vec4(1, .5, .1, .5), 10000);
    warn(msg);
}


/** Called when a setting in the settings panel was changed. */
void OnSettingsChanged() {
    if (!permissionsOkay) return;
    UpdateAllMLVariables();
}

const string get_HotkeyStr() {
    return S_HotkeyEnabled ? tostring(S_Hotkey) : "";
}

bool i_shiftKeyDown = false;
/** Called whenever a key is pressed on the keyboard. See the documentation for the [`VirtualKey` enum](https://openplanet.dev/docs/api/global/VirtualKey). */
UI::InputBlocking OnKeyPress(bool down, VirtualKey key) {
    if (!permissionsOkay) return UI::InputBlocking::DoNothing;
    if (key == VirtualKey::Shift) i_shiftKeyDown = down;
    if (down) {
        if (S_HotkeyEnabled && key == S_Hotkey) {
            ToggleAutosaveActive();
        }
    }
    return UI::InputBlocking::DoNothing;
}

void RenderInterface() {
}

void RenderMenu() {
    if (!permissionsOkay) return;
    if (UI::MenuItem("\\$f22" + Icons::Circle + "\\$z Autosave Ghosts", HotkeyStr, S_AutosaveActive)) {
        ToggleAutosaveActive();
    }
}

bool isMenuMainHovered = false;
/** Render function called every frame intended only for menu items in the main menu of the `UI`.*/
void RenderMenuMain() {
    if (!permissionsOkay) return;
    isMenuMainHovered = false;
    bool shouldRender = S_MenuBarQuickToggleOff && S_AutosaveActive || S_MenuBarQuickToggleOn && !S_AutosaveActive;
    if (!shouldRender) return;

	string label, recColor, labelColor;
	if (Time::Stamp % 2 == 1 && S_OscillateColors) {
		recColor = "\\$822";
		labelColor = "\\$666";
	} else {
		recColor = "\\$f22";
		labelColor = "\\$z";
	}

	if (S_MenuBarFloatOnRight) {
		label = S_AutosaveActive
			? (recColor + Icons::Circle + labelColor + " REC (" + g_numSaved + ")")
			: ("\\$dd3" + Icons::Pause + " REC");
	} else {
		label = S_AutosaveActive
			? ("\\$f22" + Icons::Circle + "\\$z Autosaving Ghosts (" + g_numSaved + ")")
			: ("\\$dd3" + Icons::Pause + "\\$z Autosave Ghosts");
	}

	auto pos = UI::GetCursorPos();
	if (S_MenuBarFloatOnRight) {
	    auto textSize = Draw::MeasureString(label);
		UI::SetCursorPos(vec2(UI::GetWindowSize().x - textSize.x - S_MenuBarFloatOffset - UI::GetStyleVarVec2(UI::StyleVar::WindowPadding).x * 1.5, pos.y));
	}

	bool wasClicked = UI::MenuItem(label, HotkeyStr);

	if (S_MenuBarFloatOnRight) {
		UI::SetCursorPos(pos);
	}

    string hotkeyExtra = S_HotkeyEnabled ? "\n\\$bbbHotkey: " + HotkeyStr + "\\$z" : "";
    string mainTooltip = (S_AutosaveActive ? "Click to disable autosaving new ghosts.\nShift click to force-save a replay of all current personal ghosts." : "Click to start autosaving new ghosts.");
    AddSimpleTooltip(mainTooltip + hotkeyExtra);
    if (wasClicked && S_AutosaveActive && i_shiftKeyDown) {
        startnew(ForceSaveAllGhosts);
    } else if (wasClicked && !i_shiftKeyDown) {
        ToggleAutosaveActive();
    }
}

string lastMap = "";
string get_CurrentMap() {
    auto map = GetApp().RootMap;
    if (map is null) return "";
    // return map.EdChallengeId;
    return map.MapInfo.MapUid;
}

string get_MapNameSafe() {
    auto map = GetApp().RootMap;
    if (map is null) return "";
    return StripFormatCodes(map.MapName);
}

string get_CurrentDateText() {
    auto mpsapi = cast<CGameManiaPlanet>(GetApp()).ManiaPlanetScriptAPI;
    return mpsapi.CurrentLocalDateText.Replace("/", "-").Replace(":", "-");
}

/*

settings

*/

[Setting category="Autosave Ghosts" name="Autosave Active?" description="While active, this plugin will autosave replays. When not active, it will sit in the background, biding its time, waiting for you to reactivate it."]
bool S_AutosaveActive = true;

[Setting category="Autosave Ghosts" name="Autosave Validation Replays?" description="When validating a map, validation replays will be automatically saved."]
bool S_SaveValidationReplays = true;

[Setting category="Autosave Ghosts" name="MenuBar Quick Toggle Off" description="Show a button in the main menu bar to quickly toggle autosaving off (stop saving replays)."]
bool S_MenuBarQuickToggleOff = true;

[Setting category="Autosave Ghosts" name="MenuBar Quick Toggle On" description="Show a button in the main menu bar to quickly toggle autosaving on (start saving replays)."]
bool S_MenuBarQuickToggleOn = false;

[Setting category="Autosave Ghosts" name="Compact MenuBar" description="Show the menubar toggle on the right-hand side of the Overlay. You will need to manually adjust the offset to accomodate other plugins (like Clock)"]
bool S_MenuBarFloatOnRight = false;

[Setting category="Autosave Ghosts" drag name="Compact MenuBar Blink (.5Hz)" description="If compact MenuBar is enabled, the MenuBar item will darken and lighten on a .5 Hz cycle. No effect if compact MenuBar is disabled."]
bool S_OscillateColors = true;

[Setting category="Autosave Ghosts" drag min=0 max=3000 name="Compact MenuBar Offset" description="How far over to put the recording indicator. A value of 200 works well for the Clock plugin."]
int S_MenuBarFloatOffset = 200;

[Setting category="Autosave Ghosts" name="Disable for Local Runs" description="When checked, replays will not be autosaved for local runs."]
bool S_DisableForLocal = false;

[Setting category="Autosave Ghosts" name="Hotkey Enabled" description="The hotkey will only work if this is checked."]
bool S_HotkeyEnabled = true;

[Setting category="Autosave Ghosts" name="Hotkey" description="Hotkey to toggle saving or not."]
VirtualKey S_Hotkey = VirtualKey::F7;
