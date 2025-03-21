const std = @import("std");
const pixzig = @import("pixzig");

const GameStateMgr = pixzig.gamestate.GameStateMgr;

pub const EngOptions = pixzig.PixzigEngineOptions{};
pub const Engine = pixzig.PixzigEngine(EngOptions);

pub const AppStates = enum {
    AtlasState,
    AnimationState,
    //StateC
};

pub const SpritezDataBackup: []const u8 = "spriter.autosave.json";

pub const AppEvents = enum {
    AtlasLoaded,
};
