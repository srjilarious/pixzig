// zig fmt: off
const std = @import("std");
const PixzigEngine = @import("./pixzig.zig").PixzigEngine;
const comp = @import("comp.zig");

pub fn GameStateMgr(comptime StateKeysType: type, comptime States: []const type) type {


    // Contrain the state enum keys to be the same size as the provided states.
    const numStates = comp.numEnumFields(StateKeysType);
    // std.debug.print("num States: {}\n", .{numStates});
    // std.debug.print("num states in list: {}\n", .{States.len});
    if(numStates != States.len) {
    //     @compileLog(numStates);
    //     @compileLog(states.len);
    //     @compileLog(states[0]);
    //     @compileLog(states[1]);
        @compileError("Number of states in keys enum and provided list must match!");
    }

    // Generate the GameState Manager
    return struct {
        currState: StateKeysType,
        states: []*anyopaque,

        pub fn init(states: []*anyopaque) @This() {
            
            // const enumTypeInfo = @typeInfo(StateKeysType);

            return .{
                .currState = @enumFromInt(0),
                .states = states
            };
        }

        pub fn setCurrState(self: *@This(), state: StateKeysType) void {
            const oldState = self.currState;
            self.currState = state;
            
            const oldStateIdx = @intFromEnum(oldState);
            inline for(0..States.len) |idx| {
                if(oldStateIdx == idx) {
                    const stateType = States[idx];
                    if(@hasDecl(stateType, "deactivate")) {
                        const statePtr: *stateType = @ptrCast(self.states[oldStateIdx]);
                        statePtr.deactivate();
                    }
                }
            }

            const stateIdx = @intFromEnum(self.currState);
            inline for(0..States.len) |idx| {
                if(stateIdx == idx) {
                    const stateType = States[idx];
                    if(@hasDecl(stateType, "activate")) {
                        const statePtr: *stateType = @ptrCast(self.states[stateIdx]);
                        statePtr.activate();
                    }
                }
            }
        }

        pub fn update(self: *@This(), eng: *PixzigEngine, deltaUs: f64) bool {
            const stateIdx = @intFromEnum(self.currState);
            inline for(0..States.len) |idx| {
                if(stateIdx == idx) {
                    const stateType = States[idx];
                    const statePtr: *stateType = @ptrCast(self.states[stateIdx]);
                    return statePtr.update(eng, deltaUs);
                }
            }
            return false;
        }

        pub fn render(self: *@This(), eng: *PixzigEngine) void {
            const stateIdx = @intFromEnum(self.currState);
            inline for(0..States.len) |idx| {
                if(stateIdx == idx) {
                    const stateType = States[idx];
                    const statePtr: *stateType = @ptrCast(self.states[stateIdx]);
                    return statePtr.render(eng);
                }
            }
        }
    };
}

